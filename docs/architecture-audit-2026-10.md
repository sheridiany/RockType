# 2026-10 架构审计（SPEC-014 R2-ARCH 第一阶段）

日期：2026-10-11。审计基线：`17c42417b83d0465c60c1cb6fbbee0806e10c7a2`，`agent/ime` 已执行 `git merge main`。覆盖 App、Core、Platform、Shared、两个 Services、InputMethod、Rime、构建/测试/安装脚本及许可证材料。其他窗口正在修改的 Screenshot、AI、ResultWindow、Settings、DesignSystem 仅只读检查；下述结果不代表它们后续合并后的状态。

本阶段交付审计及 pi-ime 区域内的等价整理。**Gallery/Mock 尚未从正式目标移出**：它们与正式设置、图片预览存在依赖，需由所属窗口先处理，不能直接排除目录。构建与单元测试也不能代替真实 IMK、权限、麦克风、多显示器和发布验收。

## 当前模块边界

| 边界 | 已核实的现状 | 后续边界建议 |
| --- | --- | --- |
| App 组装 | `AppDelegate` 创建并连接各功能；`Shell` 持有设置、权限、快捷键和菜单；App 单一 executable target 包含所有子目录 | 保留一个组装入口；功能对外提供生命周期与少量动作，不让组装层管理内部任务 |
| Features / Surfaces | Features 已同时包含真实视图、会话与系统适配器；Surfaces 混合 Gallery 原型及真实图片预览复用的视图 | 真实功能的视图与控制器放对应 Features；只把跨功能、无业务依赖的组件放 DesignSystem；Gallery 原型跟随 Gallery。不要机械按“所有视图/所有控制器”切两层 |
| Core / Platform | Core 含值模型、策略及 AI/下载等 Foundation 服务；Platform 包装 AppKit/AX/Vision/Carbon/Keychain | Core 不是纯数据层，文档应明确；系统能力留 Platform，功能会话留 App |
| 进程通信 | 翻译与填入协议在 Shared；语音 worker 协议在独立包，通过符号链接给 App/烟测编译 | 保留进程隔离；统一协议位置是后续目录整理，不复制两份协议，不引入通用 RPC 框架 |
| 输入法 / MIT | 主 App 与服务无 InputMethod target 依赖；输入法会编译若干 MIT Core 源文件，独立链接 librime | 禁止 GPL 代码反向进入 MIT 产物；跨进程只用 XPC；共享源码现状与仓库约定的文字差异需单独对齐 |
| 资源 / 分发 | Rime 分来源许可；VoiceVocabulary 从 MIT 工厂词典单独打入主 App；输入法另行打包；Installer 组装签名 pkg | 不从 GPL bundle 反向取资源给主 App；源码发布材料与二进制版本一一对应 |

## 按优先级的问题清单

P0 是正式发布前门槛，P1 是后续结构整理优先项，P2 是可独立安排的维护项，P3 是命名/文档清理。负责窗口为建议归属，涉及多个窗口时由 Claude 在 main 协调；不是本次授权越区修改。

| ID / 优先级 | 问题 | 影响 | 建议 | 涉及文件 | 负责窗口 / 状态 |
| --- | --- | --- | --- | --- | --- |
| A01 / P0 发布前 | GPL 对应源码的正式交付尚未闭环；现有说明仍称仓库地址未确定、开发包不是正式发行 | 签名构建成功不能证明 NFR-9 已满足 | 按 `GPL-SOURCE.md` 在同一 release 提供对应源码、依赖版本、补丁与可复现说明，再验正式发行；不在此阶段发布 | `LICENSES/GPL-SOURCE.md`、`THIRD_PARTY_NOTICES.md`、`Installer/README.md`、`scripts/build-installer.sh` | Claude / 分发负责人；既有发布门槛 |
| A02 / P1 | Gallery 和 Mock 全量进入 release，`--gallery` 与 `--render-gallery` 入口没有 DEBUG 限制 | 正式二进制携带原型样本与开发入口，产品边界不清 | 先解开 A03/A04 的生产依赖，再建立独立 Gallery target 或完整 DEBUG 编译边界；release 检查源码清单、符号和入口 | `Package.swift`、`App/main.swift`、`App/AppDelegate.swift`、`App/Gallery/*`、`App/Mock/*`、`scripts/render-gallery.sh` | pi-ui + Claude；未修改 |
| A03 / P1 | 正式设置导航的 `SettingsSection` 定义在 Mock 的 `SettingsFixtures.swift` | 整目录 exclude Mock 会直接破坏正式设置编译；数据样本与产品类型绑在一起 | 把正式导航类型移到 Settings；样本只留 Gallery，保持 case/标签/顺序不变 | `App/Mock/SettingsFixtures.swift`、`App/Shell/ShellSettingsView.swift`、`App/Shell/SettingsWindowController.swift`、`App/Shell/ShellSettingsSections.swift` | pi-ui；未修改 |
| A04 / P1 | 正式截图预览复用 Surfaces 的 `ImagePreviewView`，`init(session:)` 会先以 Mock 的 `.samples[0]` 初始化，再转到真实 `ScreenshotPreviewContent` | Surfaces 不全是废弃原型，不能为隔离 Gallery 直接删除或整目录排除 | 让真实 coordinator 直接创建 `ScreenshotPreviewContent`，取消经过 prototype 包装器；fixtures/samples 留 Gallery。与预览窗口当前重构一起落地 | `App/Features/Screenshot/ScreenshotCoordinator.swift`、`App/Features/Screenshot/ScreenshotPreviewContent.swift`、`App/Surfaces/ImagePreviewView.swift`、`App/Mock/ImagePreviewModel.swift` | pi-surfaces + pi-screenshot；与 pi-ui 协调，未修改 |
| A05 / P1 | `InputAIController` 有测试及配置下发实现，但 AppDelegate 没有实例化；输入法 E-3 也未接线 | 不能因协议和单测存在就宣称 FR-E3 已端到端完成；这是未完成能力，不是可删死代码 | 沿 SPEC-008 分别完成生命周期、输入法触发/作废/上屏及真实验收；本次仅纠正文档 | `App/Features/InputAI/*`、`App/AppDelegate.swift`、`InputMethod/sources/SquirrelInputController.swift`、`specs/008-m6-input-ai.md` | Claude + pi-platform + pi-ime；另阶段实现 |
| A06 / P1 | 实际输入法 target 直接编译 `Core/Identifiers.swift`、Settings 与部分翻译策略源；AGENTS 的“共享只能通过协议声明”字面范围更窄 | 架构规范与构建事实不一致，后续消除重复时容易越过 GPL/MIT 边界 | 主控明确哪些 MIT 值模型可被 GPL target 使用，并同步约定；若坚持仅协议共享，单独设计边界迁移。禁止把 GPL 实现抽回 Core | `InputMethod/Squirrel.xcodeproj/project.pbxproj`、`Core/Identifiers.swift`、`Core/Settings/*`、`Core/Translation/*`、`AGENTS.md` | Claude；仅记录，不改规范/共享模块 |
| A07 / P2 | Voice worker 的 Swift XPC 协议在服务包内，通过符号链接给 App 和 smoke；Shared 另有 ObjC 翻译/填入协议 | “全部协议在 Shared”的文档不实，目录依赖方向难发现 | 先保留单份协议及 wire selectors；后续若迁入 Shared，使用独立轻量 target/源分组同时维护独立包、App、烟测编译，不引入 RoarkTCore/MLX 跨端依赖 | `Services/VoiceWorker/Sources/RoarkTVoiceWorker/VoiceWorkerProtocol.swift`、`App/Features/Voice/VoiceWorkerProtocol.swift`、`Tests/VoiceWorkerSmoke/run.sh`、`Shared/XPCProtocol/include/*` | pi-ime；R4-IME 已将唯一声明归入 Shared，消费者链接同源，wire 不变 |
| A08 / P2 | 输入法 80ms 防抖后，服务还有 120ms 防抖 | 未缓存动态请求有约 200ms 人为等待，再加实际翻译时间；键盘路径仍异步，这不是已测得的按键卡顿 | 单独做两端延迟/取消测量，再决定保留哪一端；继续保持缓存即时返回及 session/generation 校验 | `InputMethod/sources/RoarkTTranslationClient.swift`、`Services/TranslationService/TranslationXPCService.swift` | pi-ime + pi-platform；本轮保留行为 |
| A09 / P2 | 候选和选区各自维护 Apple session 与可用性检查；AI fallback 在 App 的 OperationRunner 路径，静态词条在 IME 本地 | 旧文档称统一服务负责全部路由，会误导排障和后续合并；不能直接合并两类请求的语义 | 文档先按事实分开；重构时仅提取已证实相同的 Apple 适配实现，保留方向、目标语言、错误映射、取消差异 | `Services/TranslationService/SystemTranslationBackend.swift`、`Services/TranslationService/SelectionTranslationBackend.swift`、`App/Features/Operations/OperationsEnvironment.swift`、`Core/Operations/DefaultOperationRunner.swift`、`InputMethod/sources/RoarkTTranslationClient.swift` | pi-platform；文档已纠正，未改代码 |
| A10 / P2 | 部分类型拥有多个独立状态机：`SquirrelInputController`（约 914 行）、`SquirrelView`（约 799 行）；截图 coordinator 同时接管捕获、预览与输出 | 修改一次输入或窗口生命周期容易牵连其他路径；行数是线索，不能据此机械拆类 | IME 后续按事件→候选快照→翻译/填入适配划分；截图按捕获会话与预览生命周期划分。先固定失焦、取消、迟到结果和坐标回归，再拆 | `InputMethod/sources/SquirrelInputController.swift`、`InputMethod/sources/SquirrelView.swift`、`App/Features/Screenshot/ScreenshotCoordinator.swift`、`App/Features/Screenshot/ScreenshotSession.swift` | pi-ime：R4-IME 先补回归再做文件级职责整理，状态所有权保留；截图部分未由本任务修改 |
| A11 / P2 | `VoiceXPC.swift` 同时包含 reply 门、识别 transport、填入 discovery/transport；模型文件校验混在下载 store | 查找一个边界需要读几个互不相同的流程，reply 的取消/超时难独立验证 | 按职责拆文件，保留调用接口、连接/retry/超时；校验与系统环境单独放置 | `App/Features/Voice/VoiceReply.swift`、`VoiceInterfaces.swift`、`VoiceWorkerClient.swift`、`VoiceCommitBridge.swift`、`VoiceEnvironment.swift`、`VoiceModelVerification.swift` | pi-ime；本轮已整理，新增 reply 行为测试 |
| A12 / P2 | 译文栏样式有未读取的 highlight/label 字段；shortcut radius 先赋值再被固定视觉值覆盖 | 调用方以为这些字段控制 UI，实际不生效 | 删除无效输入及调用实参，保留实际渲染常量；重构前后渲染比对 | `InputMethod/sources/RoarkTTranslationPanel.swift`、`InputMethod/sources/SquirrelPanel.swift`、`Tests/InputMethodTests/PanelChecks.swift` | pi-ime；本轮已清理，10 张译文栏 PNG 字节一致 |
| A13 / P2 | 输入法多处手写签名 requirement；Swift/ObjC 两套标识符仍必须镜像 | Team ID 或 identifier 更新可能漂移，影响服务信任 | 输入法调用已编译的 `Identifiers.codeRequirement`；保留 ObjC header 镜像测试及角色权限检查，绝不扩大信任集合 | `InputMethod/sources/RoarkTProcessTrust.swift`、`RoarkTTranslationClient.swift`、`RoarkTVoiceServer.swift`、`Core/Identifiers.swift`、`Shared/XPCProtocol/include/RoarkTIdentifiers.h` | pi-ime；本轮已收敛，测试锁定与原字符串相等 |
| A14 / P2 | `SettingsStoreTests` target 已承载大量 Voice、InputAI、设置等功能测试；部分 IME 检查通过包装 XCTest 启动脚本 | 目录名不能反映覆盖边界，容易误认为 `swift test` 不含某项检查或孤立运行错路径 | 后续按功能分 testTarget；保持 `scripts/test.sh` 可达全部测试，并把 subprocess 测试的显式源码清单一起维护；不重复建立独立测试包 | `Package.swift`、`Tests/SettingsStoreTests/*`、`Tests/InputMethodTests/*`、`scripts/test.sh`、`scripts/test-ime.sh` | Claude 协调各窗口；本轮沿用既有 target |
| A15 / P3 | `U4*` 阶段名残留于长期组件；`ComingSoonController` 实际也显示功能错误/通知；`Platform/Platform.swift` 占位 enum 未发现调用 | 名称难表达实际责任；占位文件增加无效入口 | pi-ui 在其重构中按具体用途命名；无引用枚举由 pi-platform 删除；先核对生产/图库/测试引用，不把有 Gallery 调用的原型误称全仓死代码 | `App/DesignSystem/U4Primitives.swift`、`App/Shell/ComingSoonController.swift`、`Platform/Platform.swift` | pi-ui + pi-platform；未修改 |
| A16 / P3 | 架构、路线图、PRD、Installer 说明的阶段/首次引导描述不同步；部分进度仍为早期规划 | 无法从文档辨认现有启动流程与未接线能力 | 本轮 architecture 写现状、移除首次引导职责；主控后续统一产品需求/路线图/Installer 的历史叙述，不把旧进度当当前验收 | `docs/architecture.md`、`docs/prd.md`、`docs/roadmap.md`、`CONTEXT.md`、`Installer/README.md`、`docs/adr/*` | pi-ime 已更新 architecture；其余由 Claude 协调 |

## release 与许可证证据

- 根 `Package.swift` 的 App target 只 exclude `Info.plist`。本轮 `scripts/build.sh` 成功后的 release 编译清单仍有全部 `App/Gallery/*.swift` 与 `App/Mock/*.swift`。
- 对 `dist/RockType.app/Contents/MacOS/RockType` 执行只读 `nm | swift-demangle`，确认 `GalleryRenderer.render`、`GalleryWindowController.show`、`SettingsFixtures.all`、`ImagePreviewModel.samples` 符号存在。未启动正式 App 的 Gallery 入口。
- 对主 App 与 worker 的链接/构建清单及 Xcode 源分组检查，未发现 MIT 产物链接 librime 或编译 `InputMethod/sources`；反向的 MIT 源用于 GPL target 见 A06。此结论不等于做完所有第三方源码的逐行来源鉴定。
- 主 App 打包词表来自 `Rime/roarkt_ai.dict.yaml`，不是读取输入法产物。`Core/Voice/LICENSE.md` 为许可证材料，其历史版权署名属于仓库明确允许的保留，不应当成产品代码旧标识残留。
- Swift XPC 协议的符号链接保持单份定义；本轮没有复制 GPL 实现到 MIT 目录，也没有改变任何 XPC selector/参数或公开签名身份。

## 后续执行顺序

1. pi-ui 与 pi-surfaces 先分别拆出正式 SettingsSection、去掉真实预览对 prototype 的包装依赖；各自保留现有 UI 行为测试。
2. Claude 统一调整 App/Gallery 构建边界与入口，再验证 release 没有 Gallery/fixtures 符号，Gallery 独立入口仍可渲染。此步骤是 R2-ARCH 后续阶段，第一阶段不能标为完成。
3. pi-platform 与 pi-ime 分别安排协议归位、翻译重复与防抖评估；不要在并行 UI 整理中叠加请求时序变化。
4. 大型输入控制器、截图会话与测试 target 的调整按各自行为边界逐项交付，不建立超出需求的通用工作流或 transport 框架。

本轮实际变更与验证结果见 [R2-ARCH 验收证据](../specs/evidence/014-R2-ARCH.md)。

## R4-UI 后续处理（2026-10-11）

A02/A03/A04/A15 的 UI 部分已处理：正式导航移入 Shell，正式图片预览不再初始化 Mock，Gallery/Mock/原型及入口使用完整 DEBUG 边界，长期组件和通知控制器改为职责名称。未修改 ScreenshotCoordinator；A15 的 Platform 占位项仍归 pi-platform。原审计表保留审计时快照，当前边界与验证见 [架构](architecture.md) 和 [R4-UI 证据](../specs/evidence/014-R4-UI.md)。
