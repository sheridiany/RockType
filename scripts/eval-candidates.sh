#!/bin/bash
# Factory-only benchmark. Optional source checkout and output directory allow baseline replay.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root/Rime"}
output=${2:-"$root/.build/candidate-eval"}
mkdir -p "$output"
output=$(cd "$output" && pwd)
runtime="$root/InputMethod"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/roarkt-eval.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/bin" "$temporary/shared" "$temporary/user" "$temporary/build"
cp "$runtime/bin/rime_deployer" "$temporary/bin/"
ln -s "$runtime/lib" "$temporary/Frameworks"
for resource in default.yaml key_bindings.yaml punctuation.yaml symbols.yaml pinyin.yaml luna_pinyin.dict.yaml essay.txt zh-hant-t-essay-bgw.gram; do
  cp "$runtime/data/plum/$resource" "$temporary/shared/"
done
cp -R "$runtime/data/opencc" "$temporary/shared/"
cp -R "$source_dir/." "$temporary/shared/"
cp "$source_dir/default.custom.yaml" "$temporary/user/"
/usr/bin/time -p "$temporary/bin/rime_deployer" --build "$temporary/user" "$temporary/shared" "$temporary/build" > "$output/deploy.log" 2>&1
for artifact in roarkt.schema.yaml roarkt_flypy.schema.yaml roarkt_zh.table.bin roarkt_zh.prism.bin roarkt_flypy.prism.bin roarkt_en.table.bin; do
  test -s "$temporary/build/$artifact"
done
xcrun swiftc -import-objc-header "$root/Tests/InputMethodTests/RimeBridge.h" -I "$runtime/librime/src" \
  "$runtime/sources/BridgingFunctions.swift" "$root/Tests/InputMethodTests/CandidateEvaluation.swift" \
  "$runtime/lib/librime.1.dylib" "$runtime/lib/rime-plugins/librime-lua.dylib" \
  -Xlinker -rpath -Xlinker "$runtime/lib" -Xlinker -rpath -Xlinker "$runtime/lib/rime-plugins" \
  -o "$temporary/evaluate"
"$temporary/evaluate" "$temporary/shared" "$temporary/user" "$temporary/build" \
  "$root/Tests/InputMethodTests/Fixtures/candidate-eval.tsv" roarkt "$output/results.tsv" 2> "$output/runtime.log" | tee "$output/summary.tsv"
tail -n 3 "$output/deploy.log"
