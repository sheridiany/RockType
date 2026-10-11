# Rime 方案

RoarkT 输入方案：`roarkt`（全拼）、`roarkt_flypy`（小鹤双拼）、`roarkt_en`（英文词典，不单独显示）。显示名分别为「RockType」「RockType Shuangpin」。

部署依赖 librime 自带的共享数据（`luna_pinyin`、`opencc`、八股文模型）。本目录只放 RoarkT 方案，不复制共享词库。`scripts/test-rime.sh` 在临时目录部署这些方案。
