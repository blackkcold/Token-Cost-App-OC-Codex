import AppKit
import SwiftUI
import CodexTokenCostCore

struct TokenCostPalette {
    let theme: TokenCostThemeChoice
    let accent: Color
    let accentSecondary: Color
    let accentSoft: Color
    let backgroundBase: Color
    let backgroundWashTop: Color
    let backgroundWashBottom: Color
    let cardFill: Material
    let surfaceFill: Material
    let surfaceSecondaryFill: Material
    let surfaceSolidFill: Color
    let surfaceSecondarySolidFill: Color
    let cardStroke: Color
    let surfaceStroke: Color
    let surfaceInnerStroke: Color
    let surfaceAccessibleStroke: Color
    let cardShadow: Color
    let surfaceShadow: Color
    let trackBackground: Color
    let title: Color
    let subtitle: Color
    let chipText: Color
    let chipBackground: Color

    init(theme: TokenCostThemeChoice) {
        self.theme = theme

        switch theme {
        case .ocean:
            accent = Color(red: 0.18, green: 0.52, blue: 0.98)
            accentSecondary = Color(red: 0.16, green: 0.78, blue: 0.88)
            accentSoft = Color(red: 0.18, green: 0.52, blue: 0.98).opacity(0.10)
            backgroundWashTop = Color(red: 0.18, green: 0.52, blue: 0.98).opacity(0.11)
            backgroundWashBottom = Color(red: 0.16, green: 0.78, blue: 0.88).opacity(0.08)
            cardStroke = Color(red: 0.18, green: 0.52, blue: 0.98).opacity(0.14)
            chipBackground = Color(red: 0.18, green: 0.52, blue: 0.98).opacity(0.14)
        case .forest:
            accent = Color(red: 0.14, green: 0.69, blue: 0.47)
            accentSecondary = Color(red: 0.39, green: 0.81, blue: 0.56)
            accentSoft = Color(red: 0.14, green: 0.69, blue: 0.47).opacity(0.10)
            backgroundWashTop = Color(red: 0.14, green: 0.69, blue: 0.47).opacity(0.10)
            backgroundWashBottom = Color(red: 0.39, green: 0.81, blue: 0.56).opacity(0.08)
            cardStroke = Color(red: 0.14, green: 0.69, blue: 0.47).opacity(0.14)
            chipBackground = Color(red: 0.14, green: 0.69, blue: 0.47).opacity(0.14)
        case .sunset:
            accent = Color(red: 0.95, green: 0.46, blue: 0.18)
            accentSecondary = Color(red: 0.97, green: 0.68, blue: 0.18)
            accentSoft = Color(red: 0.95, green: 0.46, blue: 0.18).opacity(0.10)
            backgroundWashTop = Color(red: 0.95, green: 0.46, blue: 0.18).opacity(0.11)
            backgroundWashBottom = Color(red: 0.97, green: 0.68, blue: 0.18).opacity(0.08)
            cardStroke = Color(red: 0.95, green: 0.46, blue: 0.18).opacity(0.14)
            chipBackground = Color(red: 0.95, green: 0.46, blue: 0.18).opacity(0.14)
        case .violet:
            accent = Color(red: 0.62, green: 0.37, blue: 0.96)
            accentSecondary = Color(red: 0.91, green: 0.39, blue: 0.88)
            accentSoft = Color(red: 0.62, green: 0.37, blue: 0.96).opacity(0.10)
            backgroundWashTop = Color(red: 0.62, green: 0.37, blue: 0.96).opacity(0.11)
            backgroundWashBottom = Color(red: 0.91, green: 0.39, blue: 0.88).opacity(0.08)
            cardStroke = Color(red: 0.62, green: 0.37, blue: 0.96).opacity(0.14)
            chipBackground = Color(red: 0.62, green: 0.37, blue: 0.96).opacity(0.14)
        case .system:
            accent = Color(red: 0.18, green: 0.52, blue: 0.98)
            accentSecondary = Color(red: 0.16, green: 0.78, blue: 0.88)
            accentSoft = Color(red: 0.18, green: 0.52, blue: 0.98).opacity(0.10)
            backgroundWashTop = Color(red: 0.18, green: 0.52, blue: 0.98).opacity(0.11)
            backgroundWashBottom = Color(red: 0.16, green: 0.78, blue: 0.88).opacity(0.08)
            cardStroke = Color(red: 0.18, green: 0.52, blue: 0.98).opacity(0.14)
            chipBackground = Color(red: 0.18, green: 0.52, blue: 0.98).opacity(0.14)
        }

        backgroundBase = Color(nsColor: .windowBackgroundColor)
        cardFill = .regularMaterial
        surfaceFill = .regularMaterial
        surfaceSecondaryFill = .ultraThinMaterial
        surfaceSolidFill = Color(nsColor: .controlBackgroundColor).opacity(0.98)
        surfaceSecondarySolidFill = Color(nsColor: .windowBackgroundColor).opacity(0.96)
        surfaceStroke = cardStroke.opacity(0.64)
        surfaceInnerStroke = cardStroke.opacity(0.38)
        surfaceAccessibleStroke = Color.primary.opacity(0.18)
        cardShadow = Color.primary.opacity(0.04)
        surfaceShadow = Color.primary.opacity(0.03)
        trackBackground = Color.primary.opacity(0.06)
        title = Color.primary
        subtitle = Color.secondary
        chipText = accent
    }

    var pageBackground: some View {
        ZStack {
            backgroundBase
            LinearGradient(
                colors: [
                    backgroundWashTop,
                    .clear,
                    backgroundWashBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)
            .opacity(0.9)

            RadialGradient(
                colors: [
                    accentSoft,
                    .clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 720
            )
            .blendMode(.screen)
        }
    }
}

extension TokenCostPalette: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.theme == rhs.theme
            && lhs.accent == rhs.accent
            && lhs.accentSecondary == rhs.accentSecondary
            && lhs.accentSoft == rhs.accentSoft
            && lhs.backgroundBase == rhs.backgroundBase
            && lhs.backgroundWashTop == rhs.backgroundWashTop
            && lhs.backgroundWashBottom == rhs.backgroundWashBottom
            && lhs.surfaceSolidFill == rhs.surfaceSolidFill
            && lhs.surfaceSecondarySolidFill == rhs.surfaceSecondarySolidFill
            && lhs.cardStroke == rhs.cardStroke
            && lhs.surfaceStroke == rhs.surfaceStroke
            && lhs.surfaceInnerStroke == rhs.surfaceInnerStroke
            && lhs.surfaceAccessibleStroke == rhs.surfaceAccessibleStroke
            && lhs.cardShadow == rhs.cardShadow
            && lhs.surfaceShadow == rhs.surfaceShadow
            && lhs.trackBackground == rhs.trackBackground
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.chipText == rhs.chipText
            && lhs.chipBackground == rhs.chipBackground
    }
}
