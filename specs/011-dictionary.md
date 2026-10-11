# SPEC-011 词库优化（输入法打磨 · 第一项）

- 阶段：打磨 P1（输入法）
- 覆盖需求：FR-A1、FR-A3、FR-A5、NFR-2
- 状态：Ready

## 目标

候选更准、更全：换上词频经过大语料重统计的开源中文词库；补齐 AI / 开发领域词；按用户本人的习惯定制。**产品打包**与**用户个人数据**严格分开：个人词表只写入用户本机 `~/Library/Rime`，不进安装包、不进 git。

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

5. **学习词迁移为简体**：用户已导入的 RoType 学习词（`roarkt_zh.userdb`，繁体键）在主词库换为简体后需转换：导出 → OpenCC 繁转简（t2s）→ 导入新 userdb。脚本 `scripts/personal/migrate-userdb-simplified.sh`，执行前完整备份到 `~/Library/Rime/roarkt-backups/<时间>/`。由 Claude 在合并后执行，agent 只实现与用临时目录测试。
6. **个人习惯词表**：脚本 `scripts/personal/build-personal-dict.py`：从用户本机文本中统计高频中文词与英文术语，**来源仅限**用户明确允许的目录（默认 `~/Repos/**/*.md` 与 `~/Repos/**/*.swift` 注释/字符串，排除 `node_modules`、`.build`、`.git`），与主词库比对，产出主词库缺失或排序靠后的词，写 `~/Library/Rime/roarkt_personal.dict.yaml`（文件头注明“个人词表，由 RoarkT 生成”），并通过 `roarkt.custom.yaml` / `roarkt_flypy.custom.yaml` 的 patch 挂载（与 SPEC-004 设置同步生成的 custom 文件合并，不覆盖用户手写内容）。脚本只输出统计摘要，不打印原文；不读取聊天记录、浏览器、邮件等其他数据。产物不进 git（`.gitignore`）。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| W-1 | 评测集与评测脚本，先跑出现状基线 | pi-ui | 未开始 |
| W-2 | 引入白霜词库并调整两套方案，回归 RimeChecks | pi-ui | 未开始 |
| W-3 | AI / 开发中文词库与英文扩充，评测校准权重 | pi-ui | 未开始 |
| W-4 | 个人层脚本：学习词简体迁移、个人习惯词表（含临时目录测试） | pi-platform | 脚本及临时目录测试完成；设置同步衔接待 Claude 决定 |
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
| 个人词表不进 git、不打印原文 | 忽略规则 + 合成数据 CLI 检查 | 通过（W-4 临时目录范围） | `Tests/PersonalScriptsTests/`；未读取真实个人文本 |

## 进度

### W-4 脚本与临时目录验收证据（2026-10-11）

- 已按后续通知在当前 `agent/platform` worktree 先后快进合入 `main@9b197ce`、`main@6b0081f`，未切分支、未修改主仓库；新增用户可见名称统一为 **RockType**，内部 `roarkt*`、SPM 模块名不改。
- `scripts/personal/migrate-userdb-simplified.sh` / `migrate_userdb.py`：显式目标 + 离线确认；独立进程持有 LevelDB POSIX 锁；完整 profile 备份（排除备份目录自身）→ 副本导出 → OpenCC t2s 只转换词条 → 同词同编码合并次数 → 空库导入及再导出核对 → 替换。支持备份 ID 回滚；后续学习导致库变化则拒绝覆盖。转换失败、活动数据库或符号链接均不改原库。
- `scripts/personal/build-personal-dict.py`：默认仅统计，需显式授权来源；Markdown 全文、Swift 注释/字符串，跳过插值内容、代码标识符、符号链接、隐藏目录及 `.git` / `.build` / `node_modules`。系统 NaturalLanguage 分词，递归读取主词库 import_tables 去重，仅输出缺失词，默认最少 3 次、最多 1500 条、权重上限 100。生成中英文个人词典与英文编译依赖 schema；两套 custom 保留原字节/注释，仅插入独立 patch，中文及英文仍沿用原 userdb。
- 两套 custom 预检后发布；重复执行无变化不写入；原文件有同路径自定义、重复键、锚点等歧义时拒绝，避免猜测用户意图。备份及回滚覆盖个人层 5 个文件，后续手改导致摘要不符则拒绝回滚。普通发布异常会还原已写文件；强制中断/断电不具备跨文件事务保证，保留备份供人工恢复。
- 新增 `Tests/PersonalScriptsTests/`，通过 Package.swift 的 `RoarkTPersonalScriptsTests` 接入 `scripts/test.sh`，不修改其他 agent 的测试或产品资源。`.gitignore` 增加一行 `roarkt_personal*.yaml`，覆盖所有个人词典及 schema。
- 本地依赖许可证已核实：现有 librime BSD-3-Clause；PyYAML 6.0.3 MIT；OpenCC `8cf737a4e193db27d675b2ce9867d84aace33745` 的上游 LICENSE 为 Apache-2.0。OpenCC 仅 clone/构建于 `.build/vendor/OpenCC/`，无安装、无源码复制或克隆目录提交。白霜许可与产品词库打包仍属 W-2。

| 验证命令 / 数据 | 结果与真实退出码 |
| --- | --- |
| OpenCC 初次 CMake 配置（默认 SDK） | 失败，1；默认 macOS 27 SDK 的 `arm64e.x1` 与本机链接器不匹配 |
| `cmake -S .build/vendor/OpenCC -B .build/vendor/OpenCC/build -DCMAKE_OSX_SYSROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk -DENABLE_TESTING=OFF -DBUILD_DOCUMENTATION=OFF` 及 `cmake --build .build/vendor/OpenCC/build -j 8` | 通过，组合命令 0；只构建未安装 |
| `python3 -B Tests/PersonalScriptsTests/checks.py` | 通过，0；11 个临时目录用例。开发时曾发现重复执行增加空行、英文词典缺少 schema 编译依赖，均已修正并通过真实部署回归 |
| `scripts/test.sh`（最终基于 `6b0081f`） | 通过，0；153 个 Swift Testing 测试及 Rime 部署/能力、输入法 session/面板、AppShell 检查；新增测试只操作临时目录 |
| 中间一轮 `scripts/test.sh` | 失败，1；现有 `M3IntegrationTests.swift:57` 未等到 `.done`，随后索引越界。该测试只等待固定 30 次 yield；未改其代码。W-4 的 SPM 包装改为异步等待子进程，避免占用协作线程；后续完整重跑通过，不声称已修复 M3 的调度不稳定 |
| `bash -n scripts/personal/migrate-userdb-simplified.sh`、`git diff --check` | 通过，各 0 |
| `git check-ignore --no-index Rime/roarkt_personal.dict.yaml Rime/roarkt_personal_en.dict.yaml Rime/roarkt_personal_en.schema.yaml` | 通过，0；三个产物均被忽略 |
| 迁移合成数据 | 3 条输入，2 条发生繁转简，1 次同编码碰撞，2 条输出；提交次数分别为 10、5；重复执行不替换，回滚的原数据库 SHA-256 一致 |
| 个人词表合成数据 | 扫描 2 文件、5 个不同词项；输出缺失中文 1 条、英文 3 条；已知词、代码标识符、排除目录及符号链接内容未进入词典，stdout/stderr 不含词条 |
| 真实 librime 部署与候选 | 两套工厂方案在临时 profile 部署成功，中文/英文个人词表均编译；全拼、小鹤各查到合成中文词和保留大小写的英文词，4 次候选探测通过 |

- 完整使用说明、依赖准备和回滚命令：`scripts/personal/README.md`。PyYAML/Python 只用于规格明确要求的开发脚本，不加入 App 运行时或安装包。
- 未运行：真实 `~/Library/Rime` 迁移、真实用户源码扫描、安装/注册/启动输入法、用户试打、整包构建签名。首选命中率前后评测属于 W-1/W-3，本任务没有该数据；上述 4 次候选探测仅证明挂载有效，不代表排名或输入延迟验收。
- 待人工验证：简体迁移后真实常用词排序、中文分词与多音字质量、实际新增词权重。`--export` 不保留删除标记及完整学习时间元数据，不能声称数据库学习状态逐字段无损；原库备份可回滚。

## 问题

1. **W-4 / SPEC-004 衔接需 Claude 决定**：设置模块当前整份重写 custom，并要求首行是自己的生成标记。个人脚本保留已有设置和手写内容，但加独立首行标记，使设置模块拒绝覆盖并提示冲突，防止无声删掉个人 patch。后续需由设置模块所有者支持保留个人 patch，或明确暂时接受挂载后不能同步输入法选项的限制；本任务未越权修改 Core/App，不能声称这项无缝集成通过。
2. W-5 执行前确认接受 librime 普通导出导致删除标记、动态学习时间信息重建的语义限制，以及强制中断时从完整备份人工恢复的边界。真实数据未触碰。
