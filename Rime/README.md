# Rime 方案

RockType 使用全简体方案 D：`roarkt`（全拼）、`roarkt_flypy`（小鹤双拼），共享 `roarkt_zh` 词库和学习数据。英文词典 `roarkt_en` 不单独显示。

`roarkt_base` 从 Luna Pinyin 经系统 ICU Hant-Hans 派生，合并同词同编码权重，并校正语义歧义。`essay.txt` 由固定简体 essay 与原 essay 的简化结果取频率下限；有异体映射依据的同音词形再用原始简体 essay 频率裁决。八股文模型为 `zh-hans-t-essay-bgw`，搭配长度最大4、最小3；保留 `contextual_suggestions: true`。两套方案不再运行简繁转换、不提供繁体开关。包内不含旧 Luna、繁体 gram 或 OpenCC 转换资源。

MIT 自研 `roarkt_ai` 包含1,132条简体术语，114条显式拼音；其余用共享字表编码。通常在预置频率≥800时用100%继承，否则使用领域优先级800。R1b 校准埋点为5000、镜像为4000；再讨论/再确认/再评估/再检查/再验证/再沟通统一3000。新增开发、产品和协作搭配65条，保留原有日常同音词保护，不把评测整句写进词表。英文大小写、短语、模糊音、简拼、纠错、Shift、五候选和候选翻译行为保留。

**从 C 采用 D 时，原 `roarkt_zh.userdb` 的繁体学习键需要 t2s 迁移。** 由 pi-platform 的脚本配合 Claude 执行；本次开发没有访问或修改真实用户数据。

`scripts/test.sh` 在临时目录运行冻结评测及 RimeChecks。R1b 门槛为日常≥79/80、整句≥20/20、开发≥32/40、AI≥57/60，总计≥188/200；还逐项保护第四轮的184个命中及全部80项日常输出。冻结输入与期望的 SHA-256 由测试锁定。真实安装、迁移及键盘体验仍待人工验收。

来源、许可和生成命令见 [派生记录](../docs/dictionary-simplification.md)、[第三方声明](../THIRD_PARTY_NOTICES.md) 和 [SPEC-011](../specs/011-dictionary.md)。试验大资源仅在 `.build/`，本目录只放生产资源。
