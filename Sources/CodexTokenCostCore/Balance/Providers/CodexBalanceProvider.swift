import Foundation

public struct CodexBalanceChecker: BalanceChecker {
    public let providerKind: BalanceProviderKind = .codex

    public init() {}

    public func fetch(authToken: String) async throws -> BalanceSnapshot {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            return .unavailable(.codex, reason: "Invalid URL")
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .unavailable(.codex, reason: "Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .unavailable(.codex, reason: "Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            return .unavailable(.codex, reason: "OAuth token 已过期，请重新登录 Codex")
        default:
            return .unavailable(.codex, reason: "HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()

        struct CreditDetails: Decodable {
            let balance: Double?
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let doubleValue = try? container.decode(Double.self, forKey: .balance) {
                    self.balance = doubleValue
                } else if let stringValue = try? container.decode(String.self, forKey: .balance) {
                    self.balance = Double(stringValue)
                } else {
                    self.balance = nil
                }
            }
            enum CodingKeys: String, CodingKey { case balance }
        }

        struct WindowSnapshot: Decodable {
            let usedPercent: Int
            let resetAt: Int
            let limitWindowSeconds: Int
            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case resetAt = "reset_at"
                case limitWindowSeconds = "limit_window_seconds"
            }
        }

        struct RateLimitDetails: Decodable {
            let primaryWindow: WindowSnapshot?
            let secondaryWindow: WindowSnapshot?
            enum CodingKeys: String, CodingKey {
                case primaryWindow = "primary_window"
                case secondaryWindow = "secondary_window"
            }
        }

        struct UsageResponse: Decodable {
            let planType: String?
            let rateLimit: RateLimitDetails?
            let credits: CreditDetails?
            enum CodingKeys: String, CodingKey {
                case planType = "plan_type"
                case rateLimit = "rate_limit"
                case credits
            }
        }

        let usage: UsageResponse
        do {
            usage = try decoder.decode(UsageResponse.self, from: data)
        } catch {
            return .unavailable(.codex, reason: "Failed to parse response")
        }

        let primary = usage.rateLimit?.primaryWindow
        let secondary = usage.rateLimit?.secondaryWindow

        let primaryPct = primary.map { Double($0.usedPercent) / 100.0 }
        let secondaryPct = secondary.map { Double($0.usedPercent) / 100.0 }

        let maxPct: Double? = {
            let a = primaryPct ?? 0, b = secondaryPct ?? 0
            return max(a, b) > 0 ? max(a, b) : nil
        }()

        let primaryReset = primary.map { Date(timeIntervalSince1970: Double($0.resetAt)) }
        let secondaryReset = secondary.map { Date(timeIntervalSince1970: Double($0.resetAt)) }

        // Build unified quotaWindows
        var windows: [BalanceQuotaWindow] = []
        if let p = primary {
            let pct = Double(p.usedPercent) / 100.0
            windows.append(BalanceQuotaWindow(
                label: windowLabel(p.limitWindowSeconds),
                usedRatio: pct,
                remainingRatio: pct < 1.0 ? 1.0 - pct : 0,
                resetAt: primaryReset,
                windowSeconds: p.limitWindowSeconds
            ))
        }
        if let s = secondary {
            let pct = Double(s.usedPercent) / 100.0
            windows.append(BalanceQuotaWindow(
                label: windowLabel(s.limitWindowSeconds),
                usedRatio: pct,
                remainingRatio: pct < 1.0 ? 1.0 - pct : 0,
                resetAt: secondaryReset,
                windowSeconds: s.limitWindowSeconds
            ))
        }

        return BalanceSnapshot(
            provider: .codex,
            fetchedAt: Date(),
            isAvailable: true,
            remainingCredits: usage.credits?.balance,
            usagePercent: maxPct,
            planType: usage.planType,
            primaryWindowLabel: primary.map { windowLabel($0.limitWindowSeconds) },
            primaryWindowUsagePercent: primaryPct,
            primaryWindowResetAt: primaryReset,
            secondaryWindowLabel: secondary.map { windowLabel($0.limitWindowSeconds) },
            secondaryWindowUsagePercent: secondaryPct,
            secondaryWindowResetAt: secondaryReset,
            quotaWindows: windows.isEmpty ? nil : windows
        )
    }

    private func windowLabel(_ seconds: Int) -> String {
        if seconds <= 18000 + 3600 { return "5小时" }
        if seconds <= 604800 + 86400 { return "7天" }
        return "\(seconds / 3600)小时"
    }
}
