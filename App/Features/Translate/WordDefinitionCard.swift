import SwiftUI

/// A compact, passive card. The owner controls lookup lifetime and whether it is present.
struct WordDefinitionCard: View {
    let definition: WordLookup.Definition
    var embedded = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: embedded ? Tokens.Space.md : Tokens.Space.lg) {
            VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.sm) {
                    Text(definition.term)
                        .font(Tokens.Typography.font(Tokens.Typography.input, weight: .semibold))
                        .lineLimit(2).textSelection(.enabled).help(definition.term)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Tokens.Space.sm)
                    Label("本机词典", systemImage: "book.closed")
                        .font(Tokens.Typography.font(Tokens.Typography.caption))
                        .foregroundStyle(p.secondary).fixedSize()
                }
                if let pronunciation = definition.pronunciation {
                    Text(pronunciation)
                        .font(Tokens.Typography.font(Tokens.Typography.read))
                        .foregroundStyle(p.secondary).textSelection(.enabled)
                        .accessibilityLabel("音标，" + pronunciation)
                }
            }
            VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                ForEach(Array(definition.senses.prefix(3).enumerated()), id: \.offset) { index, sense in
                    HStack(alignment: .top, spacing: Tokens.Space.sm) {
                        Text("\(index + 1)")
                            .font(Tokens.Typography.font(Tokens.Typography.meta)).monospacedDigit()
                            .foregroundStyle(p.tertiary).frame(width: Tokens.Space.lg, alignment: .leading)
                            .padding(.top, 1).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                            if let part = sense.partOfSpeech {
                                Text(part).font(Tokens.Typography.font(Tokens.Typography.caption, weight: .medium))
                                    .foregroundStyle(p.secondary)
                            }
                            Text(sense.meaning)
                                .font(Tokens.Typography.font(Tokens.Typography.read))
                                .lineSpacing(Tokens.Space.xs).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                                .help(sense.meaning)
                                .textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityElement(children: .combine)
                }
            }
        }
        .padding(embedded ? Tokens.Space.md : Tokens.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(p.foreground)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.window).fill(embedded ? p.canvas.opacity(0.45) : p.card)
                .shadow(color: p.windowShadow.opacity(embedded ? 0 : 0.35), radius: Tokens.Shadow.secondaryRadius, y: Tokens.Shadow.secondaryY)
        }
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.window)
            .stroke(contrast == .increased ? p.secondary : (embedded ? p.borderSubtle : p.line), lineWidth: Tokens.Size.hairline))
    }
}
