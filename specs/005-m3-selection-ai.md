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
| M3-1 | 操作引擎、快照、会话、最近结果、搜索、模型选择（C6–C9、C11、C14、C15） | pi-xpc | 未开始 |
| M3-2 | 翻译服务 `translateText` 与翻译路由（FR-E1 划词路径） | pi-xpc | 未开始 |
| M3-3 | 划词监听、取词管线、黑白名单、工具栏窗口、快捷键 ⌃⌥T/⌃⌥S 接入（C1–C5） | pi-platform | 未开始 |
| M3-4 | 结果浮窗窗口与交互、复制并返回、追问、置顶（C12、C13） | pi-surfaces | 完成（待验收） |
| M3-5 | 设置：操作模板编辑与自定义模板、按功能指定模型（C9、C10、C15 的界面） | pi-surfaces | 未开始 |
| M3-6 | 集成与验收 | Claude | 未开始 |

**接口先行**：pi-xpc 第一个 commit 只提交 `Core/Operations/` 的公开类型（`ContentSnapshot`、`OperationRequest`、`OperationEvent` 流事件、`OperationRunner` 协议、`RecentResults` 接口）与测试桩，在“进度”节登记 hash；pi-platform 与 pi-surfaces 合并该 commit 后开发，用桩实现自测。

**文件所有权**：pi-xpc：`Core/Operations/`、`Services/TranslationService/`、`Shared/XPCProtocol/`、`App/Features/Operations/`；pi-platform：`App/Features/Selection/`、`Platform/` 补充；pi-surfaces：`App/Features/ResultWindow/`、`App/Shell/ShellSettingsSections.swift` 中模板与模型相关部分、`App/Surfaces/` 必要的视图调整。`AppDelegate` 接线由 Claude 在集成时完成（各方提供 `start()`/`stop()` 入口）。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 操作引擎流式、取消、迟到结果丢弃、超长报错 | 单元测试（`URLProtocol` 桩） | 未运行 | |
| 翻译路由：离线成功 / 离线失败回落 AI / 仅 AI | 单元测试 + 手工 | 未运行 | |
| 搜索 URL 编码 | 单元测试 | 未运行 | |
| 划词：TextEdit、Safari、VS Code、企业微信 直接读取或复制回退 | 手工兼容矩阵 | 待人工验证 | |
| Secure Input / 密码框无工具栏、无读取 | 手工 | 待人工验证 | |
| 结果浮窗不抢焦点，复制并返回后可直接 ⌘V | 手工 | 待人工验证 | M3-4 已提供非激活面板、来源应用与 AX 窗口检查；AppDelegate 接线由 M3-6 完成后实测 |
| M3-4 流式状态、取消、迟到结果、追问上下文、保护状态、关闭清空、最近结果重试 | 独立 Swift 回归检查 | 通过 | `ResultWindowChecks.swift`；合成数据、可控事件流，无网络和用户内容 |
| M3-4 实际视图浅深色、完成态、原文展开与追问 | AppKit 离屏渲染并目视检查 | 通过（静态检查） | `/tmp/roarkt-result-{light,dark}-{done,expanded}.png`；交互、VoiceOver 与设计验收仍待人工 |
| M3-4 分支测试与构建 | 命令 | 测试通过；完整构建阻塞 | 66 项测试及 Rime 部署通过；主 App/翻译服务构建签名通过；输入法子模块未初始化，完整 `scripts/build.sh` 未通过；Gallery 208 张通过 |
| 真实 AI 端到端（用户提供端点） | 手工 | 待人工验证 | |
| `scripts/test.sh`、`scripts/build.sh`、`scripts/render-gallery.sh` | 命令 | M3-4 分支部分通过；集成待运行 | M3-4 结果见上方专项行；不代表 M3 整体验收 |

## 进度

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

M3-4 独立检查命令（bash；限定在本 worktree，生产编译不启用检查入口）：

```bash
cd /Users/xuean/Repos/00-Roark/RoarkT-wt/surfaces
set -e
swift build --product RoarkTApp
bin_dir=$(swift build --show-bin-path)
app_objects=()
for object in "$bin_dir"/RoarkTApp.build/*.swift.o; do
  case "$object" in */main.swift.o) ;; *) app_objects+=("$object");; esac
done
swiftc -swift-version 6 -D RESULT_WINDOW_CHECKS -D RESULT_WINDOW_UI_CHECKS \
  -parse-as-library -I "$bin_dir/Modules" \
  -Xcc -fmodule-map-file="$bin_dir/RoarkTXPCProtocol.build/module.modulemap" \
  -Xcc -IShared/XPCProtocol/include \
  App/Features/ResultWindow/ResultWindowChecks.swift "${app_objects[@]}" \
  "$bin_dir"/RoarkTCore.build/*.swift.o "$bin_dir"/RoarkTPlatform.build/*.swift.o \
  "$bin_dir"/RoarkTXPCProtocol.build/*.o -o /tmp/roarkt-result-window-ui-checks
/tmp/roarkt-result-window-ui-checks
```

## 问题

- M3-4：关闭后非激活提示宿主、未聚焦窗口的纯键盘入口，由 Claude 在 M3-6 决定并接线；完整构建仍需初始化输入法子模块。
