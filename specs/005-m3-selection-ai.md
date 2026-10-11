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
| M3-4 | 结果浮窗窗口与交互、复制并返回、追问、置顶（C12、C13） | pi-surfaces | 未开始 |
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
| 结果浮窗不抢焦点，复制并返回后可直接 ⌘V | 手工 | 待人工验证 | |
| 真实 AI 端到端（用户提供端点） | 手工 | 待人工验证 | |
| `scripts/test.sh`、`scripts/build.sh`、`scripts/render-gallery.sh` | 命令 | 未运行 | |

## 进度

- pi-xpc 接口先行：`bf7ee55`（独立 commit，仅 `Core/Operations/` 公开类型与 `StubOperationRunner`）；`scripts/test.sh` 通过。pi-platform / pi-surfaces 可 cherry-pick 此提交。
- 接口约定：每个结果窗持有一个 `@MainActor OperationRunner`；`run(_:)` 返回 `AsyncStream<OperationEvent>`，终态后结束；`cancel()` / `stop()` 取消。`ContentSnapshot.Source` 保存来源，矩形为 AppKit 屏幕坐标；追问使用上次 `OperationResult.session`（仅已完成问答），新建使用新 `OperationSession`。`RecentResults` 为内存存储协议。

## 问题
