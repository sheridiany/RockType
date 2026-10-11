#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
cd "$repo_dir"
# Build only the app; rendering does not need signing, helpers or screen recording.
swift build --product RoarkTApp
bin_dir=$(swift build --show-bin-path)
"$bin_dir/RoarkTApp" --render-gallery "${1:-$repo_dir/dist/gallery}"
