# SPEC-006 截图（M4）

- 阶段：M4
- 覆盖需求：FR-D1–D7
- 状态：InProgress
- 依赖：SPEC-004（`⌃1` 快捷键、屏幕录制权限）、SPEC-005 M3-1（操作引擎、翻译路由）、SPEC-010（OCR、Placement、ScreenGeometry、Clipboard）、D0 U3 截图编辑器与图片预览

## 范围

`⌃1` 冻结所有屏幕 → 遮罩上框选（显示尺寸、可调整）→ 标注 → 完成（复制）/ 保存 / OCR / 翻译 / 图片理解；剪贴板图片与拖入图片也能进入同一套动作。界面沿用 U3 的 `ScreenshotEditor` 与图片预览视图（PixPin 风格，已验收）。

不做：滚动长截图、录屏、贴图（钉在屏幕）。

## 技术计划

- **捕获**：`ScreenCaptureKit`（`SCScreenshotManager.captureImage`，macOS 14+）按屏幕捕获原始分辨率图像；捕获前隐藏 RoarkT 自身浮窗（排除自身应用的窗口）。无屏幕录制权限时显示权限说明（SPEC-004 权限中心），不弹系统框以外的东西。
- **遮罩窗口**：每块屏幕一个无边框、`.screenSaver` 级别、覆盖全屏的 `NSPanel`，显示冻结图像；跨屏框选不支持（与 PixPin 一致：选区限制在起始屏幕）。Esc 取消，不留文件、不发请求。
- **选区**：拖拽框选、8 个手柄调整、方向键微调（⇧ 加速）、尺寸徽标显示像素尺寸。
- **标注**：矩形、椭圆、箭头、画笔、马赛克、文字、序号；颜色与粗细取 Tokens；撤销/重做；导出时按原始像素分辨率合成（不能按视图分辨率）。
- **动作**：完成=合成图写剪贴板（PNG）并关闭；保存=`NSSavePanel`，格式按设置（PNG/JPEG）；识别文字=`Platform/OCR`（本机，文案“本机识别中…”），结果面板可编辑、复制；翻译=对（可编辑的）OCR 文本走操作引擎翻译路由，结果进结果浮窗；图片理解=显式动作，需视觉模型（设置中图片能力为“可用”），否则禁用并引导；发送前显示将发送的图片。
- **外部图片输入（FR-D7）**：菜单栏面板与 Dock 拖放（不弹 Dock，用菜单栏面板接收拖入）、“从剪贴板打开图片”；进入图片预览视图，动作同上。剪贴板读取遵循 `Platform/Clipboard` 规则。
- **快捷键**：`HotkeyCenter` 的截图动作从“即将推出”改为启动截图。
- **隐私**：截图只在内存；仅“保存”写文件；临时数据关闭即释放。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| D-1 | 捕获、遮罩窗口、选区与调整、Esc 取消、⌃1 接入 | pi-xpc | 已实现，待集成与人工验收 |
| D-2 | 标注工具与原始分辨率合成、撤销 | pi-xpc | 已实现，待人工验收 |
| D-3 | 完成/保存、OCR、翻译、图片理解 | pi-xpc | 已实现，待集成与人工验收 |
| D-4 | 剪贴板图片与拖入图片入口 | pi-xpc | 已实现，待菜单栏集成与人工验收 |
| D-3a | 截图 OCR 独立取词方式与显示 | pi-xpc | 已完成，自动化通过 |
| D-4a | 主 App 接线、能力门禁、统一结果与最近结果 | pi-platform | 代码集成完成，待完整验证与人工验收 |
| D-5 | 验收 | Claude + 用户 | 未开始 |

**文件所有权**：`App/Features/Screenshot/`、`App/Surfaces/` 中截图编辑器与图片预览视图（只做接线需要的最小调整，保持 Gallery 可渲染）、`App/Shell/Hotkeys/` 中截图动作一处、`Platform/` 补充（捕获）、对应 `Tests/`。`AppDelegate` 接线由 Claude 集成（提供 `start()`/`stop()`）。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 合成按原始分辨率（2x 屏幕） | 单元测试：给定图像与标注，输出像素尺寸与关键像素 | 通过 | `CompositorTests`：2× 尺寸、边框/背景像素、上下方向、撤销重做 |
| 选区几何、手柄、微调 | 单元测试 | 通过 | `CaptureTests`：反向拖动、边界移动、8 手柄极限；真实方向键/Shift 待人工 |
| Esc 取消无文件、无请求 | 单元测试 + 手工 | 自动化通过；待人工验证 | `CaptureTests` 取消后迟到捕获不完成；`SessionTests` 关闭后 OCR 不更新、安全输入零请求。真实 Esc 事件及文件/网络监测未运行 |
| ⌃1 冻结所有屏幕，自身浮窗不入镜 | 手工 | 待人工验证 | |
| 完成后剪贴板图片与选区一致 | 手工 | 待人工验证 | |
| OCR 断网可用；翻译结果进结果浮窗 | 手工 | 待人工验证 | |
| 无视觉模型时图片理解被阻止并引导 | 单元测试 + 手工 | 自动化通过；待人工验证 | `SessionTests` 验证未通过时零发送、预览确认前零发送、连接变化后拒绝发送；设置引导待集成 |
| `scripts/test.sh`、`scripts/build.sh`、`scripts/render-gallery.sh` | 命令 | 通过 | 2026-10-11：32 XCTest + 91 Swift Testing、Rime 部署及标识检查通过；全部产物构建签名通过；Gallery 输出 208 张 PNG。Gallery 只验证原型可渲染，不代表实际编辑器已验收 |
| 外部图片导入 | 单元测试 + 手工 | 自动化通过；待人工验证 | `ImportTests`：PNG 尺寸、损坏/超限数据拒绝、远程 URL/目录拒绝、图片与文件拖放类型识别；真实拖放及剪贴板待集成 |

| 截图 OCR 独立取词方式与显示 | 回归测试 | 通过 | `SessionTests.testTextOperationsUseEditedOCRMethodAndSettings` 验证翻译/总结保留修正后文字并使用 `.screenshotOCR`；`ResultWindowTests.renderLiveSurface` 覆盖此类型的深浅色渲染。`scripts/test.sh`：32 XCTest、114 Swift Testing、Rime、快捷键、权限与标识检查全部通过。通用浮窗实际接线及人工走查留待 M3-6 后续集成 |

## 进度

- D-3a：按 Claude 验收反馈补充 `.screenshotOCR` 及“截图 OCR”显示；截图文字翻译/总结和相关测试已同步。仅补充通用结果视图的枚举显示分支，未进行截图结果控制器集成。

- D-1：ScreenCaptureKit 单次内存捕获，排除自身应用；每屏独立遮罩、8 手柄、方向键/Shift 微调、像素尺寸、Esc 取消与迟到捕获丢弃。HotkeyCenter.screenshotAction 供 Claude 接线。`scripts/test.sh` 通过（几何、取消与快捷键回归）；真实多屏、权限及焦点待人工验证。

- D-2：七种标注、文字输入、撤销/重做，工具栏沿用 Tokens。合成以原图像素为准；`scripts/test.sh` 通过，2× 合成尺寸与红色边框/未覆盖区域像素断言通过。Gallery 原型未改；实际编辑器外观待 D-5。

- D-3：完成写 PNG 剪贴板并关闭；预览提供 PNG/JPEG 另存为、本机 OCR、编辑后翻译/总结、图片发送确认和结果浮窗。复用 OperationsEnvironment/OperationRunner 与 AIClient。`scripts/test.sh` 通过：编辑后文字传递、视觉能力门禁、确认前零发送、配置变化失效、关闭后迟到结果丢弃、安全输入零请求。实际剪贴板/保存、断网 OCR、真实 XPC/视觉端点待人工验证。

- D-4：显式剪贴板读取复用 `Clipboard.readPNG()`；提供菜单栏可嵌入的 `ScreenshotImportControls`（按钮与拖入区域），图片/文件拖放共用预览流程。后台解码、EXIF 方向校正、40 MB / 6400 万像素限制、迟到导入丢弃。最终检查补充捕获等待期全局 Esc、关闭时清空本功能最近内容、翻转画布正确显示与小屏滚动预览。最终三条验收命令均通过。

### Claude 集成清单（未修改 AppDelegate 或菜单栏所有权文件）

1. AppDelegate 持有一个 `ScreenshotCoordinator`，启动/退出调用 `start()` / `stop()`；清除当前内容时调用 `cancel()` 和 `closePreview()`。
2. `hotkeys.screenshotAction = { [weak screenshot] in screenshot?.capture() }`；菜单栏截图也调用 `capture()`。快捷键设置中的“截图即将推出”文案仍在范围外的 `ShortcutRecorder.swift`，请集成时移除截图占位。
3. 设置 `readSettings` 读取当前 SettingsStore；`onNotice` 展示脱敏错误；`onPermissionRequired` 接屏幕录制权限说明；`configureVision` 打开 AI 连接设置。
4. 设置 `imageCapabilityVerified(connection, model)`：只有**当前相同连接、模型和密钥测试状态**的图片能力为“可用”才返回 true。默认 false，避免未接线时误上传。现有 `ShellConnectionModel.results[2]` 是图片测试结果；应在确认配置未变化、已刷新状态后桥接，不能只用 supportsImages 标记。
5. 将 `ScreenshotImportControls(coordinator: screenshot)` 嵌入菜单栏面板；也可直接使用 `openClipboardImage()` 与 `acceptDrop(_:)`。本分支不修改 MenuBarPanelView，不创建 Dock 入口。
6. 实际遮罩由 `CaptureCanvas` / `CaptureToolbar` 驱动；完成按钮复制并关闭，OCR 图标进入预览，预览提供识别、翻译、总结、保存和发送图片确认。`ImagePreviewView(session:)` 是运行态入口，原 Gallery 初始化器保持可用。

### 待人工验证（D-5）

- 真实 ⌃1、多屏不同缩放/负坐标、全屏应用、自身浮窗隐藏、跨屏拖动被限制；拖动/8 手柄/方向键/Shift/文字输入/撤销重做，Esc 在捕获等待与编辑中均生效。
- 七种标注、尤其文字/箭头/马赛克的实际外观；原始像素预览与完成后的剪贴板一致；PNG/JPEG 保存、保存取消、Esc 无内容文件。
- 断网 OCR；编辑 OCR 后通过真实 XPC 翻译及总结；视觉模型门禁、设置引导、发送前图片一致和真实端点收到图片；网络/限流/权限错误与取消。
- 剪贴板 PNG/TIFF、Finder 文件与应用图片拖放；Secure Input/密码框前后切换、关闭内容释放、焦点与小屏/深浅色/VoiceOver。Gallery 抽看截图编辑器和图片 OCR 原型正常，运行态设计尚未验收。

## 问题

- 请 Claude 确认外部图片导入的 40 MB / 6400 万像素上限；当前超限明确提示，不缩小或静默截断。
- 已按 Claude 决定新增 `ContentSnapshot.CaptureMethod.screenshotOCR`，截图编辑后文字的翻译/总结使用此类型；通用结果浮窗显示“截图 OCR”。本次仅补充枚举显示分支，截图结果并入通用浮窗的接线等待后续通知。
- 图片理解走现有 AIClient 的非流式图片接口；OCR 文字操作走既有 OperationRunner 流式接口。运行态结果浮窗使用相同 Tokens，尚未与并行开发的通用结果窗口控制器合并；如需共用控制器，由 Claude 集成。

### M4 集成步骤一（pi-platform，2026-10-11）

- AppDelegate 持有截图协调器，接 start/stop、快捷键与菜单截图、图片导入、清除内容、权限说明与 AI 设置定位。图片测试门禁刷新当前连接，核对测试模型及钥匙串密钥 SHA-256 摘要；配置、密钥、读取权限变化使既有测试失效。摘要仅在内存，不记录密钥。
- 删除截图独立结果窗与独立 OperationsEnvironment。OCR 翻译/总结交给共享 SelectionOperationsController；图片解释期间在预览显示状态和取消，成功后进入通用 ResultWindow / RecentResults。关闭预览不清除共享历史；隐私开关与清除当前内容继续由共享控制器处理。
- 图片不进入最近结果，追问只使用已完成的文字解释，界面原文说明此限制；最近结果重开保持相同模板与保守的“仅复制”来源行为。
- `scripts/test.sh` 退出 0：35 XCTest + 124 Swift Testing，以及 Rime、快捷键、权限与标识扫描通过。新增测试覆盖配置/模型/密钥变化、测试期间换密钥、钥匙串读取失败、OCR 修正文本、统一浮窗、图片解释追问、重开、动态隐私与清除。日志 `/tmp/roarkt-m4-tests.log`。
- 完整构建、Gallery、主 App 启动冒烟尚未运行；真实屏幕录制权限、快捷键、多屏、拖放、剪贴板、真实端点、焦点/键盘与设计验收待人工验证。
