#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../../.." && pwd)
check_dir=$(mktemp -d /tmp/roarkt-text-checks.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
mkdir -p "$check_dir/Tests" "$check_dir/Protocol"
cp -R "$repo/Core" "$check_dir/Core"
cp -R "$repo/Shared/XPCProtocol/" "$check_dir/Protocol/"
for file in "$repo/Services/TranslationService/"*.swift; do
    [[ $(basename "$file") == main.swift ]] || cp "$file" "$check_dir/Tests/"
done
cp "$repo/Services/TranslationService/.checks/TextTranslationTests.swift" "$check_dir/Tests/"
cp "$repo/App/Features/Operations/TextTranslationXPCClient.swift" "$check_dir/Tests/"
cat > "$check_dir/Package.swift" <<MANIFEST
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TextChecks", platforms: [.macOS(.v14)],
 targets: [.target(name: "RoarkTCore", path: "Core"),.target(name: "RoarkTXPCProtocol", path: "Protocol", publicHeadersPath: "include"),
 .testTarget(name: "TextChecks", dependencies: ["RoarkTCore", "RoarkTXPCProtocol"], path: "Tests")])
MANIFEST
swift test --package-path "$check_dir"
