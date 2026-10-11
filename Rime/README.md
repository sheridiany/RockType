# Rime 方案

RockType 输入方案：`roarkt`（全拼）、`roarkt_flypy`（小鹤双拼）、`roarkt_en`（英文词典，不单独显示）。显示名分别为「RockType」「RockType Shuangpin」。内部方案 ID 与用户词库名保持不变。

产品采用 SPEC-011 校准后的方案 C：原 `luna_pinyin` 繁体词库、预置八股文词频、八股文模型及 `contextual_suggestions: true`，通过原 `tw2s.json` 过滤链输出简体。两套方案共享中文词库与学习数据；模糊音、简拼、纠错、Shift、英文混输和候选翻译行为沿用原配置。

`roarkt_zh.dict.yaml` 额外导入 MIT 自研 `roarkt_ai`，共 1,067 条繁体术语。104 条显式指定多音字拼音，其余由 Rime 根据原字表编码。245 条已有高频词使用 `100%` 继承原预置词频，其他 822 条使用领域优先级 800，避免低绝对权重覆盖高频旧词。术语表不是用户文件提取结果。学习数据库继续使用原词库的繁体键，不应执行为简体主词库设计的迁移。

英文码为小写字母；上屏保留词条大小写与标点，例如 `finetune` → `fine-tune`、`mcp` → `MCP`。英文短语仍可用单引号输入。

`scripts/test-rime.sh` 与 `scripts/test-rime-capabilities.sh` 在临时目录验证部署和输入行为。`scripts/eval-candidates.sh [Rime资源目录] [报告目录]` 使用固定 200 条公开常识样例，输出首选命中率、与冻结基线的差异、部署耗时和 librime 按键刷新 P95；总命中数低于基线时退出 2。四类验收门槛由 `scripts/test.sh` 中的 SPM 测试锁定：日常 ≥78/80、整句 ≥17/20、开发 ≥29/40、AI ≥57/60。数据不来自用户文件，测试不读写真实 `~/Library/Rime`。

许可证及上游版本见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。词库资源随独立输入法打包，不链接到主 App。早期白霜试验已撤回，其词表与专用许可证不再打包；历史对照数据保存在测试夹具与 [SPEC-011](../specs/011-dictionary.md)。
