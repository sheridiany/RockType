# W-6 全简体试验 D（未采用）

2026-10-11：D 未通过冻结整句门槛和 RimeChecks，停止调整；产品仍为 C。
资源保存在 `Tests/InputMethodTests/Fixtures/variant-d/`，不是打包资源。

## 主词库派生

- 输入：当前仓库 `InputMethod/data/plum/luna_pinyin.dict.yaml`，SHA-256 `75bcf6eb3ff62b129882ed89cc22b2d80a5347aa72bcfa2ccc839bac298e7314`。
- 原频率：`InputMethod/data/plum/essay.txt`，SHA-256 `a6f8409c261e5d21bd78e6cbcde8f8e1ef7f68c07ff1c2692c07dd4ff4151cea`。这是仓库已有数据，既有来源追溯限制仍适用。
- 生成器：`swift scripts/dictionary/simplify-luna.swift <luna> <essay> <output> <collisions>`。只用 macOS Foundation 的 ICU `Hant-Hans`，不使用运行时 OpenCC。
- 为保持原量纲，先按 librime `EntryCollector::CreateEntry` 的规则将空权重/百分比解析为原繁体 essay 的绝对频率，再转换文本，对同一“词＋编码”权重求和。不同编码不合并。原始 70,732 条变为 67,548 条；合并 3,184 条，涉及 3,050 个键。
- 上游文件头完整保留，增加派生声明；LGPL-3.0，见 `LICENSES/rime-luna-pinyin/` 与 `THIRD_PARTY_NOTICES.md`。
- AI 词表仅转换文本列，保留 1,067 条术语的原权重和显式读音；未借本次试验重新校准。

## 人工复核与未完成清单

ICU 转换不等于逐词语义校正。完整碰撞清单在 `variant-d/collisions.tsv`。
已人工处理 `妳 → 你`（ICU 保留性别字形，本产品只保留通用“你”）；其读音权重仍按上述规则相加。

以下是复核发现、因验收失败停止而**尚未处理**的高频风险项，不宣称主词表语言质量验收完成：

| 原字/词 | 风险 | 后续人工处理方向 |
| --- | --- | --- |
| 著、显著、著作、统计显著性 | ICU 将著统一变成着，字表失去 `著 zhu`；AI 中的“统计显著性”因而缺字 | 按读音/词义保留著；不能全局把着改回著 |
| 乾、乾坤、乾隆 | ICU 单字转换可能丢失 qián 的字形区别 | 按编码核对 qián 与 gān；保留乾坤/乾隆，干净/干燥用干 |
| 瞭、瞭望、了解 | 瞭与了依词义区别 | 核对瞭望与了解的词形、读音 |
| 藉、借口、慰藉 | 藉/借不是所有语境均可互换 | 保留慰藉，核对借口等常用词 |
| 后/後、发/發/髮、里/裏/裡、余/餘 | 多个来源合并后频率相加改变排序 | 本试验只按要求相加，完整碰撞表可复核；没有按评测调权重 |

新 essay 中缺少以下 13 条原 `100%` AI 词项的频率：算力、机器学习、深度学习、强化学习、自然语言处理、技术方案、动态规划、时间复杂度、私钥、自动化测试、交互设计、界面设计、弹窗。另有“并发”800 < 2027、“周报”800 < 6066。检查已如实失败；没有把断言移除或修改权重来通过。

## 简体上游资源与许可

| 资源 | 仓库、固定 revision | 许可与 SHA-256 |
| --- | --- | --- |
| `essay-zh-hans.txt`（夹具内重命名 `essay.txt`，内容不改） | https://github.com/rime/rime-essay-simp ，`dc06d4c96ae72ad46b29e3aa824a5d1e8f721fd0` | 根目录 LICENSE：LGPL-3.0；数据 `93fc191743fc2b9b454a5cee0dde102afef1a566f4e7b32289f82580e4d8f3ac` |
| `zh-hans-t-essay-bgw.gram` | https://github.com/lotem/rime-octagram-data ，hans `f8ce3b534733e489a8470a7c2adf5a154e8ea069` | hans 根目录 LICENSE：LGPL-3.0；数据 `d3cb2438c1fdcd6a855dd6ca8f5c1060a29273c6b64c2c2c69af67cd71b6aa7e` |

octagram 主分支 `8ceef1b42eb77e86501382a52e85c309c0f2f04c` 的 README 明确指向 hans 分支供简体词库使用，并链接 LICENSE。选择 bgw 词模型，与 C 的 bgw 类型一致；未尝试 bgc 或其他变体。模型为上游不透明二进制，本任务核实其简体来源与文件摘要，未逐项解码审计内部 n-gram。简体 essay 与原频率表不是逐项对应，不能假设自动保留 C 的排序。

两份上游许可证原样保存于 `LICENSES/rime-essay-simp/LICENSE`、`LICENSES/rime-octagram-data/LICENSE`；LGPL 引用的 GPL 正文已有 `LICENSES/GPL-3.0.txt`。这些许可仅说明本次数据来源，不关闭原有预编译运行库的完整源码追溯问题。
