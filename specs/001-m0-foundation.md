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
| T2 | 翻译 XPC 协议与服务迁移 | pi | 未开始 |
| T3 | 输入法迁移与开发安装 | pi | 未开始 |
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

### T3 输入法迁移与开发安装

- 复制 `../RoType/Squirrel/` 到 `InputMethod/`，但 `librime`、`plum`、`Sparkle` 改为本仓库的 git submodule（同 URL 与提交：librime `a251145d`、plum `4c28f11f`、Sparkle `41847a58`），不要把子模块内容提交进本仓库；不复制 `build/`、`.build/` 等构建产物。`lib/`、`bin/`、`Frameworks/` 中的预编译 librime 可以复制（若体积 > 50MB 说明原因）。
- Xcode 工程与 Info.plist：Bundle ID `com.roarkist.inputmethod.RoarkT`，产品名 `RoarkT Input.app`，显示名 “RoarkT”；`ComponentInputModeDict` 中两个输入源 `com.roarkist.inputmethod.RoarkT.pinyin`（方案 `roarkt`）与 `com.roarkist.inputmethod.RoarkT.flypy`（方案 `roarkt_flypy`）；Connection 名称同步。
- `sources/` 中 `RoType*` 文件与类型改名为 `RoarkT*`；XPC 改用 `Shared/XPCProtocol` 头文件（在 Xcode 工程中加入 header search path，不复制头文件）；删除 v1 翻译调用、旧版本退休/备份/迁移逻辑、旧 helper（`洛克输入法设置`）启动逻辑——设置入口改为打开 `com.roarkist.roarkt`（主 App 未安装时菜单项禁用）。
- Rime 资源从本仓库 `Rime/` 打包进输入法 Bundle。
- `scripts/build.sh` 增加输入法构建（xcodebuild Release，签名同一身份），产物 `dist/RoarkT Input.app`。
- 新增 `scripts/install-dev.sh`：把 `RoarkT Input.app` 装到 `~/Library/Input Methods/`、生成并加载翻译服务 LaunchAgent（路径指向 `dist/RoarkT.app`）、用 `TISRegisterInputSource` 注册（可沿用 RoType 的 Installer/tools 中的注册工具，改名）；`scripts/uninstall-dev.sh` 逆操作。不静默启用或选择输入源。
- 验收：`scripts/build.sh`、`scripts/test.sh` 通过；`install-dev.sh` 后 `TISCreateInputSourceList` 能列出两个新输入源；`grep` 旧标识守卫通过。

### T4 端到端验收（Claude）

见下表。需要真实键盘的项目由用户配合完成。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 骨架构建 | `swift build`、`scripts/test.sh`、`scripts/build.sh` | 通过 | 2026-10-11 Claude 本机运行 |
| 无旧标识 | `scripts/test.sh` 守卫 | 未运行 | |
| Rime 部署 | `scripts/test-rime.sh` | 通过 | 2026-10-11：`scripts/test.sh` 调用 `scripts/test-rime.sh`，临时目录部署 `roarkt` / `roarkt_flypy` / `roarkt_en` 成功，生成 `roarkt_zh.table.bin`、`roarkt_zh.prism.bin`、`roarkt_flypy.prism.bin`、`roarkt_en.table.bin`、`roarkt_en.prism.bin`。`grep -ri rotype Rime/` 无结果。未验证真实键盘打字（属 T3/T4）。Claude 复核：重跑通过；4 个未迁入 Lua 均为旧版退休空壳，方案未引用。已知问题：部署器暂借 `../RoType`，T3 后改用 `InputMethod/bin`。 |
| XPC 鉴权：输入法可翻译、伪造客户端被拒 | 服务测试 + 手工 | 未运行 | |
| 输入源注册 | `install-dev.sh` 后列出输入源 | 未运行 | |
| 选中 RoarkT 打出中文、候选翻译出现 | 用户在系统设置添加输入源后试打 | 待人工验证 | |
| 许可证边界 | MIT 目录不引用 `InputMethod/` | 未运行 | |
