# Third-party notices

`Rime/roarkt_en.dict.yaml` adapts Hermit Dave's [FrequencyWords English 2018 corpus](https://github.com/hermitdave/FrequencyWords/blob/525f9b560de45753a5ea01069454e72e9aa541c6/content/2018/en/en_50k.txt), derived from OpenSubtitles2018. The upstream [license declaration](https://github.com/hermitdave/FrequencyWords/blob/525f9b560de45753a5ea01069454e72e9aa541c6/README.md#license) licenses **content under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)** and generator code under MIT. This adapted dictionary remains CC BY-SA 4.0 as a separate data asset; it is not relicensed under the repository's MIT license. Attribution, source, license link and modification details are retained here and in the dictionary header.

Modifications retained with the dictionary: clean the pinned corpus using `Rime/lua/roarkt_english_blocklist.lua`, explicit speech-noise exclusions, three-or-more repeated-letter rejection, and a below-500-occurrences cutoff for words absent from the reference/curated tables (including recognized inflections). Select 30,000 cleaned ASCII alphabetic words using their original corpus counts, preserve the existing ten entries and weights, and merge 289 authored technical/product entries with fixed ranking priority 15,000 (not a measured corpus frequency). Proper-name capitalization follows case-only entries in the reference; `I` and `London` are explicit corrections. Result: 30,196 entries. The authored entries are original; the resulting adapted dictionary remains CC BY-SA 4.0.

The generator pins corpus revision `525f9b560de45753a5ea01069454e72e9aa541c6` and SHA-256 `5351ff405b1126ef555791dd4d9798a48e3e9a501a9fc481a9da957752cfb458`. It is not included in this migration. rime-ice's GPL-3.0 English dictionary was evaluated but not copied: its main word list has no frequency column.

The capitalization/spelling reference is the macOS `/usr/share/dict/words` symlink to `web2` (Webster's Second International word list), SHA-256 `be41ad97963bf8dabedd5871d5d691596175269d540956b0f9965a885c2bbab9`. Its local `/usr/share/dict/README` credits James A. Woods and records the supplier's declaration that the 1934 copyright has lapsed. The same provenance declaration is preserved in the official [FreeBSD dictionary README](https://github.com/freebsd/freebsd-src/blob/72f0bc868bf00586cba1e50057d8f1998b4abe80/share/dict/README). The word list is used as a public-domain lexical reference on that documented supplier declaration; the full reference is not redistributed. The current FreeBSD `web2` has subsequent edits and a different hash, so reproduction requires the pinned macOS snapshot, not an unpinned replacement.

`Rime/roarkt_flypy.schema.yaml` adapts the Xiaohe algebra and preedit rules from the official [rime-double-pinyin](https://github.com/rime/rime-double-pinyin) project. That schema is GPL-3.0-or-later; upstream authors are retained in its header. The complete license is in `LICENSES/GPL-3.0.txt`.

`Rime/cn_dicts/{8105,base,ext,others}.dict.yaml` is adapted from
[gaboolic/rime-frost](https://github.com/gaboolic/rime-frost/tree/64d24e89341aee133c0ad0f09b5f47a695e3d508),
revision `64d24e89341aee133c0ad0f09b5f47a695e3d508` (retrieved 2026-10-11).
The actual upstream `LICENSE` was checked before import: GNU GPL version 3;
its verbatim text is retained in `LICENSES/rime-frost-GPL-3.0.txt` and packaged with the input method.
These data remain GPL-3.0, separate from the MIT application. Upstream headers
retain attribution to rime-ice, the character/frequency sources, and constituent
word lists. Modifications on 2026-10-11: exclude 12 base and 28 ext entries containing
`洛克` to meet this repository's literal legacy-identifier guard (including unrelated
proper names such as 巴洛克); all other data and weights are unchanged. `8105` and
`others` are verbatim. The optional zero-weight Tencent list, larger character tables,
correction list, cell dictionaries, upstream Lua and upstream schemas are not imported.
RoarkT retains its own keyboard behavior and the existing octagram model.
