import Foundation

struct OpenCodeGoDashboardUsage {
    let rolling: UsageWindow?
    let weekly: UsageWindow?
    let monthly: UsageWindow?

    struct UsageWindow {
        let usagePercent: Double
        let resetInSec: Int
        let resetDate: Date
    }

    var maxUsagePercent: Double? {
        [rolling?.usagePercent, weekly?.usagePercent, monthly?.usagePercent]
            .compactMap { $0 }.max()
    }
}

enum OpenCodeGoDashboardFetcher {
    private static let modelsURL = URL(string: "https://opencode.ai/zen/go/v1/models")!

    static func fetch(apiKey: String, workspaceID: String, cookie: String) async throws -> OpenCodeGoDashboardUsage {
        let modelCount = try await fetchModelCount(apiKey: apiKey)
        guard modelCount > 0 else {
            throw BalanceFetchError.unavailable("无可用 Go 模型")
        }

        return try await fetchDashboardUsage(workspaceID: workspaceID, cookie: cookie)
    }

    private static func fetchModelCount(apiKey: String) async throws -> Int {
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.unavailable("Go Models API 响应无效")
        }
        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.unavailable("Go Models API HTTP \(httpResponse.statusCode)")
        }

        let object = try JSONSerialization.jsonObject(with: data)
        if let dict = object as? [String: Any] {
            if let arr = dict["data"] as? [Any] { return arr.count }
            if let arr = dict["models"] as? [Any] { return arr.count }
        }
        if let arr = object as? [Any] { return arr.count }
        throw BalanceFetchError.unavailable("无法解析模型列表")
    }

    private static func fetchDashboardUsage(workspaceID: String, cookie: String) async throws -> OpenCodeGoDashboardUsage {
        guard let url = URL(string: "https://opencode.ai/workspace/\(workspaceID)/go") else {
            throw BalanceFetchError.unavailable("Invalid workspace URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeaderValue(for: cookie), forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let config2 = URLSessionConfiguration.ephemeral
        config2.timeoutIntervalForRequest = 30
        config2.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config2)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.unavailable("无效响应")
        }
        switch httpResponse.statusCode {
        case 200: break
        case 302, 401, 403:
            throw BalanceFetchError.unavailable("Cookie 已过期，请重新配置")
        default:
            throw BalanceFetchError.unavailable("Go Dashboard HTTP \(httpResponse.statusCode)")
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw BalanceFetchError.unavailable("无法解析页面")
        }

        guard let usage = parseWindows(from: html) else {
            #if DEBUG
            let head = String(html.prefix(500))
            let tail = String(html.suffix(500))
            print("[OpenCodeGoDashboard] HTML head:\n\(head)")
            print("[OpenCodeGoDashboard] HTML tail:\n\(tail)")
            #endif

            if html.contains("rollingUsage") || html.contains("monthlyUsage") {
                throw BalanceFetchError.unavailable("页面格式已更新，解析失败。请在 GitHub Issues 报告此问题")
            } else {
                throw BalanceFetchError.unavailable("页面不含配额数据。可能原因：Cookie 与 Workspace ID 不匹配，或该账号尚未订阅 Go 计划")
            }
        }

        return usage
    }

    static func cookieHeaderValue(for cookie: String) -> String {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("auth=") ? trimmed : "auth=\(trimmed)"
    }

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
