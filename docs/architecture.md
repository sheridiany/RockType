# RockType 技术架构

需求见 [PRD](prd.md)，决策见 [ADR-0001](adr/0001-swift-merged-product.md)、[ADR-0002](adr/0002-identifiers-license-shortcuts.md)。本文按 2026-10-11 SPEC-014 R2-ARCH 第一阶段的代码现状更新；内部模块及标识符仍使用 RoarkT。后续整理事项见[架构审计](architecture-audit-2026-10.md)，不能将规划接口视为已完成功能。

## 进程与请求路径

| 进程 | 产物与职责 | 通信 |
| --- | --- | --- |
| 输入法 | `RockType Input.app`；IMK、librime、按键、候选窗、译文栏、模式提示、ticket 填入 | 通过翻译 LaunchAgent 请求候选翻译、登记匿名语音端点；接收主 App 的填入 XPC |
| 主 App | `RockType.app`；菜单栏、设置、权限、划词、结果浮窗、截图/OCR、AI 配置、录音与语音会话 | 向翻译服务请求文字翻译/发现填入端点；向嵌入式语音 XPC 服务请求模型准备和识别；向输入法直接提交 ticket |
| 翻译服务 | `RoarkTTranslationService`；Apple Translation、请求代次/取消、显式输入法 AI 服务接口、填入端点登记与发现 | LaunchAgent Mach service；按调用方角色隔离接口 |
| 语音 worker | `RoarkTVoiceWorker.xpc`；独立 MLX/Qwen3-ASR 包，只处理模型与音频推理 | 系统按 `NSXPCConnection(serviceName:)` 激活；仅接受主 App 身份 |

输入法不申请隐私权限、不直接发网络请求，按键处理与候选刷新不得等待翻译/AI。主 App 为 `LSUIElement`，持有辅助功能、屏幕录制、麦克风权限与钥匙串入口。普通启动打开设置；后台启动按 `SettingsLaunchPolicy` 处理。输入源检查、语言包准备与权限入口位于设置页，没有独立首次引导流程。

当前翻译路由分三个位置实现：

- **候选翻译**：输入法本地精确缓存与技术词保护即时返回；其他请求经输入法 80ms 防抖和服务 120ms 防抖，再调用 macOS 26 Apple Translation。服务不可用时由输入法本地静态词条兜底。缓存为有界、短期、内存缓存；Secure Input 清空。
- **划词/截图文字翻译**：App 的 `DefaultOperationRunner` 经 `TextTranslationXPCClient` 先请求 Apple 离线翻译，不可用时按配置在 App 内调用 AI。结果与取消归当前操作会话。服务不是所有 AI/fallback 的统一执行位置。
- **输入法内显式 AI**：Shared 协议与服务的配置/改写接口已实现；`InputAIController` 生命周期尚未接入 AppDelegate，IMK 触发和上屏 E-3 未完成。状态见 [SPEC-008](../specs/008-m6-input-ai.md)，不能宣称端到端可用。

macOS 26 专属的无界面 `TranslationSession` 通过 availability 隔离；最低运行系统仍为 macOS 14。旧系统的候选静态词条、App AI 路径与本地 OCR 不依赖该 API。

## 源码模块与构建边界

| 目录 | target / 产物 | 许可证 | 当前职责 |
| --- | --- | --- | --- |
| `Shared/XPCProtocol` | `RoarkTXPCProtocol`，ObjC 头及模块 | MIT | 翻译、输入法 AI、ticket 填入协议与 ObjC 标识符；不包含 MLX worker 的 Swift 协议 |
| `Core` | `RoarkTCore` | MIT | 标识符、设置/快捷键、翻译校验、操作会话与路由、AI 客户端、语音模型下载/校验等 Foundation 层能力 |
| `Platform` | `RoarkTPlatform` | MIT | AX 取词、剪贴板、Vision OCR、截图、钥匙串、权限、全局快捷键、Fn、屏幕坐标、Secure Input |
| `App` | `RoarkTApp` → `RockType.app` | MIT | `AppDelegate` 组装；`Shell` 外壳；`Features` 真实功能；`DesignSystem` 组件 |
| `App/Surfaces`、`App/Mock`、`App/Gallery` | 目前仍属于 `RoarkTApp` | MIT | 原型、样本、Gallery；Surfaces 中仍有正式预览包装依赖，Mock 中仍有正式设置导航类型，不能直接排除目录 |
| `Services/TranslationService` | 根包的 `RoarkTTranslationService` | MIT | 签名鉴权、方法角色限制、翻译/AI 协调、端点登记 |
| `Services/VoiceWorker` | 独立 SPM 包 → `RoarkTVoiceWorker.xpc` | MIT（第三方依各自许可） | MLX 推理；隔离模型依赖、内存与取消退出 |
| `InputMethod` | `Squirrel.xcodeproj` → `RockType Input.app` | GPL v3（子模块依各自许可） | Squirrel 修改及 librime/plum；不被 MIT 产品 target import 或链接 |
| `Rime` | 资源 | 按来源 | 方案、词典、Lua；个人词表与学习库在独立用户目录 |
| `Installer`、`scripts` | 构建、测试、pkg 与安装脚本 | MIT | 组装、签名、注册工具、LaunchAgent 配置；构建不等于安装 |

根 App target 目前只排除 `Info.plist`，release 仍编入 Mock/Gallery，命令行 Gallery 入口也未受 DEBUG 限制。这是 R2-ARCH 后续阶段的明确待办，见审计 A02–A04。Features 已包含功能视图与控制器；后续按真实功能收拢，跨功能无业务组件归 DesignSystem，Gallery 原型跟随其目标。

主 App/服务没有 InputMethod 源码或 librime 链接依赖。输入法 Xcode target 当前直接编译部分 MIT 源文件：Identifiers、Settings/Shortcuts、翻译值协议、VoiceCommitTicket/VoiceInsertionPolicy。此事实与 AGENTS“共享只能通过协议声明”的字面范围尚需主控对齐，见审计 A06；不授权把任何 GPL 实现搬到 MIT 目录。进程间请求仍只能用 XPC。

### 语音内部边界

`VoiceInputController` 管理 Fn 会话、取消、保护检查与 HUD，依赖 `VoiceInterfaces` 中的本地接口。`VoiceEnvironment` 提供系统状态；`VoiceWorkerClient` 管理识别连接/准备；`VoiceCommitBridge` 管理端点发现和 ticket；`VoiceReply` 使成功、错误、超时、取消只完成一次。`VoiceModelStore` 管理下载状态，`VoiceModelVerification` 记录并复检已校验的文件身份。

主 App 只在按住 Fn 的录音阶段获取麦克风数据。模型预加载不录音。识别后可选 AI 润色，失败保留原文；填入前仍须核对来源、ticket、期限、Secure Input 和密码框。没有模拟粘贴或自动发送。

识别上下文来自单独打包的 MIT `VoiceVocabulary.dict.yaml` 与可选个人词表，最多 128 词/4096 UTF-8 字节，个人词上限 32；不扫描 userdb、文档或写持久上下文缓存。音频与词表上下文只经本地 worker XPC。模型下载、上下文和合成语音评测细节见 [VoiceWorker README](../Services/VoiceWorker/README.md)。

## XPC 协议位置与鉴权

翻译/填入 wire 契约位于 `Shared/XPCProtocol/include/`。worker 的 `VoiceWorkerProtocol.swift` 位于独立服务包，`App/Features/Voice/VoiceWorkerProtocol.swift` 通过符号链接引用同一源文件，签名烟测也编译该路径；不存在另一份复制定义。worker 的 Identifiers 同样链接到 Core 的单一 Swift 源。

客户端绑定服务的签名 requirement；服务按 Team ID 与具体 identifier 鉴别客户端，并实施方法级角色限制。格式为 `anchor apple generic and certificate leaf[subject.OU] = "DF7J2VBQD8" and identifier "<允许的 identifier>"`，Swift 使用 `Identifiers.codeRequirement(for:)`。不能只检查 Team ID，不能将用于查找/退出同产品进程的 `RoarkTProcessTrust` 当成 XPC 授权策略。

| 接口 | 允许调用方 |
| --- | --- |
| `translateCandidate` / `rewriteCandidate` / `cancel` | 输入法 → 翻译服务；rewrite 的 IMK 入口尚待接线 |
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
| 中英切换 | 轻按 Shift（输入法内） |
| 译文上屏 | Tab（输入法内） |
| 输入法内 AI | 设置/规格默认 `⌥Tab`；IMK 触发实现尚未完成 |

## 构建、测试与发布

- 根 SPM 构建 Core、Platform、Shared 协议、App、TranslationService 及测试；InputMethod 使用 Xcode 工程，VoiceWorker 使用独立锁定依赖的 SPM 包。
- `scripts/build.sh` 构建并签名主 App、翻译服务、输入法、注册工具、MLX worker 到本 worktree 的 `dist/`，打包独立语音词表，并运行 worker MLX/self-test 与签名 XPC 烟测。不会安装输入法或加载 LaunchAgent。
- `scripts/test.sh` 是全量入口；Swift tests 内的包装测试会调用对应 IME/词库检查脚本，另有 Rime、快捷键与权限检查。测试源码统一位于 `Tests/`。
- `scripts/build-installer.sh` 另行组装签名 pkg；公证、源码材料、更新签名与真实安装/更新验收仍有独立门槛。GPL 对应源码交付见 `LICENSES/GPL-SOURCE.md`。
- 构建通过、离屏渲染与模拟服务测试不等于真实键盘、麦克风、权限、跨应用和性能验收通过；各规格单独记录未覆盖项。
