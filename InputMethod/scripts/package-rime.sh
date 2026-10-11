#!/bin/bash
# Xcode build phase: package this repository's factory data without touching ~/Library/Rime.
set -euo pipefail
shared="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/SharedSupport"
mkdir -p "$shared/lua"
cp "$SRCROOT/../Rime/"*.yaml "$shared/"
cp "$SRCROOT/../Rime/lua/"*.lua "$shared/lua/"
cp "$SRCROOT/data/plum/zh-hant-t-essay-bgw.gram" "$shared/"
