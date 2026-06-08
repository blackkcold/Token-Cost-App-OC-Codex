import Foundation

// MARK: - HTML Parsing (SolidJS SSR hydration)

// Regex patterns matching SolidJS SSR hydration output.
// Format: rollingUsage:$R[42]={usagePercent:65,resetInSec:2520}
// Field order may vary, so we try both orderings for each window.
private static let numberPattern = #"(-?\d+(?:\.\d+)?)"#

private static func patterns(for field: String) -> (pctFirst: NSRegularExpression, resetFirst: NSRegularExpression)? {
    guard let pctFirst = try? NSRegularExpression(
        pattern: #"\#(field):\$R\[\d+\]=\{[^}]*usagePercent:\#(numberPattern)[^}]*resetInSec:\#(numberPattern)[^}]*\}"#,
        options: []
    ),
    let resetFirst = try? NSRegularExpression(
        pattern: #"\#(field):\$R\[\d+\]=\{[^}]*resetInSec:\#(numberPattern)[^}]*usagePercent:\#(numberPattern)[^}]*\}"#,
        options: []
    ) else {
        return nil
    }
    return (pctFirst, resetFirst)
}

private static func parseWindowUsage(html: String, field: String) -> OpenCodeGoDashboardUsage.UsageWindow? {
    guard let (pctFirst, resetFirst) = patterns(for: field) else { return nil }
    let nsRange = NSRange(html.startIndex..., in: html)

    // Try usagePercent-first ordering
    if let match = pctFirst.firstMatch(in: html, options: [], range: nsRange),
       match.numberOfRanges == 3,
       let pctRange = Range(match.range(at: 1), in: html),
       let secRange = Range(match.range(at: 2), in: html),
       let pct = Double(html[pctRange]),
       let sec = Int(html[secRange]),
       pct.isFinite, sec >= 0 {
        return OpenCodeGoDashboardUsage.UsageWindow(
            usagePercent: pct,
            resetInSec: sec,
            resetDate: Date().addingTimeInterval(Double(sec))
        )
    }

    // Try resetInSec-first ordering
    if let match = resetFirst.firstMatch(in: html, options: [], range: nsRange),
       match.numberOfRanges == 3,
       let secRange = Range(match.range(at: 1), in: html),
       let pctRange = Range(match.range(at: 2), in: html),
       let sec = Int(html[secRange]),
       let pct = Double(html[pctRange]),
       sec >= 0, pct.isFinite {
        return OpenCodeGoDashboardUsage.UsageWindow(
            usagePercent: pct,
            resetInSec: sec,
            resetDate: Date().addingTimeInterval(Double(sec))
        )
    }

    return nil
}

static func parseWindows(from html: String) -> OpenCodeGoDashboardUsage? {
    let rolling = parseWindowUsage(html: html, field: "rollingUsage")
    let weekly = parseWindowUsage(html: html, field: "weeklyUsage")
    let monthly = parseWindowUsage(html: html, field: "monthlyUsage")

    // Return nil only if ALL windows are missing
    guard rolling != nil || weekly != nil || monthly != nil else {
        return nil
    }

    return OpenCodeGoDashboardUsage(
        rolling: rolling,
        weekly: weekly,
        monthly: monthly
    )
}
}

struct BalanceFetchError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    static func unavailable(_ msg: String) -> BalanceFetchError {
        BalanceFetchError(message: msg)
    }
}
