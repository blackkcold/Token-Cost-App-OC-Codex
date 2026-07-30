import SwiftUI

struct LiquidGlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pressedScale: CGFloat = 0.96
    private static let pressedOpacity: Double = 0.7
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.pressedScale : 1.0)
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1.0)
            .animation(TokenMotion.resolved(TokenMotion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle { LiquidGlassButtonStyle() }
}

struct LiquidGlassTileBackground: ViewModifier {
    let palette: TokenCostPalette
    let cornerRadius: CGFloat
    let accentSoft: Color

    func body(content: Content) -> some View {
        if palette.usesWorkshopStyle {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.surfaceSecondarySolidFill.opacity(0.72))
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .fill(palette.accent)
                            .frame(width: 42, height: 4)
                            .padding(.leading, 14)
                    }
                    .shadow(
                        color: palette.accent.opacity(0.18),
                        radius: 0,
                        x: 3,
                        y: 3
                    )
            }
        } else if #available(macOS 26, *) {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        .regular.tint(accentSoft),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(palette.surfaceStroke.opacity(0.95), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(palette.surfaceAccessibleStroke.opacity(0.45), lineWidth: 0.5)
                    )
                    .shadow(
                        color: palette.surfaceShadow,
                        radius: TokenShadow.medium.radius,
                        x: 0,
                        y: TokenShadow.medium.y
                    )
            }
        } else {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.surfaceSolidFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(palette.surfaceStroke.opacity(0.95), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(palette.surfaceAccessibleStroke.opacity(0.45), lineWidth: 0.5)
                    )
                    .shadow(
                        color: palette.surfaceShadow,
                        radius: TokenShadow.small.radius,
                        x: 0,
                        y: TokenShadow.small.y
                    )
            }
        }
    }
}
