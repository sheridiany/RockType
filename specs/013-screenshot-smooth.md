# SPEC-013 截图：小而顺

- 阶段：打磨 P2（截图）
- 状态：Ready
- 来源：对比 macshot、Snapzy、Capso、capcap、Flameshot 近期提交（2026-10-11）
- 原则：功能少，流畅优先。不做录屏、滚动长截图、上传、背景美化。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| S-1 | 顺畅：① 启动后预热 `SCShareableContent` 并在后台刷新（屏幕/窗口变化时），⌃1 不再现查；多屏并行截取。② 选区画布改为图层：冻结底图作为 `CALayer.contents` 只设置一次；遮罩、选区框、手柄、尺寸标签用 `CAShapeLayer`/`CATextLayer`，拖动只改 path（关闭隐式动画）；标注单独一层，只在标注变化时重绘，不再每次拖动整屏 `draw` 和合成。③ 工具栏只创建一次，之后只移动/更新状态。④ App 启动后在后台预热 Vision OCR。⑤ 计时日志（只记数字，`privacy: .public`）：⌃1→遮罩可见毫秒数；拖动期间平均帧间隔 | pi-xpc | 未开始 |
| S-2 | 悬停选窗口：遮罩出现后鼠标悬停高亮所在窗口（用截图时刻的窗口列表，排除自身、Dock、桌面、菜单栏小窗口、透明/屏幕外窗口），单击即选中该窗口区域；拖动仍为自由框选；结果从冻结底图裁剪，不重新截图 | pi-xpc | 未开始 |
| S-3 | AI 开发输出：↩ 复制图片并关闭（现状保留，⌘C 同效）；⇧↩ 保存 PNG 并复制文件路径（默认 `~/Pictures/RockType`，设置 → 截图可改；文件名 `RockType-yyyyMMdd-HHmmss.png`）；R 恢复上次选区（仅本次运行期内存，不落盘） | pi-surfaces 提供保存/路径服务与设置；pi-xpc 在画布接键 | 服务与设置已实现；待接键及人工验收 |
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

### S-3：保存/复制服务与设置（2026-10-11）

- 新增 `ScreenshotOutput`、`ScreenshotOutputSettings`，统一设置新增 `screenshot.saveDirectory`；默认 `~/Pictures/RockType`，支持目录选择与恢复默认。快速保存固定 PNG，与预览的另存格式独立。
- 文件名采用本地时间 `RockType-yyyyMMdd-HHmmss.png`；同秒冲突追加 `-2`、`-3`，以独占写入避免覆盖。复制的是未加 shell 引号的绝对路径，含空格时终端命令需正确引用。
- 所有输出操作先检查 Secure Input/密码框状态；保存编码后再次检查；不记录内容或路径。
- 自动化通过：`scripts/test.sh` 真实退出码 **0**。覆盖文件名、默认/自选/非法路径、设置编码、PNG 尺寸、同秒不覆盖、复制路径及受保护输入无副作用。首次前台调用 60 秒超时，未取得退出码；此结果来自随后完整后台运行。
- 完整 `scripts/build.sh` 正在运行，最终结果随 S-4 证据补充。
- 待人工验证：目录选择/取消/恢复默认、重启持久化、不可写目录提示，以及 pi-xpc 接键后 ⇧↩ 保存并粘贴路径。↩/⌘C、R 恢复选区均由 pi-xpc 接入，本次未修改四个独占文件。

接入接口（均 `@MainActor`，实例有 `.shared`）：

```swift
ScreenshotOutput.save(_ image: CGImage) throws -> URL
ScreenshotOutput.copyPath(_ url: URL) throws
ScreenshotOutput.copyImage(_ image: CGImage) throws
```

传入含标注的最终合成图；⇧↩ 先 `save` 再 `copyPath`，成功后关闭画布。抛错由调用方显示固定提示，不记录原始错误或路径；保存成功但复制失败时文件仍保留。
