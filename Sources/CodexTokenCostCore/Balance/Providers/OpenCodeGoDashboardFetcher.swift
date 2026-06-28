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
            throw BalanceProviderError(
                provider: .opencodeGo,
                category: .process,
                publicMessage: "无可用 Go 模型",
                recoveryHint: "当前账号尚未订阅 OpenCode Go 计划",
                requiresReimport: false
            )
        }

        return try await fetchDashboardUsage(workspaceID: workspaceID, cookie: cookie)
    }

    private static func fetchModelCount(apiKey: String) async throws -> Int {
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BalanceProviderError(
                provider: .opencodeGo,
                category: .network,
                publicMessage: "Go API 不可用",
                recoveryHint: "网络请求失败，请检查网络连接后重试",
                requiresReimport: false
            )
        }

        let object = try JSONSerialization.jsonObject(with: data)
        if let dict = object as? [String: Any] {
            if let arr = dict["data"] as? [Any] { return arr.count }
            if let arr = dict["models"] as? [Any] { return arr.count }
        }
        if let arr = object as? [Any] { return arr.count }
        throw BalanceProviderError(
            provider: .opencodeGo,
            category: .parse,
            publicMessage: "无法解析模型列表",
            recoveryHint: "Go API 返回格式异常",
            requiresReimport: false
        )
    }

    private static func fetchDashboardUsage(workspaceID: String, cookie: String) async throws -> OpenCodeGoDashboardUsage {
        guard let url = URL(string: "https://opencode.ai/workspace/\(workspaceID)/go") else {
            throw BalanceProviderError(
                provider: .opencodeGo,
                category: .process,
                publicMessage: "Invalid workspace URL",
                recoveryHint: "请检查 Workspace ID 格式是否正确",
                requiresReimport: false
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("auth=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceProviderError(
                provider: .opencodeGo,
                category: .network,
                publicMessage: "无效响应",
                recoveryHint: "服务器返回了无效响应，请稍后重试",
                requiresReimport: false
            )
        }
        switch httpResponse.statusCode {
        case 200: break
        case 302, 401, 403:
            throw BalanceProviderError(
                provider: .opencodeGo,
                category: .auth,
                publicMessage: "Cookie 已过期",
                underlyingCode: "HTTP \(httpResponse.statusCode)",
                recoveryHint: "Auth Cookie 已过期，请从浏览器重新导入或手动更新",
                requiresReimport: true
            )
        default:
            throw BalanceProviderError(
                provider: .opencodeGo,
                category: .network,
                publicMessage: "HTTP \(httpResponse.statusCode)",
                recoveryHint: "服务器返回异常状态码，请稍后重试",
                requiresReimport: false
            )
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw BalanceProviderError(
                provider: .opencodeGo,
                category: .parse,
                publicMessage: "无法解析页面",
                recoveryHint: "服务器返回了非文本内容",
                requiresReimport: false
            )
        }

        guard let usage = parseWindows(from: html) else {
            #if DEBUG
            let head = String(html.prefix(500))
            let tail = String(html.suffix(500))
            print("[OpenCodeGoDashboard] HTML head:\n\(head)")
            print("[OpenCodeGoDashboard] HTML tail:\n\(tail)")
            #endif

            if html.contains("rollingUsage") || html.contains("monthlyUsage") {
                throw BalanceProviderError(
                    provider: .opencodeGo,
                    category: .parse,
                    publicMessage: "页面格式已更新，解析失败",
                    recoveryHint: "页面格式已更新，解析失败。请在 GitHub Issues 报告此问题",
                    requiresReimport: false
                )
            } else {
                throw BalanceProviderError(
                    provider: .opencodeGo,
                    category: .auth,
                    publicMessage: "页面不含配额数据",
                    recoveryHint: "Cookie 与 Workspace ID 不匹配，或该账号尚未订阅 Go 计划。请重新从浏览器导入",
                    requiresReimport: true
                )
            }
        }

        return usage
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
