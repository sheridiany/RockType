# RoarkT VoiceWorker

独立 Swift/MLX XPC 服务（macOS 14+、Apple Silicon）。依赖锁定在 `Package.resolved`；`scripts/build-voice-worker.sh` 用 Xcode 构建 Metal 资源、运行不加载模型的 MLX self-test，并签名 XPC bundle。

主 App 通过 `NSXPCConnection(serviceName: Identifiers.voiceWorkerID)` 连接。双向签名要求为 Team ID + 具体 identifier。协议源文件由 App 以符号链接引用；worker 的 Identifiers 链接到 Core 唯一来源。服务只接受本地模型目录与有上限的内存 PCM，不监听麦克风、不写音频或转写日志、不发起模型下载。取消、关闭自动准备或父连接失效时退出进程，释放 MLX 内存。

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
