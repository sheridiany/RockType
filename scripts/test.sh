#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
cd "$repo_dir"
swift test
zsh "$repo_dir/scripts/test-rime.sh"
# Guard: no legacy identifiers outside licence/notice files and docs.
if grep -rIl -E 'RoType|洛克|Luoke|im\.roarkai|RoarkTools' \
    --exclude-dir=.git --exclude-dir=.build --exclude-dir=dist --exclude-dir=docs --exclude-dir=specs \
    --exclude='THIRD_PARTY_NOTICES*' --exclude='LICENSE*' --exclude='AGENTS.md' --exclude='README.md' \
    --exclude='test.sh' . ; then
  print -u2 "Legacy identifiers found (see files above)."
  exit 1
fi
if grep -ri -E 'rotype|洛克|luoke|im\.roarkai|RoarkTools' Rime/; then
  print -u2 "Legacy identifiers found in Rime resources."
  exit 1
fi
print "All tests passed."
