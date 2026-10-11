# Rime 方案

RockType 输入方案：`roarkt`（全拼）、`roarkt_flypy`（小鹤双拼）、`roarkt_en`（英文词典，不单独显示）。显示名分别为「RockType Pinyin」「RockType Shuangpin」。内部方案 ID 与用户词库名保持不变。

`roarkt_zh.dict.yaml` 导入固定版本白霜的 `cn_dicts/8105`、`base`、`ext`、`others`，以及 MIT 自研的 `roarkt_ai`。中文工厂词库直接输出简体，不再使用繁转简过滤链，也不再导入 `luna_pinyin` 或预置繁体 essay 词汇。两套方案共享中文词库与学习数据。

仍使用当前 librime 的默认配置、标点、键绑定、Lua 插件和八股文模型。旧繁体模型仅保留造句；关闭已提交上下文的候选重排，原因和实测结果见 [SPEC-011](../specs/011-dictionary.md)。学习数据由个人层脚本另行处理，工厂资源部署不负责迁移用户数据。

英文码为小写字母；上屏保留词条大小写与标点，例如 `finetune` → `fine-tune`、`mcp` → `MCP`。英文短语仍可用单引号输入。

`scripts/test-rime.sh` 与 `scripts/test-rime-capabilities.sh` 在临时目录验证部署和输入行为。`scripts/eval-candidates.sh [Rime资源目录] [报告目录]` 使用固定 200 条公开常识样例，输出首选命中率、与冻结基线的差异、部署耗时和 librime 按键刷新 P95；总命中数低于基线时退出 2。数据不来自用户文件，测试不读写真实 `~/Library/Rime`。

许可证及上游版本见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。词库资源与许可随输入法打包，不链接到主 App。
