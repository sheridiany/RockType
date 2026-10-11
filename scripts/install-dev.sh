#!/bin/zsh
# Install for the current GUI user; never enable or select an input source.
set -euo pipefail
repo_dir=${0:A:h:h}
[[ $EUID -ne 0 ]] || { print -u2 'Run as your logged-in user, without sudo.'; exit 1; }
source_app="$repo_dir/dist/RoarkT Input.app"
app="$HOME/Library/Input Methods/RoarkT Input.app"
service="$repo_dir/dist/RoarkT.app/Contents/Helpers/RoarkTTranslationService"
registrar="$repo_dir/dist/RoarkTRegisterInputSource"
label=com.roarkist.roarkt.translation
agent="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"
[[ -d "$source_app" && -x "$service" && -x "$registrar" ]] || {
  print -u2 'Missing build products. Run scripts/build.sh first.'; exit 1
}
codesign --verify --strict --deep "$source_app"
codesign --verify --strict --deep "$repo_dir/dist/RoarkT.app"
# Validate an existing target before replacing it. No other input methods are touched.
if [[ -e "$app" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == com.roarkist.inputmethod.RoarkT ]] || exit 1
  "$app/Contents/MacOS/RoarkT Input" --quit
fi
mkdir -p "${app:h}" "${agent:h}"
rm -rf "$app"
ditto "$source_app" "$app"
# PlistBuddy writes the path as a plist string, including spaces and XML characters.
temporary=$(mktemp "${TMPDIR:-/tmp}/roarkt-agent.XXXXXX")
trap 'rm -f "$temporary"' EXIT
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
launchctl bootstrap "$domain" "$agent"
"$registrar" register "$app"
print 'Installed and registered RoarkT（全拼） / RoarkT（小鹤双拼）. Add and select them in System Settings.'
