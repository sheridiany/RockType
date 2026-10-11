#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
runtime="$root/InputMethod"
# Optional factory resource directory supports isolated trial replay with unchanged checks.
(( $# <= 1 )) || { echo "Usage: $0 [Rime resource directory]" >&2; exit 2; }
source_dir=${1:-"$root/Rime"}
temporary=$(mktemp -d "${TMPDIR:-/tmp}/roarkt-rime-capabilities.XXXXXX")
# lsof reports canonical paths (macOS /var is a symlink).
temporary=$(cd "$temporary" && pwd -P)
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/bin" "$temporary/shared" "$temporary/bootstrap" "$temporary/build"
cp "$runtime/bin/rime_deployer" "$temporary/bin/"
ln -s "$runtime/lib" "$temporary/Frameworks"
for resource in default.yaml key_bindings.yaml punctuation.yaml symbols.yaml pinyin.yaml; do
  cp "$runtime/data/plum/$resource" "$temporary/shared/"
done
cp -R "$source_dir/." "$temporary/shared/"
cp "$source_dir/default.custom.yaml" "$temporary/bootstrap/"
deploy() {
  if ! "$temporary/bin/rime_deployer" --build "$temporary/bootstrap" "$temporary/shared" "$temporary/build" > "$temporary/deploy.log" 2>&1; then
    cat "$temporary/deploy.log"; exit 1
  fi
}
deploy
xcrun swiftc -import-objc-header "$root/Tests/InputMethodTests/RimeBridge.h" -I "$runtime/librime/src" \
  "$root/Core/Identifiers.swift" "$runtime/sources/BridgingFunctions.swift" "$root/Tests/InputMethodTests/RimeChecks.swift" \
  "$runtime/lib/librime.1.dylib" "$runtime/lib/rime-plugins/librime-lua.dylib" \
  -Xlinker -rpath -Xlinker "$runtime/lib" -Xlinker -rpath -Xlinker "$runtime/lib/rime-plugins" \
  -o "$temporary/check"
run() {
  local profile=$1 schema=$2 action=$3
  mkdir -p "$temporary/$profile"
  "$temporary/check" "$temporary/shared" "$temporary/$profile" "$temporary/build" "$schema" "$action"
}
for schema in roarkt roarkt_flypy; do
  for action in samples domain homophones shift shift-prefix english translation input-ai lifecycle-regression; do
    run "$schema-$action" "$schema" "$action"
  done
  run "$schema-learning" "$schema" baseline
  run "$schema-learning" "$schema" train
  run "$schema-learning" "$schema" verify
  other=roarkt
  if [[ "$schema" == roarkt ]]; then other=roarkt_flypy; fi
  run "$schema-learning" "$other" verify
  run "$schema-learning" "$schema" forget
  # Rebuild schemas, then verify from a fresh process against the same private user database.
  deploy
  run "$schema-learning" "$schema" forgotten
  run "$schema-learning" "$other" forgotten
done
printf '%s\n' 'Rime capabilities passed in isolated profiles; no production user data accessed.'

# Both runtimes use the same schema/userdb names, but different profiles under a fake home.
# Keep both processes alive while inspecting actual LevelDB handles.
other="$temporary/home/Library/Rime"
private=$("$temporary/check" --private-directory "$temporary/home")
mkdir -p "$other"
"$temporary/check" "$temporary/shared" "$private" "$temporary/build" roarkt sync-path
mkfifo "$temporary/other.pipe" "$temporary/private.pipe"
exec 3<>"$temporary/other.pipe"
exec 4<>"$temporary/private.pipe"
"$temporary/check" "$temporary/shared" "$other" "$temporary/build" roarkt isolation <&3 >"$temporary/other.log" 2>&1 &
other_pid=$!
"$temporary/check" "$temporary/shared" "$private" "$temporary/build" roarkt isolation <&4 >"$temporary/private.log" 2>&1 &
private_pid=$!
cleanup_isolation() {
  kill "$other_pid" "$private_pid" 2>/dev/null || true
  rm -rf "$temporary"
}
trap cleanup_isolation EXIT
for ((attempt=0; attempt<200; attempt++)); do
  [[ -f "$other/ready" && -f "$private/ready" ]] && break
  kill -0 "$other_pid" && kill -0 "$private_pid" || { cat "$temporary/"*.log; exit 1; }
  sleep 0.1
done
[[ -f "$other/ready" && -f "$private/ready" ]]
/usr/sbin/lsof -a -p "$other_pid" -Fn > "$temporary/other.handles"
/usr/sbin/lsof -a -p "$private_pid" -Fn > "$temporary/private.handles"
for db in roarkt_zh roarkt_en; do
  grep -F "n$other/$db.userdb/LOCK" "$temporary/other.handles"
  grep -F "n$private/$db.userdb/LOCK" "$temporary/private.handles"
done
if grep -F "n$private/" "$temporary/other.handles" || grep -F "n$other/" "$temporary/private.handles"; then
  printf '%s\n' 'A librime process opened the other profile.' >&2
  exit 1
fi
printf 'release\n' >&3
printf 'release\n' >&4
wait "$other_pid"
wait "$private_pid"
trap 'rm -rf "$temporary"' EXIT
printf '%s\n' 'Concurrent librime isolation passed: each process opens only its own Chinese/English userdb.'
