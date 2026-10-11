# SPEC-003 输入法与候选翻译（M1）

- 阶段：M1
- 覆盖需求：FR-A1–A11、FR-E1（离线与静态路径）、FR-E8（输入法部分）、NFR-2
- 状态：Ready
- 依赖：SPEC-001（输入法迁移已完成）、D0 U4 候选窗/输入模式提示设计

## 范围

输入法功能已由 T3 从 RoType 迁入。M1 补齐两件事：**候选窗、译文栏、输入模式提示按 D0 基线重做视觉**；**把 RoType 已有能力在 RoarkT 上重新验证并补测试**。不新增功能。

## 视觉对齐（以 `App/Surfaces/CandidateView.swift`、`InputModeView.swift` 与 `dist/gallery/candidate-*`、`input-*` 为准）

- 候选窗：拼音行 + 横排 5 候选；高亮项强调色底；序号弱化；字号、间距、圆角、阴影取 D0 Tokens 数值（输入法不能链接 App 代码，在 `InputMethod/sources` 内用常量复刻，并在注释中注明对应 Token 名）。
- 译文栏：候选窗下方独立卡片；左侧图标 + 小标题（候选翻译 / 静态词条 / AI 改写 / 翻译中 / 不可用）+ 译文；右侧 `Tab` 提示；长译文单行截断。
- 输入模式提示：中 / 英 / 方案名胶囊，出现与消失动效按 Tokens.Motion，遵守减少动态效果。
- 浅色/深色跟随系统；多显示器、屏幕边缘、全屏应用位置正确。
- 截图证据：在 TextEdit 中真实输入后的屏幕截图（需屏幕录制权限，由用户协助）或离屏渲染 `SquirrelPanel` 的 PNG，与 Gallery 对照。

## 能力复核（自动化为主，真实键盘项标“待人工验证”）

| 需求 | 复核方式 |
| --- | --- |
| A1 全拼、词频学习、首启自动部署 | `scripts/test-rime.sh` 扩展：部署后用 `rime_api` 测试程序（或 RoType 的 `test-candidate-session.sh` 迁移版）输入样例，断言首选 |
| A2 小鹤双拼 | 同上，双拼编码样例 |
| A3 模糊音、简拼、纠错 | 同上，样例集 |
| A4 Shift 切换 | 迁移 RoType `test-modifier-keys.sh` 中可自动化部分 |
| A5 英文短语单引号 | 样例断言上屏文本 |
| A6/A7 候选翻译 generation 隔离 | 已有服务测试 + 输入法侧 session 测试 |
| A8 静态词条 | 断开服务时的译文栏状态测试 |
| A10 学习菜单 | 删词后重新部署仍生效 |

迁移 RoType 中相关脚本时一律改名，删除升级/退休相关用例。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| I-1 | 候选窗、译文栏、模式提示视觉对齐 | pi-ime | 未开始 |
| I-2 | 能力复核测试迁移与补齐，接入 `scripts/test.sh` | pi-ime | 未开始 |
| I-3 | 真实打字验收 | 用户 + Claude | 未开始 |

**文件所有权**：`InputMethod/sources` 中候选窗、面板、主题相关文件，`InputMethod/scripts`、`scripts/test-*.sh` 新增项、`Tests/`。另一个 agent（pi-ui）正在 `InputMethod/sources` 中做设置同步（读取 settings.json、redeploy 通知），避免修改其涉及的文件；如必须修改同一文件，改动集中并在汇报中列出。

## 验收

| 项 | 方法 | 结果 | 证据 |
| --- | --- | --- | --- |
| 视觉与 Gallery 一致（浅/深） | 截图对照 | 未运行 | |
| A1–A5、A8、A10 自动化 | `scripts/test.sh` | 未运行 | |
| 真实打字：全拼、双拼、Shift、英文短语、Tab 上屏译文 | 用户 | 待人工验证 | |
| 打字延迟不受翻译服务影响（NFR-2） | 停掉翻译服务后试打 | 待人工验证 | |

## 进度

## 问题
