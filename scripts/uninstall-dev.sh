#!/bin/zsh
# Remove only the current user's development installation; preserve Rime data.
set -euo pipefail
repo_dir=${0:A:h:h}
[[ $EUID -ne 0 ]] || { print -u2 'Run as your logged-in user, without sudo.'; exit 1; }
app="$HOME/Library/Input Methods/RockType Input.app"
label=com.roarkist.roarkt.translation
agent="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"
if [[ -e "$app" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == com.roarkist.inputmethod.RoarkT ]] || exit 1
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/roarkt-uninstall.XXXXXX")
  trap 'rm -rf "$temporary"' EXIT
  xcrun swiftc -swift-version 6 -parse-as-library "$repo_dir/Core/Identifiers.swift" \
    "$repo_dir/Installer/tools/RegisterInputSource.swift" -o "$temporary/register"
  "$temporary/register" disable
  "$app/Contents/MacOS/RockType Input" --quit
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app"
  rm -rf "$app"
fi
if launchctl print "$domain/$label" >/dev/null 2>&1; then
  launchctl bootout "$domain/$label"
fi
rm -f "$agent"
print 'Development installation removed. Rime user data and dist/ are preserved. macOS may retain registration entries until next login.'
