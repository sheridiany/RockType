#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
profile=${ROARKT_NOTARY_PROFILE:-}
[[ -n "$profile" ]] || { print -u2 'Set ROARKT_NOTARY_PROFILE to an existing notarytool Keychain profile. No credentials are stored by this script.'; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_dir/App/Info.plist")
pkg=${1:-"$repo_dir/dist/RoarkT-$version-macOS-arm64.pkg"}
[[ -f "$pkg" && "$pkg" == *.pkg ]] || { print -u2 'Signed installer not found; run scripts/build-installer.sh first.'; exit 1; }
pkgutil --check-signature "$pkg" | grep -q 'Developer ID Installer:.*(DF7J2VBQD8)' || {
  print -u2 'Installer must be signed by the RoarkT team.'; exit 1
}
# --wait returns a submission status; staple is an additional accepted-ticket gate.
xcrun notarytool submit "$pkg" --keychain-profile "$profile" --wait
xcrun stapler staple "$pkg"
xcrun stapler validate "$pkg"
spctl --assess --type install --verbose=4 "$pkg"
print "Notarized and stapled: $pkg"
