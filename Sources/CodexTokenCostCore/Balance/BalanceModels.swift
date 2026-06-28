import Foundation

// MARK: - Provider kinds

/// The balance providers this app can query.
public enum BalanceProviderKind: String, Codable, CaseIterable, Sendable {
    case opencodeGo = "opencode_go"
    case opencodeZen = "opencode_zen"
    case codex = "codex"
    case deepseek = "deepseek"

    /// Stable sort order for UI display (lower = first).
    public var sortOrder: Int {
        switch self {
        case .opencodeGo: return 0
        case .codex: return 1
        case .opencodeZen: return 2
        case .deepseek: return 3
        }
    }

    public var displayName: String {
        switch self {
        case .opencodeGo: return "OpenCode Go"
        case .opencodeZen: return "OpenCode Zen"
        case .codex: return "Codex"
        case .deepseek: return "DeepSeek"
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
    public var id: String { "\(label)-\(currencyCode ?? "???")" }
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
    /// User-actionable recovery suggestion (UI may display alongside error).
    public let recoveryHint: String
    /// Whether re-importing credentials from browser is the recommended fix.
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
        case underlyingCode
        case recoveryHint
        case requiresReimport
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.provider = try container.decode(BalanceProviderKind.self, forKey: .provider)
        self.category = try container.decode(Category.self, forKey: .category)
        self.publicMessage = try container.decode(String.self, forKey: .publicMessage)
        self.underlyingCode = try container.decodeIfPresent(String.self, forKey: .underlyingCode)
        self.recoveryHint = try container.decodeIfPresent(String.self, forKey: .recoveryHint) ?? ""
        self.requiresReimport = try container.decodeIfPresent(Bool.self, forKey: .requiresReimport) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(category, forKey: .category)
        try container.encode(publicMessage, forKey: .publicMessage)
        try container.encodeIfPresent(underlyingCode, forKey: .underlyingCode)
        try container.encode(recoveryHint, forKey: .recoveryHint)
        try container.encode(requiresReimport, forKey: .requiresReimport)
    }
}

// MARK: - Balance configuration

/// Runtime configuration for the balance subsystem.
public struct BalanceConfiguration: Codable, Equatable, Sendable {
    /// Providers enabled for querying. Default: all built-in except DeepSeek.
    public var enabledBalanceProviders: [BalanceProviderKind]
    /// Allow reading credentials from environment variables (off by default).
    public var allowEnvironmentCredentials: Bool
    /// When true, automatically re-import OpenCode Go credentials from browser
    /// on auth failure (cookie expiration, workspace mismatch).
    public var autoImportFromBrowserOnFailure: Bool

    public init(
        enabledBalanceProviders: [BalanceProviderKind] = [.opencodeGo, .codex, .opencodeZen],
        allowEnvironmentCredentials: Bool = false,
        autoImportFromBrowserOnFailure: Bool = false
    ) {
        self.enabledBalanceProviders = enabledBalanceProviders
        self.allowEnvironmentCredentials = allowEnvironmentCredentials
        self.autoImportFromBrowserOnFailure = autoImportFromBrowserOnFailure
    }

    private enum CodingKeys: String, CodingKey {
        case enabledBalanceProviders
        case allowEnvironmentCredentials
        case autoImportFromBrowserOnFailure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabledBalanceProviders = try container.decodeIfPresent([BalanceProviderKind].self, forKey: .enabledBalanceProviders) ?? [.opencodeGo, .codex, .opencodeZen]
        self.allowEnvironmentCredentials = try container.decodeIfPresent(Bool.self, forKey: .allowEnvironmentCredentials) ?? false
        self.autoImportFromBrowserOnFailure = try container.decodeIfPresent(Bool.self, forKey: .autoImportFromBrowserOnFailure) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabledBalanceProviders, forKey: .enabledBalanceProviders)
        try container.encode(allowEnvironmentCredentials, forKey: .allowEnvironmentCredentials)
        try container.encode(autoImportFromBrowserOnFailure, forKey: .autoImportFromBrowserOnFailure)
    }
}

// MARK: - Consumption rate

/// Estimated consumption rate derived from historical usage snapshots.
public struct ConsumptionRate: Codable, Hashable, Sendable {
    /// Percentage points per hour (e.g. 2.3 = 2.3%/h).
    public let perHour: Double
    /// Percentage points per day (e.g. 15.2 = 15.2%/d).
    public let perDay: Double
    /// Confidence score 0…1 — higher means more data points.
    public let confidence: Double

    public init(perHour: Double = 0, perDay: Double = 0, confidence: Double = 0) {
        self.perHour = perHour
        self.perDay = perDay
        self.confidence = confidence
    }
}

// MARK: - Quota window

/// A single time-based quota window (e.g. 5-hour rolling, weekly, monthly).
public struct BalanceQuotaWindow: Codable, Hashable, Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let usedRatio: Double?
    public let remainingRatio: Double?
    public let resetAt: Date?
    public let windowSeconds: Int?
    /// Estimated consumption rate (nil until enough samples are collected).
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

// MARK: - Sort order

/// Controls how balance snapshot cards are ordered in the UI.
public enum BalanceSortOrder: String, Codable, CaseIterable, Sendable {
    case quotaFirst    // 余量（quota/usage）类型优先
    case balanceFirst  // 余额（balance/cost）类型优先
    case byProvider    // 按 provider 固定顺序

    public var displayName: String {
        switch self {
        case .quotaFirst: return "余量优先"
        case .balanceFirst: return "余额优先"
        case .byProvider: return "Provider 排序"
        }
    }
}

// MARK: - Display mode

/// Controls whether progress bars show used or remaining ratios.
public enum BalanceDisplayMode: String, Codable, CaseIterable, Sendable {
    case used      // 显示已使用
    case remaining // 显示剩余

    public var displayName: String {
        switch self {
        case .used: return "已使用"
        case .remaining: return "剩余"
        }
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
    /// User-actionable recovery suggestion when unavailable.
    public let errorRecoveryHint: String?
    /// Whether re-importing credentials from browser is the recommended fix.
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

    // MARK: - Type classification helpers

    /// Whether this snapshot represents quota/usage tracking (has progress bars).
    public var isQuotaType: Bool {
        quotaWindows != nil || usagePercent != nil
    }

    /// Whether this snapshot represents monetary balance tracking.
    public var isBalanceType: Bool {
        valueEntries != nil || totalCostUSD != nil
    }
}
