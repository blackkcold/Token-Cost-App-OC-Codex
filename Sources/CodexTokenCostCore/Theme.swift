import Foundation

public enum TokenCostAccentPalette: String, Codable, CaseIterable, Identifiable, Sendable {
    case ocean
    case forest
    case sunset
    case violet
    case workshop

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ocean: return AppLocalization.text("theme.ocean.displayName")
        case .forest: return AppLocalization.text("theme.forest.displayName")
        case .sunset: return AppLocalization.text("theme.sunset.displayName")
        case .violet: return AppLocalization.text("theme.violet.displayName")
        case .workshop: return AppLocalization.text("theme.workshop.displayName")
        }
    }

    public var summary: String {
        switch self {
        case .ocean: return AppLocalization.text("theme.ocean.summary")
        case .forest: return AppLocalization.text("theme.forest.summary")
        case .sunset: return AppLocalization.text("theme.sunset.summary")
        case .violet: return AppLocalization.text("theme.violet.summary")
        case .workshop: return AppLocalization.text("theme.workshop.summary")
        }
    }
}

public enum TokenCostAppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return AppLocalization.text("appearance.system.displayName")
        case .light: return AppLocalization.text("appearance.light.displayName")
        case .dark: return AppLocalization.text("appearance.dark.displayName")
        }
    }

    public var summary: String {
        switch self {
        case .system: return AppLocalization.text("appearance.system.summary")
        case .light: return AppLocalization.text("appearance.light.summary")
        case .dark: return AppLocalization.text("appearance.dark.summary")
        }
    }
}

/// Legacy combined theme value retained for decoding older source settings.
public enum TokenCostThemeChoice: String, Codable, CaseIterable, Sendable {
    case ocean
    case forest
    case sunset
    case violet
    case system

    public var displayName: String {
        switch self {
        case .ocean: return AppLocalization.text("theme.ocean.displayName")
        case .forest: return AppLocalization.text("theme.forest.displayName")
        case .sunset: return AppLocalization.text("theme.sunset.displayName")
        case .violet: return AppLocalization.text("theme.violet.displayName")
        case .system: return AppLocalization.text("theme.system.displayName")
        }
    }

    public var summary: String {
        switch self {
        case .ocean: return AppLocalization.text("theme.ocean.summary")
        case .forest: return AppLocalization.text("theme.forest.summary")
        case .sunset: return AppLocalization.text("theme.sunset.summary")
        case .violet: return AppLocalization.text("theme.violet.summary")
        case .system: return AppLocalization.text("theme.system.summary")
        }
    }

    public var accentPalette: TokenCostAccentPalette {
        switch self {
        case .ocean, .system: return .ocean
        case .forest: return .forest
        case .sunset: return .sunset
        case .violet: return .violet
        }
    }

    public var appearanceMode: TokenCostAppearanceMode {
        .system
    }
}
