#!/usr/bin/env swift
// Offline variant arbitration. OpenCC tables are evidence, never a runtime filter.
import Foundation
let args = CommandLine.arguments
precondition(args.count == 4, "usage: resolve-variants.swift trial-directory original-essay-simp.txt opencc-dictionary-directory")
let trial = args[1], reference = args[2], tables = args[3]
func read(_ path: String) throws -> String { try String(contentsOfFile: path, encoding: .utf8) }
func write(_ text: String, _ path: String) throws { try text.write(toFile: path, atomically: true, encoding: .utf8) }
func table(_ path: String) throws -> [String: String] {
    var result: [String: String] = [:]
    for line in try read(path).split(separator: "\n") where !line.hasPrefix("#") {
        let f = line.split(separator: "\t")
        if f.count == 2 { result[String(f[0])] = String(f[1].split(separator: " ")[0]) }
    }
    return result
}
let phrases = try table(tables + "/TSPhrases.txt"), characters = try table(tables + "/TSCharacters.txt")
let maxPhrase = phrases.keys.map(\.count).max()!
func canonical(_ word: String) -> String {
    let chars = Array(word)
    var result = "", i = 0
    while i < chars.count {
        var match = false
        let length = min(maxPhrase, chars.count - i)
        if length >= 2 {
            for n in stride(from: length, through: 2, by: -1) {
                if let value = phrases[String(chars[i..<(i+n)])] { result += value; i += n; match = true; break }
            }
        }
        if !match { let ch = String(chars[i]); result += characters[ch] ?? ch; i += 1 }
    }
    return result
}
var referenceFrequency: [String: Double] = [:]
for line in try read(reference).split(separator: "\n") {
    let f = line.split(separator: "\t")
    if f.count == 2 { referenceFrequency[String(f[0])] = Double(f[1]) }
}
let basePath = trial + "/Rime/roarkt_base.dict.yaml"
let base = try read(basePath).components(separatedBy: "...\n")
var readings: [Character: Set<String>] = [:]
for line in base[1].split(separator: "\n") {
    let f = line.split(separator: "\t")
    if f.count >= 2 && f[0].count == 1 { readings[f[0].first!, default: []].insert(String(f[1])) }
}
struct Origin: Hashable { let word: String; let code: String }
var groups: [String: [String: Set<Origin>]] = [:]
var scanned = 0
for line in try read(trial + "/origins.tsv").split(separator: "\n") {
    let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard f.count == 4, ["luna", "essay-C", "essay-simp"].contains(f[0]) else { continue }
    groups[canonical(f[1]), default: [:]][f[3], default: []].insert(Origin(word: f[1], code: f[2]))
    scanned += 1
}
// Require a common actual dictionary reading for each character. A spelling's
// explicit source code takes precedence over the auto-encoding character table.
func codes(_ word: String, _ origins: Set<Origin>) -> [[Set<String>]] {
    let explicit = origins.filter { !$0.code.isEmpty }.sorted {
        $0.code == $1.code ? $0.word < $1.word : $0.code < $1.code
    }.map { $0.code.split(separator: " ").map { Set([String($0)]) } }
    if !explicit.isEmpty { return explicit }
    return [word.map { readings[$0, default: []] }]
}
func sharedCode(_ a: String, _ ao: Set<Origin>, _ b: String, _ bo: Set<Origin>) -> String? {
    for ac in codes(a, ao) { for bc in codes(b, bo) where ac.count == bc.count {
        let common = zip(ac, bc).map { $0.intersection($1).sorted().first }
        if common.allSatisfy({ $0 != nil }) { return common.map { $0! }.joined(separator: " ") }
    } }
    return nil
}
var affected = Set<String>(), examined = 0, eligible = 0
var audit = ["canonical\tcode\tpreferred\tpreferred_reference_frequency\tvariant\tvariant_reference_frequency\torigins\taction"]
for key in groups.keys.sorted() {
    let group = groups[key]!
    guard group.count > 1 else { continue }
    examined += 1
    let words = group.keys.sorted { a,b in
        let af = referenceFrequency[a, default: 0], bf = referenceFrequency[b, default: 0]
        return af == bf ? a < b : af > bf
    }
    // Pairwise matching avoids assuming all homophones are variants. Both source
    // spellings must canonicalize to the same table-backed word first.
    for i in words.indices {
        for j in words.indices where j > i {
            let preferred = words[i], variant = words[j]
            guard let code = sharedCode(preferred, group[preferred]!, variant, group[variant]!) else { continue }
            eligible += 1
            let high = referenceFrequency[preferred, default: 0], low = referenceFrequency[variant, default: 0]
            let demote = high > 0 && (low == 0 || low <= high * 0.01)
            if demote { affected.insert(variant) }
            let origins = group[variant]!.map(\.word).sorted().joined(separator: "|")
            audit.append([key, code, preferred, String(high), variant, String(low), origins, demote ? "cap-at-1" : "keep"].joined(separator: "\t"))
        }
    }
}
var baseChanged = 0, essayChanged = 0, aiChanged = 0
let baseRows = base[1].components(separatedBy: "\n").map { line -> String in
    var f = line.components(separatedBy: "\t")
    if f.count >= 3 && affected.contains(f[0]), let weight = Double(f[2]), weight > 1 { f[2] = "1"; baseChanged += 1 }
    return f.joined(separator: "\t")
}
try write(base[0] + "...\n" + baseRows.joined(separator: "\n"), basePath)
let essayPath = trial + "/Rime/essay.txt"
let essayRows = try read(essayPath).components(separatedBy: "\n").map { line -> String in
    var f = line.components(separatedBy: "\t")
    if f.count == 2 && affected.contains(f[0]), let weight = Double(f[1]), weight > 1 { f[1] = "1"; essayChanged += 1 }
    return f.joined(separator: "\t")
}
try write(essayRows.joined(separator: "\n"), essayPath)
let aiPath = trial + "/Rime/roarkt_ai.dict.yaml"
let ai = try read(aiPath).components(separatedBy: "...\n")
let aiRows = ai[1].components(separatedBy: "\n").map { line -> String in
    var f = line.components(separatedBy: "\t")
    if f.count >= 2 && affected.contains(f[0]) { f[1] = "1"; aiChanged += 1 }
    return f.joined(separator: "\t")
}
try write(ai[0] + "...\n" + aiRows.joined(separator: "\n"), aiPath)
try write(audit.joined(separator: "\n") + "\n", trial + "/variant-audit.tsv")
let summary = "source_rows=\(scanned) canonical_multiform_groups=\(examined) same_reading_pairs=\(eligible) demoted_spellings=\(affected.count) base_rows_changed=\(baseChanged) essay_rows_changed=\(essayChanged) ai_rows_changed=\(aiChanged)"
try write(summary + "\n", trial + "/variant-summary.txt")
print(summary)
