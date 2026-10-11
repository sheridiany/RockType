# RockType 用户可见文案审计

2026-10-11 · SPEC-014 R6-UI。以本 worktree 合入 main 后的源码为基线；本表行号对应本次交付工作树，后续合并可能移动。只直接修改 Shell、设置、DesignSystem/通知职责内的文案；其他窗口建议未代为实施。

## 统一规则

- 产品显示名用 **RockType**；输入源用 **RockType Pinyin / RockType Shuangpin**。RoarkT 保留在模块、目录、Bundle ID 和本地化查找键中，不全局替换。
- 用户界面的 OCR 统一为 **文字识别**，本机执行写“本机文字识别”。截图是获取屏幕图片，贴图是悬浮图片；“复制图片”“复制文字”“复制文件路径”不能混称复制结果。技术 API、协议、模型名和提示词标签中的 OCR 不因术语审计机械改名。
- 安全输入用中文“安全输入”；主 App 在用户提示中用“RockType”，许可证角色用“主程序”。服务配置的首次标签保留“服务地址（Base URL）”“密钥（API Key）”，方便对照服务商控制台。
- 中文正文用全角逗号、句号、冒号、括号和“引号”。采用 macOS 控件常见的单字符省略号 **…**，不混用三个英文句点；状态进行中或打开后续界面时使用。快捷键、URL、格式名、代码与版本号保持原样。
- 按钮用动作、不加句号；短状态标签不强加句号；完整提示用句号。错误说明“哪一步没完成 + 可做的下一步”，不把未知原因断言成权限问题，不用“有错误！”“禁止加载”等泛化/命令式语气。
- 不把有限的本机识别声明扩大为整个窗口“绝不上传”；显式图片 AI 会发送图片与文字。状态码、协议值、动态状态判断和用户输入不做文案替换。

## 提取范围与限制

完整静态候选索引见 [copy-inventory.tsv](copy-inventory.tsv)：**3386 个字符串出现位置，152 个文件**。保留重复出现位置，便于逐窗口分发。包含 App（正式与 DEBUG 原型）、InputMethod/sources 与资源、本项目 Core/Platform/翻译服务及语音 worker 的受版本控制源文件；子模块、第三方框架与许可证文本不作为本产品文案修改对象。

提取器逐字符扫描字符串，跳过注释，处理转义、原始/多行字符串及嵌套插值；另外解析 xcstrings 的语言值/默认键和 plist 字符串。索引是保守的字面量全集，包含技术值、默认提示词和静态样本，不等于每行都会显示给用户。中文及 Text/Button/Notice/菜单/无障碍等调用候选有分类；下列问题逐项结合真实调用核对。

运行时用户输入、服务商名称/模型、服务器错误、系统本地化和插值生成文本无法静态穷举：这里只记录模板和来源，不收集真实内容。英文回退、本地化键与译文要一起检查，不能只搜索中文。DEBUG 内容单列在索引中，不将演示成功提示当作正式产品行为。

## 本轮已修（pi-ui）

位置以修改后的文件为准；“审计时文案”是改前文字，建议列已落实。只改显示字符串，不更改错误码、权限逻辑或重试条件。

| 文件:行 | 审计时文案 | 已采用文案 | 负责窗口 |
| --- | --- | --- | --- |
| [App/Shell/ShortcutReference.swift:36](../App/Shell/ShortcutReference.swift#L36) | 识别并复制 OCR 文字 | 识别并复制文字 | pi-ui |
| [App/Shell/ShortcutReference.swift:41](../App/Shell/ShortcutReference.swift#L41) | 另存、OCR、翻译、锁定、鼠标穿透及透明度 | 另存、文字识别、翻译、锁定、鼠标穿透及透明度 | pi-ui |
| [App/Shell/Permissions/PermissionCenter.swift:72](../App/Shell/Permissions/PermissionCenter.swift#L72) | 无法请求该权限，请打开系统设置；麦克风请求需主 App 配置用途说明。 | 无法申请权限。请在“系统设置”的“隐私与安全性”中检查 RockType 的权限。 | pi-ui |
| [App/Shell/InputSourceManager.swift:109](../App/Shell/InputSourceManager.swift#L109) | 验证服务不可用，请确认主 App 与翻译服务已安装并重试。 | 无法验证试打。请重新打开 RockType，然后重新开始验证。 | pi-ui |
| [App/Shell/TransientNoticeController.swift:15](../App/Shell/TransientNoticeController.swift#L15) | \(action.title) · 即将推出 | \(action.title)暂不可用。请重新打开 RockType 后重试。 | pi-ui |
| [App/Shell/ShellSettingsView.swift:340](../App/Shell/ShellSettingsView.swift#L340) | 主 App：MIT · 输入法：GPL v3 | 主程序：MIT · 输入法：GPL v3 | pi-ui |
| [App/Shell/LanguagePackModel.swift:13](../App/Shell/LanguagePackModel.swift#L13) | 简体中文 ↔ English 语言包已就绪。 | 简体中文与英语语言包已就绪。 | pi-ui |
| [App/Shell/LanguagePackModel.swift:15](../App/Shell/LanguagePackModel.swift#L15) | 系统暂不支持中英语言包，可使用静态词条，或配置 AI 后使用。 | 系统暂不支持中英语言包。候选翻译可使用本地词条，其他 AI 功能需先配置连接。 | pi-ui |
| [App/Shell/LanguagePackModel.swift:16](../App/Shell/LanguagePackModel.swift#L16) | 动态候选翻译需要 macOS 26。当前系统使用静态词条；AI 需另行配置并显式启用。 | 动态候选翻译需要 macOS 26。当前系统使用本地词条；输入法 AI 需配置连接并在设置中启用。 | pi-ui |
| [App/Surfaces/SettingsView.swift:202](../App/Surfaces/SettingsView.swift#L202) | 密码框或 Secure Input 开启时，不填入语音。 | 密码框或安全输入开启时，不填入语音。 | pi-ui |
| [App/Surfaces/SettingsView.swift:247](../App/Surfaces/SettingsView.swift#L247) | 框选后显示 OCR 入口 | 框选后显示文字识别入口 | pi-ui |
| [App/Surfaces/SettingsView.swift:398](../App/Surfaces/SettingsView.swift#L398) | 主 App 权限 | RockType 权限 | pi-ui |
| [App/Surfaces/SettingsView.swift:425](../App/Surfaces/SettingsView.swift#L425) | 密码框 / Secure Input | 密码框与安全输入 | pi-ui |
| [App/Surfaces/SettingsView.swift:447](../App/Surfaces/SettingsView.swift#L447) | 主 App：MIT · 输入法：GPL v3，按进程隔离。 | 主程序：MIT · 输入法：GPL v3 | pi-ui |
| [App/Surfaces/OperationTemplateSettings.swift:22](../App/Surfaces/OperationTemplateSettings.swift#L22) | 请选择有效的 SF Symbols 图标。 | 图标名称无效，请填写有效的 SF Symbols 名称。 | pi-ui |
| [App/Shell/ShellConnectionModel.swift:231](../App/Shell/ShellConnectionModel.swift#L231) | 中文输入与本地 OCR 仍可使用。 | 中文输入与本机文字识别仍可使用。 | pi-ui |
| [App/Shell/ShellConnectionModel.swift:236](../App/Shell/ShellConnectionModel.swift#L236) | Base URL | 服务地址（Base URL） | pi-ui |
| [App/Shell/ShellConnectionModel.swift:238](../App/Shell/ShellConnectionModel.swift#L238) | API Key | 密钥（API Key） | pi-ui |
| [App/Shell/ShellConnectionModel.swift:276](../App/Shell/ShellConnectionModel.swift#L276) | 设置 API Key | 设置密钥 | pi-ui |
| [App/Shell/ShellConnectionModel.swift:277](../App/Shell/ShellConnectionModel.swift#L277) | API Key | 密钥 | pi-ui |
| [App/Shell/ShellConnectionModel.swift:123](../App/Shell/ShellConnectionModel.swift#L123) | 密钥不能为空。 | 请填写密钥。 | pi-ui |
| [App/Shell/SettingsSection.swift:27](../App/Shell/SettingsSection.swift#L27) | 一个服务商连接，供翻译、总结与润色使用。 | 管理服务商、模型和连接测试。 | pi-ui |
| [App/Shell/ShellSettingsView.swift:208](../App/Shell/ShellSettingsView.swift#L208) | 开启候选 AI 后，候选文字可能发送到所配置的服务商。 | 主动触发输入法 AI 时，当前文字会发送到所配置的服务商。 | pi-ui |

## 交接清单（落实状态见备注）

R7-UI 已落实下表 InputMethod/ 的 14 项，余下 22 项仍待分发（Voice 本轮未改）。文案列保留 R6 审计原文，已落实条目的链接更新到现资源值；完整 R6 字符串索引保留为当时快照。

按 SPEC-014 分工建议负责窗口，共享代码由主控确认归属。同一模板重复出现的地方分别保留；先统一生产入口，再同步对应 DEBUG 原型。

| 文件:行 | 现文案 | 建议 | 负责窗口 | 原因/注意事项 |
| --- | --- | --- | --- | --- | --- |
| [App/Features/ResultWindow/LiveResultWindowView.swift:129](../App/Features/ResultWindow/LiveResultWindowView.swift#L129) | 截图 OCR | 截图文字识别 | pi-platform | 术语；若属于提示词，先确认是否在界面展示，再修改，保留协议/标识符 |
| [App/Features/Screenshot/CaptureCanvas.swift:246](../App/Features/Screenshot/CaptureCanvas.swift#L246) | 截图：拖动框选，单击选窗口，双击选区或 ↩ 复制，C 复制颜色，⇧C 复制 OCR，⌘S 另存为，⌥方向键调整左上边，⌘方向键调整右下边，⇧↩ 保存路径，R 恢复，P 贴图，Esc 取消 | 截图：拖动框选，单击选窗口，双击选区或 ↩ 复制，C 复制颜色，⇧C 识别并复制文字，⌘S 另存为，⌥方向键调整左上边，⌘方向键调整右下边，⇧↩ 保存路径，R 恢复，P 贴图，Esc 取消 | pi-xpc | 术语；若属于提示词，先确认是否在界面展示，再修改，保留协议/标识符 |
| [App/Features/Screenshot/CaptureCanvas.swift:298](../App/Features/Screenshot/CaptureCanvas.swift#L298) | \(Int(pixels.width)) × \(Int(pixels.height)) · 双击/↩ 复制 · ⌘S 另存 · ⇧C OCR · ⌥ 左/上边 · ⌘ 右/下边 | \(Int(pixels.width)) × \(Int(pixels.height)) · 双击/↩ 复制 · ⌘S 另存 · ⇧C 文字识别 · ⌥ 左/上边 · ⌘ 右/下边 | pi-xpc | 术语；若属于提示词，先确认是否在界面展示，再修改，保留协议/标识符 |
| [App/Features/Screenshot/CaptureToolbar.swift:31](../App/Features/Screenshot/CaptureToolbar.swift#L31) | 预览、OCR、翻译与保存 | 预览、文字识别、翻译与保存 | pi-xpc | 术语；若属于提示词，先确认是否在界面展示，再修改，保留协议/标识符 |
| [App/Features/Screenshot/CaptureToolbar.swift:33](../App/Features/Screenshot/CaptureToolbar.swift#L33) | 复制 ↩ / ⌘C · 另存为 ⌘S · 保存路径 ⇧↩ · OCR ⇧C · P 贴图 | 复制 ↩ / ⌘C · 另存为 ⌘S · 保存路径 ⇧↩ · 文字识别 ⇧C · P 贴图 | pi-xpc | 术语；若属于提示词，先确认是否在界面展示，再修改，保留协议/标识符 |
| [App/Features/Screenshot/PinnedImagePanel.swift:293](../App/Features/Screenshot/PinnedImagePanel.swift#L293) | 复制 OCR 文字    ⇧C | 识别并复制文字    ⇧C | pi-surfaces | 术语；若属于提示词，先确认是否在界面展示，再修改，保留协议/标识符  **收尾已落实（仅显示文案）** |
| [App/Features/Screenshot/ScreenshotPreviewContent.swift:63](../App/Features/Screenshot/ScreenshotPreviewContent.swift#L63) | 本机 OCR | 本机文字识别 | pi-surfaces | 术语；若属于提示词，先确认是否在界面展示，再修改，保留协议/标识符  **收尾已落实（仅显示文案）** |
| [App/Features/Screenshot/ScreenshotPreviewContent.swift:215](../App/Features/Screenshot/ScreenshotPreviewContent.swift#L215) | 点击识别文字。OCR 在本机运行，图片不会上传。 | 点击识别文字。文字识别在本机运行，图片不会上传。 | pi-surfaces | 术语；若属于提示词，先确认是否在界面展示，再修改，保留协议/标识符  **收尾已落实（仅显示文案）** |
| [App/Features/Screenshot/ScreenshotSession.swift:147](../App/Features/Screenshot/ScreenshotSession.swift#L147) | 截图 OCR | 截图文字识别 | pi-xpc | 术语；若属于提示词，先确认是否在界面展示，再修改，保留协议/标识符 |
| [App/Features/Screenshot/ScreenshotTranslation.swift:37](../App/Features/Screenshot/ScreenshotTranslation.swift#L37) | 截图 OCR | 截图文字识别 | pi-surfaces | 术语；若属于提示词，先确认是否在界面展示，再修改，保留协议/标识符  **收尾已落实（仅显示文案）** |
| [App/Features/Screenshot/ScreenshotVisualAI.swift:166](../App/Features/Screenshot/ScreenshotVisualAI.swift#L166) | 请根据已完成的图片文字结果回答问题。你无法查看原图或原始 OCR；需要细节时请说明并请用户重新打开图片。 | 请根据已完成的图片文字结果回答问题。你无法查看原图或原始识别文字；需要细节时请说明并请用户重新打开图片。 | pi-surfaces | 术语；若属于提示词，先确认是否在界面展示，再修改，保留协议/标识符  **已核对：此项仅为模型提示词，本轮按显示文案范围保留** |
| [App/Features/Screenshot/ScreenshotVisualAI.swift:171](../App/Features/Screenshot/ScreenshotVisualAI.swift#L171) | ：追问仅基于已完成的文字结果；原图和 OCR 原文不保留在对话中。 | ：追问仅基于已完成的文字结果；原图和识别原文不保留在对话中。 | pi-surfaces | 术语；若属于提示词，先确认是否在界面展示，再修改，保留协议/标识符  **收尾已落实（仅显示文案）** |
| [InputMethod/resources/Localizable.xcstrings:33](../InputMethod/resources/Localizable.xcstrings#L33) | 检查新版本... | 检查更新… | pi-ime | 中文省略号、与关于页动作同名；只改译文，保留本地化键；**R7-UI 已落实** |
| [InputMethod/resources/Localizable.xcstrings:39](../InputMethod/resources/Localizable.xcstrings#L39) | 檢查新版本... | 檢查更新… | pi-ime | 繁体同规则；**R7-UI 已落实** |
| [InputMethod/resources/Localizable.xcstrings:161](../InputMethod/resources/Localizable.xcstrings#L161) | 日志... | 打开日志文件夹… | pi-ime | 说明打开的对象；不用三个英文句点；**R7-UI 已落实** |
| [InputMethod/resources/Localizable.xcstrings:167](../InputMethod/resources/Localizable.xcstrings#L167) | 日誌... | 開啟日誌資料夾… | pi-ime | 繁体同规则；**R7-UI 已落实** |
| [InputMethod/resources/Localizable.xcstrings:207](../InputMethod/resources/Localizable.xcstrings#L207) | 用户设定... | 输入法配置文件夹… | pi-ime | 实际 openRimeFolder，避免与 RockType 设置窗口混淆；**R7-UI 已落实** |
| [InputMethod/resources/Localizable.xcstrings:213](../InputMethod/resources/Localizable.xcstrings#L213) | 用戶設定 | 輸入法設定資料夾… | pi-ime | 实际打开目录；**R7-UI 已落实** |
| [InputMethod/resources/Localizable.xcstrings:184](../InputMethod/resources/Localizable.xcstrings#L184) | 在线文档... | 在线文档… | pi-ime | 中文省略号；**R7-UI 已落实** |
| [InputMethod/resources/Localizable.xcstrings:190](../InputMethod/resources/Localizable.xcstrings#L190) | 在線文檔... | 線上文件… | pi-ime | 繁体术语与省略号；**R7-UI 已落实** |
| [InputMethod/resources/Localizable.xcstrings:72](../InputMethod/resources/Localizable.xcstrings#L72) | 有错误！请查看日志 | 输入法部署未完成，请打开日志文件夹查看详情后重试。 | pi-ime | 移除泛化惊叹；说明失败动作与下一步；**R7-UI 已落实** |
| [InputMethod/resources/Localizable.xcstrings:78](../InputMethod/resources/Localizable.xcstrings#L78) | 有錯誤！請查看日誌 | 輸入法部署未完成，請開啟日誌資料夾查看詳情後重試。 | pi-ime | 繁体同规则；**R7-UI 已落实** |
| [InputMethod/resources/Localizable.xcstrings:110](../InputMethod/resources/Localizable.xcstrings#L110) | Squirrel is ready. | RockType is ready. | pi-ime | 英文通知仍有来源项目品牌；不是修改本地化查找键；**R7-UI 已落实** |
| [InputMethod/resources/InfoPlist.xcstrings:80](../InputMethod/resources/InfoPlist.xcstrings#L80) | RockType | RockType Pinyin | pi-ime | 全拼输入源名称应与设置指引一致；保留 identifier；**R7-UI 已落实** |
| [InputMethod/resources/InfoPlist.xcstrings:86](../InputMethod/resources/InfoPlist.xcstrings#L86) | RockType | RockType Pinyin | pi-ime | 全拼输入源名称应与设置指引一致；保留 identifier；**R7-UI 已落实** |
| [InputMethod/resources/InfoPlist.xcstrings:92](../InputMethod/resources/InfoPlist.xcstrings#L92) | RockType | RockType Pinyin | pi-ime | 全拼输入源名称应与设置指引一致；保留 identifier；**R7-UI 已落实** |
| [Core/Translation/DynamicTranslationProtocol.swift:48](../Core/Translation/DynamicTranslationProtocol.swift#L48) | 翻译权限校验失败，请完成输入法升级 | 无法验证翻译服务身份，请重新安装与输入法匹配的 RockType 版本 | pi-platform + pi-ime | 身份校验不等于存在可升级版本；保留错误码 |
| [App/Features/Screenshot/ScreenshotCoordinator.swift:183](../App/Features/Screenshot/ScreenshotCoordinator.swift#L183) | PNG 已保存，但路径复制失败。 | PNG 已保存，但路径未复制。请到截图保存目录查看。 | pi-xpc | 部分成功，给出找到文件的下一步，不建议重复保存 |
| [App/Features/Screenshot/ScreenshotImportController.swift:36](../App/Features/Screenshot/ScreenshotImportController.swift#L36) | 无法读取拖入的图片。 | 无法读取拖入的图片，请重新拖入或通过“批量识别…”选择文件。 | pi-surfaces | 提供同界面的实际替代入口  **收尾已落实（仅显示文案）** |
| [App/Features/Voice/VoiceModelStore.swift:10](../App/Features/Voice/VoiceModelStore.swift#L10) | 模型仅在点击下载后获取，每个文件均校验 SHA-256。 | 点击下载后才获取模型，并检查文件是否完整。 | pi-ime | 面向用户说明校验目的；算法可留诊断信息 |
| [App/Features/Voice/VoiceModelStore.swift:88](../App/Features/Voice/VoiceModelStore.swift#L88) | 下载完成，SHA-256 校验通过。 | 下载完成，文件校验通过。 | pi-ime | 完成状态简短 |
| [App/Features/Voice/VoiceModelStore.swift:95](../App/Features/Voice/VoiceModelStore.swift#L95) | 模型校验失败，禁止加载；请重新下载。 | 模型文件校验未通过，请重新下载后再使用。 | pi-ime | 移除命令式措辞，保留安全限制 |
| [App/Features/Update/UpdateController.swift:27](../App/Features/Update/UpdateController.swift#L27) | 此版本尚未配置更新来源，请从官方发布页下载新版本。 | 此版本尚未配置更新来源，暂时无法检查更新。 | 分发负责人 | 当前没有可点的官方发布页，避免让用户寻找未提供的地址 |
| [App/Features/Operations/AIProviderSettingsView.swift:46](../App/Features/Operations/AIProviderSettingsView.swift#L46) | 仅在没有生成正文且出现临时故障时，使用你填写的同一服务商备用模型。可填写 claude/claude-haiku-5-5；不会自动添加或跨服务商发送。图片仍需单独验证能力。 | 仅在未生成正文且遇到临时故障时，尝试同一服务商的备用模型。请填写该服务商支持的模型名称；图片能力需单独验证。 | pi-platform | 避免把特定模型示例写成通用建议；保留不跨服务商的隐私边界 |
| [docs/features.md:20](../docs/features.md#L20) | 输入法内 AI 的设置默认值是 ⌥Tab，但触发链尚未接通 | 按已合入的 R3-IME 更新：启用后 ⌥Tab 循环改写/润色/翻译，真实试打待人工验证 | pi-ime + pi-ui | R5 成文后实现已变更，手册需由实现窗口确认同步 |
| [docs/features.md:120](../docs/features.md#L120) | 当前代码为单个默认连接，多 Provider 管理尚未完成。 | 按已合入的多服务商与任务路由实现更新手册，并保留人工验收状态 | pi-platform + pi-ui | R5 成文后实现已变更；此轮不凭旧手册改产品行为 |

## 保留与验收

- “已取消”“未授权”“未配置”等简短状态保留；不强迫每个小标签重复操作说明。SF Symbols、PNG/JPEG、AI 和语言/模型品牌保留正确名称。
- 输入法紧凑面板与工具栏替换“文字识别”后需验证宽度；无障碍标签可使用完整名称，不能用视觉截断后的缩写代替。
- 本轮不修改外部窗口源码/本地化资源，不自动分发消息。后续负责窗口修订时更新文案断言与深浅色/长文本图，保护动态插值和错误类别。
- 自动化、构建与离屏结果见 [R6-UI 证据](../specs/evidence/014-R6-UI.md)；真实权限弹窗、系统语言切换、VoiceOver 和全部错误链仍待人工验收。


## pi-platform · R4-AI 落实（2026-10-11）

上述分发表中的四项已落实：结果浮窗取词方式改为“截图文字识别”；Core 身份校验失败改为说明重新安装匹配版本，错误码不变；备用模型说明移除特定模型通用建议，保留同服务商和图片单独验证边界；功能手册更新多服务商、任务路由及自定义动作的实际行为。原始审计建议表保留，其他负责窗口的条目状态不变。验证与人工边界见 [R4-AI 证据](../specs/evidence/014-R4-AI.md)。
