#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h:h}
cd "$repo_dir"
identity=${ROARKT_CODESIGN_IDENTITY:-'Developer ID Application: XIAO BIN (DF7J2VBQD8)'}
root=$(mktemp -d /tmp/roarkt-voice-smoke.XXXXXX)
trap 'rm -rf "$root"' EXIT
app="$root/VoiceSmoke.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/XPCServices"
ditto dist/RoarkTVoiceWorker.xpc "$app/Contents/Helpers/RoarkTVoiceWorker.xpc"
ln -s ../Helpers/RoarkTVoiceWorker.xpc "$app/Contents/XPCServices/RoarkTVoiceWorker.xpc"
cp App/Info.plist "$app/Contents/Info.plist"
swiftc -swift-version 6 -target arm64-apple-macos14.0 Core/Identifiers.swift Shared/VoiceWorkerProtocol/VoiceWorkerProtocol.swift \
  Tests/VoiceWorkerSmoke/main.swift Tests/VoiceWorkerSmoke/Evaluation.swift -o "$app/Contents/MacOS/RockType"
codesign --force --options runtime --timestamp=none --sign "$identity" "$app"
codesign --verify --strict --deep "$app"
"$app/Contents/Helpers/RoarkTVoiceWorker.xpc/Contents/MacOS/RoarkTVoiceWorker" --self-test
open -n -g -W "$app" --args --status-file "$root/accepted.status"
[[ -f "$root/accepted.status" && "$(cat "$root/accepted.status")" == 0 ]] || exit 1
if [[ -n "${ROARKT_VOICE_EVALUATION_DIR:-}" ]]; then
  [[ -n "${ROARKT_VOICE_EVALUATION_MODEL:-}" ]] || exit 1
  open -n -g -W "$app" --args --status-file "$root/evaluation.status" \
    --evaluate-dir "$ROARKT_VOICE_EVALUATION_DIR" "$ROARKT_VOICE_EVALUATION_MODEL"
  [[ -f "$root/evaluation.status" && "$(cat "$root/evaluation.status")" == 0 ]] || exit 1
fi
# Same team, wrong allowed identifier: server must reject it.
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.roarkist.inputmethod.RoarkT' "$app/Contents/Info.plist"
codesign --force --options runtime --timestamp=none --sign "$identity" "$app"
open -n -g -W "$app" --args --reject --status-file "$root/rejected.status"
[[ -f "$root/rejected.status" && "$(cat "$root/rejected.status")" == 0 ]] || exit 1
