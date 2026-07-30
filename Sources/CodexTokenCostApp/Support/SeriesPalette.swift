import SwiftUI

enum TokenCostSeriesPalette {
    private static let colors: [Color] = [
        Color(red: 0.14, green: 0.48, blue: 0.97),
        Color(red: 0.96, green: 0.54, blue: 0.16),
        Color(red: 0.14, green: 0.69, blue: 0.50),
        Color(red: 0.63, green: 0.38, blue: 0.96),
        Color(red: 0.93, green: 0.30, blue: 0.44),
        Color(red: 0.18, green: 0.74, blue: 0.87),
        Color(red: 0.84, green: 0.61, blue: 0.18),
        Color(red: 0.91, green: 0.38, blue: 0.82),
        Color(red: 0.23, green: 0.64, blue: 0.30),
        Color(red: 0.88, green: 0.28, blue: 0.22),
        Color(red: 0.27, green: 0.57, blue: 0.90),
        Color(red: 0.44, green: 0.52, blue: 0.97)
    ]

    static let neutral = Color.secondary.opacity(0.55)

    static func color(for key: String) -> Color {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return neutral
        }
        let index = Int(stableHash(normalized) % UInt64(colors.count))
        return colors[index]
    }

    static func color(for key: String, palette: TokenCostPalette) -> Color {
        guard palette.usesWorkshopStyle else { return color(for: key) }
        let workshopColors = [
            palette.accent,
            palette.accentSecondary,
            palette.warning,
            palette.danger,
            palette.info,
            palette.title.opacity(0.78)
        ]
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return palette.subtitle }
        let index = Int(stableHash(normalized) % UInt64(workshopColors.count))
        return workshopColors[index]
    }

    static func otherColor() -> Color {
        .secondary.opacity(0.38)
    }

    static func otherColor(palette: TokenCostPalette) -> Color {
        palette.usesWorkshopStyle ? palette.title.opacity(0.52) : otherColor()
    }

    static func color(forRank rank: Int) -> Color {
        guard !colors.isEmpty else {
            return neutral
        }
        let normalized = max(rank, 0)
        return colors[normalized % colors.count]
    }

    static func color(forRank rank: Int, palette: TokenCostPalette) -> Color {
        guard palette.usesWorkshopStyle else { return color(forRank: rank) }
        let workshopColors = [
            palette.accent,
            palette.accentSecondary,
            palette.warning,
            palette.danger,
            palette.info,
            palette.title.opacity(0.78)
        ]
        let normalized = max(rank, 0)
        return workshopColors[normalized % workshopColors.count]
    }

    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}
