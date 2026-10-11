#!/usr/bin/env swift
// Prepare a disposable C-derived D resource directory; never access user profiles.
import Foundation
let args = CommandLine.arguments
precondition(args.count == 5, "usage: prepare-trial.swift resource-directory bgw|bgc max-length min-length")
let directory = args[1]
precondition(["bgw", "bgc"].contains(args[2]))
func edit(_ name: String, _ transform: (String) -> String) throws {
    let path = directory + "/" + name
    try transform(String(contentsOfFile: path, encoding: .utf8)).write(toFile: path, atomically: true, encoding: .utf8)
}
try edit("roarkt_ai.dict.yaml") { text in
    let parts = text.components(separatedBy: "...\n")
    let rows = parts[1].components(separatedBy: "\n").map { line in
        var fields = line.components(separatedBy: "\t")
        if !line.hasPrefix("#") { fields[0] = fields[0].applyingTransform(StringTransform("Hant-Hans"), reverse: false)! }
        return fields.joined(separator: "\t")
    }
    return parts[0].replacingOccurrences(of: "# Traditional text matches Luna Pinyin and octagram; tw2s emits simplified text.", with: "# Simplified text for the D experiment.") + "...\n" + rows.joined(separator: "\n")
}
try edit("roarkt_zh.dict.yaml") { $0.replacingOccurrences(of: "  - luna_pinyin", with: "  - roarkt_base") }
for name in ["roarkt.schema.yaml", "roarkt_flypy.schema.yaml"] {
    try edit(name) { $0
        .replacingOccurrences(of: "  - name: simplification\n    reset: 1\n    # 强制启用繁转简，不提供菜单开关。\n", with: "")
        .replacingOccurrences(of: "    - simplifier@simplification\n", with: "")
        .replacingOccurrences(of: "    - lua_filter@*roarkt_simplified_only_filter\n", with: "")
        .replacingOccurrences(of: "after simplification and deduplication", with: "after deduplication")
        .replacingOccurrences(of: "zh-hant-t-essay-bgw", with: "zh-hans-t-essay-" + args[2])
        .replacingOccurrences(of: "collocation_max_length: 5", with: "collocation_max_length: " + args[3])
        .replacingOccurrences(of: "collocation_min_length: 2", with: "collocation_min_length: " + args[4])
        .replacingOccurrences(of: "simplification:\n  option_name: simplification\n  opencc_config: tw2s.json\n  tips: none\n\n", with: "")
    }
}
try FileManager.default.removeItem(atPath: directory + "/lua/roarkt_simplified_only_filter.lua")
