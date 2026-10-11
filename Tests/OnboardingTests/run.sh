#!/bin/zsh
# Standalone S4 tests: Package.swift is owned by S1.
set -euo pipefail
cd "${0:A:h:h:h}"
swift build --product RoarkTApp
bin_dir=$(swift build --show-bin-path)
test_binary=$(mktemp -t roarkt-onboarding-tests)
trap 'rm -f "$test_binary"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  -I "$bin_dir/Modules" -I Shared/XPCProtocol/include \
  -Xcc -fmodule-map-file="$bin_dir/RoarkTXPCProtocol.build/module.modulemap" \
  App/Shell/TranslationServiceClient.swift \
  App/Shell/Onboarding/InputSourceManager.swift \
  Tests/OnboardingTests/OnboardingTests.swift \
  "$bin_dir"/RoarkTCore.build/*.swift.o \
  "$bin_dir/RoarkTXPCProtocol.build/RoarkTXPCProtocol.m.o" \
  -o "$test_binary"
"$test_binary"
