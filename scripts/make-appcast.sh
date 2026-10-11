#!/bin/zsh
# Sign a notarized product pkg using Sparkle's Keychain key, then verify against its app's public key.
set -euo pipefail
repo_dir=${0:A:h:h}
[[ $# == 3 ]] || { print -u2 'Usage: scripts/make-appcast.sh <notarized.pkg> <https://github.com/OWNER/REPO/releases/download/TAG/FILE.pkg> <appcast.xml>'; exit 1; }
pkg=${1:A}
download=$2
output=${3:A}
[[ -f "$pkg" && "$pkg" == *.pkg ]] || { print -u2 'Package not found.'; exit 1; }
[[ "$output" != "$pkg" ]] || { print -u2 'Output must not replace the package.'; exit 1; }
signer="$repo_dir/.build/artifacts/sparkle/Sparkle/bin/sign_update"
[[ -x "$signer" ]] || { print -u2 'Run swift package resolve to fetch Sparkle 2.8.0 tools.'; exit 1; }
pkgutil --check-signature "$pkg" | grep -q 'Developer ID Installer:.*(DF7J2VBQD8)' || { print -u2 'Wrong package signing team.'; exit 1; }
xcrun stapler validate "$pkg"
# Private key stays in the Keychain; never accept raw keys via arguments or environment.
signature=$("$signer" --account "${ROARKT_SPARKLE_KEY_ACCOUNT:-ed25519}" -p "$pkg")
work=$(mktemp -d "$repo_dir/.build/appcast.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
pkgutil --expand-full "$pkg" "$work/expanded"
xcrun swiftc -swift-version 6 -parse-as-library -O "$repo_dir/Core/Identifiers.swift" \
  "$repo_dir/App/Features/Update/AppcastDocument.swift" "$repo_dir/Installer/tools/MakeAppcast.swift" -o "$work/make-appcast"
"$work/make-appcast" "$pkg" "$work/expanded" "$download" "$signature" "$output"
print "Generated: $output (publish alongside the exact signed pkg; no upload performed)"
