# SPEC-009 分发（M7 前置部分）

- 阶段：M7（本规格先做安装包、公证、卸载、自动更新；首版全量验收在各功能完成后进行）
- 覆盖需求：FR-F3、FR-F4、NFR-9
- 状态：Ready

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
| R-3 | 卸载流程接到设置 → 关于 | pi-surfaces | 未开始 |
| R-4 | Sparkle 2 集成、appcast 脚本、设置 → 关于 中“检查更新” | pi-surfaces | 未开始 |
| R-5 | 第三方声明与许可证文件核对 | pi-surfaces | 未开始 |
| R-6 | 干净账户安装 → 引导 → 卸载 验收 | 用户 + Claude | 未开始 |

**文件所有权**：`Installer/`、`scripts/build-installer.sh`、`scripts/notarize.sh`、`scripts/make-appcast.sh`、`App/Features/Update/`、`App/Features/Uninstall/`、`Package.swift`（仅新增 Sparkle 依赖）、`App/Info.plist`（仅 Sparkle 键）、`THIRD_PARTY_NOTICES.md`、`LICENSES/`、对应测试。设置 → 关于 中按钮接线只改关于分区；`AppDelegate` 如需改动，提供入口由 Claude 集成。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| pkg 构建、`pkgutil --check-signature` | 命令 | 进行中 | 本次提供签名构建脚本；最终证据见下方 |
| postinstall 不 enable/select、不写 HIToolbox | 脚本测试（夹具） | 通过 | `DistributionScriptTests` 执行隔离副本，验证登录用户注册、服务加载、离线卷拒绝 |
| 公证与 staple | 命令（需用户凭据） | 待人工验证 | |
| 本机安装 → 首次引导 → 卸载（含/不含数据） | 用户 | 待人工验证 | |
| Sparkle 从旧版本更新 | 用户 | 待人工验证 | |

## 进度

- R-1：安装脚本、固定路径应用退出工具、签名 product pkg 构建已实现。`scripts/test.sh` 通过；实际安装与重启输入法待 R-6 人工验证。安装使用规格规定的系统 LaunchAgent 路径。

## 问题

### R-1 补充验收（2026-10-11）

- 修复 productbuild 已有 `hostArchitectures` 时生成重复 XML 属性的问题；签名 pkg 已产出，`pkgutil --check-signature` 通过（DF7J2VBQD8）。
- `scripts/test.sh` 通过（116 Swift tests、Rime 部署、外壳检查）；修正前置提交遗留的旧快捷键处理器断言，旧处理器应不再触发动作。
- 未执行本机安装、切换输入源或升级，仍待 R-6 干净账户验证。

### R-2 验收证据（2026-10-11）

- `scripts/notarize.sh` 使用钥匙串 profile，校验包团队、提交并等待，明确要求 `Accepted` 后再 staple、validate 和 Gatekeeper 安装评估。
- `scripts/test.sh` 通过；隔离脚本测试覆盖缺 profile、Invalid 不 staple、Accepted 才 staple/validate。直接不带 `ROARKT_NOTARY_PROFILE` 运行清晰退出，符合预期。
- 真实公证未运行：未提供 profile，不创建或导出凭据，不声称通过 Gatekeeper。
