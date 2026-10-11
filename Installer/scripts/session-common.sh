#!/bin/bash
# Installed scripts only operate on the live startup volume.
set -euo pipefail
[[ "${3:-/}" == / ]] || { echo 'RoarkT: install on the startup volume only.' >&2; exit 1; }
service=com.roarkist.roarkt.translation
agent="/Library/LaunchAgents/$service.plist"
active_uids() {
  /bin/ps -axo uid=,command= | /usr/bin/awk '$1 >= 500 && $2 == "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow" {print $1}' | /usr/bin/sort -nu
}
run_as_user() {
  local uid="$1" user
  shift
  user=$(/usr/bin/id -nu "$uid")
  /bin/launchctl asuser "$uid" /usr/bin/sudo -H -u "$user" -- "$@"
}
