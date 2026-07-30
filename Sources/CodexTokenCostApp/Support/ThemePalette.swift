import AppKit
import SwiftUI
import CodexTokenCostCore

struct TokenCostPalette {
    let accentPalette: TokenCostAccentPalette
    let usesWorkshopStyle: Bool
    let accent: Color
    let accentSecondary: Color
    let accentSoft: Color
    let backgroundBase: Color
    let backgroundWashTop: Color
    let backgroundWashBottom: Color
    let cardFill: AnyShapeStyle
    let surfaceFill: AnyShapeStyle
    let surfaceSecondaryFill: AnyShapeStyle
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
    let success: Color
    let warning: Color
    let danger: Color
    let info: Color
    let cardBorderWidth: CGFloat
    let surfaceBorderWidth: CGFloat
    let shadowRadius: CGFloat
    let shadowX: CGFloat
    let shadowY: CGFloat
    let cardCornerRadius: CGFloat
    let sectionCornerRadius: CGFloat

    init(accentPalette: TokenCostAccentPalette) {
        self.accentPalette = accentPalette
        usesWorkshopStyle = accentPalette == .workshop

        switch accentPalette {
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
        case .workshop:
            accent = Color(red: 0.58, green: 0.20, blue: 0.94)
            accentSecondary = Color(red: 0.10, green: 0.72, blue: 0.38)
            accentSoft = Color(red: 0.58, green: 0.20, blue: 0.94).opacity(0.16)
            backgroundWashTop = .clear
            backgroundWashBottom = .clear
            cardStroke = Color.primary.opacity(0.92)
            chipBackground = Color(red: 0.58, green: 0.20, blue: 0.94).opacity(0.18)
        }

        if usesWorkshopStyle {
            let base = Color(nsColor: .windowBackgroundColor)
            let primarySurface = Color(nsColor: .textBackgroundColor)
            let secondarySurface = Color(nsColor: .controlBackgroundColor)

            backgroundBase = base
            cardFill = AnyShapeStyle(primarySurface)
            surfaceFill = AnyShapeStyle(primarySurface)
            surfaceSecondaryFill = AnyShapeStyle(secondarySurface)
            surfaceSolidFill = primarySurface
            surfaceSecondarySolidFill = secondarySurface
            surfaceStroke = cardStroke
            surfaceInnerStroke = Color.primary.opacity(0.72)
            surfaceAccessibleStroke = Color.primary.opacity(0.92)
            cardShadow = Color.primary.opacity(0.82)
            surfaceShadow = Color.primary.opacity(0.78)
            trackBackground = Color.primary.opacity(0.14)
            title = Color.primary
            subtitle = Color.primary.opacity(0.72)
            chipText = Color.primary
            success = accentSecondary
            cardBorderWidth = 2.5
            surfaceBorderWidth = 2.5
            shadowRadius = 0
            shadowX = 5
            shadowY = 5
            cardCornerRadius = 14
            sectionCornerRadius = 18
        } else {
            backgroundBase = Color(nsColor: .windowBackgroundColor)
            cardFill = AnyShapeStyle(.regularMaterial)
            surfaceFill = AnyShapeStyle(.regularMaterial)
            surfaceSecondaryFill = AnyShapeStyle(.ultraThinMaterial)
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
            success = Color(nsColor: .systemGreen)
            cardBorderWidth = 1
            surfaceBorderWidth = 1
            shadowRadius = TokenShadow.large.radius
            shadowX = 0
            shadowY = TokenShadow.large.y
            cardCornerRadius = TokenRadius.card
            sectionCornerRadius = TokenRadius.section
        }

        warning = Color(nsColor: .systemOrange)
        danger = Color(nsColor: .systemRed)
        info = Color(nsColor: .systemBlue)
    }

    @ViewBuilder
    var pageBackground: some View {
        if usesWorkshopStyle {
            WorkshopBoardBackground(palette: self)
        } else {
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
}

private struct WorkshopBoardBackground: View {
    let palette: TokenCostPalette

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                palette.backgroundBase

                Canvas { context, size in
                    drawGrid(context: &context, size: size)
                    drawFlow(context: &context, size: size)
                    drawCardStack(context: &context, size: size)
                }

                collaboratorTag("TEAM", color: palette.accent)
                    .position(x: proxy.size.width * 0.86, y: proxy.size.height * 0.17)

                collaboratorTag("YOU", color: palette.accentSecondary)
                    .position(x: proxy.size.width * 0.12, y: proxy.size.height * 0.78)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        var grid = Path()
        let spacing: CGFloat = 44

        for x in stride(from: CGFloat.zero, through: size.width, by: spacing) {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        for y in stride(from: CGFloat.zero, through: size.height, by: spacing) {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }

        context.stroke(grid, with: .color(palette.title.opacity(0.055)), lineWidth: 1)
    }

    private func drawFlow(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        path.move(to: CGPoint(x: size.width * 0.64, y: size.height * 0.07))
        path.addCurve(
            to: CGPoint(x: size.width * 0.76, y: size.height * 0.26),
            control1: CGPoint(x: size.width * 0.74, y: size.height * 0.05),
            control2: CGPoint(x: size.width * 0.70, y: size.height * 0.24)
        )
        path.addLine(to: CGPoint(x: size.width * 0.73, y: size.height * 0.23))
        path.move(to: CGPoint(x: size.width * 0.76, y: size.height * 0.26))
        path.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.22))

        context.stroke(
            path,
            with: .color(palette.title.opacity(0.13)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawCardStack(context: inout GraphicsContext, size: CGSize) {
        let origin = CGPoint(x: size.width * 0.06, y: size.height * 0.10)
        for index in 0..<3 {
            let rect = CGRect(
                x: origin.x + CGFloat(index * 11),
                y: origin.y + CGFloat(index * 9),
                width: min(size.width * 0.18, 220),
                height: min(size.height * 0.13, 120)
            )
            context.stroke(
                Path(roundedRect: rect, cornerRadius: 14),
                with: .color(palette.title.opacity(0.08 + Double(index) * 0.025)),
                lineWidth: 2
            )
        }
    }

    private func collaboratorTag(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "cursorarrow")
                .font(.caption2.weight(.black))
            Text(title)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.72), in: RoundedRectangle(cornerRadius: 4))
        .rotationEffect(.degrees(title == "TEAM" ? 2 : -2))
        .opacity(0.38)
    }
}

extension TokenCostPalette: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accentPalette == rhs.accentPalette
            && lhs.usesWorkshopStyle == rhs.usesWorkshopStyle
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
            && lhs.success == rhs.success
            && lhs.warning == rhs.warning
            && lhs.danger == rhs.danger
            && lhs.info == rhs.info
            && lhs.cardBorderWidth == rhs.cardBorderWidth
            && lhs.surfaceBorderWidth == rhs.surfaceBorderWidth
            && lhs.shadowRadius == rhs.shadowRadius
            && lhs.shadowX == rhs.shadowX
            && lhs.shadowY == rhs.shadowY
            && lhs.cardCornerRadius == rhs.cardCornerRadius
            && lhs.sectionCornerRadius == rhs.sectionCornerRadius
    }
}

extension TokenCostAppearanceMode {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
