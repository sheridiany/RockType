#!/bin/bash
# Xcode build phase: package this repository's factory data without touching the runtime user directory.
set -euo pipefail
shared="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/SharedSupport"
mkdir -p "$shared/lua"
cp "$SRCROOT/../Rime/"*.yaml "$shared/"
cp "$SRCROOT/../Rime/lua/"*.lua "$shared/lua/"
cp "$SRCROOT/data/plum/zh-hant-t-essay-bgw.gram" "$shared/"
cp "$SRCROOT/../THIRD_PARTY_NOTICES.md" "$shared/"
