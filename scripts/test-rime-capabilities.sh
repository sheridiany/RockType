#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
runtime="$root/InputMethod"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/roarkt-rime-capabilities.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/bin" "$temporary/shared" "$temporary/bootstrap" "$temporary/build"
cp "$runtime/bin/rime_deployer" "$temporary/bin/"
ln -s "$runtime/lib" "$temporary/Frameworks"
for resource in default.yaml key_bindings.yaml punctuation.yaml symbols.yaml pinyin.yaml luna_pinyin.dict.yaml essay.txt zh-hant-t-essay-bgw.gram; do
  cp "$runtime/data/plum/$resource" "$temporary/shared/"
done
cp -R "$runtime/data/opencc" "$root/Rime/lua" "$temporary/shared/"
cp "$root/Rime/"*.yaml "$temporary/shared/"
cp "$root/Rime/default.custom.yaml" "$temporary/bootstrap/"
deploy() {
  if ! "$temporary/bin/rime_deployer" --build "$temporary/bootstrap" "$temporary/shared" "$temporary/build" > "$temporary/deploy.log" 2>&1; then
    cat "$temporary/deploy.log"; exit 1
  fi
}
deploy
xcrun swiftc -import-objc-header "$root/Tests/InputMethodTests/RimeBridge.h" -I "$runtime/librime/src" \
  "$runtime/sources/BridgingFunctions.swift" "$root/Tests/InputMethodTests/RimeChecks.swift" \
  "$runtime/lib/librime.1.dylib" "$runtime/lib/rime-plugins/librime-lua.dylib" \
  -Xlinker -rpath -Xlinker "$runtime/lib" -Xlinker -rpath -Xlinker "$runtime/lib/rime-plugins" \
  -o "$temporary/check"
run() {
  local profile=$1 schema=$2 action=$3
  mkdir -p "$temporary/$profile"
  "$temporary/check" "$temporary/shared" "$temporary/$profile" "$temporary/build" "$schema" "$action"
}
for schema in roarkt roarkt_flypy; do
  for action in samples shift shift-prefix english translation; do
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
