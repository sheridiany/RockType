# RoarkT VoiceWorker

独立 Swift/MLX XPC 服务（macOS 14+、Apple Silicon）。依赖锁定在 `Package.resolved`；`scripts/build-voice-worker.sh` 用 Xcode 构建 Metal 资源、运行不加载模型的 MLX self-test，并签名 XPC bundle。

主 App 通过 `NSXPCConnection(serviceName: Identifiers.voiceWorkerID)` 连接。双向签名要求为 Team ID + 具体 identifier。协议唯一实体在 [`Shared/VoiceWorkerProtocol/VoiceWorkerProtocol.swift`](../../Shared/VoiceWorkerProtocol/VoiceWorkerProtocol.swift)，App 与 worker 的同名源路径均以符号链接引用它，烟测直接编译该 Shared 文件。ObjC 协议名、selectors、参数与回复类型保持不变；不引入新的包依赖。worker 的 Identifiers 链接到 Core 唯一来源。服务只接受本地模型目录与有上限的内存 PCM，不监听麦克风、不写音频或转写日志、不发起模型下载。取消、关闭自动准备或父连接失效时退出进程，释放 MLX 内存。

构建脚本将签名 bundle 放入主 App 的 `Contents/Helpers`，并在 `Contents/XPCServices` 建立发现链接。主 App 的麦克风用途声明及 hardened-runtime audio-input entitlement 在构建语音段添加。真实签名 XPC 启动、Metal 资源发现及麦克风权限需以打包 App 验收，SPM 命令行运行不能代替。

## 本机术语上下文（SPEC-014 R1c）

锁定的 `mlx-audio-swift@bf14ae0c26e4e85553dd989571cae29d70fa6735` 中，
`Qwen3ASRModel.generate(..., context:, language:, ...)` 将 context 写入 system 提示，并复用于每个音频分段。
App 使用 `VoiceContextVocabulary` 构造最多128个词、4096 UTF-8字节的上下文，经同一签名鉴权 XPC 随音频发送。
语言仍为自动识别；不进行事后字符串强制替换。

工厂源为 MIT 原创 `Rime/roarkt_ai.dict.yaml`，由 `scripts/build.sh` 独立复制到主 App 的
`Resources/VoiceVocabulary.dict.yaml`；不读取或链接 GPL 输入法代码。各词表分组轮流取样，
另附少量英文技术名。个人源只读取统一 Rime 目录中的 `roarkt_personal.dict.yaml` 与
`roarkt_personal_en.dict.yaml`，最多取32个词；不读取学习数据库，不扫描用户文档。
读文件在后台完成，前后检查安全输入与取消；词表、上下文与转写结果不写日志或持久缓存。
拒绝符号链接、非普通文件和超过256KiB的词表，过滤提示分隔符等非词项字符。

构建后可显式运行合成准确率评测：

```sh
ROARKT_VOICE_EVALUATION=1 swift test --filter syntheticMixedLanguageVoiceAccuracy
```

该测试使用系统 Tingting 将六条固定中英技术短句合成为16kHz PCM，通过 LaunchServices 启动
签名测试宿主，对已下载的0.6B模型执行有/无上下文 A/B；不开启麦克风、不下载模型、
不读取个人词表。样例与数字指标保存在 `.build/r1c-ime/voice-accuracy/`。
常规 `scripts/test.sh` 会执行上下文规则与文件边界测试；上述模型评测默认跳过，需单独记录结果。
这些小规模合成样例不代表真实口音、噪声、长录音或1.7B模型的质量。

## 长录音与预览（SPEC-014 R5）

App 最长录音 180 秒，到限自动识别。worker 接受最多 11.52 MB 的 16 kHz 单声道 Float32，拒绝非整帧、非有限值和越界幅值。Core 的 `VoiceAudioSegmentation.swift` 经源链接供 worker 编译：单段不超过 28 秒，先找静音点，无静音则硬切，所有样本仅覆盖一次。每段独立 1024 token 上限，触顶则失败而不把截断结果当成功；拼接保留模型标点与重复语句。原 wire selectors 不变。

App 使用相同的 transcribe wire 做 3 秒固定窗口 HUD 预览，一次仅一个在途请求；预览结果不能提交或复制。XPC 回复限时 3 秒，RTF > 0.8、超时或失败会按模型关闭本次运行的预览，松键后仍用完整音频识别（XPC 限时 240 秒）。worker 准备时用一秒合成静音、一个生成 token 预热，数据不来自麦克风或个人词表。

合成性能评测（要求两档模型已下载并通过固定 SHA-256 校验，无隐式下载）：

```sh
ROARKT_VOICE_PERFORMANCE=1 swift test --filter 'syntheticVoicePerformanceBothModels|syntheticVoiceCaptureAndCleanupCosts'
ROARKT_VOICE_PERFORMANCE=1 ROARKT_VOICE_PERFORMANCE_CONTEXT=1 swift test --filter syntheticVoicePerformanceBothModels
```

第一条测空上下文与采集/清理微基准，第二条加入与产品同预算的工厂词表（不读个人词表）。固定 Tingting 合成音频覆盖 3/6/28/55/75/180 秒，长样本末尾有独立校验句，另检查越长、非整帧及 NaN 拒绝。指标保存在 `.build/r5-ime/performance-{after,context}/`，只有耗时、RTF、字符/标点数和尾句是否命中，不写转写原文。

R5 的变更前对照从基线 worker 运行 `ROARKT_VOICE_PERFORMANCE_BASELINE=1` 得到；此变量仅选择旧长度范围，不会自动换回旧实现。数据和真实硬件限制见 [R5 证据](../../specs/evidence/014-R5-IME.md)。麦克风 stop 和真实 IMK insertText 不由该合成基准覆盖；主 App 的 voice 日志仅记录各阶段数字，供安装版人工验收。
