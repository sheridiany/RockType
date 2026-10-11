#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
runtime="$repo_dir/InputMethod"
bundle=""
if (( $# != 0 )); then
  [[ $# == 2 && "$1" == --bundle ]] || { print -u2 "Usage: $0 [--bundle <input-method.app>]"; exit 1; }
  bundle="${2:A}"
fi
shared_files=(default.yaml key_bindings.yaml punctuation.yaml symbols.yaml pinyin.yaml
              luna_pinyin.dict.yaml essay.txt zh-hant-t-essay-bgw.gram)
if [[ -n "$bundle" ]]; then
  deployer="$bundle/Contents/MacOS/rime_deployer"
  libraries="$bundle/Contents/Frameworks"
  shared_source="$bundle/Contents/SharedSupport"
else
  # Only use this checkout's pinned runtime; never borrow a sibling product.
  deployer="$runtime/bin/rime_deployer"
  libraries="$runtime/lib"
  shared_source="$runtime/data/plum"
fi
for resource in "$deployer" "$libraries/librime.1.dylib" "${shared_files[@]/#/$shared_source/}"; do
  if [[ ! -s "$resource" ]]; then
    print -u2 "Missing Rime deployment dependency: $resource"
    exit 1
  fi
done
[[ -x "$deployer" ]]

temporary=$(mktemp -d "${TMPDIR:-/tmp}/roarkt-rime.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/bin" "$temporary/shared" "$temporary/user" "$temporary/build"
# Resolve the deployer's @loader_path/../Frameworks without changing its source.
cp "$deployer" "$temporary/bin/"
ln -s "$libraries" "$temporary/Frameworks"
if [[ -n "$bundle" ]]; then
  cp -R "$shared_source/." "$temporary/shared/"
else
  for resource in "${shared_files[@]}"; do
    cp "$shared_source/$resource" "$temporary/shared/"
  done
  cp -R "$runtime/data/opencc" "$temporary/shared/"
  cp -R "$repo_dir/Rime/lua" "$temporary/shared/"
  cp "$repo_dir/Rime/"*.yaml "$temporary/shared/"
  cp -R "$repo_dir/Rime/cn_dicts" "$temporary/shared/"
fi
cp "$temporary/shared/default.custom.yaml" "$temporary/user/"

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
