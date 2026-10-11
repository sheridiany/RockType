#!/bin/bash
# Reproduce W-6 in ignored build storage. Does not install or access user data.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
name=${1:?trial name required}
model=${2:-bgw}
maximum=${3:-5}
minimum=${4:-2}
[[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 2
[[ "$model" == bgw || "$model" == bgc ]] || exit 2
trial="$root/.build/dictionary/w6/trials/$name"
[[ ! -e "$trial" ]] || { echo "Trial already exists: $trial" >&2; exit 2; }
vendor="$root/.build/dictionary/w6/upstream"
mkdir -p "$vendor" "$trial"
if [[ ! -d "$vendor/essay-simp/.git" ]]; then
  git clone https://github.com/rime/rime-essay-simp.git "$vendor/essay-simp"
fi
if [[ ! -d "$vendor/octagram/.git" ]]; then
  git clone https://github.com/lotem/rime-octagram-data.git "$vendor/octagram"
fi
git -C "$vendor/octagram" cat-file -e f8ce3b534733e489a8470a7c2adf5a154e8ea069 2>/dev/null || git -C "$vendor/octagram" fetch origin hans
git archive 7e6517d62f1776e90caed1b66dc4cc48bd0687c0 Rime | tar -x -C "$trial"
git -C "$vendor/essay-simp" show dc06d4c96ae72ad46b29e3aa824a5d1e8f721fd0:essay-zh-hans.txt > "$trial/Rime/essay.txt"
git -C "$vendor/octagram" show "f8ce3b534733e489a8470a7c2adf5a154e8ea069:zh-hans-t-essay-$model.gram" > "$trial/Rime/zh-hans-t-essay-$model.gram"
swift scripts/dictionary/simplify-luna.swift InputMethod/data/plum/luna_pinyin.dict.yaml InputMethod/data/plum/essay.txt "$trial/Rime/roarkt_base.dict.yaml" "$trial/collisions.tsv"
swift scripts/dictionary/prepare-trial.swift "$trial/Rime" "$model" "$maximum" "$minimum"
echo "$trial/Rime"
