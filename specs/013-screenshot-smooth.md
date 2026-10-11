# SPEC-013 截图：小而顺

- 阶段：打磨 P2（截图）
- 状态：InProgress
- 来源：对比 macshot、Snapzy、Capso、capcap、Flameshot 近期提交（2026-10-11）
- 原则：功能少，流畅优先。不做录屏、滚动长截图、上传、背景美化。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| S-1 | 顺畅：① 启动后预热 `SCShareableContent` 并在后台刷新（屏幕/窗口变化时），⌃1 不再现查；多屏并行截取。② 选区画布改为图层：冻结底图作为 `CALayer.contents` 只设置一次；遮罩、选区框、手柄、尺寸标签用 `CAShapeLayer`/`CATextLayer`，拖动只改 path（关闭隐式动画）；标注单独一层，只在标注变化时重绘，不再每次拖动整屏 `draw` 和合成。③ 工具栏只创建一次，之后只移动/更新状态。④ App 启动后在后台预热 Vision OCR。⑤ 计时日志（只记数字，`privacy: .public`）：⌃1→遮罩可见毫秒数；拖动期间平均帧间隔 | pi-xpc | 已实现，待人工验证 |
| S-2 | 悬停选窗口：遮罩出现后鼠标悬停高亮所在窗口（用截图时刻的窗口列表，排除自身、Dock、桌面、菜单栏小窗口、透明/屏幕外窗口），单击即选中该窗口区域；拖动仍为自由框选；结果从冻结底图裁剪，不重新截图 | pi-xpc | 已实现，待人工验证 |
| S-3 | AI 开发输出：↩ 复制图片并关闭（现状保留，⌘C 同效）；⇧↩ 保存 PNG 并复制文件路径（默认 `~/Pictures/RockType`，设置 → 截图可改；文件名 `RockType-yyyyMMdd-HHmmss.png`）；R 恢复上次选区（仅本次运行期内存，不落盘） | pi-surfaces 提供保存/路径服务与设置；pi-xpc 在画布接键 | 未开始 |
| S-4 | 贴图：P 把当前选区（含标注）钉在屏幕最上层；可拖动、触控板/滚轮缩放、⌘C 复制、双击或 Esc 关闭；可同时多张；不落盘 | pi-surfaces | 未开始 |

## 分工与边界

- pi-xpc 独占 `CaptureCanvas.swift`、`CaptureToolbar.swift`、`Platform/ScreenCapture.swift`、`ScreenshotCoordinator.swift`。
- pi-surfaces 新建独立文件（如 `App/Features/Screenshot/ScreenshotOutput.swift`、`PinnedImagePanel.swift`），提供 `save(_:CGImage) throws -> URL`、`copyPath(_:)`、`pin(_:CGImage, at:)` 等接口及设置项；不改上面 4 个文件。接键由 pi-xpc 在 S-1 合并后完成（或由 Claude 合并时接）。
- Secure Input 生效时拒绝截图/贴图/保存，与现状一致；不记录图片内容、路径中的用户名以外信息不写日志。

## 验收

- 目标：⌃1→遮罩 < 150 ms（预热后，计时日志）；拖动无可见卡顿（平均帧间隔 ≤ 17 ms，计时日志）；工具栏不闪烁。
- `scripts/test.sh`、`scripts/build.sh` 真实退出码 0；几何/裁剪/文件名/路径/贴图缩放边界有单元测试。
- 真实操作（⌃1、拖动、悬停窗口、⇧↩ 粘贴路径到终端、贴图）标“待人工验证”，由 Claude 安装后与用户验收。

## 验收证据

### S-1（pi-xpc）

- 实现：启动预热 ScreenCaptureKit 元数据；每秒检查窗口/屏幕几何变化并异步刷新（无权限或 Secure Input 时不读取）；预热后截图使用缓存，多屏 captureImage 并行。未预热或首次授权仍允许一次冷查询。
- 冻结底图只设置一次 CALayer.contents；遮罩、边框、手柄、尺寸标签独立图层，关闭隐式动画；标注独立视图，仅编辑时重绘，裁剪变化只改 mask；NSHostingView 工具栏复用。
- Vision 后台使用合成空白图片预热，不读取屏幕。新增数字公开日志 overlay_ms（遮罩提交显示）与 drag_frame_ms（拖动期间 display-link 回调平均间隔），不记录图片、窗口标题或路径。
- 通过：`scripts/test.sh` 真实退出码 **0**（含 CanvasTests 的底图/工具栏复用回归及原有 Retina 裁剪、标注测试）。`git diff --check` 退出码 **0**。
- 通过：`scripts/build.sh` 真实退出码 **0**，包含签名及语音 XPC smoke。
- 待人工验证：真实 ⌃1 延迟 <150 ms、拖动间隔 ≤17 ms/视觉流畅度、图层方向与标注位置、多屏、工具栏不闪烁。回调计时不能代替真实呈现与视觉验收；未安装、注册或启动输入法。


### S-2（pi-xpc）

- 截图时取一次窗口服务器前后顺序列表，排除自身、Dock、非普通层级（桌面/菜单栏）、透明、小于 40×40 point 及屏幕外窗口；各屏保留裁剪后的局部矩形。悬停使用该快照，不再查询窗口或截图。
- 悬停高亮最前窗口；单击确认；移动超过 3 point 转为自由框选。既有选区继续支持移动/手柄调整。输出仍来自冻结底图。
- 通过：`scripts/test.sh` 真实退出码 **0**；新增合成窗口过滤、负坐标/屏幕上下排列、裁剪/前后顺序、单击与拖动分流测试；`git diff --check` **0**。
- 待人工验证：真实窗口遮挡、全屏、跨屏窗口、悬停初始位置、鼠标与键盘交互。最终整合构建结果见接键证据。
