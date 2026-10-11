# ADR-0002：标识符、许可证与默认快捷键

- 状态：Accepted（2026-10-11，用户确认“按建议执行”）。

## 决策

1. **标识符前缀**：主 App 与服务用 `com.roarkist.roarkt.*`；输入法用 `com.roarkist.inputmethod.RoarkT`（IMK 要求 Bundle ID 含 `inputmethod`）。显示名 “RoarkT”。完整列表见[技术架构](../architecture.md)。
2. **许可证**：`InputMethod/`（Squirrel 修改）为 GPL v3，随发布提供源码；其余代码为 MIT。MIT 部分不得链接或复制 GPL 代码，只通过 `Shared/XPCProtocol` 中的 XPC 协议与输入法通信。
3. **默认快捷键**：语音按住 `Fn`；截图 `⌃1`（用户长期习惯）；翻译 `⌃⌥T`；总结 `⌃⌥S`。全部可在设置中修改（FR-E7）。

## 影响

- `Fn` 可能与系统“按两下 Fn 听写”或“按 Fn 切换输入法”冲突：引导与快捷键设置中检测并提示用户关闭系统对应选项。
- `⌃1` 在部分应用中有含义（如切换桌面 1 的系统快捷键，默认关闭）：注册失败时按 FR-E7 显示冲突。
