import AppKit
import SwiftUI
import RoarkTCore

/// Edits one tool only; unknown tool preferences survive round trips.
enum ScreenshotStylePreferences {
    static func updating(_ tool: ScreenshotTool, in styles: [String: ScreenshotAnnotationStyle]?,
                         change: (inout ScreenshotAnnotationStyle) -> Void) -> [String: ScreenshotAnnotationStyle] {
        var result = styles ?? [:]
        var style = tool.style(from: result)
        change(&style)
        result[tool.rawValue] = style
        result[tool.rawValue] = tool.style(from: result)
        return result
    }
}

struct ScreenshotStyleSettings: View {
    @Binding var settings: ScreenshotSettings
    @State var expandedTool: ScreenshotTool? = nil
    var body: some View {
        DesignSectionTitle(title: "标注默认样式")
        DesignCard {
            Text("每种工具单独记忆；截图工具栏中的调整也会更新这里。下次截图生效。")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ScreenshotTool.allCases.filter { $0 != .eraser }, id: \.rawValue) { tool in
                DisclosureGroup(tool.title, isExpanded: Binding(get: { expandedTool == tool },
                    set: { expandedTool = $0 ? tool : nil })) {
                    VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                        if tool != .mosaic {
                            ColorPicker("颜色", selection: Binding(get: {
                                Color(nsColor: tool.style(from: settings.annotationStyles ?? [:]).nsColor)
                            }, set: { color in
                                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                                let hex = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                                    Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
                                settings.annotationStyles = ScreenshotStylePreferences.updating(tool, in: settings.annotationStyles) { $0.colorHex = hex }
                            }), supportsOpacity: false).accessibilityLabel(tool.title + "颜色")
                        }
                        Stepper(value: Binding(get: { tool.style(from: settings.annotationStyles ?? [:]).width }, set: { width in
                            settings.annotationStyles = ScreenshotStylePreferences.updating(tool, in: settings.annotationStyles) { $0.width = width }
                        }), in: tool.widthRange, step: 1) {
                            Text("\(tool == .text ? "字号" : tool == .mosaic ? "色块大小" : tool == .number ? "大小基准" : "粗细")：\(tool.style(from: settings.annotationStyles ?? [:]).width.formatted())")
                        }.accessibilityLabel(tool.title + "尺寸")
                        Button("恢复此工具默认值") { settings.annotationStyles?.removeValue(forKey: tool.rawValue) }
                            .disabled(settings.annotationStyles?[tool.rawValue] == nil)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, Tokens.Space.sm)
                }
            }
        }
    }
}
