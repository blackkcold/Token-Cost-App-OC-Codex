import SwiftUI

struct LiquidGlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pressedScale: CGFloat = 0.96
    private static let pressedOpacity: Double = 0.7
    private static let pressAnimation: Animation = .spring(
        response: 0.28,
        dampingFraction: 0.78
    )

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.pressedScale : 1.0)
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1.0)
            .animation(reduceMotion ? nil : Self.pressAnimation, value: configuration.isPressed)
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
        if #available(macOS 26, *) {
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
                    .shadow(color: palette.surfaceShadow, radius: 10, x: 0, y: 5)
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
                    .shadow(color: palette.surfaceShadow, radius: 8, x: 0, y: 4)
            }
        }
    }
}
