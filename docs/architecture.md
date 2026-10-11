# RoarkT 技术架构

需求见 [PRD](prd.md)，决策见 [ADR-0001](adr/0001-swift-merged-product.md)、[ADR-0002](adr/0002-identifiers-license-shortcuts.md)。

## 进程

```
                 ┌──────────────────────────────┐
  用户按键 ──▶   │ RoarkT 输入法 (IMK, GPL)       │  候选窗 / 译文栏 / 模式提示
                 │ InputMethod/  librime          │
                 └───────┬──────────────▲─────────┘
                         │ XPC (translate, AI 改写)│ XPC (语音填入 ticket)
                         ▼              │
  ┌───────────────────────────┐   ┌─────┴──────────────────────────┐
  │ 翻译服务 (LaunchAgent)     │◀──│ RoarkT 主 App (菜单栏, MIT)      │
  │ Services/TranslationService│   │ App/ + Core/ + Platform/         │
  │ Apple Translation / AI / 静态│   │ 设置、引导、权限、划词、截图、AI   │
  └───────────────────────────┘   └─────┬──────────────────────────┘
                                         │ XPC / 子进程
                                   ┌─────▼──────────────┐
                                   │ 语音 worker (MLX)    │
                                   │ Services/VoiceWorker │
                                   └────────────────────┘
```

- **输入法**只做输入：按键、Rime、候选窗、译文栏。不申请任何隐私权限，不直接发网络请求。
- **主 App** 持有全部权限（辅助功能、屏幕录制、麦克风）与 AI 配置、钥匙串。默认 `LSUIElement`（无 Dock 图标）。
- **翻译服务**是统一翻译路由（FR-E1）。候选翻译与划词翻译都走它。AI 请求所需的配置由主 App 提供（XPC 下发，不落盘密钥），主 App 未运行时 AI 路径不可用、离线与静态路径照常。
- **语音 worker** 由主 App 启动；识别结果经输入法的 ticket 机制安全填入。

## 源码模块

| 目录 | SPM target / 产物 | 许可证 | 说明 |
| --- | --- | --- | --- |
| `Shared/XPCProtocol` | `RoarkTXPCProtocol`（ObjC 头） | MIT | 全部 XPC 协议与服务名。输入法也引用这里的头文件 |
| `Core` | `RoarkTCore` | MIT | 标识符、设置模型、快捷键默认值、翻译协议校验、操作模板、AI 客户端 |
| `Platform` | `RoarkTPlatform` | MIT | 取词、剪贴板、OCR、截图、钥匙串、权限、全局快捷键、Secure Input 检测 |
| `App` | `RoarkTApp` → `RoarkT.app` | MIT | 菜单栏主 App |
| `Services/TranslationService` | `RoarkTTranslationService` | MIT | 翻译 XPC 服务 |
| `Services/VoiceWorker` | 独立 SPM 包（MLX） | MIT | 语音识别 worker |
| `InputMethod` | Xcode 工程 → `RoarkT Input.app` | GPL v3 | Squirrel 修改 + librime/plum 子模块 |
| `Rime` | 资源 | 按来源 | 方案、词典、Lua |
| `Installer` | pkg 脚本 | MIT | 安装、卸载、LaunchAgent plist |

## 标识符（唯一来源：`Core/Identifiers.swift`，ObjC 侧：`Shared/XPCProtocol/include/RoarkTIdentifiers.h`）

| 用途 | 值 |
| --- | --- |
| Team ID | `DF7J2VBQD8` |
| 主 App | `com.roarkist.roarkt` |
| 输入法 Bundle | `com.roarkist.inputmethod.RoarkT` |
| 输入源：全拼 | `com.roarkist.inputmethod.RoarkT.pinyin` |
| 输入源：小鹤双拼 | `com.roarkist.inputmethod.RoarkT.flypy` |
| 翻译服务（Mach service / LaunchAgent label） | `com.roarkist.roarkt.translation` |
| 语音 worker | `com.roarkist.roarkt.voice` |
| 输入法语音填入端点 | `com.roarkist.inputmethod.RoarkT.dictation` |
| 设置目录 | `~/Library/Application Support/RoarkT/` |
| 钥匙串服务名 | `com.roarkist.roarkt.ai` |
| Rime 方案 ID | `roarkt`（全拼）、`roarkt_flypy`、`roarkt_en` |
| Rime 用户目录 | `~/Library/Rime`（方案名区分，不碰其他方案） |

## 安装位置（发布）

| 产物 | 位置 |
| --- | --- |
| `RoarkT.app` | `/Applications/` |
| `RoarkT Input.app` | `/Library/Input Methods/` |
| 翻译服务 | `RoarkT.app/Contents/Helpers/`，LaunchAgent `~/Library/LaunchAgents/com.roarkist.roarkt.translation.plist` |
| 语音 worker | `RoarkT.app/Contents/Helpers/` |

开发期输入法装到 `~/Library/Input Methods/`。

## XPC 鉴权

服务端用 `SecCode` 校验对端：`anchor apple generic and certificate leaf[subject.OU] = "DF7J2VBQD8" and identifier "<允许的 identifier>"`。每个接口声明允许的调用方：

| 接口 | 允许调用方 |
| --- | --- |
| `translateCandidate` / `cancel` | 输入法 |
| `translateText`（划词、截图） | 主 App |
| `configureAI`（下发 AI 配置） | 主 App |
| 语音填入 `capture` / `commit` / `cancel` | 主 App → 输入法 |

## 默认快捷键

| 动作 | 默认 |
| --- | --- |
| 语音：按住说话 | `Fn` |
| 截图 | `⌃1` |
| 翻译选区 | `⌃⌥T` |
| 总结选区 | `⌃⌥S` |
| 中英切换 | 轻按 Shift（输入法内） |
| 译文上屏 | Tab（输入法内） |
| 输入法内 AI | 待 M6 规格 |

## 构建

- SPM：`swift build`（Core、Platform、XPCProtocol、App、TranslationService、测试）。
- `scripts/build.sh` 把 SPM 产物组装为 `dist/RoarkT.app`（Info.plist 来自 `App/Info.plist`），嵌入翻译服务并签名；输入法与语音 worker 迁入后由同一脚本构建。
