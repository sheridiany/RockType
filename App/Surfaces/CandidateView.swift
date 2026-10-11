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
                                    .foregroundStyle(index == model.selectedIndex ? p.onAccent : p.tertiary)
                                Text(text).lineLimit(1)
                            }.padding(.horizontal, Tokens.Space.sm)
                                .frame(height: Tokens.Size.row)
                                .foregroundStyle(index == model.selectedIndex ? p.onAccent : p.foreground)
                                .background(index == model.selectedIndex ? p.accent : .clear,
                                            in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                        }.buttonStyle(.plain).accessibilityLabel("候选 \(index + 1)，\(text)")
                            .accessibilityAddTraits(index == model.selectedIndex ? .isSelected : [])
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
        }.font(Tokens.Typography.font()).frame(width: Tokens.Size.candidateWidth)
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

/// Clicks demonstrate selection locally; no text is submitted to another application.
struct CandidateDemo: View {
    let initial: CandidatePresentation
    @State private var selected = 0
    @State private var feedback = ""
    private var presentation: CandidatePresentation {
        var model = selected == 0 ? initial : CandidatePresentation(
            state: .none, preedit: initial.preedit, candidates: initial.candidates,
            translation: "", source: initial.source)
        model.selectedIndex = selected
        return model
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            CandidateView(model: presentation, onCandidate: { index in
                selected = index
                feedback = "预览：选中候选「" + initial.candidates[index] + "」"
            }, onTranslation: { feedback = "预览：已选择译文，未执行真实上屏" })
            if !feedback.isEmpty {
                Text(feedback).font(Tokens.Typography.font(Tokens.Typography.caption))
            }
        }
    }
}
