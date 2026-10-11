# W-6 全简体管线试验

最新结果见 SPEC-011 的“W-6 第四轮”：D 已通过冻结评测与完整 RimeChecks并采用。生产必需资源提交在 `Rime/`；试验大资源及审计表只在 `.build/dictionary/w6/`。旧大夹具已从当前树移除，历史提交未重写。下文前三轮结论为历史记录。

## 来源与许可

- Luna 输入 SHA-256：`75bcf6eb3ff62b129882ed89cc22b2d80a5347aa72bcfa2ccc839bac298e7314`；原 essay：`a6f8409c261e5d21bd78e6cbcde8f8e1ef7f68c07ff1c2692c07dd4ff4151cea`。均在 `InputMethod/data/plum/`；Luna 的上游头完整保留，派生词表 LGPL-3.0。
- 简体 essay：`rime/rime-essay-simp@dc06d4c96ae72ad46b29e3aa824a5d1e8f721fd0` 的 `essay-zh-hans.txt`，重命名 `essay.txt`，内容不改；SHA-256 `93fc191743fc2b9b454a5cee0dde102afef1a566f4e7b32289f82580e4d8f3ac`。LGPL-3.0。
- 简体模型：`lotem/rime-octagram-data` hans `f8ce3b534733e489a8470a7c2adf5a154e8ea069` 的 bgw / bgc。该分支 LICENSE 为 LGPL-3.0。bgw SHA-256 `d3cb2438c1fdcd6a855dd6ca8f5c1060a29273c6b64c2c2c69af67cd71b6aa7e`。
- 上游 LICENSE 原样存于 `LICENSES/rime-essay-simp/`、`LICENSES/rime-octagram-data/`，完整 GPL 正文已有。既有预编译运行库的来源追溯限制不变。

## 复现

从固定 C 提交构造临时目录，生成词表并从固定上游下载模型，不触碰个人目录。准备脚本拒绝覆盖同名试验。

```sh
bash scripts/dictionary/prepare-trial.sh original bgw 5 2
bash scripts/eval-candidates.sh .build/dictionary/w6/trials/original/Rime .build/dictionary/w6/trials/original/results
# 第一轮，分别准备并评测四组：
bash scripts/dictionary/prepare-trial.sh r1-bgc-2 bgc 2 2
bash scripts/dictionary/prepare-trial.sh r1-bgc-5 bgc 5 2
bash scripts/dictionary/prepare-trial.sh r1-bgw-4 bgw 4 3
bash scripts/dictionary/prepare-trial.sh r1-bgw-penalty bgw 5 2
perl -0pi -e 's/collocation_min_length: 2/collocation_min_length: 2\n  collocation_penalty: -6\n  non_collocation_penalty: -18/' .build/dictionary/w6/trials/r1-bgw-penalty/Rime/roarkt{,_flypy}.schema.yaml
for name in r1-bgc-2 r1-bgc-5 r1-bgw-4 r1-bgw-penalty; do
  bash scripts/eval-candidates.sh ".build/dictionary/w6/trials/$name/Rime" ".build/dictionary/w6/trials/$name/results"
done
```

生成器使用系统 ICU Hant-Hans；原百分比/空权重先按原 essay 解析，再按词＋编码相加。70,732 → 67,548 条，3,050 个碰撞键。完整碰撞表由脚本生成到 `.build/`。人工统一妳→你；著/乾/瞭/藉待第三轮语义校正。
AI 文本列转换，读音与权重不动；第一轮仍有 13 个 `100%` 词缺少新 essay 频率、并发/周报频率下限和“著”字缺失的问题。

octagram 参数依据 `lotem/librime-octagram@57d18b9f58e5284bd891d559f6bdd16cf60341e9` 的 `src/octagram.cc`；只读取搭配长度及四种 penalty，没有 `grammar/weight`。本次运行日志确认加载所选模型；不以仅写入 YAML 作为参数有效性的证据。

第二轮复现：`bash scripts/dictionary/prepare-trial.sh r2-max bgw 4 3 max`，随后按相同命令评测该目录。`max` 只对同词同编码取原始解析频率最大值，不调整其他频率。

## 第三轮：语义与频率继承

```sh
for mode in semantics floor; do
  bash scripts/dictionary/prepare-trial.sh "r3-$mode" bgw 4 3 sum
  swift scripts/dictionary/correct-trial.swift ".build/dictionary/w6/trials/r3-$mode" InputMethod/data/plum "$mode"
  bash scripts/eval-candidates.sh ".build/dictionary/w6/trials/r3-$mode/Rime" ".build/dictionary/w6/trials/r3-$mode/results"
  # 预计失败，真实退出码 133；不修改任何断言。
  bash scripts/test-rime-capabilities.sh ".build/dictionary/w6/trials/r3-$mode/Rime"
done
```

- 主词表重新从原始 Luna 生成，保持 sum。按编码保留 `著 zhu`、`乾 qian`、`藉 ji`，恢复 `瞭 liao`；按词义校正乾坤/乾隆、瞭望、慰藉/蕴藉、借口/借助/凭借。54 条与纯 ICU 不同（包括妳→你），输出 67,549 条；明细只生成在本地 `corrections.tsv`。
- 两组均把简体上游 essay 残存的繁体用 ICU 规范化，同词用最大值，避免频率估计相加。AI 按最终预置词频统一使用 `100%`（≥800），缺失或不足800使用原领域优先级800；不对评测单题加词。
- `semantics` 的 essay 规范化后 239,164 条；`floor` 再对所有转换后的原 essay 词条取 `max(新频率, C原频率)`，得到438,486条。不同来源是频率估计，不是可直接相加的独立语料；此规则用于维持 C 的频率下限，不按评测逐词调权。
- `floor` 的派生 essay 同时来自已核实的 LGPL-3.0 简体上游与仓库原 essay；原 essay 的精确历史来源限制仍适用。数据仅在 `.build/`，未打包。
- bgc 数据 SHA-256：`c52deb56b1642e4f56a18926fffcb4b70385828f921bfac92c5ff4055cce5377`。

**三轮后停止，产品仍为 C。** 最接近交付的是 `r3-floor`：79/18/30/57，保留 C 的181条原命中；RimeChecks 在“链条→炼条”失败。源 essay 的“鍊條”和“鏈條”各2071，ICU 前者变成“炼条”，后者变成“链条”，两者同频；这是尚未处理的词义歧义，不能把评测达标视为全简体质量已通过。没有继续第四轮校正。`r3-semantics` 总分更高（186），但“现存→显存”仍失败。

## 第四轮（单独授权）：异体裁决与生产 D

第三轮停止结论为历史记录；第四轮评测和完整 RimeChecks 通过后，生产切换为 D。
本轮只做异体权重裁决，未改模型、grammar 参数、冻结期望或同音词断言。

复现（全程临时资源，不访问用户 profile）：

```sh
bash scripts/dictionary/prepare-trial.sh r4-variants bgw 4 3 sum
swift scripts/dictionary/correct-trial.swift .build/dictionary/w6/trials/r4-variants InputMethod/data/plum floor
swift scripts/dictionary/resolve-variants.swift .build/dictionary/w6/trials/r4-variants \
  .build/dictionary/w6/upstream/essay-simp/essay-zh-hans.txt \
  InputMethod/librime/deps/opencc/data/dictionary
bash scripts/eval-candidates.sh .build/dictionary/w6/trials/r4-variants/Rime .build/dictionary/w6/trials/r4-variants/results
bash scripts/test-rime-capabilities.sh .build/dictionary/w6/trials/r4-variants/Rime
```

### 裁决边界

- 第三轮生成器新增本地 `origins.tsv`，记录词条来源、原词形、显式编码（若有）和 ICU/语义校正结果，不改变第三轮生成资源。
- 以固定 OpenCC `556ed22496d650bd0b13b6c163be9814637970ae` 的 `TSPhrases.txt`（词组最长匹配）和 `TSCharacters.txt`（默认映射）作为异体依据。例如词组表明确给出“鍊條→链条”，不是把所有鍊/鏈语境或所有同音词混合。
- 同一映射结果内还需有共同编码：有显式读音时以显式读音为准，没有显式读音才使用实际单字表逐字读音交集。没有共享读音不裁决。审计表的 code 是一个共同读音见证，不是宣布该词的唯一/常用读音。
- 仅使用**未修改**的固定 `rime-essay-simp` 频率选词形；另一词形缺失或频率≤首选的1%时，将其各处现有权重上限设为1（原为0/1的不提高）；没有证据时保留，不按评测单题补丁。保留条目/读音，不删除单字导致其他词无法编码。
- 新 essay 没有对应频率，或两个词形都常用的组，不强行裁决。OpenCC 表只用于离线证据，生产无转换 filter 或相关数据依赖。

### 全量影响

| 统计项 | 数量 |
| --- | ---: |
| 来源记录（含原词形/显式读音，不是去重词数） | 753,384 |
| 映射后仍含不同 ICU 词形的组 | 1,551 |
| 有共同读音的组 / 词形对 | 1,445 / 1,472 |
| 有降权判定的组 | 1,110 |
| 标记低频词形 | 1,123 |
| 实际发生权重变化的不同词形 | 973 |
| 主字词表实际改动行 | 121 |
| essay 实际改动行 | 973 |
| AI 表实际改动行 | 0 |
| 合计改动记录 | 1,094 |

其余150个标记词形原权重已≤1，无实质变化。完整审计表与摘要为本地 `variant-audit.tsv` / `variant-summary.txt`，不放入 git。与第三轮逐行比较证实只改相同词形的权重为1，无删除/增词或编码修改。
“链条”在 essay-simp 中1049，“炼条”缺失；D 中链条保留2071，炼条由2071降为1。两套方案的原始日常同音词断言均通过。

### 生产文件与许可

生产主表67,549条，派生 essay 438,486条，简体AI 1,067条；只有生产资源进入 `Rime/`，中间资源与审计仍在 `.build/`。
Xcode 不再复制原 Luna、原 essay 或 OpenCC 数据阶段；打包脚本重建产物 SharedSupport，复制简体字表/essay/gram，防止构建目录残留。OpenCC 作为 librime 预编译依赖的代码许可仍保留，不声称重编译并移除了二进制内的 OpenCC。

| 最终资源 | SHA-256 |
| --- | --- |
| `Rime/roarkt_base.dict.yaml` | `dfcd7dcf9c08e28ff4a02e146872398ecdf9e6ff70d2c4d1e75982ac38477e9e` |
| `Rime/essay.txt` | `21aa427a686fafcfb49c3eb5b12fa70ffc7b3523773a2537b7ebadd8f3d8d281` |
| `Rime/zh-hans-t-essay-bgw.gram` | `d3cb2438c1fdcd6a855dd6ca8f5c1060a29273c6b64c2c2c69af67cd71b6aa7e` |
| OpenCC `TSCharacters.txt`（仅离线） | `6b5a0a799bea2bb22c001f635eaa3fc2904310f0c08addbff275477a80ecf09a` |
| OpenCC `TSPhrases.txt`（仅离线） | `504169029c43f7f234b8e2ae470720af3657675c5574ff8aa0feb257e1dc5ce2` |

Luna/essay 派生数据与简体gram为LGPL-3.0，AI为MIT，异体证据OpenCC为Apache-2.0；许可随输入法包附带。来源精确版本及未关闭的历史来源限制见 NOTICES 和 LICENSES/PROVENANCE.md。
D 正式采用后真实 userdb 仍需 pi-platform + Claude 执行 t2s 迁移；本任务未操作真实数据。
