# SPEC-001 工程骨架（M0）

- 阶段：M0
- 覆盖需求：NFR-8、NFR-9、FR-F3（开发签名）
- 状态：Ready

## 范围

把 RoType 中可复用的输入法、Rime 方案、翻译服务迁入 RoarkT，全部换成新标识符（见 [技术架构](../docs/architecture.md)），打通“输入法 → 翻译服务”的鉴权 XPC，做到开发机上可构建、可安装、可选中、可打字。

不做：主 App 功能、UI 设计、语音（M5）、发布安装包与公证（M7）、旧版本升级与迁移（永不做）。

## 迁移来源（只读）

| 来源 | 去向 |
| --- | --- |
| `../RoType/Rime/` | `Rime/` |
| `../RoType/Shared/RoTypeXPCProtocol/` | `Shared/XPCProtocol/` |
| `../RoType/Sources/RoTypeCore/DynamicTranslationProtocol.swift`、`RoTypeTranslationXPC.swift` | `Core/Translation/` |
| `../RoType/Sources/RoTypeTranslationService/` | `Services/TranslationService/` |
| `../RoType/Squirrel/`（含 librime、plum、Sparkle 子模块） | `InputMethod/` |
| `../RoType/Installer/im.roarkai.inputmethod.Luoke.translation.plist` | `Installer/com.roarkist.roarkt.translation.plist` |
| RoType 对应测试 | `Tests/` |

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| T1 | Rime 方案迁移 | pi | 完成（Claude 已验收 2026-10-11） |
| T2 | 翻译 XPC 协议与服务迁移 | pi | 完成（Claude 已验收 2026-10-11；服务测试已并入根 Package.swift） |
| T3 | 输入法迁移与开发安装 | pi | 完成（待验收；根测试脚本的词库误报需 Claude 处理） |
| T4 | 端到端验收 | Claude | 未开始 |

### T1 Rime 方案迁移

- 复制 `../RoType/Rime/` 到 `Rime/`，方案与词典改名：`rotype` → `roarkt`，`rotype_flypy` → `roarkt_flypy`，`rotype_en` → `roarkt_en`，`rotype_zh` → `roarkt_zh`；Lua 文件 `rotype_*.lua` → `roarkt_*.lua`，同步所有 `require`、`lua_filter`、`lua_translator` 引用与 `schema_id`、`name`（显示名 “RoarkT（全拼）”“RoarkT（小鹤双拼）”）。
- 删除仅为旧版本升级、备份、退休存在的逻辑。
- 新增 `scripts/test-rime.sh`：用 `rime_deployer`（`../RoType/Squirrel/bin/rime_deployer` 或迁入后的 `InputMethod/bin/`）在临时目录部署方案，成功即通过；接入 `scripts/test.sh`。
- 验收：`scripts/test.sh` 通过；`grep -ri rotype Rime/` 无结果。

### T2 翻译 XPC 协议与服务迁移

- `Shared/XPCProtocol/include/RoarkTTranslationXPCProtocol.h`：在现有 `ping` 之外加入 RoType v2 接口 `translateCandidate(sessionID:generation:request:withReply:)`、`cancel(sessionID:throughGeneration:)`、`recordControllerInput`、`controllerInputGeneration(reply:)`、语音端点 rendezvous（`registerDictationEndpoint` / `dictationEndpoint`）。**删除 v1 的 `translate(sessionID:generation:rawInput:sourceText:...)`**。语音协议头改名为 `RoarkTDictationXPCProtocol.h`。服务名一律用 `RoarkTIdentifiers.h` 中的宏。
- `Core/Translation/`：迁入 `DynamicTranslationProtocol.swift`（v2 请求校验）与 XPC 辅助类型，改名去掉 RoType 前缀。
- `Services/TranslationService/`：迁入服务实现。鉴权改为：输入法 `com.roarkist.inputmethod.RoarkT` 可调用翻译与 `recordControllerInput`；主 App `com.roarkist.roarkt` 可调用 `controllerInputGeneration`、`ping`、`dictationEndpoint`；其余拒绝。Team ID 来自 `Identifiers.teamID`。
- `Installer/com.roarkist.roarkt.translation.plist`：LaunchAgent，`MachServices` 为 `com.roarkist.roarkt.translation`，程序路径指向 `RoarkT.app/Contents/Helpers/RoarkTTranslationService`（开发期由 `scripts/install-dev.sh` 写入实际路径，见 T3）。
- 迁入并改名相应测试（`RoTypeCoreTests` 中翻译协议、`RoTypeTranslationServiceTests`），全部通过。
- `scripts/build.sh` 已签名服务的 identifier 为 `com.roarkist.roarkt.translation`，保持。
- 验收：`swift test` 全部通过；`scripts/build.sh` 成功；`codesign -dv` 显示正确 identifier。

#### T2 验收证据（2026-10-11，agent/xpc）

- 完成（待验收）：迁入 v2 候选请求与语音 rendezvous 协议、Core 校验/错误/静态兜底类型、Apple 翻译服务、LaunchAgent 模板及对应测试。删除 v1 接口与兼容路径。服务仅接收架构规定的输入法和主 App 签名，Team ID 取自 `Identifiers`，并用 `setCodeSigningRequirement` 约束连接后续消息。`ping` 仅主 App 可调用；输入法越权调用时断开连接。
- 通过：`scripts/test.sh`（包含 `swift test`），8 项核心测试，含参数化 v2 请求、UTF-8 长度边界、方向/原文匹配、静态兜底及旧标识守卫。
- 通过：`swift test`（RoarkTTranslationServiceTests，合并后由 Claude 并入根 Package.swift），30 项服务测试，含参数化用例；覆盖角色权限、SecCode 拒绝非产品测试进程、generation 乱序/取消水位、连接隔离、不响应取消的后端迟到结果、端点归属清理，以及语言包错误和有限重试。后端测试使用合成文本和可控 session，不调用真实翻译语言包。
- 通过：`swift build`、`scripts/build.sh`；`codesign -dv --verbose=4 dist/RoarkT.app/Contents/Helpers/RoarkTTranslationService` 确认 `Identifier=com.roarkist.roarkt.translation`、`TeamIdentifier=DF7J2VBQD8`；构建脚本的严格签名验证通过。
- 通过：`plutil -lint Installer/com.roarkist.roarkt.translation.plist`。模板路径为 `/Applications/RoarkT.app/Contents/Helpers/RoarkTTranslationService`，开发路径替换仍由 T3 完成。
- 待 Claude 合并决定：根 `Package.swift` 没有服务测试 target，且不属于 T2 文件修改范围，因此未修改它或 `scripts/test.sh`。当前服务测试入口在临时 SPM 包中链接本 worktree 的真实源码，执行后自动清理。合并时可增加 `RoarkTTranslationServiceTests` target（路径 `Tests/TranslationServiceTests`，依赖 `RoarkTTranslationService`、`RoarkTCore`、`RoarkTXPCProtocol`）并移除临时测试入口，或由总测试脚本调用该入口。根 `swift test` 当前只运行核心测试。
- 未运行 / 待 T4：真实签名输入法与主 App 经 LaunchAgent 的 XPC 往返、伪造客户端经真实监听器被拒、实际语言包翻译、真实键盘候选翻译、macOS 14 运行验证。本次未安装/加载 LaunchAgent，未更改其他 worktree，未执行 T1/T3。

### T3 输入法迁移与开发安装

- 复制 `../RoType/Squirrel/` 到 `InputMethod/`，但 `librime`、`plum`、`Sparkle` 改为本仓库的 git submodule（同 URL 与提交：librime `a251145d`、plum `4c28f11f`、Sparkle `41847a58`），不要把子模块内容提交进本仓库；不复制 `build/`、`.build/` 等构建产物。`lib/`、`bin/`、`Frameworks/` 中的预编译 librime 可以复制（若体积 > 50MB 说明原因）。
- Xcode 工程与 Info.plist：Bundle ID `com.roarkist.inputmethod.RoarkT`，产品名 `RoarkT Input.app`，显示名 “RoarkT”；`ComponentInputModeDict` 中两个输入源 `com.roarkist.inputmethod.RoarkT.pinyin`（方案 `roarkt`）与 `com.roarkist.inputmethod.RoarkT.flypy`（方案 `roarkt_flypy`）；Connection 名称同步。
- `sources/` 中 `RoType*` 文件与类型改名为 `RoarkT*`；XPC 改用 `Shared/XPCProtocol` 头文件（在 Xcode 工程中加入 header search path，不复制头文件）；删除 v1 翻译调用、旧版本退休/备份/迁移逻辑、旧 helper（`洛克输入法设置`）启动逻辑——设置入口改为打开 `com.roarkist.roarkt`（主 App 未安装时菜单项禁用）。
- Rime 资源从本仓库 `Rime/` 打包进输入法 Bundle。
- `scripts/build.sh` 增加输入法构建（xcodebuild Release，签名同一身份），产物 `dist/RoarkT Input.app`。
- 新增 `scripts/install-dev.sh`：把 `RoarkT Input.app` 装到 `~/Library/Input Methods/`、生成并加载翻译服务 LaunchAgent（路径指向 `dist/RoarkT.app`）、用 `TISRegisterInputSource` 注册（可沿用 RoType 的 Installer/tools 中的注册工具，改名）；`scripts/uninstall-dev.sh` 逆操作。不静默启用或选择输入源。
- 验收：`scripts/build.sh`、`scripts/test.sh` 通过；`install-dev.sh` 后 `TISCreateInputSourceList` 能列出两个新输入源；`grep` 旧标识守卫通过。

### T3 验收证据（2026-10-11，agent/ime）

状态：**完成（待验收）**。T2 已通过 `git merge main` 合入（main 当时为 `53ed599`；合并提交 `e16bb2d`），不再等待 T2。实现提交：`d9e2135`、`e0426b1`、`add8a31`。未 push、未合并回 main、未修改其他 worktree。

- 输入法源码、Xcode 工程、资源及 arm64 预编译 librime 已迁入。产品为 `RoarkT Input.app`，Bundle ID 为 `com.roarkist.inputmethod.RoarkT`；上游 target/scheme 名 `Squirrel` 保留。Swift 6 / macOS 14；IMK 同步回调用主线程断言进入 MainActor，Rime 通知转交主队列，XPC 回调以连接 token 防止迟到回调影响新连接。
- librime / plum / Sparkle 均为 gitlink，固定提交为 `a251145d3aafa33871824a40bbec04c966bd8b56` / `4c28f11f451facef809b380502874a48ba964ddb` / `41847a58cdef7506b257591fcca6f9495df591d4`，URL 与来源相同。无构建目录入库。`lib/` + `bin/` 约 12 MB；`data/plum/` 约 52 MB，其中约 40 MB 是全拼/小鹤所需八股文模型，非构建产物。未携带无用的预编译 Sparkle framework。
- 两个输入源独立声明，显示为“RoarkT（全拼）”“RoarkT（小鹤双拼）”，`setValue(_:forTag:client:)` 与新建 Rime session 分别选用 `roarkt` / `roarkt_flypy`。Xcode build phase 从根 `Rime/` 打包 YAML/Lua 和语言模型到 SharedSupport。
- 删除旧工厂数据备份/迁移、旧签名替换兼容分支、旧设置 helper 启动和产品跨进程 DistributedNotification 通知。设置菜单按主 App Bundle ID 查找，未安装时禁用。无麦克风用途声明/entitlement，不主动申请通知权限。
- 翻译客户端经 header search path 引用 `Shared/XPCProtocol` 的共享头，无头文件副本，只调用 v2 `translateCandidate` / `cancel` / `recordControllerInput`。语音端点通过 `registerDictationEndpoint` 注册，导出 `RoarkTDictationXPCProtocol` 的 capture/commit/cancel，按主 App Team ID + identifier 鉴权；翻译服务连接也校验服务签名。所有 ticket/焦点状态访问在主队列，安全输入/有预编辑内容时拒绝获取上下文，按一次性 ticket、调用方连接、前台应用、选择区、activation、deadline 约束填入，拒绝控制字符。语音录音/worker/UI 仍属 M5。
- 本地请求值类型、ticket 和填入策略在输入法独立编译；原 MIT 授权保留于 `InputMethod/LICENSE.translation.txt`。MIT 产品不 import/link 输入法代码。
- `build.sh` 生成并签名主 App、服务、输入法和注册工具；`install-dev.sh` 安装到当前用户目录，加载指向本 worktree `dist/RoarkT.app` helper 的 LaunchAgent，然后注册/查询两输入源；`uninstall-dev.sh` 逆操作并保留 Rime 用户数据。安装不启用或选择输入源。TIS 无公开注销 API，移除 bundle 后系统缓存项可能需重新登录消失。

| 检查 | 结果 | 证据 / 限制 |
| --- | --- | --- |
| `scripts/build.sh` | 通过 | Swift 6 Release 编译、主 App / 服务 / 输入法 / 注册工具签名及 bundle `codesign --verify --strict --deep` 成功。仅保留 Xcode 的“无 AppIntents 依赖，跳过 metadata”提示。 |
| 签名身份 | 通过 | `codesign -dv 'dist/RoarkT Input.app'`：Identifier `com.roarkist.inputmethod.RoarkT`，TeamIdentifier `DF7J2VBQD8`；服务 Identifier `com.roarkist.roarkt.translation`，同 Team ID。 |
| `scripts/test.sh` | **失败：词库守卫误报** | Swift Testing **38/38 通过**，Rime 三方案临时部署通过；末尾 grep 把上游词库中的“巴洛克”“夏洛克”等普通词条识别成旧产品。命中 `InputMethod/librime/data/minimal/essay.txt`、`InputMethod/data/plum/essay.txt`、`InputMethod/data/plum/terra_pinyin.dict.yaml`，以及构建后 SharedSupport 中的两份词库副本。保留原始词库与固定子模块提交，未篡改自然语言词条。`scripts/test.sh` 不在 T3 所有权内，需 Claude 调整产品标识判定和第三方词库/构建产物扫描边界。 |
| `InputMethod/scripts/test-ticket.sh` | 通过 | 实际 ticket 类型的重放拒绝、应用/光标/activation 变化、取消、过期、deadline、NaN、后请求替代前请求；实际填入策略的空文本/控制字符/缺失应用拒绝。 |
| 产品源码旧标识检查 | 通过 | 对 git 跟踪的 `InputMethod` 文件排除上游词库、许可证及上游 README 后，旧产品标识 grep 无结果；不递归 gitlink。共享头只引用，不复制。 |
| Plist / shell 语法 | 通过 | `plutil -lint` 检查 Info.plist、entitlements、pbxproj；`zsh -n scripts/build.sh scripts/install-dev.sh scripts/uninstall-dev.sh`；`bash -n InputMethod/scripts/package-rime.sh InputMethod/scripts/test-ticket.sh`。 |
| Rime 资源打包 | 通过 | 临时目录运行 `package-rime.sh`，逐字节比较根 Rime YAML/Lua、语言模型与打包副本一致；输入源/方案映射与默认禁用断言通过。最终 bundle 含同一打包资源。 |
| 注册工具失败路径 | 通过 | Swift 6 独立编译成功；`register /tmp/nonexistent-roarkt.app` 返回 1，拒绝错误 bundle。安装产物缺失时安装脚本在写用户目录前退出。 |
| 实际安装、查询、卸载、重新安装 | **通过** | `scripts/install-dev.sh`、`dist/RoarkTRegisterInputSource list`、`scripts/uninstall-dev.sh`、再次安装均返回 0。卸载后用户 bundle/LaunchAgent 文件消失、`launchctl print` 确认服务已卸载；重新安装后两源均可查询，LaunchAgent 指向当前 worktree 的服务。 |
| 不静默启用/选择 | **通过** | TIS 查询得到两源正确中文显示名，均 `enabled=false`、`selected=false`。安装后的 bundle 深度签名校验通过。 |
| 真实键盘、候选翻译、语音端点真实 XPC 往返、密码框、macOS 14 运行 | 待人工 / T4 验证 | 不自动选择输入源；编译、服务单测和 ticket 测试不能替代真实 IMK/语音填入验收。 |

交接给 Claude：调整根测试脚本的词库误报（本任务没有该文件所有权）并复跑；执行 T4。当前保留 `~/Library/Input Methods/RoarkT Input.app` 与 `~/Library/LaunchAgents/com.roarkist.roarkt.translation.plist` 供验收，输入源未启用/选中，Rime 用户数据未修改。LaunchAgent 指向此 worktree 的 `dist/`，合并后需从目标 checkout 重新构建/安装；在此之前不要删除此 worktree。

### T4 端到端验收（Claude）

见下表。需要真实键盘的项目由用户配合完成。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 骨架构建 | `swift build`、`scripts/test.sh`、`scripts/build.sh` | 通过 | 2026-10-11 Claude 本机运行 |
| 无旧标识 | `scripts/test.sh` 守卫 | 失败（词库误报） | T3 产品源码检查通过；上游词库自然语言词条误报，见 T3 证据。 |
| Rime 部署 | `scripts/test-rime.sh` | 通过 | 2026-10-11：`scripts/test.sh` 调用 `scripts/test-rime.sh`，临时目录部署 `roarkt` / `roarkt_flypy` / `roarkt_en` 成功，生成 `roarkt_zh.table.bin`、`roarkt_zh.prism.bin`、`roarkt_flypy.prism.bin`、`roarkt_en.table.bin`、`roarkt_en.prism.bin`。`grep -ri rotype Rime/` 无结果。未验证真实键盘打字（属 T3/T4）。Claude 复核：重跑通过；4 个未迁入 Lua 均为旧版退休空壳，方案未引用。已知问题：部署器暂借 `../RoType`，T3 后改用 `InputMethod/bin`。 |
| XPC 鉴权：输入法可翻译、伪造客户端被拒 | 服务测试 + 手工 | 未运行 | |
| 输入源注册 | `install-dev.sh` 后列出输入源 | 通过 | 2026-10-11 T3：全拼/小鹤均可查询、显示名正确、未启用/选中；卸载和重新安装通过。 |
| 选中 RoarkT 打出中文、候选翻译出现 | 用户在系统设置添加输入源后试打 | 待人工验证 | |
| 许可证边界 | MIT 目录不引用 `InputMethod/` | 未运行 | |
