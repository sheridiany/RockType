#!/bin/zsh
# Build and sign RoarkT products into dist/.
set -euo pipefail
repo_dir=${0:A:h:h}
cd "$repo_dir"

identity=${ROARKT_CODESIGN_IDENTITY:-}
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application: XIAO BIN \(DF7J2VBQD8\)/ { print $2; exit }')
fi
[[ -n "$identity" ]] || { print -u2 "No signing identity; set ROARKT_CODESIGN_IDENTITY."; exit 1; }

# Keep build products out of Spotlight/Launchpad: several worktrees build RoarkT.app,
# and indexed copies would also be candidates when LaunchServices opens the bundle ID.
dist_store="$repo_dir/.build/dist.noindex"
mkdir -p "$dist_store"
if [[ -d "$repo_dir/dist" && ! -L "$repo_dir/dist" ]]; then
  ditto "$repo_dir/dist" "$dist_store" && rm -rf "$repo_dir/dist"
fi
[[ -L "$repo_dir/dist" ]] || ln -s .build/dist.noindex "$repo_dir/dist"

swift build -c release --product RoarkTApp
swift build -c release --product RoarkTTranslationService
bin_dir=$(swift build -c release --show-bin-path)

app="$repo_dir/dist/RoarkT.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp "$repo_dir/App/Info.plist" "$app/Contents/Info.plist"
cp "$bin_dir/RoarkTApp" "$app/Contents/MacOS/RoarkT"
cp "$bin_dir/RoarkTTranslationService" "$app/Contents/Helpers/RoarkTTranslationService"
xcrun actool "$repo_dir/Assets/AppIcon.icon" --compile "$app/Contents/Resources" --app-icon AppIcon \
  --platform macosx --minimum-deployment-target 14.0 \
  --output-partial-info-plist "$repo_dir/.build/appicon-partial.plist" > /dev/null

codesign --force --options runtime --timestamp=none --sign "$identity" \
  --identifier com.roarkist.roarkt.translation "$app/Contents/Helpers/RoarkTTranslationService"
# Voice: the signed helper lives in Helpers; XPCServices exposes it to launchd.
ROARKT_CODESIGN_IDENTITY="$identity" zsh "$repo_dir/scripts/build-voice-worker.sh"
ditto "$repo_dir/dist/RoarkTVoiceWorker.xpc" "$app/Contents/Helpers/RoarkTVoiceWorker.xpc"
mkdir -p "$app/Contents/XPCServices"
ln -s ../Helpers/RoarkTVoiceWorker.xpc "$app/Contents/XPCServices/RoarkTVoiceWorker.xpc"
/usr/libexec/PlistBuddy -c 'Add :NSMicrophoneUsageDescription string 按住 Fn 时录音，在本机识别后填入当前输入框。' "$app/Contents/Info.plist"
codesign --force --options runtime --timestamp=none --sign "$identity" \
  --entitlements "$repo_dir/Services/VoiceWorker/App.entitlements" "$app"
# End voice integration.
codesign --verify --strict --deep "$app"
print "Built $app (signed with $identity)"

# Build the GPL input method separately, compiling shared MIT value types from Core.
# No input method code is linked into the MIT products.
for dependency in librime plum Sparkle; do
  [[ -f "$repo_dir/InputMethod/$dependency/.git" ]] || {
    print -u2 'Initialize dependencies with git submodule update --init --recursive.'; exit 1
  }
done
xcodebuild -project "$repo_dir/InputMethod/Squirrel.xcodeproj" -scheme Squirrel \
  -configuration Release -derivedDataPath "$repo_dir/.build/ime" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
input_app="$repo_dir/dist/RoarkT Input.app"
rm -rf "$input_app"
ditto "$repo_dir/.build/ime/Build/Products/Release/RoarkT Input.app" "$input_app"
# Sign nested executables/libraries before the bundle (without --deep signing).
for binary in "$input_app/Contents/Frameworks/"*.dylib(N) \
    "$input_app/Contents/Frameworks/rime-plugins/"*.dylib(N) \
    "$input_app/Contents/MacOS/rime_deployer" "$input_app/Contents/MacOS/rime_dict_manager"; do
  codesign --force --options runtime --timestamp=none --sign "$identity" "$binary"
done
codesign --force --options runtime --timestamp=none --sign "$identity" "$input_app"
codesign --verify --strict --deep "$input_app"
xcrun swiftc -swift-version 6 -parse-as-library -O "$repo_dir/Core/Identifiers.swift" \
  "$repo_dir/Installer/tools/RegisterInputSource.swift" -o "$repo_dir/dist/RoarkTRegisterInputSource"
codesign --force --options runtime --timestamp=none --sign "$identity" "$repo_dir/dist/RoarkTRegisterInputSource"
print "Built $input_app and registration tool (signed with $identity)"
