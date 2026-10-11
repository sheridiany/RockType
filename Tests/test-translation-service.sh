#!/bin/zsh
# T2 owns Tests/, but not the root Package.swift or scripts/test.sh.
# Exercise the real service sources in an isolated SPM package until integration
# adds TranslationServiceTests to the root manifest.
set -euo pipefail
repo_dir=${0:A:h:h}
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/roarkt-translation-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
ln -s "$repo_dir/Core" "$test_dir/Core"
ln -s "$repo_dir/Shared" "$test_dir/Shared"
ln -s "$repo_dir/Services/TranslationService" "$test_dir/Service"
ln -s "$repo_dir/Tests/TranslationServiceTests" "$test_dir/ServiceTests"
cat > "$test_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "RoarkTTranslationTests", platforms: [.macOS(.v14)], targets: [
    .target(name: "RoarkTCore", path: "Core"),
    .target(name: "RoarkTXPCProtocol", path: "Shared/XPCProtocol", publicHeadersPath: "include"),
    .executableTarget(name: "RoarkTTranslationService",
        dependencies: ["RoarkTCore", "RoarkTXPCProtocol"], path: "Service"),
    .testTarget(name: "RoarkTTranslationServiceTests",
        dependencies: ["RoarkTTranslationService", "RoarkTCore", "RoarkTXPCProtocol"], path: "ServiceTests"),
])
SWIFT
swift test --package-path "$test_dir"
