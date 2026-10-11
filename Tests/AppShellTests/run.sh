#!/bin/bash
# Compile shell checks without changing the shared Package.swift owned by S1.
set -euo pipefail
cd "$(dirname "$0")/../.."
swift build
bin_dir=$(swift build --show-bin-path)
checks_dir=$(mktemp -d /tmp/roarkt-shell-checks.XXXXXX)
trap 'rm -rf "$checks_dir"' EXIT
for check in Tests/AppShellTests/*Checks.swift; do
  sources=(App/Shell/Permissions/PermissionCenter.swift)
  if [[ "$check" == *HotkeyChecks.swift ]]; then
    sources=(App/Shell/Hotkeys/HotkeyCenter.swift)
  fi
  swiftc -swift-version 6 -parse-as-library -I "$bin_dir/Modules" \
    "$bin_dir"/RoarkTCore.build/*.swift.o "$bin_dir"/RoarkTPlatform.build/*.swift.o \
    "${sources[@]}" "$check" -o "$checks_dir/check"
  "$checks_dir/check"
done
