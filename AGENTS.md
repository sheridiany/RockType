# RoarkT 开发约定

使用简洁中文。先说结果、证据和未完成项。最小、可回滚的修改。

## 开始任何任务前必读

1. [PRD](docs/prd.md)：需求编号 FR-xx / NFR-x 与验收条件。
2. [技术架构](docs/architecture.md)：进程、模块、标识符、XPC 边界。**标识符只能用 `Core/Identifiers.swift` 与架构文档里的值。**
3. [路线图](docs/roadmap.md) 与当前任务对应的 [规格](specs/README.md)。
4. [术语](CONTEXT.md)。

## 硬性规则

- 语言：Swift 6（SwiftUI + AppKit）。输入法沿用 Squirrel 的 Swift/ObjC。不引入其他语言运行时。
- 最低系统 macOS 14；macOS 26 专属 API 用 `if #available(macOS 26, *)` 隔离。
- **不兼容旧产品**：代码、资源、脚本中不得残留 `RoType`、`洛克`、`Luoke`、`im.roarkai`、`RoarkTools` 等旧标识（`THIRD_PARTY_NOTICES`、许可证文件和 git 历史说明除外）。迁移旧代码时一律改名。
- 不做旧版本升级迁移、旧进程退休、旧文件备份之类逻辑；迁移代码时直接删除这类逻辑。
- 进程间只用 XPC，按签名身份（Team ID `DF7J2VBQD8` + 具体 identifier）鉴权。
- 打字路径（按键处理、候选刷新）不得等待任何网络、翻译或 AI 结果。
- Secure Input / 密码框：不取词、不翻译、不调用 AI、不填入语音、不写缓存。
- 不把密钥、屏幕内容、选中文字、用户文件写进日志、测试夹具和文档。
- `InputMethod/` 下是 GPL v3 代码；其他目录（MIT）不得 import、链接或复制 `InputMethod/` 的代码。共享只能通过 `Shared/XPCProtocol` 中的协议声明。
- 不引入需求之外的服务端、插件系统、数据库、通用工作流引擎。

## 构建与测试

- 测试一律放在 `Tests/<目标名>/`，并在 `Package.swift` 新增或扩展 testTarget（任何 agent 都可以只为自己的测试新增 testTarget 或给已有 testTarget 加依赖）。不要把测试藏在源码目录或另建独立 Package/脚本，`scripts/test.sh` 必须能跑到全部测试。

- `scripts/build.sh`：构建并签名全部产物到 `dist/`。
- `scripts/test.sh`：全部自动化测试。提交前必须通过。
- 签名身份默认 `Developer ID Application: XIAO BIN (DF7J2VBQD8)`，可用 `ROARKT_CODESIGN_IDENTITY` 覆盖。

## 本机环境（用户的真实电脑）

- 不要运行 `scripts/install-dev.sh` / `uninstall-dev.sh`，不要从 worktree 启动或注册输入法、加载 LaunchAgent。用户正在用 main 的安装版本做真实验收；需要安装验证时在汇报中提出，由 Claude 从 main 执行。
- 可以用 `open dist/RockType.app` 做启动冒烟检查，但检查完立即退出该进程。
- 只在自己的 worktree 中工作；不在主仓库切分支、提交或留下未提交改动。

## 交付要求

- 完成后在对应规格的“任务”与“验收证据”中更新状态，写清：做了什么、怎么验证、结果、未验证项。
- 区分“未运行 / 通过 / 失败 / 阻塞”。构建成功不等于功能验收。需要真实键盘、麦克风、权限弹窗的验证若无法自动完成，明确标为“待人工验证”，不要声称通过。
- 每个任务一个 git commit，消息格式：`<范围>: <做了什么>`，例如 `ime: migrate Squirrel sources with RoarkT identifiers`。不要 push。
- 参考旧代码时只读，不修改：`../RoType`、`../RoarkTools`。
