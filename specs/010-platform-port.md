# SPEC-010 原生能力迁移（Platform）

- 阶段：M2/M3 前置（可与 M0 并行）
- 覆盖需求：FR-C1、FR-D3、FR-E2（钥匙串）、FR-E6、FR-E7、FR-E8 的底层能力
- 状态：InProgress（P1–P4 完成，待 Claude 验收）

## 范围

把 RoarkTools 的 ObjC 原生桥（`../RoarkTools/internal/platform/bridge_darwin.{h,m}`、`platform_darwin.go`、`monitor_darwin.go`）与布局算法（`../RoarkTools/internal/placement/`）用 **Swift** 重写到 `Platform/`（target `RoarkTPlatform`），并迁入 RoType 的 Fn 手势识别（`../RoType/Sources/RoTypeCore/VoiceFnGesture.swift`、`../RoType/Sources/RoTypeApp/VoiceFnShortcut.swift`）。只提供能力 API 与测试，不做 UI、不接业务流程。

## API（`Platform/`，全部 `public`）

| 文件 | 能力 | 来源 |
| --- | --- | --- |
| `Accessibility.swift` | `isTrusted(prompt:)`；前台应用（pid、bundle ID、名称） | `rt_ax_trusted`、`rt_frontmost` |
| `SecureInput.swift` | `isSecureInputActive()`；焦点元素是否为密码框（AXSecureTextField） | `rt_secure_input` |
| `SelectionReader.swift` | 通过 AX 读取选区文字与屏幕矩形；结果含状态（成功 / 空 / 不支持 / 无权限 / 安全输入） | `rt_ax_selection` |
| `Clipboard.swift` | `changeCount`；完整保存/恢复所有类型；读写字符串与 PNG；复制回退流程 `copySelectionFallback()`：保存 → 发送 ⌘C → 等待 changeCount 变化（超时）→ 读取 → 仅当 changeCount 仍是本次写入时恢复 | `rt_pb_*`、`rt_post_copy`、`platform_darwin.go` 中的回退逻辑 |
| `ScreenGeometry.swift` | 鼠标位置；点所在屏幕的 frame / visibleFrame / scale（统一为左上原点坐标） | `rt_mouse`、`rt_screen_*` |
| `Placement.swift` | 浮窗位置规则（见 `../RoarkTools/specs/006-ui-design-baseline.md` “浮窗位置规则”） | `internal/placement` |
| `OCR.swift` | Vision 本地识别（中英，`async`），返回文本与行框 | `rt_ocr` |
| `Keychain.swift` | set / get / delete / exists，服务名默认 `Identifiers.keychainService` | `rt_kc_*` |
| `GlobalHotkeys.swift` | 注册/注销全局快捷键（Carbon `RegisterEventHotKey`），注册失败返回冲突错误；`Shortcut` 来自 `RoarkTCore` | 新 |
| `FnKeyMonitor.swift` | 按住 / 松开 Fn 事件（flagsChanged），过滤与其他修饰键组合、短按 | RoType Fn 手势 |
| `Permissions.swift` | 辅助功能、屏幕录制、麦克风状态查询与打开对应系统设置页 | 新 |

## 规则

- Swift 6 严格并发；AppKit/AX 调用标注 `@MainActor` 或明确线程。
- 读取当前焦点内容前检查 Secure Input；处于 Secure Input 时返回明确状态，不尝试取词或复制回退（FR-E8）。OCR 处理已提供的图片、Keychain 读取自身密钥不受全局 Secure Input 门控（Claude 验收决定）；后续语音填入及缓存写入仍需保护。
- 不记录任何选中文字、剪贴板内容到日志。
- 文件所有权：只改 `Platform/`、`Tests/PlatformTests/`、`Package.swift` 中**新增** `RoarkTPlatformTests` 测试 target 一处、本规格。不改 `App/`、`Core/`（如需 Core 新类型，写在规格“问题”节由 Claude 处理）。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| P1 | Placement + ScreenGeometry + 单元测试（迁移 `placement_test.go` 的全部用例） | pi | 完成（Claude 已验收 2026-10-11） |
| P2 | Clipboard（含复制回退）、SecureInput、Accessibility、SelectionReader | pi | 完成（Claude 已验收 2026-10-11） |
| P3 | OCR（用 `../RoarkTools/internal/platform/testdata/ocr-sample.png` 复制到 `Tests/PlatformTests/Fixtures/` 做测试）、Keychain（测试用独立服务名并清理） | pi | 完成（Claude 已验收 2026-10-11） |
| P4 | GlobalHotkeys、FnKeyMonitor、Permissions | pi | 完成（Claude 已验收 2026-10-11） |
| P5 | 验收 | Claude | 未开始 |

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| Placement 用例全部通过 | `swift test` | 通过 | P1：原 placement_test.go 全部 4 个场景，另测 right/edge/panel 与上方副屏坐标；scripts/test.sh 通过（3 个 XCTest + 2 个 Core 测试）。超大浮窗由调用方限制尺寸。 |
| OCR 样例识别出预期文字 | `swift test` | 通过 | P3：迁入指定合成 PNG，真实 Vision 检出 OCR / 12345 / 本地识别，行框归一化且左上原点；非法图片测试通过；验收修正后直接使用公共 OCR() API，不再注入安全输入策略。 |
| Keychain 读写删 | `swift test` | 通过 | P3：随机独立服务名实测缺失、添加、更新、读取、exists、删除及重复删除，defer 清理；验收修正后直接使用公共 Keychain(service:) API，移除安全输入拒绝测试。 |
| 复制回退不覆盖用户新剪贴板 | 单元测试（模拟 changeCount）+ 手工 | 自动化通过；待人工验证 | P2：scripts/test.sh 通过（9 个 XCTest + 2 个 Core 测试）。模拟完整多条目多类型恢复、用户新复制不覆盖、安全输入拒绝、超时、来源切换、取消。 |
| 真实应用中 AX 取词 / 复制回退 | M3 接入后手工 | 待人工验证 | |
| `⌃1` 注册与冲突检测、Fn 按住/松开 | 手工 | 待人工验证 | P4 自动化仅覆盖默认键位映射、Fn 短按/长按/组合键/取消/安全输入状态机；真实注册、冲突及硬件事件没有验收。 |
| 权限状态及设置入口 | 手工 | 待人工验证 | API 直接查询 AX、屏幕录制和麦克风状态；无启动时自动授权。首次、拒绝、授予、撤销及设置页面跳转均需主 App 集成后验收。 |
| 全量自动化与签名构建 | scripts/test.sh；scripts/build.sh | 通过 | 2026-10-11，Apple Silicon，Swift 6.3.2，macOS SDK 26.5，部署目标 macOS 14：验收修正前 21 个 Platform XCTest + 2 个 Core 测试通过；现有脚本产出主 App / 翻译服务并通过签名校验。git diff --check 通过。未运行真实 macOS 14 设备验收。 |
| Claude 验收修正：OCR / Keychain 不受 Secure Input 门控 | scripts/test.sh；git diff --check | 通过 | 2026-10-11：移除两处门控、checkReadable 注入及两项拒绝测试；19 个 Platform XCTest + 2 个 Core 测试通过（真实 OCR 样例、独立钥匙串读写删与清理、既有复制回退安全测试）。本轮未重跑签名构建；真实应用、快捷键及 Fn 仍待人工验证。 |

## 问题

- P2：NSPasteboard 没有写入者身份或原子 compare-and-swap；复制回退把发送 ⌘C 后首次观察到的 changeCount 视为本次写入，后续变化则保留用户内容并报错。首次变化由外部写入、超时后的迟到复制、跨进程检查与恢复间的竞争无法仅靠 changeCount 完全排除，**已决定（Claude）**：保留现有 changeCount 竞争限制记录，不新增交互限制；真实应用仍在 M3 兼容矩阵中验收。
- P2：无法确认焦点元素是否受保护时保守拒绝读取；AX / 剪贴板内容不记录日志、不持久化。真实应用、密码框、终端 Secure Keyboard Entry 均待人工验证。
- P3：OCR 在后台执行，取消后丢弃结果（当前 Vision perform 完成后才能结束计算）；不请求网络、不写文件。OCR / Keychain 的自动化内容测试直接使用公共 API。
- P4：**已决定（Claude）**：Fn 按住阈值保留 180ms 默认值，后续可配置。只监听、不吞键；与系统听写/输入源切换的冲突处理仍在 M5 验收。长按期间的录音、模型和业务超时不在本规格内。
- P4：**已决定（Claude）**：快捷键按物理 ANSI 键位解释即可，Fn-only / 未支持键名明确报错；检查系统已启用的 symbolic hotkeys，并将 Carbon 重复注册错误映射为 conflict。其他应用自行拦截事件、非 ANSI 布局与动态系统设置变化仍需人工验收，不增加按当前布局字符注册。
- P4：AX / 屏幕录制预检只能区分 granted / notGranted；麦克风可区分 notDetermined / denied / restricted。更详细的引导状态需由 App 层管理。
- **已决定（Claude）**：OCR / Keychain 去掉 SecureInput.requireReadable()、checkReadable 注入及相关拒绝测试。Secure Input 是系统全局状态，其他应用的密码框或终端 Secure Keyboard Entry 可能长期开启，不应阻止读取自身密钥或识别已有图片。FR-E8 约束当前焦点内容的读取/写入；SelectionReader、Clipboard 复制回退以及后续语音填入、缓存写入保留保护。本次未修改取词及剪贴板实现。
- Claude 验收备注（2026-10-11）：OCR、Keychain 不受 Secure Input 门控（已修正，e888c1b）。`Clipboard.readString/readPNG` 仍门控；M4 实现“剪贴板图片作为输入”（FR-D7）时重新评估。
