#!/usr/bin/env swift
// Development-only generator. macOS Foundation uses the system ICU Hant-Hans transform.
import Foundation

let args = CommandLine.arguments
precondition(args.count == 5, "usage: simplify-luna.swift luna.dict.yaml essay.txt output.yaml collisions.tsv")
let source = try String(contentsOfFile: args[1], encoding: .utf8)
var preset: [String: Double] = [:]
for line in try String(contentsOfFile: args[2], encoding: .utf8).split(separator: "\n") {
    let fields = line.split(separator: "\t")
    if fields.count == 2 { preset[String(fields[0])] = Double(fields[1]) }
}
let parts = source.components(separatedBy: "...\n")
precondition(parts.count == 2)
var order: [String] = []
var weights: [String: Double] = [:]
var origins: [String: [String]] = [:]
var inputCount = 0
for line in parts[1].split(separator: "\n") where !line.hasPrefix("#") {
    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    precondition(fields.count >= 2 && fields.count <= 3)
    let original = fields[0]
    // ICU retains the gender-specific pronoun 妳; this simplified-only product uses 你.
    let text = original.applyingTransform(StringTransform("Hant-Hans"), reverse: false)!
        .replacingOccurrences(of: "妳", with: "你")
    let key = text + "\t" + fields[1]
    let raw = fields.count == 3 ? fields[2] : ""
    let weight: Double
    if raw.isEmpty || raw.hasSuffix("%") {
        weight = preset[original, default: 0] * (raw.isEmpty ? 1 : Double(raw.dropLast())! / 100)
    } else { weight = Double(raw)! }
    if weights[key] == nil { order.append(key) }
    weights[key, default: 0] += weight
    origins[key, default: []].append(original)
    inputCount += 1
}
let header = parts[0].replacingOccurrences(of: "name: luna_pinyin", with: "name: roarkt_base")
let notice = "# Derived by RockType: macOS ICU Hant-Hans; duplicate text+code weights summed.\n# Relative/omitted weights resolved against the pinned source essay before merging.\n# Manual correction: 妳 → 你. See docs/dictionary-simplification.md.\n"
let rows = order.map { $0 + "\t" + String(format: "%.10g", weights[$0]!) }
try (notice + header + "...\n" + rows.joined(separator: "\n") + "\n").write(toFile: args[3], atomically: true, encoding: .utf8)
let collisions = order.filter { origins[$0]!.count > 1 }.map { $0 + "\t" + origins[$0]!.joined(separator: "|") + "\t" + String(format: "%.10g", weights[$0]!) }
try ("text\tcode\torigins\tweight\n" + collisions.joined(separator: "\n") + "\n").write(toFile: args[4], atomically: true, encoding: .utf8)
print("input=\(inputCount) output=\(order.count) merged=\(inputCount-order.count) collision_keys=\(collisions.count)")
