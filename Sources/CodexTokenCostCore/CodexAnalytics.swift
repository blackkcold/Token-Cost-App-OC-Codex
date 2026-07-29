import Foundation
import os

public enum CodexSessionSortField: String, CaseIterable, Identifiable, Codable, Sendable {
    case updatedAt
    case input
    case output
    case reasoning
    case cachedInput
    case actualTokens
    case totalTokens
    case tokenCountEvents

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .updatedAt: return AppLocalization.text("sort.codex.updatedAt")
        case .input: return AppLocalization.text("sort.codex.input")
        case .output: return AppLocalization.text("sort.codex.output")
        case .reasoning: return AppLocalization.text("sort.codex.reasoning")
        case .cachedInput: return AppLocalization.text("sort.codex.cachedInput")
        case .actualTokens: return AppLocalization.text("sort.codex.actualTokens")
        case .totalTokens: return AppLocalization.text("sort.codex.totalTokens")
        case .tokenCountEvents: return AppLocalization.text("sort.codex.tokenCountEvents")
        }
    }
}

public struct CodexDailyTrendPoint: Identifiable, Sendable {
    public var id: String { dateString }

    public var date: Date
    public var dateString: String
    public var sessionCount: Int
    public var actualTokens: Double
    public var inputTokens: Double
    public var outputTokens: Double
    public var reasoningOutputTokens: Double
    public var cachedInputTokens: Double
}

public enum CodexDashboardAnalytics {
    public static func dailyTrendPoints(from payload: CodexDashboardPayload) -> [CodexDailyTrendPoint] {
        var groupedSessions: [Date: [CodexSessionSummary]] = [:]
        let calendar = calendar()
        let labelFormatter = dayLabelFormatter()

        for session in payload.sessions {
            guard let parsedDate = date(from: session.updatedAt) else {
                continue
            }
            let bucketDate = calendar.startOfDay(for: parsedDate)
            groupedSessions[bucketDate, default: []].append(session)
        }

        return groupedSessions.keys.sorted().map { date in
            let sessions = groupedSessions[date, default: []]
            return CodexDailyTrendPoint(
                date: date,
                dateString: labelFormatter.string(from: date),
                sessionCount: sessions.count,
                actualTokens: sessions.reduce(0) { $0 + $1.actualTokens },
                inputTokens: sessions.reduce(0) { $0 + $1.usage.inputTokens },
                outputTokens: sessions.reduce(0) { $0 + $1.usage.outputTokens },
                reasoningOutputTokens: sessions.reduce(0) { $0 + $1.usage.reasoningOutputTokens },
                cachedInputTokens: sessions.reduce(0) { $0 + $1.usage.cachedInputTokens }
            )
        }
    }

    public static func sortSessions(
        _ sessions: [CodexSessionSummary],
        field: CodexSessionSortField,
        direction: TokenCostSortDirection
    ) -> [CodexSessionSummary] {
        sessions.sorted { lhs, rhs in
            let comparison = compare(lhs, rhs, field: field)
            switch comparison {
            case .orderedAscending:
                return direction == .ascending
            case .orderedDescending:
                return direction == .descending
            case .orderedSame:
                return tieBreak(lhs, rhs)
            }
        }
    }

    /// Returns model breakdown slices from the summary, sorted by totalTokens descending.
    public static func modelSlices(from payload: CodexDashboardPayload) -> [CodexModelUsage] {
        payload.summary.modelBreakdown
    }

    public static func displayTimestamp(for updatedAt: String) -> String {
        guard let date = date(from: updatedAt) else {
            return updatedAt
        }
        return displayDateFormatter().string(from: date)
    }

    public static func date(from updatedAt: String) -> Date? {
        let trimmed = updatedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let parsed = isoFormatterLock.withLock({
            fractionalISOFormatter.date(from: trimmed) ?? standardISOFormatter.date(from: trimmed)
        }) {
            return parsed
        }

        let dayPrefix = String(trimmed.prefix(10))
        if let date = dayBucketFormatter().date(from: dayPrefix) {
            return date
        }

        return nil
    }

    private static func compare(_ lhs: CodexSessionSummary, _ rhs: CodexSessionSummary, field: CodexSessionSortField) -> ComparisonResult {
        switch field {
        case .updatedAt:
            return compareDates(lhs.updatedAt, rhs.updatedAt)
        case .input:
            return compareNumbers(lhs.usage.inputTokens, rhs.usage.inputTokens)
        case .output:
            return compareNumbers(lhs.usage.outputTokens, rhs.usage.outputTokens)
        case .reasoning:
            return compareNumbers(lhs.usage.reasoningOutputTokens, rhs.usage.reasoningOutputTokens)
        case .cachedInput:
            return compareNumbers(lhs.usage.cachedInputTokens, rhs.usage.cachedInputTokens)
        case .actualTokens:
            return compareNumbers(lhs.actualTokens, rhs.actualTokens)
        case .totalTokens:
            return compareNumbers(lhs.usage.totalTokens, rhs.usage.totalTokens)
        case .tokenCountEvents:
            return compareNumbers(Double(lhs.tokenCountEvents), Double(rhs.tokenCountEvents))
        }
    }

    private static func compareNumbers(_ lhs: Double, _ rhs: Double) -> ComparisonResult {
        if lhs == rhs {
            return .orderedSame
        }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private static func compareDates(_ lhs: String, _ rhs: String) -> ComparisonResult {
        switch (date(from: lhs), date(from: rhs)) {
        case let (lhsDate?, rhsDate?):
            if lhsDate == rhsDate {
                return .orderedSame
            }
            return lhsDate < rhsDate ? .orderedAscending : .orderedDescending
        case _:
            let result = lhs.localizedStandardCompare(rhs)
            switch result {
            case .orderedAscending: return .orderedAscending
            case .orderedDescending: return .orderedDescending
            case .orderedSame: return .orderedSame
            }
        }
    }

    private static func tieBreak(_ lhs: CodexSessionSummary, _ rhs: CodexSessionSummary) -> Bool {
        let dateComparison = compareDates(lhs.updatedAt, rhs.updatedAt)
        if dateComparison != .orderedSame {
            return dateComparison == .orderedDescending
        }

        let labelComparison = lhs.label.localizedStandardCompare(rhs.label)
        if labelComparison != .orderedSame {
            return labelComparison == .orderedAscending
        }

        return lhs.sessionId < rhs.sessionId
    }

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
        return calendar
    }

    private static func dayBucketFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func dayLabelFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func displayDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = AppLocalization.currentLanguage.locale
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }

    private static let isoFormatterLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let standardISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
