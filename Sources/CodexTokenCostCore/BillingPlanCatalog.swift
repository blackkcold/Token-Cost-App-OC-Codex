import Foundation

public enum BillingProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case opencode
    case codex
    case minimax
    case xiaomiMimo = "xiaomi-mimo"
    case deepseek
    case ollama

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .opencode: return "OpenCode"
        case .codex: return "Codex / ChatGPT"
        case .minimax: return "MiniMax"
        case .xiaomiMimo: return "Xiaomi MiMo"
        case .deepseek: return "DeepSeek"
        case .ollama: return "Ollama Cloud"
        }
    }

    public var legacySubscriptionKey: String {
        switch self {
        case .opencode: return "opencode-go"
        case .codex: return "openai"
        case .minimax: return "minimax-cn-coding-plan"
        case .xiaomiMimo: return "xiaomi-token-plan-cn"
        case .deepseek: return "deepseek-api-cn"
        case .ollama: return "ollama-cloud"
        }
    }
}

public enum BillingPlanKind: String, Codable, Sendable {
    case fixedMonthly
    case fixedAnnual
    case usageBased
    case contactSales
    case free

    public var hasFixedMonthlyCost: Bool {
        switch self {
        case .fixedMonthly, .fixedAnnual, .free:
            return true
        case .usageBased, .contactSales:
            return false
        }
    }
}

public struct BillingPlanPreset: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let provider: BillingProvider
    public let name: String
    public let kind: BillingPlanKind
    public let currencyCode: String?
    public let price: Double?
    public let displayPrice: String
    public let normalizedMonthlyUSD: Double?
    public let sourceNote: String
    public let usageNote: String

    public init(
        id: String,
        provider: BillingProvider,
        name: String,
        kind: BillingPlanKind,
        currencyCode: String?,
        price: Double?,
        displayPrice: String,
        normalizedMonthlyUSD: Double?,
        sourceNote: String,
        usageNote: String
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.kind = kind
        self.currencyCode = currencyCode
        self.price = price
        self.displayPrice = displayPrice
        self.normalizedMonthlyUSD = normalizedMonthlyUSD
        self.sourceNote = sourceNote
        self.usageNote = usageNote
    }
}

public enum BillingSelectionMode: String, Codable, Sendable {
    case preset
    case customMonthlyUSD
}

/// 订阅周期粒度：按日精确折算或按月整体计算
public enum PeriodGranularity: String, Codable, Sendable, CaseIterable {
    case day
    case month
}

/// 订阅周期快捷预设：选择后自动填充起止日期，不持久化（填充后立即置 nil）
public enum PeriodPreset: String, Codable, Sendable, CaseIterable {
    case monthly
    case quarterly
    case yearly
}

public struct BillingPlanSelection: Codable, Equatable, Sendable {
    public var mode: BillingSelectionMode
    public var presetID: String
    public var customMonthlyUSD: Double?
    public var isSubscribed: Bool
    /// 订阅周期粒度（默认 .month）
    public var periodGranularity: PeriodGranularity
    /// 订阅起始日期（nil 表示未设置，回退月费口径）
    public var periodStart: Date?
    /// 订阅结束日期（nil 表示未设置，回退月费口径）
    public var periodEnd: Date?
    /// 快捷预设（用于 UI 日期填充，持久化以支持跨会话恢复）
    public var periodPreset: PeriodPreset?
    /// 是否为此 provider 启用按周期成本跟踪（UI Toggle）。
    /// 默认 `false`；从旧数据解码时若 `periodStart` 和 `periodEnd` 均已设置，则自动为 `true`。
    public var hasPeriodTracking: Bool

    public init(
        mode: BillingSelectionMode = .preset,
        presetID: String,
        customMonthlyUSD: Double? = nil,
        isSubscribed: Bool = true,
        periodGranularity: PeriodGranularity = .month,
        periodStart: Date? = nil,
        periodEnd: Date? = nil,
        periodPreset: PeriodPreset? = nil,
        hasPeriodTracking: Bool = false
    ) {
        self.mode = mode
        self.presetID = presetID
        self.customMonthlyUSD = customMonthlyUSD
        self.isSubscribed = isSubscribed
        self.periodGranularity = periodGranularity
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.periodPreset = periodPreset
        self.hasPeriodTracking = hasPeriodTracking
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case presetID = "presetId"
        case customMonthlyUSD = "customMonthlyUsd"
        case isSubscribed
        case periodGranularity = "period_granularity"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case periodPreset = "period_preset"
        case hasPeriodTracking = "period_tracking"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = try container.decode(BillingSelectionMode.self, forKey: .mode)
        self.presetID = try container.decode(String.self, forKey: .presetID)
        self.customMonthlyUSD = try container.decodeIfPresent(Double.self, forKey: .customMonthlyUSD)
        self.isSubscribed = try container.decodeIfPresent(Bool.self, forKey: .isSubscribed) ?? true
        self.periodGranularity = try container.decodeIfPresent(PeriodGranularity.self, forKey: .periodGranularity) ?? .month
        self.periodStart = try container.decodeIfPresent(Date.self, forKey: .periodStart)
        self.periodEnd = try container.decodeIfPresent(Date.self, forKey: .periodEnd)
        self.periodPreset = try container.decodeIfPresent(PeriodPreset.self, forKey: .periodPreset)
        if let decodedTracking = try container.decodeIfPresent(Bool.self, forKey: .hasPeriodTracking) {
            self.hasPeriodTracking = decodedTracking
        } else if self.periodStart != nil, self.periodEnd != nil {
            self.hasPeriodTracking = true
        } else {
            self.hasPeriodTracking = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(presetID, forKey: .presetID)
        try container.encodeIfPresent(customMonthlyUSD, forKey: .customMonthlyUSD)
        try container.encode(isSubscribed, forKey: .isSubscribed)
        try container.encode(periodGranularity, forKey: .periodGranularity)
        try container.encodeIfPresent(periodStart, forKey: .periodStart)
        try container.encodeIfPresent(periodEnd, forKey: .periodEnd)
        try container.encodeIfPresent(periodPreset, forKey: .periodPreset)
        try container.encode(hasPeriodTracking, forKey: .hasPeriodTracking)
    }
}

public struct ResolvedBillingPlan: Equatable, Sendable {
    public var provider: BillingProvider
    public var selection: BillingPlanSelection
    public var preset: BillingPlanPreset?
    public var displayName: String
    public var priceDescription: String
    public var monthlyUSD: Double?
    public var isCustom: Bool
    public var isFixedCost: Bool
    public var isSubscribed: Bool
}

/// Single canonical result for costs across a global reporting date range.
///
/// Combines prorated fixed subscription costs and uncovered API usage costs
/// without double counting: a provider covered by a fixed subscription suppresses
/// that provider's API usage contribution.
public struct ReportingCostBreakdown: Equatable, Sendable {
    public let totalCost: Double
    /// Per-provider fixed subscription costs (prorated when period dates overlap the reporting range;
    /// full monthly USD when no period dates are set, for backward compatibility).
    public let fixedCostByProvider: [BillingProvider: Double]
    /// Uncovered API usage costs keyed by normalized provider key.
    public let uncoveredUsageByProviderKey: [String: Double]

    public var hasCost: Bool { totalCost > 0 }

    public init(
        totalCost: Double,
        fixedCostByProvider: [BillingProvider: Double] = [:],
        uncoveredUsageByProviderKey: [String: Double] = [:]
    ) {
        self.totalCost = totalCost
        self.fixedCostByProvider = fixedCostByProvider
        self.uncoveredUsageByProviderKey = uncoveredUsageByProviderKey
    }
}

public enum BillingPlanCatalog {
    public static let customOptionID = "__custom_monthly_usd"

    public static var exchangeRateUSDToCNY: Double { TokenCostCurrencyService.defaultExchangeRateUSDToCNY }

    private static let cnyToUSD: Double = 1 / exchangeRateUSDToCNY

    public static let presets: [BillingPlanPreset] = [
        BillingPlanPreset(
            id: "opencode-go",
            provider: .opencode,
            name: "OpenCode Go",
            kind: .fixedMonthly,
            currencyCode: "USD",
            price: 10,
            displayPrice: "$10/月",
            normalizedMonthlyUSD: 10,
            sourceNote: "OpenCode Go 官方页；首月 $5 仅作促销说明，不作为默认月费。",
            usageNote: "低成本 coding models 订阅。"
        ),
        BillingPlanPreset(
            id: "opencode-zen-paygo",
            provider: .opencode,
            name: "OpenCode Zen",
            kind: .usageBased,
            currencyCode: nil,
            price: nil,
            displayPrice: "按量计费",
            normalizedMonthlyUSD: nil,
            sourceNote: "OpenCode Zen 官方文档。",
            usageNote: "按 token/request 透明计费，无固定月费。"
        ),
        BillingPlanPreset(
            id: "chatgpt-plus",
            provider: .codex,
            name: "ChatGPT Plus",
            kind: .fixedMonthly,
            currencyCode: "USD",
            price: 20,
            displayPrice: "$20/月",
            normalizedMonthlyUSD: 20,
            sourceNote: "OpenAI ChatGPT pricing。",
            usageNote: "含扩展 Codex 使用量。"
        ),
        BillingPlanPreset(
            id: "chatgpt-pro",
            provider: .codex,
            name: "ChatGPT Pro",
            kind: .fixedMonthly,
            currencyCode: "USD",
            price: 200,
            displayPrice: "$200/月",
            normalizedMonthlyUSD: 200,
            sourceNote: "OpenAI ChatGPT pricing。",
            usageNote: "面向重度使用；Codex usage 较 Plus 更高。"
        ),
        BillingPlanPreset(
            id: "chatgpt-business-codex-paygo",
            provider: .codex,
            name: "Business Codex",
            kind: .usageBased,
            currencyCode: nil,
            price: nil,
            displayPrice: "按量计费",
            normalizedMonthlyUSD: nil,
            sourceNote: "OpenAI ChatGPT pricing。",
            usageNote: "开发团队按量计费，无固定 seat fee。"
        ),
        BillingPlanPreset(
            id: "deepseek-api-paygo",
            provider: .deepseek,
            name: "DeepSeek API",
            kind: .usageBased,
            currencyCode: "CNY",
            price: nil,
            displayPrice: "按量计费",
            normalizedMonthlyUSD: nil,
            sourceNote: "DeepSeek API 官方定价（2026/06）。",
            usageNote: "V4-Flash: $0.14/$0.28 · V4-Pro: $0.435/$0.87/M tokens"
        ),
        ollama(id: "ollama-free", name: "Ollama Free", price: 0, usage: "本地运行 + 轻量云端用量；单模型并发"),
        ollama(id: "ollama-pro", name: "Ollama Pro", price: 20, usage: "50x Free 云端用量；3 模型并发；$200/年"),
        ollama(id: "ollama-max", name: "Ollama Max", price: 100, usage: "5x Pro 云端用量；10 模型并发"),
        minimax(id: "minimax-starter-monthly", name: "Starter 标准版", cny: 29, usage: "M2.7 600 次请求/5小时"),
        minimax(id: "minimax-plus-monthly", name: "Plus 标准版", cny: 49, usage: "M2.7 1,500 次请求/5小时"),
        minimax(id: "minimax-max-monthly", name: "Max 标准版", cny: 119, usage: "M2.7 4,500 次请求/5小时"),
        minimax(id: "minimax-plus-speed-monthly", name: "Plus 极速版", cny: 98, usage: "M2.7-highspeed 1,500 次请求/5小时"),
        minimax(id: "minimax-max-speed-monthly", name: "Max 极速版", cny: 199, usage: "M2.7-highspeed 4,500 次请求/5小时"),
        minimax(id: "minimax-ultra-speed-monthly", name: "Ultra 极速版", cny: 899, usage: "M2.7-highspeed 30,000 次请求/5小时"),
        mimo(id: "mimo-current-default", name: "当前默认费用", cny: 34.9, usd: nil, credits: "保持现有 App 默认费用"),
        mimo(id: "mimo-lite-cn-monthly", name: "Lite 中国区", cny: 39, usd: nil, credits: "4.1B credits/月；入门探索"),
        mimo(id: "mimo-standard-cn-monthly", name: "Standard 中国区", cny: 99, usd: nil, credits: "11B credits/月；日常使用"),
        mimo(id: "mimo-pro-cn-monthly", name: "Pro 中国区", cny: 329, usd: nil, credits: "38B credits/月；专业工作流"),
        mimo(id: "mimo-max-cn-monthly", name: "Max 中国区", cny: 659, usd: nil, credits: "82B credits/月；高频重度使用"),
        mimo(id: "mimo-lite-global-monthly", name: "Lite 海外", cny: nil, usd: 6, credits: "4.1B credits/月；入门探索"),
        mimo(id: "mimo-standard-global-monthly", name: "Standard 海外", cny: nil, usd: 16, credits: "11B credits/月；日常使用"),
        mimo(id: "mimo-pro-global-monthly", name: "Pro 海外", cny: nil, usd: 50, credits: "38B credits/月；专业工作流"),
        mimo(id: "mimo-max-global-monthly", name: "Max 海外", cny: nil, usd: 100, credits: "82B credits/月；高频重度使用"),
        mimoAnnualCN(id: "mimo-lite-cn-annual", name: "Lite 中国区年付", cnyAnnual: 411.84, credits: "49.2B credits/年"),
        mimoAnnualCN(id: "mimo-standard-cn-annual", name: "Standard 中国区年付", cnyAnnual: 1045.44, credits: "132B credits/年"),
        mimoAnnualCN(id: "mimo-pro-cn-annual", name: "Pro 中国区年付", cnyAnnual: 3474.24, credits: "456B credits/年"),
        mimoAnnualCN(id: "mimo-max-cn-annual", name: "Max 中国区年付", cnyAnnual: 6959.04, credits: "984B credits/年"),
        mimoAnnual(id: "mimo-lite-global-annual", name: "Lite 海外年付", usdAnnual: 63.36, credits: "49.2B credits/年"),
        mimoAnnual(id: "mimo-standard-global-annual", name: "Standard 海外年付", usdAnnual: 168.96, credits: "132B credits/年"),
        mimoAnnual(id: "mimo-pro-global-annual", name: "Pro 海外年付", usdAnnual: 528, credits: "456B credits/年"),
        mimoAnnual(id: "mimo-max-global-annual", name: "Max 海外年付", usdAnnual: 1056, credits: "984B credits/年")
    ]

    public static func presets(for provider: BillingProvider) -> [BillingPlanPreset] {
        presets.filter { $0.provider == provider }
    }

    public static func subscriptionPresets(for provider: BillingProvider) -> [BillingPlanPreset] {
        presets(for: provider).filter { isSubscriptionPreset($0) }
    }

    public static func preset(id: String) -> BillingPlanPreset? {
        let normalized = normalize(id)
        return presets.first { normalize($0.id) == normalized }
    }

    public static func isSubscriptionPresetID(_ presetID: String) -> Bool {
        guard let preset = preset(id: presetID) else { return false }
        return isSubscriptionPreset(preset)
    }

    public static func defaultSelection(for provider: BillingProvider) -> BillingPlanSelection {
        switch provider {
        case .opencode:
            return BillingPlanSelection(presetID: "opencode-go")
        case .codex:
            return BillingPlanSelection(presetID: "chatgpt-plus")
        case .minimax:
            return BillingPlanSelection(presetID: "minimax-plus-speed-monthly")
        case .xiaomiMimo:
            return BillingPlanSelection(presetID: "mimo-current-default")
        case .deepseek:
            return BillingPlanSelection(presetID: "deepseek-api-paygo", isSubscribed: false)
        case .ollama:
            return BillingPlanSelection(presetID: "ollama-free", isSubscribed: false)
        }
    }

    public static func defaultSubscriptionSelection(for provider: BillingProvider) -> BillingPlanSelection {
        let defaultSelection = defaultSelection(for: provider)
        if isSubscriptionPresetID(defaultSelection.presetID) {
            return defaultSelection
        }
        guard let preset = subscriptionPresets(for: provider).first else {
            return defaultSelection
        }
        return BillingPlanSelection(presetID: preset.id)
    }

    public static func provider(forLegacyProviderKey providerKey: String) -> BillingProvider? {
        let normalized = normalize(providerKey)
        return BillingProvider.allCases.first { normalize($0.legacySubscriptionKey) == normalized }
    }

    public static func resolve(provider: BillingProvider, selection: BillingPlanSelection?) -> ResolvedBillingPlan {
        var effectiveSelection = selection ?? defaultSelection(for: provider)
        if effectiveSelection.isSubscribed,
           effectiveSelection.mode == .preset,
           !isSubscriptionPresetID(effectiveSelection.presetID) {
            effectiveSelection = defaultSubscriptionSelection(for: provider)
        }
        let fallbackSelection = effectiveSelection.isSubscribed
            ? defaultSubscriptionSelection(for: provider)
            : defaultSelection(for: provider)
        let preset = preset(id: effectiveSelection.presetID) ?? preset(id: fallbackSelection.presetID)

        guard effectiveSelection.isSubscribed else {
            return ResolvedBillingPlan(
                provider: provider,
                selection: effectiveSelection,
                preset: preset,
                displayName: AppLocalization.text("settings.billing.notSubscribed"),
                priceDescription: AppLocalization.text("settings.billing.notSubscribedDescription"),
                monthlyUSD: nil,
                isCustom: false,
                isFixedCost: false,
                isSubscribed: false
            )
        }

        if effectiveSelection.mode == .customMonthlyUSD,
           let custom = effectiveSelection.customMonthlyUSD,
           isValidCustomCost(custom) {
            return ResolvedBillingPlan(
                provider: provider,
                selection: effectiveSelection,
                preset: preset,
                displayName: AppLocalization.text("overview.plan.custom"),
                priceDescription: formatUSD(custom) + "/月",
                monthlyUSD: custom,
                isCustom: true,
                isFixedCost: true,
                isSubscribed: true
            )
        }

        guard let preset else {
            return ResolvedBillingPlan(
                provider: provider,
                selection: defaultSelection(for: provider),
                preset: nil,
                displayName: provider.displayName,
                priceDescription: "未配置",
                monthlyUSD: nil,
                isCustom: false,
                isFixedCost: false,
                isSubscribed: false
            )
        }

        return ResolvedBillingPlan(
            provider: provider,
            selection: effectiveSelection,
            preset: preset,
            displayName: preset.name,
            priceDescription: preset.displayPrice,
            monthlyUSD: preset.normalizedMonthlyUSD,
            isCustom: false,
            isFixedCost: preset.kind.hasFixedMonthlyCost,
            isSubscribed: true
        )
    }

    public static func isValidCustomCost(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }

    public static func formatUSD(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    public static func formatRMB(_ value: Double) -> String {
        "¥" + trim(value)
    }

    public static func formatCurrency(_ usdAmount: Double, displayCurrency: DisplayCurrency) -> String {
        let converted = TokenCostCurrencyService.convert(usdAmount, from: .usd, to: displayCurrency)
        return TokenCostCurrencyService.format(converted, currency: displayCurrency)
    }

    private static func minimax(id: String, name: String, cny: Double, usage: String) -> BillingPlanPreset {
        BillingPlanPreset(
            id: id,
            provider: .minimax,
            name: name,
            kind: .fixedMonthly,
            currencyCode: "CNY",
            price: cny,
            displayPrice: "¥\(trim(cny))/月",
            normalizedMonthlyUSD: cny * cnyToUSD,
            sourceNote: "MiniMax Token Plan 官方文档。",
            usageNote: usage
        )
    }

    private static func ollama(id: String, name: String, price: Double, usage: String) -> BillingPlanPreset {
        BillingPlanPreset(
            id: id,
            provider: .ollama,
            name: name,
            kind: .fixedMonthly,
            currencyCode: "USD",
            price: price,
            displayPrice: price == 0 ? "免费" : "$\(trim(price))/月",
            normalizedMonthlyUSD: price,
            sourceNote: "Ollama 官方定价页（2026/07）。",
            usageNote: usage
        )
    }

    private static func mimo(id: String, name: String, cny: Double?, usd: Double?, credits: String) -> BillingPlanPreset {
        let price = usd ?? cny
        let currency = usd == nil ? "CNY" : "USD"
        let display = usd.map { "$\(trim($0))/月" } ?? cny.map { "¥\(trim($0))/月" } ?? "未提供"
        let normalized = usd ?? cny.map { $0 * cnyToUSD }
        return BillingPlanPreset(
            id: id,
            provider: .xiaomiMimo,
            name: name,
            kind: .fixedMonthly,
            currencyCode: currency,
            price: price,
            displayPrice: display,
            normalizedMonthlyUSD: normalized,
            sourceNote: "Xiaomi MiMo Token Plan 官方页与官宣转载交叉核对。",
            usageNote: credits
        )
    }

    private static func mimoAnnual(id: String, name: String, usdAnnual: Double, credits: String) -> BillingPlanPreset {
        BillingPlanPreset(
            id: id,
            provider: .xiaomiMimo,
            name: name,
            kind: .fixedAnnual,
            currencyCode: "USD",
            price: usdAnnual,
            displayPrice: "$\(trim(usdAnnual))/年",
            normalizedMonthlyUSD: usdAnnual / 12,
            sourceNote: "Xiaomi MiMo Token Plan 官方页。",
            usageNote: credits
        )
    }

    private static func mimoAnnualCN(id: String, name: String, cnyAnnual: Double, credits: String) -> BillingPlanPreset {
        BillingPlanPreset(
            id: id,
            provider: .xiaomiMimo,
            name: name,
            kind: .fixedAnnual,
            currencyCode: "CNY",
            price: cnyAnnual,
            displayPrice: "¥\(trim(cnyAnnual))/年",
            normalizedMonthlyUSD: cnyAnnual * cnyToUSD / 12,
            sourceNote: "Xiaomi MiMo Token Plan 官方页。",
            usageNote: credits
        )
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSubscriptionPreset(_ preset: BillingPlanPreset) -> Bool {
        preset.kind == .fixedMonthly || preset.kind == .fixedAnnual
    }

    private static func trim(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

public extension AppPreferences {
    func billingSelection(for provider: BillingProvider) -> BillingPlanSelection {
        billingSelectionsByProvider[provider.rawValue] ?? BillingPlanCatalog.defaultSelection(for: provider)
    }

    mutating func setBillingSelection(_ selection: BillingPlanSelection, for provider: BillingProvider) {
        billingSelectionsByProvider[provider.rawValue] = selection
    }

    func resolvedBillingPlan(for provider: BillingProvider) -> ResolvedBillingPlan {
        BillingPlanCatalog.resolve(provider: provider, selection: billingSelection(for: provider))
    }

    /// Returns billing overrides for all 5 providers.
    ///
    /// Each provider is resolved independently:
    /// - subscribed with a fixed monthly cost → override = that monthly USD
    /// - not subscribed or usage-based (nil monthlyUSD) → no override
    ///   (analytics falls back to API/raw/synthetic cost)
    func billingOverridesByProviderKey() -> [String: Double] {
        var overrides: [String: Double] = [:]
        for provider in BillingProvider.allCases {
            let resolved = resolvedBillingPlan(for: provider)
            guard resolved.isSubscribed,
                  resolved.isFixedCost,
                  let monthlyUSD = resolved.monthlyUSD,
                  monthlyUSD > 0
            else {
                continue
            }
            overrides[provider.legacySubscriptionKey] = monthlyUSD
            overrides[provider.rawValue] = monthlyUSD
        }
        return overrides
    }

    /// Computes the OpenCode cost for the total overview card.
    /// Fixed monthly subscription takes priority; otherwise falls back to API usage cost.
    func openCodeOverviewCost(payload: DashboardPayload) -> Double? {
        let resolved = resolvedBillingPlan(for: .opencode)
        if resolved.isSubscribed, resolved.isFixedCost,
           let monthlyUSD = resolved.monthlyUSD, monthlyUSD > 0 {
            return monthlyUSD
        }
        let usageCosts = TokenCostDashboardAnalytics.providerUsageCosts(payload: payload)
        for (key, (raw, synthetic)) in usageCosts {
            let normalized = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized == "opencode-go" || normalized == "opencode" else { continue }
            let cost = synthetic > 0 ? synthetic : raw
            if cost > 0 { return cost }
        }
        return nil
    }

    func nonCodexMonthlyCost(payload: DashboardPayload) -> Double? {
        guard let combined = combinedMonthlyCost(payload: payload) else { return nil }
        let codexCost: Double
        let resolved = resolvedBillingPlan(for: .codex)
        if resolved.isSubscribed,
           resolved.isFixedCost,
           let monthlyUSD = resolved.monthlyUSD,
           monthlyUSD > 0 {
            codexCost = monthlyUSD
        } else {
            codexCost = 0
        }
        let cost = combined - codexCost
        return cost > 0 ? cost : nil
    }

    /// Computes the combined monthly cost across OpenCode, Codex, MiniMax,
    /// Xiaomi MiMo, and DeepSeek according to the unified rule:
    ///
    ///     total = Σ enabled fixed subscriptions
    ///           + Σ API usage cost for providers not covered by a fixed subscription
    ///
    /// API usage cost for a provider is `rawCost > 0 ? rawCost : syntheticApiCost`.
    /// Legacy fallback subscription costs are NOT used — only explicit user selections.
    /// Returns nil when no provider has any cost.
    func combinedMonthlyCost(payload: DashboardPayload) -> Double? {
        var total: Double = 0
        var hasAnyCost = false
        var coveredRawKeys: Set<String> = []

        func addCost(_ cost: Double?) {
            guard let cost, cost.isFinite, cost > 0 else { return }
            total += cost
            hasAnyCost = true
        }

        for provider in BillingProvider.allCases {
            let resolved = resolvedBillingPlan(for: provider)
            guard resolved.isSubscribed,
                  resolved.isFixedCost,
                  let monthlyUSD = resolved.monthlyUSD,
                  monthlyUSD > 0
            else {
                continue
            }
            addCost(monthlyUSD)
            coveredRawKeys.insert(provider.rawValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
            coveredRawKeys.insert(provider.legacySubscriptionKey.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let usageCosts = TokenCostDashboardAnalytics.providerUsageCosts(payload: payload)
        for (rawKey, (raw, synthetic)) in usageCosts {
            let normalized = rawKey.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if coveredRawKeys.contains(normalized) { continue }
            let cost = synthetic > 0 ? synthetic : raw
            addCost(cost)
        }

        return hasAnyCost ? total : nil
    }

    /// 按订阅周期计算单个 provider 的总成本（完整周期金额）。
    ///
    /// 算法（包含式日历日：起止日期均计入）：
    /// - hasPeriodTracking=false / start/end 为 nil / start > end → 回退 monthlyUSD（月费口径）
    /// - .month 粒度：total = monthlyUSD × (months + inclusiveDays/该月总天数)
    /// - .day 粒度：total = (monthlyUSD / 30.4375) × inclusiveCalendarDays
    /// - 同一天 = 1 天（非回退）
    func periodTotalCost(for provider: BillingProvider) -> Double? {
        let resolved = resolvedBillingPlan(for: provider)
        guard resolved.isSubscribed,
              resolved.isFixedCost,
              let monthlyUSD = resolved.monthlyUSD,
              monthlyUSD > 0 else { return nil }

        let selection = billingSelection(for: provider)
        guard selection.hasPeriodTracking,
              let start = selection.periodStart,
              let end = selection.periodEnd else { return monthlyUSD }

        let calendar = Calendar.autoupdatingCurrent
        guard calendar.startOfDay(for: start) <= calendar.startOfDay(for: end) else { return monthlyUSD }

        let includedDays = Self.inclusiveCalendarDays(from: start, to: end)
        switch selection.periodGranularity {
        case .month:
            let dayStart = calendar.startOfDay(for: start)
            let dayEnd = calendar.startOfDay(for: end)
            // Compute date components from start to the day after the included end,
            // so full calendar-month cycles yield exact whole months without overcount.
            guard let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: dayEnd) else {
                // Conservative fallback when calendar arithmetic fails
                return (monthlyUSD / 30.4375) * Double(includedDays)
            }
            let components = calendar.dateComponents([.month, .day], from: dayStart, to: exclusiveEnd)
            let months = Double(components.month ?? 0)
            let days = Double(components.day ?? 0)
            let daysInEndMonth: Double
            if let endMonthRange = calendar.range(of: .day, in: .month, for: dayEnd) {
                daysInEndMonth = Double(endMonthRange.count)
            } else {
                daysInEndMonth = 30
            }
            return monthlyUSD * (months + days / daysInEndMonth)
        case .day:
            return (monthlyUSD / 30.4375) * Double(includedDays)
        }
    }

    /// 所有 provider 的订阅周期总成本之和（仅含已设置有效周期的 provider）。
    func combinedPeriodCost() -> Double? {
        var total: Double = 0
        var hasAnyCost = false
        for provider in BillingProvider.allCases {
            guard let cost = periodTotalCost(for: provider), cost > 0 else { continue }
            total += cost
            hasAnyCost = true
        }
        return hasAnyCost ? total : nil
    }

    /// 总成本：通过持久化的 `reportingRangeMode` 解析范围，委托给规范 `reportingCostBreakdown`。
    /// 仅当 payload 无法形成有效范围时回退 `combinedMonthlyCost`。
    /// `periodTotalCostEnabled` 不再影响规范总成本语义；仅作为旧字段保留以供兼容解码。
    func combinedTotalCost(payload: DashboardPayload) -> Double? {
        if let breakdown = reportingCostBreakdown(
            payload: payload,
            mode: reportingRangeMode,
            customBounds: reportingRangeCustomBounds
        ) {
            return breakdown.totalCost
        }
        return combinedMonthlyCost(payload: payload)
    }

    // MARK: - Unified Reporting-Range Cost Model

    /// Derives an inclusive whole-day reporting range from payload raw-data date strings.
    ///
    /// Returns `(startOfMinDay, endOfMaxDay)` adjusting via `Calendar.autoupdatingCurrent`,
    /// or `nil` when rawData is empty or dates are unparseable.
    static func reportingRange(from payload: DashboardPayload) -> (start: Date, end: Date)? {
        let dates = payload.rawData.compactMap { row -> Date? in
            let trimmed = row.date.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.count <= 10 {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                // No explicit timeZone: local-calendar semantics match SQLite localtime aggregation
                return formatter.date(from: trimmed)
            }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            return iso.date(from: trimmed)
        }
        guard let minDate = dates.min(), let maxDate = dates.max() else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        let dayStart = calendar.startOfDay(for: minDate)
        guard let dayEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: maxDate)) else {
            return nil
        }
        return (dayStart, dayEnd)
    }

    /// Resolves the effective reporting date range for the given mode and payload.
    ///
    /// - `.allAvailable`: full range derived from payload rawData dates (backward compat default)
    /// - `.currentMonth`: start of current calendar month → now
    /// - `.last30Days`: 30 days ago → now
    /// - `.custom`: uses `ReportingRangeCustomBounds`; falls back to `.allAvailable` when bounds are missing or invalid
    /// Returns `nil` only when the payload has no usable dates and the mode is `.allAvailable`.
    static func resolveReportingRange(
        mode: ReportingRangeMode,
        customBounds: ReportingRangeCustomBounds,
        payload: DashboardPayload
    ) -> (start: Date, end: Date)? {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()

        func dayRange(from startDate: Date, to endDate: Date) -> (start: Date, end: Date)? {
            let s = calendar.startOfDay(for: startDate)
            guard let e = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: endDate)) else {
                return nil
            }
            guard s < e else { return nil }
            return (s, e)
        }

        switch mode {
        case .allAvailable:
            return reportingRange(from: payload)

        case .currentMonth:
            guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
                return reportingRange(from: payload)
            }
            return dayRange(from: monthStart, to: now)

        case .last30Days:
            guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else {
                return reportingRange(from: payload)
            }
            return dayRange(from: thirtyDaysAgo, to: now)

        case .custom:
            guard let cs = customBounds.start,
                  let ce = customBounds.end,
                  cs < ce else {
                return reportingRange(from: payload)
            }
            return dayRange(from: cs, to: ce)
        }
    }

    /// Returns per-provider API usage costs, filtered to raw-data rows within the reporting range.
    private static func filteredProviderUsageCosts(
        payload: DashboardPayload,
        reportingStart: Date,
        reportingEnd: Date
    ) -> [String: (raw: Double, synthetic: Double)] {
        let calendar = Calendar.autoupdatingCurrent
        let dayStart = calendar.startOfDay(for: reportingStart)
        let dayEnd = calendar.startOfDay(for: reportingEnd)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let filteredRows = payload.rawData.filter { row in
            let trimmed = row.date.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            guard let rowDate = dateFormatter.date(from: trimmed) ?? {
                if trimmed.count > 10 {
                    let iso = ISO8601DateFormatter()
                    iso.formatOptions = [.withFullDate, .withDashSeparatorInDate]
                    return iso.date(from: trimmed)
                }
                return nil
            }() else { return false }
            let rowDay = calendar.startOfDay(for: rowDate)
            return rowDay >= dayStart && rowDay <= dayEnd
        }

        let filteredPayload = DashboardPayload(
            summary: payload.summary,
            dailyTotals: payload.dailyTotals,
            modelTotals: payload.modelTotals,
            providerCosts: payload.providerCosts,
            providerTotals: payload.providerTotals,
            rawData: filteredRows
        )
        return TokenCostDashboardAnalytics.providerUsageCosts(payload: filteredPayload)
    }

    /// Computes the number of whole calendar days between two dates, counting both
    /// the start and end dates as included days.
    ///
    /// Uses `Calendar.autoupdatingCurrent` for day boundaries.
    /// Returns 1 for same-day intervals; 0 only when `start > end`.
    private static func inclusiveCalendarDays(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: end)
        guard s <= e else { return 0 }
        let days = calendar.dateComponents([.day], from: s, to: e).day ?? 0
        return days + 1
    }

    /// Computes the number of whole days a subscription period overlaps with the reporting range,
    /// counting both the first and last overlapping days as included calendar days.
    ///
    /// Uses `Calendar.autoupdatingCurrent` for day boundaries.
    private static func overlappingDays(
        periodStart: Date, periodEnd: Date,
        reportingStart: Date, reportingEnd: Date
    ) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        let overlapStart = max(periodStart, reportingStart)
        let overlapEnd = min(periodEnd, reportingEnd)
        guard calendar.startOfDay(for: overlapStart) <= calendar.startOfDay(for: overlapEnd) else { return 0 }
        return Self.inclusiveCalendarDays(from: overlapStart, to: overlapEnd)
    }

    /// Single canonical cost breakdown for a global reporting date range.
    ///
    /// Phase 1: Fixed subscriptions prorated when `hasPeriodTracking` is enabled
    /// and the subscription period overlaps the reporting range (otherwise full monthly fallback).
    /// Phase 2: Uncovered API usage costs filtered to rawData rows whose date falls within
    /// the reporting range (`dayStart…dayEnd` inclusive whole-day).
    /// No double counting: a provider with a tracked fixed subscription suppresses its API usage.
    func reportingCostBreakdown(
        payload: DashboardPayload,
        reportingStart: Date,
        reportingEnd: Date
    ) -> ReportingCostBreakdown {
        var total: Double = 0
        var fixedCostByProvider: [BillingProvider: Double] = [:]
        var uncoveredUsageByProviderKey: [String: Double] = [:]
        var coveredRawKeys: Set<String> = []

        let calendar = Calendar.autoupdatingCurrent
        let reportingDayStart = calendar.startOfDay(for: reportingStart)

        func addCost(_ cost: Double) {
            guard cost.isFinite, cost > 0 else { return }
            total += cost
        }

        // Phase 1: Fixed subscriptions — canonical per-provider cycle allocation
        for provider in BillingProvider.allCases {
            let resolved = resolvedBillingPlan(for: provider)
            guard resolved.isSubscribed,
                  resolved.isFixedCost,
                  let monthlyUSD = resolved.monthlyUSD,
                  monthlyUSD > 0
            else { continue }

            let selection = billingSelection(for: provider)
            let cost: Double
            if selection.hasPeriodTracking,
               let pStart = selection.periodStart,
               let pEnd = selection.periodEnd,
               calendar.startOfDay(for: pStart) <= calendar.startOfDay(for: pEnd) {
                let cycleTotalCost = periodTotalCost(for: provider) ?? monthlyUSD
                let cycleIncludedDays = Self.inclusiveCalendarDays(from: pStart, to: pEnd)
                let overlapDays = Self.overlappingDays(
                    periodStart: pStart, periodEnd: pEnd,
                    reportingStart: reportingDayStart, reportingEnd: reportingEnd
                )
                if overlapDays > 0, cycleIncludedDays > 0 {
                    cost = cycleTotalCost * Double(overlapDays) / Double(cycleIncludedDays)
                } else {
                    cost = 0
                }
            } else {
                cost = monthlyUSD
            }
            addCost(cost)
            if cost > 0 {
                fixedCostByProvider[provider] = cost
                coveredRawKeys.insert(provider.rawValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
                coveredRawKeys.insert(provider.legacySubscriptionKey.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        // Phase 2: Uncovered API usage (filtered to reporting range)
        let usageCosts = Self.filteredProviderUsageCosts(
            payload: payload,
            reportingStart: reportingDayStart,
            reportingEnd: reportingEnd
        )
        for (rawKey, (raw, synthetic)) in usageCosts {
            let normalized = rawKey.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !coveredRawKeys.contains(normalized) else { continue }
            let cost = synthetic > 0 ? synthetic : raw
            guard cost.isFinite, cost > 0 else { continue }
            total += cost
            uncoveredUsageByProviderKey[rawKey] = cost
        }

        return ReportingCostBreakdown(
            totalCost: total,
            fixedCostByProvider: fixedCostByProvider,
            uncoveredUsageByProviderKey: uncoveredUsageByProviderKey
        )
    }

    /// Convenience wrapper that resolves the reporting range from the persisted mode
    /// and custom bounds, then delegates to `reportingCostBreakdown(payload:reportingStart:reportingEnd:)`.
    func reportingCostBreakdown(
        payload: DashboardPayload,
        mode: ReportingRangeMode,
        customBounds: ReportingRangeCustomBounds = ReportingRangeCustomBounds()
    ) -> ReportingCostBreakdown? {
        guard let range = Self.resolveReportingRange(
            mode: mode, customBounds: customBounds, payload: payload
        ) else { return nil }
        return reportingCostBreakdown(
            payload: payload,
            reportingStart: range.start,
            reportingEnd: range.end
        )
    }

    /// Produces a reporting-range-filtered DashboardPayload with recalculated
    /// aggregate fields and a billing-override map derived from the canonical
    /// ReportingCostBreakdown.fixedCostByProvider for the same range.
    ///
    /// Filters `rawData` to rows whose date falls within the resolved reporting
    /// range (inclusive whole-day boundaries) and rebuilds `summary`,
    /// `dailyTotals`, `modelTotals`, `providerCosts`, and `providerTotals`
    /// from the remaining rows.
    ///
    /// The override map includes both raw provider identities and legacy
    /// subscription keys for providers that contribute fixed costs in the
    /// reporting range.
    ///
    /// - Returns: `(filteredPayload, overrides)` or `nil` when the reporting
    ///   range cannot be resolved (e.g. empty payload).
    func filteredPayloadWithReportingOverrides(
        payload: DashboardPayload,
        mode: ReportingRangeMode,
        customBounds: ReportingRangeCustomBounds = ReportingRangeCustomBounds()
    ) -> (payload: DashboardPayload, overrides: [String: Double])? {
        guard let range = Self.resolveReportingRange(
            mode: mode, customBounds: customBounds, payload: payload
        ) else { return nil }

        let calendar = Calendar.autoupdatingCurrent
        let dayStart = calendar.startOfDay(for: range.start)
        let dayEnd = calendar.startOfDay(for: range.end)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        func parseDate(_ trimmed: String) -> Date? {
            if let d = dateFormatter.date(from: trimmed) { return d }
            if trimmed.count > 10 {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withFullDate, .withDashSeparatorInDate]
                return iso.date(from: trimmed)
            }
            return nil
        }

        let filteredRows = payload.rawData.filter { row in
            let trimmed = row.date.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let rowDate = parseDate(trimmed) else { return false }
            let rowDay = calendar.startOfDay(for: rowDate)
            return rowDay >= dayStart && rowDay <= dayEnd
        }

        // Rebuild aggregate fields from filtered rows
        let sortedDates = Array(Set(filteredRows.map { $0.date })).sorted()
        var dailyTotals: [String: Double] = [:]
        var modelTotals: [String: Double] = [:]
        var providerCosts: [String: Double] = [:]
        var providerTotals: [String: DashboardPayload.ProviderTotals] = [:]

        var totalTokens: Double = 0
        var totalActualTokens: Double = 0
        var totalCacheReadTokens: Double = 0
        var totalCacheWriteTokens: Double = 0
        var totalCost: Double = 0
        var totalMessages: Int = 0

        for row in filteredRows {
            totalTokens += row.total
            let actual = row.input + row.output + row.reasoning
            totalActualTokens += actual
            totalCacheReadTokens += row.cacheRead
            totalCacheWriteTokens += row.cacheWrite
            totalCost += row.cost
            totalMessages += row.msgCount

            dailyTotals[row.date, default: 0] += row.total
            modelTotals[row.model, default: 0] += row.total
            providerCosts[row.provider, default: 0] += row.cost

            let provKey = row.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var pt = providerTotals[provKey] ?? DashboardPayload.ProviderTotals(
                input: 0, output: 0,
                cacheRead: 0, cacheWrite: 0,
                cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
                total: 0, actualTokens: 0, cost: 0, messages: 0
            )
            pt.input += row.input
            pt.output += row.output
            pt.cacheRead += row.cacheRead
            pt.cacheWrite += row.cacheWrite
            pt.cacheWriteMissingCount += row.cacheWriteMissingCount
            pt.cacheWriteReportedCount += row.cacheWriteReportedCount
            pt.total += row.total
            pt.actualTokens += actual
            pt.cost += row.cost
            pt.messages += row.msgCount
            providerTotals[provKey] = pt
        }

        let filteredPayload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: totalTokens,
                totalActualTokens: totalActualTokens,
                totalCacheReadTokens: totalCacheReadTokens,
                totalCacheWriteTokens: totalCacheWriteTokens,
                totalCacheTokens: totalCacheReadTokens + totalCacheWriteTokens,
                totalCost: totalCost,
                totalMessages: totalMessages,
                activeDays: sortedDates.count,
                dateRange: DashboardPayload.DateRange(
                    start: sortedDates.first,
                    end: sortedDates.last
                ),
                updatedAt: payload.summary.updatedAt
            ),
            dailyTotals: dailyTotals,
            modelTotals: modelTotals,
            providerCosts: providerCosts,
            providerTotals: providerTotals,
            rawData: filteredRows
        )

        let breakdown = reportingCostBreakdown(
            payload: payload,
            reportingStart: range.start,
            reportingEnd: range.end
        )

        var overrides: [String: Double] = [:]
        for (provider, cost) in breakdown.fixedCostByProvider where cost > 0 {
            overrides[provider.rawValue] = cost
            overrides[provider.legacySubscriptionKey] = cost
        }

        return (filteredPayload, overrides)
    }
}
