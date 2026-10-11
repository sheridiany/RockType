# W-6 D：未通过，未采用

从 C（`7e6517d62f1776e90caed1b66dc4cc48bd0687c0`）派生。这里只保存复现夹具；产品保持 C。
许可、转换方法和未完成语言校正见 `docs/dictionary-simplification.md`。

在仓库根目录复现（只操作 `.build`，不安装、不注册、不访问个人数据）：

```sh
mkdir -p .build/dictionary/replay-D/Rime
cp -R Rime/. .build/dictionary/replay-D/Rime/
cp Tests/InputMethodTests/Fixtures/variant-d/Rime/* .build/dictionary/replay-D/Rime/
rm .build/dictionary/replay-D/Rime/lua/roarkt_simplified_only_filter.lua
bash scripts/eval-candidates.sh .build/dictionary/replay-D/Rime .build/dictionary/replay-D/results
```

C 的评测脚本会复制旧依赖；D 夹具会覆盖 essay，schema 只引用简体模型/字表，旧繁体词表/模型/OpenCC 在此复现中不被使用。
`integration.patch` 保存试验时产品接入的完整改动：两套 schema 去掉 simplifier、繁体 switch 和旧 Lua 字形过滤；不改变 speller、Shift、英文、候选翻译、五候选、contextual_suggestions。打包阶段替换 essay/gram、停止复制 Luna 和 OpenCC；测试资源复制同步调整。
补丁需要这里的 Rime 文件才能完整重建，不能把补丁直接视为通过验收的发布变更。

整句 15/20 < 17/20；RimeChecks“现存”被“显存”挤掉；词库完整性也失败。没有修改期望、继续调权重或尝试其他模型。`candidate-w6-C.tsv` / `candidate-w6-D.tsv` 保存同一冻结集逐项结果。
