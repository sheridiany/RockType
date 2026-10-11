# RockType 个人词库工具

仅供用户明确授权后离线执行，不由安装器或主 App 自动调用。脚本不会安装、注册、启动输入法或重新部署。W-4 开发只用合成文本和临时目录；真实用户数据由 Claude 在合并后处理。

两个入口必须显式传入已有的 `--rime-dir`。实际执行前退出输入法及会写 custom 文件的设置程序，再传 `--offline`。不运行脚本替你停止进程。目标及其子项拒绝符号链接；源树不跟随符号链接，排除隐藏目录、`.git`、`.build`、`node_modules`。只输出数字统计、状态及备份 ID，不输出词条、文本、路径或子工具诊断。产物及临时文件在私有目录中，umask 为 077。

依赖为开发工具，不打入产品：Python 3.9+（本次 3.13.13）、PyYAML 6.0.3、Xcode command line tools（Swift + 系统 NaturalLanguage）；迁移还需要 `rime_dict_manager` 及 OpenCC CLI。PyYAML LICENSE 已核实为 MIT，librime LICENSE 为 BSD-3-Clause，OpenCC 上游 LICENSE 为 Apache-2.0。未复制任何上游源码进脚本，也未安装额外运行时。

## 个人词表

以下 `$profile`、`$approved_source`、`$dictionary_sources` 都应由执行者设为审核过的绝对路径。默认仅统计，显式 `--apply --offline` 才写入。

```sh
python3 scripts/personal/build-personal-dict.py \
  --rime-dir "$profile" --source "$approved_source" \
  --dictionary-dir "$dictionary_sources"
# 核对摘要后，使用完全相同参数加 --apply --offline
```

`--source` 可重复传入；传 `--allow-default-source` 且不传 `--source` 才授权默认的 `~/Repos`。只读 `.md` 全文和 `.swift` 的注释、普通/多行/raw 字符串。嵌套注释受支持，含插值的整个字符串不统计，表达式里的代码及字符串也不统计。这是保守词法扫描，不是完整 Swift parser；遇到不完整字符串/注释会失败而不发布，复杂正则字面量等语法应先移除该来源或改用明确整理的 Markdown。

`--dictionary-dir` 必须包含完整的 `roarkt_zh`、`roarkt_en` 及其递归 `import_tables` 源文件；缺失即失败，不以不完整的主词库去重。本版本仅输出主词库**缺失**的词，不推断候选真实排名。中文使用 macOS `NLTokenizer`，英文保留原始大小写（编码小写）；默认至少出现 3 次，最多 1500 条，可用 `--min-count` / `--limit` 调整。重复词按次数降序、词文字典序稳定排序，权重上限 100，避免未经评测就抢占日常首选。分词和多音字自动编码质量仍需试打；不承诺提取所有领域复合词。

产出：

- `roarkt_personal.dict.yaml`：导入 `roarkt_zh` 并补充中文，沿用 `roarkt_zh` userdb。
- `roarkt_personal_en.dict.yaml` 及同名 schema：导入 `roarkt_en` 并补充英文，沿用 `roarkt_en` userdb；额外 schema 只用作编译依赖。
- `roarkt_personal.patch.yaml`：只挂载个人中英文词典及编译依赖。设置生成的两份 custom 通过 `patch` 下的 `__include: roarkt_personal.patch:/patch?` 可选引用它，文件不存在时正常部署。脚本从不读取、修改或备份两份 custom；手写 custom 也保持原样，需由其所有者自行加入同样的可选引用。重复执行内容相同则不写文件。

设置同步与个人脚本各自管理自己的文件：设置重写 custom 不影响个人词典，个人脚本回滚也不撤销设置变更。已用真实 librime 验证缺失引用、加入词表、重写设置后继续命中个人词，以及回滚删除个人 patch 后恢复工厂词典。个人层文件没有生成标记时拒绝覆盖。

成功写入会输出 `backup_id`。回滚只恢复这 4 个个人层文件，且要求它们仍与本次生成内容相同；有后续手改则拒绝覆盖：

```sh
python3 scripts/personal/build-personal-dict.py \
  --rime-dir "$profile" --rollback "$backup_id" --apply --offline
```

备份位于目标的 `roarkt-backups/<UTC时间>-personal/`，记录原文件及哪些文件原本不存在。发布遇到普通异常会恢复已经写入的文件；强制断电/kill -9 可能留下部分发布，应从备份人工恢复，不能宣称多文件操作具有文件系统事务保证。完成或回滚后由 Claude 手动重新部署。

## 学习词简体转换

只处理当前 `roarkt_zh.userdb`，不搜索或读取任何旧产品数据。备份整个指定 Rime 目录（排除备份目录自身及脚本锁），保存到 `roarkt-backups/<UTC时间>-simplified/original/`，不覆盖已有备份。禁止在线迁移；脚本通过独立进程持有 LevelDB POSIX 锁，并检测备份及发布前数据库是否变化。

```sh
scripts/personal/migrate-userdb-simplified.sh \
  --rime-dir "$profile" --offline \
  --manager "$rime_dict_manager" --opencc "$opencc_binary" \
  --t2s-config "$opencc_t2s_json"
```

`--manager` 指向能正常找到 librime 的可执行文件。仓库测试采用与现有 RimeChecks 一样的临时 `bin/` + `Frameworks` 布局，不运行输入法 App。`--t2s-config` 必须是 OpenCC 的 `t2s.json`，同目录应有它引用的词典。

流程：完整备份 → 在备份副本导出 TSV → 仅词条文本经 OpenCC t2s（编码不变）→ 同词同编码累计提交次数 → 导入空数据库 → 再导出逐条核对 → 同文件系统替换。不同编码不合并，溢出或条数不匹配即失败。没有繁体变化则不替换数据库，仍保留这次完整备份。转换/导入失败不修改原库；所有中间导出都随私有临时目录清理。

**数据语义限制**：librime `--export` 不导出被删除的词和完整的时间/动态学习元数据，`--import` 重建它们。该脚本保证可导出词条的编码和提交次数，不保证原始排序完全相同。保留字节级原库备份用于回滚；真实“常用词仍优先”由 W-5 试打确认。

```sh
scripts/personal/migrate-userdb-simplified.sh \
  --rime-dir "$profile" --offline --rollback "$backup_id"
```

回滚只替换 `roarkt_zh.userdb`；完整 profile 备份供人工恢复其他文件。若迁移后发生学习、部署或别的写入导致库文件改变，回滚拒绝，避免丢掉后续数据。极端中断发生在两个目录 rename 之间时，应停用输入法后从 `original/roarkt_zh.userdb` 人工恢复；不要删除备份。迁移不自动部署。

## 复现临时目录测试

OpenCC 本次核实并使用上游提交 `8cf737a4e193db27d675b2ce9867d84aace33745`，clone 与构建目录均不提交。先阅读上游 LICENSE，再构建，无安装步骤：

```sh
git clone https://github.com/BYVoid/OpenCC.git .build/vendor/OpenCC
git -C .build/vendor/OpenCC checkout 8cf737a4e193db27d675b2ce9867d84aace33745
cat .build/vendor/OpenCC/LICENSE
cmake -S .build/vendor/OpenCC -B .build/vendor/OpenCC/build \
  -DCMAKE_OSX_SYSROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
  -DENABLE_TESTING=OFF -DBUILD_DOCUMENTATION=OFF
cmake --build .build/vendor/OpenCC/build -j 8
swift test --filter personalScriptsInTemporaryDirectories
scripts/test.sh
```

SDK 路径按机器已有 SDK 设置；本机默认 macOS 27 SDK 与链接器不匹配，因此本次显式选 26.5。也可通过 `ROARKT_TEST_OPENCC`、`ROARKT_TEST_T2S`、`ROARKT_TEST_OPENCC_DATA` 指向已准备的 CLI、t2s 配置和词典目录。测试缺少真实依赖时失败，绝不静默跳过。测试经 `RoarkTPersonalScriptsTests` 注册在 Package.swift，统一测试入口可运行。

测试入口先调用实际 `RimeSettingsPatchWriter` 生成默认及修改后的设置文件，再将私有 fixture 路径交给 Python 检查；`checks.py` 是内部子进程，不单独运行。
