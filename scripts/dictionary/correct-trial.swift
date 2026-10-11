#!/usr/bin/env swift
// Final W-6 trial: semantic corrections plus optional original-frequency floor.
import Foundation
let args = CommandLine.arguments
precondition(args.count == 4, "usage: correct-trial.swift trial-directory source-plum-directory semantics|floor")
let trial = args[1], source = args[2], mode = args[3]
precondition(["semantics", "floor"].contains(mode))
func read(_ path: String) throws -> String { try String(contentsOfFile: path, encoding: .utf8) }
func write(_ text: String, _ path: String) throws { try text.write(toFile: path, atomically: true, encoding: .utf8) }
// Hant-Hans is contextual. Only override ambiguities whose reading/meaning is known.
func simplify(_ text: String, code: String? = nil) -> String {
    var result = Array(text.applyingTransform(StringTransform("Hant-Hans"), reverse: false)!.replacingOccurrences(of: "妳", with: "你"))
    let original = Array(text), syllables = code?.split(separator: " ").map(String.init)
    if let syllables, syllables.count == original.count, result.count == original.count {
        for index in original.indices {
            if original[index] == "著" && syllables[index] == "zhu" { result[index] = "著" }
            if original[index] == "乾" && syllables[index] == "qian" { result[index] = "乾" }
            if original[index] == "藉" && syllables[index] == "ji" { result[index] = "藉" }
        }
    }
    var output = String(result)
    if text == "瞭" { output = "瞭" } // Both 了 and 瞭 must remain encodable.
    for (from, to) in [("乾坤", "乾坤"), ("乾隆", "乾隆"), ("瞭望", "瞭望"), ("慰藉", "慰藉"), ("蘊藉", "蕴藉"), ("藉口", "借口"), ("藉助", "借助"), ("憑藉", "凭借")] where text.contains(from) {
        let converted = from.applyingTransform(StringTransform("Hant-Hans"), reverse: false)!
        output = output.replacingOccurrences(of: converted, with: to)
    }
    return output
}
var provenance = ["source\toriginal\tcode\tsimplified"]
var oldPreset: [String: Double] = [:]
for line in try read(source + "/essay.txt").split(separator: "\n") {
    let f = line.split(separator: "\t")
    if f.count == 2 { oldPreset[String(f[0])] = Double(f[1]) }
}
let luna = try read(source + "/luna_pinyin.dict.yaml").components(separatedBy: "...\n")
var order: [String] = [], weights: [String: Double] = [:], corrected: [String] = []
for line in luna[1].split(separator: "\n") where !line.hasPrefix("#") {
    let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    let word = simplify(f[0], code: f[1]), key = word + "\t" + f[1]
    provenance.append("luna\t" + f[0] + "\t" + f[1] + "\t" + word)
    let raw = f.count > 2 ? f[2] : ""
    let weight = raw.isEmpty || raw.hasSuffix("%") ? oldPreset[f[0], default: 0] * (raw.isEmpty ? 1 : Double(raw.dropLast())! / 100) : Double(raw)!
    if weights[key] == nil { order.append(key) }
    weights[key, default: 0] += weight
    let automatic = f[0].applyingTransform(StringTransform("Hant-Hans"), reverse: false)!
    if word != automatic { corrected.append(f[0] + "\t" + f[1] + "\t" + automatic + "\t" + word) }
}
let header = "# RockType derivative: ICU Hant-Hans with reading-aware semantic corrections.\n# Duplicate text+code weights summed; see docs/dictionary-simplification.md.\n" + luna[0].replacingOccurrences(of: "name: luna_pinyin", with: "name: roarkt_base")
try write(header + "...\n" + order.map { $0 + "\t" + String(format: "%.10g", weights[$0]!) }.joined(separator: "\n") + "\n", trial + "/Rime/roarkt_base.dict.yaml")
try write("original\tcode\tICU\tcorrected\n" + corrected.joined(separator: "\n") + "\n", trial + "/corrections.tsv")
// Normalize remaining traditional entries in upstream essay; duplicates take max,
// because the two inputs are frequency estimates rather than additive corpora.
var preset: [String: Double] = [:]
for line in try read(trial + "/Rime/essay.txt").split(separator: "\n") {
    let f = line.split(separator: "\t")
    if f.count == 2 {
        let key = simplify(String(f[0]))
        provenance.append("essay-simp\t" + f[0] + "\t\t" + key)
        preset[key] = max(preset[key, default: 0], Double(f[1])!)
    }
}
if mode == "floor" {
    for (word, weight) in oldPreset {
        let key = simplify(word)
        provenance.append("essay-C\t" + word + "\t\t" + key)
        preset[key] = max(preset[key, default: 0], weight)
    }
}
try write(preset.keys.sorted().map { $0 + "\t" + String(format: "%.10g", preset[$0]!) }.joined(separator: "\n") + "\n", trial + "/Rime/essay.txt")
// Resolve inherited weights against the new preset. Missing inherited terms retain
// authored domain priority 800; no term demotes an existing preset frequency.
let aiPath = trial + "/Rime/roarkt_ai.dict.yaml"
let ai = try read(aiPath).components(separatedBy: "...\n")
let rows = ai[1].components(separatedBy: "\n").map { line -> String in
    if line.isEmpty || line.hasPrefix("#") { return line }
    var f = line.components(separatedBy: "\t")
    let frequency = preset[f[0], default: 0]
    f[1] = frequency >= 800 ? "100%" : "800"
    return f.joined(separator: "\t")
}
let aiHeader = ai[0].components(separatedBy: "\n").filter { !$0.hasPrefix("# 100%") && !$0.hasPrefix("# Other 822") }.joined(separator: "\n")
try write("# Inherit simplified preset frequency when >=800; otherwise authored priority 800.\n" + aiHeader + "...\n" + rows.joined(separator: "\n"), aiPath)
try write(provenance[0] + "\n" + provenance.dropFirst().sorted().joined(separator: "\n") + "\n", trial + "/origins.tsv")
print("mode=\(mode) base=\(order.count) corrections=\(corrected.count) preset=\(preset.count)")
