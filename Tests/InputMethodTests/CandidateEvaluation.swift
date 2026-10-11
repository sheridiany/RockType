// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@_silgen_name("_Z23rime_require_module_luav")
func requireLua()

/// Factory-only, no commits: samples cannot train or influence later samples.
@main
struct CandidateEvaluation {
  static func main() throws {
    let args = CommandLine.arguments
    guard args.count == 7 else { fatalError("shared user build fixture schema output required") }
    let lines = try String(contentsOfFile: args[4], encoding: .utf8).split(separator: "\n")
    requireLua()
    let api = rime_get_api_stdbool().pointee
    var traits = RimeTraits.rimeStructInit()
    traits.setCString(args[1], to: \.shared_data_dir)
    traits.setCString(args[2], to: \.user_data_dir)
    traits.setCString(args[3], to: \.staging_dir)
    traits.setCString(args[3], to: \.prebuilt_data_dir)
    traits.setCString(args[2], to: \.log_dir)
    traits.setCString("rime.roarkt.tests", to: \.app_name)
    traits.min_log_level = 3
    api.setup(&traits)
    api.initialize(&traits)
    defer { api.finalize() }
    var counts: [String: (hits: Int, total: Int)] = [:]
    var timings: [Double] = []
    var report = "category\tcode\texpected\tactual\thit\n"
    for line in lines where !line.hasPrefix("#") {
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard fields.count == 3, !fields[1].isEmpty, !fields[2].isEmpty else { fatalError("invalid fixture row") }
      let session = api.create_session()
      guard session != 0, api.select_schema(session, args[5]) else { fatalError("schema unavailable") }
      api.set_option(session, "ascii_mode", false)
      api.set_property(session, "roarkt_translation_presentation", "panel")
      for byte in fields[1].utf8 {
        let start = DispatchTime.now().uptimeNanoseconds
        _ = api.process_key(session, Int32(byte), 0)
        _ = api.simulate_key_sequence(session, "{F19}")
        var context = RimeContext_stdbool.rimeStructInit()
        if api.get_context(session, &context) { _ = api.free_context(&context) }
        timings.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
      }
      var context = RimeContext_stdbool.rimeStructInit()
      guard api.get_context(session, &context) else { fatalError("missing context") }
      let actual = context.menu.num_candidates > 0 ? String(cString: context.menu.candidates[0].text) : ""
      _ = api.free_context(&context)
      api.clear_composition(session)
      _ = api.destroy_session(session)
      let hit = actual == fields[2]
      for key in [fields[0], "total"] {
        var count = counts[key, default: (0, 0)]
        count.total += 1
        count.hits += hit ? 1 : 0
        counts[key] = count
      }
      report += fields.joined(separator: "\t") + "\t\(actual)\t\(hit ? 1 : 0)\n"
    }
    guard !counts.isEmpty else { fatalError("empty evaluation") }
    try report.write(toFile: args[6], atomically: true, encoding: .utf8)
    for key in counts.keys.sorted() {
      let count = counts[key]!
      print(String(format: "%@\t%d/%d\t%.2f%%", key, count.hits, count.total, 100 * Double(count.hits) / Double(count.total)))
    }
    timings.sort()
    print(String(format: "key_refresh_p95_ms\t%.3f\tkeys=%d", timings[Int(ceil(Double(timings.count) * 0.95)) - 1], timings.count))
  }
}
