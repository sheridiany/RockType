# SPEC-009 分发（M7 前置部分）

- 阶段：M7（本规格先做安装包、公证、卸载、自动更新；首版全量验收在各功能完成后进行）
- 覆盖需求：FR-F3、FR-F4、NFR-9
- 状态：InProgress（R-1～R-5 代码与许可证审计已交付；发布配置、来源核验及 R-6 人工验收未完成）

## 范围

一个签名、公证的 `RoarkT-<版本>-macOS-arm64.pkg`；安装、首次运行、卸载、Sparkle 自动更新可用。参考 `../RoType/scripts/build-installer.sh`、`notarize-installer.sh`、`Installer/scripts/*`（只读），但**不兼容旧产品**：删除旧版本退休、升级迁移、语音退休、HIToolbox 规范化等逻辑。

## 安装布局（见 docs/architecture.md）

| 产物 | 位置 |
| --- | --- |
| `RoarkT.app`（含翻译服务、语音 worker） | `/Applications/` |
| `RoarkT Input.app` | `/Library/Input Methods/` |
| 翻译服务 LaunchAgent | `/Library/LaunchAgents/com.roarkist.roarkt.translation.plist`，程序路径 `/Applications/RoarkT.app/Contents/Helpers/RoarkTTranslationService` |

## 规则

- postinstall：以登录用户身份 `TISRegisterInputSource` 注册（`launchctl asuser`），加载 LaunchAgent，启动主 App（首次引导会处理“添加输入源”）。**不 enable/select 输入源**，不写 HIToolbox 偏好，不重启系统代理（见 RoType 研究文档）。
- 升级（同为 RoarkT）：退出旧输入法与主 App 进程后替换，保留用户数据（`~/Library/Rime`、`Application Support/RoarkT`、语音模型、钥匙串）。
- 卸载：设置 → 关于 → “卸载 RoarkT…”（已有入口）：确认对话 → 停用并移除输入源注册、bootout LaunchAgent、删除三处程序文件（需管理员授权，用 `NSAppleScript` 的 `with administrator privileges` 或 SMJobBless 以外的最简可靠方式）；勾选“同时删除我的数据”时再删除用户数据（Rime 中仅删 roarkt 相关文件与 RoarkT 生成的 custom.yaml）。
- 公证：`notarytool submit --wait` + `stapler staple`；凭据用钥匙串 profile（名称经环境变量 `ROARKT_NOTARY_PROFILE` 传入），脚本不含任何凭据。
- Sparkle：主 App 集成 Sparkle 2（SPM 依赖，固定版本），`SUFeedURL` 指向 GitHub Releases 上的 appcast（URL 用占位常量，待用户确定仓库）；EdDSA 公钥写入 Info.plist，私钥只在用户钥匙串；`scripts/make-appcast.sh` 生成 appcast。更新后需重启输入法进程（安装后脚本处理）。输入法自身不再内嵌 Sparkle 更新逻辑（若 InputMethod 中仍有，移除其更新入口，子模块可保留）。
- 第三方声明：`THIRD_PARTY_NOTICES.md` 完整覆盖 librime、plum、Squirrel（GPL）、MLX 等；pkg 内附 `Licenses/`；附 GPL 源码获取说明。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| R-1 | `scripts/build-installer.sh`、pre/postinstall、pkg 产出（未公证也可本地安装测试） | pi-surfaces | 已实现；安装待人工验证 |
| R-2 | `scripts/notarize.sh`（无凭据时清晰报错退出） | pi-surfaces | 已实现；真实公证待凭据 |
| R-3 | 卸载流程接到设置 → 关于 | pi-surfaces | 已实现；授权与真实卸载待人工验证 |
| R-4 | Sparkle 2 集成、appcast 脚本、设置 → 关于 中“检查更新” | pi-surfaces | 已实现入口与 feed 工具；配置、启动接线和真实更新待验收 |
| R-5 | 第三方声明与许可证文件核对 | pi-surfaces | 文本与审计已完成；预编译来源及对应源码发布待确认 |
| R-6 | 干净账户安装 → 引导 → 卸载 验收 | 用户 + Claude | 未开始 |
| R-7 | 官网（FR-F5）：`website/` 静态站，只本地构建与测试，不部署 | pi-ui | 未开始 |

**文件所有权**：`Installer/`、`scripts/build-installer.sh`、`scripts/notarize.sh`、`scripts/make-appcast.sh`、`App/Features/Update/`、`App/Features/Uninstall/`、`Package.swift`（仅新增 Sparkle 依赖）、`App/Info.plist`（仅 Sparkle 键）、`THIRD_PARTY_NOTICES.md`、`LICENSES/`、对应测试。设置 → 关于 中按钮接线只改关于分区；`AppDelegate` 如需改动，提供入口由 Claude 集成。

### R-7 官网

- 以 `../RoType/website/` 为参考（只读），沿用其原则：纯静态 HTML/CSS、无 JS 框架、无外部字体与分析脚本、跟随系统浅深色、尊重减少动态效果。
- 内容改为 RoarkT：一个产品的四个能力（双语输入法与候选翻译、本地语音、划词 AI、截图 OCR），各配图；隐私说明页（本地优先、只有显式 AI 动作发送内容、密钥只在钥匙串）；更新日志页；下载按钮指向占位常量（GitHub Releases，待用户确定仓库）；GPL 源码获取说明。
- 产品图：用 `scripts/render-gallery.sh` 产出的 Gallery PNG（候选窗、结果浮窗、截图编辑器、语音 HUD、设置），注明“界面示意”；不得伪造实机截图。
- 视觉风格对齐 D0 Tokens（靛蓝强调色、灰底白卡），不照搬 RoType 的黑白灰。
- 测试：`Tests/Website/` 下用 Python 标准库（`html.parser`）检查链接、图片存在与 alt、无外部脚本；接入 `scripts/test.sh`。不依赖 playwright。
- 文件所有权：`website/`、`Tests/Website/`、`scripts/test.sh` 中一行接入。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| pkg 构建、`pkgutil --check-signature` | 命令 | 通过 | 已生成 0.1.0 arm64 product pkg，Developer ID Installer 团队 DF7J2VBQD8；未安装 |
| postinstall 不 enable/select、不写 HIToolbox | 脚本测试（夹具） | 通过 | `DistributionScriptTests` 执行隔离副本，验证登录用户注册、服务加载、离线卷拒绝 |
| 公证与 staple | 命令（需用户凭据） | 待人工验证 | |
| 本机安装 → 首次引导 → 卸载（含/不含数据） | 用户 | 待人工验证 | |
| Sparkle 从旧版本更新 | 用户 | 待人工验证 | 需正式 feed、公钥、公证 pkg 及 AppDelegate 启动接线 |
| 许可证文本随包分发 | pkg 展开逐文件比对 | 通过 | 两个 App 均包含完整 Licenses 树与声明 |
| 对应源码发布与预编译来源 | 发布审计 | 阻塞 | 缺确切插件构建来源、essay 修订与正式源码下载地址 |

## 进度

- R-1：安装脚本、固定路径应用退出工具、签名 product pkg 构建已实现。`scripts/test.sh` 通过；实际安装与重启输入法待 R-6 人工验证。安装使用规格规定的系统 LaunchAgent 路径。

## 验收证据

### R-1 补充验收（2026-10-11）

- 修复 productbuild 已有 `hostArchitectures` 时生成重复 XML 属性的问题；签名 pkg 已产出，`pkgutil --check-signature` 通过（DF7J2VBQD8）。
- `scripts/test.sh` 通过（116 Swift tests、Rime 部署、外壳检查）；修正前置提交遗留的旧快捷键处理器断言，旧处理器应不再触发动作。
- 未执行本机安装、切换输入源或升级，仍待 R-6 干净账户验证。

### R-2 验收证据（2026-10-11）

- `scripts/notarize.sh` 使用钥匙串 profile，校验包团队、提交并等待，明确要求 `Accepted` 后再 staple、validate 和 Gatekeeper 安装评估。
- `scripts/test.sh` 通过；隔离脚本测试覆盖缺 profile、Invalid 不 staple、Accepted 才 staple/validate。直接不带 `ROARKT_NOTARY_PROFILE` 运行清晰退出，符合预期。
- 真实公证未运行：未提供 profile，不创建或导出凭据，不声称通过 Gatekeeper。

### R-3 验收证据（2026-10-11）

- 生产设置关于页接入确认对话框，默认保留数据。限定从 `/Applications/RoarkT.app` 发起；停用自己的输入源、等待输入法退出、注销登录项，管理员仅执行固定程序路径的删除和服务 bootout。其他 GUI 账户未退出时拒绝程序删除。
- 勾选清理时预先复制用户权限的工具，待主 App 退出后删除设置/模型、RoarkT 方案与独立学习数据、当前用户 AI 钥匙串条目；保留共享词典、其他方案、无归属标记的 custom.yaml。不执行用户提供的 root 脚本。
- `scripts/test.sh` 通过（119 Swift tests）；隔离目录验证保留共享数据、重复清理、拒绝符号链接跳转；独立清理工具 `swiftc` 编译通过。未执行真实删除、管理员弹窗和退出后清理，待人工验证。
- 平台限制：TIS 无公开 unregister API，执行 disable + 移除输入法 bundle 后提示注销并重新登录。需要 Claude 确认这作为“移除输入源注册”的验收口径。

### R-4 验收证据（2026-10-11）

- Sparkle 2.8.0 使用已固定的依赖；生产关于页接“检查更新”，公开 `UpdateController.shared.start()` 由 Claude 集成到 AppDelegate。缺少真实 feed、公钥时禁用检查并说明，避免占位 URL 网络请求。
- 安装包包含 Sparkle 框架，按嵌套层级签名；保留 main 已有的开发构建框架嵌入工作。输入法 Sources / 工程 / Resources 检索未发现独立 Sparkle 更新入口，无需删除代码；子模块保留。
- appcast 脚本从钥匙串签署已公证 pkg，从包内读取版本/公钥并验证签名，生成 `guided-package` enclosure；不上传、不生成私钥。
- `scripts/test.sh` 通过（121 Swift tests）；覆盖包篡改、错误公钥、未配置 feed、无效 URL 拒绝。独立 appcast 工具编译通过。
- 真实 appcast 签名与跨版本更新未运行：待仓库 URL、EdDSA 公钥及用户钥匙串私钥、公证 profile。自动启动接线留给 Claude；真实安装包最终构建记录见后续验收。

### 合入 main 后补验

- 已在本 worktree 合入 `7245678` 所在 main（合并提交 `9a94dff`），未修改主仓库。合并冲突采用 main 已接入真实选区动作的快捷键断言；全量测试通过。
- R-3 随 main 新增的 Rime 配置归属标记收紧清理：`roarkt*.custom.yaml` 仅带生成标记时删除，用户手写补丁保留；全量测试通过，覆盖标记删除与手写保留。

### R-5 与最终构建验收（2026-10-11）

- 补齐 `THIRD_PARTY_NOTICES.md` 组件清单、45 份许可证/来源/源码说明文件（含既有 GPL 文本）。覆盖 Squirrel、librime/plum、插件、Lua、Boost、OpenCC 等静态依赖、Rime 数据、CC-BY-SA-4.0、Sparkle 及语音锁定依赖；保留原版权署名与 NOTICE。
- `scripts/test.sh` **通过**：合入 main 后 131 tests / 4 suites，Rime 部署、快捷键与权限检查通过；脚本语法与 `git diff --check` 通过。既有 `Core/Voice/LICENSE.md` SPM 未声明资源警告不影响通过。
- `scripts/build.sh` **通过**：主 App、输入法、MLX worker 构建与签名；独立 voice XPC smoke 回复、无效模型拒绝、未授权调用方拒绝均通过。未启动主 App 或输入法，未安装/注册/加载 LaunchAgent。
- `scripts/build-installer.sh` **通过**：产出 `dist/RoarkT-0.1.0-macOS-arm64.pkg`；`pkgutil --check-signature` 为 DF7J2VBQD8 的 Developer ID Installer。
- `pkgutil --expand-full` **通过**（仅展开，不安装）；展开的两个 App 均 `codesign --verify --deep --strict` 通过，主 App hardened runtime 与时间戳存在；Sparkle、注册/清理 helper、语音 worker 均包含。两个 `Contents/Resources/Licenses` 与仓库许可证逐文件一致，附加 THIRD_PARTY_NOTICES 也逐字节一致。
- pkg SHA-256：`cb97da70ab3bd11d8a72465b2a807d33d2aab182c81029076892f658249d9c69`。本机详细日志留在 `.build/distribution-logs/`，未入 git。
- 真实公证、签署发布 appcast、跨版本自动更新、管理员授权卸载和两种数据选项 **未运行 / 待人工验证**。按本机环境规则由 Claude 从 main 执行 R-6。

## 需要 Claude 决定或接线

1. 确定 GitHub 仓库、`SUFeedURL` 与 EdDSA 公钥；用户钥匙串保管私钥并提供公证 profile。现有占位配置明确禁用更新，不应当作发行配置发布。
2. 在 `AppDelegate.applicationDidFinishLaunching` 调用 `UpdateController.shared.start()`；本分支按文件所有权仅提供入口，关于页已可按需启动。每次发布递增 `CFBundleVersion`。
3. 确认 TIS 无公开 unregister API 时，以停用 + 删除 bundle + 注销登录清缓存作为注册移除验收。取消授权或中途失败可能已停用输入源/登录项，人工验收需覆盖重试。
4. 核实预编译 librime / Lua / Octagram / Predict 的完整构建来源与静态依赖，及 essay 数据的精确修订；现有源码无法证明全部二进制来源。建议取得原构建记录，或从固定源码重建后发布。`LICENSES/GPL-SOURCE.md` 已列对应源码包材料；正式源代码下载 URL 和源码包尚未发布，NFR-9 不标记完成。
5. 本实现遵循 SPEC-009 的 `/Library/LaunchAgents/` 系统位置；架构表仍写 `~/Library/LaunchAgents/`，请统一文档口径。
