# 分发

先运行 `scripts/build.sh`，再运行 `scripts/build-installer.sh`。后者使用 `dist/` 的已有产物，在临时目录内加许可证、同步版本、为嵌套代码补时间戳签名，产出 `dist/RockType-<版本>-macOS-arm64.pkg`。不会安装到本机。可用 `ROARKT_CODESIGN_IDENTITY` / `ROARKT_INSTALLER_IDENTITY` 指定证书，默认使用架构规定的团队。

安装只支持当前启动卷。preinstall 在所有已登录 GUI 会话内退出固定安装路径的两个应用，等待最多 8 秒；拒绝退出则中止，不强杀、不删除用户数据。postinstall 以登录用户身份注册输入源，加载 `/Library/LaunchAgents/com.roarkist.roarkt.translation.plist`，为控制台用户打开主 App。没有登录用户时提示登录后打开主 App 添加输入源。普通启动打开设置；在“权限”页检查输入源与授权，在语音/翻译/AI 设置中按需准备，不再有独立首次引导。不启用或选择输入源，不改系统输入源偏好。

签名包构建成功不代表已公证或完成安装验收。请在干净测试账户中验证安装、同产品升级、输入法重新启动和卸载，勿对日常账户自动执行破坏性测试。

## 当前产物与验收边界

SPEC-014 已加入截图标注/圆角/贴图历史、OCR 与图片 AI 预览、快捷键速查及菜单入口，用户操作见 [功能手册](../docs/features.md)。这些界面可构建不代表真实权限、键盘、麦克风、多显示器已经验收。

`build.sh` 在签名前将许可证和第三方声明放入主 App，关于页打开包内文档；Gallery/Mock 仅用于 debug，release 构建会检查符号边界。历史规格中的安装/发布证据不因本说明更新而改写。GPL 对应源码材料仍需按 [GPL-SOURCE](../LICENSES/GPL-SOURCE.md) 随正式 release 交付。

## 更新发布

Sparkle 固定为 2.8.0。当前由关于页按需启动更新控制器；AppDelegate 尚未在启动时调用该入口，因此不能宣称每次启动都会安排自动检查。主 App 的 Info.plist 尚需发布负责人填入 GitHub Releases 的 `SUFeedURL` 和真实 `SUPublicEDKey`；占位期间不会启动 Sparkle 或请求网络。每次发布必须递增 `CFBundleVersion`。

私钥用 Sparkle `generate_keys` 保存在用户钥匙串，不提交、不导出。公证并 staple 后运行：

```sh
ROARKT_SPARKLE_KEY_ACCOUNT=ed25519 scripts/make-appcast.sh \
  dist/RockType-0.1.0-macOS-arm64.pkg \
  https://github.com/OWNER/REPO/releases/download/v0.1.0/RockType-0.1.0-macOS-arm64.pkg \
  dist/appcast.xml
```

脚本使用 `sign_update`，因为 Sparkle 的 `generate_appcast` 不支持 pkg。生成前验证公证票据；从 pkg 提取版本和公钥，并验证 Ed25519 签名，输出 `guided-package` feed。同一发布上传原样 pkg 和 appcast.xml；脚本不上传。先发布源码材料及许可证，再发布二进制。升级必须在 main 的测试安装上验收，确认输入法进程退出后重新加载及用户数据保留。
