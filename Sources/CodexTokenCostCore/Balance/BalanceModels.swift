import Foundation

// MARK: - Provider kinds

/// The balance providers this app can query.
public enum BalanceProviderKind: String, Codable, CaseIterable, Sendable {
    case opencodeGo = "opencode_go"
    case opencodeZen = "opencode_zen"
    case codex = "codex"
    case deepseek = "deepseek"
    case ollama = "ollama"

    /// Stable sort order for UI display (lower = first).
    public var sortOrder: Int {
        switch self {
        case .opencodeGo: return 0
        case .codex: return 1
        case .opencodeZen: return 2
        case .deepseek: return 3
        case .ollama: return 4
        }
    }

    public var displayName: String {
        switch self {
        case .opencodeGo: return "OpenCode Go"
        case .opencodeZen: return "OpenCode Zen"
        case .codex: return "Codex"
        case .deepseek: return "DeepSeek"
        case .ollama: return "Ollama Cloud"
        }
    }
}

// MARK: - Usage gradient

public enum UsageGradient: Sendable {
    case unused
    case low
    case moderate
    case high
    case critical
    case exceeded
    case unknown

    public var label: String {
        switch self {
        case .unused: return "未使用"
        case .low: return "剩余充足"
        case .moderate: return "适中"
        case .high: return "接近上限"
        case .critical: return "即将用尽"
        case .exceeded: return "已超额"
        case .unknown: return "未知"
        }
    }
}


// MARK: - Value entry (multi-currency balance)

/// A single currency-denominated balance entry (e.g. CNY, USD).
public struct BalanceValueEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(label)-\(currencyCode ?? "???")-\(amount)" }
    public let label: String
    public let currencyCode: String?
    public let amount: Double
    public let grantedAmount: Double?
    public let toppedUpAmount: Double?

    public init(
        label: String,
        currencyCode: String? = nil,
        amount: Double,
        grantedAmount: Double? = nil,
        toppedUpAmount: Double? = nil
    ) {
        self.label = label
        self.currencyCode = currencyCode
        self.amount = amount
        self.grantedAmount = grantedAmount
        self.toppedUpAmount = toppedUpAmount
    }
}

// MARK: - Structured provider error

/// Categorised error for a balance provider, with safe public messaging.
public struct BalanceProviderError: Error, Codable, Hashable, Sendable {
    public enum Category: String, Codable, Sendable {
        case auth
        case network
        case process
        case parse
        case unknown
    }

    public let provider: BalanceProviderKind
    public let category: Category
    public let publicMessage: String
    public let underlyingCode: String?
    public let recoveryHint: String
    public let requiresReimport: Bool

    public init(
        provider: BalanceProviderKind,
        category: Category,
        publicMessage: String,
        underlyingCode: String? = nil,
        recoveryHint: String = "",
        requiresReimport: Bool = false
    ) {
        self.provider = provider
        self.category = category
        self.publicMessage = publicMessage
        self.underlyingCode = underlyingCode
        self.recoveryHint = recoveryHint
        self.requiresReimport = requiresReimport
    }

    private enum CodingKeys: String, CodingKey {
        case provider, category, publicMessage
        case underlyingCode, recoveryHint, requiresReimport
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.provider = try c.decode(BalanceProviderKind.self, forKey: .provider)
        self.category = try c.decode(Category.self, forKey: .category)
        self.publicMessage = try c.decode(String.self, forKey: .publicMessage)
        self.underlyingCode = try c.decodeIfPresent(String.self, forKey: .underlyingCode)
        self.recoveryHint = try c.decodeIfPresent(String.self, forKey: .recoveryHint) ?? ""
        self.requiresReimport = try c.decodeIfPresent(Bool.self, forKey: .requiresReimport) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(provider, forKey: .provider)
        try c.encode(category, forKey: .category)
        try c.encode(publicMessage, forKey: .publicMessage)
        try c.encodeIfPresent(underlyingCode, forKey: .underlyingCode)
        try c.encode(recoveryHint, forKey: .recoveryHint)
        try c.encode(requiresReimport, forKey: .requiresReimport)
    }
}

// MARK: - Balance configuration

/// Runtime configuration for the balance subsystem.
public struct BalanceConfiguration: Codable, Equatable, Sendable {
    /// Providers enabled for querying.
    /// Default: OpenCode Go, Codex, OpenCode Zen (DeepSeek and Ollama are opt-in).
    public var enabledBalanceProviders: [BalanceProviderKind]
    /// Allow reading credentials from environment variables (off by default).
    public var allowEnvironmentCredentials: Bool

    public init(
        enabledBalanceProviders: [BalanceProviderKind] = [.opencodeGo, .codex, .opencodeZen],
        allowEnvironmentCredentials: Bool = false
    ) {
        self.enabledBalanceProviders = enabledBalanceProviders
        self.allowEnvironmentCredentials = allowEnvironmentCredentials
    }
}

// MARK: - Consumption rate

public struct ConsumptionRate: Codable, Hashable, Sendable {
    public let perHour: Double
    public let perDay: Double
    public let confidence: Double

    public init(perHour: Double = 0, perDay: Double = 0, confidence: Double = 0) {
        self.perHour = perHour
        self.perDay = perDay
        self.confidence = confidence
    }
}

// MARK: - Sort / display preferences

public enum BalanceSortOrder: String, Codable, CaseIterable, Sendable {
    case quotaFirst
    case balanceFirst
    case byProvider
}

public enum BalanceDisplayMode: String, Codable, CaseIterable, Sendable {
    case used
    case remaining
}

// MARK: - Quota window

/// A single time-based quota window (e.g. 5-hour rolling, weekly, monthly).
public struct BalanceQuotaWindow: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(label)-\(windowSeconds ?? 0)" }
    public let label: String
    public let usedRatio: Double?
    public let remainingRatio: Double?
    public let resetAt: Date?
    public let windowSeconds: Int?
    public let consumptionRate: ConsumptionRate?

    public init(
        label: String,
        usedRatio: Double? = nil,
        remainingRatio: Double? = nil,
        resetAt: Date? = nil,
        windowSeconds: Int? = nil,
        consumptionRate: ConsumptionRate? = nil
    ) {
        self.label = label
        self.usedRatio = usedRatio
        self.remainingRatio = remainingRatio
        self.resetAt = resetAt
        self.windowSeconds = windowSeconds
        self.consumptionRate = consumptionRate
    }
}

// MARK: - Snapshot

/// A point-in-time snapshot of balance information for a single provider.
public struct BalanceSnapshot: Codable, Sendable, Identifiable {
    public var id: String { provider.rawValue }

    public let provider: BalanceProviderKind
    public let fetchedAt: Date
    public let isAvailable: Bool
    public let errorMessage: String?
    public let errorRecoveryHint: String?
    public let errorRequiresReimport: Bool

    // -- Generic fields --
    public let remainingCredits: Double?
    public let totalCredits: Double?
    public let usedCredits: Double?
    public let usagePercent: Double?

    // -- Subscription / plan info --
    public let planType: String?

    // -- Codex-specific --
    public let primaryWindowLabel: String?
    public let primaryWindowUsagePercent: Double?
    public let primaryWindowResetAt: Date?
    public let secondaryWindowLabel: String?
    public let secondaryWindowUsagePercent: Double?
    public let secondaryWindowResetAt: Date?
    public let tertiaryWindowLabel: String?
    public let tertiaryWindowUsagePercent: Double?
    public let tertiaryWindowResetAt: Date?

    // -- Unified quota windows --
    public let quotaWindows: [BalanceQuotaWindow]?

    // -- Multi-currency value entries (DeepSeek etc.) --
    public let valueEntries: [BalanceValueEntry]?

    // -- Zen-specific --
    public let totalCostUSD: Double?
    public let avgCostPerDayUSD: Double?

    // MARK: Init

    public init(
        provider: BalanceProviderKind,
        fetchedAt: Date,
        isAvailable: Bool,
        errorMessage: String? = nil,
        errorRecoveryHint: String? = nil,
        errorRequiresReimport: Bool = false,
        remainingCredits: Double? = nil,
        totalCredits: Double? = nil,
        usedCredits: Double? = nil,
        usagePercent: Double? = nil,
        planType: String? = nil,
        primaryWindowLabel: String? = nil,
        primaryWindowUsagePercent: Double? = nil,
        primaryWindowResetAt: Date? = nil,
        secondaryWindowLabel: String? = nil,
        secondaryWindowUsagePercent: Double? = nil,
        secondaryWindowResetAt: Date? = nil,
        tertiaryWindowLabel: String? = nil,
        tertiaryWindowUsagePercent: Double? = nil,
        tertiaryWindowResetAt: Date? = nil,
        totalCostUSD: Double? = nil,
        avgCostPerDayUSD: Double? = nil,
        quotaWindows: [BalanceQuotaWindow]? = nil,
        valueEntries: [BalanceValueEntry]? = nil
    ) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.isAvailable = isAvailable
        self.errorMessage = errorMessage
        self.errorRecoveryHint = errorRecoveryHint
        self.errorRequiresReimport = errorRequiresReimport
        self.remainingCredits = remainingCredits
        self.totalCredits = totalCredits
        self.usedCredits = usedCredits
        self.usagePercent = usagePercent
        self.planType = planType
        self.primaryWindowLabel = primaryWindowLabel
        self.primaryWindowUsagePercent = primaryWindowUsagePercent
        self.primaryWindowResetAt = primaryWindowResetAt
        self.secondaryWindowLabel = secondaryWindowLabel
        self.secondaryWindowUsagePercent = secondaryWindowUsagePercent
        self.secondaryWindowResetAt = secondaryWindowResetAt
        self.tertiaryWindowLabel = tertiaryWindowLabel
        self.tertiaryWindowUsagePercent = tertiaryWindowUsagePercent
        self.tertiaryWindowResetAt = tertiaryWindowResetAt
        self.totalCostUSD = totalCostUSD
        self.avgCostPerDayUSD = avgCostPerDayUSD
        self.quotaWindows = quotaWindows
        self.valueEntries = valueEntries
    }

    private enum CodingKeys: String, CodingKey {
        case provider, fetchedAt, isAvailable, errorMessage
        case errorRecoveryHint, errorRequiresReimport
        case remainingCredits, totalCredits, usedCredits, usagePercent, planType
        case primaryWindowLabel, primaryWindowUsagePercent, primaryWindowResetAt
        case secondaryWindowLabel, secondaryWindowUsagePercent, secondaryWindowResetAt
        case tertiaryWindowLabel, tertiaryWindowUsagePercent, tertiaryWindowResetAt
        case totalCostUSD, avgCostPerDayUSD, quotaWindows, valueEntries
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.provider = try c.decode(BalanceProviderKind.self, forKey: .provider)
        self.fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
        self.isAvailable = try c.decode(Bool.self, forKey: .isAvailable)
        self.errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        self.errorRecoveryHint = try c.decodeIfPresent(String.self, forKey: .errorRecoveryHint)
        self.errorRequiresReimport = try c.decodeIfPresent(Bool.self, forKey: .errorRequiresReimport) ?? false
        self.remainingCredits = try c.decodeIfPresent(Double.self, forKey: .remainingCredits)
        self.totalCredits = try c.decodeIfPresent(Double.self, forKey: .totalCredits)
        self.usedCredits = try c.decodeIfPresent(Double.self, forKey: .usedCredits)
        self.usagePercent = try c.decodeIfPresent(Double.self, forKey: .usagePercent)
        self.planType = try c.decodeIfPresent(String.self, forKey: .planType)
        self.primaryWindowLabel = try c.decodeIfPresent(String.self, forKey: .primaryWindowLabel)
        self.primaryWindowUsagePercent = try c.decodeIfPresent(Double.self, forKey: .primaryWindowUsagePercent)
        self.primaryWindowResetAt = try c.decodeIfPresent(Date.self, forKey: .primaryWindowResetAt)
        self.secondaryWindowLabel = try c.decodeIfPresent(String.self, forKey: .secondaryWindowLabel)
        self.secondaryWindowUsagePercent = try c.decodeIfPresent(Double.self, forKey: .secondaryWindowUsagePercent)
        self.secondaryWindowResetAt = try c.decodeIfPresent(Date.self, forKey: .secondaryWindowResetAt)
        self.tertiaryWindowLabel = try c.decodeIfPresent(String.self, forKey: .tertiaryWindowLabel)
        self.tertiaryWindowUsagePercent = try c.decodeIfPresent(Double.self, forKey: .tertiaryWindowUsagePercent)
        self.tertiaryWindowResetAt = try c.decodeIfPresent(Date.self, forKey: .tertiaryWindowResetAt)
        self.totalCostUSD = try c.decodeIfPresent(Double.self, forKey: .totalCostUSD)
        self.avgCostPerDayUSD = try c.decodeIfPresent(Double.self, forKey: .avgCostPerDayUSD)
        self.quotaWindows = try c.decodeIfPresent([BalanceQuotaWindow].self, forKey: .quotaWindows)
        self.valueEntries = try c.decodeIfPresent([BalanceValueEntry].self, forKey: .valueEntries)
    }

    /// Creates a snapshot indicating the provider is unavailable.
    public static func unavailable(
        _ provider: BalanceProviderKind,
        reason: String? = nil,
        recoveryHint: String? = nil,
        requiresReimport: Bool = false,
        fetchedAt: Date = Date()
    ) -> BalanceSnapshot {
        BalanceSnapshot(
            provider: provider,
            fetchedAt: fetchedAt,
            isAvailable: false,
            errorMessage: reason,
            errorRecoveryHint: recoveryHint,
            errorRequiresReimport: requiresReimport
        )
    }

    // MARK: Derived

    /// The usage gradient based on `usagePercent`.
    public var gradient: UsageGradient {
        guard isAvailable else { return .unknown }
        if let pct = usagePercent {
            if pct <= 0 { return .unused }
            if pct < 0.50 { return .low }
            if pct < 0.80 { return .moderate }
            if pct < 0.95 { return .high }
            if pct < 1.0 { return .critical }
            return .exceeded
        }
        if totalCostUSD != nil { return .low }
        if let entries = valueEntries, !entries.isEmpty { return .low }
        return .unknown
    }

    /// A human-readable summary line for menu bar / compact display.
    public var shortSummary: String {
        guard isAvailable else { return "\(provider.displayName) 不可用" }
        if let pct = usagePercent {
            return "\(provider.displayName) \(Int(pct * 100))% \(gradient.label)"
        }
        if let cost = totalCostUSD {
            return "\(provider.displayName) $\(String(format: "%.2f", cost)) 累计"
        }
        if let entries = valueEntries, !entries.isEmpty {
            let parts = entries.map { e in
                let code = e.currencyCode ?? ""
                return "\(code)\(String(format: "%.2f", e.amount))"
            }
            return "\(provider.displayName) \(parts.joined(separator: " "))"
        }
        return "\(provider.displayName) OK"
    }

    public var isQuotaType: Bool {
        quotaWindows != nil || usagePercent != nil
    }

    public var isBalanceType: Bool {
        valueEntries != nil || totalCostUSD != nil
    }
}
