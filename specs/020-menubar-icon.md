# SPEC-020 输入法菜单栏图标消失

- 状态：InProgress（2026-10-12）
- 用户反馈（多次）：菜单栏输入法图标会消失。“这个 bug 需要好好解决下。”

## 已知事实（Claude 观察）

- 消失时：`TextInputMenuAgent` 在运行；当前输入源是 `com.roarkist.inputmethod.RoarkT.pinyin`（enabled/selectable）；`RockType Input.app` 进程在跑；Info.plist 各模式 `tsInputModeMenuIconFileKey`/`PaletteIconFileKey`/`AlternateMenuIconFileKey` = `roarktMenuTemplate.pdf`，文件存在于 Resources；还有 `TISIconLabels`。
- `killall TextInputMenuAgent` 能临时恢复，但之后会再次消失（今天安装后重启过代理，几小时后又消失）——不只是安装时刻的问题。
- 主 App 也可能有菜单栏状态项（`general.menuBarIcon` / 北京时间）；需确认用户看到的“图标”是输入法输入源图标（Squirrel 系）。
- 安装路径：`scripts/install-dev.sh` 原地覆盖 bundle + `RoarkTRegisterInputSource register`，并重启输入法进程。
- 历史：之前出现过菜单栏/输入源名称 TIS 缓存问题，当时判断需要重新登录。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| M1 | 找到图标消失根因并根治；不允许依赖 killall/重新登录 | pi-ime | 未开始 |

## M1 要求

- 先复现：可疑触发点包括输入法进程重启/崩溃后被系统拉起、切换输入源（中英、程序化切换、Caps Lock）、睡眠唤醒/锁屏、显示器变化、主 App 重启、设置同步写入后输入法重载 Rime（是否改变 bundle/Info 或调用了会触发 TIS 刷新的 API）、`TISIconLabels` 与 PDF 模板图标的组合（对比上游 Squirrel 与系统输入法如何声明图标：icns/tiff/pdf、`TISIconIsTemplate`、是否需要 `tsInputModeMenuIconFileKey` 用 tiff）、同一 bundle 内多个 mode 与父源 selectable=0 的关系。
- 参考：上游 rime/squirrel 的 Info.plist 与图标资源、其 issue 中“menu bar icon disappears”类问题；只读参考 `../RoType`（旧产品是否有同样问题、怎么处理的）。
- 产出：根因写进证据（含复现步骤）；修复后提供自动化检查（例如脚本读取 TIS 属性 `kTISPropertyIconImageURL`/`kTISPropertyIconRef` 校验图标可解析），以及安装脚本不再导致缓存错乱（如安装用原子替换、版本号变化策略、必要时只在注册信息变化时 re-register）。
- 不允许的方案：定时 killall 系统进程、修改系统文件。
- 遵守 AGENTS.md：不要在 worktree 安装/注册；需要真机验证的步骤写清楚，由 Claude 从 main 安装验证。test/build 真实退出码 0；更新本表与 `specs/evidence/020-M1.md`；一个 commit。
