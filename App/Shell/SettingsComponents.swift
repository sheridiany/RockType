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

struct SettingsControlRow<Content: View>: View {
    let title: String
    let detail: String?
    let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    init(_ title: String, detail: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.detail = detail; self.content = content
    }
    var body: some View {
        HStack(spacing: Tokens.Space.md) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(Tokens.Typography.font(Tokens.Typography.caption))
                        .foregroundStyle(Tokens.palette(scheme).secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Tokens.Space.sm)
            content()
        }.frame(minHeight: Tokens.Size.row)
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
