# R3-SURF：覆盖式图片翻译与二维码/条码

日期：2026-10-11；负责人：pi-surfaces；分支：`agent/surfaces`。

## 任务

- [x] 开始前 `git merge main`，结果 Already up to date。保留 importer、saveAs 与既有视觉 AI 接线。
- [x] 基于 OCR 区域，一次整图批量翻译，再本机生成覆盖译图。预览切换原图/译图，支持复制、保存与贴图。
- [x] 翻译复用 `DefaultOperationRunner` 和现有 Apple Translation XPC 路由。默认离线优先，可显式选择 AI。翻译只传文字，不传图片；未更改原有视觉 AI 功能。
- [x] Vision 本机识别二维码与条码，文字 OCR 时并行识别（包括遮罩 ⇧C 路径），也可单独触发。支持复制内容；完整展示 URL 后确认打开，不自动导航。
- [x] 贴图右键新增覆盖翻译、二维码/条码入口，复用同一预览。
- [x] 程序生成图片的识别、工作流、绘制与离屏渲染测试。主 spec 仅新增 R3-SURF 一行。

## 实现与取舍

`ScreenshotOverlayTranslation` 把本图所有 OCR 行以稳定区域编号封装成一个文字请求，复用现有路由：Apple 优先，离线不可用时按既有配置回退 AI；显式选 AI 时跳过离线。每张图一个逻辑请求，不逐框发送；底层既有错误重试规则不变。返回允许编号重排，但缺号、重复号、未知号、空区域、缺结束标记均失败，不拼凑错位译图。默认目标语言沿用设置与现有中英自动判定。

`ScreenshotTranslatedImageRenderer` 按 OCR 左上原点归一化坐标绘制，以原图区域边缘的主要取样色填底，按明暗选择黑/白文字。字号逐步缩小并支持换行，不扩展区域侵占邻行；无法完整容纳时整图失败，不静默截断。取样始终来自原图，输出保留尺寸。绘制运行在后台，取消时丢弃结果。请求限制为 200 个区域、12 KB 源文本、64 KB 译文；绘图限制为 6400 万像素、单边 16000px，最小字号 4px。

覆盖翻译使用几何 OCR 行，不使用自由编辑框中的整段文字，界面对此明确说明。编辑原文会清除旧译图；重新 OCR、关闭与受保护输入会取消任务并清理相关内容。切换批次取消未完成翻译，完成图可留在该图会话中；关闭整批清空。保存时固定用户选中的图片版本，避免保存对话框期间切换版本影响输出；原有 JPEG 白底规则保留。视觉 AI 请求仍使用原图，确认图也保持原图。

`BarcodeScanner` 使用 `VNDetectBarcodesRequest` 支持的符号类型，返回可解码文字和与 OCR 一致的归一化框。`ScreenshotBarcodes` 独立管理扫描、取消和 URL 确认；OCR 失败不阻止独立条码结果。仅 HTTP/HTTPS 且无用户信息、空白或控制字符的 URL 提供打开入口，其余内容可复制。确认页展示实际要交给浏览器的完整 `absoluteString`（含路径、查询与片段），打开时再次检查保护状态。没有轮询剪贴板、内容落盘或内容日志。

预览分为图片 AI、文字翻译、覆盖翻译、二维码/条码四个操作页，避免叠加所有工具。发现条码时在其他页显示结果入口。条码使用原图本机识别；原图/译图切换不改变识别来源。

## 验收证据

- `BarcodeScannerTests`：Core Image 程序生成同图 QR + Code 128，真实 Vision 返回精确 payload、符号类别及正确上下位置；非法图片、取消及 URL 策略检查。
- `OverlayTranslationTests`：区域重排、缺失/重复/未知编号和结束标记；浅/深背景绘图尺寸、区域外及填底颜色像素、可见内容变化、超长文本拒绝；真实 Vision 回读译图中的中文；取消/迟到/安全输入不能产生结果。
- `OverlayRoutingTests`：生产 `DefaultOperationRunner` 配合假的离线/AI 传输，断言全图只有一次离线调用、成功不进 AI、离线失败回退 AI 一次、显式 AI 跳过离线。实际 Vision OCR 框进入覆盖生成，原图/译图导出选择正确，编辑清除旧结果。该测试不代表真实语言包或供应商翻译质量验收。
- `BarcodeWorkflowTests`：扫描不导航、预览完整 URL 不导航、仅确认打开一次、取消和保护状态阻止打开；文字 OCR 同时启动扫描；关闭丢弃迟到结果。
- `PinnedImageTests`：两个新菜单项确实分发对应动作，原有菜单/透明度/历史行为保留。
- `R3RenderingTests`：原图、译图、处理中、失败与完整链接确认 × 明暗主题，以及 460pt 窄窗口；只创建离屏 AppKit 窗口，不启动产品 App、不截图真实桌面。

图片证据均可由测试重建：`/tmp/roarkt-r3-{original,translated,barcodes}.png`；预览 `/tmp/roarkt-r3-preview-{original,translated,running,failed,barcode-confirm}-{light,dark}.png` 与 `narrow-{translated,barcode}-light.png`。已读取检查译图与窄窗口 URL 确认图；非人工交互验收。

最终门禁（代码冻结后）：

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `scripts/test.sh` | 通过，真实退出码 **0** | 150 XCTest + 202 Swift Testing，以及 Rime/外壳/旧标识检查；`/tmp/surfaces-r3-verified-test.log` 与 `.exit`。 |
| `scripts/build.sh` | 通过，真实退出码 **0** | 完整签名构建、语音 MLX 自测及脚本内 XPC 冒烟；`/tmp/surfaces-r3-verified-build.log` 与 `.exit`。 |
| `git diff --check` | 通过 | 主 spec 仅新增一行；不改设置、翻译服务或画布结构。 |

开发中一次构建因源文件在编译期间修改而退出 1（`/tmp/surfaces-r3-delivery-build.log`）；冻结源码后顺序重跑上述门禁均为 0。最终复查同时修复了带前置空白的译文编号范围解析，并覆盖 emoji、缺结束标记、超长输出、边界外区域；不把失败或部分结果当作译图。

## 未验证与限制

- 待人工验证：安装版 Apple 离线语言包/真实 AI 的区域标记保留与翻译质量、连续取消、多屏/Retina、真实复制/保存/贴图、遮罩与右键操作、默认浏览器打开、VoiceOver。
- 本轮没有调用真实 AI、修改真实设置或访问用户图片；路由验证使用生产 runner + 合成传输。若供应商改写区域标记，明确失败并允许重试/切换路由，不暗中逐行补请求。
- 复杂照片/渐变底图使用区域主要取样色平填，不是图像修复；重叠框、竖排、极小文字与过长译文不保证理想排版。字号最低 4px 的极密文本仍可能需要放大或改用文字翻译。
- Vision 未返回文本 payload 的二进制码不展示；非 HTTP/HTTPS 内容只支持复制。未新增联系人、Wi-Fi、支付或任意自定义 URL scheme 动作。
- 未安装或注册输入法、未加载 LaunchAgent、未模拟全局输入。尝试的并行助手因无模型凭据未执行，已关闭；实现和验证由主会话完成。
