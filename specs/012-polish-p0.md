# SPEC-012 打磨 P0（参考开源项目）

- 阶段：打磨 P1（输入法 / 语音）
- 状态：InProgress
- 来源：对比 Handy、FluidVoice、OpenWhispr、VoiceInk、雾凇、鼠须管、万象近期提交（2026-10-11）

## 任务

| # | 任务 | 执行 | 状态 |
| --- | --- | --- | --- |
| P0-2 | 合并上游鼠须管修复（只读参考 rime/squirrel 最新提交，不升级 librime）：终端/marked text 客户端直接上屏（Alacritty 等）、激活时同步硬件 Caps Lock 状态、切走输入法时可靠隐藏状态、程序化切换输入源时完成未上屏内容、翻页点击区域残留 | pi-xpc | 已实现，自动化通过；待人工验证 |
| P0-1 | 语音状态说实话：HUD 区分“加载模型 / 录音中 / 本机识别中 / 润色中”；按 Fn 时模型未就绪显示“模型加载中…”而不是卡在识别；无可用模型时不开始录音；无有效声音后不留错误态太久 | pi-ime | 代码完成，待人工验证 |
| P0-3 | 本地文字清理（不依赖 AI）：识别结果去掉句首/独立的口头填充词（嗯、啊、呃、额、那个、就是说 等，保守列表，不误删实义用法），合并多余空格，中文句末补句号（已有标点不动）；设置 → 语音 中一个开关，默认开启；单元测试覆盖误删边界 | pi-ime | 代码完成，待人工验证 |

## 规则

- 保持现有行为与 RoType 视觉，不做大改；每项一个或几个小 commit。
- 用户可见文字一律 RockType；不记录识别文本。
- 验收：`scripts/test.sh`、`scripts/build.sh` 真实退出码 0；需真实键盘/麦克风的项标“待人工验证”。安装与试用由 Claude 从 main 执行。

## 验收证据

### P0-2：上游输入法修复

- 参考仓库：`https://github.com/rime/squirrel`，克隆到忽略目录 `.build/vendor/squirrel`，HEAD `769ae426f33f500266101a88f694aab0d158e680`；只读对照，不提交 vendor、不升级 librime 或任何子模块。
- 移植范围：
  - `8ce1020` / `1dde022`：按应用选项 `force_marked_text_for_direct_commit`，仅对无 preedit 的非空直接提交先建立 marked text；Alacritty 默认启用。保留既有翻译取消与提交路径。
  - `c2280ad`：激活时从 `CGEventSource.flagsState(.combinedSessionState)` 同步 Caps Lock 位，保留其他 modifier 的现有初始化。
  - `8418c95` / `52d3bc3`：输入源切换通知以 `.deliverImmediately` 接收，在主队列核对当前输入源；切离 RockType 时调用当前活动控制器的既有停用逻辑，完成原始输入、隐藏模式提示/候选/译文、取消翻译及语音 ticket。正常停用后清空弱引用，通知不重复提交；全拼/双拼仍视为本产品输入源。此分支没有上游状态栏图标，不引入该 UI。
  - `769ae42`：重绘时无条件替换上下翻页命中路径，箭头消失时清除旧点击区域。
- 保持现有候选窗、译文栏、模式提示的视觉与 RockType 定制；未安装、注册或启动本 worktree 的输入法。
- 新增回归：沿用 `Tests/InputMethodTests/PanelChecks.swift` 和已注册的 `InputMethodChecks` testTarget，运行生产绘制/点击代码，检查首页清除上翻区域、末页清除下翻区域、关闭翻页同时清除两侧区域。
- 自动化验证（2026-10-11）：`scripts/test.sh` **通过，真实退出码 0**（包含上述生产面板回归）；`scripts/build.sh` **通过，真实退出码 0**（完整构建、签名校验及既有语音 worker 冒烟）；`git diff --check` **通过，退出码 0**。日志和退出码保存在 `.build/p0-2/test.log`、`test.exit`、`build.log`、`build.exit`。`git submodule status` 确认 librime 仍为 `a251145d`（1.16.0），所有子模块无改动。
- 待人工验证（由 Claude 从 main 安装试用）：Alacritty 全角标点直接上屏与普通中文输入；在其他输入源切 Caps Lock 后回到 RockType 再切换；菜单栏切走后提示及时消失；macOS 26 上通过 `TISSelectInputSource` 程序化切走时未上屏内容只提交一次、所有输入法浮窗消失，切回正常；实际翻页点击及原视觉保持。自动化构建不代替这些验收。
### P0-1（2026-10-11）
- 模型校验/加载移到开麦前；HUD 分别显示模型加载、录音、本机识别、AI 润色。加载中松开 Fn 或取消不会在加载完成后开麦；缺模型/校验失败不录音。空音频或空识别结果显示无有效声音提示，两秒后隐藏。
- 保留音频 tap 的 nonisolated 安装、worker 最后连接断开才退出/加载幂等、模型校验戳，未修改这些实现。
- 通过：`scripts/test.sh` 真实退出码 **0**（`/tmp/roarkt-p01-test-final.log`）；`scripts/build.sh` 真实退出码 **0**（`/tmp/roarkt-p01-build-final.log`），含签名和 worker XPC 冒烟。生命周期回归覆盖冷加载不开麦、加载中松键、缺失/损坏模型、润色阶段与空结果自动隐藏。
- 中间运行记录：首次构建因编译中修改源文件中断，未保留其退出码；一次全量测试退出码 **1**，既有 `xpcTimeoutFinishesAndRebuilds` 超时，未修改该测试，最终全量重跑通过。
- 待人工验证：真实 Fn、冷/热模型与麦克风指示、静音/无有效声音、跨应用填入、HUD 四阶段视觉及 Secure Input。未安装、注册或启动 worktree 输入法。
### P0-3（2026-10-11）
- 新增纯本地文字清理，在识别后、可选 AI 润色前执行；仅移除标点分隔的独立填充词（嗯、啊、呃、额、那个、就是说），无分隔的歧义用法保留。合并横向空白并保留换行；以汉字结尾且无标点时补句号，已有标点/引号不动。全是填充词时不调用 AI、不提交空结果。
- 设置 → 语音新增“本地文字清理”，默认开启；已有 RockType 设置缺少此字段时采用默认值，保留其他设置；关闭后沿用原识别文本处理。AI 失败回退使用清理后的文字。
- 通过：`scripts/test.sh` 真实退出码 **0**（`/tmp/roarkt-p03-test-final.log`）。覆盖实义前缀/引号/连续填充词/中英混排/空白/已有标点/幂等性、设置默认值与读写、开关到提交路径、全填充词零润色/零提交。首轮测试退出码 **1**，发现 Han 匹配包含句号导致重复补标点；已增加字母类别条件，最终全量通过。
- 通过：`scripts/build.sh` 真实退出码 **0**（`/tmp/roarkt-p03-build.log`），全部产物构建/签名及 worker XPC 冒烟通过。
- 待人工验证：真实识别文本、开关即时生效与重启持久化、语音设置 UI、AI 失败回退和真实输入框填入。未调用麦克风或真实 AI；P0-2 不在本次改动范围。
