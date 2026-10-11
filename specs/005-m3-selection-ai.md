# SPEC-005 划词与 AI（M3）

- 阶段：M3
- 覆盖需求：FR-C1–C15、FR-E1（AI 路径与划词翻译）、FR-E8（取词部分）
- 状态：Ready
- 依赖：SPEC-004 设置、AI 客户端、权限、快捷键；SPEC-010 Platform；D0 界面 1–3

## 范围

划词或快捷键 → 内容快照 → 操作（翻译、解释、总结、润色、自定义模板、搜索、复制）→ 结果浮窗（流式、追问、复制并返回来源）→ 会话内最近结果。

不做：截图入口（M4）、输入法内 AI（M6）、自动回填。

## 架构

- **内容快照** `Core/Operations/ContentSnapshot.swift`：文字、来源（pid、bundle ID、应用名、窗口标识）、取词方式（直接读取 / 复制回退 / 粘贴）、选区屏幕矩形、时间。创建后不可变。
- **操作引擎** `Core/Operations/`：`OperationRunner` 按模板构造请求，调用 `AIClient.stream`；会话（快照 + 已完成问答 + 新问题）；`generation` 隔离，取消或新操作后迟到结果丢弃；超长输入按模型上限明确报错，不截断。翻译操作按 `TranslationSettings.engine` 路由：`offlineFirst` 走翻译服务 `translateText`（Apple Translation，失败回落 AI），`ai` 直接走 AI。
- **翻译服务新接口** `translateText(sessionID:generation:text:target:withReply:)`：仅主 App 可调用；中英与指定目标语言；保留段落结构（按段翻译再拼接）。
- **最近结果** `App/Features/Operations/RecentResults.swift`：内存 10 条，退出或“清除当前内容”清空。
- **划词监听** `App/Features/Selection/`：全局鼠标监听（拖选、双击、三击），在 mouse-up 后读取选区；黑白名单（Finder 默认排除）；Secure Input 时什么都不做；触发方式“划词即出 / 仅快捷键”。工具栏为非激活 `NSPanel`，位置用 `Platform/Placement`，点外部或按键即隐藏。
- **结果浮窗** `App/Features/ResultWindow/`：非激活 `NSPanel`，只在追问输入时成为 key window；按键 `↩`/`⌘↩` 复制并返回、`C` 复制、`Esc` 停止或关闭、`⌘L` 追问、置顶；复制并返回 = 写剪贴板 + 关闭 + 激活来源（来源失效则只复制并提示）。窗口跟随工具栏、自动关闭、透明度等按 `SelectionSettings`。
- **搜索** `Core/Operations/SearchURL.swift`：按设置的搜索引擎编码查询词，`NSWorkspace.open`。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| M3-1 | 操作引擎、快照、会话、最近结果、搜索、模型选择（C6–C9、C11、C14、C15） | pi-xpc | 完成（待验收） |
| M3-2 | 翻译服务 `translateText` 与翻译路由（FR-E1 划词路径） | pi-xpc | 完成（待验收） |
| M3-3 | 划词监听、取词管线、黑白名单、工具栏窗口、快捷键 ⌃⌥T/⌃⌥S 接入（C1–C5） | pi-platform | 完成（待验收） |
| M3-4 | 结果浮窗窗口与交互、复制并返回、追问、置顶（C12、C13） | pi-surfaces | 完成（待验收） |
| M3-5 | 设置：操作模板编辑与自定义模板、按功能指定模型（C9、C10、C15 的界面） | pi-surfaces | 完成（待验收） |
| M3-6 | 集成与验收 | pi-platform / Claude 验收 | 代码集成完成（待验收） |

**接口先行**：pi-xpc 第一个 commit 只提交 `Core/Operations/` 的公开类型（`ContentSnapshot`、`OperationRequest`、`OperationEvent` 流事件、`OperationRunner` 协议、`RecentResults` 接口）与测试桩，在“进度”节登记 hash；pi-platform 与 pi-surfaces 合并该 commit 后开发，用桩实现自测。

**文件所有权**：pi-xpc：`Core/Operations/`、`Services/TranslationService/`、`Shared/XPCProtocol/`、`App/Features/Operations/`；pi-platform：`App/Features/Selection/`、`Platform/` 补充；pi-surfaces：`App/Features/ResultWindow/`、`App/Shell/ShellSettingsSections.swift` 中模板与模型相关部分、`App/Surfaces/` 必要的视图调整。`AppDelegate` 接线由 Claude 在集成时完成（各方提供 `start()`/`stop()` 入口）。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 操作引擎流式、取消、迟到结果丢弃、超长报错 | 单元测试（`URLProtocol` 桩） | 通过（自动化） | `Core/Operations/.checks/run.sh`：11 项通过；包括真实 AIClient 流式和取消底层 URLSession、无视取消的晚到回调、完整会话输入限额、安全输入切换、错误/空响应不入库、模型选择、追问/新建、最近结果。 |
| 翻译路由：离线成功 / 离线失败回落 AI / 仅 AI | 单元测试 + 手工 | 自动化通过；真实引擎待人工验证 | 操作检查覆盖三条路由及翻译/助手/模板模型优先级。`Services/TranslationService/.checks/run.sh`：9 项通过，覆盖指定目标参数、角色权限、代次/连接隔离、结构保留，以及真实匿名 XPC 往返、取消、断线/超时后的重建。Apple 语言包与真实 AI 未验收。 |
| 搜索 URL 编码 | 单元测试 | 通过 | 操作检查覆盖中文、空格、特殊符号、emoji 编码还原；拒绝空查询和非 HTTPS/错误占位模板。 |
| 划词：TextEdit、Safari、VS Code、企业微信 直接读取或复制回退 | 手工兼容矩阵 | 待人工验证 | |
| Secure Input / 密码框无工具栏、无读取 | 手工 | 待人工验证 | |
| 结果浮窗不抢焦点，复制并返回后可直接 ⌘V | 手工 | 待人工验证 | M3-4 已提供非激活面板、来源应用与 AX 窗口检查；AppDelegate 接线由 M3-6 完成后实测 |
| M3-4 流式状态、取消、迟到结果、追问上下文、保护状态、关闭清空、最近结果重试 | Swift Testing | 通过 | `Tests/SurfaceTests/ResultWindowTests.swift`；合成数据、可控事件流，无网络和用户内容 |
| M3-4 实际视图浅深色、完成态、原文展开与追问 | AppKit 离屏渲染并目视检查 | 通过（静态检查） | `/tmp/roarkt-result-{light,dark}-{done,expanded}.png`；交互、VoiceOver 与设计验收仍待人工 |
| M3-4 分支测试与构建 | 命令 | 测试通过；完整构建阻塞 | 66 项测试及 Rime 部署通过；主 App/翻译服务构建签名通过；输入法子模块未初始化，完整 `scripts/build.sh` 未通过；Gallery 208 张通过 |
| M3-5 模板新增/编辑/删除、默认提示词、模型优先级、重启持久化 | Swift Testing + 真实 runner 的合成传输 | 通过 | `Tests/SurfaceTests/TemplateSettingsTests.swift`：验证设置读写、工具栏同步、无效/过期草稿拒绝、新提示词与模型进入真实 DefaultOperationRunner、图片模板文字入口拒绝 |
| M3-5 模板列表、模型分区与图片模板编辑浅深色 | AppKit 离屏渲染并目视检查 | 静态检查通过；生产接线与交互待验收 | `/tmp/roarkt-m35-{templates,models,image-editor}-{light,dark}.png`；新增 Binding 分区入口，未改非归属 ShellSettingsView |
| M3-5 分支测试、完整构建、Gallery | 命令 | 通过 | `scripts/test.sh`：98 项 Swift Testing（另含既有 XCTest）、Rime 与旧标识检查通过；`scripts/build.sh`：全部产物构建签名通过；`scripts/render-gallery.sh`：208 张 PNG；不代表真实交互验收 |
| 真实 AI 端到端（用户提供端点） | 手工 | 待人工验证 | |
| `scripts/test.sh`、`scripts/build.sh`、`scripts/render-gallery.sh` | 命令 | 测试/渲染通过；完整构建阻塞 | 2026-10-11：test.sh 通过（19 XCTest + 66 Swift Testing，Rime 部署和旧标识扫描通过）；build.sh 主 App/翻译服务 release 编译与签名通过，随后因输入法子模块未初始化退出 1；render-gallery.sh 生成 208 PNG，未作视觉验收。 |


## 进度

- M3-3 第一段：合入 `agent/xpc` 接口 `bf7ee55` / 登记 `3142b7b`；新增 SelectionCapture、SelectionPolicy 与 Platform.SelectionSource。AX 优先、仅 unsupported 时复制回退；安全输入、取消、来源应用/焦点/窗口身份前后校验；在快照边界转为 AppKit 坐标。`scripts/test.sh` 通过；独立 `SELECTION_CHECKS` 检查通过，真实应用兼容性待人工验证。

- pi-xpc 接口先行：`bf7ee55`（独立 commit，仅 `Core/Operations/` 公开类型与 `StubOperationRunner`）；`scripts/test.sh` 通过。pi-platform / pi-surfaces 可 cherry-pick 此提交。
- 接口约定：每个结果窗持有一个 `@MainActor OperationRunner`；`run(_:)` 返回 `AsyncStream<OperationEvent>`，终态后结束；`cancel()` / `stop()` 取消。`ContentSnapshot.Source` 保存来源，矩形为 AppKit 屏幕坐标；追问使用上次 `OperationResult.session`（仅已完成问答），新建使用新 `OperationSession`。`RecentResults` 为内存存储协议。

### M3-4 交付记录（pi-surfaces，2026-10-11）

- 在 `agent/surfaces` 合并 `agent/xpc` 至 `3142b7b`（快进，包含接口 `bf7ee55`）后开发。只新增 `App/Features/ResultWindow/` 文件并更新本规格；未改 AppDelegate、设置窗口、其他 worktree；M3-5 未开始。
- `ResultWindowController` 提供 `start()` / `stop()`、`show(OperationRequest, toolbarRect:)`、`show(OperationResult, template:, toolbarRect:)`、`close()`、`applySettings()`、`beginQuestion()`；每窗注入独占 `OperationRunner`、实时设置读取闭包、关闭后提示 `feedback`、完成回调 `completed`。`stop()` 移除事件监听、清空内容与视图；隐私“清除当前内容”需调用 `close()` 并由集成方清空最近结果。
- 普通展示和置顶不主动成为 key window，只有追问动作请求键盘焦点。键盘处理仅限本窗：Esc 停止／退出追问／关闭，⌘L 追问，非编辑状态 C／⌘C 复制、↩ 复制并返回，⌘↩ 复制并返回。中文 marked text 的按键交给输入法。未获取焦点时不会截获来源应用按键；纯键盘进入追问需集成入口调用 `beginQuestion()`，交互方案由 Claude 验收。
- 请求、追问与重试前以及事件提交时检查安全输入；显示期间每 200ms 检查保护状态并在不可检查时取消、关闭。事件按本窗 revision 隔离，终态后不再消费；追问仅使用 runner 返回的已完成问答；取消的部分结果可复制但不加入上下文；无终态 EOF 显示不完整错误。
- 复制使用 Platform Clipboard，不模拟粘贴。返回前核对原 NSRunningApplication、bundle ID、仍存活且仍聚焦的 AX 窗口；切换其他应用后不拉回。无法确认来源时关闭后通过 `feedback` 提示“仅复制”。重新打开最近结果没有原 AX 窗口引用，保守地仅复制并提示，不猜测窗口。
- 位置以 AppKit 屏幕坐标接收，转换后使用 Platform Placement；透明度、跟随工具栏、自动关闭、自动置顶读取 SelectionSettings。设置变更由集成方调用 `applySettings()`。完成回调由集成方按隐私开关交给 RecentResults；成功结果存储不是本任务文件归属。
- 验证日志：`/tmp/roarkt-surfaces-tests.log`、`/tmp/roarkt-surfaces-build.log`、`/tmp/roarkt-surfaces-release.log`、`/tmp/roarkt-surfaces-gallery.log`。这些日志与合成预览只在本机，不提交内容产物。
- 待人工验证：真实 runner / AI 端到端、来源 TextEdit/Safari/VS Code 的焦点与返回、来源关闭或切换应用、真实中文输入法 marked text、键盘路径、全屏/多显示器/屏幕边缘、置顶/透明度即时设置、Secure Input/密码框/撤销辅助功能权限、VoiceOver。静态渲染不代表上述功能通过。
- Claude 需决定／接线：关闭后非激活提示的宿主；未聚焦结果窗的纯键盘追问入口；初始化输入法依赖后运行完整构建并完成 M3-6。M3-5 等用户另行通知。

M3-4 检查已按新 AGENTS 规则迁入 `Tests/SurfaceTests/ResultWindowTests.swift`，通过 `Package.swift` 的 `RoarkTSurfaceTests` 运行，不再保留源码内独立测试入口。命令：`scripts/test.sh`（全部）或 `swift test --filter RoarkTSurfaceTests`（专项），同时生成合成内容的四张离屏预览。




### M3-1 / M3-2 交付记录

- pi-xpc M3-1：`9d41579` 实现 `DefaultOperationRunner`、目标语言/模型选择、模板提示词、仅完成问答的上下文、超长拒绝、代次取消、Secure Input 防护、内存最近 10 条、搜索 URL；`8b02467` 提供 App 组合入口并补齐真实传输取消/隐私开关/空响应检查。
- pi-xpc M3-2：`1801c8f` 增加主 App 专用 `RoarkTTextTranslationXPCProtocol`（继承候选基础协议）、`translateText` / `cancelText`、独立的文本请求协调器、macOS 26 Apple 后端、App 侧签名校验 XPC 客户端；离线失败由操作引擎在主 App 回落 AI，密钥不进入翻译服务。未更改候选调用方权限。
- Claude 接线入口：App 创建一个 `OperationsEnvironment`，启动/退出调用 `start()` / `stop()`；每个结果窗用 `makeRunner(connectionID: settings.ai.id)` 获取独立 runner，关闭时 `stop()`；监听 `run(_:)` 事件，追问使用成功结果的 `session`。“清除当前内容”调用 `clearCurrentContent()` 并清除窗口自身内容；隐私设置关闭最近结果时，Claude 需清空现存最近结果。搜索调用 `search(_:settings:)` 并处理返回 false。
- 文件边界：未修改 AppDelegate、Package.swift、共享 Tests 或其他 worktree。新行为检查位于归属目录的 `.checks/`；脚本创建临时 Swift 测试包并在结束后清理。它们目前需单独执行，未修改 `scripts/test.sh`。
- 最终验证命令：`Core/Operations/.checks/run.sh`（11/11）、`Services/TranslationService/.checks/run.sh`（9/9）、`scripts/test.sh`（通过）、`scripts/build.sh`（输入法依赖阻塞）、`scripts/render-gallery.sh`（208 PNG，生成不等于视觉验收）、`git diff --check`（通过）。检查夹具均为合成内容，不含真实选区、用户文件或凭据。构建/图库产物只在本 worktree 的忽略目录中。

### M3-3 验收证据（2026-10-11）

- 第一段提交 `11dae58`：取词管线、来源身份、过滤策略与独立检查。第二段：按 Claude 通知合入 main（`7368d26`），测试迁入 Tests/SelectionTests 并新增 RoarkTSelectionTests testTarget，全部由 scripts/test.sh 执行。SelectionController / SelectionToolbarWindow 提供 `start()`、`stop()`、`trigger(_ action: ShortcutAction)`；按设置监听拖选/双击/三击，90ms 等待 AX 更新，generation 隔离迟到结果；外部点击、按键、滚动、切换应用/空间、睡眠、设置变更均撤销；可见期间检查安全输入和来源身份并隐藏。
- 工具栏为不可成为 key/main 的 nonactivating NSPanel，使用 Placement 与统一 Tokens；支持启用、禁用、顺序、自定义文字模板，过多操作使用紧凑按钮与“更多操作”。默认 Finder 黑名单；白名单未知应用保守拒绝；快捷键同样遵守应用过滤，但不受“仅快捷键”触发模式限制。
- 显式动作交付不可变 ContentSnapshot / OperationRequest；复制直接写剪贴板，搜索交给注入回调。快照不落盘，不记录内容。Clipboard 仅增加 synthetic copy 的 eventSourceUserData 标记，避免自身监听取消复制回退；既有 changeCount 保存/恢复逻辑不变。
- 文件边界：实现只改 `App/Features/Selection/`、`Platform/`；按新增授权改 `Tests/SelectionTests/` 和 Package.swift 中自己的 testTarget，并更新本规格。未自行修改 AppDelegate、HotkeyCenter、Core 或其他 worktree；仅将 main 合入本分支，未 push / 未合并到 main。

| M3-3 检查 | 结果 | 证据与限制 |
| --- | --- | --- |
| `scripts/test.sh` | 通过 | 合入最新 main 后 19 个 XCTest + 93 个 Swift Testing 测试（含本任务 2 项）；三个 Rime 方案部署及旧标识扫描通过。已有 Core/Voice/LICENSE.md 未归类资源警告不在本任务范围。 |
| `swift test --filter selectionCaptureProtectsSourcesAndRejectsLateResults` | 通过 | AX 优先且不复制、安全输入禁止读取、空选区不复制、unsupported 复制回退、异步返回时来源变化/保护状态变化拒绝、开始前取消/挂起后取消拒绝迟到结果、坐标转换、Finder 黑名单/白名单、操作禁用排序去重与图片模板过滤。全部使用合成内容。 |
| `swift test --filter selectionToolbarRendersThemesAndStaysNonactivating` | 通过 | 普通/大量操作 × 浅/深四张 PNG，宽度受限；实际 NSPanel 检查 nonactivating、不能 key/main、隐藏有效。`dist/selection-review/` 四图已查看；ImageRenderer 不支持原生 Menu，导出仅替换该菜单标签为省略号，不能证明菜单交互。 |
| `scripts/render-gallery.sh` | 通过 | 原有 Gallery 导出 208 PNG；本任务新增生产工具栏单独按上一行导出，未越界改 Gallery 注册表。 |
| `scripts/build.sh` | **阻塞** | 主 App / 翻译服务 Release 编译、签名和 strict/deep 验证通过；脚本随后因本 worktree 的 InputMethod/librime、plum、Sparkle 子模块为空退出 1。未初始化或修改不归本任务所有的输入法目录。不能声称全产物构建通过。 |
| `git diff --check` | 通过 | 最终修改无空白错误。 |
| 真实 TextEdit / Safari / VS Code / 企业微信取词；全屏/多屏；纯键盘/VoiceOver | 待人工验证 | 未接 AppDelegate，不把测试桩、PNG 或面板属性断言当作实际跨应用验收。 |
| Secure Input / 密码框、权限撤销、来源前台保持、用户新复制不覆盖、实际快捷键冲突/改键 | 待人工验证 | 管线与现有 Clipboard 自动化通过，但真实系统状态与键鼠时序仍需集成后验证。 |

测试位于 `Tests/SelectionTests/`，通过 @testable import RoarkTApp 检查生产类型；App 内已移除全部测试入口与编译开关。默认测试不输出 PNG，需要重建自查图片时运行：

```sh
scripts/test.sh
ROARKT_SELECTION_RENDER_DIR="$PWD/dist/selection-review" swift test --filter selectionToolbarRendersThemesAndStaysNonactivating
scripts/render-gallery.sh
```
### M3-5 交付记录（pi-surfaces，2026-10-11）
- 已合并 main 的真实操作引擎与测试规范，合并时保留 M3-1/M3-2 与 M3-4 双方状态及验收记录。M3-4 独立检查已迁入正式 `RoarkTSurfaceTests`；所有新增测试由 `scripts/test.sh` 运行。
- 新增 `OperationTemplateSettings` 与 `OperationTemplateEditor`：内置提示词编辑与恢复；自定义模板名称、图标、输入类型、提示词、模型和输出形式；新增自动加入工具栏，删除同时移除启用/排序配置。编辑先保留草稿，保存后一次写入 SettingsStore 的 Binding；取消不更改设置；空名称、无效图标、空提示词、过期草稿不会覆盖已保存内容；内置模板保留文字输入且不能删除。
- 新增 `OperationModelSettings` / `OperationModelField`：翻译与助手模型、模板覆盖、默认继承、空白模型归一化；下拉只使用当前连接已配置的模型，也可填写该服务商的其他模型 ID。不请求网络，不读取密钥。实际优先级与真实 runner 一致：模板 → 功能 → 连接默认；离线优先成功不使用自定义提示词，界面已明确。
- 图片模板可以保存，未配置视觉模型时显示引导；已配置仍提示须验证，不冒充已验证。当前 M3 文字快照入口由真实 runner 拒绝图片模板；图片发送与执行仍属 M4。
- 文件边界：仅在 `App/Shell/ShellSettingsSections.swift` 追加模板/模型分区入口，视图放 `App/Surfaces/`；没有修改输入法说明、侧栏焦点、AppDelegate，也没有修改非归属的 `App/Shell/ShellSettingsView.swift`。main 已把旧模板表单迁到 ShellSettingsView，因此新界面尚待 M3-6 替换该宿主的一处调用；不是生产设置页已接入的声明。
- M3-6 接线：在 `ShellSettingsView.content` 的 `.templates` 分支使用 `sections.templatesPane(settings: $settings, showAIConnection: { section = .ai })`，替换旧的 `templates` 表单。这个分区已包含按功能模型设置；独立复用可调用 `sections.modelsPane(settings: $settings, showAIConnection: { section = .ai })`。两者直接绑定同一 SettingsStore，持久化与变更通知沿用现有机制，不需要第二套 store 或生命周期对象。
- 验证：`swift test --filter RoarkTSurfaceTests` 7 项通过，其中 M3-5 五项；真实 DefaultOperationRunner 使用合成 transport，未调用真实网络；临时设置文件验证后清理。AppKit 六张静态预览通过目视检查。`scripts/test.sh` 98 项 Swift Testing 及既有 XCTest、Rime 检查通过；`scripts/build.sh` 全部构建签名通过；`scripts/render-gallery.sh` 208 张通过；`git diff --check` 通过。日志为 `/tmp/roarkt-m35-{tests,release,gallery}.log`。
- 待人工验证：M3-6 生产设置入口、sheet 新增/取消/保存/删除/恢复、中文输入、VoiceOver、系统字号、窗口缩放和滚动；真实模型权限与图片能力；工具栏新模板的真实点击执行。自动测试不能替代这些验收。
- Claude 已决定的 M3-4 事项：关闭后提示使用现有 ComingSoonController 或其通用化版本；未聚焦时不截获来源按键，点击浮窗或 key 状态下 ⌘L 追问；真实 runner、最近结果、设置回调由 M3-6 接线；最近结果只复制不猜测返回窗口的保守行为获认可。输入法子模块现已由 Claude 初始化，dist 符号链接保持原样。

### M3-4 交付记录（pi-surfaces，2026-10-11）

- 在 `agent/surfaces` 合并 `agent/xpc` 至 `3142b7b`（快进，包含接口 `bf7ee55`）后开发。只新增 `App/Features/ResultWindow/` 文件并更新本规格；未改 AppDelegate、设置窗口、其他 worktree；M3-5 未开始。
- `ResultWindowController` 提供 `start()` / `stop()`、`show(OperationRequest, toolbarRect:)`、`show(OperationResult, template:, toolbarRect:)`、`close()`、`applySettings()`、`beginQuestion()`；每窗注入独占 `OperationRunner`、实时设置读取闭包、关闭后提示 `feedback`、完成回调 `completed`。`stop()` 移除事件监听、清空内容与视图；隐私“清除当前内容”需调用 `close()` 并由集成方清空最近结果。
- 普通展示和置顶不主动成为 key window，只有追问动作请求键盘焦点。键盘处理仅限本窗：Esc 停止／退出追问／关闭，⌘L 追问，非编辑状态 C／⌘C 复制、↩ 复制并返回，⌘↩ 复制并返回。中文 marked text 的按键交给输入法。未获取焦点时不会截获来源应用按键；纯键盘进入追问需集成入口调用 `beginQuestion()`，交互方案由 Claude 验收。
- 请求、追问与重试前以及事件提交时检查安全输入；显示期间每 200ms 检查保护状态并在不可检查时取消、关闭。事件按本窗 revision 隔离，终态后不再消费；追问仅使用 runner 返回的已完成问答；取消的部分结果可复制但不加入上下文；无终态 EOF 显示不完整错误。
- 复制使用 Platform Clipboard，不模拟粘贴。返回前核对原 NSRunningApplication、bundle ID、仍存活且仍聚焦的 AX 窗口；切换其他应用后不拉回。无法确认来源时关闭后通过 `feedback` 提示“仅复制”。重新打开最近结果没有原 AX 窗口引用，保守地仅复制并提示，不猜测窗口。
- 位置以 AppKit 屏幕坐标接收，转换后使用 Platform Placement；透明度、跟随工具栏、自动关闭、自动置顶读取 SelectionSettings。设置变更由集成方调用 `applySettings()`。完成回调由集成方按隐私开关交给 RecentResults；成功结果存储不是本任务文件归属。
- 验证日志：`/tmp/roarkt-surfaces-tests.log`、`/tmp/roarkt-surfaces-build.log`、`/tmp/roarkt-surfaces-release.log`、`/tmp/roarkt-surfaces-gallery.log`。这些日志与合成预览只在本机，不提交内容产物。
- 待人工验证：真实 runner / AI 端到端、来源 TextEdit/Safari/VS Code 的焦点与返回、来源关闭或切换应用、真实中文输入法 marked text、键盘路径、全屏/多显示器/屏幕边缘、置顶/透明度即时设置、Secure Input/密码框/撤销辅助功能权限、VoiceOver。静态渲染不代表上述功能通过。
- Claude 需决定／接线：关闭后非激活提示的宿主；未聚焦结果窗的纯键盘追问入口；初始化输入法依赖后运行完整构建并完成 M3-6。M3-5 等用户另行通知。

M3-4 检查已按新 AGENTS 规则迁入 `Tests/SurfaceTests/ResultWindowTests.swift`，通过 `Package.swift` 的 `RoarkTSurfaceTests` 运行，不再保留源码内独立测试入口。命令：`scripts/test.sh`（全部）或 `swift test --filter RoarkTSurfaceTests`（专项），同时生成合成内容的四张离屏预览。


### M3-5 交付记录（pi-surfaces，2026-10-11）

- 已合并 main 的真实操作引擎与测试规范，合并时保留 M3-1/M3-2 与 M3-4 双方状态及验收记录。M3-4 独立检查已迁入正式 `RoarkTSurfaceTests`；所有新增测试由 `scripts/test.sh` 运行。
- 新增 `OperationTemplateSettings` 与 `OperationTemplateEditor`：内置提示词编辑与恢复；自定义模板名称、图标、输入类型、提示词、模型和输出形式；新增自动加入工具栏，删除同时移除启用/排序配置。编辑先保留草稿，保存后一次写入 SettingsStore 的 Binding；取消不更改设置；空名称、无效图标、空提示词、过期草稿不会覆盖已保存内容；内置模板保留文字输入且不能删除。
- 新增 `OperationModelSettings` / `OperationModelField`：翻译与助手模型、模板覆盖、默认继承、空白模型归一化；下拉只使用当前连接已配置的模型，也可填写该服务商的其他模型 ID。不请求网络，不读取密钥。实际优先级与真实 runner 一致：模板 → 功能 → 连接默认；离线优先成功不使用自定义提示词，界面已明确。
- 图片模板可以保存，未配置视觉模型时显示引导；已配置仍提示须验证，不冒充已验证。当前 M3 文字快照入口由真实 runner 拒绝图片模板；图片发送与执行仍属 M4。
- 文件边界：仅在 `App/Shell/ShellSettingsSections.swift` 追加模板/模型分区入口，视图放 `App/Surfaces/`；没有修改输入法说明、侧栏焦点、AppDelegate，也没有修改非归属的 `App/Shell/ShellSettingsView.swift`。main 已把旧模板表单迁到 ShellSettingsView，因此新界面尚待 M3-6 替换该宿主的一处调用；不是生产设置页已接入的声明。
- M3-6 接线：在 `ShellSettingsView.content` 的 `.templates` 分支使用 `sections.templatesPane(settings: $settings, showAIConnection: { section = .ai })`，替换旧的 `templates` 表单。这个分区已包含按功能模型设置；独立复用可调用 `sections.modelsPane(settings: $settings, showAIConnection: { section = .ai })`。两者直接绑定同一 SettingsStore，持久化与变更通知沿用现有机制，不需要第二套 store 或生命周期对象。
- 验证：`swift test --filter RoarkTSurfaceTests` 7 项通过，其中 M3-5 五项；真实 DefaultOperationRunner 使用合成 transport，未调用真实网络；临时设置文件验证后清理。AppKit 六张静态预览通过目视检查。`scripts/test.sh` 98 项 Swift Testing 及既有 XCTest、Rime 检查通过；`scripts/build.sh` 全部构建签名通过；`scripts/render-gallery.sh` 208 张通过；`git diff --check` 通过。日志为 `/tmp/roarkt-m35-{tests,release,gallery}.log`。
- 待人工验证：M3-6 生产设置入口、sheet 新增/取消/保存/删除/恢复、中文输入、VoiceOver、系统字号、窗口缩放和滚动；真实模型权限与图片能力；工具栏新模板的真实点击执行。自动测试不能替代这些验收。
- Claude 已决定的 M3-4 事项：关闭后提示使用现有 ComingSoonController 或其通用化版本；未聚焦时不截获来源按键，点击浮窗或 key 状态下 ⌘L 追问；真实 runner、最近结果、设置回调由 M3-6 接线；最近结果只复制不猜测返回窗口的保守行为获认可。输入法子模块现已由 Claude 初始化，dist 符号链接保持原样。

## 问题

- 待 Claude 决定：各真实模型的输入预算。`OperationRequest.maximumInputBytes` 默认 16,384 UTF-8 字节，对完整提示词及会话一起校验、绝不截断；可由调用方按已验证模型的输入预算覆盖。当前设置没有模型上下文容量元数据，默认值不是对所有模型上限的声明。
- 待 Claude 确认产品语义：翻译模板自定义提示词用于 AI 路径；`offlineFirst` 成功时仍按规格使用 Apple Translation（该 API 不支持提示词），不会应用自定义提示词。若希望编辑翻译提示词后必走 AI，需要在设置/路由规格中明确。
- 已由 Claude 在 `44e7aad` 将 M3-1/M3-2 测试迁入 Tests 并接入 Package；原 `.checks/run.sh` 记录为历史证据，当前使用 scripts/test.sh。初始化输入法构建子模块后仍需重新运行完整 build.sh。
- 待人工验证：真实端点/模型及错误响应；已安装 Apple 语言包的中英与指定目标翻译；macOS < 26 回落；签名 App 到 LaunchAgent 的真实调用；密码框与终端 Secure Keyboard Entry 的无请求/无缓存；结果浮窗追问、复制并返回、最近结果菜单和设计验收（由 M3-3～M3-6 集成）。

- **M3-3 集成交给 Claude**：构造并持有 SelectionController，`settings` 闭包读取 SettingsStore.settings（Observation 自动跟踪）；`perform` 将 OperationRequest 交给 M3-4 结果窗/runner，`search` 调用 `operationsEnvironment.search(snapshot.text, settings: settings.selection)` 并处理 false/错误，`notice` 展示无内容的错误提示；AppDelegate 生命周期调用 start/stop。窗口 followToolbar / automaticallyClose / automaticallyPin / windowOpacity 已在 request.settings 中，具体效果由 M3-4 结果窗处理。
- **快捷键接线必须由 Claude 完成**：现有 `App/Shell/Hotkeys/HotkeyCenter.swift` 已注册翻译/总结，但 handler 仍调用 comingSoon；它不归 M3-3 所有。可在 AppDelegate 注入的 comingSoon 回调中将这两项分发至 `selectionController.trigger(.translateSelection / .summarizeSelection)`，保留现有冲突提示、录制暂停与即时改键。M3-3 不重复注册 Carbon 快捷键。真实快捷键端到端尚未完成。
- **来源标识约定**：Platform.SelectionSource 的 windowIdentifier 是 AX 窗口 CFHash 得到的运行期不透明标识，不是 CGWindowID；在取词/工具栏期间另持有 AX 窗口与焦点元素并用 CFEqual 校验。M3-4 若需要实际定位来源窗口，应由 Claude 协调接口，不能把此字符串强转 CGWindowID。
- 复制回退沿用 SPEC-010 已接受的 changeCount 竞争限制：NSPasteboard 不提供写入者身份/原子 compare-and-swap；外部首次写入、超时后迟到复制无法完全识别。未增加后台剪贴板监听。
- M3-4：关闭后非激活提示宿主、未聚焦窗口的纯键盘入口，由 Claude 在 M3-6 决定并接线；完整构建仍需初始化输入法子模块。


### M3-6 代码集成证据（2026-10-11）

- 代码集成完成（待验收）。AppDelegate 持有 SelectionController / OperationsEnvironment，生命周期已接入；翻译、总结快捷键转发，截图保持“即将推出”。工具栏操作通过 SelectionOperationsController 创建独占 runner，流式结果、追问、最近结果列表及重开已接入；搜索使用 OperationsEnvironment，复制使用 Clipboard，错误走 ComingSoonController 通用非激活提示。
- 来源窗口在捕获时保留进程内 AXUIElement，不进入快照或最近结果；复制返回先激活来源应用再 AXRaise，窗口失效退化为应用，应用失效仅复制提示；切换过其他应用不拉回；最近结果重开不猜测窗口。
- 设置即时读取：触发方式、黑白名单、窗口配置、模型及模板；生产模板页已使用 M3-5 分区。未配置 AI 时禁用工具栏 AI 操作并提示设置，翻译强制离线优先，追问拒绝并提示。最近结果改由完成回调按当前隐私设置写入，避免进行中请求用旧设置回写；菜单及隐私页均有清除当前内容入口。
- 自动化：scripts/test.sh 通过（19 XCTest + 102 Swift Testing，Rime 与旧标识检查通过）。新增桩 runner 经生产工具栏分发→真实结果窗→最近结果测试，覆盖流式、追问、模型变更、隐私关闭、重开、清除、AI 未配置与保护状态；快捷键覆盖两项转发、录制暂停、改键、迟到回调、保护状态及截图占位。已有持久化/结果窗测试的固定时序等待改为有截止时间的条件等待，解决并行渲染占用 MainActor 导致的误报。
- 完整 build、gallery 与实际启动将在追加 M5 集成并合并 main 后统一重跑，当前未据此声明通过。真实应用取词兼容矩阵、权限撤销、Secure Input、离线语言包和真实 AI、AXRaise 返回、中文追问、键盘与 VoiceOver、全屏/多屏与设计验收仍待人工验证。
