# SPEC-011 词库优化（输入法打磨 · 第一项）

- 阶段：打磨 P1（输入法）
- 覆盖需求：FR-A1、FR-A3、FR-A5、NFR-2
- 状态：Ready

## 目标

候选更准、更全：换上词频经过大语料重统计的开源中文词库；补齐 AI / 开发领域词；按用户本人的习惯定制。**产品打包**与**用户个人数据**严格分开：个人词表只写入用户本机 `~/Library/Application Support/RoarkT/Rime`，不进安装包、不进 git。

## 调研结论（2026-10-11）

| 词库 | 许可 | 结论 |
| --- | --- | --- |
| 白霜拼音 rime-frost（基于雾凇，约 7.45 亿字语料重统计字频词频） | GPL-3.0（实施时须以上游 LICENSE 文件核实） | **采用**为主词库：`cn_dicts/8105`、`base`、`ext`、`tencent`、`others`（如有）按需取舍 |
| 雾凇拼音 rime-ice | GPL-3.0 | 不并用（白霜已是其改进版，避免重复词条与词频冲突） |
| 万象 rime-wanxiang 语言模型 `.gram` | 未明确（第三方显示 CC-BY-4.0，未核实） | **不打包**；记入后续“可选下载语言模型”候选 |
| 现用 八股文 `zh-hant-t-essay-bgw.gram`（rime-octagram-data） | 随 Squirrel/plum | 先保留；评估其与简体词库的配合，若明显变差则在规格问题节报告 |

## 产品层（打包进输入法）

1. **主词库替换**：`Rime/roarkt_zh.dict.yaml` 改为 `import_tables` 引入白霜词库（放 `Rime/cn_dicts/`，保留上游文件头与许可说明，`THIRD_PARTY_NOTICES.md` 补充），替代现在的 `luna_pinyin`（繁体）+ 简化转换。方案 `roarkt` 与 `roarkt_flypy` 同步调整：
   - 白霜为简体词库：去掉繁→简转换链，或保留并确保无副作用；以“输出简体、无错转”为准。
   - 保留现有模糊音、简拼、纠错、Shift、英文混输、候选翻译 Lua、五候选等全部行为（SPEC-003 的 RimeChecks 必须继续通过）。
   - 参考白霜/雾凇自身的 schema 中对其词库所需的 `speller/algebra`、`translator` 设置（如 `enable_word_completion`、`contextual_suggestions`）按需采用，并说明取舍。
2. **AI / 开发领域词库** `Rime/roarkt_ai.dict.yaml`（新建，MIT，自研）：约 800–1500 条常用中文术语，例如 大模型、提示词、智能体、多智能体、微调、预训练、推理、检索增强生成、向量数据库、嵌入、词元、上下文窗口、幻觉、对齐、蒸馏、量化、多模态、思维链、工具调用、函数调用、知识库、工作流、算力、显存、提示工程、评测、基准测试、开源模型、端侧模型、文生图、语音识别、令牌、并发、限流、灰度、埋点、验收、需求文档、技术方案、接口、联调、部署、回滚、前端、后端、组件、状态管理 等；覆盖 AI、编程、产品、设计、办公协作。词条不写编码（由 Rime 按单字读音自动编码），多音字有歧义的词显式写编码。权重设置让领域词在常见同音词之前但不压过最常用日常词（用评测集校准）。
3. **英文与混输**：扩充 `Rime/roarkt_en.dict.yaml`（参考 `../RoType/scripts/data/english-technical.tsv` 与 `generate-english-dict.py` 的做法）加入 AI / 开发英文词：LLM、RAG、MCP、Agent、prompt、token、embedding、fine-tune、Claude、GPT、Gemini、Codex、Cursor、Copilot、OpenAI、Anthropic、SwiftUI、Xcode、GitHub、API、SDK、JSON、YAML、Kubernetes 等，保持大小写原样上屏。
4. **评测集**：`Tests/InputMethodTests/Fixtures/candidate-eval.tsv`（编码 → 期望首选），覆盖日常高频、产品开发与 AI 术语、整句（约 200 条）；`scripts/eval-candidates.sh` 用 librime 跑出替换前/后的首选命中率对比，写入本规格“验收”。替换后命中率不得低于替换前，AI 领域条目应显著提升。

## 个人层（只在用户本机，脚本化、可重复执行、可回滚）

5. **学习词迁移为简体**：用户已导入的 RoType 学习词（`roarkt_zh.userdb`，繁体键）在主词库换为简体后需转换：导出 → OpenCC 繁转简（t2s）→ 导入新 userdb。脚本 `scripts/personal/migrate-userdb-simplified.sh`，执行前完整备份到 `~/Library/Application Support/RoarkT/Rime/roarkt-backups/<时间>/`。由 Claude 在合并后执行，agent 只实现与用临时目录测试。
6. **个人习惯词表**：脚本 `scripts/personal/build-personal-dict.py`：从用户本机文本中统计高频中文词与英文术语，**来源仅限**用户明确允许的目录（默认 `~/Repos/**/*.md` 与 `~/Repos/**/*.swift` 注释/字符串，排除 `node_modules`、`.build`、`.git`），与主词库比对，产出主词库缺失或排序靠后的词，写 `~/Library/Application Support/RoarkT/Rime/roarkt_personal.dict.yaml`（文件头注明“个人词表，由 RoarkT 生成”），并通过 `roarkt.custom.yaml` / `roarkt_flypy.custom.yaml` 的 patch 挂载（与 SPEC-004 设置同步生成的 custom 文件合并，不覆盖用户手写内容）。脚本只输出统计摘要，不打印原文；不读取聊天记录、浏览器、邮件等其他数据。产物不进 git（`.gitignore`）。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| W-1 | 评测集与评测脚本，先跑出现状基线 | pi-ui | 未开始 |
| W-2 | 引入白霜词库并调整两套方案，回归 RimeChecks | pi-ui | 未开始 |
| W-3 | AI / 开发中文词库与英文扩充，评测校准权重 | pi-ui | 未开始 |
| W-4 | 个人层脚本：学习词简体迁移、个人习惯词表（含临时目录测试） | pi-platform | 未开始 |
| W-5 | Claude 在本机执行个人层脚本、安装、用户试打 | Claude + 用户 | 未开始 |

**文件所有权**：pi-ui：`Rime/`、`THIRD_PARTY_NOTICES.md`、`LICENSES/`、`scripts/eval-candidates.sh`、`Tests/InputMethodTests/Fixtures/`、评测相关测试；pi-platform：`scripts/personal/`、其测试、`.gitignore` 一行。两人都不改 `InputMethod/sources`（pi-ime 正在恢复 RoType 视觉）。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 上游许可证核实并随包附带 | 检查 LICENSE 文件与 NOTICES | 未运行 | |
| 首选命中率：替换后 ≥ 替换前；AI 条目显著提升 | `scripts/eval-candidates.sh` | 未运行 | |
| RimeChecks 全部通过（模糊音、简拼、纠错、Shift、英文、学习） | `scripts/test.sh` | 未运行 | |
| 部署时间与打字延迟无明显退化 | 计时 + 人工 | 未运行 | |
| 学习词迁移后常用词仍优先 | 本机试打 | 待人工验证 | |
| 个人词表不进 git、不打印原文 | 检查 | 未运行 | |

## 进度

## 问题
