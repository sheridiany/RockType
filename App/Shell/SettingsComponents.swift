import SwiftUI

struct SettingsBrand: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: Tokens.Space.sm) {
            Text("R").font(Tokens.Typography.font(weight: .semibold))
                .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                .foregroundStyle(Tokens.palette(scheme).onAccent)
                .background(Tokens.palette(scheme).accent, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
            Text("RockType").font(Tokens.Typography.font(weight: .semibold))
        }.accessibilityElement(children: .ignore).accessibilityLabel("RockType")
    }
}

struct SettingsPageHeading: View {
    let section: SettingsSection
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            Text(section.title).font(Tokens.Typography.font(Tokens.Typography.pageTitle, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(section.detail).font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(Tokens.palette(scheme).secondary)
        }
    }
}

enum SettingsRowStatus { case on, off, attention }

struct SettingsControlRow<Content: View>: View {
    let title: String
    let detail: String?
    let symbol: String
    let status: SettingsRowStatus?
    let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.settingsPresentation) private var styled
    init(_ title: String, detail: String? = nil, symbol: String = "slider.horizontal.3",
         status: SettingsRowStatus? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.detail = detail; self.symbol = symbol; self.status = status; self.content = content
    }
    var body: some View {
        HStack(spacing: 12) {
            if styled {
                Image(systemName: symbol).font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Tokens.palette(scheme).secondary)
                    .frame(width: 30, height: 32).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fontWeight(styled ? .medium : .regular).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        if let status {
                            Circle().fill(status == .on ? Tokens.palette(scheme).ok : status == .attention ? Tokens.palette(scheme).warn : Tokens.palette(scheme).tertiary)
                                .frame(width: 5, height: 5).accessibilityHidden(true)
                        }
                        Text(detail).font(.system(size: 11)).foregroundStyle(Tokens.palette(scheme).secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 4)
            content()
        }.frame(minHeight: styled ? 44 : Tokens.Size.row)
            .padding(.vertical, styled ? 3 : 0)
    }
}

struct SettingsMore<Content: View>: View {
    var title = "更多"
    @ViewBuilder var content: () -> Content
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(title, isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12, content: content).padding(.top, 12)
        }.font(.system(size: 12)).padding(.vertical, 4)
    }
}

/// Unknown language identifiers are retained so opening this pane never discards
/// choices introduced by another version. At least one language remains selected.
enum SettingsOCRLanguages {
    static let choices = [("zh-Hans", "简体中文"), ("zh-Hant", "繁体中文"),
                          ("en-US", "英语"), ("ja-JP", "日语"), ("ko-KR", "韩语")]
    static func setting(_ id: String, enabled: Bool, in languages: [String]) -> [String] {
        if enabled { return languages.contains(id) ? languages : languages + [id] }
        let remaining = languages.filter { $0 != id }
        return remaining.isEmpty ? languages : remaining
    }
}

struct OCRLanguageSettings: View {
    @Binding var languages: [String]
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text("识别语言").fontWeight(.medium)
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: Tokens.Space.md) {
            ForEach(SettingsOCRLanguages.choices, id: \.0) { id, title in
                Toggle(title, isOn: Binding(get: { languages.contains(id) }, set: {
                    languages = SettingsOCRLanguages.setting(id, enabled: $0, in: languages)
                })).toggleStyle(.checkbox)
                    .disabled(languages == [id])
            }
        }
        Text("至少保留一种语言。文字识别在本机完成，不上传图片。")
            .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(Tokens.palette(scheme).secondary)
    }
}
