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
| S2 | 菜单栏、菜单栏面板、设置窗口、开机启动 | pi-ui | S1 的 Settings 模型（先提交）；U3 菜单栏面板 | 完成（待验收） |
| S3 | 权限中心与全局快捷键接线 | pi-platform | S1 的 Settings 模型 | 未开始 |
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
| 权限四态显示与跳转 | 手工 | 待人工验证 | |
| `⌃1` 注册、冲突提示、重设 | 手工 | 待人工验证 | |
| 引导：输入源真实按键验证、语言包状态 | 手工 | 待人工验证 | |
| 输入法菜单“设置…”拉起主 App | 手工 | 待人工验证 | |
| Gallery 仍可渲染全部状态 | `scripts/render-gallery.sh` | 未运行 | |
| `scripts/test.sh`、`scripts/build.sh` | 命令 | 未运行 | |

## 进度

Settings 模型已提交：f87c60a。`Core/Settings/AppSettings.swift` 为公共接口，`scripts/test.sh` 通过（40 tests + Rime 部署与标识检查）。S1 后续存储、AI 与诊断进行中。

## 问题

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
