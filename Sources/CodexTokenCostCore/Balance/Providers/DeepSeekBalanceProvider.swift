import Foundation

public struct DeepSeekBalanceChecker: BalanceChecker {
    public var providerKind: BalanceProviderKind { .deepseek }

    public init() {}

    public func fetch(authToken: String) async throws -> BalanceSnapshot {
        guard !authToken.isEmpty else {
            return .unavailable(.deepseek, reason: "未找到 DeepSeek API key")
        }

        guard let url = URL(string: "https://api.deepseek.com/user/balance") else {
            return .unavailable(.deepseek, reason: "Invalid URL")
        }

        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .unavailable(.deepseek, reason: "Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .unavailable(.deepseek, reason: "Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            return .unavailable(.deepseek, reason: "API key 无效或已过期")
        default:
            return .unavailable(.deepseek, reason: "HTTP \(httpResponse.statusCode)")
        }

        return parseBalanceResponse(data: data)
    }

    // MARK: - Response parsing

    private func parseBalanceResponse(data: Data) -> BalanceSnapshot {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unavailable(.deepseek, reason: "无法解析响应")
        }

        let isAvailable = json["is_available"] as? Bool ?? true
        guard isAvailable else {
            return .unavailable(.deepseek, reason: "账户不可用")
        }

        guard let balanceInfos = json["balance_infos"] as? [[String: Any]], !balanceInfos.isEmpty else {
            return .unavailable(.deepseek, reason: "无余额信息")
        }

        var entries: [BalanceValueEntry] = []
        for info in balanceInfos {
            let currency = info["currency"] as? String
            let label = currency ?? "余额"

            // amount may be a number or a numeric string
            let totalBalance = parseDouble(from: info["total_balance"])
            let grantedBalance = parseDouble(from: info["granted_balance"])
            let toppedUpBalance = parseDouble(from: info["topped_up_balance"])

            if let amount = totalBalance {
                entries.append(BalanceValueEntry(
                    label: label,
                    currencyCode: currency,
                    amount: amount,
                    grantedAmount: grantedBalance,
                    toppedUpAmount: toppedUpBalance
                ))
            }
        }

        guard !entries.isEmpty else {
            return .unavailable(.deepseek, reason: "无法解析余额数据")
        }

        return BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: Date(),
            isAvailable: true,
            valueEntries: entries
        )
    }

    private func parseDouble(from value: Any?) -> Double? {
        guard let value else { return nil }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
