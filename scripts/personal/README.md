# RockType 个人词库工具

仅供用户明确授权后离线执行，不由安装器或主 App 自动调用。脚本不会安装、注册、启动输入法或重新部署。W-4 开发只用合成文本和临时目录；真实用户数据由 Claude 在合并后处理。

两个入口使用相同的目录优先级：`--rime-dir` 参数 → `ROARKT_RIME_USER_DIR` 环境变量 → `~/Library/Application Support/RoarkT/Rime`。环境变量未设置或为空时使用默认值；目标目录必须已存在，不自动创建或寻找其他目录。路径含空格时须加引号，例如 `export ROARKT_RIME_USER_DIR="$HOME/Library/Application Support/RoarkT/Rime"`。实际执行前退出输入法及会写 custom 文件的设置程序，再传 `--offline`。不运行脚本替你停止进程。目标及其子项拒绝符号链接；源树不跟随符号链接，排除隐藏目录、`.git`、`.build`、`node_modules`。只输出数字统计、状态及备份 ID，不输出词条、文本、路径或子工具诊断。产物及临时文件在私有目录中，umask 为 077。

依赖为开发工具，不打入产品：Python 3.9+、PyYAML 6、Xcode command line tools（Swift + 系统 NaturalLanguage/Foundation ICU）；迁移还需要 `rime_dict_manager`。繁简转换使用 macOS 自带 ICU `Hant-Hans`，不依赖外部 OpenCC，也不需要下载转换词典。PyYAML 为 MIT，librime 为 BSD-3-Clause。

## 个人词表

以下 `$profile`、`$approved_source`、`$dictionary_sources` 都应由执行者设为审核过的绝对路径。默认仅统计，显式 `--apply --offline` 才写入。

```sh
python3 scripts/personal/build-personal-dict.py \
  --rime-dir "$profile" --source "$approved_source" \
  --dictionary-dir "$dictionary_sources"
# 核对摘要后，使用完全相同参数加 --apply --offline
```

`--source` 可重复传入；传 `--allow-default-source` 且不传 `--source` 才授权默认的 `~/Repos`。中文仍读取 `.md` 全文和 `.swift` 的注释、普通/多行/raw 字符串。英文只统计 Markdown 正文及 Swift 注释中的散文，不从 Swift 字符串提取。英文扫描会剔除 Markdown 元数据、围栏/缩进代码块、行内代码、链接地址、URL、路径、图片及 HTML 代码块；保留链接的可见正文。嵌套注释受支持，含插值的整个字符串不统计，表达式里的代码及字符串也不统计。这是保守词法扫描，不是完整 Swift parser；遇到不完整字符串/注释会失败而不发布，复杂正则字面量等语法应先移除该来源或改用明确整理的 Markdown。

英文候选必须是 2–48 个 ASCII 字母；拒绝数字、下划线、内部点号等复合 token，整项排除，不拆出其中片段。拒绝 camelCase/PascalCase 标识符与内置小写关键字/API 停用词。保留普通单词、首字母大写专名（如 Herdr、Magpie）和全大写缩写（如 MLX、LLM）；RockType 等混合大小写品牌由 `english_prose.py` 的小型明确白名单保留。与主词库英文条目忽略大小写去重。同一英文词的大小写变体合并频次，只输出一条；优先采用非句首出现最多的写法，平票优先小写。句首普通首字母大写只计频次、不作为专名证据；只有句首出现且没有其他写法证据时用小写，明确品牌与全大写缩写仍保留大小写票数。该规则是保守筛选，无法仅凭拼写区分所有品牌和代码：新混合大小写品牌需补入白名单，复杂 Markdown 的缩进正文可能被略过。

`--dictionary-dir` 必须包含完整的 `roarkt_zh`、`roarkt_en` 及其递归 `import_tables` 源文件；缺失即失败，不以不完整的主词库去重。递归读入所有 `import_tables`，并按顶层字典的 `use_preset_vocabulary` / `vocabulary` 读取预置词表（默认 `essay.txt`）；预置词表缺失也拒绝继续。主词库和分词输入均使用 macOS ICU `Hant-Hans` 在简体空间比较，因此兼容尚含繁体条目的过渡词库。本版本仅输出主词库**缺失**的词，不推断候选真实排名。中文使用 macOS `NLTokenizer`，英文保留原始大小写（编码小写）；默认至少出现 3 次，最多 1500 条，可用 `--min-count` / `--limit` 调整。重复词按次数降序、词文字典序稳定排序，权重上限 100，避免未经评测就抢占日常首选。分词和多音字自动编码质量仍需试打；不承诺提取所有领域复合词。

中文候选还会经过质量过滤：排除 `第?[〇零一二三四五六七八九十百千万两]+` 及常见量词组合（同时识别约数前缀/后缀）；排除能完全由主词库至少两个 2 字及以上词组成的候选，以及由主词库词加一个边缘单字组成的候选。分词时仅在内存保留左右最多 15 字的连续汉字上下文；某个词至少 80% 的分词出现都嵌在同一个更长候选或主词库词中时，按碎片排除。不同长词的包含次数不会相加；有足够独立用例的词保留。过滤、大小写合并和频次门槛均先于总上限截取。

产出共 6 个个人层文件：

- `roarkt_personal.dict.yaml`：只包含可编码的个人中文词，每行写显式拼音；不导入或替换主词库。
- `roarkt_personal_en.dict.yaml`：只包含个人英文词，显式小写字母编码；不导入主英文词库。
- `roarkt_personal.schema.yaml`、`roarkt_personal_flypy.schema.yaml`、`roarkt_personal_en.schema.yaml`：编译依赖。中文全拼/双拼各有独立 prism，分别引用对应工厂方案的 speller；不是新增用户输入源。
- `roarkt_personal.patch.yaml`：`pinyin` / `flypy` 两节仅追加 `engine/translators`、编译依赖和个人 translator 配置。主 `translator/dictionary: roarkt_zh`、`english/dictionary: roarkt_en` 及其学习设置保持原样。个人中文使用 `script_translator@personal_zh`，英文使用 `table_translator@personal_en`；初始质量 0.1，禁用个人层造句、补全与 userdb。某语言没有可用词时不挂载该语言的 translator/依赖，避免部署空词库。

中文编码递归读取 `roarkt_zh` 的词表及逐字读音：先取整词最高频显式读音；否则组合逐字最高频读音。简体词/字在表中没有读音时，用系统 ICU `Hans-Hant` 查对应繁体字形。预置词频和百分比权重纳入读音选择。无法得到完整拼音的候选丢弃，摘要输出 `unencoded_chinese`，不写空编码列。

设置生成的两份 custom 分别引用 `roarkt_personal.patch:/pinyin?` / `roarkt_personal.patch:/flypy?`，不存在个人文件时正常部署。更新到本实现后需由设置所有者重新生成 custom；旧的 `/patch?` 引用不会挂载本文件。个人脚本从不读取、修改或备份 custom；手写 custom 由其所有者采用对应引用。重复生成内容相同则不写文件。

设置同步与个人脚本各自管理自己的文件：设置重写 custom 不影响个人词典，个人脚本回滚也不撤销设置变更。已用真实 librime 验证缺失引用、加入词表、重写设置后继续命中个人词，以及回滚删除个人 patch 后恢复工厂词典。个人层文件没有生成标记时拒绝覆盖。

成功写入会输出 `backup_id`。回滚只恢复这 6 个个人层文件，且要求它们仍与本次生成内容相同；有后续手改则拒绝覆盖：

```sh
python3 scripts/personal/build-personal-dict.py \
  --rime-dir "$profile" --rollback "$backup_id" --apply --offline
```

备份位于目标的 `roarkt-backups/<UTC时间>-personal/`，记录原文件及哪些文件原本不存在。发布遇到普通异常会恢复已经写入的文件；强制断电/kill -9 可能留下部分发布，应从备份人工恢复，不能宣称多文件操作具有文件系统事务保证。完成或回滚后由 Claude 手动重新部署。

## 学习词简体转换

**主词库全简体后执行**：等待 SPEC-011 D / W-6 合并并部署全简体主词库，再由 Claude 在授权的离线窗口处理用户 userdb。本次开发仅用临时数据库验证，不提前操作真实学习数据。

只处理当前 `roarkt_zh.userdb`，不搜索或读取任何旧产品数据。备份指定 Rime 目录的用户数据（排除备份目录自身、脚本锁及顶层真实 `logs/` 目录），保存到 `roarkt-backups/<UTC时间>-simplified/original/`，不覆盖已有备份。日志目录内的 librime 符号链接随日志一起排除，不读取、不复制也不修改。若 `logs` 本身是符号链接，或其他目录含非常规成员，仍拒绝；不会泛化为允许符号链接。禁止在线迁移；脚本通过独立进程持有 LevelDB POSIX 锁，并检测备份及发布前数据库是否变化。

```sh
scripts/personal/migrate-userdb-simplified.sh \
  --rime-dir "$profile" --offline \
  --manager "$rime_dict_manager"
```

`--manager` 指向能正常找到 librime 的可执行文件。仓库测试采用与现有 RimeChecks 一样的临时 `bin/` + `Frameworks` 布局，不运行输入法 App。转换器在私有临时目录编译，仅通过进程管道接收词条，不输出词条内容。

流程：完整备份 → 在备份副本导出 TSV → 仅词条文本经 macOS ICU `Hant-Hans`（编码不变）→ 同词同编码累计提交次数 → 导入空数据库 → 再导出逐条核对 → 同文件系统替换。不同编码不合并，溢出或条数不匹配即失败。没有繁体变化则不替换数据库，仍保留这次完整备份。转换/导入失败不修改原库；所有中间导出都随私有临时目录清理。

**数据语义限制**：librime `--export` 不导出被删除的词和完整的时间/动态学习元数据，`--import` 重建它们。该脚本保证可导出词条的编码和提交次数，不保证原始排序完全相同。保留字节级原库备份用于回滚；真实“常用词仍优先”由 W-5 试打确认。

```sh
scripts/personal/migrate-userdb-simplified.sh \
  --rime-dir "$profile" --offline --rollback "$backup_id"
```

回滚只替换 `roarkt_zh.userdb`；完整 profile 备份供人工恢复其他文件。若迁移后发生学习、部署或别的写入导致库文件改变，回滚拒绝，避免丢掉后续数据。极端中断发生在两个目录 rename 之间时，应停用输入法后从 `original/roarkt_zh.userdb` 人工恢复；不要删除备份。迁移不自动部署。

## 复现临时目录测试

无需准备 OpenCC。真实部署回归必须使用本 worktree 的完整构建产物，先运行：

```sh
scripts/build.sh
swift test --filter personalScriptsInTemporaryDirectories
scripts/test.sh
```

测试使用 `scripts/build.sh` 产物内的真实 SharedSupport、librime 与系统 ICU，缺少产物或工具时失败，不跳过。临时 profile 对照验证主中英文 table 尺寸及字节一致、无 Encode failure、常用词首选不变、个人中英文可查到，并覆盖仅英文/空个人层。测试经 `RoarkTPersonalScriptsTests` 注册在 Package.swift，统一测试入口可运行。

测试入口先调用实际 `RimeSettingsPatchWriter` 生成默认及修改后的设置文件，再将私有 fixture 路径交给 Python 检查；完整 `checks.py` 是内部子进程，不单独运行。
