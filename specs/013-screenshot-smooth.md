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
| S-3 | AI 开发输出：↩ 复制图片并关闭（现状保留，⌘C 同效）；⇧↩ 保存 PNG 并复制文件路径（默认 `~/Pictures/RockType`，设置 → 截图可改；文件名 `RockType-yyyyMMdd-HHmmss.png`）；R 恢复上次选区（仅本次运行期内存，不落盘） | pi-surfaces 提供保存/路径服务与设置；pi-xpc 在画布接键 | 服务、设置与画布接键已实现；待人工验收 |
| S-4 | 贴图：P 把当前选区（含标注）钉在屏幕最上层；可拖动、触控板/滚轮缩放、⌘C 复制、双击或 Esc 关闭；可同时多张；不落盘 | pi-surfaces | 面板与画布接键已实现；待人工验收 |

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

### S-3：保存/复制服务与设置（2026-10-11）

- 新增 `ScreenshotOutput`、`ScreenshotOutputSettings`，统一设置新增 `screenshot.saveDirectory`；默认 `~/Pictures/RockType`，支持目录选择与恢复默认。快速保存固定 PNG，与预览的另存格式独立。
- 文件名采用本地时间 `RockType-yyyyMMdd-HHmmss.png`；同秒冲突追加 `-2`、`-3`，以独占写入避免覆盖。复制的是未加 shell 引号的绝对路径，含空格时终端命令需正确引用。
- 所有输出操作先检查 Secure Input/密码框状态；保存编码后再次检查；不记录内容或路径。
- 自动化通过：`scripts/test.sh` 真实退出码 **0**。覆盖文件名、默认/自选/非法路径、设置编码、PNG 尺寸、同秒不覆盖、复制路径及受保护输入无副作用。首次前台调用 60 秒超时，未取得退出码；此结果来自随后完整后台运行。
- 完整 `scripts/build.sh` 真实退出码 **0**（含签名与语音 XPC smoke）；未安装、注册或启动输入法。
- 待人工验证：目录选择/取消/恢复默认、重启持久化、不可写目录提示，以及 pi-xpc 接键后 ⇧↩ 保存并粘贴路径。↩/⌘C、R 恢复选区均由 pi-xpc 接入，本次未修改四个独占文件。

接入接口（均 `@MainActor`，实例有 `.shared`）：

```swift
ScreenshotOutput.save(_ image: CGImage) throws -> URL
ScreenshotOutput.copyPath(_ url: URL) throws
ScreenshotOutput.copyImage(_ image: CGImage) throws
```

传入含标注的最终合成图；⇧↩ 先 `save` 再 `copyPath`，成功后关闭画布。抛错由调用方显示固定提示，不记录原始错误或路径；保存成功但复制失败时文件仍保留。


### S-4：内存贴图面板（2026-10-11）

- 新增独立 `PinnedImagePanel.swift`，支持多张浮动贴图、原生拖动、滚轮/触控板滚动与捏合缩放、⌘C 复制原始合成图、双击/Esc 关闭；关闭即释放面板图片。图层直接持有 CGImage，不生成磁盘文件。
- 初始位置与缩放结果收进当前屏幕可见区域；保持宽高比，缩放范围为初始显示大小的 0.1–4 倍（另受屏幕尺寸上限限制）。面板可跨 Spaces/全屏应用显示，不激活来源应用以外的主窗口。
- 创建、交互和复制均检查安全输入；100 ms 检查发现受保护输入时关闭所有贴图。
- 最终 `scripts/test.sh` 与 `scripts/build.sh` 真实退出码均为 **0**；构建包含本面板及全部签名产物。新增测试覆盖缩放上下界、非有限倍率、负坐标副屏、越界收敛、宽高比及安全输入拒绝创建。
- 待人工验证：pi-xpc 接 P 后的完整流程、含标注/Retina 显示、跨屏拖动、全屏置顶、多张贴图、键盘焦点与来源保持、滚轮/捏合手感、⌘C 内容、双击/Esc 关闭、Secure Input 生效后关闭、浅深色及 VoiceOver。未把构建成功视为 UI 验收通过。

接入接口（均 `@MainActor`）：

```swift
PinnedImageController.shared.pin(_ image: CGImage, at rect: CGRect) -> Bool
PinnedImageController.shared.closeAll()
```

`rect` 为选区的 **AppKit 全局屏幕坐标，左下原点、单位 point**，不能传像素坐标或画布局部坐标；`image` 为含标注最终合成图。返回 false 表示受保护输入、无可用屏幕或非法矩形。调用方先关闭截图遮罩再 `pin`，避免关闭画布时影响新贴图焦点；无需持有返回面板，由共享 controller 管理其生命周期。应用“清除当前内容”或停止截图功能时可调用 `closeAll()`。四个 pi-xpc 独占文件保持不变，P 接键由 pi-xpc 完成。

### S-3 画布接键（pi-xpc）

- 已将 main 的 surfaces 实现合入当前 agent/xpc（合并后 `scripts/test.sh` 真实退出码 **0**），使用真实 `ScreenshotOutput.shared` 接口，无占位。
- ↩/⌘C 复制合成图后关闭；⇧↩ 保存 PNG、复制绝对路径，成功后关闭；失败保留画布并显示固定提示，保存成功但复制失败明确提示文件已保留。文字标注编辑期间 ⌘C/⌘Z 交给文本编辑器。
- R 恢复最近成功复制、保存、贴图或打开预览的选区；只记显示器 ID 与 point 矩形，不保存图片/标注或写磁盘；恢复切回原显示器，屏幕缩小时裁剪，断开时提示。恢复会清除本次标注，仅恢复选区。
- 工具栏 tooltip 与尺寸标签已列出 ↩/⌘C、⇧↩、R；空选区也提示 R。
- 通过：`scripts/test.sh` 真实退出码 **0**；覆盖按键分流、Retina 输出尺寸、保护态拒绝保存、恢复裁剪边界，含 surfaces 文件名/路径/PNG/受保护输入测试。`swift build` 与 `git diff --check` **0**。
- 待人工验证：真实剪贴板粘贴、⇧↩ 路径到终端（有空格时自行引用）、失败提示、文本标注编辑、跨屏 R、键盘焦点。最终签名构建在 S-4 接键后统一执行。

### S-4 画布接键与最终整合（pi-xpc）

- P 将含标注的最终合成图交给 `PinnedImageController.shared.pin(_:at:)`。先关闭遮罩/恢复隐藏窗口，再显示贴图，避免新面板丢失焦点；停止截图协调器时调用 `closeAll()`。
- 画布 top-left point 转换为全局 AppKit bottom-left point，保留负坐标副屏位置及原尺寸，不把 Retina 像素传给面板。P 同样经过安全输入检查；成功贴图更新 R 的内存选区。
- 工具栏完成按钮 tooltip、尺寸标签和可访问性说明均补齐 P。
- 新增测试：P 输出确实包含标注像素、Retina 裁剪尺寸、安全输入拒绝输出、负坐标副屏全局坐标；同时运行 surfaces 的贴图缩放边界与拒绝创建测试。
- 通过：最终 `scripts/test.sh` 真实退出码 **0**，`scripts/build.sh` 真实退出码 **0**（包含 App/输入法/语音产物签名与语音 XPC smoke），`git diff --check` **0**。所有任务的最终整合版本已覆盖。
- 待人工验证：安装版 ⌃1/拖动/悬停窗口、150 ms/17 ms 指标、工具栏及图层方向、真实 ↩/⌘C/⇧↩/R/P、保存路径粘贴、跨屏恢复/贴图、多张贴图的焦点/缩放/关闭、安全输入切换。未安装、注册或从 worktree 启动输入法；未启动主 App 冒烟。
