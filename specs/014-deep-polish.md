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
| R1-PIN | 贴图（批次 3）：关闭后可找回（本次运行内最近 N 张，菜单/快捷键恢复）、透明度（滚轮+⌥ 或菜单）、锁定位置、鼠标穿透（带可退出方式）、右键菜单（复制/保存/OCR/翻译/关闭）、⇧C 复制 OCR 文字；贴图阴影/边框视觉打磨 | pi-surfaces | 已实现，测试/构建通过；待人工验收 |
| R1-OCR | OCR 深度优化：Vision `.accurate` + 语言纠正 + 自动识别语言（含 zh-Hans/zh-Hant/en/ja/ko 可选）；按行/段落合并（中文不插空格、英文保留空格、保留列表与缩进、代码块尽量保持等宽换行）；小字图放大后识别；OCR 结果面板：可编辑、复制、翻译、带框选高亮对照；截图遮罩里一键 OCR 复制（快捷键，和 pi-xpc 协商接键只加一处调用）；测试用程序生成的图像（不得使用真实屏幕内容） | pi-surfaces | 已实现，测试/构建通过；待人工验收 |
| R1-AI | AI 深度优化：客户端兼容推理模型（`reasoning_content`、`content:null`、流式 delta 只含 reasoning 时显示“思考中”而非空白；足够的 max_tokens），超时/重试/取消、错误文案人话化；各操作提示词打磨（翻译自动判断中↔英、保留格式/代码/术语；总结、润色、解释）；截图 AI（翻译/总结/图片理解）走视觉模型，先 OCR 文字+图片一起给模型；设置里“测试连接”显示延迟与是否支持图片；确认默认 Provider 指向 Magpie `workbuddy/glm-5.3-flash` 且开箱可用；结果窗口流式体验与追问打磨 | pi-platform | 未开始 |
| R1-UI | 去掉首次引导：删除 Onboarding 窗口、代码、Gallery/Mock 中对应条目与 `onboardingCompleted` 的使用（字段可保留以兼容解码）；权限与输入法启用改为设置里的“权限”页 + 功能首次使用时就地提示（例如按 ⌃1 无屏幕录制权限时给出一个小提示并打开对应系统设置）。然后逐个打磨设置各页（通用/输入法/语音/截图/AI/快捷键/隐私/关于）：布局、间距、文案、空状态、错误状态、深浅色 | pi-ui | 未开始 |
| R1-IME | 输入法与语音打磨：译文栏 “Tab” 提示对比度；候选窗/译文栏/模式提示深浅色细节；语音 HUD 视觉与动画细节、错误文案；语音设置项对齐；检查打字路径无阻塞 | pi-ime | 代码与自动验证完成；待人工交互验收 |
| R1b-IME | 词库第二轮：开发类首选 30/40 与整句 18/20 偏弱，分析 `scripts/eval-candidates.sh` 的未命中项，扩充/校准 `Rime/roarkt_ai`（开发、产品、协作术语）与权重；冻结评测集不改；日常不得下降；不改个人词表/学习库 | pi-ime | 未开始 |

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


### R1-IME · pi-ime · 2026-10-11

状态：代码与自动验证完成；真实交互与最终设计验收待人工验证。开工前在 `agent/ime` 执行 `git merge main`，结果 Already up to date；未 push、未安装或注册输入法、未加载 LaunchAgent、未模拟全局按键。

| Before | After | 原因 |
| --- | --- | --- |
| Tab 复用候选编号颜色与候选高亮背景 | 独立语义键帽、11pt medium、细边框；浅深色文字对比度均 ≥ 4.5:1 | 避免主题颜色组合使快捷键提示难辨认 |
| 浅色候选编号/注释较淡，高亮蓝底较亮 | 加深浅色辅助文字及两主题高亮蓝底；译文加载态不再额外降低透明度 | 提升小字、白色高亮候选的可读性 |
| 中英模式提示固定配色 | 中文标记跟随浅深色；英文标记加深橙色，保留模式区分 | 暗色环境不刺眼，英文白字更清楚 |
| HUD 固定深色、重复状态清空波形及展开状态 | 系统语义背景/文字/边框；重复状态保持音量和展开状态，关闭释放显示层结果 | 匹配主题、减少跳动与内容保留 |
| 失败 HUD 标题统一“语音输入” | 标题呈现当前原因，详情可展开；区分无有效声音、超时及其他识别失败 | 用户能找到具体恢复方向 |
| 语音开关与说明逐行堆叠 | 三个开关统一右对齐，标题和说明成组，保留 AI 未配置禁用与说明 | 长说明不挤压开关，便于扫读 |

实现提交：`a26a981`（输入法主题）、`0b32278`（HUD/错误状态）、`6334976`（语音设置）、`e486bd3`（验证宿主）。GPL 改动仅位于 `InputMethod/`；面板测试沿用 `Tests/InputMethodTests/PanelChecks.swift` 的 GPL 独立可执行测试路径，没有复制或链接进 MIT App。

**验证通过**：

- `scripts/test.sh` 最终真实退出码 **0**；60 项 XCTest、176 项 Swift Testing 通过，另含 Rime 部署/能力、AppShell 与旧标识扫描。完整日志 `.build/r1-ime-final-test.log`，退出码 `.build/r1-ime-final-test.exit`。
- `scripts/build.sh` 最终真实退出码 **0**；主 App、输入法与语音 worker 构建、签名验证和 XPC 冒烟通过。完整日志 `.build/r1-ime-final-build.log`，退出码 `.build/r1-ime-final-build.exit`。
- 新增检查：生产译文栏双主题 Tab 对比度与无障碍标签；重复 HUD 状态保留展开/真实音量，状态切换清空音量，关闭不保留结果文字；空识别/超时/worker 不可用对应不同恢复文案且不填入。沿用现有时钟像素对齐、迟到结果、Secure Input、候选刷新和屏幕边界检查。
- 离屏图来自生产视图和合成文字，已人工读取检查：`.build/ime-evidence/{candidate,translation-ready,mode-chinese,mode-english}-{light,dark}.png`，以及 `voice-{recording,processing,notice,result,done}-{light,dark}.png`。无真实屏幕或用户内容。最终交互设计验收仍须使用安装版。
- 打字路径代码检查：`SquirrelInputController` 候选刷新使用 150ms 延迟加载提示；`RoarkTTranslationClient.translate` 使用 `remoteObjectProxyWithErrorHandler` 异步请求与 4s `asyncAfter` 超时，无信号量等待、同步 XPC 或网络等待。会话 token/generation、迟到丢弃、缓存与安全输入测试通过；本次未改请求调度。
- 动效取舍：候选窗、模式提示与语音快捷键入口保持即时显示；波形仅绘制真实采样，不添加循环装饰、弹跳或进出场动画。
- 不再将语音错误对象描述写入日志，仅保留操作失败类别，避免底层错误携带内容。

**验证入口的最小跨区调整**：`Tests/VoiceWorkerSmoke` 原先从 shell 直接执行测试 App 二进制，与本次约束冲突；改为 `open -n -g -W` 通过 LaunchServices 启动，以临时状态文件回传并检查测试真实结果（不把 open 成功当测试通过）。首次构建在此处失败 `-10825`，定位为测试宿主缺少显式部署版本，已补 `-target arm64-apple-macos14.0`。独立复测及最终完整构建通过；合法签名连接成功、错误身份被拒绝。没有启动正式 App 或输入法二进制。

**待人工验证**：安装版在浅/深色及增强对比度下的最终视觉；多显示器/全屏/光标边缘；连续快速打字和翻译服务不可用时的 P95 延迟；真实 Fn 按住/松开、Esc、麦克风授权/撤销、无声音/长录音、跨应用安全填入；VoiceOver 对键帽、语音开关与 HUD 的朗读；语音设置长文案布局。未以构建成功代替这些功能验收。分支与当前 worktree 保留，等待合并及人工验收；R2-ARCH 尚未启动。

### pi-surfaces · R1-OCR（2026-10-11）

- 开工前已 `git merge main`（Already up to date）。沿用 `agent/surfaces` 工作树分支。
- Vision accurate + 语言纠正 + 自动检测；初始语言读取截图设置，预览可临时选择简/繁/英/日/韩。小图最长边小于 2400px 时放大 2 倍，额外像素开销有界。
- 保留文字框，按阅读行排序；默认逐行保留列表、段落间隔和估算缩进。可选合并正文段落，中文相邻行不添空格，英文保留空格。复杂多栏/代码识别仍是启发式，默认逐行更稳妥。
- 结果使用可编辑等宽文本，原图文字框可点击高亮并对照原始行；翻译/总结继续读取编辑后的文字。遮罩 ⇧C 仅增加输出回调与 coordinator 调用，打开结果并本机识别复制，失败可原地重试。
- 新增测试：程序绘制 12px 英文小字真实 Vision 识别、语言参数、中文/英文合并、列表/缩进/段落、会话关闭清除文字框；原有取消/安全输入测试保留。
- 验证：`scripts/test.sh` 最终退出码 0（`/tmp/surfaces-r1-ocr-final-test.log`）；`scripts/build.sh` 退出码 0（`/tmp/surfaces-r1-ocr-build.log`），完整产物构建签名与脚本既有语音 XPC 测试通过。未安装/注册输入法、未加载 LaunchAgent、未启动主 App；⇧C 测试仅直接调用画布事件方法，不投递全局按键。
- 待人工验证：简繁/日/韩实际识别质量、多栏/代码复杂排版、浅深色文字框对照、真实遮罩 ⇧C、编辑后翻译、Secure Input 中途启用；不把自动构建当作 UI 验收。

### pi-surfaces · R1-PIN（2026-10-11）

- R1-OCR 提交后再次 `git merge main`（Already up to date），继续在 `agent/surfaces`。
- 关闭的贴图在内存保留最近 10 张，累计像素内存最多 64 MB，超大单图不进入记录；菜单栏“贴图”可逐张恢复最近关闭，贴图内或该菜单里支持 ⌘⇧Z。不注册新的全局快捷键，最后一张关闭后仍能通过菜单恢复。
- ⌥滚轮或右键菜单调节 20%–100% 透明度；锁定同时禁止拖动和缩放。恢复时保留位置、大小、透明度与锁定，始终退出穿透。右键可启用鼠标穿透，独立菜单栏入口可一次退出全部穿透。
- 右键复制图片、另存为、OCR、翻译、关闭；⇧C 识别并复制文字。保存/OCR 复用既有预览会话；翻译先打开识别结果供核对，用户点击翻译后才发送编辑后的文本。图片原始像素不随显示缩放/透明度改变。
- 轻圆角、细边框、原生阴影，锁定使用强调色边框；复制/锁定/透明度提供短暂文字反馈。跨区仅 coordinator 的动作接线和 AppDelegate“清除当前内容”一行。
- 隐私：Secure Input 中途启用会关闭全部贴图并清除最近记录；全局清除内容与退出也清空。未加入内容日志或持久化。
- 新增自动化覆盖数量/字节淘汰、关闭恢复状态、恢复强制退出穿透、菜单退出穿透、保护状态清空、⇧C 不走图片复制、锁定阻止缩放、右键动作与透明度。仅程序生成图像，测试窗口不展示、不抢焦点、不投递全局事件。
- 验证：`scripts/test.sh` 退出码 0（69 XCTest + 173 Swift Testing，及 Rime/权限/快捷键/标识检查；`/tmp/surfaces-r1-pin-test.log`）；`scripts/build.sh` 最终退出码 0（`/tmp/surfaces-r1-pin-build-final.log`），全部产物构建签名、既有 worker 自检和 XPC 鉴权通过。未安装、注册输入法、加载 LaunchAgent 或启动主 App。
- 构建限制：本轮第一次增量构建退出 65，`package-rime.sh` 无法覆盖前次生成的只读 `Resources/Licenses/Voice/*` 副本。仅对本 worktree `.build/ime/Build/Products/Release/RockType Input.app/Contents/Resources/Licenses` 执行 `chmod -R u+w` 后完整重跑通过；未越区修改输入法打包脚本。失败日志 `/tmp/surfaces-r1-pin-build.log`，后续重复增量构建仍可能需要输入法负责人修复打包脚本。
- 待人工验证：多屏移动/恢复、真实滚轮/手势、最后一张穿透后的菜单退出、菜单栏拥挤时入口可达性、浅深色阴影/边框、真实保存与剪贴板、OCR/翻译交互、VoiceOver。新增独立“贴图”菜单是为了减少 pi-ui 区域改动，后续可由外壳统一入口。
