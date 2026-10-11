# ADR-0001：合并 RoType 与 RoarkTools，以 Swift 重写为 RoarkT

- 状态：Accepted（2026-10-11，用户确认）。
- 适用范围：RoarkT 全部组件；需求见 [PRD](../prd.md)。

## 决策

1. 把洛克输入法（RoType）与 RoarkTools 合并为一个新产品 RoarkT。原两个项目保留归档，不再迭代。
2. 全部使用 Swift（SwiftUI + AppKit）。输入法沿用 Squirrel 修改（Swift/ObjC，GPL v3）与 librime；必要的 ObjC 原生代码可保留。
3. 不兼容旧用户：全新 Bundle ID、输入源 ID、Mach service、设置目录与钥匙串条目，不做升级迁移。
4. 进程结构：主 App（菜单栏、设置、划词、截图、权限、AI）、输入法（只负责输入）、翻译服务与语音 worker（后台）。进程间只用 XPC，并按签名身份鉴权。
5. 全部功能纳入产品范围，按[路线图](../roadmap.md)分阶段交付。

## 原因

- 输入法（IMK）、Apple Translation（`TranslationSession`）、MLX 语音都只能用 Swift/ObjC 实现。用 Go + Wails 时这些仍需原生进程，还要多维护一套 IPC 与构建链。
- RoarkTools 处在 D0/M1，业务逻辑量小，原生桥本来就是 ObjC，迁移成本低。
- RoType 已有可用的 XPC 鉴权、翻译协议、安装与公证流程，可以直接作为底座。
- 放弃旧用户兼容后，可以去掉 RoType 中大量升级、迁移和旧进程退休的逻辑与测试。

## 代价

- RoarkTools 的 Svelte 界面需用 SwiftUI/AppKit 重写，设计稿与截图作为基线保留。
- 放弃 Windows 方向。
- 放弃 RoType“不安装独立 App、无 Dock 图标”的原则：改为一个菜单栏主 App（默认不显示 Dock 图标）。
- 已安装旧 RoType 的用户需手动卸载旧版。

## 后续

许可证、标识符与默认快捷键见 [ADR-0002](0002-identifiers-license-shortcuts.md)。
