# SPEC-007 语音（M5）

- 阶段：M5
- 覆盖需求：FR-B1–B6、FR-E8（语音填入）
- 状态：InProgress（V1–V4 完成，待 Claude + 用户验收）
- 依赖：SPEC-004（设置、权限、Fn 探针）、SPEC-001（输入法语音 ticket 端点）、D0 语音 HUD

## 范围

按住 Fn 录音 → 本地 Qwen3-ASR（MLX）识别 → 经输入法 ticket 安全填入当前输入框，不自动发送；模型下载管理；HUD；自动准备模型；可选 AI 润色。约束沿用 `../RoType/docs/architecture/local-voice-plan.md` 的“必须守住”。

## 迁移来源（只读）

- `../RoType/VoiceRuntime/`（MLX worker）→ `Services/VoiceWorker/`（独立 SPM 包，改名 `RoarkTVoiceWorker`，identifier `com.roarkist.roarkt.voice`）
- `../RoType/Sources/RoTypeApp/Voice*.swift` → `App/Features/Voice/`（录音、激活、模型存储、worker 客户端、填入桥接、HUD 控制）
- `scripts/build-voice-worker.sh`、`fetch-*` 相关脚本按需迁入并改名
- 输入法侧 `InputMethod/sources/RoarkTVoiceServer.swift` 已在 T3 迁入，按需调整

## 规则

- 麦克风权限归主 App；仅按住 Fn 期间录音，松开或取消立即关闭麦克风。
- 识别结果只通过输入法 dictation ticket 填入（`capture` 绑定目标 → `commit`）；目标变化、超时、Secure Input 时拒绝填入，结果保留在 HUD 可复制。
- 模型不进安装包；下载可取消、校验完整性；卸载模型不删其他数据。
- 自动准备（B5）只加载模型，不开麦；关闭后释放内存。
- AI 润色（B6）默认关闭；失败或未配置 AI 时填入原识别结果。
- 删除 RoType 中旧 Python 语音链退休、升级迁移相关逻辑。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| V1 | VoiceWorker 迁移、构建脚本、签名、`scripts/build.sh` 集成 | pi-ime | 完成（待验收） |
| V2 | 模型存储与下载（B2、B3），设置 → 语音 分区接线 | pi-ime | 完成（待验收） |
| V3 | Fn 按住录音、worker 客户端、HUD 控制、ticket 填入（B1、B4） | pi-ime | 完成（待验收） |
| V4 | 自动准备（B5）、AI 润色（B6） | pi-ime | 完成（待验收） |
| V5 | 集成与验收 | pi-platform 集成 / Claude + 用户验收 | 代码集成完成（待验收） |

**文件所有权**：`Services/VoiceWorker/`、`App/Features/Voice/`、`InputMethod/` 语音相关、`scripts/build-voice-worker.sh`、`scripts/build.sh` 中语音段、设置语音分区接线、对应测试。`AppDelegate` 接线由 Claude 集成。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| worker 构建、签名、identifier | 命令 | 通过 | `scripts/build-voice-worker.sh`：Xcode Release、MLX self-test、codesign verify 通过；identifier `com.roarkist.roarkt.voice`，Team `DF7J2VBQD8`。`Tests/VoiceWorkerSmoke/run.sh` 验证打包 helper 启动、无效模型拒绝、同 Team 错 identifier 拒绝。真实模型识别待人工。 |
| 下载取消、校验失败不加载 | 单元测试 | 通过 | `VoiceDownloadTests` 使用 Swift 本地 HTTP 服务器验证断点、取消不发布、重试、错误 Range、SHA-256 损坏、加载校验门与删除范围；`scripts/test.sh` 69 测试通过。 |
| ticket：目标变化 / 超时 / Secure Input 拒绝 | 单元测试 + 手工 | 自动测试通过；待人工验证 | `VoiceLifecycleTests` 验证麦克风先停、捕获中松键、权限缺失、取消/安全输入后迟到结果丢弃、目标变化与 ticket 超时/复用拒绝；真实 IMK 安全输入待人工。 |
| 真实麦克风：中文、中英混说识别并填入 | 手工 | 待人工验证 | |
| 非录音期间麦克风关闭 | 手工（菜单栏麦克风指示） | 待人工验证 | 自动生命周期测试确认 release 先关闭录音；预加载从不调用录音入口。真实设备指示仍需走查。 |
| 自动准备、关闭释放、模型切换 | 单元测试 + 手工 | 自动测试通过；待人工验证 | `VoiceLifecycleTests` 覆盖非目标输入源不准备、预加载不录音、首轮复用、关闭停止、切换重载、新 Fn 中止旧识别。真实 MLX 内存与冷启动延迟待测。 |
| AI 润色开关、失败回退、取消 | 单元测试 + 手工 | 自动测试通过；待人工验证 | `VoicePolisherTests` 覆盖默认关闭、缺密钥、安全输入零请求、成功、超时回原文及空/多行/过长响应；生命周期测试覆盖 AI 迟到不提交。真实服务商未调用。 |
| HUD 与语音设置设计验收 | 浅/深色、VoiceOver、键盘、屏幕边缘走查 | 待人工验证 | 复用设计变量；非激活面板、真实录音电平、完成/失败与复制按钮已实现。未提供真实运行截图，不将构建等同 UI 验收。 |
| `scripts/test.sh`、`scripts/build.sh` | 命令 | 通过 | 最终：80 测试 + Rime 部署通过；主 App、翻译服务、worker、输入法及注册工具 Release 构建/签名通过。`Tests/AppShellTests/run.sh` 通过；`git diff --check` 通过。 |

## 进度

- V1：固定版本 MLX 独立包、双向签名 XPC 协议、内存音频、取消退出进程；构建脚本嵌入 XPC helper/Metal 资源、补主 App 麦克风声明与 entitlement。`scripts/test.sh` 通过（66 测试与 Rime 部署）；worker Release 构建、MLX self-test 与签名校验通过。未进行真实模型与权限验收。

- V2：两档固定 revision/大小/SHA-256 清单，分块下载、进度、取消、重试、空间不足提示和按模型删除；统一设置仅替换语音分区。模型切换持久化复用 SettingsStore；大小不能代替加载前哈希校验。真实 GB 下载、磁盘不足、UI 主题/可访问性待人工验证。

- V3：复用 Fn 手势探针，新增内存录音、50 ms 安全/松键看门狗、60 秒上限、真实波形 HUD；XPC 调用均有限时/取消门，输入法侧补 Secure Input 拒绝。`VoiceInputController.start()/stop()` 为集成入口，未改 AppDelegate。`Tests/VoiceWorkerSmoke/run.sh` 通过：打包 Metal self-test、合法签名调用返回、同 Team 错 identifier 被拒绝；已修正 Swift 6 XPC 回调跨 executor 隔离问题。

- V4：自动准备只在已选中 RoarkT 且开关开启时加载已下载、校验通过的模型；关闭、停止、删除模型时释放进程。润色默认关闭，复用 Core AIClient 与平台钥匙串，15 秒请求限时，失败回原文，安全输入与取消丢弃迟到结果。最终 80 项自动测试通过。
- 最终复核：修正新 Fn 到来时不能复用仍在识别的 worker；并发安全的录音转换回调；保留权限提示而不保留受保护内容；worker bundle 包含依赖许可证。主 App 打包结果含麦克风用途声明与 audio-input entitlement，深度签名检查通过。

## Claude 集成说明

1. 主 App 唯一持有 `VoiceInputController(store: settingsStore)`，启动调用 `start()`，退出调用 `stop()`。默认模型存储与设置分区均用 `VoiceModelStore.shared`。未改 `AppDelegate`、`Core`、`Platform`、`Shared` 或其他 worktree。
2. 语音设置接线只替换 `App/Shell/ShellSettingsView.swift` 的 `private var voice`；没有修改 `ShellSettingsSections.swift`。合并时保留其他分区的集成改动。
3. `HotkeyCenter` 原 Fn 入口仍是探针；语音控制器自己消费 Fn press/release/cancel。Claude 需统一 Fn 监听所有权与快捷键录制期间的暂停：录制快捷键时 `stop()`，结束后 `start()`；勿把仅有 press 的旧 probe 当成完整语音入口。辅助功能重新授权后同样 stop/start 重建监听。
4. 发行/验收请运行 `scripts/build.sh`；SPM 裸可执行文件没有麦克风 bundle 声明、entitlement 或 XPC helper。helper 位于 `Contents/Helpers`，`Contents/XPCServices` 使用发现链接，已在临时签名 App 中验证启动与鉴权。

## 问题

- 待 Claude + 用户确定真实 Fn 与系统听写/输入源切换冲突的验收配置；当前只解释冲突，不更改系统设置。
- 待人工：内置麦克风/AirPods、中文/中英混说、首尾字与静音、Esc/松键丢失/设备断开/睡眠、不同应用/窗口/密码框/终端 Secure Keyboard Entry 的 ticket 行为；两档模型实际下载中断、磁盘不足、模型内存与延迟；HUD 与设置 UI 设计验收。
- 当前只验证自动生命周期与无模型 XPC 调用，未下载 GB 模型、未启用麦克风、未向真实 AI 发送用户内容，也未安装或激活输入法。V5 保持未开始。
- 非本任务的既有构建提示：SPM 提示 `Core/Voice/LICENSE.md` 未声明资源；未越权修改根 Package.swift。


### M5 App 集成证据（2026-10-11）

- AppDelegate 唯一持有 VoiceInputController(store: store)，通过快捷键生命周期回调调用 start()/stop()，退出明确 stop()；启动仅在 Fn 已配置、无冲突且辅助功能已授权时开启监听。设置语音分区保留 main 的 VoiceModelStore.shared 接线，操作模板分区同时使用 M3-5 templatesPane。
- HotkeyCenter / SystemHotkeyRegistrar 移除旧 press-only Fn 探针和第二套 FnKeyMonitor，保留 Fn 配置合法性、重复绑定冲突、权限缺失和监听失败状态。VoiceInputController 独占 press/release/cancel。快捷键录制开始同步停止语音，取消或保存后按当前配置恢复；辅助功能状态变化由现有 2 秒检查触发 stop/start 重建；录制中重新授权不提前恢复。未配置、冲突与不支持绑定均停止语音。
- scripts/test.sh 通过，包含 AppShellTests。新增回归覆盖监听独占、录制暂停/恢复、授权撤销/重新授予、录制中授权变化、Fn 冲突、清除绑定、启动失败/重试和退出；原语音生命周期与模型/润色测试保留。截图仍为“即将推出”。
- 完整签名构建、worker 冒烟、图库与实际 App 启动检查正在统一验证，后续补最终结果。真实 Fn/麦克风/模型下载识别/ticket 填入、系统权限与听写冲突、HUD 设计与 VoiceOver 仍待人工验证，未启用麦克风或下载模型。
