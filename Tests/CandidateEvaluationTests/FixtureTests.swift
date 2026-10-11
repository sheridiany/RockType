import Foundation
import Testing

@Test func fixedEvaluationHasUniqueValidInputs() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
  let text = try String(contentsOf: root.appendingPathComponent("InputMethodTests/Fixtures/candidate-eval.tsv"), encoding: .utf8)
  let rows = text.split(separator: "\n").filter { !$0.hasPrefix("#") }
  #expect(rows.count == 200)
  var codes = Set<String>()
  var categories = Set<String>()
  for row in rows {
    let fields = row.split(separator: "\t", omittingEmptySubsequences: false)
    #expect(fields.count == 3)
    guard fields.count == 3 else { continue }
    #expect(fields[1].allSatisfy { $0.isASCII && ($0.isLowercase || $0 == "'") })
    #expect(codes.insert(String(fields[1])).inserted)
    #expect(!fields[2].isEmpty)
    categories.insert(String(fields[0]))
  }
  #expect(categories == ["daily", "ai", "development", "sentence"])
}

@Test func factoryEvaluationRunsAgainstRealLibrime() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let output = FileManager.default.temporaryDirectory.appendingPathComponent("roarkt-eval-test-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: output) }
  let log = output.appendingPathComponent("runner.log")
  FileManager.default.createFile(atPath: log.path, contents: nil)
  let handle = try FileHandle(forWritingTo: log)
  defer { try? handle.close() }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/bash")
  process.arguments = [root.appendingPathComponent("scripts/eval-candidates.sh").path, root.appendingPathComponent("Rime").path, output.path]
  process.standardOutput = handle
  process.standardError = handle
  try process.run()
  process.waitUntilExit()
  #expect(process.terminationStatus == 0)
  guard process.terminationStatus == 0 else { return }
  let results = try String(contentsOf: output.appendingPathComponent("results.tsv"), encoding: .utf8)
  let rows = results.split(separator: "\n").dropFirst()
  #expect(rows.count == 200)
  #expect(rows.filter { $0.hasSuffix("\t1") }.count >= 181)
  #expect(rows.filter { $0.hasPrefix("ai\t") && $0.hasSuffix("\t1") }.count >= 57)
  #expect(rows.filter { $0.hasPrefix("daily\t") && $0.hasSuffix("\t1") }.count >= 78)
  #expect(rows.filter { $0.hasPrefix("development\t") && $0.hasSuffix("\t1") }.count >= 29)
  #expect(rows.filter { $0.hasPrefix("sentence\t") && $0.hasSuffix("\t1") }.count >= 17)
}

@Test func domainDictionaryReadingsAreEncodableAndUnique() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  func dictionaryRows(_ relativePath: String) throws -> [[String]] {
    let text = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    let body = try #require(text.components(separatedBy: "...\n").last)
    return body.split(separator: "\n").filter { !$0.hasPrefix("#") }.map {
      $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    }
  }
  var readings: [Character: Set<String>] = [:]
  for row in try dictionaryRows("InputMethod/data/plum/luna_pinyin.dict.yaml") where row.count >= 2 && row[0].count == 1 {
    readings[row[0].first!, default: []].insert(row[1])
  }
  let presetText = try String(contentsOf: root.appendingPathComponent("InputMethod/data/plum/essay.txt"), encoding: .utf8)
  var preset: [String: Int] = [:]
  for line in presetText.split(separator: "\n") {
    let fields = line.split(separator: "\t")
    if fields.count == 2 { preset[String(fields[0])] = Int(fields[1]) }
  }
  let rows = try dictionaryRows("Rime/roarkt_ai.dict.yaml")
  #expect((800...1500).contains(rows.count))
  var terms = Set<String>()
  var uncodedCount = 0
  for row in rows {
    #expect(row.count == 2 || row.count == 3)
    guard row.count >= 2 else { continue }
    #expect(terms.insert(row[0]).inserted, "duplicate domain term: \(row[0])")
    let inherited = preset[row[0], default: 0]
    let weight = row[1] == "100%" ? inherited : (Int(row[1]) ?? 0)
    #expect(weight > 0)
    #expect(weight >= inherited, "domain entry must not demote its existing preset frequency: \(row[0])")
    for character in row[0] {
      #expect(readings[character] != nil, "character cannot auto-encode: \(character)")
    }
    if row.count == 3 {
      let syllables = row[2].split(separator: " ").map(String.init)
      #expect(syllables.count == row[0].count, "reading length: \(row[0])")
      for (character, syllable) in zip(row[0], syllables) {
        #expect(readings[character, default: []].contains(syllable), "unsupported reading: \(row[0]) \(syllable)")
      }
    } else { uncodedCount += 1 }
  }
  #expect(uncodedCount > rows.count / 2, "ordinary terms should use the shared Rime character table")
}
