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
# notarytool may exit successfully after an Invalid submission. Require Accepted explicitly.
result=$(mktemp -t roarkt-notary)
trap 'rm -f "$result"' EXIT
xcrun notarytool submit "$pkg" --keychain-profile "$profile" --wait --output-format json > "$result"
submission_status=$(/usr/bin/plutil -extract status raw -o - "$result")
[[ "$submission_status" == Accepted ]] || { print -u2 "Notarization was not accepted ($submission_status). Inspect the submission in notarytool; installer was not stapled."; exit 1; }
xcrun stapler staple "$pkg"
xcrun stapler validate "$pkg"
spctl --assess --type install --verbose=4 "$pkg"
print "Notarized and stapled: $pkg"
