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
| S3 | 权限中心与全局快捷键接线 | pi-platform | S1 的 Settings 模型 | 完成（待验收） |
| S4 | 首次引导与输入法“设置”入口 | pi-ime | S1 的 Settings 模型 | 未开始 |
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
| 权限四态显示与跳转 | 手工 | 待人工验证 | S3 已提供实时权限中心；自动检查覆盖单项请求、拒绝→授予→撤销、打开设置失败；真实系统弹窗与跳转未验证。 |
| `⌃1` 注册、冲突提示、重设 | 手工 | 待人工验证 | S3 桩检查覆盖默认注册、系统/内部冲突、重设、外部设置变更、暂停录制、过期回调与安全输入；真实 Carbon 注册和键盘操作待验收。 |
| 引导：输入源真实按键验证、语言包状态 | 手工 | 待人工验证 | |
| 输入法菜单“设置…”拉起主 App | 手工 | 待人工验证 | |
| Gallery 仍可渲染全部状态 | `scripts/render-gallery.sh` | 未运行 | |
| `scripts/test.sh`、`scripts/build.sh` | 命令 | 未运行 | |

## 进度

### S3（pi-platform）完成（待验收）

- 依赖：Settings 模型 `f87c60a` 已合入当前 `agent/platform`，合并提交 `237edf3`；未修改其他 worktree、未 push、未合并 main。
- `d5fd9c8`：权限中心及视图；每 2 秒刷新，查询不弹权限请求；按钮仅申请指定权限，支持打开对应系统设置。AX/屏幕录制 API 仅返回布尔值，明确显示“未授权（系统未区分首次与拒绝）”，不伪造首次/拒绝状态。麦克风覆盖尚未请求、授权、拒绝、限制状态。
- `69fe99e`：快捷键中心与原生录制控件；读取 `ShortcutSettings`，使用 Observation 跟踪注入的 Store 读取闭包；修改、恢复默认和外部变更均重注册。重复组合键与系统注册失败反馈到各行。录制期间停用全局注册，Esc/离开窗口或分区取消；注册代次阻止旧回调执行。
- Fn 使用现有 `FnKeyMonitor`，一次按住只在 press 记录 `action=voiceHoldProbe status=pressed`，不记录文字、不录音；安全输入/无法确认安全状态时不记录。辅助功能授权变化后重试注册。截图、翻译、总结在界面明确标“即将推出”。

#### S3 验收证据（当前 worktree）

| 检查 | 结果 | 证据与边界 |
| --- | --- | --- |
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


## 问题

- S3 → Claude/S2：`App/Info.plist` 尚无 `NSMicrophoneUsageDescription`。请 S2 补充准确用途说明后，在签名主 App 验收请求；S3 在缺失说明时返回错误，避免系统终止进程。
- S3 → Claude：请确认 S2 按上述接口接入实时权限/快捷键分区并管理生命周期；当前 S3 的完成范围是所拥有目录的可编译模块，真实窗口集成待 S5 验收。
- S3 → Claude：当前 worktree 未初始化输入法子模块，完整构建阻塞；请在集成 worktree 运行完整构建。Fn 与系统听写/切换输入源的冲突无法由 Carbon 注册结果证明，界面已提示，仍需人工确认系统键盘设置。
