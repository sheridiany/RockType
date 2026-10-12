#!/bin/zsh
# Install and explicitly enable parent + Pinyin for the GUI user; never select an input source.
set -euo pipefail
repo_dir=${0:A:h:h}
[[ $EUID -ne 0 ]] || { print -u2 'Run as your logged-in user, without sudo.'; exit 1; }
source_app="$repo_dir/dist/RockType Input.app"
app="$HOME/Library/Input Methods/RockType Input.app"
service="$repo_dir/dist/RockType.app/Contents/Helpers/RoarkTTranslationService"
registrar="$repo_dir/dist/RoarkTRegisterInputSource"
label=com.roarkist.roarkt.translation
agent="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"
[[ -d "$source_app" && -x "$service" && -x "$registrar" ]] || {
  print -u2 'Missing build products. Run scripts/build.sh first.'; exit 1
}
codesign --verify --strict --deep "$source_app"
codesign --verify --strict --deep "$repo_dir/dist/RockType.app"
# Build a complete, signed staging bundle on the destination filesystem before stopping IME.
mkdir -p "${app:h}" "${agent:h}"
staging=$(mktemp -d "${app:h}/.roarkt-install.XXXXXXXX")
temporary=''
trap 'rm -rf "$staging"; [[ -z "$temporary" ]] || rm -f "$temporary"' EXIT
staged_app="$staging/RockType Input.app"
ditto "$source_app" "$staged_app"
codesign --verify --strict --deep "$staged_app"
# Validate an existing target before replacing it. No other input methods are touched.
if [[ -e "$app" || -L "$app" ]]; then
  [[ ! -L "$app" && -d "$app" ]] || { print -u2 'Refusing a non-directory or symlink target.'; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == com.roarkist.inputmethod.RoarkT ]] || exit 1
  "$app/Contents/MacOS/RockType Input" --quit
fi
"$registrar" replace-bundle "$staged_app" "$app"
# After a swap the staging directory contains the previous bundle; it is not retained.
rm -rf "$staging"
# PlistBuddy writes the path as a plist string, including spaces and XML characters.
temporary=$(mktemp "${TMPDIR:-/tmp}/roarkt-agent.XXXXXX")
cat > "$temporary" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.roarkist.roarkt.translation</string>
<key>ProgramArguments</key><array><string></string></array>
<key>MachServices</key><dict><key>com.roarkist.roarkt.translation</key><true/></dict>
<key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $service" "$temporary"
plutil -lint "$temporary"
if launchctl print "$domain/$label" >/dev/null 2>&1; then
  launchctl bootout "$domain/$label"
fi
install -m 644 "$temporary" "$agent"
# bootout returns before launchd has released the label; bootstrap too early fails with EIO (5).
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  launchctl print "$domain/$label" >/dev/null 2>&1 || break
  sleep 0.5
done
for attempt in 1 2 3; do
  launchctl bootstrap "$domain" "$agent" && break
  [[ $attempt == 3 ]] && exit 1
  sleep 1
done
"$registrar" ensure-enabled "$app"
"$registrar" verify-enabled
print 'Installed RockType; parent and Pinyin TIS enablement verified. Selection unchanged.'
