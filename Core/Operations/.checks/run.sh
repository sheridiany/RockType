#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../../.." && pwd)
check_dir=$(mktemp -d /tmp/roarkt-operation-checks.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
mkdir -p "$check_dir/Tests"
cp "$repo/Core/Operations/.checks/OperationTests.swift" "$check_dir/Tests/"
cp "$repo/App/Features/Operations/RecentResults.swift" "$check_dir/Tests/"
cat > "$check_dir/Package.swift" <<MANIFEST
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "OperationChecks", platforms: [.macOS(.v14)],
 dependencies: [.package(name: "RoarkT", path: "$repo")],
 targets: [.testTarget(name: "OperationChecks", dependencies: [.product(name: "RoarkTCore", package: "RoarkT")], path: "Tests")])
MANIFEST
swift test --package-path "$check_dir"
