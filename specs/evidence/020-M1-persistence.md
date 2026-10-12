# SPEC-020 M1：持久启用列表校验

基线 `d34a07a`；开始前 `git merge main` 为 Already up to date。本轮依据用户提供的持久列表现场，继续修复安装完成判据。**代码与合成策略测试完成；真实 API 启用/持久化和点击回归待 main 验证。** 未在 worktree 安装、注册、启用、选择输入源或修改 HIToolbox 偏好。

## 核实结果

- 原 `RoarkTRegisterInputSource register` 只有 TISRegisterInputSource，没有 Enable/Select。原 dev/pkg 安装都仅调用 register。因此不能将“注册工具只做运行期 Enable/Select”作为代码事实。
- 输入法自身另有 `--enable-input-source` / `--select-input-source`：SquirrelInstaller 只启用模式，验证运行期标志；安装脚本没有调用这两个入口。不能据此断言现场一定由该入口造成。
- 新只读检查复核当前用户：`listReadable=true`，parent/pinyin/flypy 均为 false；同一次 `diagnose-icons` 的 `resourceCheckPassed=true`、`persistentEnablementPassed=false`。缺失场景 `verify-enabled` 实际退出 1。证据 `.build/m1-persistence/live-before.{json,exit}`、`live-before-error.log`、`live-diagnostic.json`。只输出匹配结果，不复制完整用户偏好。
- SDK `TextInputSources.h` 的 TISEnableInputSource 文档明确要求模式的父输入法先启用，API 使源可在 UI 选择；**没有承诺 noErr 等价于持久列表已经写入**。没有直接写 plist 的官方依据，也未实现这种回退。

## 实现

1. `ensure-enabled <已安装 bundle>`：校验 bundle ID，注册列表已完整则不重复 register；缺少注册时调用 TISRegisterInputSource 并等待源可见。父源、pinyin 按顺序检查运行期与持久状态，任一缺失即通过 TISEnableInputSource 修复。已有完整启用状态不再次调用 Enable；不调用 Select，不启用未请求的双拼。
2. `verify-enabled`：只读 CFPreferences 的 `com.apple.HIToolbox / AppleEnabledInputSources`（当前用户、any host），匹配父源的 Keyboard Input Method 记录及属于同 bundle 的 pinyin Input Mode 记录；不以 Selected/History 或裸模式 ID 代替。
3. API 操作后，以新进程执行 verify-enabled，避免沿用调用进程的 CFPreferences 缓存；最多二十次复核。API noErr 但缺项仍明确失败，提示在系统键盘设置添加 RockType Pinyin 后重跑 verify-enabled。没有禁用再启用、切换源、重启代理、同步写偏好或直接改 plist。
4. dev 原子替换之后及 pkg 每个现有 GUI 用户会话调用 ensure-enabled，再独立执行一次 verify-enabled；缺项非零退出，不打印安装成功。pkg 无登录用户仍保持既有的登录后添加提示。FR-F3 与 Installer README 按本轮用户授权同步更新。
5. 卸载注册工具依次禁用两个模式再禁用父源；没有改变卸载脚本的其他行为。主 App 自身卸载入口及输入法手动 CLI 未在本轮扩展。
6. diagnose-icons 新增 persistentEnablement（listReadable、parentEnabled、pinyinEnabled、flypyEnabled）及 persistentEnablementPassed。既有 resourceCheckPassed/退出码仍只表示资源检查；持久状态的自动化门禁必须用 verify-enabled。

## 自动验证

- 六项定向测试通过：匹配父源与模式/排除其他 bundle 与历史记录、运行期已启用但持久记录缺失、健康更新零注册零启用、父源 API 失败中止模式启用、注册不完整拒绝继续、API noErr 但复核失败必须报错。测试使用合成状态与 API 闭包，不操作真实输入源。
- 真实缺失状态的只读命令退出 1；这是正确检测，**不是 API 修复后的真机绿灯**。
- 全量 `scripts/test.sh`：通过，真实退出码 0；256 XCTest（5 skipped）、338 Swift Testing / 18 suites 及 Rime/AppShell 检查，见 `.build/m1-persistence/tests-final.{log,exit}`。首次全测发现旧分发测试仍断言只注册；已按新授权更新，并增加最终持久检查失败必须中止安装的脚本回归。
- 全量 `scripts/build.sh`：通过，真实退出码 0；签名及 voice MLX/XPC 烟测通过，见 `.build/m1-persistence/build-final.{log,exit}`。
- 最终签名工具只读检查：当前缺失状态 verify-enabled 退出 1、diagnose-icons 资源检查退出 0 且 persistentEnablementPassed=false，分别保存在 packaged-verify / packaged-diagnostic 文件。符合预期的独立判据。
- 安装脚本语法与 diff 检查通过。pkg 安装、卸载和真实启用未执行。

## main 验证步骤

从 main 合入并构建后执行，勿从本 worktree 安装：

```sh
./dist/RoarkTRegisterInputSource verify-enabled
./scripts/install-dev.sh
./dist/RoarkTRegisterInputSource verify-enabled
./dist/RoarkTRegisterInputSource diagnose-icons
```

第一条在当前损坏状态下应退出 1；安装后仅当最后的 verify-enabled 退出 0、parentEnabled 与 pinyinEnabled 均为 true，才确认正规 API 的启用已体现在持久列表。可另用 `defaults read com.apple.HIToolbox AppleEnabledInputSources` 本机核对，但不要把整份用户偏好加入仓库。

若 ensure-enabled 报 API 错误或持久列表仍缺失，记录错误和诊断摘要，不运行 defaults write；在系统设置 → 键盘 → 文本输入中添加 RockType Pinyin，再执行 verify-enabled。**必须把“API 自动修复成功”和“系统设置手动添加后恢复”分别记录，后者不能证明 API 自动持久化成功。** 这时自动修复验收仍未完成。

持久状态通过后：连续打开/关闭图标十次、ABC ↔ RockType、中英状态、全拼 ↔ 双拼（双拼按用户需要手动添加）、睡眠唤醒；再运行一次 install-dev 验证健康原子更新不重复注册且持久状态保留。过程中不以 killall 或重新登录作为修复。出现问题保留 verify-enabled、diagnose-icons 的前后摘要。
