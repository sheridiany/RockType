# SPEC-014 深度打磨：截图、AI、OCR、界面与架构

- 阶段：打磨 P2
- 覆盖需求：FR-C*、FR-D*、FR-B*、FR-F1/F2、NFR-7
- 状态：InProgress（2026-10-11 启动，多轮夜间迭代）

## 目标（用户原话要点）

1. 截图需要深度优化（对标 PixPin，用户 PixPin 配置见下）。
2. AI 要配置好、OCR 要配置好——这是程序重点，各种深度优化。
3. 去掉首次引导。
4. 每个界面精细化打磨；代码结构、架构整体整理。

## 已确认的环境事实

- AI：设置里已有 Provider `Magpie · WorkBuddy`，`http://127.0.0.1:3425/v1`，默认模型 `workbuddy/glm-5.3-flash`，密钥在钥匙串 `com.roarkist.roarkt.ai`。实测（2026-10-11）：中译英 1.3s；支持图片输入（data URL PNG 正确识别）。**它是推理模型**：`max_tokens` 太小时 `content` 为 `null`、只有 `reasoning_content`——客户端必须容忍 `reasoning_content` / 空 content、不能把它当成功结果，也不能把推理内容展示给用户。备用：`claude/claude-haiku-5-5`（2.6s，支持图片）。
- OCR：离线 Vision；设置 `screenshot.ocrLanguages = [zh-Hans, en-US]`。

## 分工（文件所有权，跨区只做最小增量修改）

| 窗口 | 负责区域（主要文件） |
| --- | --- |
| pi-xpc | 截图遮罩/选区/标注：`App/Features/Screenshot/{CaptureCanvas,CaptureToolbar,ScreenshotAnnotations,ScreenshotText,ScreenshotCoordinator,ScreenshotSession}.swift` 及其测试 |
| pi-surfaces | 贴图 + 截图预览面板 + OCR：`PinnedImagePanel.swift`、`ScreenshotPreviewContent.swift`、`App/Surfaces/ImagePreviewView.swift`、OCR 引擎 |
| pi-platform | AI 层与 AI 操作：`Core/AI`、`Core/Operations`、`App/Features/{Operations,ResultWindow,Selection,InputAI}`、`Services/TranslationService` 中 AI 路由 |
| pi-ui | 外壳与所有设置界面、菜单栏面板、设计系统、去掉首次引导：`App/Shell`、`App/Surfaces/{SettingsView,MenuBarPanelView,...}`、`App/DesignSystem`、`App/AppDelegate.swift` |
| pi-ime | 输入法 + 语音：`InputMethod/`、`App/Features/Voice`、`Services/VoiceWorker`；第二轮起负责全局架构整理（见 R2） |

`Core/Settings/AppSettings.swift` 是共享文件：只允许追加字段（带默认值、旧 JSON 缺字段可解码），不改已有字段。

## 任务

### 第一轮（R1）

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| R1-SHOT | 标注体验（PixPin 批次 1）：选中/移动/缩放/删除已有标注（Delete/⌫）；每工具独立颜色与粗细（色板 + 滚轮调粗细，记忆到设置）；Shift 约束（正方形/正圆/45° 箭头与直线）；新增圆角矩形（默认）、荧光笔、橡皮擦/删除；⇧1–⇧9 切工具（不得和 ⇧↩ 冲突）；默认值：颜色 `#D84A2F`，矩形圆角 8 线宽 5，箭头线宽 4，文字 17pt 白色描边；工具栏视觉打磨 | pi-xpc | 未开始 |
| R1-PIN | 贴图（批次 3）：关闭后可找回（本次运行内最近 N 张，菜单/快捷键恢复）、透明度（滚轮+⌥ 或菜单）、锁定位置、鼠标穿透（带可退出方式）、右键菜单（复制/保存/OCR/翻译/关闭）、⇧C 复制 OCR 文字；贴图阴影/边框视觉打磨 | pi-surfaces | 未开始 |
| R1-OCR | OCR 深度优化：Vision `.accurate` + 语言纠正 + 自动识别语言（含 zh-Hans/zh-Hant/en/ja/ko 可选）；按行/段落合并（中文不插空格、英文保留空格、保留列表与缩进、代码块尽量保持等宽换行）；小字图放大后识别；OCR 结果面板：可编辑、复制、翻译、带框选高亮对照；截图遮罩里一键 OCR 复制（快捷键，和 pi-xpc 协商接键只加一处调用）；测试用程序生成的图像（不得使用真实屏幕内容） | pi-surfaces | 未开始 |
| R1-AI | AI 深度优化：客户端兼容推理模型（`reasoning_content`、`content:null`、流式 delta 只含 reasoning 时显示“思考中”而非空白；足够的 max_tokens），超时/重试/取消、错误文案人话化；各操作提示词打磨（翻译自动判断中↔英、保留格式/代码/术语；总结、润色、解释）；截图 AI（翻译/总结/图片理解）走视觉模型，先 OCR 文字+图片一起给模型；设置里“测试连接”显示延迟与是否支持图片；确认默认 Provider 指向 Magpie `workbuddy/glm-5.3-flash` 且开箱可用；结果窗口流式体验与追问打磨 | pi-platform | 未开始 |
| R1-UI | 去掉首次引导：删除 Onboarding 窗口、代码、Gallery/Mock 中对应条目与 `onboardingCompleted` 的使用（字段可保留以兼容解码）；权限与输入法启用改为设置里的“权限”页 + 功能首次使用时就地提示（例如按 ⌃1 无屏幕录制权限时给出一个小提示并打开对应系统设置）。然后逐个打磨设置各页（通用/输入法/语音/截图/AI/快捷键/隐私/关于）：布局、间距、文案、空状态、错误状态、深浅色 | pi-ui | 未开始 |
| R1-IME | 输入法与语音打磨：译文栏 “Tab” 提示对比度；候选窗/译文栏/模式提示深浅色细节；语音 HUD 视觉与动画细节、错误文案；语音设置项对齐；检查打字路径无阻塞 | pi-ime | 未开始 |

### 第二轮（R2，R1 合并后派发）

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| R2-SHOT | 选区（批次 2）：放大镜 + 取色（显示 HEX，C 复制）、双击选区复制、按边微调（⌥/⌘+方向键调整边）、截图圆角输出、⌘S 另存为；遮罩性能与多屏复测 | pi-xpc | 未开始 |
| R2-AI | AI 第二轮：划词工具栏与结果窗口打磨、多 Provider 管理体验、请求取消与并发、隐私（Secure Input 时一律不发） | pi-platform | 未开始 |
| R2-OCR | OCR/预览第二轮：预览面板整体视觉、OCR 结果与翻译并排、批量/剪贴板图片 OCR | pi-surfaces | 未开始 |
| R2-UI | 菜单栏面板、结果窗口、划词工具栏等剩余界面视觉统一；设计系统 token 清理 | pi-ui | 未开始 |
| R2-ARCH | 架构整理：`App/Mock`、`App/Gallery` 移出正式 App 目标（或仅 DEBUG）；`App/Surfaces` 与 `App/Features` 职责划分（视图 vs 控制器）；死代码清理；`docs/architecture.md` 同步；不改行为 | pi-ime | 未开始 |

## 规则

- 每个任务开工前 `git merge main`；每个任务一个或多个小 commit；`scripts/test.sh`、`scripts/build.sh` 真实退出码 0 才算完成。
- 不安装、不注册输入法、不加载 LaunchAgent；不模拟全局按键；不记录用户内容。
- 需要真实交互的项标“待人工验证”。在本文件“验收证据”下追加自己的小节。

## 用户 PixPin 默认值

颜色 `#D84A2F`；矩形圆角 8、线宽 5；箭头线宽 4；文字 17pt 白色描边；截图输出圆角。

## 验收证据

（各窗口追加）
