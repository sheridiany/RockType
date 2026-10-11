# SPEC-003 输入法与候选翻译（M1）

- 阶段：M1
- 覆盖需求：FR-A1–A11、FR-E1（离线与静态路径）、FR-E8（输入法部分）、NFR-2
- 状态：InProgress（I-1/I-2 已实现；I-3 与视觉验收待完成）
- 依赖：SPEC-001（输入法迁移已完成）、D0 U4 候选窗/输入模式提示设计

## 范围

输入法功能已由 T3 从 RoType 迁入。M1 补齐两件事：**候选窗、译文栏、输入模式提示按 D0 基线重做视觉**；**把 RoType 已有能力在 RoarkT 上重新验证并补测试**。不新增功能。

## 视觉对齐（以 `App/Surfaces/CandidateView.swift`、`InputModeView.swift` 与 `dist/gallery/candidate-*`、`input-*` 为准）

- 候选窗：拼音行 + 横排 5 候选；高亮项强调色底；序号弱化；字号、间距、圆角、阴影取 D0 Tokens 数值（输入法不能链接 App 代码，在 `InputMethod/sources` 内用常量复刻，并在注释中注明对应 Token 名）。
- 译文栏：候选窗下方独立卡片；左侧图标 + 小标题（候选翻译 / 静态词条 / AI 改写 / 翻译中 / 不可用）+ 译文；右侧 `Tab` 提示；长译文单行截断。
- 输入模式提示：中 / 英 / 方案名胶囊，出现与消失动效按 Tokens.Motion，遵守减少动态效果。
- 浅色/深色跟随系统；多显示器、屏幕边缘、全屏应用位置正确。
- 截图证据：在 TextEdit 中真实输入后的屏幕截图（需屏幕录制权限，由用户协助）或离屏渲染 `SquirrelPanel` 的 PNG，与 Gallery 对照。

## 能力复核（自动化为主，真实键盘项标“待人工验证”）

| 需求 | 复核方式 |
| --- | --- |
| A1 全拼、词频学习、首启自动部署 | `scripts/test-rime.sh` 扩展：部署后用 `rime_api` 测试程序（或 RoType 的 `test-candidate-session.sh` 迁移版）输入样例，断言首选 |
| A2 小鹤双拼 | 同上，双拼编码样例 |
| A3 模糊音、简拼、纠错 | 同上，样例集 |
| A4 Shift 切换 | 迁移 RoType `test-modifier-keys.sh` 中可自动化部分 |
| A5 英文短语单引号 | 样例断言上屏文本 |
| A6/A7 候选翻译 generation 隔离 | 已有服务测试 + 输入法侧 session 测试 |
| A8 静态词条 | 断开服务时的译文栏状态测试 |
| A10 学习菜单 | 删词后重新部署仍生效 |

迁移 RoType 中相关脚本时一律改名，删除升级/退休相关用例。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| I-1 | 候选窗、译文栏、模式提示视觉对齐 | pi-ime | 已实现，待视觉/人工验收；来源标题待协调 |
| I-2 | 能力复核测试迁移与补齐，接入 `scripts/test.sh` | pi-ime | 自动化通过，已接入统一测试入口 |
| I-3 | 真实打字验收 | 用户 + Claude | 未开始 |

**文件所有权**：`InputMethod/sources` 中候选窗、面板、主题相关文件，`InputMethod/scripts`、`scripts/test-*.sh` 新增项、`Tests/`。另一个 agent（pi-ui）正在 `InputMethod/sources` 中做设置同步（读取 settings.json、redeploy 通知），避免修改其涉及的文件；如必须修改同一文件，改动集中并在汇报中列出。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 视觉与 Gallery 一致（浅/深） | 生产面板离屏 PNG + D0 源码数值对照 | 已生成并查看，待 Claude 视觉验收 | `.build/ime-evidence/`，`scripts/test-ime.sh` 可重建；静态来源标题待协调 |
| A1–A5、A8、A10 自动化 | `scripts/test.sh` | 通过（下述自动化范围） | `Tests/InputMethodTests/`；首启 IMK、真实停服与菜单点击待人工验证 |
| A6/A7 generation、取消与 Secure Input | 实际 session/client 源码 + 假 XPC transport；真实 Rime 提交 | 通过 | `SessionChecks.swift`、`RimeChecks.swift` |
| 真实打字：全拼、双拼、Shift、英文短语、Tab 上屏译文 | 用户 | 待人工验证 | |
| 打字延迟不受翻译服务影响（NFR-2） | 停掉翻译服务后试打 | 待人工验证 | |

## 进度与验收证据

### I-1 实施证据（2026-10-11）

- 已实现：生产候选窗改为 D0 横排五候选、420pt 卡片、12pt 内边距、36pt 行高、7pt 高亮圆角；译文独立卡片、图标/标题/Tab、单行截断；中英提示改为 D0 胶囊，140ms 出现/80ms 消失并遵守减少动态效果。方案/其他状态提示使用同一胶囊视觉。全部展示代码留在 GPL 输入法内，未链接 App。
- 输入变化立即隐藏旧译文；加载状态不展示 session 中保留的旧文字。保留候选点击、悬停、滚轮翻页、学习菜单入口，不改控制器或设置同步文件。
- 通过：输入法 Release `xcodebuild`；合并 main 后的 `scripts/test.sh`（124 个 Swift Testing 测试、现有部署/AppShell 检查及新增输入法检查）。
- 通过：生产 `--preview-candidates` 离屏导出浅/深色候选与译文 PNG，位于 `.build/ime-evidence/`（可重建，不提交生成物）；查看浅深色候选、译文、模式提示及长译文截断，颜色、间距、布局与 D0 源码数值对照。仍待 Claude 视觉验收。
- 未验证：真实 IMK 焦点/点击、实际多显示器/全屏、减少动态效果开关实机体验。
- 边界：现有 session/响应没有“静态/动态/AI”来源字段；面板不猜测来源，成功统一标题“候选翻译”。若要求可靠显示“静态词条”，需要控制器/session 所有者增加来源字段；AI 是 M6 能力。本次未越权修改这些文件。

### I-2 实施证据（2026-10-11）

- `Tests/InputMethodTests/SessionChecks.swift`：迁移实际 session/client 行为测试，覆盖 selection/generation、迟到成功/失败、取消、retry、Tab 判定、静态精确匹配/未命中、双向词条、Secure Input 下无请求/无缓存、缓存容量/过期/焦点边界。移除旧接口、旧主题与旧验证窗口用例。异步回复改用主队列 FIFO 标记等待，消除旧用例固定 10ms 等待的不稳定性；不依赖用户当前 Secure Input 状态。
- `ModifierChecks.swift`：左右 Shift、合并 flagsChanged、缺 keycode、普通按键映射。
- `RimeChecks.swift`：用 Swift 直接调用当前 checkout 的 librime bool API 和 Lua 插件；从工厂资源部署到临时目录。全拼/小鹤首选、模糊音、全拼简拼/拼写及按键纠错、五候选页、左右 Shift 持续英文/Shift+字母、已确认前缀 + 原始后缀提交、英文补全/单引号短语/屏蔽词、候选与翻页身份校验、当前译文提交均通过。
- 学习测试使用多个独立进程：先验证工厂首选，再学习另一词，重启和切换全拼/双拼后首选保留；忘记学习记录后重新部署，两个方案恢复原首选且工厂词仍存在。只操作临时用户数据库，不读写真实 `~/Library/Rime`。
- `PanelChecks.swift`：直接编译生产面板，只有 controller/configuration 边界使用测试替身。验证候选可访问性点击、非激活窗口、加载时旧文字不可见/不可提交、不可用状态、长译文固定高度、失效后隐藏、负坐标显示器与边缘布局。导出 18 张浅/深色候选、译文五种状态（含服务不可用时静态回退）、中英/方案提示 PNG。
- 新入口 `scripts/test-ime.sh`、`scripts/test-rime-capabilities.sh` 已接入 `scripts/test.sh`。测试全部位于 `Tests/InputMethodTests/`；采用仓库已有 standalone Swift 检查方式，不新增 Package、不把 GPL 输入法链接到 MIT App target。`scripts/test.sh` 是为完成 I-2 的接入要求所作的两行修改，未修改既有 `scripts/test-rime.sh`。
- 通过：`scripts/test-ime.sh`；`scripts/test-rime-capabilities.sh`；`scripts/test.sh`；输入法 Release `xcodebuild`。未运行整套 `scripts/build.sh`、签名/安装/注册、真实停服打字性能测试。
- 集成：按用户后续指令将 `main`（包含 pi-ui 偏好同步）合入本分支，无冲突。保留 `RoarkTInputSettings.swift`、`SquirrelApplicationDelegate.swift`、`SquirrelInputController.swift`、Xcode 工程的全部上游修改；未额外编辑这些文件。新面板继续使用同一 controller 调用入口，中英提示开关和翻译开关仍由 controller 管理；真实开关体验待人工验证。

## 问题与人工验收

1. Claude 决定来源字段归属：session/服务协议目前不提供静态/动态/AI 来源，成功统一“候选翻译”。可靠“静态词条”标题需要该模块所有者扩展来源信息；不可依据译文恰好等于词典文本猜测来源。
2. Claude 进行 D0 视觉验收；原生弹窗使用系统投影，Gallery 对照重点为卡片/排版/颜色，系统投影与 Tokens.Shadow 的精确一致性未验收。
3. I-3：干净账户首启自动部署、TextEdit/浏览器/编辑器真实全拼/双拼/Shift/Tab/学习菜单、偏好开关、全屏/多屏/边缘、不抢焦点、减少动态效果、VoiceOver 均待人工验证。自动化 serviceUnavailable 注入不等于真实杀掉翻译服务后试打；NFR-2 延迟仍待人工实测。
4. 规格复核范围的 A10“忘记学习记录”已验证；PRD 中置顶/降权并非现有菜单能力，本规格“不新增功能”下未扩展，不能据此宣称整个 FR-A10 已验收。

### 最新 main 与本机环境规则（2026-10-11）

- 按 Claude 第二次通知合并 `main@7245678`，无冲突；已完整读取新增“本机环境”约定。
- 合并后再次执行 `scripts/test.sh`，124 个 Swift Testing 测试、Rime 部署/能力、session/修饰键/面板、AppShell 检查通过。
- 规则生效后不从 worktree 启动输入法，不运行安装/卸载/注册、不加载 LaunchAgent。本任务从未安装、注册输入法或加载 LaunchAgent；早期预览进程已退出。
- 后续图片复现仅运行 `scripts/test-ime.sh` 的独立测试程序：编译实际面板，但不创建 IMK server、不访问用户 Rime 目录。安装版验证统一由 Claude 从 main 执行。
