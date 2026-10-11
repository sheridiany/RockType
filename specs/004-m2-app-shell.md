# SPEC-004 主 App 外壳（M2）

- 阶段：M2
- 覆盖需求：FR-F1、FR-F2、FR-F6、FR-E2、FR-E4、FR-E5、FR-E6、FR-E7；输入法菜单“设置”入口
- 状态：Ready

## 范围

把 D0 的界面接到真实数据与系统能力，得到一个可日常常驻的菜单栏主 App：菜单栏与面板、统一设置窗口（各分区读写真实设置）、AI 连接与连接测试、权限中心、全局快捷键、首次引导、开机启动、本地诊断日志。

不做：划词、结果浮窗的真实 AI 流程（M3）、截图（M4）、语音录音与识别（M5）。这些分区在设置中可显示与保存配置，但功能入口标“即将推出”，不能是无响应按钮。

## 架构约定

- **设置模型**：`Core/Settings/`。`AppSettings`（Codable、Sendable、带 `schemaVersion`），文件 `~/Library/Application Support/RoarkT/settings.json`，原子写入；缺失或损坏时回落默认值并保留损坏文件副本（`settings.json.corrupt-<时间>`）。不兼容旧产品，不读取任何 RoType/RoarkTools 路径。
- **设置存储**：`App/Shell/SettingsStore.swift`，`@MainActor @Observable`，唯一读写入口；修改即时生效并持久化（节流 ≤ 300ms）；对外暴露变更通知供快捷键、开机启动等订阅。
- **密钥**：只存钥匙串（`Platform/Keychain`，服务名 `Identifiers.keychainService`，account 为服务商连接 ID）。`settings.json` 中只有 `hasAPIKey` 之类的派生状态都不存，界面显示状态时实时查询钥匙串。
- **AI 客户端**：`Core/AI/`。OpenAI Chat Completions 兼容：非流式、SSE 流式、图片输入（data URL）、取消（Task 取消即断开）、超时；错误分类：配置错误、网络、401/403、404 模型、429 限流、5xx、解码。不记录请求体与响应体。迁移参考 `../RoarkTools/internal/ai/client.go` 与测试。
- **连接测试**：文字、流式、图片、取消四项分别得出 可用 / 不可用 / 未验证，对应 D0 设置界面的四格。
- **诊断日志**：`Core/Diagnostics/`，`os.Logger`（subsystem `com.roarkist.roarkt`）+ 本地滚动文件（`~/Library/Logs/RoarkT/`，单文件 ≤ 2MB，保留 5 个）；只记录动作类型、状态、耗时、脱敏错误。设置 → 关于 中“导出诊断…”生成 zip。
- **界面接线**：D0 的 `App/Surfaces/` 视图保持纯视图；新增 `App/Shell/`（窗口、状态栏、视图模型、把 Store 映射为视图数据）。Gallery 与 `--render-gallery` 必须继续可用（视图仍接受 Mock 数据）。

## 任务

| # | 任务 | 执行 | 依赖 | 状态 |
| --- | --- | --- | --- | --- |
| S1 | 设置模型 + 存储 + AI 客户端 + 连接测试 + 诊断日志 | pi-xpc | — | 完成（待验收） |
| S2 | 菜单栏、菜单栏面板、设置窗口、开机启动 | pi-ui | S1 的 Settings 模型（先提交）；U3 菜单栏面板 | 未开始 |
| S1 | 设置模型 + 存储 + AI 客户端 + 连接测试 + 诊断日志 | pi-xpc | — | 未开始 |
| S2 | 菜单栏、菜单栏面板、设置窗口、开机启动 | pi-ui | S1 的 Settings 模型（先提交）；U3 菜单栏面板 | 完成（待验收） |
| S3 | 权限中心与全局快捷键接线 | pi-platform | S1 的 Settings 模型 | 未开始 |
| S3 | 权限中心与全局快捷键接线 | pi-platform | S1 的 Settings 模型 | 完成（待验收） |
| S4 | 首次引导与输入法“设置”入口 | pi-ime | S1 的 Settings 模型 | 未开始 |
| S4 | 首次引导与输入法“设置”入口 | pi-ime | S1 的 Settings 模型 | 完成（待验收） |
| S5 | 集成验收 | Claude | S1–S4 | 未开始 |

### S1（pi-xpc，分支 agent/xpc）

1. **第一个 commit 只包含 `Core/Settings/` 的模型与默认值**（覆盖 PRD 中所有设置项：通用、输入法、翻译、语音、划词、截图、AI 连接、操作模板、快捷键、隐私），加单元测试。提交后在规格“进度”节写一行“Settings 模型已提交：<hash>”，其他 agent 据此合并。
2. 持久化与 `SettingsStore`（`App/Shell/SettingsStore.swift`）、损坏回落测试。
3. `Core/AI/`：客户端、SSE 解析、错误分类、连接测试；用本地 `URLProtocol` 桩测试，不访问真实网络。
4. `Core/Diagnostics/`：日志、脱敏、滚动、导出 zip；测试脱敏（URL query、Authorization、正文不落盘）。
- 文件所有权：`Core/Settings/`、`Core/AI/`、`Core/Diagnostics/`、`App/Shell/SettingsStore.swift`、对应 `Tests/`、`Package.swift` 仅新增测试 target。

### S2（pi-ui，分支 agent/ui）

- 状态栏图标（模板图，参考 `../RoarkTools/assets/tray/`，改为 RoarkT 字形）；可选“北京 HH:mm”（`Asia/Shanghai`，默认关闭，FR-F1），跨日、睡眠唤醒、时区变化刷新。
- 左键打开菜单栏面板（U3 的 MenuBarPanel，NSPanel 承载，点外部关闭）；右键菜单：设置 `⌘,`、设计面板（Debug）、退出。
- 设置窗口：U4 的 SettingsView 接 `SettingsStore`，各分区读写真实设置；AI 连接分区接 S1 的连接测试与钥匙串；关于分区“导出诊断…”。权限与快捷键分区的数据源由 S3 提供，先用协议占位。
- 开机启动：`SMAppService.mainApp`，状态与设置一致（FR-F2）。
- 依赖：等 S1 第一个 commit 后 `git merge agent/xpc`；U3（agent/surfaces）合并到 main 后 `git merge main` 获取 MenuBarPanel。等待方式：每 3 分钟检查一次，最多 60 分钟。
- 文件所有权：`App/Shell/`（SettingsStore.swift 除外）、`App/AppDelegate.swift`、`App/main.swift`、`App/Info.plist`、`App/Resources/`。

### S3（pi-platform，分支 agent/platform）

- `App/Shell/Permissions/`：权限中心视图模型，轮询或通知刷新辅助功能、屏幕录制、麦克风状态；“打开系统设置”；按功能说明用途（FR-E6）。只请求用户触发的那一项。
- `App/Shell/Hotkeys/`：读取 Settings 中的快捷键，用 `Platform/GlobalHotkeys` 注册；冲突/失败状态回写到设置界面；修改即时重注册（FR-E7）。Fn 用 `FnKeyMonitor`，M2 只做“按住 Fn 时在日志记录一次事件”的探针，录音属于 M5。
- 快捷键录制控件（设置 → 快捷键）：录制、冲突提示、恢复默认。
- 文件所有权：`App/Shell/Permissions/`、`App/Shell/Hotkeys/`、`Platform/` 中需要的补充、对应测试。

### S4（pi-ime，分支 agent/ime）

- `App/Shell/Onboarding/`：U4 引导界面接真实状态：
  1. 输入源：检测 RoarkT 输入源是否已添加 / 已选中；引导打开“键盘”设置；真实按键验证用翻译服务 `controllerInputGeneration` 前后对比（参考 `../RoType/Sources/RoTypeApp/InputSourceManager.swift`、`ControllerInputVerificationClient.swift`）。不静默启用或选择输入源。
  2. 语言包：macOS 26 用 `LanguageAvailability` 检查中英状态并引导下载；更早系统说明使用静态词条与 AI。
  3. 权限：调用 S3 的权限中心（未合并前用协议占位）。
  4. 语音模型：本阶段只显示说明并可跳过（下载属 M5）。
  5. AI：复用 S1 的连接表单与测试。
  - 首次启动自动打开；完成或全部跳过后不再自动弹出；设置 → 通用 中可“重新运行引导”。
- 主 App 侧的翻译服务客户端（`App/Shell/TranslationServiceClient.swift`：ping、controllerInputGeneration、dictationEndpoint），连接中断自动重建。
- 输入法菜单“设置…”：用 `NSWorkspace` 按 Bundle ID 打开主 App 并带参数 `--show-settings`；主 App 未安装时禁用该菜单项。主 App 处理 `--show-settings` 与重复启动（已运行时激活设置窗口）。
- 文件所有权：`App/Shell/Onboarding/`、`App/Shell/TranslationServiceClient.swift`、`InputMethod/`、对应测试。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 设置读写、损坏回落、即时生效 | 单元测试 + 手工 | 自动化通过；UI 待人工验证 | `SettingsTests`、`SettingsPersistenceTests`、`SettingsStoreTests`：默认值/编辑往返、损坏副本、原子保存、0600 权限、立即通知、250ms 节流、重启读回、读取失败不覆盖；真实设置界面由 S2 接线验收 |
| AI 客户端四项测试与错误分类 | `URLProtocol` 桩测试；真实端点待用户提供 | 本地桩通过；真实端点未运行 | `AIClientTests`：文字/流式/图片/取消四格成功与错误状态、UTF-8 字节分片、SSE 多行/CRLF/截断/限长、401/403/404/429/5xx、超时、模型图片能力约束；取消确认底层 `stopLoading` |
| 日志脱敏与导出 | 单元测试 | 通过 | `DiagnosticsTests`：固定字段拒绝原始错误内容；URL query/Authorization/正文合成标记不落盘；滚动文件上限 2MB、最多 5 个；ZIP 解包检查、丢弃额外字段、拒绝无效记录 |
| 菜单栏、北京时间、开机启动 | 手工 | 待人工验证 | |
| 权限四态显示与跳转 | 手工 | 待人工验证 | S3 已提供实时权限中心；自动检查覆盖单项请求、拒绝→授予→撤销、打开设置失败；真实系统弹窗与跳转未验证。 |
| `⌃1` 注册、冲突提示、重设 | 手工 | 待人工验证 | S3 桩检查覆盖默认注册、系统/内部冲突、重设、外部设置变更、暂停录制、过期回调与安全输入；真实 Carbon 注册和键盘操作待验收。 |
| 引导：输入源真实按键验证、语言包状态 | 手工 | 待人工验证 | |
| 输入法菜单“设置…”拉起主 App | 手工 | 待人工验证 | |
| Gallery 仍可渲染全部状态 | `scripts/render-gallery.sh` | 渲染通过；视觉待人工验收 | 当前分支产出 `dist/gallery/` 共 134 张 PNG；未宣称 UI 设计验收通过 |
| `scripts/test.sh`、`scripts/build.sh` | 命令 | 测试通过；全量构建阻塞 | 60 个 Swift tests + Rime 部署/标识检查通过；主 App、翻译服务 release 构建与签名通过；输入法因未初始化子模块停止（exit 1），未修改 S1 之外目录 |
| 权限四态显示与跳转 | 手工 | 待人工验证 | |
| `⌃1` 注册、冲突提示、重设 | 手工 | 待人工验证 | |
| 引导：输入源真实按键验证、语言包状态 | 手工 | 待人工验证 | S4：检测两种输入源；同一来源、同一 XPC 连接内计数递增才通过；macOS 26 检查中英双向并显式准备下载。真实试打与系统下载弹窗未运行，须先完成下方 S5 接线。 |
| 输入法菜单“设置…”拉起主 App | 手工 | 待人工验证 | S4：保留 Bundle ID 查找、未安装禁用与 `--show-settings`；补标准 reopen AppleEvent。主 App 的 AppDelegate 接线归 S2/S5。 |
| Gallery 仍可渲染全部状态 | `scripts/render-gallery.sh` | 通过（S4 分支） | 2026-10-11：134 张 PNG，`dist/gallery/`；这仅验证现有 Gallery，真实引导窗口的视觉与键盘走查待人工验证。 |
| `scripts/test.sh`、`scripts/build.sh` | 命令 | 通过（S4 分支） | 2026-10-11：50 项 Swift 测试、Rime 部署、标识检查通过；主 App、翻译服务、输入法与注册工具构建及 Developer ID 签名验证通过。 |
| S4 引导持久化与 XPC 生命周期 | 自动化测试 | 通过 | `Tests/SettingsStoreTests/OnboardingTests.swift`、`OnboardingXPCTests.swift`：跳过全部步骤、跳到末步不漏步骤、保存失败与重试、重新引导、启动参数优先级、来源切换、计数复位、迟到结果、关闭断连；匿名 XPC 实测发现、取消、4 秒超时、下次调用重建。 |

## 进度

Settings 模型已提交：f87c60a。`Core/Settings/AppSettings.swift` 为公共接口，`scripts/test.sh` 通过（40 tests + Rime 部署与标识检查）。S1 其余任务已完成（待验收）。

### S1 后续提交与接线说明（2026-10-11）

- `31ba621`：单独登记模型提交，供其他 agent 合并。
- `84f3818`：`SettingsPersistence` 与 `@MainActor @Observable SettingsStore`，损坏回落、即时通知、持久化测试；仅为 Store 新增测试 target。
- `b942c74`：`AIClient`、`AIConnectionTester`、SSE 与本地 `URLProtocol` 测试；默认 ephemeral 会话，无磁盘缓存/Cookie，不跟随重定向。
- `912f033`：`DiagnosticLog` actor、固定词汇 `DiagnosticEvent`、滚动与安全 ZIP 导出测试。
- `bcf28a7`：读取失败保护、四项连接探针成功路径、按所选模型检查图片能力。
- S2/S3/S4 使用 `SettingsStore.shared.settings`；变更立即通过 Observation 与 `SettingsStore.didChange` 通知；保存每 250ms 节流，退出时调用 `flush()`；读取失败不覆盖原文件，错误显示于 `persistenceError`。`general.onboardingCompleted` 控制引导完成状态，`shortcuts.bindings` 沿用 `ShortcutAction` / `Shortcut`。
- AI 密钥由调用者从钥匙串实时读取，传入 `AIClient.complete` / `stream` 或 `AIConnectionTester.run`，不进入 Settings。`stream` 在调用者 Task 中执行，取消 Task 即取消传输。连接测试为 `text` / `streaming` / `image` / `cancellation` 四格；未声明图片模型时图片为未验证，请求在取消前已完成时取消为未验证。
- 诊断入口：`try await DiagnosticLog.shared.record(DiagnosticEvent(...))`；保存面板选择路径后 `try await DiagnosticLog.shared.exportZIP(to:)`。日志只接受枚举字段，不传选中文字、URL、密钥或原始错误描述。
- 验证日志在本工作树任务的 `/tmp/roarkt-s1-test.log`、`/tmp/roarkt-s1-build.log`、`/tmp/roarkt-s1-gallery.log`；构建产物和截图未纳入提交。
- 未验证：真实 AI 服务/凭据、设置窗口接线与退出保存、钥匙串接线、真实权限/快捷键/输入法、完整输入法构建、UI 人工验收。无 push、无合并、未修改其他 worktree。

### S4 交付（2026-10-11）

- 状态“完成（待验收）”指 S4 所有权内的模块交付；首次启动、设置中的重跑入口、权限与 AI 表单需 S2/S5 接线后才可作端到端验收，当前分支的 AppDelegate 尚未调用引导控制器。
- 依赖：快进接入 S1 模型 `f87c60a`，经合并提交 `3402178` 接入 S1 存储 `84f3818`；未手改 S1 的模型、存储或 Package.swift。
- S4 实现提交：`6faf167`（输入源验证 / XPC）、`2769599`（引导 / 语言包 / 持久化与测试）、`1af7659`（输入法设置菜单 reopen）。末次交付提交补充关闭窗口释放验证连接与本节证据。
- 新增 `App/Shell/Onboarding/` 五个文件及 `App/Shell/TranslationServiceClient.swift`；沿用 U4 设计变量与组件，保留 `App/Surfaces/`、Mock 与 Gallery 不变。
- 权限与 AI 表单由构造参数注入相同的设置视图，不另建权限实例、密钥存储或连接测试。语音模型明确显示“即将推出”，只有跳过入口。
- 完成或全部跳过后同步 `SettingsStore.flush()`；保存失败留在引导中，可重试。关闭未完成的窗口不写完成标记；设置中重跑不清除已保存的首次启动标记。
- 人工验证未运行：安装/选中输入源与真实试打，翻译服务被杀后的签名连接恢复，语言包已安装/缺失/下载取消/失败与 macOS 14–25 降级，权限四态与 AI 四项测试，首次/重复启动设置路由，浅深色、VoiceOver、纯键盘走查。

## 问题

- Claude 集成时需在负责输入法的工作树补齐子模块后重跑完整 `scripts/build.sh`；本工作树主 App/翻译服务已签名，不能代替输入法构建验收。
- 当前 AI Base URL 仅允许 HTTPS（且不允许 userinfo/query/fragment），阻止密钥经明文发送；若产品要支持本机 HTTP 兼容端点，请决定是否只放行 loopback 并另行补充测试。
- 同一 schemaVersion 当前严格完整解码；不支持的 schema 或缺字段按损坏配置保留副本并回落默认值。后续新增设置字段时需明确默认解码策略；不涉及旧产品迁移。
### S2 交给 Claude 的集成决定

1. U3 `MenuBarPanelView` 与 U4 `SettingsView` 把按钮动作和模拟状态封装在视图内部，没有生产回调/Binding 接口；它们不在 S2 文件所有权内。本分支保留它们及 Gallery，在 `App/Shell/` 新增生产视图，复用 Tokens、U4Card、U4Toggle、Notice 等组件。请确认该边界方案与生产界面视觉；如要合一，请另安排 Surfaces 所有者提取共享展示接口，不能直接把演示动作带入生产。
2. S5 在 `AppDelegate` 创建 `SettingsWindowController` 时注入 `ShellSettingsSections`：`permissionsPane()` / `shortcutsPane()` 接 S3，`showOnboarding()` 接 S4。目前显式显示“等待集成”，不展示假授权、不注册模拟快捷键。S4 的首次自动引导也需在 AppDelegate 统一组装；S2 已处理 `--show-settings` 与重复启动时复用设置窗口。
3. 输入法设置目前保存到统一 SettingsStore；需要 Claude 确认输入法侧实时消费链路归属与验收。语言包真实状态由 S4 提供。界面明确标示同步待集成，未宣称跨进程即时生效。
4. 当前 `scripts/build.sh` 在完成主 App/翻译服务 Release 构建及签名后，因当前 worktree 输入法子模块未初始化退出 1；请在集成 worktree 初始化固定依赖后跑全产物构建。S2 未改动 InputMethod 或构建脚本。

## S2 验收证据（2026-10-11）

**状态：完成（待验收）**。仅 S2 实现与自动化自查完成，系统交互、设计与 S5 集成仍待 Claude 验收。

### 实现与边界

- RoarkT `R` 模板字形状态栏图标；左键 NSPanel、右键设置 / Debug 设计面板 / 退出；主菜单支持 `⌘,`、`⌘Q` 和文本编辑快捷键。面板点外部关闭、Esc 关闭、切换应用关闭；坐标限制在状态项所在屏幕的可见范围，不请求辅助功能来监听键盘。
- 北京时间默认关闭，开启显示 `北京 HH:mm`；面板始终显示北京日期/星期和本地时间。固定 `Asia/Shanghai`，按分钟刷新，同时监听唤醒、系统时钟和时区变化；时钟变化不写设置文件。
- 设置窗口 12 分区，复用单一窗口、支持滚动与浅深主题；通过 S1 SettingsStore 读写真实偏好。菜单栏时钟和主题即时更新；语音/划词/截图/模板执行清楚标为即将推出。输入法跨进程消费及 S3/S4 界面注入见问题节。
- 开机启动使用 `SMAppService.mainApp`，读取实际系统状态；设置失败或待用户批准时展示原因，返回 App 时重新同步；不在启动时根据旧的偏好自动注册登录项。
- AI 设置只将非密钥字段写入 SettingsStore；SecureField 编辑密钥、保存/删除走 S1 约定的 Keychain account。四项能力测试调用 S1 AIConnectionTester，逐项显示可用/不可用/未验证及固定错误原因；只发送合成样本。取消、修改配置或密钥后旧结果不能覆盖新状态；Secure Input 开启时拒绝测试，测试期间开启则取消。
- 关于页 NSSavePanel 导出 S1 的诊断 ZIP；只记录封闭词汇的动作、状态和耗时，不记录连接字段、响应正文、密钥或导出文件路径。目标已存在时不覆盖，提示换新文件名。
- 没有修改 `App/Surfaces/`、`App/Mock/`、`App/Gallery/`、S1 SettingsStore 或 S3/S4 文件；其他目录变化仅来自规格要求的依赖 merge。没有 push、没有 merge 到 main、没有修改其他 worktree。

### 提交

- `40e911a`：时钟与开机启动封装。
- `ab78daa`：生产菜单栏面板、设置窗口、持久化绑定与钥匙串表单。
- `852870b`：AI 能力测试、诊断导出、面板键盘焦点与分钟刷新收尾。
- 依赖 merge：`fc8203c`（main / U3），`9c23baa`（S1 Settings 模型），`6764fc8`（S1 SettingsStore），`d73747c`（S1 AI），`b120876`（S1 诊断）。

### 验证记录

环境：Apple Silicon，Swift 6，当前 macOS 27；部署目标 macOS 14。

| 命令 / 检查 | 结果 | 证据与限制 |
| --- | --- | --- |
| `swift build` | 通过 | 最终 S2 + 已合入 S1/U3 编译成功 |
| `scripts/test.sh` | 通过 | 最终 57 项 Swift 测试、3 个 Rime 方案新鲜部署、旧标识扫描；S1 的设置/AI/诊断测试包含在内 |
| `scripts/render-gallery.sh` | 通过 | `dist/gallery/` 共 208 张浅深主题 PNG，D0 入口保持可用；本次未重新执行 U3/U4 全量视觉验收 |
| 临时 Swift 验证程序 | 通过 | `2026-10-11T15:59Z → 16:00Z` 验证北京 `23:59 → 00:00`、日期 11 → 12、星期一；同一 SettingsWindowController 连续 show 两次及关闭后重开始终只有一个设置窗口；使用临时设置文件并清理 |
| 生产 Shell 渲染自查 | 通过（自查） | `dist/s2-review/`：12 设置分区 × 2 主题 + 时钟开关 × 2 主题，共 28 PNG；全部查看，默认视口可读，输入法/划词/模板长页通过滚动继续浏览；不包含用户配置或内容。不是完整键盘交互验收 |
| `scripts/build.sh` | **阻塞（退出 1）** | 主 App、翻译服务 Release 构建与签名验证通过；随后提示 `Initialize dependencies with git submodule update --init --recursive.`，输入法完整构建未执行；未越界初始化/更改其依赖 |
| `git diff --check` | 通过 | 自有代码无空白错误；最终文档修改后再次检查 |

临时验证源保留在忽略的 `dist/s2-review/verify.swift`，截图同目录。复现命令（先 `swift build`，不读用户密钥、不请求权限、不改变登录项）：

```sh
swiftc -swift-version 6 -parse-as-library -module-name RoarkTApp \
  -I .build/arm64-apple-macosx/debug/Modules -I Shared/XPCProtocol/include \
  $(rg --files App -g '*.swift' | rg -v '^App/main.swift$') \
  dist/s2-review/verify.swift \
  $(rg --files .build/arm64-apple-macosx/debug | rg '(RoarkTCore.build|RoarkTPlatform.build)/.*\.o$') \
  -o /tmp/roarkt-s2-verify
/tmp/roarkt-s2-verify dist/s2-review
```

### 待人工验证 / 未验证

- 菜单栏左右键、点外关闭/Esc、真实键盘编辑与 VoiceOver；多显示器/全屏下定位；实际睡眠唤醒与更改系统时区。
- 已安装并签名 App 的开机启动启用、拒绝/允许批准、关闭、注销后重新登录；本次没有改变用户登录项。
- 真实密钥保存/更换/删除与真实 AI 端点四项能力测试、Secure Input 中途取消；本次没有使用真实凭据或外部网络，Core URLProtocol 桩通过不代表真实端点验收。
- NSSavePanel 交互式导出、打开 ZIP；Core 诊断导出与脱敏测试通过，但未以用户身份执行保存对话框。
- S3 权限/快捷键与 S4 引导组装、输入法菜单打开设置端到端、输入法设置跨进程即时生效。
- Claude 的生产界面设计验收、macOS 14 真机、NFR-3 空闲功耗实测。
### S3（pi-platform）完成（待验收）
- 依赖：Settings 模型 `f87c60a` 已合入当前 `agent/platform`，合并提交 `237edf3`；未修改其他 worktree、未 push、未合并 main。
- `d5fd9c8`：权限中心及视图；每 2 秒刷新，查询不弹权限请求；按钮仅申请指定权限，支持打开对应系统设置。AX/屏幕录制 API 仅返回布尔值，明确显示“未授权（系统未区分首次与拒绝）”，不伪造首次/拒绝状态。麦克风覆盖尚未请求、授权、拒绝、限制状态。
- `69fe99e`：快捷键中心与原生录制控件；读取 `ShortcutSettings`，使用 Observation 跟踪注入的 Store 读取闭包；修改、恢复默认和外部变更均重注册。重复组合键与系统注册失败反馈到各行。录制期间停用全局注册，Esc/离开窗口或分区取消；注册代次阻止旧回调执行。
- Fn 使用现有 `FnKeyMonitor`，一次按住只在 press 记录 `action=voiceHoldProbe status=pressed`，不记录文字、不录音；安全输入/无法确认安全状态时不记录。辅助功能授权变化后重试注册。截图、翻译、总结在界面明确标“即将推出”。
#### S3 验收证据（当前 worktree）
| 检查 | 结果 | 证据与边界 |
| `bash Tests/AppShellTests/run.sh` | 通过 | PermissionCenterChecks / HotkeyChecks 均通过；注入系统能力桩，无弹窗、无真实按键。独立编译检查以避免修改 S1 所有的 Package.swift。 |
| `scripts/test.sh` | 通过 | 19 个 XCTest + 40 个 Swift Testing 测试；Rime 部署检查与旧标识扫描通过。 |
| `swift build` | 通过 | Swift 6 下主 App 与新增 SwiftUI/AppKit 控件编译通过。 |
| `scripts/build.sh` | 阻塞 | 主 App、翻译服务 release 构建及签名验证通过；输入法阶段因 librime/plum/Sparkle 子模块未初始化退出，完整产物构建未通过。 |
| `scripts/render-gallery.sh /tmp/roarkt-s3-gallery` | 通过 | 原 Gallery 渲染 134 张 PNG；只证明现有模拟视图回归可用，不代表新增实时面板设计验收通过。 |
| 权限与快捷键真实交互、浅深色与 VoiceOver | 待人工验证 | 在签名主 App 中走查首次/拒绝/授予/撤销、系统设置跳转、真实 ⌃1 冲突/重设、录制取消、Fn 长按/组合键/安全输入/权限撤销、系统 Fn 行为冲突。 |
#### S2 / S4 接入边界
- S2 持有一个 `PermissionCenter`，App 生命周期调用 `start()` / `stop()`；设置权限分区使用 `PermissionCenterView(center:)`。S4 可复用同一实例，通过 `items`、`request(_:)`、`openSettings(_:)` 接引导。不要在引导出现时自动请求权限。
- S2 持有一个 `HotkeyCenter(read:write:showSettings:)`：`read` 直接读取 Observable SettingsStore 的 `ShortcutSettings`，`write` 通过 Store 唯一入口保存，`showSettings` 打开现有设置窗口。启动/退出调用 `start()` / `stop()`；快捷键分区使用 `HotkeySettingsView(center:)`。运行状态仅在内存中，不写 settings.json。
- 上述生命周期与设置窗口装配归 S2；S3 未越权修改 AppDelegate、SettingsView、SettingsStore 或 Info.plist，合并后需 S5 验证真实接线。
- S3 → Claude/S2：`App/Info.plist` 尚无 `NSMicrophoneUsageDescription`。请 S2 补充准确用途说明后，在签名主 App 验收请求；S3 在缺失说明时返回错误，避免系统终止进程。
- S3 → Claude：请确认 S2 按上述接口接入实时权限/快捷键分区并管理生命周期；当前 S3 的完成范围是所拥有目录的可编译模块，真实窗口集成待 S5 验收。
- S3 → Claude：当前 worktree 未初始化输入法子模块，完整构建阻塞；请在集成 worktree 运行完整构建。Fn 与系统听写/切换输入源的冲突无法由 Carbon 注册结果证明，界面已提示，仍需人工确认系统键盘设置。
### S4 → Claude/S5 接线交接（文件归属限制，未越界修改）
1. S2 的 `AppDelegate` 保留一个 `OnboardingWindowController(store:permissions:aiConnection:showSettings:)`，`store` 必须是设置窗口的同一个 `SettingsStore`；`permissions` 与 `aiConnection` 是返回 `AnyView` 的闭包，分别嵌入 S3 权限中心视图和共享的 AI 连接表单/四项测试。
2. `applicationDidFinishLaunching` 在窗口控制器就绪后调用其同名方法；该方法使 `--show-settings` 优先于首次引导，且跳过 Gallery 模式。传入的 `showSettings` 必须显示并激活设置窗口。
3. `AppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)` 转发到 `onboarding.applicationShouldHandleReopen()`。已运行进程不重新读取启动参数；输入法菜单明确发送标准 reopen 事件。
4. 设置 → 通用 的“重新运行引导”按钮调用 `onboarding.rerun()`。
5. 请 Claude 确认 AI 表单最终提供者：S4 原文称“S1 的连接表单”，但 S1 所有权是客户端/存储，表单接线归 S2。本实现按复用 S2 的同一表单设计，避免重复状态。S3 权限中心的 start/stop 仍由共享外壳管理。
以上接线未完成前，FR-E5 与输入法打开设置的端到端验收仍为阻塞；自动化通过不代表这些功能已集成。
