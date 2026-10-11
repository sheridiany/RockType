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
| R1-AI | AI 深度优化：客户端兼容推理模型（`reasoning_content`、`content:null`、流式 delta 只含 reasoning 时显示“思考中”而非空白；足够的 max_tokens），超时/重试/取消、错误文案人话化；各操作提示词打磨（翻译自动判断中↔英、保留格式/代码/术语；总结、润色、解释）；截图 AI（翻译/总结/图片理解）走视觉模型，先 OCR 文字+图片一起给模型；设置里“测试连接”显示延迟与是否支持图片；确认默认 Provider 指向 Magpie `workbuddy/glm-5.3-flash` 且开箱可用；结果窗口流式体验与追问打磨 | pi-platform | 服务／接口与自动验证完成；待 pi-surfaces 入口集成及人工验收 |
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

### pi-platform · R1-AI（2026-10-11）

- 开工在 `agent/platform` 执行 `git merge main`，结果 Already up to date。未安装或注册输入法，未加载 LaunchAgent，未模拟全局按键，未启动主 App 二进制；未修改用户设置或钥匙串。
- **推理模型与请求生命周期**：Chat Completions 显式提供 `max_tokens = 8192`；默认整次请求预算 90 秒（含重试），调用者仍可指定更短预算。`reasoning_content` 只产生状态回调，不进入正文、对话或最近结果；`content: null`、空白正文、`finish_reason: length` 分别作为无正文／输出未完成处理。流式必须收到 `[DONE]`，中途断开不报成功。
- **重试与错误**：只对收到响应头后的 429／5xx 最多重试一次，默认等待 0.5 秒，遵守不超过 2 秒的数值 Retry-After；更长或日期格式留给用户稍后重试。认证失败、网络错误、部分正文与解码失败不自动重发。取消会停止当前网络任务与退避；结果窗口、连接测试和输入法 AI 路由映射新错误，错误信息不含供应商响应体。
- **结果窗口与追问**：新增“思考中”状态，空 delta 不误切换到生成中；支持选择正文。只有已有完整回答才开放追问，取消或失败的片段不加入上下文。真实冒烟发现翻译提示词会压过追问语言，现已明确让最后的追问决定回答语言和形式。
- **操作提示词**：翻译自动中↔英、保留格式／代码／术语，打磨总结、润色、解释的准确性和篇幅。通过 `OperationPrompts.resolved` 升级未编辑的内置提示词，用户自定义保持原样，恢复默认后使用新指令；输入法 AI 配置也使用同一解析器。遵守共享设置文件限制，未改 `Core/Settings/AppSettings.swift` 既有字段，也未迁移已存设置。
- **截图服务交接 pi-surfaces**：新增 `Core/Operations/ScreenshotAIService.swift`，`run(action: .translate/.summarize/.explain, png:, correctedText:, model:, imageCapabilityVerified:, apiKey:, onThinking:, onDelta:)`。调用前由预览负责展示待发送图片并获得确认、校验当前连接／模型／密钥的图片测试状态。`correctedText == nil` 先调用注入的本机 OCR；传入编辑后的字符串（包括空字符串）则以编辑值为准。OCR 与图片一起走视觉模型；限制 10 MiB 图片和 32 KiB OCR 文本，持续检查保护状态并支持取消。服务不保留图片或文字历史。现有 `ScreenshotSession` 默认图片理解闭包只做最小接线，使用生产 Vision OCR；翻译／总结的视觉入口、OCR 编辑值接线、发送预览与状态展示归 pi-surfaces 集成，本分支不改预览 UI。纯文本 OCR 翻译入口维持原行为。
- **连接测试与实际配置**：测试结果提供文字完整响应耗时，设置页文字结果显示秒数，图片能力继续单独显示。最小跨区改动仅 `ShellConnectionModel` 的结果文案／耗时、`ScreenshotSession` 的默认服务闭包。
- **真实冒烟通过**：使用现有设置中的 `http://127.0.0.1:3425/v1`、`workbuddy/glm-5.3-flash`，通过钥匙串服务和当前 account 在内存读取凭据。`ROARKT_LIVE_AI_SMOKE=1 swift test --filter localMagpieLiveSmoke` 退出码 0；文字／流式／图片／取消均可用，中译英、同会话追问译回中文、本机 Vision OCR + 程序生成图片理解均通过。最终一次文字探针 3.49 秒，整组约 28.67 秒。未输出响应正文、密钥或真实用户内容。测试进程无需 AX 权限，因为不读取来源内容；仍拒绝系统 Secure Input，生产路径的焦点／密码检查不变。
- **自动化覆盖**：新增 null／空白／仅推理帧、推理不泄漏、输出预算与截断、整次超时、重试次数／Retry-After／取消退避、部分流不重发、思考状态与取消、未完成结果禁止追问、截图 OCR 与图片并送／编辑值优先、未验证模型阻止发送、保护状态中途启用取消静默请求；既有自定义模板与输入法配置测试同步新提示词。夹具均为合成内容。真实端点测试默认跳过，仅显式环境变量启用。
- **验证过程说明**：首次真实流程因测试进程无法检查来源焦点而被保护拦截，调整为合成内容专用测试边界后继续；随后真实追问暴露语言优先级问题，修复后通过。首轮全量测试有一条旧提示词字面断言失败，已更新；最终最新代码的 `scripts/test.sh` 真实退出码 0（`/tmp/platform-r1-delivery-test.log`），`scripts/build.sh` 真实退出码 0（`/tmp/platform-r1-final-build.log`）；主 App、翻译服务、输入法与语音 helper 签名构建及脚本内鉴权冒烟通过。`git diff --check` 通过。
- **待人工验证／待集成**：截图翻译／总结视觉入口由 pi-surfaces 集成后验收；真实窗口中的流式滚动、长答案、取消／重试、中文输入追问、复制并返回、VoiceOver、浅深色和多屏仍需人工走查。已检查既有合成结果窗口离屏渲染，不能据此声称真实键盘或 UI 验收完成。Secure Input／密码框的真实应用交互待人工验证；自动保护测试通过不替代该项。
