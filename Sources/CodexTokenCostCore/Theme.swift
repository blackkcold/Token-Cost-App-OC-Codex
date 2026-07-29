import Foundation

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
}
