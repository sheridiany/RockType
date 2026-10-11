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
swiftc -swift-version 6 Core/Identifiers.swift App/Features/Voice/VoiceWorkerProtocol.swift \
  Tests/VoiceWorkerSmoke/main.swift -o "$app/Contents/MacOS/RockType"
codesign --force --options runtime --timestamp=none --sign "$identity" "$app"
codesign --verify --strict --deep "$app"
"$app/Contents/Helpers/RoarkTVoiceWorker.xpc/Contents/MacOS/RoarkTVoiceWorker" --self-test
"$app/Contents/MacOS/RockType"
# Same team, wrong allowed identifier: server must reject it.
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.roarkist.inputmethod.RoarkT' "$app/Contents/Info.plist"
codesign --force --options runtime --timestamp=none --sign "$identity" "$app"
"$app/Contents/MacOS/RockType" --reject
