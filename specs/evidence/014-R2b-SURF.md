# R2b-SURF：截图视觉服务接入

日期：2026-10-11；负责人：pi-surfaces；工作分支：`agent/surfaces`。

## 任务与范围

- [x] 开始前 `git merge main`，结果 Already up to date。
- [x] 截图翻译、截图总结、理解图片统一调用 `ScreenshotAIService`，发送 PNG + 当前 OCR 编辑值。没有编辑值时先在本机 OCR；识别为空或用户清空时允许仅图片请求，不重新填回已删除文字。
- [x] 发送前显示原图、实际文字、动作、连接名称/主机和模型；取消确认不发送。连接/模型/能力发生变化后原确认失效。
- [x] “以后不再询问”只在确认发送时保存；截图设置追加可缺省解码的 `skipImageAIConfirmation: Bool?`，旧配置默认为每次询问。“图片操作”提供恢复入口；重试始终再次确认。
- [x] 面板支持思考状态、流式正文、取消、失败重试、完成后复制和追问。只显示“思考中”，不显示或保留推理正文；空最终正文不能成功，失败/取消清理未完成正文。
- [x] 保留仅文字 OCR 翻译及其思考状态，纯文字通路不包含图片。
- [x] 贴图右键翻译进入同一视觉确认；右键 OCR 进入同一预览并只做本地识别。
- [x] 主规格仅新增 R2b-SURF 一行，未改其他任务及已有证据。

## 实现说明

`ScreenshotVisualAI` 管理确认快照和异步生命周期，实际发送经 `ScreenshotAIService → AIClient`。请求限制为 PNG 10 MB、文字 32 KB；编辑、取消、关闭、切换批次均使旧回调失效。Secure Input、当前连接或已验证模型失效时停止请求并丢弃未完成内容。没有新增 provider、传输协议或缓存。

原图、OCR 编辑区和结果共用预览，原图可展开；确认阶段显示完整发送摘要。视觉与纯文字翻译可切换，长内容保留滚动。批量导入沿用同一 session，复用记忆确认设置，不因导入或切换自动发送。

追问复用现有结果窗口，仅携带已完成的文字结果，不带原图和原始 OCR。窗口明确说明此限制；三个视觉动作的原请求都不能在结果窗口直接重试，需返回预览重新确认。追问不会自动上传原图。结果进入现有会话内最近结果的时机是用户点击“追问”，并遵守现有内存记录设置。

跨负责人区域仅做小范围接线：`ScreenshotSession`/`ScreenshotCoordinator` 绑定新模型与入口；`SelectionOperationsController`/`LiveResultWindowView` 扩展三个图片动作的识别；`AppSettings` 仅追加带默认值字段。未修改 `ScreenshotAIService`、`CaptureCanvas` 或设置持久化实现。

## 自动化验收证据

- `VisualAIWorkflowTests`：三个动作确认前零请求，发送内容等于确认快照；用户清空文字不会重跑 OCR；思考/流式/取消/迟到回调；记忆选项、恢复每次确认与强制重试确认；编辑/连接/能力/受保护输入失效；追问仅包含完成结果；旧设置缺字段与新字段 JSON 往返；请求大小上限；贴图翻译/OCR 路由。
- `VisualAIServiceBridgeTests`：真实预览模型 → 生产 `ScreenshotAIService` → 生产 `AIClient`，仅网络传输由 URLProtocol 替代。三个动作逐项断言请求 JSON 的模型、提示词含编辑值、PNG data URL；确认前无传输；推理事件随后返回正文，界面最终只保留正文。无真实网络、凭证或用户图片参与。
- `VisualAIRenderingTests`：确认、思考、流式、完成、失败五态 × 明暗两主题的 AppKit 离屏渲染；合成图片和文字。检查了确认及完成截图，调整默认原图高度以让结果操作可见；离屏渲染不等同真实键盘/鼠标验收。
- 既有 `SessionTests`、`M4IntegrationTests`、`PreviewWorkflowTests` 验证旧 OCR、纯文字翻译、生命周期、最近结果和追问兼容性。

门禁结果：

| 验证 | 状态 | 证据 |
| --- | --- | --- |
| `scripts/test.sh` | 通过，退出 0 | 最终 108 XCTest + 191 Swift Testing 全部通过；Rime、AppShell、旧标识检查通过。日志 `/tmp/surfaces-r2b-test-final.log`，退出码 `/tmp/surfaces-r2b-test-final.exit`。 |
| `scripts/build.sh` | 通过，退出 0 | App、Agent、输入法及工具完成签名；语音 MLX 自测通过。日志 `/tmp/surfaces-r2b-build.log`，退出码 `/tmp/surfaces-r2b-build.exit`。 |
| 最终 diff 检查 | 通过 | `git diff --check` 无空白错误；主规格只新增任务行。 |
| 安装版本真实交互与真实 AI | 待人工验证／本轮未运行 | 具体边界见下文。 |

离屏文件：`/tmp/roarkt-r2b-{confirm,thinking,streaming,done,failed}-{light,dark}.png`；只含合成内容，不提交图片。

## 未验证与限制

- 待人工验证：安装版本真实截图/贴图右键、确认勾选与重启保持、实际网络服务思考/流式/取消、剪贴板复制结果、结果窗口继续追问、多屏/窄窗口、VoiceOver 与文本焦点。
- 本轮未调用真实 AI 端点；传输测试使用生产序列化/流解析配合合成 SSE，不能替代供应商质量和延迟验收。
- 不支持保留原图的多轮视觉追问；当前明确使用已完成的文字结果。需要图片细节时重新从预览发送。
- 超过 10 MB 的 PNG 或 32 KB 的 OCR 文本会在确认前提示缩小选区/精简文字，不静默截断或缩放。
- 运行全仓构建/测试不等于输入法安装验收；未安装、注册输入法、加载 LaunchAgent 或注入全局输入。

## 与 main 融合（2026-10-11）

- 合入 main `f84b085`。保留 pi-xpc 的 `ScreenshotImportController`、`presentBatch`、`ScreenshotSaveAsController` 与统一图片导出结构；单图和批量 session 均接入视觉 AI 确认偏好，贴图翻译入口保持视觉确认路径。
- 设置同时保留 `roundedCorners` 与 `skipImageAIConfirmation`，均允许旧 JSON 缺字段。设置往返测试同时携带两个字段，防止合并丢失任一偏好。
- 扩展 `MergeImportTests`：批量 session 能恢复每次确认、以编辑文字准备视觉总结；切换到剪贴板导入清除原批次图片及待确认请求，新单图继续使用同一确认偏好回调；导入不弹出保存对话框。
- 主规格保留 R2-SHOT、R2-UI、R2-ARCH 及 R2b-SURF 的实际进度。逐行核对两边“验收证据”及证据文件均保留。
- 本次 `scripts/test.sh` 与 `scripts/build.sh` 真实退出码均为 **0**：135 XCTest + 198 Swift Testing 通过，完整签名构建与语音 MLX 自测通过。日志 `/tmp/surfaces-r2b-merge-{test,build}.log`，退出码保存于同名 `.exit` 文件。真实安装版本交互仍待人工验证；未安装、注册输入法或加载 LaunchAgent。
