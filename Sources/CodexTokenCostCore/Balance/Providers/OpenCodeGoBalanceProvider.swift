import Foundation

public struct OpenCodeGoBalanceChecker: BalanceChecker {
    public var providerKind: BalanceProviderKind { .opencodeGo }
    let allowEnvironmentCredentials: Bool

    public init(allowEnvironmentCredentials: Bool = false) {
        self.allowEnvironmentCredentials = allowEnvironmentCredentials
    }

    public func fetch(authToken: String) async -> BalanceSnapshot {
        guard !authToken.isEmpty else {
            return .unavailable(.opencodeGo, reason: "未找到 OpenCode Go API key")
        }

        let (workspaceID, cookie) = SecureCredentialStore.shared.discoverCredentials(
            allowEnvironment: allowEnvironmentCredentials
        )
        guard let workspaceID, let cookie else {
            return .unavailable(.opencodeGo, reason: "请先在设置中配置 OpenCode Go 凭证")
        }

        let usage: OpenCodeGoDashboardUsage
        do {
            usage = try await OpenCodeGoDashboardFetcher.fetch(
                apiKey: authToken,
                workspaceID: workspaceID,
                cookie: cookie
            )
        } catch {
            return .unavailable(.opencodeGo, reason: error.localizedDescription)
        }

        let rolling = usage.rolling
        let weekly = usage.weekly
        let monthly = usage.monthly

        // Build unified quotaWindows
        var windows: [BalanceQuotaWindow] = []
        if let r = rolling {
            windows.append(BalanceQuotaWindow(
                label: "5小时", usedRatio: r.usagePercent / 100.0,
                remainingRatio: r.usagePercent < 100 ? (100 - r.usagePercent) / 100.0 : 0,
                resetAt: r.resetDate, windowSeconds: 5 * 3600
            ))
        }
        if let w = weekly {
            windows.append(BalanceQuotaWindow(
                label: "每周", usedRatio: w.usagePercent / 100.0,
                remainingRatio: w.usagePercent < 100 ? (100 - w.usagePercent) / 100.0 : 0,
                resetAt: w.resetDate, windowSeconds: 7 * 86400
            ))
        }
        if let m = monthly {
            windows.append(BalanceQuotaWindow(
                label: "每月", usedRatio: m.usagePercent / 100.0,
                remainingRatio: m.usagePercent < 100 ? (100 - m.usagePercent) / 100.0 : 0,
                resetAt: m.resetDate, windowSeconds: 30 * 86400
            ))
        }

        return BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: Date(),
            isAvailable: true,
            usagePercent: usage.maxUsagePercent.map { $0 / 100.0 },
            primaryWindowLabel: rolling != nil ? "5小时" : nil,
            primaryWindowUsagePercent: rolling.map { $0.usagePercent / 100.0 },
            primaryWindowResetAt: rolling?.resetDate,
            secondaryWindowLabel: weekly != nil ? "每周" : nil,
            secondaryWindowUsagePercent: weekly.map { $0.usagePercent / 100.0 },
            secondaryWindowResetAt: weekly?.resetDate,
            tertiaryWindowLabel: monthly != nil ? "每月" : nil,
            tertiaryWindowUsagePercent: monthly.map { $0.usagePercent / 100.0 },
            tertiaryWindowResetAt: monthly?.resetDate,
            quotaWindows: windows.isEmpty ? nil : windows
        )
    }

    /// Shared parser for OpenCode Go model costs from CLI output.
    /// Used by both Go checker (CLI fallback) and Zen checker (dedup).
    static func parseGoModelCosts(from output: String) -> [String: Double] {
        let lines = output.components(separatedBy: .newlines)
        var modelCosts: [String: Double] = [:]
        var currentModel: String?
        let goProviderPrefixes = ["opencode-go/", "go/", "opencode_go/", "Go:", "go:"]

        func isGoModelLine(_ text: String) -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            let lower = trimmed.lowercased()
            // Match any known Go provider prefix, excluding summary lines
            for prefix in goProviderPrefixes {
                if lower.hasPrefix(prefix) { return true }
            }
            // Also match bare model names prefixed with "opencode-go" anywhere
            if lower.hasPrefix("opencode-go") || lower.contains("opencode-go/") {
                return true
            }
            return false
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("│") else { continue }
            let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)

            if isGoModelLine(inner),
               !inner.localizedCaseInsensitiveContains("Messages"),
               !inner.localizedCaseInsensitiveContains("Tokens"),
               !inner.localizedCaseInsensitiveContains("Cost"),
               !inner.localizedCaseInsensitiveContains("Input"),
               !inner.localizedCaseInsensitiveContains("Output"),
               !inner.localizedCaseInsensitiveContains("Cache"),
               !inner.localizedCaseInsensitiveContains("Avg") {
                currentModel = inner.trimmingCharacters(in: .whitespaces)
                continue
            }

            if let model = currentModel, inner.hasPrefix("Cost"),
               let dollarRange = inner.range(of: "$") {
                let valueStr = inner[dollarRange.upperBound...].trimmingCharacters(in: .whitespaces)
                if let cost = Double(valueStr) {
                    modelCosts[model] = cost
                }
                currentModel = nil
            }
        }

        #if DEBUG
        if !modelCosts.isEmpty {
            let total = modelCosts.values.reduce(0, +)
            print("[OpenCodeGoBalance] Parsed \(modelCosts.count) Go model costs: total=$\(String(format: "%.2f", total))")
            for (model, cost) in modelCosts.sorted(by: { $0.value > $1.value }) {
                print("  \(model): $\(String(format: "%.2f", cost))")
            }
        } else {
            print("[OpenCodeGoBalance] No Go model costs found in CLI output")
        }
        #endif

        return modelCosts
    }
}
