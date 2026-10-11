import SwiftUI

/// Independent SwiftUI design prototype; no IMK/Rime dependency or input capture.
struct CandidateView: View {
    let model: CandidatePresentation
    var onCandidate: (Int) -> Void = { _ in }
    var onTranslation: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                Text(model.preedit).font(Tokens.Typography.font(Tokens.Typography.meta))
                    .foregroundStyle(p.secondary)
                // Five numbered candidates; translation never occupies a number.
                HStack(spacing: Tokens.Space.xs) {
                    ForEach(Array(model.candidates.prefix(5).enumerated()), id: \.offset) { index, text in
                        Button { onCandidate(index) } label: {
                            HStack(spacing: Tokens.Space.xs) {
                                Text(String(index + 1)).font(Tokens.Typography.font(Tokens.Typography.caption))
                                    .foregroundStyle(index == 0 ? p.onAccent : p.tertiary)
                                Text(text).lineLimit(1)
                            }.padding(.horizontal, Tokens.Space.sm)
                                .frame(height: Tokens.Size.row)
                                .foregroundStyle(index == 0 ? p.onAccent : p.foreground)
                                .background(index == 0 ? p.accent : .clear,
                                            in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                        }.buttonStyle(.plain).accessibilityLabel("候选 \(index + 1)，\(text)")
                            .accessibilityAddTraits(index == 0 ? .isSelected : [])
                            .help(text)
                    }
                }
            }.padding(Tokens.Space.md).frame(maxWidth: .infinity, alignment: .leading)
                .modifier(DesignSurface())
            if model.state != .none {
                if model.canCommit {
                    Button(action: onTranslation) { translationRow }
                        .buttonStyle(.plain).help(model.translation)
                        .accessibilityLabel(model.source + "：" + model.translation)
                        .accessibilityHint("按 Tab 使用译文")
                } else {
                    translationRow.accessibilityElement(children: .combine)
                        .accessibilityHint("继续输入无需等待")
                }
            }
        }.font(Tokens.Typography.font()).frame(width: Tokens.U4.candidateWidth)
    }

    private var translationRow: some View {
        let p = Tokens.palette(scheme)
        return HStack(spacing: Tokens.Space.sm) {
            Image(systemName: model.state == .ai ? "sparkles" : "character.bubble")
                .foregroundStyle(model.canCommit ? p.accent : p.secondary)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(model.source).font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                Text(model.translation).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(model.canCommit ? p.foreground : p.secondary)
            }
            Spacer(minLength: Tokens.Space.xs)
            if model.canCommit { Kbd("Tab") }
        }.padding(Tokens.Space.md).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(DesignSurface())
    }
}
