import SwiftUI
import RoarkTCore

/// Audited against CaptureCanvas and PinnedImageView, not the roadmap.
struct ShortcutReference: View {
    @Environment(\.colorScheme) private var scheme
    private var features: FeatureSettings { SettingsStore.shared.settings.enabledFeatures }
    var body: some View {
        if features.screenshot {
        DesignSectionTitle(title: "截图遮罩内")
        DesignCard {
            row("↩ / ⌘C", "复制选区图片")
            row("⌘S", "另存为（可选格式与位置）")
            row("C", "复制放大镜处的 HEX 颜色值")
            row("⇧↩", "快速保存 PNG，并复制文件路径")
            row("R", "恢复上次选区（同一显示器）")
            if features.pinning { row("P", "将选区贴到屏幕") }
            row("⇧C", "识别选区文字并复制")
            ForEach(ScreenshotTool.allCases, id: \.rawValue) { tool in row(tool.shortcut, tool.title) }
            row("V", "退出标注工具，选择或移动")
            row("⌫ / Delete", "删除选中的标注")
            row("⌘Z / ⌘⇧Z", "撤销 / 重做标注")
            row("方向键 / ⇧方向键", "移动选区或选中标注 1 / 10 点")
            row("⌥← / ⌥→ · ⌥↑ / ⌥↓", "微调选区左边 / 上边")
            row("⌘← / ⌘→ · ⌘↑ / ⌘↓", "微调选区右边 / 下边")
            row("⇧ + 按边微调", "步长从 1 点改为 10 点")
            row("双击选区空白", "选择模式下复制选区；双击文字标注编辑")
            row("⌥拖拽", "在已有标注上叠画新标注")
            row("滚轮", "调整当前标注工具粗细")
            row("⇧拖拽", "矩形与椭圆等比；箭头与直线按 45° 约束")
            row("Esc", "结束文字编辑；再次按下取消截图")
            Text("编辑文字时，按键由文本编辑器处理，↩ 换行、Esc 提交。按边微调始终调整选区；普通方向键优先移动选中的标注。")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(Tokens.palette(scheme).secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        }
        if features.pinning {
        DesignSectionTitle(title: "贴图内")
        DesignCard {
            row("⌘C", "复制图片")
            row("⇧C", "识别并复制文字")
            row("⌘⇧Z", "恢复最近关闭的贴图（贴图获焦时）")
            row("Esc", "关闭当前贴图，按历史数量设置保留")
            row("滚轮 / 捏合", "缩放贴图；锁定时不可缩放")
            row("⌥滚轮", "调整透明度")
            row("右键菜单", "另存、文字识别、翻译、锁定、鼠标穿透及透明度")
            Text("全部贴图关闭后，从 RockType 菜单栏找回。鼠标穿透开启后，从菜单栏“退出贴图鼠标穿透”或独立“贴图”菜单退出。以上快捷键不是全局快捷键。")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(Tokens.palette(scheme).secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    }
    private func row(_ key: String, _ action: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.md) {
            Text(action).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Tokens.Space.sm)
            Text(key).font(Tokens.Typography.font(Tokens.Typography.caption)).monospaced()
                .fixedSize().foregroundStyle(Tokens.palette(scheme).secondary)
        }.padding(.vertical, Tokens.Space.xs).accessibilityElement(children: .combine)
    }
}
