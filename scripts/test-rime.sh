#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
runtime="$repo_dir/InputMethod"
# Until the input method is imported, use a sibling checkout that already has the deployer.
if [[ ! -x "$runtime/bin/rime_deployer" ]]; then
  runtime=""
  for candidate in "$repo_dir"/../*/Squirrel/bin/rime_deployer(N); do
    runtime="${candidate:h:h}"
    break
  done
fi
for resource in bin/rime_deployer lib/librime.1.dylib data/plum/default.yaml \
    data/plum/luna_pinyin.dict.yaml data/plum/essay.txt data/plum/zh-hant-t-essay-bgw.gram; do
  if [[ ! -f "$runtime/$resource" ]]; then
    print -u2 "Missing Rime deployment dependency: $runtime/$resource"
    exit 1
  fi
done
[[ -x "$runtime/bin/rime_deployer" ]]

temporary=$(mktemp -d "${TMPDIR:-/tmp}/roarkt-rime.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/bin" "$temporary/shared" "$temporary/user" "$temporary/build"
# Resolve the deployer's @loader_path/../Frameworks without changing its source.
cp "$runtime/bin/rime_deployer" "$temporary/bin/"
ln -s "$runtime/lib" "$temporary/Frameworks"
for resource in default.yaml punctuation.yaml key_bindings.yaml luna_pinyin.dict.yaml essay.txt \
    zh-hant-t-essay-bgw.gram; do
  cp "$runtime/data/plum/$resource" "$temporary/shared/"
done
cp -R "$runtime/data/opencc" "$temporary/shared/"
cp -R "$repo_dir/Rime/lua" "$temporary/shared/"
cp "$repo_dir/Rime/"*.yaml "$temporary/shared/"
cp "$repo_dir/Rime/default.custom.yaml" "$temporary/user/"

if ! "$temporary/bin/rime_deployer" --build "$temporary/user" "$temporary/shared" \
    "$temporary/build" > "$temporary/deploy.log" 2>&1; then
  cat "$temporary/deploy.log"
  exit 1
fi
# Require fresh outputs, so an empty or partially deployed schema list cannot pass.
for artifact in roarkt.schema.yaml roarkt_flypy.schema.yaml roarkt_en.schema.yaml \
    roarkt_zh.table.bin roarkt_zh.prism.bin roarkt_flypy.prism.bin \
    roarkt_en.table.bin roarkt_en.prism.bin; do
  if [[ ! -s "$temporary/build/$artifact" ]]; then
    cat "$temporary/deploy.log"
    print -u2 "Missing deployment output: $artifact"
    exit 1
  fi
done
print "Rime deployment passed: roarkt, roarkt_flypy, roarkt_en; fresh dictionaries and prisms."
