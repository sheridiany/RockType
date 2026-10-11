#!/bin/bash
# Compile the actual GPL input-method sources only into isolated test executables.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/roarkt-ime-checks.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
xcrun swiftc -import-objc-header "$root/Shared/XPCProtocol/include/RoarkTTranslationXPCProtocol.h" \
  "$root/Core/Identifiers.swift" "$root/Core/Shortcuts.swift" "$root/Core/Translation/DynamicTranslationProtocol.swift" \
  "$root/InputMethod/sources/RoarkTTranslationClient.swift" \
  "$root/InputMethod/sources/RoarkTCandidateTranslationSession.swift" \
  "$root/Tests/InputMethodTests/SessionChecks.swift" -o "$temporary/session"
"$temporary/session"
xcrun swiftc -import-objc-header "$root/InputMethod/librime/src/rime/key_table.h" \
  -I "$root/InputMethod/librime/src" -I "$root/InputMethod/librime/include" \
  "$root/InputMethod/sources/MacOSKeyCodes.swift" \
  "$root/Tests/InputMethodTests/ModifierChecks.swift" -o "$temporary/modifiers"
"$temporary/modifiers"
xcrun swiftc -swift-version 6 -import-objc-header "$root/Tests/InputMethodTests/PanelBridge.h" \
  -I "$root/InputMethod/librime/src" \
  "$root/Core/Identifiers.swift" "$root/Core/Shortcuts.swift" "$root/Core/Translation/DynamicTranslationProtocol.swift" \
  "$root/InputMethod/sources/BridgingFunctions.swift" \
  "$root/InputMethod/sources/SquirrelConfig.swift" "$root/InputMethod/sources/SquirrelTheme.swift" \
  "$root/InputMethod/sources/SquirrelView.swift" \
  "$root/InputMethod/sources/RoarkTCandidateTranslationSession.swift" \
  "$root/InputMethod/sources/SquirrelPanel.swift" "$root/InputMethod/sources/RoarkTTranslationPanel.swift" \
  "$root/InputMethod/sources/RoarkTInputModePanel.swift" \
  "$root/InputMethod/sources/RoarkTCandidateLearningMenu.swift" \
  "$root/Tests/InputMethodTests/PanelChecks.swift" \
  "$root/InputMethod/lib/librime.1.dylib" -Xlinker -rpath -Xlinker "$root/InputMethod/lib" \
  -o "$temporary/panels"
"$temporary/panels" "$root/.build/ime-evidence" "$root/InputMethod/data/squirrel.yaml"
# Menu icon evidence uses the same registered SwiftPM tests as scripts/test.sh.
if [[ "${ROARKT_IME_FROM_SWIFTPM:-0}" != 1 ]]; then
  swift test --package-path "$root" --filter 'MenuIconTests|voiceHUD|recordingClock'
fi
