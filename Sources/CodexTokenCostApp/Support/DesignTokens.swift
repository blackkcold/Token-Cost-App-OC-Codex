import SwiftUI

enum TokenSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let control: CGFloat = 12
    static let card: CGFloat = 16
    static let section: CGFloat = 20
    static let page: CGFloat = 24
}

enum TokenRadius {
    static let compact: CGFloat = 10
    static let row: CGFloat = 14
    static let card: CGFloat = 16
    static let section: CGFloat = 20
}

struct TokenShadowStyle {
    let radius: CGFloat
    let y: CGFloat
}

enum TokenShadow {
    static let small = TokenShadowStyle(radius: 6, y: 3)
    static let medium = TokenShadowStyle(radius: 10, y: 6)
    static let large = TokenShadowStyle(radius: 14, y: 8)
}

enum TokenTypography {
    static func headline(weight: Font.Weight = .semibold, palette: TokenCostPalette) -> Font {
        palette.usesWorkshopStyle
            ? .system(.headline, design: .monospaced, weight: weight)
            : .headline.weight(weight)
    }

    static func subheadline(weight: Font.Weight = .regular, palette: TokenCostPalette) -> Font {
        palette.usesWorkshopStyle
            ? .system(.subheadline, design: .monospaced, weight: weight)
            : .subheadline.weight(weight)
    }

    static func caption(weight: Font.Weight = .regular, palette: TokenCostPalette) -> Font {
        palette.usesWorkshopStyle
            ? .system(.caption, design: .monospaced, weight: weight)
            : .caption.weight(weight)
    }

    static func caption2(weight: Font.Weight = .regular, palette: TokenCostPalette) -> Font {
        palette.usesWorkshopStyle
            ? .system(.caption2, design: .monospaced, weight: weight)
            : .caption2.weight(weight)
    }

    static func metric(
        size: CGFloat,
        weight: Font.Weight = .semibold,
        defaultDesign: Font.Design = .rounded,
        palette: TokenCostPalette
    ) -> Font {
        .system(
            size: size,
            weight: weight,
            design: palette.usesWorkshopStyle ? .monospaced : defaultDesign
        )
    }
}

enum TokenMotion {
    static let micro = Animation.easeOut(duration: 0.12)
    static let contentSwap = Animation.easeInOut(duration: 0.16)
    static let expand = Animation.easeInOut(duration: 0.18)
    static let progress = Animation.easeOut(duration: 0.28)
    static let press = Animation.spring(response: 0.28, dampingFraction: 0.78)

    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    static func disclosureTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }
}
