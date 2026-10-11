#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
cd "$repo_dir/Services/VoiceWorker"
xcodebuild -scheme RoarkTVoiceRuntime -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$repo_dir/.build/voice-worker" \
  -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO build
products="$repo_dir/.build/voice-worker/Build/Products/Release"
"$products/RoarkTVoiceWorker" --self-test
bundle="$repo_dir/dist/RoarkTVoiceWorker.xpc"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$products/RoarkTVoiceWorker" "$bundle/Contents/MacOS/"
cp "$repo_dir/Services/VoiceWorker/Info.plist" "$bundle/Contents/Info.plist"
# MLX uses a Metal resource bundle at runtime.
for resource in "$products/"*.bundle(N); do
  ditto "$resource" "$bundle/Contents/Resources/${resource:t}"
done
# Retain upstream license and NOTICE files alongside the statically linked worker.
notices="$bundle/Contents/Resources/ThirdPartyNotices"
mkdir -p "$notices"
for checkout in "$repo_dir/.build/voice-worker/SourcePackages/checkouts/"*(/N); do
  for notice in "$checkout"/LICENSE*(N.) "$checkout"/NOTICE*(N.); do
    mkdir -p "$notices/${checkout:t}"
    cp "$notice" "$notices/${checkout:t}/${notice:t}"
  done
done
cp "$repo_dir/Services/VoiceWorker/THIRD_PARTY_NOTICES.md" "$notices/README.md"
identity=${ROARKT_CODESIGN_IDENTITY:-'Developer ID Application: XIAO BIN (DF7J2VBQD8)'}
codesign --force --options runtime --timestamp=none --sign "$identity" "$bundle"
codesign --verify --strict "$bundle"
print "Built $bundle"
