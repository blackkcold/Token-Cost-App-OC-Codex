import Foundation

/// A single day cell in the contribution-style heatmap
public struct TokenHeatmapCell: Identifiable, Sendable {
    public var id: String { dateString }
    public let dateString: String
    public let date: Date
    public let tokenCount: Double
    /// Normalised intensity 0.0–1.0 for colour mapping
    public let intensity: Double
}

/// Contribution-style heatmap data for the previous 52 weeks.
public struct TokenHeatmapData: Sendable {
    /// Each inner array is a day-of-week row (0=Mon … 6=Sun), each containing 52 week columns
    public let rows: [[TokenHeatmapCell?]]
    /// Chronological cells for responsive UI layouts.
    public let cells: [TokenHeatmapCell]

    public init(rows: [[TokenHeatmapCell?]], cells: [TokenHeatmapCell]? = nil) {
        self.rows = rows
        self.cells = cells ?? rows
            .flatMap { $0.compactMap { $0 } }
            .sorted { $0.date < $1.date }
    }

    /// Flattened, date-sorted array of every cell for iteration.
    public var allCells: [TokenHeatmapCell] {
        cells
    }
}

public enum TokenHeatmapBuilder {
    /// Build a 52-week heatmap ending at `referenceDate`.
    public static func build(
        fromOpenCodeDaily openCodeDaily: [String: Double],
        codexDaily: [String: Double],
        referenceDate: Date
    ) -> TokenHeatmapData {
        // Merge both sources
        var merged: [String: Double] = openCodeDaily
        for (date, tokens) in codexDaily {
            merged[date, default: 0] += tokens
        }

        // Find the max token count for intensity calculation
        let maxTokens = max(merged.values.max() ?? 1, 1)

        // Compute the start date: 52 weeks before referenceDate, aligned to Monday
        let calendar = Self.calendar
        // Find the Monday of the week containing referenceDate
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
        components.weekday = 2 // Monday
        let mondayOfRefWeek = calendar.date(from: components)!
        // Go back 52 weeks
        let startDate = calendar.date(byAdding: .weekOfYear, value: -51, to: mondayOfRefWeek)!

        // Build grid: 7 rows (Mon=0 ... Sun=6), 52 columns
        var rows: [[TokenHeatmapCell?]] = (0..<7).map { _ in
            Array(repeating: nil, count: 52)
        }
        var cells: [TokenHeatmapCell] = []

        for weekOffset in 0..<52 {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: startDate)!
            for dayOffset in 0..<7 {
                let cellDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
                let dateString = dateFormatter.string(from: cellDate)

                // Don't include future dates
                if cellDate > referenceDate { continue }

                let tokens = merged[dateString] ?? 0
                let intensity = maxTokens > 0 ? tokens / maxTokens : 0

                let cell = TokenHeatmapCell(
                    dateString: dateString,
                    date: cellDate,
                    tokenCount: tokens,
                    intensity: intensity
                )
                rows[dayOffset][weekOffset] = cell
                cells.append(cell)
            }
        }

        return TokenHeatmapData(rows: rows, cells: cells)
    }

    // MARK: - Private helpers

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2 // Monday
        return cal
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}
