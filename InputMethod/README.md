# RoarkT 输入法

基于 Squirrel 的 GPL v3 独立输入法进程，最低 macOS 14，Swift 6。开发构建与安装使用仓库根目录的 `scripts/build.sh` 与 `scripts/install-dev.sh`；安装仅注册输入源。

- `Squirrel.xcodeproj` 保留上游工程/target 名 `Squirrel`，产物为 `RoarkT Input.app`，Swift 模块为 `RoarkTInput`。
- `sources/` 中的候选翻译客户端只引用 `Shared/XPCProtocol/include` 的协议头；请求校验直接编译 `Core/Translation/DynamicTranslationProtocol.swift` 与 `Core/Identifiers.swift`，ticket/填入策略直接编译 `Core/Voice/` 的同一份 MIT 源码（原授权见 `LICENSE.translation.txt`）。MIT 产品不反向引用输入法源码。
- `scripts/package-rime.sh` 将根目录 `Rime/` 的方案、Lua 与八股文模型打包到 `Contents/SharedSupport`；运行时不迁移、覆盖或备份其他方案的用户文件。
- librime / plum / Sparkle 为固定提交的子模块。`lib/`、`bin/` 为 Apple Silicon 预编译依赖；`data/plum/` 保留上游词库与约 40 MB 的八股文模型。词库中的人名、艺术名词不代表产品标识。
- M0 通过共享协议注册语音填入端点，仅接受主 App 的签名身份与一次性 ticket；语音 worker/录音 UI 留在 M5，不启动旧设置 helper，不申请麦克风权限。

以下为上游说明与署名。

---

    鼠鬚管
    爲物雖微情不淺
    新詩醉墨時一揮
    別後寄我無辭遠

    　　　——歐陽修

今由　[中州韻輸入法引擎／Rime Input Method Engine](https://rime.im)
及其他開源技術強力驅動

【鼠鬚管】輸入法
===
[![Download](https://img.shields.io/github/v/release/rime/squirrel)](https://github.com/rime/squirrel/releases/latest)
[![Build Status](https://github.com/rime/squirrel/actions/workflows/commit-ci.yml/badge.svg)](https://github.com/rime/squirrel/actions/workflows)
[![GitHub Tag](https://img.shields.io/github/tag/rime/squirrel.svg)](https://github.com/rime/squirrel)

式恕堂 版權所無

授權條款：[GPL v3](https://www.gnu.org/licenses/gpl-3.0.en.html)

項目主頁：[rime.im](https://rime.im)

您可能還需要 Rime 用於其他操作系統的發行版：

  * 【中州韻】（ibus-rime、fcitx-rime）用於 Linux
  * 【小狼毫】用於 Windows

安裝輸入法
---

本品適用於 macOS 13.0+

初次安裝，如果在部份應用程序中打不出字，請註銷並重新登錄。

使用輸入法
---

選取輸入法指示器菜單裏的【ㄓ】字樣圖標，開始用鼠鬚管寫字。
通過快捷鍵 `` Ctrl+` `` 或 `F4` 呼出方案選單、切換輸入方式。

定製輸入法
---

定製方法，請參考線上 [幫助文檔](https://rime.im/docs/)。

使用系統輸入法菜單：

  * 選中「在線文檔」可打開以上網址
  * 編輯用戶設定後，選擇「重新部署」以令修改生效

安裝輸入方案
---

使用 [/plum/](https://github.com/rime/plum) 配置管理器獲取更多輸入方案。

致謝
---

輸入方案設計：

  * 【朙月拼音】系列

    感謝 CC-CEDICT、Android 拼音、新酷音、opencc 等開源項目

程序設計：

  * 佛振
  * Linghua Zhang
  * Chongyu Zhu
  * 雪齋
  * faberii
  * Chun-wei Kuo
  * Junlu Cheng
  * Jak Wings
  * xiehuc

美術：

  * 圖標設計 佛振、梁海、雨過之後
  * 配色方案 Aben、Chongyu Zhu、skoj、Superoutman、佛振、梁海

本品引用了以下開源軟件：

  * Boost C++ Libraries  (Boost Software License)
  * capnproto (MIT License)
  * darts-clone  (New BSD License)
  * google-glog  (New BSD License)
  * Google Test  (New BSD License)
  * LevelDB  (New BSD License)
  * librime  (New BSD License)
  * OpenCC / 開放中文轉換  (Apache License 2.0)
  * plum / 東風破 (GNU Lesser General Public License 3.0)
  * Sparkle  (MIT License)
  * UTF8-CPP  (Boost Software License)
  * yaml-cpp  (MIT License)

感謝王公子捐贈開發用機。

問題與反饋
---

發現程序有 BUG，或建議，或感想，請反饋到 [Rime 代碼之家討論區](https://github.com/rime/home/discussions)

聯繫方式
---

技術交流，歡迎光臨 [Rime 代碼之家](https://github.com/rime/home)，
或致信 Rime 開發者 <rimeime@gmail.com>。

謝謝
