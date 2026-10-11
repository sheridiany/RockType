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
  #expect(rows.filter { $0.hasSuffix("\t1") }.count >= 162)
}
