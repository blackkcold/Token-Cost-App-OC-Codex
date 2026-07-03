import Foundation

public struct OllamaBalanceChecker: BalanceChecker {
    public var providerKind: BalanceProviderKind { .ollama }

    public init() {}

    public func fetch(authToken: String) async throws -> BalanceSnapshot {
        guard !authToken.isEmpty else {
            return .unavailable(.ollama, reason: AppLocalization.text("balance.ollama.error.noCookie"))
        }

        guard let url = URL(string: "https://ollama.com/settings") else {
            return .unavailable(.ollama, reason: AppLocalization.text("balance.ollama.error.invalidUrl"))
        }

        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(authToken, forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 30

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .unavailable(.ollama, reason: AppLocalization.format("balance.ollama.error.network", error.localizedDescription))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .unavailable(.ollama, reason: AppLocalization.text("balance.ollama.error.invalidResponse"))
        }

        if let finalURL = httpResponse.url {
            let path = finalURL.path.lowercased()
            if path.contains("/login") || path.contains("/signin") || path.contains("/auth") {
                return .unavailable(.ollama, reason: AppLocalization.text("balance.ollama.error.cookieExpiredRedirect"))
            }
        }
        switch httpResponse.statusCode {
        case 200:
            break
        case 302, 303, 307:
            return .unavailable(.ollama, reason: AppLocalization.text("balance.ollama.error.cookieExpiredRedirectLogin"))
        case 401, 403:
            return .unavailable(.ollama, reason: AppLocalization.text("balance.ollama.error.cookieExpired"))
        default:
            return .unavailable(.ollama, reason: "HTTP \(httpResponse.statusCode)")
        }

        guard let html = String(data: data, encoding: .utf8) else {
            return .unavailable(.ollama, reason: AppLocalization.text("balance.ollama.error.parseFailed"))
        }

        return parseUsage(from: html)
    }

    // MARK: - HTML Parsing

    internal func parseUsageForTesting(from html: String) -> BalanceSnapshot {
        parseUsage(from: html)
    }

    /// Session window duration in seconds (5 hours).
    private static let sessionWindowSeconds = 18_000
    /// Weekly window duration in seconds (7 days).
    private static let weeklyWindowSeconds = 604_800

    private func parseUsage(from html: String) -> BalanceSnapshot {
        // Strategy 1 (preferred): aria-label="Session usage NN%" + aria-label="Weekly usage NN%"
        // This is the structured format on the current Ollama Cloud settings page.
        let sessionPct = extractUsagePercent(from: html, label: "Session")
        let weeklyPct = extractUsagePercent(from: html, label: "Weekly")

        if sessionPct != nil || weeklyPct != nil {
            let timestamps = extractResetTimestamps(from: html)
            let sessionReset = timestamps.count >= 1 ? timestamps[0] : nil
            let weeklyReset = timestamps.count >= 2 ? timestamps[1] : nil
            let planType = extractPlanType(from: html)

            return buildSnapshot(
                sessionPct: sessionPct,
                weeklyPct: weeklyPct,
                sessionResetAt: sessionReset,
                weeklyResetAt: weeklyReset,
                planType: planType
            )
        }

        // Strategy 2 (legacy fallback): data-usage-track aria-label="..%"
        if let pct = extractPercent(from: html, pattern: #"data-usage-track[^>]*aria-label="([^"]*%)""#) {
            return buildSnapshot(usagePercent: pct)
        }
        // Strategy 3 (legacy fallback): usage-meter__fill style width:NN%
        if let pct = extractPercent(from: html, pattern: #"usage-meter__fill[^>]*style="[^"]*width:\s*(\d+(?:\.\d+)?)%"#) {
            return buildSnapshot(usagePercent: pct)
        }
        // Strategy 4 (legacy fallback): generic "NN% used" / "已用 NN%"
        if let pct = extractPercent(from: html, pattern: #"(\d+(?:\.\d+)?)%\s*(?:used|已用)"#) {
            return buildSnapshot(usagePercent: pct)
        }

        BalanceLog.provider.notice("Ollama HTML parse failed — HTML length: \(html.count), all strategies exhausted")

        return .unavailable(.ollama, reason: AppLocalization.text("balance.ollama.error.noUsageData"))
    }

    // MARK: - New parsers (Session/Weekly windows)

    private static let planLabelPattern = #"Cloud usage</span>\s*<span[^>]*>(\w+)</span>"#

    private func extractPlanType(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: Self.planLabelPattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: html)
        else { return nil }
        let value = String(html[captureRange]).lowercased()
        return value.isEmpty ? nil : value
    }

    /// Extracts usage percentage for a named window (e.g. "Session", "Weekly") from
    /// `aria-label="<label> usage NN%"` in the HTML.
    ///
    /// The `%` and closing `"` may be separated by a suffix such as ` used`
    /// (e.g. `aria-label="Session usage 51% used"`); `[^"]*` tolerates that suffix
    /// while still allowing the legacy suffix-less form (`aria-label="Session usage 51%"`).
    private func extractUsagePercent(from html: String, label: String) -> Double? {
        let pattern = #"aria-label="\#(label) usage (\d+(?:\.\d+)?)%[^"]*""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: html)
        else { return nil }
        guard let value = Double(String(html[captureRange])), value.isFinite, value >= 0, value <= 100
        else { return nil }
        return value / 100.0
    }

    /// Extracts `data-time="ISO_TIMESTAMP"` values from the HTML, in document order.
    private func extractResetTimestamps(from html: String) -> [Date] {
        let pattern = #"data-time="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return [] }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var results: [Date] = []
        regex.enumerateMatches(in: html, range: NSRange(html.startIndex..., in: html)) { match, _, _ in
            guard let match,
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: html)
            else { return }
            let raw = String(html[captureRange])
            if let date = formatter.date(from: raw) {
                results.append(date)
            }
        }
        return results
    }

    // MARK: - Legacy fallback percent extraction

    private func extractPercent(from html: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: html)
        else { return nil }
        let captured = String(html[captureRange]).replacingOccurrences(of: "%", with: "")
        guard let value = Double(captured), value.isFinite, value >= 0, value <= 100
        else { return nil }
        return value / 100.0
    }

    // MARK: - Snapshot builders

    /// Builds a multi-window snapshot for the new `aria-label="Session/Weekly usage"` format.
    private func buildSnapshot(
        sessionPct: Double?,
        weeklyPct: Double?,
        sessionResetAt: Date?,
        weeklyResetAt: Date?,
        planType: String? = nil
    ) -> BalanceSnapshot {
        let sessionLabel = AppLocalization.text("balance.ollama.window.session")
        let weeklyLabel = AppLocalization.text("balance.ollama.window.weekly")

        var windows: [BalanceQuotaWindow] = []
        if let s = sessionPct {
            windows.append(BalanceQuotaWindow(
                label: sessionLabel,
                usedRatio: s,
                remainingRatio: s < 1.0 ? 1.0 - s : 0,
                resetAt: sessionResetAt,
                windowSeconds: Self.sessionWindowSeconds
            ))
        }
        if let w = weeklyPct {
            windows.append(BalanceQuotaWindow(
                label: weeklyLabel,
                usedRatio: w,
                remainingRatio: w < 1.0 ? 1.0 - w : 0,
                resetAt: weeklyResetAt,
                windowSeconds: Self.weeklyWindowSeconds
            ))
        }

        // usagePercent: the higher of the two (mirrors Codex's max(primary, secondary) approach)
        let maxPct: Double? = {
            let a = sessionPct ?? 0, b = weeklyPct ?? 0
            let m = max(a, b)
            return m > 0 ? m : nil
        }()

        return BalanceSnapshot(
            provider: .ollama,
            fetchedAt: Date(),
            isAvailable: true,
            usagePercent: maxPct,
            planType: planType,
            primaryWindowLabel: sessionPct != nil ? sessionLabel : nil,
            primaryWindowUsagePercent: sessionPct,
            primaryWindowResetAt: sessionResetAt,
            secondaryWindowLabel: weeklyPct != nil ? weeklyLabel : nil,
            secondaryWindowUsagePercent: weeklyPct,
            secondaryWindowResetAt: weeklyResetAt,
            quotaWindows: windows.isEmpty ? nil : windows
        )
    }

    /// Legacy single-window builder (for backward-compatible fallback paths).
    private func buildSnapshot(usagePercent: Double) -> BalanceSnapshot {
        let label = AppLocalization.text("balance.ollama.window.session")
        let window = BalanceQuotaWindow(
            label: label,
            usedRatio: usagePercent,
            remainingRatio: max(0, 1.0 - usagePercent)
        )
        return BalanceSnapshot(
            provider: .ollama,
            fetchedAt: Date(),
            isAvailable: true,
            usagePercent: usagePercent,
            quotaWindows: [window]
        )
    }
}