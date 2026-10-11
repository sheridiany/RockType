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
| S1 | 设置模型 + 存储 + AI 客户端 + 连接测试 + 诊断日志 | pi-xpc | — | 未开始 |
| S2 | 菜单栏、菜单栏面板、设置窗口、开机启动 | pi-ui | S1 的 Settings 模型（先提交）；U3 菜单栏面板 | 未开始 |
| S3 | 权限中心与全局快捷键接线 | pi-platform | S1 的 Settings 模型 | 未开始 |
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
| 设置读写、损坏回落、即时生效 | 单元测试 + 手工 | 未运行 | |
| AI 客户端四项测试与错误分类 | `URLProtocol` 桩测试；真实端点待用户提供 | 未运行 | |
| 日志脱敏与导出 | 单元测试 | 未运行 | |
| 菜单栏、北京时间、开机启动 | 手工 | 待人工验证 | |
| 权限四态显示与跳转 | 手工 | 待人工验证 | |
| `⌃1` 注册、冲突提示、重设 | 手工 | 待人工验证 | |
| 引导：输入源真实按键验证、语言包状态 | 手工 | 待人工验证 | S4：检测两种输入源；同一来源、同一 XPC 连接内计数递增才通过；macOS 26 检查中英双向并显式准备下载。真实试打与系统下载弹窗未运行，须先完成下方 S5 接线。 |
| 输入法菜单“设置…”拉起主 App | 手工 | 待人工验证 | S4：保留 Bundle ID 查找、未安装禁用与 `--show-settings`；补标准 reopen AppleEvent。主 App 的 AppDelegate 接线归 S2/S5。 |
| Gallery 仍可渲染全部状态 | `scripts/render-gallery.sh` | 通过（S4 分支） | 2026-10-11：134 张 PNG，`dist/gallery/`；这仅验证现有 Gallery，真实引导窗口的视觉与键盘走查待人工验证。 |
| `scripts/test.sh`、`scripts/build.sh` | 命令 | 通过（S4 分支） | 2026-10-11：50 项 Swift 测试、Rime 部署、标识检查通过；主 App、翻译服务、输入法与注册工具构建及 Developer ID 签名验证通过。 |
| S4 引导持久化与 XPC 生命周期 | 自动化测试 | 通过 | `Tests/SettingsStoreTests/OnboardingTests.swift`、`OnboardingXPCTests.swift`：跳过全部步骤、跳到末步不漏步骤、保存失败与重试、重新引导、启动参数优先级、来源切换、计数复位、迟到结果、关闭断连；匿名 XPC 实测发现、取消、4 秒超时、下次调用重建。 |

## 进度

Settings 模型已提交：f87c60a。`Core/Settings/AppSettings.swift` 为公共接口，`scripts/test.sh` 通过（40 tests + Rime 部署与标识检查）。S1 后续存储、AI 与诊断进行中。

### S4 交付（2026-10-11）

- 状态“完成（待验收）”指 S4 所有权内的模块交付；首次启动、设置中的重跑入口、权限与 AI 表单需 S2/S5 接线后才可作端到端验收，当前分支的 AppDelegate 尚未调用引导控制器。
- 依赖：快进接入 S1 模型 `f87c60a`，经合并提交 `3402178` 接入 S1 存储 `84f3818`；未手改 S1 的模型、存储或 Package.swift。
- S4 实现提交：`6faf167`（输入源验证 / XPC）、`2769599`（引导 / 语言包 / 持久化与测试）、`1af7659`（输入法设置菜单 reopen）。末次交付提交补充关闭窗口释放验证连接与本节证据。
- 新增 `App/Shell/Onboarding/` 五个文件及 `App/Shell/TranslationServiceClient.swift`；沿用 U4 设计变量与组件，保留 `App/Surfaces/`、Mock 与 Gallery 不变。
- 权限与 AI 表单由构造参数注入相同的设置视图，不另建权限实例、密钥存储或连接测试。语音模型明确显示“即将推出”，只有跳过入口。
- 完成或全部跳过后同步 `SettingsStore.flush()`；保存失败留在引导中，可重试。关闭未完成的窗口不写完成标记；设置中重跑不清除已保存的首次启动标记。
- 人工验证未运行：安装/选中输入源与真实试打，翻译服务被杀后的签名连接恢复，语言包已安装/缺失/下载取消/失败与 macOS 14–25 降级，权限四态与 AI 四项测试，首次/重复启动设置路由，浅深色、VoiceOver、纯键盘走查。

## 问题

### S4 → Claude/S5 接线交接（文件归属限制，未越界修改）

1. S2 的 `AppDelegate` 保留一个 `OnboardingWindowController(store:permissions:aiConnection:showSettings:)`，`store` 必须是设置窗口的同一个 `SettingsStore`；`permissions` 与 `aiConnection` 是返回 `AnyView` 的闭包，分别嵌入 S3 权限中心视图和共享的 AI 连接表单/四项测试。
2. `applicationDidFinishLaunching` 在窗口控制器就绪后调用其同名方法；该方法使 `--show-settings` 优先于首次引导，且跳过 Gallery 模式。传入的 `showSettings` 必须显示并激活设置窗口。
3. `AppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)` 转发到 `onboarding.applicationShouldHandleReopen()`。已运行进程不重新读取启动参数；输入法菜单明确发送标准 reopen 事件。
4. 设置 → 通用 的“重新运行引导”按钮调用 `onboarding.rerun()`。
5. 请 Claude 确认 AI 表单最终提供者：S4 原文称“S1 的连接表单”，但 S1 所有权是客户端/存储，表单接线归 S2。本实现按复用 S2 的同一表单设计，避免重复状态。S3 权限中心的 start/stop 仍由共享外壳管理。

以上接线未完成前，FR-E5 与输入法打开设置的端到端验收仍为阻塞；自动化通过不代表这些功能已集成。
