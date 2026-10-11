# SPEC-007 语音（M5）

- 阶段：M5
- 覆盖需求：FR-B1–B6、FR-E8（语音填入）
- 状态：Ready
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
| V3 | Fn 按住录音、worker 客户端、HUD 控制、ticket 填入（B1、B4） | pi-ime | 未开始 |
| V4 | 自动准备（B5）、AI 润色（B6） | pi-ime | 未开始 |
| V5 | 验收 | Claude + 用户 | 未开始 |

**文件所有权**：`Services/VoiceWorker/`、`App/Features/Voice/`、`InputMethod/` 语音相关、`scripts/build-voice-worker.sh`、`scripts/build.sh` 中语音段、设置语音分区接线、对应测试。`AppDelegate` 接线由 Claude 集成。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| worker 构建、签名、identifier | 命令 | 通过 | `scripts/build-voice-worker.sh`：Xcode Release、MLX self-test、codesign verify 通过；identifier `com.roarkist.roarkt.voice`，Team `DF7J2VBQD8`。真实 App XPC 启动待验证。 |
| 下载取消、校验失败不加载 | 单元测试 | 通过 | `VoiceDownloadTests` 使用 Swift 本地 HTTP 服务器验证断点、取消不发布、重试、错误 Range、SHA-256 损坏、加载校验门与删除范围；`scripts/test.sh` 69 测试通过。 |
| ticket：目标变化 / 超时 / Secure Input 拒绝 | 单元测试 + 手工 | 未运行 | |
| 真实麦克风：中文、中英混说识别并填入 | 手工 | 待人工验证 | |
| 非录音期间麦克风关闭 | 手工（菜单栏麦克风指示） | 待人工验证 | |
| `scripts/test.sh`、`scripts/build.sh` | 命令 | 未运行 | |

## 进度

- V1：固定版本 MLX 独立包、双向签名 XPC 协议、内存音频、取消退出进程；构建脚本嵌入 XPC helper/Metal 资源、补主 App 麦克风声明与 entitlement。`scripts/test.sh` 通过（66 测试与 Rime 部署）；worker Release 构建、MLX self-test 与签名校验通过。未进行真实模型与权限验收。

- V2：两档固定 revision/大小/SHA-256 清单，分块下载、进度、取消、重试、空间不足提示和按模型删除；统一设置仅替换语音分区。模型切换持久化复用 SettingsStore；大小不能代替加载前哈希校验。真实 GB 下载、磁盘不足、UI 主题/可访问性待人工验证。

## 问题
