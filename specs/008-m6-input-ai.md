# SPEC-008 输入法内 AI（M6）

- 阶段：M6
- 覆盖需求：FR-E3、FR-E8、NFR-2
- 状态：InProgress（E-1/E-2 代码及自动化完成；AppDelegate 接线、E-3/E-4 与真实验收未完成）
- 依赖：SPEC-001 翻译服务、SPEC-004 AI 连接、SPEC-005 操作引擎与模板、SPEC-003 候选窗

## 范围

候选窗中由用户快捷键触发 AI 动作：对“当前整句（已确认前缀 + 当前高亮候选）”做 改写 / 润色 / 翻译，结果显示在译文栏（标题“AI 改写”等），Tab 上屏。只在触发时请求；输入变化即作废；任何时候不阻塞打字。

## 架构

- **AI 配置下发**：输入法不读钥匙串、不发网络请求。主 App 在启动、AI 设置变化、钥匙串密钥变化时，通过翻译服务新接口 `configureAI(config:withReply:)`（仅主 App 可调用）下发：Base URL、模型、密钥、超时、三个动作的提示词（来自操作模板：改写=润色模板的变体、润色=润色模板、翻译=翻译模板）。服务只在内存保存；主 App 退出或清除配置时下发空配置使其失效。
- **请求接口**：`rewriteCandidate(sessionID:generation:text:action:withReply:)`（仅输入法可调用），`action` ∈ `rewrite | polish | translate`；同一 session 新 generation 取消旧请求；回复带 generation 与原文，由输入法比对当前快照决定是否显示。未配置 AI 时返回明确错误码（输入法显示“未配置 AI”并提示去设置）。
- **Secure Input**：输入法侧在 Secure Input 或密码框时不发请求；服务侧再次拒绝来自 Secure Input 期间的请求（沿用候选翻译的处理）。
- **触发键**：默认 `⌥Tab` 循环三个动作（改写 → 润色 → 翻译），`Esc` 关闭 AI 结果回到普通候选翻译；可在设置 → 快捷键 中修改（存于 InputSettings，经已有的设置同步到输入法）。若 `⌥Tab` 与 Rime 按键冲突，在规格问题节提出替代键。
- **复用**：服务端 AI 调用复用 `Core/AI/AIClient`（服务进程已链接 RoarkTCore）。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| E-1 | XPC 协议新增 `configureAI`、`rewriteCandidate`；服务实现（内存配置、取消、超时、错误码、鉴权） | pi-xpc | E-1 代码与自动化通过；真实安装鉴权待 Claude 验收 |
| E-2 | 主 App 下发配置：启动、AI 设置/模板/密钥变化、退出清空；设置中输入法 AI 开关与快捷键项 | pi-xpc | E-2 代码与自动化通过；AppDelegate 接线及 UI 验收待 Claude |
| E-3 | 输入法侧：触发键、请求、译文栏 AI 状态、Tab 上屏、作废规则 | pi-ime（M1 合并后） | 未开始 |
| E-4 | 验收 | Claude + 用户 | 未开始 |

**文件所有权（E-1、E-2）**：`Shared/XPCProtocol/`、`Services/TranslationService/`、`Core/Settings`（只新增字段）、`App/Features/InputAI/`、设置快捷键分区中新增一项、对应 `Tests/`。`AppDelegate` 接线提供 `start()/stop()` 由 Claude 集成。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 鉴权：输入法不能 configureAI，主 App 不能 rewriteCandidate | 服务测试 | 通过 | `InputAITests` 角色拒绝与共享 generation 测试；真实签名安装场景待人工 |
| 未配置 / 配置清空后返回明确错误 | 服务测试 | 通过 | 空配置、无配置、非法替换配置、配置所属连接断开均撤销 |
| generation 取消与迟到丢弃 | 服务测试 | 通过 | 忽略取消的受控 backend；取消立即回复、deadline 独立终止、旧结果丢弃 |
| 密钥不落盘、不进日志 | 代码检查 + 测试 | 自动化与代码检查通过 | 内存配置；AIClient ephemeral 会话；固定错误映射，未透传服务商错误内容；主 App 持久化测试确认未写入密钥 |
| 打字期间 AI 请求不影响按键延迟 | 手工 | 待人工验证 | |
| 真实 AI 改写 / 润色 / 翻译上屏 | 手工 | 待人工验证 | |

## 进度

### E-1（2026-10-11）

- 新增 `RoarkTInputAIXPCProtocol`，继承现有文字翻译协议；服务导出新接口，既有窄接口客户端保持可用。E-3 应使用新接口创建 `NSXPCInterface`。
- `configureAI` 使用字符串字典（七个必填键见协议头），空字典撤销配置；提示词沿用 `{{target}}`，服务追加原文。错误码 100–112 的语义见协议头。
- 实现配置所属连接生命周期、输入法/主 App 方法级角色检查、普通候选与 AI 共用 generation 门槛、取消、独立 deadline、Secure Input 请求前/结果前复检与运行期间监测。密码框焦点检查仍由 E-3 输入法负责，服务不申请辅助功能权限。
- 验证：`swift test --filter RoarkTTranslationServiceTests` 退出 0（45 tests）；补匿名 XPC 字典/回复往返后 `scripts/test.sh` 退出 0（131 tests、Rime 部署、Hotkey/Permission checks 均通过）。首次编译因 actor 隔离报错退出 1，已修复并通过上述复测。
- 未运行安装、LaunchAgent 加载、真实端点请求、真实签名安装鉴权和键盘验收；这些不由单元测试替代。

### E-2（2026-10-11）

- 提供 `App/Features/InputAI/InputAIController` 的 `start()/stop()`：启动下发，监听 SettingsStore（AI 配置、模板、输入法 AI 设置）与无内容钥匙串事件；事件注册失败时每 2 秒重读。专用 XPC 客户端做签名绑定、串行更新、超时/取消与断连重试，停止时下发空配置后关闭连接。
- `InputSettings.inputAI` 新增可选设置（缺失时默认关闭、`⌥Tab`、30 秒）；通过现有设置文件和通知同步到输入法。未使用旧的 `ShortcutSettings.inputMethodAI` 占位字段，不做迁移。设置 → 快捷键新增开关、录制、清除、恢复默认和与已配置全局键的冲突提示；不把输入法按键注册为全局键。
- 验证：`swift test --filter inputAI` 退出 0（13 tests）；补匿名 XPC 主 App 客户端下发/清空/重连及快捷键冲突检查后，`scripts/test.sh` 退出 0（139 tests + Rime + Hotkey/Permission checks）。初次编译因 Swift 6 通知隔离与 Security 枚举导入名称报错，已修复并通过复测。
- 验证覆盖启动、重复 start/stop、设置/模板/模拟钥匙串变化、删除密钥、读取失败、并发编辑时串行下发、停止后重启、配置不含密钥的持久化、IME 设置投影。系统钥匙串回调后续已用隔离合成条目验证（见下）；设置 UI 走查待人工。
- 未改 AppDelegate。Claude 集成时持有一个 `InputAIController`，设置就绪后调用 `start()`，`applicationWillTerminate` 调用 `stop()`。在此接线与 E-3 完成前，不能宣称输入法内 AI 已端到端可用。
- 已按通知分别在 E-1、E-2 提交后执行 `git merge main`，取得本机环境规则及回环 HTTP 支持。

### main 同步与最终复核（2026-10-11）

- 两端统一调用 `AIClient.isAllowedEndpoint`，仅给该方法新增 `public` 可见性；允许共享规则规定的回环 HTTP，拒绝外部 HTTP、相似主机名及带 URL 凭据的配置。未另建 URL 协议规则。
- 加固连接交替：旧连接的迟到清空不能撤销新连接配置；断连前排队的成功回复不能阻止新连接重新下发配置。已加回归测试。
- `swift test --filter inputAI` 退出 0（18 tests）；隔离系统钥匙串新增/更换/删除测试 `swift test --filter inputAIKeychainMonitorReceivesIsolatedKeyEdits` 退出 0（1 test），只操作随机测试服务名下的合成条目，已清理。
- 最终 `scripts/test.sh` 退出 0（144 项 Swift Testing + 32 项 XCTest、Rime 临时目录部署、Hotkey/Permission checks）；已有 `Core/Voice/LICENSE.md` 未声明资源警告不影响退出码。
- `scripts/build.sh` 退出 0：主 App、翻译服务、输入法、语音 worker 构建及签名完成，脚本内语音 MLX self-test、签名 XPC helper 往返与错误身份拒绝均通过。产物仅位于本 worktree 的 `dist/`（指向 `.build/dist.noindex`）。
- `git diff --check` 最终退出 0。未运行 install-dev/uninstall-dev、未注册或启动输入法、未加载 LaunchAgent、未启动本 worktree 的主 App；安装和真实交互留给 Claude 从 main 验收。

## 问题

- 待 Claude 集成 AppDelegate 生命周期并从 main 做安装/签名鉴权、真实端点、按键 P95、三动作 Tab 上屏、Secure Input/密码框与浅深色 UI/键盘/VoiceOver 验收。
- 钥匙串事件接口为 macOS 现有但已标记 deprecated 的 `SecKeychainAddCallback`；注册失败有重读兜底。隔离条目的新增、更换、删除已自动验证；仍待真实 App 连接和钥匙串锁定/解锁走查。
- E-3 需决定未配置 AI 时隐藏入口的状态来源：目前协议提供请求时的明确 `notConfigured` 错误，InputSettings 只同步用户开关，不同步密钥是否存在。若要在首次触发前准确隐藏入口，应由 Claude 确认增加无内容的可用性查询或运行时状态同步；不得让输入法读钥匙串。
