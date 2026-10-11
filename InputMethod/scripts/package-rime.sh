#!/bin/bash
# Rebuild this build product's factory resources; never touch runtime user data.
set -euo pipefail
shared="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/SharedSupport"
rm -rf "$shared"
mkdir -p "$shared/lua"
for resource in default.yaml key_bindings.yaml punctuation.yaml symbols.yaml pinyin.yaml; do
  cp "$SRCROOT/data/plum/$resource" "$shared/"
done
cp "$SRCROOT/data/squirrel.yaml" "$shared/"
cp "$SRCROOT/../Rime/"*.yaml "$shared/"
cp "$SRCROOT/../Rime/lua/"*.lua "$shared/lua/"
cp "$SRCROOT/../Rime/essay.txt" "$SRCROOT/../Rime/"*.gram "$shared/"
cp "$SRCROOT/../THIRD_PARTY_NOTICES.md" "$shared/"
licenses="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Resources/Licenses"
# Recreate generated notices: cp preserves source read-only modes, so overwriting
# yesterday's copies fails. Removing also prevents stale dependency notices.
rm -rf "$licenses"
mkdir -p "$licenses"
cp -R "$SRCROOT/../LICENSES/." "$licenses/"
cp "$SRCROOT/../THIRD_PARTY_NOTICES.md" "$licenses/"
