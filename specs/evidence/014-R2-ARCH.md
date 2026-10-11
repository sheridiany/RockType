# SPEC-014 R2-ARCH 第一阶段验收证据

- 日期：2026-10-11；执行窗口：pi-ime。
- 工作区：`RoarkT-wt/ime`，分支 `agent/ime`。
- 开始时工作树干净，执行 `git merge main` 返回 `Already up to date.`；基线为 `17c42417b83d0465c60c1cb6fbbee0806e10c7a2`。
- **结论：第一阶段完成，待 main 合并。** 全仓审计、自己区域内的等价整理、架构文档同步完成；正式 App 的 Gallery/Mock 隔离仍是后续阶段，未冒充完成整个 R2-ARCH。

## 做了什么

1. 新增 [全仓架构审计](../../docs/architecture-audit-2026-10.md)，按“问题—影响—建议—文件—负责窗口”列出 16 项，涵盖模块边界、release 的 Mock/Gallery、Surfaces/Features、重复/死代码、命名、过大类型、GPL/MIT、XPC 协议位置及后续顺序。
2. `VoiceXPC.swift` 拆为 `VoiceInterfaces.swift`、`VoiceReply.swift`、`VoiceWorkerClient.swift`、`VoiceCommitBridge.swift`。另把 `VoiceEnvironment` 与 `VoiceModelVerification` 从控制器/store 提到同目录的独立文件。原声明/方法体逐段与基线比对一致；仅 reply 从 file-private 改为模块内可见以供两个适配器共用和测试，调整 imports/注释。未改变 timeout、retry、请求、保护检查、模型目录或填入规则。
3. 输入法删去译文栏 Style 的未使用 highlight/label、被后续固定值覆盖的 shortcut radius，同步生产/测试调用点；实际 UI 常量保持原值。
4. 输入法进程信任、翻译连接、语音端点的 requirement 调用既有 `Identifiers.codeRequirement(for:)`，移除重复字符串/包装方法；允许身份不变。没有改 Shared 协议、Core 或鉴权角色规则。
5. [architecture.md](../../docs/architecture.md) 更新真实进程、翻译路由、协议所在位置、当前语音边界、产物和发布安装路径；明确设置承担权限/输入源检查、没有独立首次引导，区分已实现服务接口与未接线的输入法 AI。
6. 主 spec 只修改 R2-ARCH 一行状态。本轮未改 Screenshot、AI、ResultWindow、Settings、DesignSystem；没有安装、注册输入法、加载 LaunchAgent、录音或修改个人词表/userdb。

## 验证

| 项目 | 状态 | 方法与结果 |
| --- | --- | --- |
| 全量自动化 | **通过** | `scripts/test.sh` 实际退出 0；86 项 XCTest、Swift Testing 汇总 195 项，另有 Rime/快捷键/权限检查。两个显式 opt-in 测试跳过，见下方。日志 `.build/r2-arch/tests.log`，退出码 `.build/r2-arch/tests.exit` |
| 全产物构建与签名 | **通过** | `scripts/build.sh` 实际退出 0，覆盖 App、翻译服务、输入法、注册工具、worker；脚本的 MLX 自检、正确身份 XPC 往返和错误 identifier 拒绝均通过。日志 `.build/r2-arch/build.log`，退出码 `.build/r2-arch/build.exit` |
| 语音行为 | **通过** | 37 项专项测试通过；新增 `Tests/SettingsStoreTests/VoiceReplyTests.swift` 四项：首次终态获胜、timeout 后迟到成功、发送前取消不启动 transport、等待中取消释放 continuation 并拒绝二次完成。使用 AsyncStream 启动信号，不靠延长等待掩盖竞争。既有语音生命周期/取消/安全输入/模型校验测试保留 |
| 结构搬迁等价 | **通过** | 将所有抽出的语音声明/方法体逐段与 `git show HEAD:<旧文件>` 比对（提交前 HEAD 即基线）；除 reply 可见性、imports 和新增职责注释外，抽出内容一致。worker/填入适配器方法体完整保留 |
| 输入法行为与身份字符串 | **通过** | 重构前后 `scripts/test-ime.sh` 均退出 0。`SessionChecks.swift` 增加主 App、翻译服务、输入法三种身份的新/旧 requirement 字符串相等断言；原 session/generation、缓存、取消、按键与面板检查通过 |
| 译文栏视觉等价 | **通过** | 重构前保留 `.build/r2-arch/panels-before/`，与重构后的 `.build/ime-evidence/translation-*.png` 逐文件比较，10 张 PNG 字节完全相等；不涉及真实桌面或用户内容 |
| release 架构取证 | **通过（确认待整改事实）** | release 源清单包含 Mock/Gallery；`nm` + `swift-demangle` 确认 Gallery render/window 与 Settings/ImagePreview samples 在正式 App 中。主 App/worker `otool -L` 未见 librime；根 MIT target 源清单未见 `InputMethod/sources`。记录 `.build/r2-arch/release-audit.txt`，并核对 Xcode 与独立 worker 包配置 |
| 冻结词库回归 | **通过** | 完整测试保留真实 librime 的 ≥188/200 门槛、分组与原命中/日常逐项保护；冻结文件 SHA-256 为 `7b8d9651974895879a2d11a28325eb2ca86e6e046a2b6c1c345b41ab39d15f96`，Rime 与评测夹具本轮未改 |
| 差异与所有权 | **通过** | `git diff --check` 通过；文档中引用的仓库文件核对存在；代码仅改自己所属 Voice/InputMethod 和对应测试，主 spec 仅改一行 |

自动化没有失败项。构建/测试仍有既有 `Core/Voice/LICENSE.md` 未声明资源提示，不影响退出码；许可证未删除或改写。

## 未运行与待后续项

- **未运行**：`localMagpieLiveSmoke`、`syntheticMixedLanguageVoiceAccuracy` 两个 opt-in 测试。此次未改识别上下文、模型或 AI 行为，未请求真实 AI、下载模型或重做 R1c 的质量评测；不引用旧评测充当本次新结果。
- **待人工验证**：真实 IMK 按键/迟到翻译/Tab、真实 Fn/麦克风授权、Secure Input/密码框切换、跨应用安全填入，以及多显示器/全屏/VoiceOver。离屏等价与单元测试不代替这些验收。
- **待后续阶段**：先由 pi-ui 分离 Mock 中的正式 SettingsSection，由 pi-surfaces/pi-screenshot 去除真实预览经过 prototype 的包装依赖，再由主控隔离 Gallery/Mock 构建与入口。当前 release 仍携带它们。
- 其余审计项按负责窗口安排；输入法内 AI 接线、双层防抖优化、GPL 对应源码正式发布材料均未在本阶段实施。
- 无后台测试或 Worker 遗留；未 push。分支与 worktree 保留，等待合并和人工验收。
