# 分发

先运行 `scripts/build.sh`，再运行 `scripts/build-installer.sh`。后者使用 `dist/` 的已有产物，在临时目录内加许可证、同步版本、为嵌套代码补时间戳签名，产出 `dist/RoarkT-<版本>-macOS-arm64.pkg`。不会安装到本机。可用 `ROARKT_CODESIGN_IDENTITY` / `ROARKT_INSTALLER_IDENTITY` 指定证书，默认使用架构规定的团队。

安装只支持当前启动卷。preinstall 在所有已登录 GUI 会话内退出固定安装路径的两个应用，等待最多 8 秒；拒绝退出则中止，不强杀、不删除用户数据。postinstall 以登录用户身份注册输入源，加载 `/Library/LaunchAgents/com.roarkist.roarkt.translation.plist`，为控制台用户打开主 App。没有登录用户时提示登录后打开主 App 完成引导。不启用或选择输入源，不改系统输入源偏好。

签名包构建成功不代表已公证或完成安装验收。请在干净测试账户中验证安装、同产品升级、输入法重新启动和卸载，勿对日常账户自动执行破坏性测试。
