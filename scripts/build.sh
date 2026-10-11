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

swift build -c release --product RoarkTApp
swift build -c release --product RoarkTTranslationService
bin_dir=$(swift build -c release --show-bin-path)

app="$repo_dir/dist/RoarkT.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp "$repo_dir/App/Info.plist" "$app/Contents/Info.plist"
cp "$bin_dir/RoarkTApp" "$app/Contents/MacOS/RoarkT"
cp "$bin_dir/RoarkTTranslationService" "$app/Contents/Helpers/RoarkTTranslationService"

codesign --force --options runtime --timestamp=none --sign "$identity" \
  --identifier com.roarkist.roarkt.translation "$app/Contents/Helpers/RoarkTTranslationService"
codesign --force --options runtime --timestamp=none --sign "$identity" "$app"
codesign --verify --strict --deep "$app"
print "Built $app (signed with $identity)"
