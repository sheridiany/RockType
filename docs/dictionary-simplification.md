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
