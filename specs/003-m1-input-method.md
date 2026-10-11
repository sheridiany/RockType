# SPEC-003 输入法与候选翻译（M1）

- 阶段：M1
- 覆盖需求：FR-A1–A11、FR-E1（离线与静态路径）、FR-E8（输入法部分）、NFR-2
- 状态：InProgress（I-1/I-2 已实现；I-3 与视觉验收待完成）
- 依赖：SPEC-001（输入法迁移已完成）；输入法视觉按用户指定的旧产品基线恢复，覆盖原 D0 U4 要求。

## 范围

输入法功能已由 T3 从 RoType 迁入。当前按用户决定恢复旧产品候选窗、译文栏、状态提示与图标设计，同时保留 I-1/I-2 行为修正与测试。用户可见产品名为 RockType，内部标识仍为 RoarkT / roarkt。下方 D0 与早期实施记录为历史证据，现行基线见“RoType 视觉恢复”。

## 原视觉对齐（已被用户决定覆盖；以 `App/Surfaces/CandidateView.swift`、`InputModeView.swift` 与 `dist/gallery/candidate-*`、`input-*` 为准）

- 候选窗：拼音行 + 横排 5 候选；高亮项强调色底；序号弱化；字号、间距、圆角、阴影取 D0 Tokens 数值（输入法不能链接 App 代码，在 `InputMethod/sources` 内用常量复刻，并在注释中注明对应 Token 名）。
- 译文栏：候选窗下方独立卡片；左侧图标 + 小标题（候选翻译 / 静态词条 / AI 改写 / 翻译中 / 不可用）+ 译文；右侧 `Tab` 提示；长译文单行截断。
- 输入模式提示：中 / 英 / 方案名胶囊，出现与消失动效按 Tokens.Motion，遵守减少动态效果。
- 浅色/深色跟随系统；多显示器、屏幕边缘、全屏应用位置正确。
- 截图证据：在 TextEdit 中真实输入后的屏幕截图（需屏幕录制权限，由用户协助）或离屏渲染 `SquirrelPanel` 的 PNG，与 Gallery 对照。

## 能力复核（自动化为主，真实键盘项标“待人工验证”）

| 需求 | 复核方式 |
| --- | --- |
| A1 全拼、词频学习、首启自动部署 | `scripts/test-rime.sh` 扩展：部署后用 `rime_api` 测试程序（或 RoType 的 `test-candidate-session.sh` 迁移版）输入样例，断言首选 |
| A2 小鹤双拼 | 同上，双拼编码样例 |
| A3 模糊音、简拼、纠错 | 同上，样例集 |
| A4 Shift 切换 | 迁移 RoType `test-modifier-keys.sh` 中可自动化部分 |
| A5 英文短语单引号 | 样例断言上屏文本 |
| A6/A7 候选翻译 generation 隔离 | 已有服务测试 + 输入法侧 session 测试 |
| A8 静态词条 | 断开服务时的译文栏状态测试 |
| A10 学习菜单 | 删词后重新部署仍生效 |

迁移 RoType 中相关脚本时一律改名，删除升级/退休相关用例。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| I-1 | 候选窗、译文栏、模式提示恢复旧产品视觉 | pi-ime | 恢复完成、离屏对照通过；待 Claude 视觉/人工验收 |
| I-2 | 能力复核测试迁移与补齐，接入 `scripts/test.sh` | pi-ime | 自动化通过，已接入统一测试入口 |
| I-3 | 真实打字验收 | 用户 + Claude | 未开始 |

**文件所有权**：`InputMethod/sources` 中候选窗、面板、主题相关文件，`InputMethod/scripts`、`scripts/test-*.sh` 新增项、`Tests/`。另一个 agent（pi-ui）正在 `InputMethod/sources` 中做设置同步（读取 settings.json、redeploy 通知），避免修改其涉及的文件；如必须修改同一文件，改动集中并在汇报中列出。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 恢复旧产品视觉（浅/深） | 生产面板与旧源码离屏 PNG 比较 | 10 组逐像素一致；菜单图标与旧安装版一致；待 Claude 人工验收 | `.build/ime-evidence/`，`scripts/test-ime.sh` 可重建当前图 |
| A1–A5、A8、A10 自动化 | `scripts/test.sh` | 通过（下述自动化范围） | `Tests/InputMethodTests/`；首启 IMK、真实停服与菜单点击待人工验证 |
| A6/A7 generation、取消与 Secure Input | 实际 session/client 源码 + 假 XPC transport；真实 Rime 提交 | 通过 | `SessionChecks.swift`、`RimeChecks.swift` |
| 真实打字：全拼、双拼、Shift、英文短语、Tab 上屏译文 | 用户 | 待人工验证 | |
| 打字延迟不受翻译服务影响（NFR-2） | 停掉翻译服务后试打 | 待人工验证 | |

## 进度与验收证据

### I-1 实施证据（2026-10-11）

- 已实现：生产候选窗改为 D0 横排五候选、420pt 卡片、12pt 内边距、36pt 行高、7pt 高亮圆角；译文独立卡片、图标/标题/Tab、单行截断；中英提示改为 D0 胶囊，140ms 出现/80ms 消失并遵守减少动态效果。方案/其他状态提示使用同一胶囊视觉。全部展示代码留在 GPL 输入法内，未链接 App。
- 输入变化立即隐藏旧译文；加载状态不展示 session 中保留的旧文字。保留候选点击、悬停、滚轮翻页、学习菜单入口，不改控制器或设置同步文件。
- 通过：输入法 Release `xcodebuild`；合并 main 后的 `scripts/test.sh`（124 个 Swift Testing 测试、现有部署/AppShell 检查及新增输入法检查）。
- 通过：生产 `--preview-candidates` 离屏导出浅/深色候选与译文 PNG，位于 `.build/ime-evidence/`（可重建，不提交生成物）；查看浅深色候选、译文、模式提示及长译文截断，颜色、间距、布局与 D0 源码数值对照。仍待 Claude 视觉验收。
- 未验证：真实 IMK 焦点/点击、实际多显示器/全屏、减少动态效果开关实机体验。
- 边界：现有 session/响应没有“静态/动态/AI”来源字段；面板不猜测来源，成功统一标题“候选翻译”。若要求可靠显示“静态词条”，需要控制器/session 所有者增加来源字段；AI 是 M6 能力。本次未越权修改这些文件。

### I-2 实施证据（2026-10-11）

- `Tests/InputMethodTests/SessionChecks.swift`：迁移实际 session/client 行为测试，覆盖 selection/generation、迟到成功/失败、取消、retry、Tab 判定、静态精确匹配/未命中、双向词条、Secure Input 下无请求/无缓存、缓存容量/过期/焦点边界。移除旧接口、旧主题与旧验证窗口用例。异步回复改用主队列 FIFO 标记等待，消除旧用例固定 10ms 等待的不稳定性；不依赖用户当前 Secure Input 状态。
- `ModifierChecks.swift`：左右 Shift、合并 flagsChanged、缺 keycode、普通按键映射。
- `RimeChecks.swift`：用 Swift 直接调用当前 checkout 的 librime bool API 和 Lua 插件；从工厂资源部署到临时目录。全拼/小鹤首选、模糊音、全拼简拼/拼写及按键纠错、五候选页、左右 Shift 持续英文/Shift+字母、已确认前缀 + 原始后缀提交、英文补全/单引号短语/屏蔽词、候选与翻页身份校验、当前译文提交均通过。
- 学习测试使用多个独立进程：先验证工厂首选，再学习另一词，重启和切换全拼/双拼后首选保留；忘记学习记录后重新部署，两个方案恢复原首选且工厂词仍存在。只操作临时用户数据库，不读写真实 `~/Library/Rime`。
- `PanelChecks.swift`：直接编译生产面板，只有 controller/configuration 边界使用测试替身。验证候选可访问性点击、非激活窗口、加载时旧文字不可见/不可提交、不可用状态、长译文固定高度、失效后隐藏、负坐标显示器与边缘布局。导出 18 张浅/深色候选、译文五种状态（含服务不可用时静态回退）、中英/方案提示 PNG。
- 新入口 `scripts/test-ime.sh`、`scripts/test-rime-capabilities.sh` 已接入 `scripts/test.sh`。测试全部位于 `Tests/InputMethodTests/`；采用仓库已有 standalone Swift 检查方式，不新增 Package、不把 GPL 输入法链接到 MIT App target。`scripts/test.sh` 是为完成 I-2 的接入要求所作的两行修改，未修改既有 `scripts/test-rime.sh`。
- 通过：`scripts/test-ime.sh`；`scripts/test-rime-capabilities.sh`；`scripts/test.sh`；输入法 Release `xcodebuild`。未运行整套 `scripts/build.sh`、签名/安装/注册、真实停服打字性能测试。
- 集成：按用户后续指令将 `main`（包含 pi-ui 偏好同步）合入本分支，无冲突。保留 `RoarkTInputSettings.swift`、`SquirrelApplicationDelegate.swift`、`SquirrelInputController.swift`、Xcode 工程的全部上游修改；未额外编辑这些文件。新面板继续使用同一 controller 调用入口，中英提示开关和翻译开关仍由 controller 管理；真实开关体验待人工验证。

## 问题与人工验收

1. 历史 D0 标题问题（恢复旧版无标题译文栏后不再阻塞本任务）：session/服务协议目前不提供静态/动态/AI 来源，成功统一“候选翻译”。可靠“静态词条”标题需要该模块所有者扩展来源信息；不可依据译文恰好等于词典文本猜测来源。
2. Claude 按旧版基线进行真实安装视觉验收；离屏像素不包含系统窗口投影，不能代替实际菜单栏、IMK 焦点与屏幕定位验收。
3. I-3：干净账户首启自动部署、TextEdit/浏览器/编辑器真实全拼/双拼/Shift/Tab/学习菜单、偏好开关、全屏/多屏/边缘、不抢焦点、减少动态效果、VoiceOver 均待人工验证。自动化 serviceUnavailable 注入不等于真实杀掉翻译服务后试打；NFR-2 延迟仍待人工实测。
4. 规格复核范围的 A10“忘记学习记录”已验证；PRD 中置顶/降权并非现有菜单能力，本规格“不新增功能”下未扩展，不能据此宣称整个 FR-A10 已验收。

### 最新 main 与本机环境规则（2026-10-11）

- 按 Claude 第二次通知合并 `main@7245678`，无冲突；已完整读取新增“本机环境”约定。
- 合并后再次执行 `scripts/test.sh`，124 个 Swift Testing 测试、Rime 部署/能力、session/修饰键/面板、AppShell 检查通过。
- 规则生效后不从 worktree 启动输入法，不运行安装/卸载/注册、不加载 LaunchAgent。本任务从未安装、注册输入法或加载 LaunchAgent；早期预览进程已退出。
- 后续图片复现仅运行 `scripts/test-ime.sh` 的独立测试程序：编译实际面板，但不创建 IMK server、不访问用户 Rime 目录。安装版验证统一由 Claude 从 main 执行。

## RoType 视觉恢复

用户明确指定旧产品视觉为输入法的新验收基线，优先于本规格原 I-1/D0 视觉要求；I-1/I-2 的行为修正继续保留。旧源码实际只读路径为主仓库同级 `RoType`（本 worktree 中为 `../../RoType`）。

### 任务与验收证据

- [x] 菜单图标：迁移原 22×16pt、4.5pt 圆角、透明 R 镂空生成器与像素测试、SystemRendererProbe、截图比较工具；两输入源共六个图标键改为 `roarktMenuTemplate.pdf`；构建在签名前生成 Bundle 资源。
- 图标验证：`scripts/test.sh` 通过（真实退出码 0）；系统 renderer 输出 44×32px / 22×16pt，R 字高 8pt。PNG：`.build/ime-evidence/menu-icon-system.png`。安装后真实系统菜单仍待 Claude 验证。
- [x] 恢复中英圆形提示、候选窗/译文栏/方案提示与旧配色。
- [x] 完成逐文件资源盘点与离屏对照；最终合并后构建结果见下方。

- 面板恢复验证：`scripts/test.sh` 真实退出码 0；完整 `scripts/build.sh` 真实退出码 0（含签名与 worker XPC 冒烟，未启动输入法）。恢复原 SquirrelPanel/SquirrelTheme/SquirrelView 路径，移除 D0 固定宽度、卡片标题/图标与胶囊。额外保留候选可访问性动作、不可激活窗口、输入变化隐藏旧译文、加载态隐藏旧文字。输入模式计时器替换/1.1 秒消失/按键路径隐藏与有效屏幕边缘测试通过。
- 原源码离屏对照：在临时目录编译只读旧源码（仅重命名与 Swift 6 隔离适配），使用相同样例/主题导出 `.build/ime-evidence/reference/`；浅/深候选、就绪译文、中文圆形、英文圆形、方案提示共 10 对 PNG 逐像素比较，差异均为 0。记录 `.build/ime-evidence/reference-comparison.txt`。
- 配色核对：当前 `InputMethod/data/squirrel.yaml` 已与旧源码仅有产品/配色名称差异，末尾不存在 D0 覆盖段；安装旧版的 style/配色也相同，只少一些 app_options。不更改该文件、词库或用户数据。


### 逐文件恢复清单

比较对象：只读 `../../RoType/Squirrel/sources` 的全部 18 个文件，以及两边 `resources`、`Assets.xcassets`、`Rime.icon`、`data/squirrel.yaml`；同时读取已安装旧版的菜单 PDF 与 SharedSupport 配色。下表逐项记录，不把架构差异当成视觉缺失重新引入。

| 当前文件 | 对照与处理 |
| --- | --- |
| `SquirrelPanel.swift` | 恢复原 SquirrelView/TextKit 排版、自然宽度、16pt 候选/12pt 编号、评论、拼音选区、横竖排、鼠标/滚轮/分页、方案与其他选项状态消息。额外保留 I-1 输入变化即隐藏旧译文和不可激活/可访问性行为。 |
| `SquirrelTheme.swift` | 与旧版视觉逻辑一致；唯一差异是 Swift 6 兼容的 defaultFont 计算属性，保留。 |
| `SquirrelView.swift` | 原背景、高亮路径、圆角、分页箭头绘制本已一致；恢复到生产调用路径，并把 I-1 候选可访问性点击绑定到原文本布局。 |
| `RoarkTTranslationPanel.swift` | 恢复主题色文字、原 Tab 色块、最小 300pt 宽/34pt 高、3pt 间距、长文本换行、失败/重试的原样式；旧版没有左侧翻译图标/来源标题，移除 D0 新增图标与标题。保留加载不显示旧文字与禁用提交、VoiceOver 按钮动作。 |
| `RoarkTInputModePanel.swift` | 恢复 40pt 画布、34pt 米白“中”/橙色“EN”圆、1.3pt 描边、20/15pt 字号、1.1 秒计时、立即隐藏、不接收鼠标、不抢焦点。旧版原生绘制无动画，不保留 D0 胶囊/动效。可选 PNG 入口改名为 roarktModeZh/En；旧源码和安装包都未提供该 PNG。 |
| `RoarkTCandidateLearningMenu.swift` | 改名后内容完全一致，保留“忘记…学习记录”、禁用态与提示；测试触发 action 并验证禁用状态。旧版没有置顶/降权图标或菜单项，未凭空新增。 |
| `RoarkTCandidateTranslationSession.swift` | 改名后内容一致；未改 generation、取消、静态回退、Tab 策略。 |
| `RoarkTTranslationClient.swift` | 差异为新版签名 XPC、连接代次与输入证据节流；无视觉绘制，不回滚。 |
| `RoarkTVoiceServer.swift` | 两边均无绘制/HUD；新版将权限和录音归主 App、强化 Secure Input 与 XPC，保持。旧语音展示实际位于 MIT 主 App，已另行恢复，见下表后说明。 |
| `RoarkTProcessTrust.swift` | 仅签名/身份与旧升级兼容删除，无视觉差异，保持。 |
| `SquirrelInputController.swift` | 中英切换/按键隐藏模式面板的调用完整；新版偏好同步、两输入源、Swift 6 与 Secure Input 保留。部署/同步/日志/配置目录菜单仍在，设置项使用 RockType 主 App。旧产品专属项目主页链接未恢复：当前产品未提供项目 URL，不能指向旧项目或编造地址。 |
| `SquirrelApplicationDelegate.swift` | 方案/选项/部署通知展示调用保留；差异为主线程、设置同步、权限归属与旧通知桥删除，保持。 |
| `Main.swift` | 保留预览入口但本任务未运行输入法进程；其余差异为旧数据迁移和分布式通知删除，无视觉资源缺失。 |
| `InputSource.swift` | 新增独立全拼/双拼 ID 与注册验证，保持；显示名来自 Info.plist。 |
| `SquirrelConfig.swift` | 内容一致；离屏测试直接使用真实 YAML 解析器，未用 D0 常量或假主题。 |
| `MacOSKeyCodes.swift` | 内容一致，无视觉差异。 |
| `BridgingFunctions.swift` | 内容一致，无视觉差异。 |
| `Squirrel-Bridging-Header.h` | 仅共享协议 include 路径差异，无视觉差异。 |
| `RoarkTInputSettings.swift`（新增） | 新版设置同步，无旧版对应文件，保留偏好开关与部署行为。 |

源目录共 18 个旧文件、当前新增 1 个设置文件（按实际目录枚举；文件逐项列于上表）。

| 资源/其他展示 | 对照与处理 |
| --- | --- |
| `resources/Info.plist` | 两个输入源六个图标键均指向生成的 `roarktMenuTemplate.pdf`；可见名 RockType Pinyin / RockType Shuangpin；内部 ID 不变。旧麦克风声明/权限归属不回迁。构建产物的 CFBundleIconName/File 均为 Rime，指向已有应用图标。 |
| `resources/InfoPlist.xcstrings` | 仅产品/输入源名称变更与新增双拼名称；保留 main 的英文 RockType 名称。 |
| `resources/Localizable.xcstrings` | 仅产品名替换，其余菜单/部署通知翻译一致。 |
| `resources/Squirrel.entitlements` | 旧录音 entitlement 已移至主 App，输入法不申请麦克风，非视觉缺失。 |
| `resources/rime.pdf` | 原文件仍作上游资源保留，但两个输入源均不再引用它。 |
| `Assets.xcassets` | 根 Contents、图标 Contents、十张 PNG 与旧版逐字节一致，无需复制。 |
| `Rime.icon` | icon.json 与 Assets/logo.svg 均逐字节一致，无需复制。 |
| `data/squirrel.yaml` | 除名称外与旧源码相同；旧安装版 style 和配色相同。不存在待删除的 D0 末尾覆盖段。当前相对 main 零改动。 |
| `scripts/generate-menu-icon.swift`、`Tests/MenuIcon` | 生成器原样迁移，截图比较变量改名；PDF 画布/像素、两输入源资源键与真实系统 renderer 纳入 SwiftPM testTarget。诊断只在独立进程加载系统 renderer，不注册/切换输入源。 |
| 真实语音 HUD | MIT `Sources/RoTypeApp/VoiceHUD.swift` / Waveform 恢复到 `App/Features/Voice/RoarkTVoiceHUD*.swift`；188×36 深色条、点/勾/感叹号/箭头、原 9 柱波形、计时、取消，240×36 详情入口与 288×180 展开/复制。适配现有 lifecycle，保留绑定/识别/润色的真实文案和 Secure Input 复制门。Gallery 是历史 D0 演示，未改其非生产视图。 |

### 对照证据与边界

- `.build/ime-evidence/`：18 张输入法浅/深 PNG + 1 张菜单 PNG + 7 张真实 HUD 实现的离屏 PNG。测试数据全为人工样例，不截取用户屏幕/文字。
- `reference/`：旧源码在临时独立测试程序渲染；没有创建 IMK server、注册输入源、读取真实用户 Rime 数据。10 对正常状态图片逐像素零差异；加载旧文字是本次明确保留的行为修正，不要求与旧版错误显示相同。
- 菜单基线直接读取已安装旧版 PDF，经同一 SystemRendererProbe 得到 44×32px；与新图逐像素零差异。probe 只读资源，未启动旧输入法。
- HUD 原文件仅名称、进度文案适配扩展；绘制/尺寸/布局按原源码，迁移原像素对齐测试通过。已查看录音/展开/通知截图；不声称做过真实录音。
- 测试全部在 Tests 下：MenuIconTests 为 SPM testTarget；InputMethodChecks 的 SPM testTarget 调用独立 GPL 测试可执行程序；不将 GPL 源码链接到 MIT App。脚本单独运行时也导出菜单与 HUD。
- 未恢复旧产品的专属项目主页链接（需产品提供 RockType URL）；未恢复旧权限申请、旧数据迁移与进程退休逻辑，它们不属于视觉恢复。
- 待 Claude 从 main 安装验收：系统菜单图标染色与输入源切换、Shift/真实按键隐藏、不抢焦点、全屏/多屏（含负坐标）、屏幕边缘/系统投影、学习菜单点击/词频、Tab/真实停服快速输入、VoiceOver、Fn/麦克风/复制与安全输入。离屏测试只覆盖本机可用显示器边缘，未模拟不存在的负坐标显示器。

### main 更名集成

- 合并 `main@9b197ce`，提交 `0c133bd`；两个冲突仅为构建脚本产物路径与第三方声明，均保留双方意图。用户可见名称 RockType，内部 Bundle ID、类型、模块、设置路径与资源名维持现有标识。
- 本任务相对 main 不修改 Rime 方案/词库/学习数据或 `squirrel.yaml`。main 自身的方案 name 更名随合并保留。

### 最终验证（2026-10-11）

- 再合并 `main@6b0081f`（合并提交 `d65f552`），无冲突；主 App 默认隐藏菜单栏图标与构建末尾 LaunchServices 注销均保留。
- **通过**：合并后 `scripts/test.sh` 真实退出码 0；40 XCTest、157 Swift Testing，加 Rime 部署/能力与 AppShell 检查。日志 `.build/delivery-tests.log`，退出码 `.build/delivery-tests.exit`。
- **通过**：合并后最终 `scripts/build.sh` 真实退出码 0；`RockType.app` / `RockType Input.app` 与 helpers 签名、worker MLX 自检、合法 XPC/无效模型与错误调用方拒绝通过；末尾执行中间产物/worktree App 注销。日志 `.build/delivery-build.log`，退出码 `.build/delivery-build.exit`。
- **通过**：单独 `scripts/test-ime.sh` 真实退出码 0；直接导出当前生产面板、菜单与 HUD 图片，`.build/final-ime-test.log`。清理旧 D0 预览残图后目录根共 26 张当前 PNG；reference 子目录仅用于对照。
- **通过**：最终签名包 Info.plist 的可执行文件名、RockType 显示名、两个输入源英文名称、六个图标资源键与 PDF 文件存在性逐项检查；主 App 与输入法 strict/deep 签名复核通过。最终本分支与 main 的 `Rime/`、`InputMethod/data/squirrel.yaml` 零差异。
- **通过**：最终源码与旧源码差异复核仅为改名、Swift 6 隔离、保留行为/可访问性与 HUD 进度文案适配；未新增视觉设计。无新增语言运行时。
- **未运行 / 待人工**：安装、注册、worktree App/输入法启动、真实 Fn/麦克风/键盘/权限/VoiceOver 与跨应用视觉验收。本次从未执行安装/卸载、输入法启动或 LaunchAgent 加载；旧安装仅只读资源。由 Claude 从 main 执行 I-3。
- 所有实现与文档在 `agent/ime` 提交；未 push、未合并到 main。worktree 与证据保留供 Claude 验收；无运行中的协作 Worker。构建/测试临时源码与旧命名产物已清理。
