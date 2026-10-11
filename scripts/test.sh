#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
cd "$repo_dir"
swift test
zsh "$repo_dir/scripts/test-rime.sh"
bash "$repo_dir/scripts/test-rime-capabilities.sh"
bash "$repo_dir/Tests/AppShellTests/run.sh"
# Guard: retain existing exclusions, plus only these upstream IME trees.
scan_roots=()
for entry in ./*(DN); do
  if [[ "$entry" == ./InputMethod ]]; then
    for input_entry in "$entry"/*(DN); do
      case "$input_entry" in
        ./InputMethod/data|./InputMethod/librime|./InputMethod/plum|./InputMethod/Sparkle) ;;
        *) scan_roots+=("$input_entry") ;;
      esac
    done
  else
    scan_roots+=("$entry")
  fi
done
if grep -rIl -E 'RoType|洛克输入法|Luoke|im\.roarkai|RoarkTools' \
    --exclude-dir=.git --exclude-dir=.build --exclude-dir=dist --exclude-dir=docs --exclude-dir=specs \
    --exclude='THIRD_PARTY_NOTICES*' --exclude='LICENSE*' --exclude='AGENTS.md' --exclude='README.md' \
    --exclude='test.sh' "${scan_roots[@]}" ; then
  print -u2 "Legacy identifiers found (see files above)."
  exit 1
fi
if grep -ri -E 'rotype|洛克输入法|luoke|im\.roarkai|RoarkTools' Rime/; then
  print -u2 "Legacy identifiers found in Rime resources."
  exit 1
fi
print "All tests passed."
