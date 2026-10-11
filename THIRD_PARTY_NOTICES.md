# Third-party notices

`Rime/roarkt_en.dict.yaml` adapts Hermit Dave's [FrequencyWords English 2018 corpus](https://github.com/hermitdave/FrequencyWords/blob/525f9b560de45753a5ea01069454e72e9aa541c6/content/2018/en/en_50k.txt), derived from OpenSubtitles2018. The upstream [license declaration](https://github.com/hermitdave/FrequencyWords/blob/525f9b560de45753a5ea01069454e72e9aa541c6/README.md#license) licenses **content under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)** and generator code under MIT. This adapted dictionary remains CC BY-SA 4.0 as a separate data asset; it is not relicensed under the repository's MIT license. Attribution, source, license link and modification details are retained here and in the dictionary header.

Modifications retained with the dictionary: clean the pinned corpus using `Rime/lua/roarkt_english_blocklist.lua`, explicit speech-noise exclusions, three-or-more repeated-letter rejection, and a below-500-occurrences cutoff for words absent from the reference/curated tables (including recognized inflections). Select 30,000 cleaned ASCII alphabetic words using their original corpus counts, preserve the existing ten entries and weights, and merge 289 authored technical/product entries with fixed ranking priority 15,000 (not a measured corpus frequency). Proper-name capitalization follows case-only entries in the reference; `I` and `London` are explicit corrections. Result: 30,196 entries. The authored entries are original; the resulting adapted dictionary remains CC BY-SA 4.0.

The generator pins corpus revision `525f9b560de45753a5ea01069454e72e9aa541c6` and SHA-256 `5351ff405b1126ef555791dd4d9798a48e3e9a501a9fc481a9da957752cfb458`. It is not included in this migration. rime-ice's GPL-3.0 English dictionary was evaluated but not copied: its main word list has no frequency column.

The capitalization/spelling reference is the macOS `/usr/share/dict/words` symlink to `web2` (Webster's Second International word list), SHA-256 `be41ad97963bf8dabedd5871d5d691596175269d540956b0f9965a885c2bbab9`. Its local `/usr/share/dict/README` credits James A. Woods and records the supplier's declaration that the 1934 copyright has lapsed. The same provenance declaration is preserved in the official [FreeBSD dictionary README](https://github.com/freebsd/freebsd-src/blob/72f0bc868bf00586cba1e50057d8f1998b4abe80/share/dict/README). The word list is used as a public-domain lexical reference on that documented supplier declaration; the full reference is not redistributed. The current FreeBSD `web2` has subsequent edits and a different hash, so reproduction requires the pinned macOS snapshot, not an unpinned replacement.

`Rime/roarkt_flypy.schema.yaml` adapts the Xiaohe algebra and preedit rules from the official [rime-double-pinyin](https://github.com/rime/rime-double-pinyin) project. That schema is GPL-3.0-or-later; upstream authors are retained in its header. The complete license is in `LICENSES/GPL-3.0.txt`.

The menu icon generator/diagnostic checks and native voice HUD (`RoarkTVoiceHUD`, waveform and rendering checks) adapt RoType's MIT sources. Copyright (c) 2026 RoType contributors; the original license is retained in `LICENSES/LICENSE-RoType-MIT.txt`. Product symbols and labels are renamed; the existing voice lifecycle, XPC and Secure Input boundaries remain RockType's. Input method panels remain GPL v3 within `InputMethod/`, separate from these MIT sources.

## Distributed components

This inventory covers the main app, the separate GPL input method, the translation helper and the voice worker. License texts are shipped in each app's `Contents/Resources/Licenses/`. The MIT programs do not link to the input method. Original copyright notices are retained; copied MIT portions in the input method retain `Squirrel/LICENSE.translation.txt`, and the shared voice implementation retains `Voice/LICENSE.md`.

| Component / upstream | License | Included notice |
| --- | --- | --- |
| Modified [Squirrel](https://github.com/rime/squirrel) input method | GPL-3.0-or-later | `Squirrel/LICENSE.txt`, `GPL-3.0.txt`, `GPL-SOURCE.md` |
| [librime](https://github.com/rime/librime), submodule a251145d3aafa33871824a40bbec04c966bd8b56 (1.16.0) | BSD-3-Clause | `librime/LICENSE` |
| [plum](https://github.com/rime/plum), submodule 4c28f11f451facef809b380502874a48ba964ddb; includes the bundled rime-install script | LGPL-3.0 | `plum/LICENSE` + `GPL-3.0.txt` |
| [librime-lua](https://github.com/hchunhui/librime-lua), [librime-octagram](https://github.com/lotem/librime-octagram), [librime-predict](https://github.com/rime/librime-predict) | BSD-3-Clause | Each named license directory |
| [Lua](https://github.com/lua/lua) | MIT | `lua/LICENSE`, from Lua 5.4.8 `lua.h` |
| [Boost](https://github.com/boostorg/boost) | BSL-1.0 | `boost/LICENSE_1_0.txt` |
| [glog](https://github.com/google/glog), [LevelDB](https://github.com/google/leveldb) | BSD-3-Clause | `glog/COPYING`, `leveldb/LICENSE` |
| [marisa-trie](https://github.com/s-yata/marisa-trie) | BSD-2-Clause (selected from upstream BSD/LGPL dual license) | `marisa-trie/COPYING.md` |
| [OpenCC](https://github.com/BYVoid/OpenCC) code and conversion dictionaries | Apache-2.0 | `opencc/LICENSE` |
| [yaml-cpp](https://github.com/jbeder/yaml-cpp) | MIT | `yaml-cpp/LICENSE` |
| [Rime Luna Pinyin](https://github.com/rime/rime-luna-pinyin), [essay](https://github.com/rime/rime-essay), [prelude](https://github.com/rime/rime-prelude) data | LGPL-3.0 | Named directories + `GPL-3.0.txt`; existing upstream dictionary header credits retained |
| [Rime double-pinyin](https://github.com/rime/rime-double-pinyin) Xiaohe rules | GPL-3.0-or-later | `GPL-3.0.txt`; attribution in `Rime/roarkt_flypy.schema.yaml` |
| FrequencyWords / OpenSubtitles English data, adapted as described above | CC-BY-SA-4.0 | `CC-BY-SA-4.0.txt` |
| [Sparkle](https://github.com/sparkle-project/Sparkle) 2.8.0, revision 9a1d2a19d3595fcf8d9c447173f9a1687b3dcadb | MIT and bundled dependency notices | `Sparkle/LICENSE` includes bsdiff, sais-lite, Ed25519 and helper notices |
| [MLX Swift](https://github.com/ml-explore/mlx-swift), [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm), [MLX Audio Swift](https://github.com/Blaizzy/mlx-audio-swift) | MIT | `Voice/mlx-swift/`, `Voice/mlx-swift-lm/`, `Voice/mlx-audio-swift/` |
| MLX Swift vendored MLX, mlx-c, fmt, nlohmann/json, metal-cpp | MIT / upstream notices | `Voice/mlx-swift/Source/Cmlx/` retains each bundled license |
| Apple Swift ASN.1, Collections, Crypto, Numerics, Syntax | Apache-2.0 with Swift runtime library exception | `Voice/swift-*/LICENSE.txt`; upstream NOTICE files included where present |
| Hugging Face Swift HuggingFace, Jinja, Transformers | Apache-2.0 | `Voice/swift-huggingface/`, `Voice/swift-jinja/`, `Voice/swift-transformers/` |
| [EventSource](https://github.com/mattt/EventSource), [yyjson](https://github.com/ibireme/yyjson) | MIT | `Voice/EventSource/LICENSE.md`, `Voice/yyjson/LICENSE` |

Voice dependency revisions are pinned in `Services/VoiceWorker/Package.resolved`; the matching lockfile is included as `Licenses/Voice/Package.resolved`. Some packages are build-time or transitive dependencies; notices are included conservatively for the entire resolved dependency graph. Model weights are not in the installer. The user downloads `mlx-community/Qwen3-ASR-0.6B-8bit` or `mlx-community/Qwen3-ASR-1.7B-8bit` separately; model repository terms continue to apply.

## Release provenance and outstanding source checks

`LICENSES/PROVENANCE.md` records the precise notice-source revisions used in this audit. For librime dependencies these are the commits pinned by librime 1.16.0. The shipped Luna Pinyin dictionary is byte-identical to upstream revision 56b934b099dfbeab842320f13aa8b461a6ab3e42 (SHA-256 75bcf6eb3ff62b129882ed89cc22b2d80a5347aa72bcfa2ccc839bac298e7314).

The repository contains prebuilt universal librime and plugin binaries. Their plugin build revisions and full static dependency bill of materials are not recorded. The current essay data also differs from upstream HEAD. Supplying present upstream license texts does not prove the provenance of those binaries/data. Before public distribution, the release owner must recover the exact build inputs or rebuild from pinned source, reconcile any additional notices, and publish the matching complete source. These checks remain open; this inventory is not a claim that source-distribution acceptance has passed. See `GPL-SOURCE.md`.

## RockType authored domain vocabulary (2026-10-11)

`Rime/roarkt_ai.dict.yaml` contains 1,067 original Chinese terms across AI,
software development, product, design and collaboration, licensed under MIT.
It is not extracted from user files or copied from upstream domain dictionaries.
The source asset remains MIT; it is imported into the GPL input method's combined
Rime dictionary. Rime auto-encodes ordinary entries, with 104 explicit polyphonic
readings. Terms use traditional text for the existing Luna Pinyin/octagram pipeline,
with simplified output supplied by its original OpenCC filter. The weight `100%`
preserves existing preset frequencies for 245 entries; the other 822 use authored
priority 800. No upstream frequency table is copied into this MIT asset.

The English dictionary adds 65 entries and updates 19 existing entries for canonical
case or technical priority, bringing the total to 30,261. The curation follows the
previous documented convention: lowercase alphabetic lookup codes, original output
case and punctuation (`finetune` → `fine-tune`), priority 15,000 while preserving
higher existing weights. This original contribution does not change the combined
English data asset's CC-BY-SA-4.0 license or its upstream attribution.
