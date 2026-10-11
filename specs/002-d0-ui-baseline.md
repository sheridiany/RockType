# SPEC-002 UI 设计基线（D0）

- 阶段：D0
- 覆盖需求：NFR-7；为全部用户可见 FR 提供界面基线
- 状态：Ready

## 范围

用 SwiftUI（必要时 AppKit 承载窗口）实现 RoarkT 全部关键界面的**可运行高保真版本**，使用模拟数据，覆盖所有状态与浅色/深色主题。它同时是设计稿、交互原型和后续阶段直接复用的组件。

不做：任何真实系统能力（取词、截图、权限、网络、XPC）、输入法内真实候选窗（Squirrel 绘制在 M1 按本基线调整主题）。

## 设计来源

以 `../RoarkTools/specs/006-ui-design-baseline.md` 为准（只读），沿用其“设计方向”“设计变量”“组件”“浮窗位置规则”。参考实现：`../RoarkTools/frontend/src/`（Svelte，`lib/tokens.css`、`surfaces/*.svelte`、`mock/*`）与截图 `../RoarkTools/*.png`。RoType 候选窗与设置参考：`../RoType/Squirrel/sources/SquirrelPanel.swift`、`RoTypeTranslationPanel.swift`、`../RoType/Sources/RoTypeApp/`。

与 RoarkTools 基线的差异：

- **取消快捷面板**。
- 截图快捷键 `⌃1`；语音 `Fn`（ADR-0002）。
- 菜单栏面板的北京时间大字改为可选（FR-F1，默认关闭）；关闭时顶部显示最近结果与 AI 状态。
- 新增界面：候选窗 + 译文栏、输入模式提示、语音 HUD、截图编辑器（冻结屏幕 + 框选 + 标注工具栏）、首次引导。
- 设置分区按 PRD FR-E4：通用、输入法、翻译、语音、划词、截图、AI 连接、操作模板、快捷键、权限、隐私、关于。

## 技术计划

- `App/DesignSystem/`：`Tokens.swift`（颜色按浅/深定义，间距、圆角、字号、动效常量）与组件：Button（primary/secondary/ghost/danger）、Kbd、Chip、ActionRow、StatusLine、TextField/TextArea 样式、Notice、SettingsRow、Toggle/Segmented/Select 样式。界面只引用 Tokens，不写死数值。
- `App/Surfaces/`：每个界面一个 SwiftUI View，输入是纯数据模型（`App/Mock/` 提供各状态的样例）。界面清单：
  1. 菜单栏面板（宽 320）
  2. 划词工具栏
  3. 结果浮窗（宽 420，高 160–480）
  4. 截图编辑器：遮罩 + 选区尺寸 + 标注工具栏（矩形、椭圆、箭头、画笔、马赛克、文字、序号、识别文字、翻译、撤销、保存、取消、完成）
  5. 图片预览 / OCR 结果
  6. 设置窗口（760 × 540，全部分区）
  7. 首次引导（输入源、语言包、权限、语音模型、AI，每步可跳过）
  8. 候选窗 + 译文栏（5 候选；译文栏状态：翻译中 / 译文 / 静态词条 / 不可用 / AI 结果）
  9. 输入模式提示（中 / 英 / 方案名）
  10. 语音 HUD（录音中带波形 / 识别中 / 完成 / 失败 / 已取消）
- `App/Gallery/`：设计面板窗口，左侧列出“界面 × 状态”，右侧显示，顶部切换浅色/深色、减少动态效果。启动参数 `RoarkT --gallery` 打开；菜单栏菜单中加“设计面板…”（仅 Debug 构建或按住 ⌥ 显示）。
- 渲染证据：`RoarkT --render-gallery <目录>` 用 `ImageRenderer` 把每个“界面 × 状态 × 主题”渲染为 PNG（文件名 `<界面>-<状态>-<light|dark>.png`），无需屏幕录制权限。`scripts/render-gallery.sh` 调用它输出到 `dist/gallery/`。
- 文件所有权：只改 `App/`、`scripts/render-gallery.sh`、本规格。不改 `Package.swift`（App target 已包含 `App/` 下全部源码）、`Core/`、`Platform/`。

## 状态覆盖

沿用 RoarkTools 基线“状态覆盖”表（删除快捷面板行），并加：

| 界面 | 状态 |
| --- | --- |
| 候选窗 + 译文栏 | 无译文；翻译中；中→英译文；英→中释义；静态词条；不可用；AI 改写结果；长译文截断 |
| 输入模式提示 | 中；英；切换方案 |
| 语音 HUD | 录音中；识别中；完成；失败；取消；模型未下载 |
| 截图编辑器 | 框选中（显示尺寸）；已选区 + 工具栏；标注中；OCR 中；OCR 完成 |
| 首次引导 | 每一步的 未完成 / 进行中 / 完成 / 跳过 / 失败 |
| 设置 | 各分区默认；AI 未配置；连接测试混合结果；快捷键冲突；权限未授权；语音模型下载中 |

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| U1 | DesignSystem：Tokens + 组件 | pi | 完成（Claude 已验收 2026-10-11） |
| U2 | Gallery 窗口与 `--render-gallery` | pi | 完成（Claude 已验收 2026-10-11） |
| U3 | 界面 1–5（菜单栏、工具栏、结果浮窗、截图编辑器、图片预览） | pi | 完成（待验收） |
| U4 | 界面 6–10（设置、引导、候选窗、模式提示、语音 HUD） | pi | 未开始 |
| U5 | 设计走查 | Claude + 用户 | 未开始 |

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 全部界面 × 状态 × 两种主题都有 PNG | `scripts/render-gallery.sh` | U3 通过；全部覆盖待 U4 | 界面 1–5 共 39 状态 × 2 主题 = 78 张，见 U3 分段证据与 `dist/gallery/` |
| 只引用 Tokens（无写死颜色/尺寸） | 代码检查 | U1/U2/U3 通过 | U3 的颜色、字号、间距、圆角、尺寸全部引用现有 Tokens；专用尺寸缺项见“问题” |
| 与 RoarkTools 基线视觉一致 | 对照截图走查 | 未运行 | |
| Gallery 可键盘操作 | 手工 | 待人工验证 | |
| `swift build`、`scripts/test.sh` 通过 | 命令 | U3 构建通过；全量测试阻塞 | Debug / Release 编译、2 个 Swift 测试通过；本 worktree 的 Rime 运行时缺失，统一测试退出 1，详见 U3 证据 |

## U1 / U2 增量验收证据

### U1：DesignSystem

- 完成（待验收）：`App/DesignSystem/Tokens.swift` 和 `Components.swift` 提供浅深主题、字体、间距、圆角、尺寸、阴影与动效常量，以及 Button 四变体、Kbd、Chip、ActionRow、StatusLine、输入框/文本区、Notice、SettingsRow、Toggle、Segmented、Select。
- 数值来源：参考规格完整阅读；其元信息指定 UI-0.1 表格由 `frontend/src/lib/tokens.css` UI-0.2 覆盖，故采用 UI-0.2 数值（例如窗口圆角 12、强调色浅色 #4f46e5 / 深色 #a5b4fc）。原生选择控件保留系统焦点和禁用行为；Kbd 按 UI-0.2 使用无框淡色文字。SF Symbols 使用系统图标。
- 参考文件实际位于 `/Users/xuean/Repos/00-Roark/RoarkTools/`（当前 worktree 的 `../RoarkTools` 不存在）；只读。
- 通过：`swift build`；`scripts/test.sh`（2 个 Swift Testing 测试及旧标识扫描）。
- 待人工验证：组件各交互态、VoiceOver、真实键盘焦点、与参考设计逐项视觉比对。macOS 14 为编译部署目标，尚未在 macOS 14 真机运行。

### U2：Gallery 与渲染入口

- 完成（待验收）：`--gallery` 打开可复用窗口，左侧按界面/状态选择，顶部切换浅深主题及减少动态效果；Debug 菜单栏提供“设计面板…”。Release 保留命令行入口，不显示菜单入口。
- `GalleryCatalog` 是窗口与 `ImageRenderer` 的共同注册表。后续 U3/U4 添加条目即可参与批量导出，条目的 View 应保持纯 SwiftUI 可渲染内容。图片文件名为 `<surface>-<state>-<light|dark>.png`。
- `--render-gallery <目录>` 在菜单栏和窗口初始化前执行，成功退出 0，参数缺失/输出错误退出 1；不会调用屏幕捕获。`scripts/render-gallery.sh [目录]` 默认输出 `dist/gallery/`，支持含空格路径。
- 示例：`App/Mock/ResultExample.swift` 的合成数据 + `App/Surfaces/ResultExampleView.swift`，仅“流式中 / 完成”静态预览。保留原文展开以检验中文、英文及次要文字；不实现 U3 的浮窗交互。结果宽 420 按本规格，其他共享数值按参考 UI-0.2；采用参考 UI-0.3 的紧凑文本操作提示，仍以本仓库后续 U3 验收为准。
- 减少动态效果使用自定义环境值与系统设置取并集；PNG 固定开启。此静态示例无闪烁动画，动态流式行为不在本增量中。

验证环境：2026-10-11，Apple Silicon，macOS 27.0.1（26A434），Swift 6 模式，部署目标 macOS 14。

| 检查 | 结果 | 证据 / 实际观察 |
| --- | --- | --- |
| `swift build`、`swift build -c release` | 通过 | App 和翻译服务编译成功，无 macOS 26 专属 API |
| `scripts/test.sh` | 通过 | 2 个 Swift Testing 测试及旧标识扫描；未新增镜像实现的单元测试 |
| `scripts/render-gallery.sh` | 通过 | `dist/gallery/result-{streaming,done}-{light,dark}.png`，共 4 张，均为 840×538 像素（420×269 pt，2x） |
| 图片内容检查 | 通过（示例） | 4 张逐张查看，正文/原文/状态可读，无截断；两种状态、主题可区分。PNG 为忽略的构建产物，由脚本重建 |
| 直接运行 `RoarkTApp --render-gallery <含空格的临时目录>` | 通过 | PNG 签名、数量、尺寸核对通过；4 张与默认目录的图片逐字节一致 |
| 缺失目录参数 / 输出至 `/dev/null/gallery` | 通过 | 均退出 1，并输出错误；未卡入 App 事件循环 |
| `RoarkTApp --gallery` 启动冒烟检查 | 通过 | 通过 CoreGraphics 仅查询该测试进程的窗口信息，确认可见窗口，宽 760；测试后结束该进程。未使用屏幕录制 |
| Tokens 代码检查、`git diff --check` | 通过 | 示例及 Gallery 无非零颜色/尺寸字面量；空白检查通过 |
| 纯键盘、VoiceOver、菜单点击、主题/减少动态效果交互 | 待人工验证 | 原生控件已接入，尚未执行完整交互走查 |
| macOS 14 真机运行、与参考截图完整视觉一致性 | 待人工验证 | 当前机器为 macOS 27；编译成功不代表真机与设计验收通过 |

U2 交付时的未完成范围：U3、U4、U5 均未开始；当时尚无全部界面状态 PNG。Claude 需确认本增量视觉及原生 SF Symbols/控件的表现，后续完整结果浮窗在 U3 实现。没有修改其他 worktree、Package.swift、Core 或 Platform；未 push、未合并。


## U3 分段证据

- A 段（2026-10-11）：`App/Mock/` 中建立界面 1–5 的纯 Swift 数据模型，39 个确定性合成状态样例（菜单栏 6、划词工具栏 5、结果浮窗 15、截图编辑器 5、图片预览 8）。不引用 SwiftUI、DesignSystem 或 Gallery。
- `swift build` 通过；`scripts/test.sh` 中 2 个 Swift 测试通过，但 Rime 部署被阻塞：独立 worktree 下现有脚本无法定位相邻运行时，报 `Missing Rime deployment dependency: /bin/rime_deployer`。A 段交付时尚未生成 PNG，B 段等待 U1/U2；后续结果见下。

### B 段（2026-10-11）

- 已合并 `agent/ui`（U1 `fbbabfa`、U2 `1f5b27a`，分支检查时已含验收提交 `041b098`）；合并只解决本规格的证据冲突，保留双方记录。未修改 `App/DesignSystem/`、Gallery 窗口或渲染器。
- `App/Surfaces/` 新增五个界面 View，输入为 A 段数据。`App/Gallery/PrimarySurfaceEntries.swift` 提供 39 个条目，`GalleryCatalog` 改为注册这些条目，替代 U2 的两个示例注册。U2 示例文件保留。
- 菜单栏默认不显示时钟，可展开/清除最近结果；工具栏覆盖禁用与已复制反馈；结果浮窗支持模拟停止、追问、原文展开、置顶状态和复制反馈；截图编辑器包含全部 13 个工具操作，标注使用合成示例；图片预览支持 OCR 编辑与后续动作反馈。所有动作只更新内存演示状态，不读取屏幕/选区/剪贴板，不请求权限、网络或 XPC，不写入用户文件。
- 原型不包含生产截图绘制/裁剪引擎，不验证真实返回来源、窗口置顶或剪贴板写入。安全输入样例只显示 Gallery 说明，不显示可操作的划词工具栏。

| 界面 | 样例覆盖 | 状态数 | PNG 数 |
| --- | --- | --- | --- |
| 菜单栏 | 正常（时钟关闭）、AI 未配置、空最近结果、有最近结果、时钟开启、本地时区、AI 异常（时钟与本地时区同一样例） | 6 | 12 |
| 划词工具栏 | 普通、紧凑、已复制、AI 未配置、安全输入隐藏 | 5 | 10 |
| 结果浮窗 | 连接、流式、完成、追问、断流、截断、取消、网络/认证/输入过长错误、长内容、代码、来源关闭、复制回退、总结 | 15 | 30 |
| 截图编辑器 | 框选中、已选区、标注中、OCR 中、OCR 完成 | 5 | 10 |
| 图片预览 | 预览、OCR 中、OCR 可编辑结果、无文字、无视觉模型、无屏幕录制权限、剪贴板图片、拖入图片 | 8 | 16 |

| U3 检查 | 结果 | 证据与限制 |
| --- | --- | --- |
| `swiftc -typecheck -swift-version 6`（A 段六个数据文件） | 通过 | 不依赖 SwiftUI、Tokens 或 Gallery |
| `swift build`、`swift build -c release` | 通过 | Swift 6；macOS 14 部署目标；最终版本无编译警告 |
| `scripts/test.sh` | 阻塞 | 2 个 Swift 测试通过，随后 Rime 缺运行时退出 1；不是全量通过 |
| U3 旧标识、非零颜色/尺寸字面量扫描；`git diff --check` | 通过 | 未发现旧标识、硬编码颜色/非零布局尺寸或空白错误 |
| `scripts/render-gallery.sh` | 通过 | `dist/gallery/` 共 78 张；PNG 导出无需屏幕录制权限 |
| PNG 清单、文件签名与尺寸检查 | 通过 | 五类状态数分别 6/5/15/5/8，各两种主题；菜单宽 640 px（320 pt @2x），结果宽 840 px、高 536/608/960 px（268/304/480 pt @2x） |
| PNG 自查 | 通过（实现自查，非 U5 设计验收） | `dist/gallery-review/` 十张分类联系表覆盖全部 PNG；另查看长内容、错误、OCR 等原图。修正首轮滚动区正文空白、原生文本编辑器占位图，以及长内容挤出标题栏的问题 |
| `RoarkTApp --gallery` 启动冒烟 | 通过 | 临时 Swift 检查只查询本次启动进程的可见窗口，确认窗口存在后终止该进程；无屏幕捕获 |
| 真实键盘、VoiceOver、macOS 14 真机、与参考设计逐项一致 | 待人工验证 | 由 Claude / 用户在 U5 走查，不能以 PNG 或构建成功代替 |


## 问题

- U3：独立 worktree 的 `scripts/test-rime.sh` 只搜索相邻一层目录，当前布局下找不到 Rime 运行时。该脚本不属于 U3 文件所有权；需维护者提供运行时或调整测试入口后复验。
- U3 组件需求：增加可被 `ImageRenderer` 渲染的滚动正文/多行编辑快照。现有 `ScrollView` 在本机离屏渲染正文空白，`DesignTextArea` 内的原生 `TextEditor` 显示不支持占位图；U3 注册点在 `--render-gallery` 时传入只读导出标记，用同一数据、同一 Tokens 绘制正文/编辑文本快照。交互 Gallery 保留原滚动区和 DesignTextArea。PNG 不证明编辑器光标、选择与滚动行为。
- U3 Tokens 需求：图片预览宽 480、缩略图最大高 280、截图画布、选区与遮罩专用变量。目前分别借用 `resultMaxHeight`、`control × 10`、`settingsWidth/settingsHeight`、间距网格及 `windowShadow`；未另建 Tokens。请 Claude 确认这些近似布局后由 U1 所有者补齐语义变量。
- U3 交互边界：设置/退出/复制/保存/返回来源是演示反馈；截图标注点击添加预设标注，并非生产绘制引擎。原型流式状态为冻结时刻，不运行异步网络，也无闪烁动画；减少动态效果下仍保持静态。真实系统能力按后续规格接入。
