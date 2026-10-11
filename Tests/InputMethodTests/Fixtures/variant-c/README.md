# Variant C evaluation fixture

This is the experimental AI dictionary for SPEC-011 variant C. It is **not shipped**.
It preserves all 1,067 original terms, their priority 800 and the 104 explicit readings.
Only the text column was converted with macOS Foundation's ICU `Hans-Hant` transform;
Rime's original `tw2s.json` filter produces simplified output. It retains the original MIT license.

C uses the complete A resource set from `a3fa578`, including `luna_pinyin`, preset
vocabulary, the original simplified-output chain, octagram and
`contextual_suggestions: true`. It adds this dictionary via `import_tables` and the
expanded English dictionary from `9df3960`. The fixed 200-row evaluation input is unchanged.

Reproduce from the repository root (all Rime profiles are temporary):

```sh
variant_dir=.build/dictionary/reproduce-C
mkdir -p "$variant_dir"
git archive a3fa578 Rime | tar -x -C "$variant_dir"
cp Tests/InputMethodTests/Fixtures/variant-c/roarkt_ai.dict.yaml "$variant_dir/Rime/"
git show 9df3960:Rime/roarkt_en.dict.yaml > "$variant_dir/Rime/roarkt_en.dict.yaml"
awk '{print} $0 == "  - luna_pinyin" {print "  - roarkt_ai"}' \
  "$variant_dir/Rime/roarkt_zh.dict.yaml" > "$variant_dir/dictionary.yaml"
mv "$variant_dir/dictionary.yaml" "$variant_dir/Rime/roarkt_zh.dict.yaml"
scripts/eval-candidates.sh "$variant_dir/Rime" .build/dictionary/reproduce-C-results
```

Expected result: daily 78/80, AI 53/60, development 24/40, sentence 17/20, total
172/200. The evaluator exits 0 because execution succeeds and total exceeds A;
**C fails the new AI ≥95% acceptance requirement**. No variant is adopted by this experiment.
The adjacent `candidate-variant-c.tsv` preserves exact outputs. The diagnostic
`candidate-variant-c-simplified.tsv` records the initial direct simplified import
(173/200, AI 52/60), which also fails acceptance.
