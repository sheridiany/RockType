# SPEC-011 词库优化（输入法打磨 · 第一项）

- 阶段：打磨 P1（输入法）
- 覆盖需求：FR-A1、FR-A3、FR-A5、NFR-2
- 状态：InProgress（W-1/W-2/W-3 已实现；个人层与人工验收由其他执行者完成）

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
| W-1 | 评测集与评测脚本，先跑出现状基线 | pi-ui | 已完成，基线 162/200（81%） |
| W-2 | 引入白霜词库并调整两套方案，回归 RimeChecks | pi-ui | 已完成，164/200（82%）；上下文重排取舍见证据 |
| W-3 | AI / 开发中文词库与英文扩充，评测校准权重 | pi-ui | 已完成，181/200（90.5%），AI 58/60 |
| W-4 | 个人层脚本：学习词简体迁移、个人习惯词表（含临时目录测试） | pi-platform | 未开始 |
| W-5 | Claude 在本机执行个人层脚本、安装、用户试打 | Claude + 用户 | 未开始 |

**文件所有权**：pi-ui：`Rime/`、`THIRD_PARTY_NOTICES.md`、`LICENSES/`、`scripts/eval-candidates.sh`、`Tests/InputMethodTests/Fixtures/`、评测相关测试；pi-platform：`scripts/personal/`、其测试、`.gitignore` 一行。两人都不改 `InputMethod/sources`（pi-ime 正在恢复 RoType 视觉）。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 上游许可证核实并随包附带 | 检查 LICENSE 文件与 NOTICES | 通过 | 固定上游版本、逐字复制 GPL-3.0；打包脚本包含许可与声明 |
| 首选命中率：替换后 ≥ 替换前；AI 条目显著提升 | `scripts/eval-candidates.sh` | 通过 | 81% → 90.5%；AI 63.33% → 96.67%；固定集与逐条结果已提交 |
| RimeChecks 全部通过（模糊音、简拼、纠错、Shift、英文、学习） | `scripts/test.sh` | 通过 | 原断言保留；新增双方案领域读音、英文原样上屏、日常同音词保护 |
| 部署时间与打字延迟无明显退化 | 计时 + 人工 | 部分验证，真实 IMK 待人工 | 已测临时部署与同步按键 P95，见下；不能代替真实输入延迟验收 |
| 学习词迁移后常用词仍优先 | 本机试打 | 待人工验证 | |
| 个人词表不进 git、不打印原文 | 检查 | 未运行 | |

## 进度

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

- `candidate-baseline.tsv` / `candidate-frost.tsv` / `candidate-final.tsv` 保存逐项结果，评测输入与期望在 W-1 提交后未改动。脚本现在直接输出基线对比（输入/期望必须与基线一致）；总命中数低于基线退出 **2**。SPM 回归门槛为总计 ≥181、AI ≥58、日常 ≥75。
- 扩展既有 `RimeChecks.swift`：两套方案各 13 条领域词读音与实际提交、24 个英文词大小写/标点实际提交、10 条日常同音词首选。`bash scripts/test-rime-capabilities.sh` **退出码 0**；词库完整性测试检查 800–1500 条、无重复、单字均可编码、显式拼音与字表一致，`swift test --filter domainDictionaryReadingsAreEncodableAndUnique` **退出码 0**。
- 已按用户后续通知将 main 的 RockType 更名、默认隐藏菜单栏图标及构建后 LaunchServices 注销逻辑合入当前 worktree（`8e6019c`、`d6e6628`）；没有向 main 合并、push 或新建分支。名称冲突保留 RockType Pinyin / RockType Shuangpin 和词库版本；未自行编辑输入法 sources。合并 `9b197ce` 后统一测试退出码 0。
- 未验证：全部 1,067 词的逐条人工读音验收、真实键盘/IMK 延迟、用户学习词简体迁移和个人词表；本任务范围不覆盖 W-4/W-5。

### 最终验证与性能复测

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

## 问题

1. 旧繁体八股文模型与简体词库的已提交上下文重排不匹配（“中国”之后 `shijian` 首选变“事件”）。本次保留模型和造句，关闭两套方案 `contextual_suggestions`；Claude 决定后续是否选用许可明确的简体模型。
2. 白霜 W-2 首选新增退步包括“哪里→那里、北京→背景、上海→伤害”和两条整句；总指标仍高于基线。不为评测硬调这些日常同音词，请 Claude 与用户试打确认词频偏好。
3. 仓库禁止旧标识的字面扫描会命中无关专名（如“巴洛克”）。本次按硬规则排除上游 40 条相关词，NOTICES 记录；若希望恢复，需要 Claude 修改该约定/扫描边界。
