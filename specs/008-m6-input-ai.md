# SPEC-008 输入法内 AI（M6）

- 阶段：M6
- 覆盖需求：FR-E3、FR-E8、NFR-2
- 状态：Ready（服务与主 App 部分）；输入法部分待 M1 合并
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
| E-2 | 主 App 下发配置：启动、AI 设置/模板/密钥变化、退出清空；设置中输入法 AI 开关与快捷键项 | pi-xpc | 未开始 |
| E-3 | 输入法侧：触发键、请求、译文栏 AI 状态、Tab 上屏、作废规则 | pi-ime（M1 合并后） | 未开始 |
| E-4 | 验收 | Claude + 用户 | 未开始 |

**文件所有权（E-1、E-2）**：`Shared/XPCProtocol/`、`Services/TranslationService/`、`Core/Settings`（只新增字段）、`App/Features/InputAI/`、设置快捷键分区中新增一项、对应 `Tests/`。`AppDelegate` 接线提供 `start()/stop()` 由 Claude 集成。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 鉴权：输入法不能 configureAI，主 App 不能 rewriteCandidate | 服务测试 | 通过 | `InputAITests` 角色拒绝与共享 generation 测试；真实签名安装场景待人工 |
| 未配置 / 配置清空后返回明确错误 | 服务测试 | 通过 | 空配置、无配置、非法替换配置、配置所属连接断开均撤销 |
| generation 取消与迟到丢弃 | 服务测试 | 通过 | 忽略取消的受控 backend；取消立即回复、deadline 独立终止、旧结果丢弃 |
| 密钥不落盘、不进日志 | 代码检查 + 测试 | E-1 通过；E-2 待实现 | 内存配置；AIClient ephemeral 会话；固定错误映射，未透传服务商错误内容 |
| 打字期间 AI 请求不影响按键延迟 | 手工 | 待人工验证 | |
| 真实 AI 改写 / 润色 / 翻译上屏 | 手工 | 待人工验证 | |

## 进度

### E-1（2026-10-11）

- 新增 `RoarkTInputAIXPCProtocol`，继承现有文字翻译协议；服务导出新接口，既有窄接口客户端保持可用。E-3 应使用新接口创建 `NSXPCInterface`。
- `configureAI` 使用字符串字典（七个必填键见协议头），空字典撤销配置；提示词沿用 `{{target}}`，服务追加原文。错误码 100–112 的语义见协议头。
- 实现配置所属连接生命周期、输入法/主 App 方法级角色检查、普通候选与 AI 共用 generation 门槛、取消、独立 deadline、Secure Input 请求前/结果前复检与运行期间监测。密码框焦点检查仍由 E-3 输入法负责，服务不申请辅助功能权限。
- 验证：`swift test --filter RoarkTTranslationServiceTests` 退出 0（45 tests）；补匿名 XPC 字典/回复往返后 `scripts/test.sh` 退出 0（131 tests、Rime 部署、Hotkey/Permission checks 均通过）。首次编译因 actor 隔离报错退出 1，已修复并通过上述复测。
- 未运行安装、LaunchAgent 加载、真实端点请求、真实签名安装鉴权和键盘验收；这些不由单元测试替代。


## 问题
