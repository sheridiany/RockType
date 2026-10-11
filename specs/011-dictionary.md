# SPEC-011 词库优化（输入法打磨 · 第一项）

- 阶段：打磨 P1（输入法）
- 覆盖需求：FR-A1、FR-A3、FR-A5、NFR-2
- 状态：InProgress（已采用校准后的 C；四类自动验收通过，个人层对齐及真实试打待完成）

## 目标

候选更准、更全：换上词频经过大语料重统计的开源中文词库；补齐 AI / 开发领域词；按用户本人的习惯定制。**产品打包**与**用户个人数据**严格分开：个人词表只写入用户本机 `~/Library/Application Support/RoarkT/Rime`，不进安装包、不进 git。
候选更准、更全，同时日常与整句首选不得低于旧词库基线。补齐 AI / 开发领域词，按用户本人的习惯定制。**已采用校准后的 C：原词库 + 繁体 AI 术语 + 英文扩充**。日常、整句、开发均保持 A，AI 达到 95%；此前 B 与未校准 C 的结论保留为历史证据，最新结论以“C 校准与采用”节为准。**产品打包**与**用户个人数据**严格分开：个人词表只写入用户本机 `~/Library/Rime`，不进安装包、不进 git。

## 调研结论（2026-10-11）

| 词库 | 许可 | 结论 |
| --- | --- | --- |
| 白霜拼音 rime-frost（基于雾凇，约 7.45 亿字语料重统计字频词频） | GPL-3.0（实施时须以上游 LICENSE 文件核实） | **不采用、不打包**：B 的日常与整句退步，词表、专用许可与声明均已撤回 |
| 雾凇拼音 rime-ice | GPL-3.0 | 不并用（白霜已是其改进版，避免重复词条与词频冲突） |
| 万象 rime-wanxiang 语言模型 `.gram` | 未明确（第三方显示 CC-BY-4.0，未核实） | **不打包**；记入后续“可选下载语言模型”候选 |
| 现用 八股文 `zh-hant-t-essay-bgw.gram`（rime-octagram-data） | 随 Squirrel/plum | 先保留；评估其与简体词库的配合，若明显变差则在规格问题节报告 |

## 历史产品层实施范围（W-2/W-3；采用结论以复评为准）

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
5. **学习词迁移为简体**：用户已导入的 RoType 学习词（`roarkt_zh.userdb`，繁体键）在主词库换为简体后需转换：导出 → OpenCC 繁转简（t2s）→ 导入新 userdb。脚本 `scripts/personal/migrate-userdb-simplified.sh`，执行前完整备份到 `<Rime 用户目录>/roarkt-backups/<时间>/`。由 Claude 在合并后执行，agent 只实现与用临时目录测试。
6. **个人习惯词表**：脚本 `scripts/personal/build-personal-dict.py`：从用户本机文本中统计高频中文词与英文术语，**来源仅限**用户明确允许的目录（默认 `~/Repos/**/*.md` 与 `~/Repos/**/*.swift` 注释/字符串，排除 `node_modules`、`.build`、`.git`），与主词库比对，产出主词库缺失或排序靠后的词，写 `<Rime 用户目录>/roarkt_personal.dict.yaml`（文件头注明“个人词表，由 RockType 生成”），通过独立 `roarkt_personal.patch.yaml` 挂载。SPEC-004 设置生成的两份 custom 在 patch 内可选引用它；个人脚本不读写 custom，不覆盖用户手写内容。脚本只输出统计摘要，不打印原文；不读取聊天记录、浏览器、邮件等其他数据。产物不进 git（`.gitignore`）。
5. **学习词保持原格式（C 方案）**：继续使用原 `luna_pinyin` / `roarkt_zh.userdb` 的繁体学习键。本次没有用户数据库格式迁移，**不应执行**先前为白霜简体主词库设计的 `scripts/personal/migrate-userdb-simplified.sh`。W-4 负责人需将个人层方案与 C 对齐，由 Claude 在合并后安排本机操作；本任务不改个人脚本、不访问真实用户数据。
6. **个人习惯词表**：脚本 `scripts/personal/build-personal-dict.py`：从用户本机文本中统计高频中文词与英文术语，**来源仅限**用户明确允许的目录（默认 `~/Repos/**/*.md` 与 `~/Repos/**/*.swift` 注释/字符串，排除 `node_modules`、`.build`、`.git`），与主词库比对，产出主词库缺失或排序靠后的词，写 `~/Library/Rime/roarkt_personal.dict.yaml`（文件头注明“个人词表，由 RockType 生成”），并通过 `roarkt.custom.yaml` / `roarkt_flypy.custom.yaml` 的 patch 挂载（与 SPEC-004 设置同步生成的 custom 文件合并，不覆盖用户手写内容）。脚本只输出统计摘要，不打印原文；不读取聊天记录、浏览器、邮件等其他数据。产物不进 git（`.gitignore`）。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| W-1 | 评测集与评测脚本，先跑出现状基线 | pi-ui | 未开始 |
| W-2 | 引入白霜词库并调整两套方案，回归 RimeChecks | pi-ui | 未开始 |
| W-3 | AI / 开发中文词库与英文扩充，评测校准权重 | pi-ui | 未开始 |
| W-4 | 个人层脚本：学习词简体迁移、个人习惯词表（含临时目录测试） | pi-platform | 完成；个人 patch 与设置同步解耦，用户目录支持参数/环境变量及独立默认目录 |
| W-1 | 评测集与评测脚本，先跑出现状基线 | pi-ui | 已完成，基线 162/200（81%） |
| W-2 | 引入白霜词库并调整两套方案，回归 RimeChecks | pi-ui | 白霜已撤回；采用 C 原主词库/原设置，回归通过 |
| W-3 | AI / 开发中文词库与英文扩充，评测校准权重 | pi-ui | 已完成 C 校准：日常 78、整句 17、开发 29、AI 57，总计 181/200 |
| W-4 | 个人层脚本：按 C 对齐原学习格式、个人习惯词表（含临时目录测试） | pi-platform | 待负责人与 Claude 对齐 C |
| W-5 | Claude 在本机执行个人层脚本、安装、用户试打 | Claude + 用户 | 未开始 |
| W-6 | 全简体管线 D：词库、预置词汇、模型、方案与 C/D 冻结评测 | pi-ui | 失败后停止；试验已保存，产品保持 C，详见 W-6 验收 |

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
| 许可证与实际打包内容一致 | 检查 LICENSE 文件与 NOTICES | 通过 | 白霜文件/专用许可/声明撤回；保留原词库许可及 MIT 自研词表声明 |
| 日常 ≥78/80、整句 ≥17/20、开发 ≥29/40、AI ≥57/60 | 同一冻结集 A/C 对照 | **通过** | 校准 C：78、17、29、57；总计 181/200，A 的所有命中项均保留 |
| RimeChecks 全部通过（模糊音、简拼、纠错、Shift、英文、学习） | `scripts/test.sh` | 通过 | 原断言保留；新增双方案领域读音、英文原样上屏、日常同音词保护 |
| 部署时间与打字延迟无明显退化 | 计时 + 人工 | 部分验证，真实 IMK 待人工 | 已测临时部署与同步按键 P95，见下；不能代替真实输入延迟验收 |
| 既有学习词仍优先（C 不迁移数据库） | 本机试打 | 待人工验证 | 两方案临时 profile 的学习/重启/忘记回归通过，真实旧学习数据未访问 |
| 个人词表不进 git、不打印原文 | 检查 | 未运行 | |

## C 校准与采用（Claude 二次授权，2026-10-11）

**结论：采用校准后的 C，四类门槛同时通过。** 原词库、繁转简、八股文模型、`contextual_suggestions: true` 和其他原行为设置保持 A；新增繁体 AI 词表与已有英文扩充。白霜四张词表、专用许可证、NOTICES/PROVENANCE 声明、资源复制依赖均已移除。

### 根因与权重策略

- 单变量对照：A 只换英文扩充，仍为 **162/200，开发 29/40**；A 只加未校准的繁体 AI（800），变为 **172/200，开发 24/40**，与未校准 C 一致。因此英文扩充不是这次开发类退步的原因。
- librime `EntryCollector::CreateEntry` 对绝对权重直接赋值；新增 AI 词条会阻止同文本的预置词再自动加入。统一 800 把已有高频词降权，并非单纯新增词挤占。五项退步及恢复：接口→借口→接口、部署→不熟→部署、前端→前段→前端、进程→京城→进程、构建→构件→构建。它们的原预置频率分别为 **10,415 / 5,289 / 9,490 / 6,446 / 12,722**。
- 对 1,067 条繁体术语应用原量纲：预置词频高于 800 的 **245 条写 `100%`**，由 Rime 继承原频率；其余 **822 条保持领域优先级 800**。数值 `max(800, 原预置频率)` 试验与最终 `100%` 版本逐项结果一致。未复制原频率表到 MIT 自研词表；未提高有歧义的短词来压过日常词。
- 原 104 条显式拼音保持，其余自动编码。词库完整性测试改用原 `luna_pinyin` 字表，并新增“不得降低已有预置词频”的回归断言。两套 schema 与 A 对照，仅显示名称、作者、版本元数据不同；原行为设置一致。

| 类别 | A 原词库 | 校准 C | 门槛 | 结果 |
| --- | --- | --- | --- | --- |
| 日常 | 78/80 (97.50%) | 78/80 (97.50%) | ≥78/80 | 通过 |
| 整句 | 17/20 (85%) | 17/20 (85%) | ≥17/20 | 通过 |
| 开发 | 29/40 (72.50%) | 29/40 (72.50%) | ≥29/40 | 通过 |
| AI | 38/60 (63.33%) | 57/60 (95%) | ≥57/60 | 通过 |
| **总计** | **162/200 (81%)** | **181/200 (90.5%)** | 四类同时达标 | **+9.5pp** |

- A 的 **162 条原命中全部保留**；增加 19 条 AI 命中。AI 剩余三条未首选：词元→次元、对齐→对其、显存→现存。它们可从候选选择并学习，不继续提高权重以挤掉日常同音词。
- 冻结 200 条评测输入与期望未改，SHA-256 仍为 `7b8d9651974895879a2d11a28325eb2ca86e6e046a2b6c1c345b41ab39d15f96`。`candidate-final.tsv` 更新为本次 C；旧 B 结果保存为 `candidate-frost-ai.tsv`，未校准 C 夹具与结果保留作历史证据。
- 继续运行 10 条日常同音词保护。补充检查中的 `yibu` 原期望“一步”来自 B；按冻结 A 的实际首选改为“一部”，C 与 A 一致。正式评测仍期望“异步”并计为未命中；其他九条保护不变。两套方案的 13 条领域词读音/实际提交、24 条英文原样提交与所有原 RimeChecks 均通过。
- SPM 门槛更新为日常 ≥78、整句 ≥17、开发 ≥29、AI ≥57、总计 ≥181。旧标识守卫维持上次已授权的“洛克输入法”精确短语规则。

### 本次真实验证

| 命令 | 退出码 | 证据/范围 |
| --- | --- | --- |
| `scripts/eval-candidates.sh .build/dictionary/calibrate/english-only/Rime .build/dictionary/calibrate/results-english-only` | 0 | 英文单变量：162/200，开发 29 |
| `scripts/eval-candidates.sh .build/dictionary/calibrate/ai-only/Rime .build/dictionary/calibrate/results-ai-only` | 0 | AI 单变量：172/200，开发 24 |
| `scripts/eval-candidates.sh .build/dictionary/calibrate/preset-floor/Rime .build/dictionary/calibrate/results-preset-floor` | 0 | 原频率数值下限：181/200 |
| `scripts/eval-candidates.sh .build/dictionary/calibrate/preset-relative/Rime .build/dictionary/calibrate/results-relative` | 0 | `100%` 继承原频率：181/200 |
| `scripts/eval-candidates.sh .build/dictionary/abc/A/Rime .build/dictionary/calibrate/final-A` | 0 | 本次串行重跑 A：162/200 |
| `scripts/eval-candidates.sh Rime .build/dictionary/calibrate/final-C` | 0 | 本次串行最终 C：181/200 |
| `zsh scripts/test.sh` | 0 | 155 个 Swift Testing 测试、两方案 RimeChecks、面板/session、AppShell；`.build/dictionary/calibrate/tests.log` |
| `xcodebuild -project InputMethod/Squirrel.xcodeproj -scheme Squirrel -configuration Release -derivedDataPath .build/ime clean` | 0 | 清理本 worktree 输入法构建缓存，避免旧白霜资源残留 |
| `zsh scripts/build.sh` | 0 | 全部产物签名、语音 worker XPC 冒烟；已执行构建脚本的 LaunchServices 注销；`.build/dictionary/calibrate/build.log` |
| `zsh scripts/test-rime.sh --bundle 'dist/RockType Input.app'` | 0 | 新产品包内资源临时部署通过 |

- 所有打包 YAML 与 `Rime/` 的 `cmp` 均退出 **0**；包内不存在 `cn_dicts` 与专用白霜许可的断言退出 **0**；最终评测与已保存 C 逐项结果的 `cmp` 退出 **0**。
- 同机串行单次测量：A/C 干净临时部署 **2.62s / 1.87s**，1878 次按键刷新 P95 **1.738ms / 1.807ms**。仅同步 librime 路径，不代表真实 IMK/用户数据库/停服打字验收。
- 未安装、注册或启动输入法，未写真实 `~/Library/Rime`，未改 `InputMethod/sources`。真实试打与既有学习数据体验待 Claude/用户验证；W-4 必须对齐 C 的繁体学习格式，不能执行旧简体迁移计划。

## A/B/C 初次复评（历史，Claude 首轮验收反馈，2026-10-11）

**当时结论：没有满足全部条件的方案，停止选型调整，等待 Claude 决定。** 本次没有采用 C，没有改动产品 `Rime/`、打包逻辑或白霜许可/NOTICES。工作分支仍是 B 的实现，这不代表 B 获准发布。

新的选择规则：日常至少 **78/80**、整句至少 **17/20**、AI 至少 **57/60（95%）**；全部满足后才比较总命中数。不能用 AI 的收益抵消日常或整句的退步。

| 方案 | 日常 | AI | 开发 | 整句 | 总计 | 新规则结论 |
| --- | --- | --- | --- | --- | --- | --- |
| A：原词库、原英文，`a3fa578` | 78/80 (97.50%) | 38/60 (63.33%) | 29/40 (72.50%) | 17/20 (85%) | 162/200 (81%) | AI 不达标 |
| B：白霜 + AI + 英文扩充，`9df3960` | 75/80 (93.75%) | 58/60 (96.67%) | 32/40 (80%) | 16/20 (80%) | 181/200 (90.5%) | 日常与整句退步，不可采用 |
| C：原词库 + 繁体 AI + 英文扩充 | 78/80 (97.50%) | 53/60 (88.33%) | 24/40 (60%) | 17/20 (85%) | 172/200 (86%) | AI 不达标，不可采用 |

- C 保留 A 的 `luna_pinyin`、`use_preset_vocabulary: true`、繁转简 filter/config、八股文模型、`contextual_suggestions: true` 及其他原设置。仅新增 `roarkt_ai` 的 import，以及 B 的英文扩充。1,067 条术语及权重 800 不变，使用 macOS Foundation ICU `Hans-Hant` 转换文本列为繁体，104 条显式拼音不变；输出通过原 `tw2s.json` 转回简体。
- 初步直接导入简体 AI 的诊断版 C-S：日常 78/80、AI 52/60、开发 26/40、整句 17/20，总计 173/200（86.5%）。转换繁体后“开源模型、语义检索”命中，但仍未达到 AI 门槛。C 的七条 AI 未命中为：推理→推力、嵌入→潜入、词元→次元、对齐→对其、算力→算你、显存→现存、评测→拼车。没有改写期望、没有继续调权重强行达标。
- 同一评测输入 SHA-256 仍为 `7b8d9651974895879a2d11a28325eb2ca86e6e046a2b6c1c345b41ab39d15f96`。每次使用全新临时 Rime profile，不学习、不触碰真实用户目录。A/B 本次重跑数据与前次逐项结果一致。
- 可复现的 C 词库保存在 `Tests/InputMethodTests/Fixtures/variant-c/roarkt_ai.dict.yaml`（MIT，仅测试夹具、不打包）；其 README 给出从 A/B 固定提交重建 C 的命令。`candidate-variant-c.tsv` 与 `candidate-variant-c-simplified.tsv` 保存两个 C 试验的逐项输出。

| 本次实际验证命令 | 真实退出码 | 含义 |
| --- | --- | --- |
| `scripts/eval-candidates.sh .build/dictionary/abc/A/Rime .build/dictionary/abc/results-A` | 0 | A 评测执行成功 |
| `scripts/eval-candidates.sh .build/dictionary/abc/B/Rime .build/dictionary/abc/results-B` | 0 | B 评测执行成功 |
| `scripts/eval-candidates.sh .build/dictionary/abc/C/Rime .build/dictionary/abc/results-C`（简体诊断版本） | 0 | C-S 评测执行成功 |
| `scripts/eval-candidates.sh .build/dictionary/abc/C/Rime .build/dictionary/abc/results-C-traditional`（转换后） | 0 | C 评测执行成功，**不代表满足新验收门槛** |
| `zsh scripts/test.sh` | 0 | 当前 B 实现原有回归通过；新验收条件仍失败 |
| `scripts/eval-candidates.sh .build/dictionary/reproduce-C/Rime .build/dictionary/reproduce-C-results` | 0 | 按已保存夹具 README 重建 C，输出逐项一致 |

A/B 与先前保存结果、重建 C 与新保存结果的三个 `cmp` 均退出 **0**。

- 守卫修正：`scripts/test.sh` 两处中文表达式由“洛克”收窄为“洛克输入法”，其他旧标识与大小写匹配规则不变。手工检查 `printf '%s\n' 巴洛克` 经同一 `grep -E` 表达式返回 **1（不匹配，符合预期）**；旧产品名及其他四种旧标识返回 **0（匹配，符合预期）**。这来自 Claude 的明确授权，覆盖旧 AGENTS 字面规则的该项范围。
- 未运行：本次没有产品变更，因此未重复构建/签名、未启动/安装/注册 App 或输入法；未进行真实键盘验收。
- 下一步由 Claude 决定：是否另行授权针对原词库重新校准领域词权重，或调整词库/模型组合。依照“若都不满足则报告并停下”，本次不继续探索其他变体。

## 进度（历史实施证据）

### W-1 验收证据（2026-10-11）

- 固定 200 条原创公开常识样例：日常 80、AI 60、开发 40、整句 20。人工校对多音字编码；无个人数据。`candidate-eval.tsv` 是输入，`candidate-baseline.tsv` 保存替换前逐项结果，后续不修改期望以迎合词库。
- `scripts/eval-candidates.sh [Rime资源目录] [报告目录]` 使用当前 checkout 的 librime/Lua，在 `mktemp` 中部署、逐条新建会话、不提交候选；输出逐项 TSV、分类首选命中率、按键处理 + F19 刷新 + 读取 context 的 P95。退出码 0 表示评测成功执行，不表示所有首选正确。SPM `RoarkTCandidateEvaluationTests` 接入 `scripts/test.sh`，验证固定集完整性及命中数不低于基线。
- `scripts/eval-candidates.sh Rime .build/dictionary/baseline`：退出码 **0**。基线：日常 **78/80 (97.50%)**、AI **38/60 (63.33%)**、开发 **29/40 (72.50%)**、整句 **17/20 (85%)**，合计 **162/200 (81%)**。
- Apple M3 Max，macOS 27.0.1 (26A434)：一次干净部署 **2.41s**，1878 按键刷新 P95 **1.538ms**。这是 librime 同步路径测量，非真实 IMK 端到端延迟；受机器负载/文件缓存影响，不作为严格性能门禁。
- 未验证：真实键盘、安装版与用户学习数据。本步骤不启动输入法，不触碰真实 Rime 目录。


### W-1 提交前检查

- `zsh scripts/test.sh`：退出码 **0**（含新评测 SPM 测试、原 RimeChecks、面板/session、AppShell）；`git diff --check`：退出码 **0**。完整日志 `.build/dictionary/w1-final-tests.log`。

### W-2 验收证据（2026-10-11）

- 先克隆 `.build/vendor/rime-frost` 并核实实际 `LICENSE`，固定 `64d24e89341aee133c0ad0f09b5f47a695e3d508`。许可 SHA-256 `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`；`cmp` 确认许可、8105、others 与上游逐字一致（退出码 0）。base/ext 只排除命中仓库旧标识的 40 条专名，并加修改声明；不改上游频率，保留完整原文件头。
- 引入 8105/base/ext/others（约 17MiB）；不引入可选 Tencent 的 34 万多条零权重长尾词，控制体积/部署成本，与上游默认关闭该表一致。不并用雾凇，也不引入万象模型、细胞词库或上游 Lua。
- 两套方案共用 `roarkt_zh` 与用户词库；关闭 `use_preset_vocabulary`，避免繁体 essay 词条混入；删除繁转简 switch/filter/config，保留 Lua 过滤、模糊音/简拼/纠错 algebra、Shift、英文、候选翻译、五候选与学习行为。
- 对照上游 speller/translator：保留现有 lowercase alphabet 与 algebra，因 8105 的 `nve/lve/ju/qu/xu/yu` 与现有规则兼容，且设置 patch 按规则位置启停；不引入上游大写/符号拼写、corrector 或注释显示。保留补全/造句/用户词库与 1.2 初始质量；当前 librime 未实现上游 `grammar_penalty`，试验无效后移除。关闭已提交上下文重排，保留 octagram 造句（依据当前 librime `Poet::ContextualWeighted` 与 `MakeSentence` 边界）。
- 首次 `zsh scripts/test.sh` **失败，退出码 133**：RimeChecks 在连续提交“中国”后 `shijian` 首选错误。临时增加“时间”权重以及 `grammar_penalty` 均未修复，已撤销；关闭 `contextual_suggestions` 后 `bash scripts/test-rime-capabilities.sh` **通过，退出码 0**，没有降低原断言。
- `scripts/eval-candidates.sh .build/dictionary/frost-context-off .build/dictionary/w2-context-off` **退出码 0**：日常 **75/80 (93.75%)**、AI **41/60 (68.33%)**、开发 **32/40 (80%)**、整句 **16/20 (80%)**，合计 **164/200 (82%)**。一次部署 **2.21s**，按键 P95 **2.109ms**（并行构建负载下，仅记录，不宣称无性能退化）。
- 资源子目录同步接入 Xcode `package-rime.sh`、两条部署/能力脚本与 settings 部署测试；Xcode 包内同时附 GPL 与第三方声明。没有修改 `InputMethod/sources`。
- 最终 `zsh scripts/test.sh` **退出码 0**；`xcodebuild -project InputMethod/Squirrel.xcodeproj -scheme Squirrel -configuration Release -derivedDataPath .build/ime ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build` **退出码 0**；`zsh scripts/test-rime.sh --bundle '.build/ime/Build/Products/Release/RoarkT Input.app'` **退出码 0**。仅编译和读取包内资源进行临时部署，未启动/安装/注册输入法。未运行整套签名构建与真实键盘验证。

### W-3 验收证据（2026-10-11）

- 原创 `roarkt_ai.dict.yaml` **1,067 条**，覆盖 AI、算法、推理/智能体、检索/评测、编程/系统/网络/存储、工程、产品协作、设计、桌面输入；其中 **963 条不带编码**、**104 条显式多音字编码**。MIT；不读取用户文件，不复制白霜的领域词表。词条直接作为维护源，不引入生成器运行时。
- 英文原表已有多数品牌/技术词；只读参考既有英文整理方法，新增 **65 条**，调整 **19 条**的大小写或权重，总计 **30,261 条**。沿用小写纯字母输入码、原样大小写/标点输出，领域优先级 15,000；高于该值的原词频不降权。既有英文数据继续 CC-BY-SA-4.0。
- 权重校准（同一冻结的 200 条；三次评测退出码均 **0**）：

| 中文领域词权重 | 日常 | AI | 开发 | 整句 | 总计 |
| --- | --- | --- | --- | --- | --- |
| 200 | 75/80 | 57/60 | 32/40 | 16/20 | 180/200 (90%) |
| **800（采用）** | **75/80** | **58/60** | **32/40** | **16/20** | **181/200 (90.5%)** |
| 3000 | 75/80 | 59/60 | 35/40 | 16/20 | 185/200 (92.5%) |

- 不选 3000：它使“显存、联调、回调、断点”分别超过“现存、链条、毁掉、断电”。800 档已明显改善 AI 长词，保留这些日常同音词的工厂首选；领域短词仍可从候选选择并学习。对照结果在 `.build/dictionary/w3-{200,800,3000}/`。
- 冻结集汇总：

| 类别 | W-1 旧词库 | W-2 白霜 | W-3 最终 | 最终比基线 |
| --- | --- | --- | --- | --- |
| 日常 | 78/80 (97.50%) | 75/80 (93.75%) | 75/80 (93.75%) | -3.75pp |
| AI | 38/60 (63.33%) | 41/60 (68.33%) | 58/60 (96.67%) | +33.33pp |
| 开发 | 29/40 (72.50%) | 32/40 (80%) | 32/40 (80%) | +7.50pp |
| 整句 | 17/20 (85%) | 16/20 (80%) | 16/20 (80%) | -5pp |
| **总计** | **162/200 (81%)** | **164/200 (82%)** | **181/200 (90.5%)** | **+9.5pp** |

- `candidate-baseline.tsv` / `candidate-frost.tsv` / `candidate-frost-ai.tsv` 保存旧三阶段逐项结果（原 B 的 `candidate-final.tsv` 已更名，现 `candidate-final.tsv` 为校准 C），评测输入与期望在 W-1 提交后未改动。脚本现在直接输出基线对比（输入/期望必须与基线一致）；总命中数低于基线退出 **2**。SPM 回归门槛为总计 ≥181、AI ≥58、日常 ≥75。
- 扩展既有 `RimeChecks.swift`：两套方案各 13 条领域词读音与实际提交、24 个英文词大小写/标点实际提交、10 条日常同音词首选。`bash scripts/test-rime-capabilities.sh` **退出码 0**；词库完整性测试检查 800–1500 条、无重复、单字均可编码、显式拼音与字表一致，`swift test --filter domainDictionaryReadingsAreEncodableAndUnique` **退出码 0**。
- 已按用户后续通知将 main 的 RockType 更名、默认隐藏菜单栏图标及构建后 LaunchServices 注销逻辑合入当前 worktree（`8e6019c`、`d6e6628`）；没有向 main 合并、push 或新建分支。名称冲突保留 RockType Pinyin / RockType Shuangpin 和词库版本；未自行编辑输入法 sources。合并 `9b197ce` 后统一测试退出码 0。
- 未验证：全部 1,067 词的逐条人工读音验收、真实键盘/IMK 延迟、用户学习词简体迁移和个人词表；本任务范围不覆盖 W-4/W-5。

### 历史 B 验证与性能复测

- `zsh scripts/test.sh`：**退出码 0**，155 个 Swift Testing 测试以及 Rime 部署/能力、session/修饰键/面板和 AppShell 检查通过。日志 `.build/dictionary/final-tests.log`。
- `zsh scripts/build.sh`（已含 main `6b0081f`）：**退出码 0**，主 App、输入法、翻译服务、语音 worker 签名构建与语音 XPC 冒烟检查通过；没有启动 App 或输入法，没有安装/注册输入源。构建脚本已执行中间产物/worktree App 的 LaunchServices 注销。日志 `.build/dictionary/final-build.log`。
- `zsh scripts/test-rime.sh --bundle 'dist/RockType Input.app'`：**退出码 0**。`cmp` 核对打包的领域词库和白霜 GPL 文本与源文件：各 **退出码 0**。
- 完成构建后串行复测：`git archive a3fa578 Rime` 解到 `.build/dictionary/replay-baseline`，再运行 `scripts/eval-candidates.sh .build/dictionary/replay-baseline/Rime .build/dictionary/baseline-replay` 与 `scripts/eval-candidates.sh Rime .build/dictionary/final`，均 **退出码 0**。仍是 162 → 181 命中；最终逐项结果与已提交 fixture 的 `cmp` **退出码 0**。

| 同机串行单次测量 | W-1 资源重放 | 最终资源 |
| --- | --- | --- |
| 全新临时目录部署（含两套方案及英文） | 1.98s | 1.63s |
| 1878 次按键处理/刷新 P95 | 1.981ms | 1.749ms |

- 此次样本未显示同步路径退化；文件系统缓存未清空，单次测量受系统负载影响，不能代替真实 IMK、翻译服务停掉时打字、首装部署及用户数据库规模的验收。
- 评测集 SHA-256：`7b8d9651974895879a2d11a28325eb2ca86e6e046a2b6c1c345b41ab39d15f96`；W-1 后未修改。工厂样例不是用户真实输入内容。

### W-4 首次交付证据（2026-10-11；custom 合并方式已被下节替代）

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

1. W-4 / SPEC-004 原文件归属冲突已按 Claude 决定解决，详见下方解耦验收。手写 custom 不自动修改，由所有者决定加入可选引用。
2. Claude 已接受 librime 导出丢失删除标记、动态学习时间元数据的限制，继续保留原库备份与记录。强制中断的人工恢复边界不变，真实数据未触碰。

### W-4 后续：个人 patch 与设置同步解耦

- 先用临时目录中最小 schema 实测 `patch` 下 `__include: roarkt_personal.patch:/patch?`：文件缺失与存在两次部署均退出 0；缺失不阻塞部署，存在则引入个人字段，同时保留设置的同级覆盖。
- `Core/Settings/RimeSettingsPatch.swift` 为两套 custom 加入该可选引用。个人脚本移除 custom 解析、合并及所有权标记，仅读写独立个人 patch、中英文词典和英文编译依赖 schema（共 4 文件），回滚不包含 custom。
- 临时测试调用实际 `RimeSettingsPatchWriter`，验证设置写入不覆盖个人文件；将默认及重写后的设置产物交给真实 librime 部署，两个方案的中文与英文个人词共 8 次候选探测通过。重写后的 Shift/英文补全设置也实际生效。回滚删除个人 patch 后重新部署，两个方案恢复工厂 dictionary；既有 Core 部署测试覆盖全新 profile 中缺少个人 patch 的场景。
- `swift test --filter personalScriptsInTemporaryDirectories`：退出 0，9 项个人脚本检查通过（删除旧 custom 合并专用测试，替换为解耦及文件归属验证）。`scripts/test.sh`：退出 0。仅临时目录合成数据，无真实 profile 操作。

### W-4 后续：独立 Rime 用户目录

- 两个个人脚本共享目录参数定义，优先级为 `--rime-dir` → `ROARKT_RIME_USER_DIR` → `~/Library/Application Support/RoarkT/Rime`；环境变量为空也使用默认值。仍要求目标目录已存在；离线确认、来源授权、锁、备份及回滚约束保留，不搜索或迁移其他输入法的目录。
- 新增临时 HOME 下的 CLI 测试：两个入口分别验证默认路径（含空格）、环境覆盖、参数优先于环境、对应目录内执行及回滚；检查未选中的目录和旧 `Library/Rime` 哨兵保持原样。学习词转换使用真实 librime/OpenCC 和合成数据。
- 验收：完整 `scripts/test.sh` 通过，直接捕获真实退出码 `0`；153 个 Swift Testing 测试通过，其中个人脚本包装执行 11 项临时目录检查。Rime 部署、能力、输入法及 AppShell 检查通过。`git diff --check` 通过。
- 未验证：真实用户目录操作、安装与试打。Core 单一路径常量由 pi-ime 实现，待其合入 main 后再在当前 worktree 合并对齐。
1. W-4 需对齐 C：继续使用原繁体学习键，不执行为白霜设计的简体 userdb 迁移；个人词表的字表/编码/挂载由负责人和 Claude 确认。本任务未修改个人脚本或真实数据。
2. Claude 从 main 合并后安排真实试打：全拼/双拼、原学习词优先级、整句、英文与候选翻译。自动化均通过，但真实 IMK 延迟和用户数据库规模未验收。
3. 早期白霜与上下文模型取舍已关闭：采用保留原设置的校准 C。旧标识守卫已按授权收窄，不再误伤普通词；白霜的 40 条专名排除随整个词库撤回而不再涉及产品。

## W-6 全简体管线 D（2026-10-11，未通过，停止采用）

**最新结论：D 未达到整句门槛，RimeChecks 也失败；按用户指令停止优化，产品保持 C。**
没有修改冻结期望，没有尝试其他模型或调高词频。实现试验保存为
`Tests/InputMethodTests/Fixtures/variant-d/` 与 `integration.patch`，不是产品打包资源。

### 任务

| 步骤 | 状态 | 产物与未完成项 |
| --- | --- | --- |
| W-6.1 ICU 主词表与 AI 简体转换 | 试验完成，语义校正未完成 | 70,732 → 67,548 条；相同词＋编码权重相加，3,050 个碰撞键；人工统一妳→你；著/乾/瞭/藉等风险清单见下述文档 |
| W-6.2 简体 essay 与 gram | 来源/许可核实完成，保存试验资源 | rime-essay-simp + octagram hans 的 bgw 词模型；未进入最终安装包 |
| W-6.3 两方案去除繁简转换 | 试验实现，未采用 | 完整补丁保存；模糊音、简拼、纠错、Shift、英文、Lua 候选翻译、五候选、上下文建议配置保留；行为回归未全部通过 |
| W-6.4 冻结 C/D 评测 | **失败，停止** | 整句 15 < 17；RimeChecks 现存/显存断言失败 |
| W-6.5 用户学习词迁移 | 未运行，非 pi-ui 职责 | **D 未来正式采用时，`roarkt_zh.userdb` 必须由 pi-platform 脚本 + Claude 执行 t2s 迁移。当前保留 C，不执行迁移。** |

### 来源与派生方法

详细许可、SHA-256、碰撞表和未处理高频项见
[`docs/dictionary-simplification.md`](../docs/dictionary-simplification.md)。主词表保留上游完整文件头；LGPL-3.0。
macOS 自带 ICU `Hant-Hans` 转换，百分比/空权重先按原繁体 essay 解析为绝对值再相加，保留不同读音。
AI 仍为 MIT 原创词表；只转换文本，保留 C 的数值/相对权重。

- 简体 essay：`rime/rime-essay-simp@dc06d4c96ae72ad46b29e3aa824a5d1e8f721fd0`，原 `essay-zh-hans.txt` 原样重命名 `essay.txt`；LGPL-3.0。
- 简体模型：实际来源为 `lotem/rime-octagram-data` 的 hans 分支，`f8ce3b534733e489a8470a7c2adf5a154e8ea069`；`zh-hans-t-essay-bgw.gram`，LGPL-3.0。采用与 C 相同类别的 bgw 词模型；用户列举的 bgc 是另一种模型，本次未尝试。
- 两个仓库/分支的 LICENSE 已读取、原样保存；NOTICES 明确它们仅为未采用试验夹具。原有运行库来源追溯限制未关闭。

### 验收证据

| 类别 | 本次重跑 C | 试验 D | 门槛 | D 结果 |
| --- | --- | --- | --- | --- |
| 日常 | 78/80 | 78/80 | ≥78 | 通过 |
| 整句 | 17/20 | **15/20** | ≥17 | **失败** |
| 开发 | 29/40 | 31/40 | ≥29 | 通过 |
| AI | 57/60 | 58/60 | ≥57 | 通过 |
| 总计 | 181/200 | 182/200 | 四类同时满足 | **不可采用** |

同一冻结集 SHA-256 `7b8d9651974895879a2d11a28325eb2ca86e6e046a2b6c1c345b41ab39d15f96`。
C/D 逐项结果：`candidate-w6-C.tsv`、`candidate-w6-D.tsv`。总数提升不能抵消整句退步；日常总数相同也不代表逐项无退步。

D 全部 18 项未命中（标记“新增退步”表示 C 曾命中）：

| 类别 | 期望 | D 首选 | 与 C 比较 |
| --- | --- | --- | --- |
| 日常 | 同事 | 同时 | 原未命中 |
| 日常 | 哪里 | 那里 | 新增退步 |
| AI | 对齐 | 对其 | 原未命中 |
| AI | 算力 | 算你 | 新增退步 |
| 开发 | 埋点 | 卖点 | 原未命中 |
| 开发 | 联调 | 链条 | 原未命中 |
| 开发 | 前端 | 前段 | 新增退步 |
| 开发 | 组件 | 逐渐 | 原未命中 |
| 开发 | 异步 | 一步 | C 首选一部，均未命中 |
| 开发 | 协程 | 写成 | 原未命中 |
| 开发 | 线程 | 县城 | 原未命中 |
| 开发 | 编译 | 便宜 | 原未命中 |
| 开发 | 断点 | 断电 | 原未命中 |
| 整句 | 很高兴认识你 | 很高兴人是你 | 新增退步 |
| 整句 | 你现在在哪里 | 你现在在那里 | 新增退步 |
| 整句 | 我正在学习编程 | 我正在学习变成 | 原未命中 |
| 整句 | 我想喝一杯咖啡 | 我想和一杯咖啡 | 原未命中 |
| 整句 | 我们下周再讨论 | 我们下走在讨论 | 原未命中 |

| 实际验证 | 真实退出码 | 结论 |
| --- | --- | --- |
| `bash scripts/eval-candidates.sh .build/dictionary/w6/C/Rime .build/dictionary/w6/results-C` | 0 | C 181/200，四类达标 |
| `bash scripts/eval-candidates.sh Rime .build/dictionary/w6/results-D`（当时 Rime 为 D） | 0 | D 182/200，**整句门槛失败**；脚本退出 0 仅代表评测执行/旧总分底线通过 |
| `zsh scripts/test.sh`（D） | 1 | 164 个测试中记录 17 个失败 issue：13 个 AI `100%` 没有新 essay 频率、2 个频率下限、1 个缺“著”字、1 个整句门槛；未削弱断言 |
| `bash scripts/test-rime-capabilities.sh`（D） | 133 | RimeChecks 在全拼日常保护“现存”得到“显存”而停止；后续检查及双拼完整回归未完成，不能声明全过 |
| 恢复 C 后 `zsh scripts/test.sh` | 0 | 当前产品完整回归通过；个人脚本包装报告 11 项中 5 项因环境依赖跳过，不作为真实迁移验收 |
| `bash scripts/eval-candidates.sh .build/dictionary/replay-D/Rime .build/dictionary/replay-D/results` | 0 | 按夹具 README 重建 D，仍为 182/200 / 整句 15 |
| 重建 D 结果与保存 D `cmp` | 0 | 200 条输出逐项一致 |
| `git diff --check` | 0 | 无空白错误 |

本次 C/D 单次临时部署 2.52s / 1.48s，1878 按键同步刷新 P95 2.432ms / 1.163ms；不代表真实 IMK 性能验收。
日志在 `.build/dictionary/w6/{C.log,D.log,tests.log,rimechecks.log,restored-C-tests.log,replay-D.log}`。
未运行整包构建/签名/包内验证：D 已被门槛拒绝，打包接入仅保存补丁，不声称打包成功。
未安装、注册、启动输入法；未触碰真实 Rime 目录；未改输入法 sources、个人迁移脚本或评测期望。
