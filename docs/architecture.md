# RockType 技术架构

需求见 [PRD](prd.md)，决策见 [ADR-0001](adr/0001-swift-merged-product.md)、[ADR-0002](adr/0002-identifiers-license-shortcuts.md)。本文按 2026-10-11 SPEC-014 R5-IME 的代码现状更新；内部模块及标识符仍使用 RoarkT。后续整理事项见[架构审计](architecture-audit-2026-10.md)，不能将规划接口视为已完成功能。

## 进程与请求路径

| 进程 | 产物与职责 | 通信 |
| --- | --- | --- |
| 输入法 | `RockType Input.app`；IMK、librime、按键、候选窗、译文栏、模式提示、ticket 填入 | 通过翻译 LaunchAgent 请求候选翻译、登记匿名语音端点；接收主 App 的填入 XPC |
| 主 App | `RockType.app`；菜单栏、设置、权限、划词、结果浮窗、截图/OCR、AI 配置、录音与语音会话 | 向翻译服务请求文字翻译/发现填入端点；向嵌入式语音 XPC 服务请求模型准备和识别；向输入法直接提交 ticket |
| 翻译服务 | `RoarkTTranslationService`；Apple Translation、请求代次/取消、显式输入法 AI 服务接口、填入端点登记与发现 | LaunchAgent Mach service；按调用方角色隔离接口 |
| 语音 worker | `RoarkTVoiceWorker.xpc`；独立 MLX/Qwen3-ASR 包，只处理模型与音频推理 | 系统按 `NSXPCConnection(serviceName:)` 激活；仅接受主 App 身份 |

输入法不申请隐私权限、不直接发网络请求，按键处理与候选刷新不得等待翻译/AI。主 App 为 `LSUIElement`，持有辅助功能、屏幕录制、麦克风权限与钥匙串入口。普通启动打开设置；后台启动按 `SettingsLaunchPolicy` 处理。输入源检查、语言包准备与权限入口位于设置页，没有独立首次引导流程。

当前翻译路由分三个位置实现：

- **候选翻译**：输入法本地精确缓存与技术词保护即时返回；其他请求只经输入法 80ms 防抖，服务收到后直接调用 macOS 26 Apple Translation。服务不可用时由输入法本地静态词条兜底。缓存为有界、短期、内存缓存；Secure Input 清空。
- **划词/截图文字翻译**：App 的 `DefaultOperationRunner` 经 `TextTranslationXPCClient` 先请求 Apple 离线翻译，不可用时按配置在 App 内调用 AI。结果与取消归当前操作会话。服务不是所有 AI/fallback 的统一执行位置。
- **输入法内显式 AI**：`InputAIController` 已接入 AppDelegate 的 start/stop。启用输入法 AI 后，默认 `⌥Tab` 循环改写/润色/翻译，对已确认前缀与当前高亮候选发送显式请求；AI 与普通翻译共享 session/generation，输入变化、Esc、失焦或保护状态作废，Tab 上屏。AI 不走普通翻译缓存/防抖，部分候选提交保留未转换后缀。自动化结果见 [R3-IME](../specs/evidence/014-R3-IME.md)，真实安装试打仍待人工验证。

操作模板的名称、提示词、模型、输出、图片入口和可选快捷键统一保存在设置中；工具栏顺序和启用状态沿用 selection 设置。HotkeyCenter 统一注册固定快捷键与动作快捷键，录制时暂停全部监听；文字动作走取词与操作 runner，图片动作先框选并经原预览确认。JSON 只交换动作定义，不包含连接或密钥，不执行脚本。

候选与选区的 Apple 翻译只共享 `AppleTranslationSession` 的原生 session 创建及返回文字适配；方向、语言检测、可用性检查、session 缓存、重试和错误映射仍归各自后端。长文翻译/总结在 App 的操作 runner 内分段：每任务最多两段并行，按序合并，只保留完整操作结果；不会把分段或网络等待带进按键路径。限制与验证见 [R3-AI](../specs/evidence/014-R3-AI.md)。

macOS 26 专属的无界面 `TranslationSession` 通过 availability 隔离；最低运行系统仍为 macOS 14。旧系统的候选静态词条、App AI 路径与本地 OCR 不依赖该 API。

## 源码模块与构建边界

| 目录 | target / 产物 | 许可证 | 当前职责 |
| --- | --- | --- | --- |
| `Shared/XPCProtocol` | `RoarkTXPCProtocol`，ObjC 头及模块 | MIT | 翻译、输入法 AI、ticket 填入协议与 ObjC 标识符；不包含 MLX worker 的 Swift 协议 |
| `Shared/VoiceWorkerProtocol` | Swift 协议源分组，由 App/独立 worker 编译同一源 | MIT | 唯一语音识别 wire 声明；只有 Foundation，不引入 MLX 或产品实现依赖 |
| `Core` | `RoarkTCore` | MIT | 标识符、设置/快捷键、翻译校验、操作会话与路由、AI 客户端、语音模型下载/校验等 Foundation 层能力 |
| `Platform` | `RoarkTPlatform` | MIT | AX 取词、剪贴板、Vision OCR、截图、钥匙串、权限、全局快捷键、Fn、屏幕坐标、Secure Input |
| `App` | `RoarkTApp` → `RockType.app` | MIT | `AppDelegate` 组装；`Shell` 外壳；`Features` 真实功能；`DesignSystem` 组件 |
| `App/Surfaces`、`App/Mock`、`App/Gallery` | `RoarkTApp`，开发代码以 `DEBUG` 隔离 | MIT | Mock/Gallery 与原型视图只在 debug 编译；Surfaces 的正式操作设置仍在 release；图片预览直接使用 Features 视图 |
| `Services/TranslationService` | 根包的 `RoarkTTranslationService` | MIT | 签名鉴权、方法角色限制、翻译/AI 协调、端点登记 |
| `Services/VoiceWorker` | 独立 SPM 包 → `RoarkTVoiceWorker.xpc` | MIT（第三方依各自许可） | MLX 推理；隔离模型依赖、内存与取消退出 |
| `InputMethod` | `Squirrel.xcodeproj` → `RockType Input.app` | GPL v3（子模块依各自许可） | Squirrel 修改及 librime/plum；不被 MIT 产品 target import 或链接 |
| `Rime` | 资源 | 按来源 | 方案、词典、Lua；个人词表与学习库在独立用户目录 |
| `Installer`、`scripts` | 构建、测试、pkg 与安装脚本 | MIT | 组装、签名、注册工具、LaunchAgent 配置；构建不等于安装 |

R4-UI 为 Mock/Gallery、依赖样本的原型视图和全部 Gallery 启动入口建立完整 `#if DEBUG` 边界。SPM 仍发现这些源文件，但 release 不编译其中的声明；`scripts/build.sh` 用 `nm` 检查正式 App 没有 Gallery/fixtures 符号。`scripts/render-gallery.sh` 显式构建 debug，开发测试可直接调用同一个 GalleryRenderer。

正式 `SettingsSection` 在 `App/Shell/SettingsSection.swift`；正式协调器直接创建 `ScreenshotPreviewContent`，没有 Surfaces 包装器；`ImagePreviewPrototype` 仅在 debug 使用。设计组件按职责命名于 `DesignPrimitives.swift`，短暂浮窗通知由 `TransientNoticeController` 管理。Features 已包含功能视图与控制器；跨功能无业务组件归 DesignSystem。

主 App/服务没有 InputMethod 源码或 librime 链接依赖。输入法 Xcode target 当前直接编译部分 MIT 源文件：Identifiers、Settings/Shortcuts、翻译值协议、VoiceCommitTicket/VoiceInsertionPolicy。此事实与 AGENTS“共享只能通过协议声明”的字面范围尚需主控对齐，见审计 A06；不授权把任何 GPL 实现搬到 MIT 目录。进程间请求仍只能用 XPC。

### 输入法内部职责（R4-IME）

输入法保留同一个 `@MainActor final SquirrelInputController` 对 session、generation、连接和计时器的所有权，按同一类型的 extension 分文件：

| 文件 | 职责 |
| --- | --- |
| `SquirrelInputController.swift` | IMK 入口、激活/失焦/销毁、设置、菜单、原始/标记文本提交；`handle` 保留原主线程断言后同步转调 |
| `SquirrelInputController+Events.swift` | NSEvent 顺序、修饰键映射、Shift/和弦处理、AI/Tab/Esc 分流及调用 Rime |
| `SquirrelInputController+Candidates.swift` | 候选/翻页/光标动作、Rime context 到展示、候选与 AI 快照、Rime 属性桥 |
| `SquirrelInputController+Translation.swift` | 翻译/AI 请求、回复校验、取消、状态展示及经过快照校验的上屏 |
| `SquirrelView.swift` | TextKit 视图及状态、绘制入口、点击命中、可访问性 |
| `SquirrelView+Geometry.swift` | 文本布局矩形、候选高亮路径、边框和分页几何 |

这次是文件级职责整理，不引入新状态机、队列或独立所有者；跨文件 extension 所需成员改为模块内可见，不暴露公共接口。生命周期调用顺序、按键分支、Rime C 内存的读取/释放时机及全部方法体保留。语音填入已经由 `RoarkTVoiceServer` 与 `VoiceCommitTicket` 承担；controller 的 `voiceClient` 组合输入/安全输入门禁继续留在生命周期入口，没有再次拆动。

### 语音内部边界

`VoiceInputController` 管理 Fn 会话、取消、保护检查与 HUD，依赖 `VoiceInterfaces` 中的本地接口。`VoiceEnvironment` 提供系统状态；`VoiceWorkerClient` 管理识别连接/准备；`VoiceCommitBridge` 管理端点发现和 ticket；`VoiceReply` 使成功、错误、超时、取消只完成一次。`VoiceModelStore` 管理下载状态，`VoiceModelVerification` 记录并复检已校验的文件身份。

主 App 只在按住 Fn 的录音阶段获取麦克风数据。模型预加载不录音。识别后可选 AI 润色，失败保留原文；填入前仍须核对来源、ticket、期限、Secure Input 和密码框。没有模拟粘贴或自动发送。

录音内存上限 180 秒（16 kHz 单声道 Float32，11.52 MB）；到限自动停止并识别。`VoiceAudioSegmentation` 是 Core 中的 MIT Foundation 策略，worker 通过源链接编译同一源文件：最多 28 秒一段，在上限前搜索静音，段间不重叠、不丢样；各段独立 token 预算，拼接不去重、不改已有标点。模型准备时用一秒合成静音预热首个解码步骤，不启用麦克风。

App 每 3 秒取新音频做一次预览，同一连接只允许一个预览在途，避免与最终识别并发。预览只进入 HUD 的独立字段；松键后同步停录，等待当前有界预览，然后完整重识别所有音频。RTF 超过 0.8 或预览失败会在本次运行内按模型停用预览；失败导致 worker 退出时，松键后恢复已校验模型。取消/安全输入/新会话丢弃迟到回复并清空预览。自动准备在受保护输入下不开始。

长录音使用固定 600 秒 ticket 租约（App 截止时间提前 10 秒），没有续租或重新绑定；原 120 秒默认票据语义保留。按键、激活/失焦、连接身份、选区、Secure Input 与单次消费检查不变。最慢路径超出租约时仍拒绝填入并提供结果复制。`VoiceLatency` 区分松键后的阶段耗时与录音期间的重采样总耗时，后者不能再次计入首字延迟；日志不包含文字、音频或上下文。

识别上下文来自单独打包的 MIT `VoiceVocabulary.dict.yaml` 与可选个人词表，最多 128 词/4096 UTF-8 字节，个人词上限 32；不扫描 userdb、文档或写持久上下文缓存。音频与词表上下文只经本地 worker XPC。模型下载、上下文和合成语音评测细节见 [VoiceWorker README](../Services/VoiceWorker/README.md)。

## XPC 协议位置与鉴权

翻译/填入 wire 契约位于 `Shared/XPCProtocol/include/`。语音识别契约唯一实体为 `Shared/VoiceWorkerProtocol/VoiceWorkerProtocol.swift`；App 与独立 worker 的同名源路径均为指向它的符号链接，签名烟测直接编译 Shared 源。保留原 `@objc(RoarkTVoiceWorkerProtocol)` 及 `prepareWithDirectory:reply:`、`transcribeWithAudio:context:reply:`、`shutdown` selectors，不增加两端运行时/包依赖。worker 的 Identifiers 仍链接到 Core 的单一 Swift 源。

客户端绑定服务的签名 requirement；服务按 Team ID 与具体 identifier 鉴别客户端，并实施方法级角色限制。格式为 `anchor apple generic and certificate leaf[subject.OU] = "DF7J2VBQD8" and identifier "<允许的 identifier>"`，Swift 使用 `Identifiers.codeRequirement(for:)`。不能只检查 Team ID，不能将用于查找/退出同产品进程的 `RoarkTProcessTrust` 当成 XPC 授权策略。

| 接口 | 允许调用方 |
| --- | --- |
| `translateCandidate` / `rewriteCandidate` / `cancel` | 输入法 → 翻译服务；rewrite 仅显式触发 |
| `translateText` / `cancelText` / `configureAI` / `ping` | 主 App → 翻译服务 |
| `recordControllerInput` / `controllerInputGeneration` | 输入法写计数 / 主 App 读计数；不传试打原文 |
| `registerDictationEndpoint` / `dictationEndpoint` | 输入法登记匿名 listener endpoint / 主 App 发现 |
| 语音填入 `capture` / `commit` / `cancel` | 主 App → 输入法匿名 endpoint；不经过翻译服务转发文本 |
| worker `prepare` / `transcribe` / `shutdown` | 主 App → 嵌入式语音 XPC 服务 |

`dictationEndpointName` 是规定的端点标识；当前发现机制是翻译服务保存的 `NSXPCListenerEndpoint`，不是额外安装一个同名 LaunchAgent。迟到回复必须通过 session/generation 或 ticket 验证，断线取消不得影响新会话。

## 标识符

Swift 唯一来源为 `Core/Identifiers.swift`；ObjC 镜像为 `Shared/XPCProtocol/include/RoarkTIdentifiers.h`，自动测试核对二者。

| 用途 | 值 |
| --- | --- |
| Team ID | `DF7J2VBQD8` |
| 主 App | `com.roarkist.roarkt` |
| 输入法 Bundle | `com.roarkist.inputmethod.RoarkT` |
| 输入源：全拼 | `com.roarkist.inputmethod.RoarkT.pinyin` |
| 输入源：小鹤双拼 | `com.roarkist.inputmethod.RoarkT.flypy` |
| 翻译服务（Mach service / LaunchAgent label） | `com.roarkist.roarkt.translation` |
| 语音 worker | `com.roarkist.roarkt.voice` |
| 输入法语音填入端点标识 | `com.roarkist.inputmethod.RoarkT.dictation` |
| 设置目录 | `~/Library/Application Support/RoarkT/` |
| 可选截图历史 | `~/Library/Application Support/RockType/ScreenshotHistory/`，由 `Identifiers.screenshotHistoryDirectory(home:)` 生成；默认关闭 |
| 钥匙串服务名 | `com.roarkist.roarkt.ai` |
| Rime 方案 ID | `roarkt`（全拼）、`roarkt_flypy`、`roarkt_en` |
| Rime 用户目录 | `~/Library/Application Support/RoarkT/Rime`，由 `Identifiers.rimeUserDirectory(home:)` 生成 |

## 安装位置（发布）

| 产物 | 位置 |
| --- | --- |
| 主 App | `/Applications/RockType.app` |
| 输入法 | `/Library/Input Methods/RockType Input.app` |
| 翻译服务 | `RockType.app/Contents/Helpers/RoarkTTranslationService` |
| 翻译 LaunchAgent | `/Library/LaunchAgents/com.roarkist.roarkt.translation.plist`；按各 GUI 用户会话运行 |
| 语音 worker | `RockType.app/Contents/Helpers/RoarkTVoiceWorker.xpc`；`Contents/XPCServices/` 下有发现用链接 |

开发安装脚本使用 `~/Library/Input Methods/` 与 `~/Library/LaunchAgents/`，这是开发路径，不是发布安装路径。各 worktree 只构建和测试，不从这里安装、注册输入法或加载 LaunchAgent；真实安装验证由主控在 main 执行。

## 默认快捷键

| 动作 | 默认 |
| --- | --- |
| 语音：按住说话 | `Fn` |
| 截图 | `⌃1` |
| 翻译选区 | `⌃⌥T` |
| 总结选区 | `⌃⌥S` |
| 截图历史 | `⌃⌥H` |
| 隐藏／显示全部贴图 | `⌃⌥P` |
| 关闭全部贴图 | `⌃⌥X` |
| 下一张贴图 | `⌃⌥N` |
| 中英切换 | 轻按 Shift（输入法内） |
| 译文上屏 | Tab（输入法内） |
| 输入法内 AI | `⌥Tab` 循环改写 → 润色 → 翻译；需在设置中启用，可改键 |

## 构建、测试与发布

- 根 SPM 构建 Core、Platform、Shared 协议、App、TranslationService 及测试；InputMethod 使用 Xcode 工程，VoiceWorker 使用独立锁定依赖的 SPM 包。
- `scripts/build.sh` 构建并签名主 App、翻译服务、输入法、注册工具、MLX worker 到本 worktree 的 `dist/`，打包独立语音词表，并运行 worker MLX/self-test 与签名 XPC 烟测。不会安装输入法或加载 LaunchAgent。
- `scripts/test.sh` 是全量入口；Swift tests 内的包装测试会调用对应 IME/词库检查脚本，另有 Rime、快捷键与权限检查。测试源码统一位于 `Tests/`。
- `scripts/build-installer.sh` 另行组装签名 pkg；公证、源码材料、更新签名与真实安装/更新验收仍有独立门槛。GPL 对应源码交付见 `LICENSES/GPL-SOURCE.md`。
- 构建通过、离屏渲染与模拟服务测试不等于真实键盘、麦克风、权限、跨应用和性能验收通过；各规格单独记录未覆盖项。
