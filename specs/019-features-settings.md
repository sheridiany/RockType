# SPEC-019 功能开关与设置界面重做

- 状态：InProgress（2026-10-12）
- 用户原话：“除了输入法打字外，其他的功能都可以设置是否启用；设置界面好好优化下，学习 https://github.com/yetone/magpie”；“截图的时候右键可以取消截图”。
- 约定：Claude 只规划/验收/合并，代码全部由 pi 实现。

## 已定契约（main 已提交）

`Core/Settings/AppSettings.swift`：`AppSettings.features: FeatureSettings?`（nil = 全部启用），读写用 `settings.enabledFeatures`。`FeatureSettings` 字段：`voice`、`selectionToolbar`、`selectionShortcuts`、`screenshot`、`screenshotHistory`、`pinning`、`inputMethodAI`，支持 `FeatureSettings.Feature` 枚举下标。输入法打字、候选（含已有的 `input.candidateTranslation`）不在此列。需要增字段时只追加、保持逐键 `decodeIfPresent ?? true`。

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| G1 | 功能开关运行时生效（App 侧） | pi-platform | 完成（test/build 0；独立审查阻塞，真实交互待验） |
| G2 | 输入法内 AI 开关在输入法侧生效 | pi-ime | 已实现；test/build 通过；真实 IMK 待人工验证（[证据](evidence/019-G2.md)） |
| G3 | 设置界面按 Magpie 风格重做 + “功能”总览页 | pi-ui | 未开始 |
| G4 | 截图时右键取消；修复整套测试中偶发失败的 `AnnotationStyleTests.testToolbarStyleChangeIsRememberedOnlyForThatTool`（单跑通过，整套偶发失败，疑似共享设置状态） | pi-xpc | 实现及 test/build 通过（0）；真实焦点/多屏待人工，见 [证据](evidence/019-G4.md) |

## G1 运行时生效（pi-platform）

- 关掉即彻底停：语音 → 不监听 Fn、停止并释放 voice worker/模型；划词工具栏 → 不监听选区、不弹；划词快捷键 → 注销翻译/总结/自定义文字动作全局快捷键；截图 → 注销 ⌃1 及截图类快捷键（含图片动作快捷键）、菜单入口隐藏；截图历史 → 不记录并清空内存历史；贴图 → 贴图入口隐藏、已有贴图保留可关。
- 打开即时恢复，不需要重启；与已有的权限/Secure Input 保护共存；菜单栏面板与快捷键速查只显示启用的功能。
- 被关闭功能的快捷键在快捷键页显示为“已停用（功能关闭）”，不报冲突。
- 测试：每个开关的注册/注销与资源释放、旧设置 JSON 无 features 时全部启用。

## G2 输入法侧（pi-ime）

- `inputMethodAI` 关闭时 ⌥Tab 不触发、不请求 AI，按键交还系统/原行为；经现有设置同步通道到输入法，不重启输入法即可生效。若输入法读取设置走 `InputMethodPreferences`，按现有方式扩展（注意 Squirrel.xcodeproj 只编译 AppSettings.swift 与 InputMethodPreferences.swift）。

## G3 设置界面重做（pi-ui）

参考图：`/Users/xuean/Repos/00-Roark/RoarkT/.build/ref/magpie/*.png`（Magpie 截图，仅参考不入库）。要点：
- 顶部分段标签（或保留侧栏但同等简洁）、浅灰窗口底 + 白色大圆角卡片分组、卡片内行列表 + 细分隔线；每行：左侧图标、标题、下方一行次级状态（带状态圆点，如“已启用 · 按住 Fn”“需要麦克风权限”）、右侧值/选择器 + 开关；“更多 ⌄”折叠次要项；分组小标题用大写/小号次级色。深色模式同样精致。
- 新增首页“功能”：列出语音、划词工具栏、划词快捷键、截图、截图历史、贴图、输入法内 AI、候选翻译（`input.candidateTranslation`），每行开关 + “设置 ›”跳转对应页；状态行显示快捷键与权限状态。
- 其余各页（通用、输入法、翻译、语音、划词、截图、AI 连接、操作模板、快捷键、权限、隐私、关于）统一改成上述行卡片样式；AI 连接页的服务商列表参考 Magpie Providers/Add provider 卡片网格。
- 功能关闭时对应设置页顶部提示“此功能已关闭”并提供开启按钮，其余项置灰。
- 只改设置界面与组件；运行时逻辑由 G1 负责。离屏深浅色前后对比放 `.build/g3/`。

## G4（pi-xpc）

- 截图选区/遮罩状态下鼠标右键：未开始框选或已框选未标注 → 直接取消截图；正在编辑文字时右键不打断输入。与 Esc 行为一致（恢复焦点到原应用）。
- 修复上面的偶发失败测试，找到共享状态根因，不靠重试掩盖。

## 通用

遵守 AGENTS.md；先 `git merge main`；test/build 真实退出码 0；更新本表与 `specs/evidence/019-<编号>.md`；每任务一个 commit；需真实交互的标“待人工验证”。

## 验收证据

- G1：[App 侧运行时功能开关](evidence/019-G1.md)。沿用既定 FeatureSettings 契约，覆盖热键、语音、划词、截图/历史/贴图及 App 侧输入法 AI 配置撤销；新增 9 项回归。最终 test/build 实际退出 0；独立审查因提供方凭证缺失及 `fire-review did not start` 未完成，真实桌面/输入法交互待人工验证。
