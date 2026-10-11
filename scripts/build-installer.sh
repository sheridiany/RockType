#!/bin/zsh
# Consume the products from scripts/build.sh; stage and re-sign for distribution.
set -euo pipefail
export COPYFILE_DISABLE=1
repo_dir=${0:A:h:h}
cd "$repo_dir"
[[ $(uname -m) == arm64 ]] || { print -u2 'RoarkT requires Apple Silicon.'; exit 1; }
identity=${ROARKT_CODESIGN_IDENTITY:-'Developer ID Application: XIAO BIN (DF7J2VBQD8)'}
installer_identity=${ROARKT_INSTALLER_IDENTITY:-'Developer ID Installer: XIAO BIN (DF7J2VBQD8)'}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid release version.'; exit 1; }
for product in 'RoarkT.app' 'RoarkT Input.app'; do
  [[ -d "dist/$product" ]] || { print -u2 'Run scripts/build.sh first.'; exit 1; }
done
work=$(mktemp -d "$repo_dir/.build/installer.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
root="$work/root"
app="$root/Applications/RoarkT.app"
input="$root/Library/Input Methods/RoarkT Input.app"
mkdir -p "$root/Applications" "$root/Library/Input Methods" "$root/Library/LaunchAgents"
ditto --norsrc --noextattr dist/RoarkT.app "$app"
ditto --norsrc --noextattr 'dist/RoarkT Input.app' "$input"
cp Installer/com.roarkist.roarkt.translation.plist "$root/Library/LaunchAgents/"
ditto Installer/scripts "$work/scripts"
xcrun swiftc -swift-version 6 -parse-as-library -O Core/Identifiers.swift Installer/tools/SessionControl.swift -o "$work/scripts/RoarkTSessionControl"
xcrun swiftc -swift-version 6 -parse-as-library -O Core/Identifiers.swift Installer/tools/RegisterInputSource.swift -o "$app/Contents/Helpers/RoarkTRegisterInputSource"
xcrun swiftc -swift-version 6 -parse-as-library -O Core/Identifiers.swift App/Features/Uninstall/UninstallData.swift Installer/tools/CleanupUserData.swift -o "$app/Contents/Helpers/RoarkTCleanupUserData"
for bundle in "$app" "$input"; do
  mkdir -p "$bundle/Contents/Resources/Licenses"
  ditto LICENSES "$bundle/Contents/Resources/Licenses"
  cp THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/Licenses/"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$bundle/Contents/Info.plist"
  build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' App/Info.plist)
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$bundle/Contents/Info.plist"
done
# Timestamp every Mach-O, then each enclosing bundle from the inside out.
# Keep existing identifiers and entitlements (notably the voice worker).
while IFS= read -r -d '' file; do
  if /usr/bin/file -b "$file" | /usr/bin/grep -q 'Mach-O'; then
    codesign --force --options runtime --timestamp --preserve-metadata=identifier,entitlements --sign "$identity" "$file"
  fi
done < <(find "$root" "$work/scripts" -type f -print0)
while IFS= read -r -d '' bundle; do
  codesign --force --options runtime --timestamp --preserve-metadata=identifier,entitlements --sign "$identity" "$bundle"
done < <(find "$root" -depth -type d \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' \) -print0)
for bundle in "$app" "$input"; do
  codesign --verify --strict --deep "$bundle"
done
chmod 755 "$work/scripts/preinstall" "$work/scripts/postinstall"
chmod 644 "$root/Library/LaunchAgents/com.roarkist.roarkt.translation.plist"
pkgbuild --analyze --root "$root" "$work/components.plist"
i=0
while /usr/libexec/PlistBuddy -c "Print :$i:RootRelativeBundlePath" "$work/components.plist" >/dev/null 2>&1; do
  /usr/libexec/PlistBuddy -c "Add :$i:BundleIsRelocatable bool false" "$work/components.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :$i:BundleIsRelocatable false" "$work/components.plist"
  /usr/libexec/PlistBuddy -c "Add :$i:BundleIsVersionChecked bool false" "$work/components.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :$i:BundleIsVersionChecked false" "$work/components.plist"
  i=$((i+1))
done
pkgbuild --root "$root" --component-plist "$work/components.plist" --scripts "$work/scripts" \
  --identifier com.roarkist.roarkt --version "$version" --install-location / \
  --sign "$installer_identity" "$work/component.pkg"
# A product archive supports Sparkle's guided package installation.
productbuild --synthesize --package "$work/component.pkg" "$work/Distribution.xml"
sed -E -i '' 's/ hostArchitectures="[^"]*"//g; s/<options /<options hostArchitectures="arm64" /' "$work/Distribution.xml"
output="$repo_dir/dist/RoarkT-$version-macOS-arm64.pkg"
productbuild --distribution "$work/Distribution.xml" --package-path "$work" --sign "$installer_identity" "$output"
pkgutil --check-signature "$output"
print "Built: $output"
