# 取词兼容矩阵（SPEC-017 T6）

2026-10-11，本机检查。**安装检测不是取词通过**。自动测试使用合成选区与隔离剪贴板；以下应用没有由 agent 接管真实窗口或读取用户文档，因此直接读取、复制回退的真实结果如实保留为待人工。

| 应用 | 安装检测（自动） | AX 直接读取 | 复制回退 | 注意点 |
| --- | --- | --- | --- | --- |
| TextEdit | 已检测到 | 待人工 | 待人工 | 分别检查纯文本、富文本 |
| 备忘录 | 已检测到 | 待人工 | 待人工 | 笔记正文与列表分别检查 |
| Safari | 已检测到 | 待人工 | 待人工 | 网页正文、输入框分别检查 |
| Chrome | 已检测到 | 待人工 | 待人工 | 可检查的安全焦点下，尝试 AXEnhancedUserInterface |
| VS Code | 未检测到 | 待人工 | 待人工 | 安装后检查编辑器与内置终端；支持范围文本读取 |
| Xcode | 未检测到 | 待人工 | 待人工 | 源码编辑器、控制台分别检查 |
| 终端 | 已检测到 | 待人工 | 待人工 | Secure Keyboard Entry 开启时应拒绝 |
| iTerm2 | 未检测到 | 待人工 | 待人工 | 安装后检查复制选区配置 |
| Ghostty | 已检测到 | 待人工 | 待人工 | 终端应用可能仅提供复制回退 |
| 微信 | 已检测到 | 待人工 | 待人工 | 输入框、消息正文分别检查；不发送样本文字 |
| 飞书 | 已检测到 | 待人工 | 待人工 | 输入框、消息、文档分别检查；不发送样本文字 |
| Pages | 未检测到 | 待人工 | 待人工 | 安装后用新建本地文档 |
| 预览 PDF | 已检测到 | 待人工 | 待人工 | 有文本层 PDF；扫描 PDF 不据此判定 OCR 支持 |
| Notion | 未检测到 | 待人工 | 待人工 | 安装后使用空白测试页 |
| Obsidian | 已检测到 | 待人工 | 待人工 | 编辑、阅读视图分别检查 |

“未检测到”指 Launch Services 按 bundle ID 未返回存在的应用，不断言机器上绝对没有便携/未注册安装。未执行取词的项目不标为“不支持”。仅当安全状态允许、合成样本确实选中且直接/回退均失败，才记录相应界面不支持。

## 自动检查

```sh
ROARKT_SELECTION_INVENTORY=1 swift test --filter SelectionCompatibilityProbeTests
swift test --filter 'SelectionRangeTests|ClipboardTests|SelectionCapture'
```

本轮自动结果：4 项范围读取测试、12 项剪贴板测试及现有取词保护/回退测试通过。范围路径覆盖空/缺失 AXSelectedText、精确 UTF-16 选区、富文本降级、过大/溢出范围、读取途中保护变化。剪贴板覆盖延迟供给文本、超时、取消、来源变化、保护变化、多格式恢复及用户新复制优先。

## 人工 / 半自动检查步骤

1. 在目标应用的可丢弃本地文档中准备并准确选中 `RockType compatibility 42`。网页需要先由操作者准备测试页；不复用个人内容。聊天应用不要发送样本。
2. 运行下列检查；启动测试后有 5 秒切回目标选区。检查不激活应用、不截屏、不输出原文。将 bundle ID 换为目标应用的实际值。

```sh
ROARKT_SELECTION_PROBE_BUNDLE=com.apple.TextEdit \
  swift test --filter testExplicitSyntheticSelectionProbe
```

3. 如报告 unsupported，再显式允许一次复制回退（会发送带标记的 ⌘C，绝不发送粘贴）：

```sh
ROARKT_SELECTION_PROBE_BUNDLE=com.apple.TextEdit ROARKT_SELECTION_PROBE_COPY=1 \
  swift test --filter testExplicitSyntheticSelectionProbe
```

4. 记录“direct pass / fallback pass / 不支持 / 权限或保护阻塞”，以及应用版本、界面种类。不要保存选中文字、剪贴板内容、窗口标题或屏幕图。权限属于执行测试的宿主；最终安装版本必须再验收。
5. 分别检查空选区、切换窗口、选区改变、复制回退期间用户再复制、开启 Secure Input。用户新复制必须保留，保护状态下不得读内容。不要通过关闭安全输入来让保护测试通过。

## 路径与限制

- 优先 AXSelectedText；缺失/空值时，只请求 AXSelectedTextRange 指定的 StringForRange / AttributedStringForRange。最多 65,536 UTF-16 单元；不读 AXValue 整篇文档，不遍历网页。
- Chrome / VS Code 仅在保护检查通过、当前来源不变且属性可设置时启用 AXEnhancedUserInterface，再检查焦点与保护。无法检查密码角色时仍拒绝，不为兼容性绕过保护。
- 复制等待默认 650ms，调用方期限最高 1 秒；同一 changeCount 内等待延迟文本。遇到第二次写入拒绝归属判断，不恢复覆盖新内容。超时/取消仅在仍属于本次写入时恢复所有原格式。
- 与操作系统剪贴板 API 一样，无法严格区分“恰好只有一次、发生在等待期间的用户复制”和应用响应 ⌘C；changeCount 保护是有界的最佳努力，不是剪贴板所有权协议。
