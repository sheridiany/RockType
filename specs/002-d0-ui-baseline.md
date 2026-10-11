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
| U3 | 界面 1–5（菜单栏、工具栏、结果浮窗、截图编辑器、图片预览） | pi | 完成（Claude 已验收 2026-10-11；截图编辑器、本地措辞、安全输入已返工） |
| U4 | 界面 6–10（设置、引导、候选窗、模式提示、语音 HUD） | pi | 完成（Claude 已验收 2026-10-11） |
| U5 | 设计走查 | Claude + 用户 | 未开始 |

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 全部界面 × 状态 × 两种主题都有 PNG | `scripts/render-gallery.sh` | U3 通过；全部覆盖待 U4 | 界面 1–5 共 39 状态 × 2 主题 = 78 张，见 U3 分段证据与 `dist/gallery/` |
| 只引用 Tokens（无写死颜色/尺寸） | 代码检查 | U1/U2/U3 通过 | U3 的颜色、字号、间距、圆角、尺寸全部引用现有 Tokens；专用尺寸缺项见“问题” |
| 与 RoarkTools 基线视觉一致 | 对照截图走查 | 部分通过（Claude） | 菜单栏、结果浮窗、划词工具栏、图片预览已通过；截图编辑器按复验意见重做，待 Claude 复验 |
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

未完成范围：U3、U4、U5 均未开始；尚无全部界面状态 PNG。Claude 需确认本增量视觉及原生 SF Symbols/控件的表现，后续完整结果浮窗在 U3 实现。没有修改其他 worktree、Package.swift、Core 或 Platform；未 push、未合并。

## U4 增量记录（2026-10-11）

### 候选窗、模式提示、语音 HUD

- 已实现候选 8 状态、模式 3 状态、HUD 6 状态及失败/缺模型的展开详情（共 19 条，38 张浅深主题 PNG）。实现位于独立的 `CandidateView`、`InputModeView`、`VoiceHUDView` 与对应 fixtures；Gallery 在 U4 独立区块追加，不改界面 1–5 或现有 DesignSystem 接口。
- 参考候选窗、译文栏、模式提示和 HUD 的交互语义，独立编写 SwiftUI 展示层；未复制或链接 GPL 输入法代码。颜色/排版沿用 Tokens，新增尺寸均由已有网格派生。录音波形为明确的合成样例，识别中不显示波形；无麦克风与真实输入调用。
- 通过：编译、渲染；38 张 PNG 已逐张在联系表检查。发现禁用按钮使翻译中/不可用状态整栏变淡，已改为保持可读的非交互状态行。
- 仓库直接 `scripts/test.sh`：阻塞于 Rime 依赖相对路径（`/bin/rime_deployer` 缺失），Swift 测试通过。使用临时源码副本、原样测试脚本及相邻只读参考运行库补跑：全部通过（2 个 Swift 测试、3 个 Rime 方案部署、旧标识扫描）；临时目录自动删除。未修改范围外的测试脚本。
- 本记录为分步提交证据；U4 总体完成状态在设置与引导完成、全量截图走查后更新。

### 首次引导

- 输入源、语言包、权限、语音模型、AI 连接，每步均提供未完成/进行中/完成/跳过/失败，共 25 条、50 张 PNG。50 张已逐张检查：步骤标题、阶段标记、原因提示、跳过与继续/重试均可见，无裁切。
- `OnboardingView` 接收展示模型与回调，`OnboardingDemo` 仅在内存中模拟步骤切换与状态推进，不把模拟检查当作真实输入源、语言包、权限或服务验证。模型体积与下载进度明确标为示例。
- 支持跳过后继续、重试、返回指定步骤；各 Gallery 条目带独立身份，避免切换状态时沿用上一条的本地状态。
- 通过：`scripts/render-gallery.sh`（此时含 U2 示例共 92 张）、临时验证目录原样 `scripts/test.sh`（Swift + Rime + 标识扫描）。真实输入法试打、权限弹窗与下载不在 D0 实现范围；键盘和 VoiceOver 待人工走查。


### 设置窗口与 U4 最终验收证据

- **完成（待验收）**：设置窗口 760×540，通用、输入法、翻译、语音、划词、截图、AI 连接、操作模板、快捷键、权限、隐私、关于全部 12 分区。额外覆盖 AI 未配置/测试中/混合结果、快捷键冲突、权限未授权、语音模型下载中/已就绪、模板编辑、划词功能与应用子页，共 21 条、42 张 PNG。
- 设置可在内存中切换分区、编辑值、调整开关与选择项、演示模板编辑/恢复、模型下载/取消/删除、能力测试状态和快捷键录制。字段点击后在原生编辑 sheet 中修改；导出初态用纯 SwiftUI 绘制，以免系统承载控件缺失。不会读取真实偏好、接收真实密钥、注册快捷键、访问网络/权限/麦克风或写入用户配置。
- 原生滚动容器首次导出出现空白正文，已改为固定分页布局；划词“功能与应用”初版裁切标题/页脚，已按网格调整行距。最终 42 张设置 PNG 已全部重看，正文与页脚均完整。额外用 Vision 检查这 42 张合成截图：均为 1520×1080，均识别出正文与“设计预览”页脚，0 失败。
- 候选预览点击可更新选中项；选择其他候选后清除旧译文。HUD 录音/识别中关闭切换为取消，其余状态关闭隐藏，可重新显示；详情可展开/收起。全部只是本地演示，不声称真实输入或录音功能已完成。

| U4 覆盖组 | 独立条目 | 浅深 PNG | 文件名模式 |
| --- | ---: | ---: | --- |
| 设置：12 默认 + 9 补充 | 21 | 42 | `settings-<section>-<scenario>-<theme>.png` |
| 引导：5 步 × 5 状态 | 25 | 50 | `onboarding-{input,language,permissions,voice,ai}-{pending,progressing,done,skipped,failed}-<theme>.png` |
| 候选窗 + 译文栏 | 8 | 16 | `candidate-{none,translating,zh-en,en-zh,dictionary,unavailable,ai,long}-<theme>.png` |
| 输入模式提示 | 3 | 6 | `input-mode-{chinese,english,scheme}-<theme>.png` |
| 语音 HUD：6 状态 + 2 详情 | 8 | 16 | `voice-hud-{recording,recognizing,done,failed,cancelled,missing-model,failed-detail,missing-model-detail}-<theme>.png` |
| **U4 合计** | **65** | **130** | 另保留 U2 示例 4 张，全量 134 张 |

| 验证项 | 结果 | 实际证据 |
| --- | --- | --- |
| `git merge main` | 通过 | 开工时快进到 `041b098`（U1/U2 已验收）；后续 main 的并行提交未再合入 |
| `swift build`、`swift build -c release` | 通过 | Swift 6 Debug/Release 编译成功 |
| `xcrun vtool -show-build .build/release/RoarkTApp` | 通过 | `minos 14.0`，SDK 26.5；未调用 macOS 26 专属 API |
| 当前 worktree `scripts/test.sh` | **阻塞（环境路径）** | Swift 2 测试通过；Rime 脚本只搜索相邻 checkout，当前布局找不到参考运行库 |
| 临时源码副本的原样 `scripts/test.sh` | 通过 | 复制当前 App/Core/Platform/Shared/Services/Tests/Rime/Package.swift 和两个测试脚本，在相邻目录链接只读参考库。全部通过：2 Swift 测试、3 Rime 方案新鲜部署产物、旧标识扫描。未更改测试脚本或参考库，副本自动清理 |
| `scripts/render-gallery.sh` | 通过 | `dist/gallery/` 共 134 PNG；按规格独立列出的状态矩阵核对，文件名/数量完整，无重复或缺项 |
| 重复 `RoarkTApp --render-gallery <临时目录>` | 通过 | 134 张与默认输出逐字节一致；临时目录已清理 |
| 每张 PNG 自查 | 通过（自查，待 Claude 视觉验收） | 134 张全部查看；U4 的 130 张按带文件名的联系表逐张检查，修复后重看受影响项。联系表保留于忽略的 `dist/u4-review/` |
| 代码与文件边界检查 | 通过 | 相对开工基线只新增 U4 的 View/Mock/Gallery/组件文件，并追加 Catalog 与本规格；既有 DesignSystem 接口、界面 1–5、Package.swift、Core、Platform 均无改动；`git diff --check` 通过 |
| 真实键盘 / VoiceOver / macOS 14 真机 | 待人工验证 | 编译和图片检查不能代替交互及真机兼容验收 |

Claude 需决定/验收：

1. U4 最终视觉（包括按网格派生的候选/HUD/模式尺寸、设置字段的编辑 sheet）与纯键盘、VoiceOver 表现。
2. 由测试脚本负责方修复独立 worktree 的 Rime 依赖发现路径；本任务未越界修改。
3. U3 分支合入时保留 Catalog 的 U4 追加区块：`InputVoiceGallery.entries + OnboardingGallery.entries + SettingsGallery.entries`。本任务未改 U3 文件，未合并或推送其他分支。

未验证的真实系统行为属于后续 M1/M2/M5：输入源试打鉴权、候选上屏/窗口避让、不抢焦点、麦克风与 Fn、模型下载、权限弹窗、AI 服务与设置持久化。D0 使用合成状态，不代表这些功能验收通过。
U2 交付时的未完成范围：U3、U4、U5 均未开始；当时尚无全部界面状态 PNG。Claude 需确认本增量视觉及原生 SF Symbols/控件的表现，后续完整结果浮窗在 U3 实现。没有修改其他 worktree、Package.swift、Core 或 Platform；未 push、未合并。


## U3 分段证据

- A 段（2026-10-11）：`App/Mock/` 中建立界面 1–5 的纯 Swift 数据模型，39 个确定性合成状态样例（菜单栏 6、划词工具栏 5、结果浮窗 15、截图编辑器 5、图片预览 8）。不引用 SwiftUI、DesignSystem 或 Gallery。
- `swift build` 通过；`scripts/test.sh` 中 2 个 Swift 测试通过，但 Rime 部署被阻塞：独立 worktree 下现有脚本无法定位相邻运行时，报 `Missing Rime deployment dependency: /bin/rime_deployer`。A 段交付时尚未生成 PNG，B 段等待 U1/U2；后续结果见下。

### B 段（2026-10-11）

- 初次 B 段已合并 `agent/ui`（U1 `fbbabfa`、U2 `1f5b27a`，分支检查时已含验收提交 `041b098`）；合并只解决本规格的证据冲突，保留双方记录。未修改 `App/DesignSystem/`、Gallery 窗口或渲染器。
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


### Claude 复验修正（2026-10-11）

- 已收到验收：菜单栏、结果浮窗、划词工具栏、图片预览通过。U3 保持“完成（待验收）”，等待截图编辑器本轮复验。
- 截图编辑器重做为 PixPin 式全屏冻结遮罩：合成桌面含菜单栏、文稿窗口、终端窗口、文件图标与 Dock；同一画面通过偶奇填充遮罩压暗选区外，选区保持原亮度。去掉截图编辑器标题栏与窗口外框；强调色边框有 8 个独立调整手柄，尺寸徽标位于左上方；支持原型内移动/调整选区。
- 13 个标注/操作按钮集中在浮动胶囊中，默认贴选区下方右对齐，底部空间不足时上翻。“已选区”样例特意靠近屏幕底部，展示上翻；保存、取消、完成位于胶囊右端。OCR 结果浮在选区右侧；右侧不足时移到左侧，位置限制在屏幕内。
- 屏幕逻辑尺寸 1440×900，Gallery 按 2/3 比例显示为 960×600 pt；2x 导出 PNG 为 1920×1200 px，比例保持 16:10。
- 两处 OCR 进行中界面统一为“本机识别中…”，不再复用带“连接中”的 StatusLine。全局检查 `App/`：连接/网络措辞仅保留在 AI 服务与结果请求状态；本地 OCR 不使用网络措辞。
- `SelectionToolbarView` 在安全输入时返回空视图，连提示条、尺寸与可访问性容器都不输出。Gallery 注册点单独展示“Gallery 说明 · FR-E8 / 此状态不渲染任何界面”，用于解释空白行为，不属于产品界面。
- 按 Claude 本轮明确授权，仅在 `Tokens.swift` 新增截图常量及两项桌面颜色；未修改或删除已有 Tokens，也未改动 DesignSystem 组件。

| 本轮验证 | 结果 | 证据 |
| --- | --- | --- |
| `swift build`、`swift build -c release` | 通过 | Debug / Release 均成功 |
| `swift test` | 通过 | 2 个 Swift 测试；`scripts/test.sh` 的已知 T1 Rime 阻塞按要求忽略，本轮不作为 U3 阻塞 |
| `scripts/render-gallery.sh` | 通过 | 重新生成 78 张 PNG，包含 10 张新版全屏截图编辑器与两张 Gallery 安全输入说明卡 |
| `.build/review-check dist/gallery`（临时 Swift 验证程序） | 通过 | 8 个手柄位置唯一；工具栏下方/上方位置正确；选区移动/极端拖拽不越界且保留最小尺寸；OCR 面板不越界；安全输入视图 `NSHostingView.fittingSize == .zero`；10 张截图 PNG 均为 1920×1200 |
| `swift .build/check-gallery.swift dist/gallery` | 通过 | 全部 78 张 PNG 的数量、签名与尺寸核对通过；刷新 `dist/gallery-review/` 联系表 |
| 两种主题 PNG 自查 | 通过（实现自查） | 查看截图编辑器五态联系表及标注、上翻、OCR 浮板原图；查看两个 OCR 入口与 Gallery 安全输入卡。未发现外框残留、面板出界或工具栏被裁切 |
| 全局本地操作措辞扫描、Tokens 差异、`git diff --check` | 通过 | 本地 OCR 无“连接中”；Tokens 仅新增；无空白错误 |

仍未覆盖：真实键鼠调整、VoiceOver、生产截图/裁剪/保存、真实 OCR 与 Secure Input 检测。本轮仍是合成数据设计原型，未申请系统权限、读取屏幕或访问网络。

## 问题

- U3：Rime 运行时缺失是已知 T1 依赖问题；Claude 已明确由另一 agent 修复，本次按要求忽略该阻塞，未修改测试脚本。
- U3 组件需求：增加可被 `ImageRenderer` 渲染的滚动正文/多行编辑快照。现有 `ScrollView` 在本机离屏渲染正文空白，`DesignTextArea` 内的原生 `TextEditor` 显示不支持占位图；U3 注册点在 `--render-gallery` 时传入只读导出标记，用同一数据、同一 Tokens 绘制正文/编辑文本快照。交互 Gallery 保留原滚动区和 DesignTextArea。PNG 不证明编辑器光标、选择与滚动行为。
- U3 Tokens：截图画布、选区、遮罩、手柄、浮动工具栏与 OCR 面板常量已按 Claude 授权新增，已有项未改。图片预览仍复用 `resultMaxHeight`（480）与 `control × 10`（280），其视觉已验收，语义命名可由 U1 所有者后续统一。
- U3 交互边界：设置/退出/复制/保存/返回来源是演示反馈；截图标注点击添加预设标注，并非生产绘制引擎。原型流式状态为冻结时刻，不运行异步网络，也无闪烁动画；减少动态效果下仍保持静态。真实系统能力按后续规格接入。
