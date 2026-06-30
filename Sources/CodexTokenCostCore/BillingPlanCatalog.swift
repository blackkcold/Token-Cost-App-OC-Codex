import Foundation

public enum BillingProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case opencode
    case codex
    case minimax
    case xiaomiMimo = "xiaomi-mimo"
    case deepseek

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .opencode: return "OpenCode"
        case .codex: return "Codex / ChatGPT"
        case .minimax: return "MiniMax"
        case .xiaomiMimo: return "Xiaomi MiMo"
        case .deepseek: return "DeepSeek"
        }
    }

    public var legacySubscriptionKey: String {
        switch self {
        case .opencode: return "opencode-go"
        case .codex: return "openai"
        case .minimax: return "minimax-cn-coding-plan"
        case .xiaomiMimo: return "xiaomi-token-plan-cn"
        case .deepseek: return "deepseek-api-cn"
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

public struct BillingPlanSelection: Codable, Equatable, Sendable {
    public var mode: BillingSelectionMode
    public var presetID: String
    public var customMonthlyUSD: Double?
    public var isSubscribed: Bool

    public init(
        mode: BillingSelectionMode = .preset,
        presetID: String,
        customMonthlyUSD: Double? = nil,
        isSubscribed: Bool = true
    ) {
        self.mode = mode
        self.presetID = presetID
        self.customMonthlyUSD = customMonthlyUSD
        self.isSubscribed = isSubscribed
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case presetID = "presetId"
        case customMonthlyUSD = "customMonthlyUsd"
        case isSubscribed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = try container.decode(BillingSelectionMode.self, forKey: .mode)
        self.presetID = try container.decode(String.self, forKey: .presetID)
        self.customMonthlyUSD = try container.decodeIfPresent(Double.self, forKey: .customMonthlyUSD)
        self.isSubscribed = try container.decodeIfPresent(Bool.self, forKey: .isSubscribed) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(presetID, forKey: .presetID)
        try container.encodeIfPresent(customMonthlyUSD, forKey: .customMonthlyUSD)
        try container.encode(isSubscribed, forKey: .isSubscribed)
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
}
