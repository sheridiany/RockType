#if DEBUG
import SwiftUI

struct InputModeView: View {
    let model: InputModePresentation
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Tokens.palette(scheme)
        HStack(spacing: Tokens.Space.sm) {
            Text(model.badge).font(Tokens.Typography.font(Tokens.Typography.input, weight: .semibold))
                .frame(width: Tokens.Size.modeSide, height: Tokens.Size.modeSide)
                .foregroundStyle(p.accent).background(p.accentSoft, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            if model == .scheme {
                Text(model.detail).font(Tokens.Typography.font(weight: .medium)).padding(.trailing, Tokens.Space.md)
            }
        }.padding(Tokens.Space.xs).modifier(DesignSurface())
            .accessibilityElement(children: .ignore).accessibilityLabel(model.title + "，" + model.detail)
    }
}

#endif
