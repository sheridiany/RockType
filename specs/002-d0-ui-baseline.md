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
| U1 | DesignSystem：Tokens + 组件 | pi | 未开始 |
| U2 | Gallery 窗口与 `--render-gallery` | pi | 未开始 |
| U3 | 界面 1–5（菜单栏、工具栏、结果浮窗、截图编辑器、图片预览） | pi | 未开始 |
| U4 | 界面 6–10（设置、引导、候选窗、模式提示、语音 HUD） | pi | 未开始 |
| U5 | 设计走查 | Claude + 用户 | 未开始 |

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 全部界面 × 状态 × 两种主题都有 PNG | `scripts/render-gallery.sh` | 未运行 | |
| 只引用 Tokens（无写死颜色/尺寸） | 代码检查 | 未运行 | |
| 与 RoarkTools 基线视觉一致 | 对照截图走查 | 未运行 | |
| Gallery 可键盘操作 | 手工 | 待人工验证 | |
| `swift build`、`scripts/test.sh` 通过 | 命令 | 未运行 | |
