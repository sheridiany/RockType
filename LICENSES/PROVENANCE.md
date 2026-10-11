# License source provenance

Notice snapshots only; plugin/source revisions below do not assert that the existing prebuilt binaries were built from those revisions. See THIRD_PARTY_NOTICES.md and GPL-SOURCE.md.

| Notice source | Revision |
| --- | --- |
| glog | 7b134a5c82c0c0b5698bb6bf7a835b230c5638e4 |
| leveldb | 99b3c03b3284f5886f9ef9a4ef703d57373e61be |
| marisa-trie | 3e87d53b78e15f2f43783d5e376561a8c9722051 |
| opencc | 556ed22496d650bd0b13b6c163be9814637970ae |
| yaml-cpp | 2f86d13775d119edbb69af52e5f566fd65c6953b |
| librime-lua | 6da5d6cedb853380ed1b5b9b6979cb1a9c028353 |
| librime-octagram | 57d18b9f58e5284bd891d559f6bdd16cf60341e9 |
| librime-predict | 920bd41ebf6f9bf6855d14fbe80212e54e749791 |
| rime-luna-pinyin | 56b934b099dfbeab842320f13aa8b461a6ab3e42 |
| rime-essay | 054920de4f54c9e5994276a96a4fc2a35cb51aa3 |
| lua | 6e22fedb74cf0c9b6656e9fce8b7331db847c605 |
| creative-commons | a0dac18d1a773b4cdb7d8dd5d9bf4efab7901030 |
| boost | d6245cc84c0bf429d0f20eb157cfd8959da21243 |

Creative Commons text: official creativecommons/cc-legal-tools-data, docs/licenses/by-sa/4.0/legalcode.txt. Lua text: license comment in lua/lua v5.4.8 lua.h. Voice notices: the revisions in Voice/Package.resolved, including vendored MLX dependencies. Sparkle: official 2.8.0 binary artifact LICENSE. Squirrel notices: repository InputMethod/LICENSE.txt and LICENSE.translation.txt. Original copyright attributions are intentionally preserved.

Rime prelude notice revision: `082425ea0684bca36474415d4a0e8db9b016487e` (https://github.com/rime/rime-prelude).

## W-6 production D data (2026-10-11)

- Simplified essay source: `rime/rime-essay-simp@dc06d4c96ae72ad46b29e3aa824a5d1e8f721fd0`, LGPL-3.0. Production `Rime/essay.txt` is a modified derivative combined with the existing essay's simplified frequency floor, then variant arbitration; the older essay provenance caveat above remains.
- Simplified gram: `lotem/rime-octagram-data` hans `f8ce3b534733e489a8470a7c2adf5a154e8ea069`, LGPL-3.0, `zh-hans-t-essay-bgw.gram` copied unchanged.
- Offline variant evidence: the existing pinned OpenCC `556ed22496d650bd0b13b6c163be9814637970ae` `TSPhrases.txt` and `TSCharacters.txt`, Apache-2.0. Tables are not packaged as runtime conversion resources; attribution/license retained.
- Luna derivative: source revision/hash above, macOS ICU Hant-Hans, code-preserving merge and semantic corrections, then essay-simp-based variant weight cap. Full generation and hashes: `docs/dictionary-simplification.md`.
