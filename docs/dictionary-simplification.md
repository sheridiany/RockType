# W-6 全简体管线试验

最新结果见 SPEC-011 的“三轮迭代”。试验大资源只在 `.build/dictionary/w6/`，git 只保留生成器、许可、文档和评测结果；若最终采用 D，才提交生产资源。旧大夹具已从当前树移除，历史提交未重写。

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
