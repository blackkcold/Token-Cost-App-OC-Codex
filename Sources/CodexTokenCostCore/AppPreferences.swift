import Foundation

public enum DisplayCurrency: String, Codable, CaseIterable, Identifiable, Sendable {
    case usd
    case cny

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .usd: return AppLocalization.text("settings.currency.usd")
        case .cny: return AppLocalization.text("settings.currency.cny")
        }
    }

    public var symbol: String {
        switch self {
        case .usd: return "USD"
        case .cny: return "RMB"
        }
    }
}

public struct SkillsPanelPreferences: Codable, Equatable, Sendable {
    public var showSourceColumn: Bool
    public var showStateColumn: Bool
    public var showTagsColumn: Bool
    public var previewLength: Int
    public var sortBy: String

    public init(
        showSourceColumn: Bool = true,
        showStateColumn: Bool = true,
        showTagsColumn: Bool = true,
        previewLength: Int = 300,
        sortBy: String = "name"
    ) {
        self.showSourceColumn = showSourceColumn
        self.showStateColumn = showStateColumn
        self.showTagsColumn = showTagsColumn
        self.previewLength = previewLength
        self.sortBy = sortBy
    }
}

public enum MenuBarChartStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case sparkline
    case matrix

    public var id: String { rawValue }
}

public enum ReportingRangeMode: String, Codable, CaseIterable, Sendable {
    case allAvailable
    case currentMonth
    case last30Days
    case custom

    public var id: String { rawValue }
}

public struct ReportingRangeCustomBounds: Codable, Equatable, Sendable {
    public var start: Date?
    public var end: Date?

    public init(start: Date? = nil, end: Date? = nil) {
        self.start = start
        self.end = end
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var language: AppDisplayLanguage
    public var billingSelectionsByProvider: [String: BillingPlanSelection]
    public var balanceEnabled: Bool
    public var balanceRefreshSeconds: Int
    public var opencodeGoWorkspaceID: String?
    public var accentPalette: TokenCostAccentPalette
    public var appearanceMode: TokenCostAppearanceMode
    public var displayCurrency: DisplayCurrency
    public var balanceConfig: BalanceConfiguration?
    public var skillsPanel: SkillsPanelPreferences
    public var developerMode: DeveloperModePreferences
    public var backup: BackupPreferences
    public var taskClassificationEnabled: Bool
    public var optimizeEnabled: Bool
    public var multiCurrencyEnabled: Bool
    public var modelCompareEnabled: Bool
    public var balanceSortOrder: BalanceSortOrder
    public var balanceDisplayMode: BalanceDisplayMode
    public var balanceCustomOrder: [BalanceProviderKind]
    public var balanceOrderLocked: Bool
    public var balanceMenuBarExtraEnabled: Bool
    public var balanceFloatingPanelEnabled: Bool
    public var balanceFloatingPanelAlwaysOnTop: Bool
    public var balanceFloatingPanelDisplayMode: BalanceFloatingPanelDisplayMode
    public var credentialSourceMode: CredentialSourceMode
    public var periodTotalCostEnabled: Bool
    public var reportingRangeMode: ReportingRangeMode
    public var reportingRangeCustomBounds: ReportingRangeCustomBounds
    public var menuBarChartStyle: MenuBarChartStyle
    public var relayLoggingEnabled: Bool

    public init(
        language: AppDisplayLanguage = .zhHans,
        billingSelectionsByProvider: [String: BillingPlanSelection] = [:],
        balanceEnabled: Bool = false,
        balanceRefreshSeconds: Int = 300,
        opencodeGoWorkspaceID: String? = nil,
        accentPalette: TokenCostAccentPalette = .ocean,
        appearanceMode: TokenCostAppearanceMode = .system,
        displayCurrency: DisplayCurrency = .usd,
        skillsPanel: SkillsPanelPreferences = SkillsPanelPreferences(),
        developerMode: DeveloperModePreferences = DeveloperModePreferences(),
        balanceConfig: BalanceConfiguration? = nil,
        backup: BackupPreferences = BackupPreferences(),
        taskClassificationEnabled: Bool = true,
        optimizeEnabled: Bool = true,
        multiCurrencyEnabled: Bool = true,
        modelCompareEnabled: Bool = true,
        balanceSortOrder: BalanceSortOrder = .quotaFirst,
        balanceDisplayMode: BalanceDisplayMode = .used,
        balanceCustomOrder: [BalanceProviderKind] = [],
        balanceOrderLocked: Bool = true,
        balanceMenuBarExtraEnabled: Bool = false,
        balanceFloatingPanelEnabled: Bool = false,
        balanceFloatingPanelAlwaysOnTop: Bool = true,
        balanceFloatingPanelDisplayMode: BalanceFloatingPanelDisplayMode = .normal,
        credentialSourceMode: CredentialSourceMode = .autoBrowser,
        periodTotalCostEnabled: Bool = false,
        reportingRangeMode: ReportingRangeMode = .allAvailable,
        reportingRangeCustomBounds: ReportingRangeCustomBounds = ReportingRangeCustomBounds(),
        menuBarChartStyle: MenuBarChartStyle = .sparkline,
        relayLoggingEnabled: Bool = false
    ) {
        self.language = language
        self.billingSelectionsByProvider = billingSelectionsByProvider
        self.balanceEnabled = balanceEnabled
        self.balanceRefreshSeconds = balanceRefreshSeconds
        self.opencodeGoWorkspaceID = opencodeGoWorkspaceID
        self.accentPalette = accentPalette
        self.appearanceMode = appearanceMode
        self.displayCurrency = displayCurrency
        self.skillsPanel = skillsPanel
        self.developerMode = developerMode
        self.balanceConfig = balanceConfig
        self.backup = backup
        self.taskClassificationEnabled = taskClassificationEnabled
        self.optimizeEnabled = optimizeEnabled
        self.multiCurrencyEnabled = multiCurrencyEnabled
        self.modelCompareEnabled = modelCompareEnabled
        self.balanceSortOrder = balanceSortOrder
        self.balanceDisplayMode = balanceDisplayMode
        self.balanceCustomOrder = balanceCustomOrder
        self.balanceOrderLocked = balanceOrderLocked
        self.balanceMenuBarExtraEnabled = balanceMenuBarExtraEnabled
        self.balanceFloatingPanelEnabled = balanceFloatingPanelEnabled
        self.balanceFloatingPanelAlwaysOnTop = balanceFloatingPanelAlwaysOnTop
        self.balanceFloatingPanelDisplayMode = balanceFloatingPanelDisplayMode
        self.credentialSourceMode = credentialSourceMode
        self.periodTotalCostEnabled = periodTotalCostEnabled
        self.reportingRangeMode = reportingRangeMode
        self.reportingRangeCustomBounds = reportingRangeCustomBounds
        self.menuBarChartStyle = menuBarChartStyle
        self.relayLoggingEnabled = relayLoggingEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case language
        case billingSelectionsByProvider
        case balanceEnabled = "balance_enabled"
        case balanceRefreshSeconds = "balance_refresh_seconds"
        case legacyBalanceRefreshMinutes = "balance_refresh_minutes"
        case opencodeGoWorkspaceID = "opencode_go_workspace_id"
        case accentPalette = "accent_palette"
        case appearanceMode = "appearance_mode"
        case theme
        case displayCurrency
        case balanceConfig = "balance_config"
        case skillsPanel
        case developerMode
        case backup
        case taskClassificationEnabled = "task_classification_enabled"
        case optimizeEnabled = "optimize_enabled"
        case multiCurrencyEnabled = "multi_currency_enabled"
        case modelCompareEnabled = "model_compare_enabled"
        case balanceSortOrder = "balance_sort_order"
        case balanceDisplayMode = "balance_display_mode"
        case balanceCustomOrder = "balance_custom_order"
        case balanceOrderLocked = "balance_order_locked"
        case balanceMenuBarExtraEnabled = "balance_menu_bar_extra_enabled"
        case balanceFloatingPanelEnabled = "balance_floating_panel_enabled"
        case balanceFloatingPanelAlwaysOnTop = "balance_floating_panel_always_on_top"
        case balanceFloatingPanelDisplayMode = "balance_floating_panel_display_mode"
        case credentialSourceMode = "credential_source_mode"
        case periodTotalCostEnabled = "period_total_cost_enabled"
        case reportingRangeMode = "reporting_range_mode"
        case reportingRangeCustomBounds = "reporting_range_custom_bounds"
        case menuBarChartStyle = "menu_bar_chart_style"
        case relayLoggingEnabled = "relay_logging_enabled"
    }

    private enum DecodingKeys: String, CodingKey {
        case language
        case billingSelectionsByProvider
        case balanceEnabled
        case balanceRefreshSeconds
        case legacyBalanceRefreshMinutes = "balanceRefreshMinutes"
        case opencodeGoWorkspaceID = "opencodeGoWorkspaceId"
        case accentPalette
        case appearanceMode
        case theme
        case displayCurrency
        case balanceConfig
        case skillsPanel
        case developerMode
        case backup
        case taskClassificationEnabled
        case optimizeEnabled
        case multiCurrencyEnabled
        case modelCompareEnabled
        case balanceSortOrder
        case balanceDisplayMode
        case balanceCustomOrder
        case balanceOrderLocked
        case balanceMenuBarExtraEnabled
        case balanceFloatingPanelEnabled
        case balanceFloatingPanelAlwaysOnTop
        case balanceFloatingPanelDisplayMode
        case credentialSourceMode
        case periodTotalCostEnabled
        case reportingRangeMode
        case reportingRangeCustomBounds
        case menuBarChartStyle
        case relayLoggingEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)
        let legacyContainer = try? decoder.container(keyedBy: CodingKeys.self)
        self.language = try container.decodeIfPresent(AppDisplayLanguage.self, forKey: .language) ?? .zhHans

        if let selections = try container.decodeIfPresent([String: BillingPlanSelection].self, forKey: .billingSelectionsByProvider) {
            self.billingSelectionsByProvider = selections
        } else if let legacyCosts = try container.decodeIfPresent([String: Double].self, forKey: .billingSelectionsByProvider) {
            self.billingSelectionsByProvider = legacyCosts.reduce(into: [:]) { partialResult, item in
                guard let provider = BillingProvider(rawValue: item.key), BillingPlanCatalog.isValidCustomCost(item.value) else {
                    return
                }
                partialResult[provider.rawValue] = BillingPlanSelection(
                    mode: .customMonthlyUSD,
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    customMonthlyUSD: item.value
                )
            }
        } else {
            self.billingSelectionsByProvider = [:]
        }

        self.balanceEnabled = try container.decodeIfPresent(Bool.self, forKey: .balanceEnabled)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .balanceEnabled)
            ?? false
        if let raw = try container.decodeIfPresent(Int.self, forKey: .balanceRefreshSeconds) {
            self.balanceRefreshSeconds = raw
        } else if let raw = try legacyContainer?.decodeIfPresent(Int.self, forKey: .balanceRefreshSeconds) {
            self.balanceRefreshSeconds = raw
        } else if let oldValue = try container.decodeIfPresent(Int.self, forKey: .legacyBalanceRefreshMinutes) {
            self.balanceRefreshSeconds = oldValue < 120 ? oldValue * 60 : oldValue
        } else if let oldValue = try legacyContainer?.decodeIfPresent(Int.self, forKey: .legacyBalanceRefreshMinutes) {
            self.balanceRefreshSeconds = oldValue < 120 ? oldValue * 60 : oldValue
        } else {
            self.balanceRefreshSeconds = 300
        }
        self.opencodeGoWorkspaceID = try container.decodeIfPresent(String.self, forKey: .opencodeGoWorkspaceID)
            ?? legacyContainer?.decodeIfPresent(String.self, forKey: .opencodeGoWorkspaceID)
        let legacyTheme = try container.decodeIfPresent(TokenCostThemeChoice.self, forKey: .theme)
            ?? legacyContainer?.decodeIfPresent(TokenCostThemeChoice.self, forKey: .theme)
        self.accentPalette = try container.decodeIfPresent(TokenCostAccentPalette.self, forKey: .accentPalette)
            ?? legacyContainer?.decodeIfPresent(TokenCostAccentPalette.self, forKey: .accentPalette)
            ?? legacyTheme?.accentPalette
            ?? .ocean
        self.appearanceMode = try container.decodeIfPresent(TokenCostAppearanceMode.self, forKey: .appearanceMode)
            ?? legacyContainer?.decodeIfPresent(TokenCostAppearanceMode.self, forKey: .appearanceMode)
            ?? legacyTheme?.appearanceMode
            ?? .system
        self.displayCurrency = try container.decodeIfPresent(DisplayCurrency.self, forKey: .displayCurrency) ?? .usd
        self.skillsPanel = try container.decodeIfPresent(SkillsPanelPreferences.self, forKey: .skillsPanel) ?? SkillsPanelPreferences()
        self.developerMode = try container.decodeIfPresent(DeveloperModePreferences.self, forKey: .developerMode)
            ?? legacyContainer?.decodeIfPresent(DeveloperModePreferences.self, forKey: .developerMode)
            ?? DeveloperModePreferences()
        self.balanceConfig = try container.decodeIfPresent(BalanceConfiguration.self, forKey: .balanceConfig)
            ?? legacyContainer?.decodeIfPresent(BalanceConfiguration.self, forKey: .balanceConfig)
        self.backup = try container.decodeIfPresent(BackupPreferences.self, forKey: .backup)
            ?? legacyContainer?.decodeIfPresent(BackupPreferences.self, forKey: .backup)
            ?? BackupPreferences()
        self.taskClassificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .taskClassificationEnabled)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .taskClassificationEnabled)
            ?? true
        self.optimizeEnabled = try container.decodeIfPresent(Bool.self, forKey: .optimizeEnabled)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .optimizeEnabled)
            ?? true
        self.multiCurrencyEnabled = try container.decodeIfPresent(Bool.self, forKey: .multiCurrencyEnabled)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .multiCurrencyEnabled)
            ?? true
        self.modelCompareEnabled = try container.decodeIfPresent(Bool.self, forKey: .modelCompareEnabled)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .modelCompareEnabled)
            ?? true
        self.balanceSortOrder = try container.decodeIfPresent(BalanceSortOrder.self, forKey: .balanceSortOrder)
            ?? legacyContainer?.decodeIfPresent(BalanceSortOrder.self, forKey: .balanceSortOrder)
            ?? .quotaFirst
        self.balanceDisplayMode = try container.decodeIfPresent(BalanceDisplayMode.self, forKey: .balanceDisplayMode)
            ?? legacyContainer?.decodeIfPresent(BalanceDisplayMode.self, forKey: .balanceDisplayMode)
            ?? .used
        self.balanceCustomOrder = try container.decodeIfPresent([BalanceProviderKind].self, forKey: .balanceCustomOrder)
            ?? legacyContainer?.decodeIfPresent([BalanceProviderKind].self, forKey: .balanceCustomOrder)
            ?? []
        self.balanceOrderLocked = try container.decodeIfPresent(Bool.self, forKey: .balanceOrderLocked)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .balanceOrderLocked)
            ?? true
        self.balanceMenuBarExtraEnabled = try container.decodeIfPresent(Bool.self, forKey: .balanceMenuBarExtraEnabled)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .balanceMenuBarExtraEnabled)
            ?? false
        self.balanceFloatingPanelEnabled = try container.decodeIfPresent(Bool.self, forKey: .balanceFloatingPanelEnabled)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .balanceFloatingPanelEnabled)
            ?? false
        self.balanceFloatingPanelAlwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .balanceFloatingPanelAlwaysOnTop)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .balanceFloatingPanelAlwaysOnTop)
            ?? true
        self.balanceFloatingPanelDisplayMode = try container.decodeIfPresent(BalanceFloatingPanelDisplayMode.self, forKey: .balanceFloatingPanelDisplayMode)
            ?? legacyContainer?.decodeIfPresent(BalanceFloatingPanelDisplayMode.self, forKey: .balanceFloatingPanelDisplayMode)
            ?? .normal
        self.credentialSourceMode = try container.decodeIfPresent(CredentialSourceMode.self, forKey: .credentialSourceMode)
            ?? legacyContainer?.decodeIfPresent(CredentialSourceMode.self, forKey: .credentialSourceMode)
            ?? .autoBrowser
        self.periodTotalCostEnabled = try container.decodeIfPresent(Bool.self, forKey: .periodTotalCostEnabled)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .periodTotalCostEnabled)
            ?? false
        self.reportingRangeMode = try container.decodeIfPresent(ReportingRangeMode.self, forKey: .reportingRangeMode)
            ?? legacyContainer?.decodeIfPresent(ReportingRangeMode.self, forKey: .reportingRangeMode)
            ?? .allAvailable
        self.reportingRangeCustomBounds = try container.decodeIfPresent(ReportingRangeCustomBounds.self, forKey: .reportingRangeCustomBounds)
            ?? legacyContainer?.decodeIfPresent(ReportingRangeCustomBounds.self, forKey: .reportingRangeCustomBounds)
            ?? ReportingRangeCustomBounds()
        self.menuBarChartStyle = try container.decodeIfPresent(MenuBarChartStyle.self, forKey: .menuBarChartStyle)
            ?? legacyContainer?.decodeIfPresent(MenuBarChartStyle.self, forKey: .menuBarChartStyle)
            ?? .sparkline
        self.relayLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .relayLoggingEnabled)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .relayLoggingEnabled)
            ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(language, forKey: .language)
        try container.encode(billingSelectionsByProvider, forKey: .billingSelectionsByProvider)
        try container.encode(balanceEnabled, forKey: .balanceEnabled)
        try container.encode(balanceRefreshSeconds, forKey: .balanceRefreshSeconds)
        try container.encodeIfPresent(opencodeGoWorkspaceID, forKey: .opencodeGoWorkspaceID)
        try container.encode(accentPalette, forKey: .accentPalette)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        try container.encode(displayCurrency, forKey: .displayCurrency)
        try container.encode(skillsPanel, forKey: .skillsPanel)
        try container.encode(developerMode, forKey: .developerMode)
        try container.encodeIfPresent(balanceConfig, forKey: .balanceConfig)
        try container.encode(backup, forKey: .backup)
        try container.encode(taskClassificationEnabled, forKey: .taskClassificationEnabled)
        try container.encode(optimizeEnabled, forKey: .optimizeEnabled)
        try container.encode(multiCurrencyEnabled, forKey: .multiCurrencyEnabled)
        try container.encode(modelCompareEnabled, forKey: .modelCompareEnabled)
        try container.encode(balanceSortOrder, forKey: .balanceSortOrder)
        try container.encode(balanceDisplayMode, forKey: .balanceDisplayMode)
        try container.encode(balanceCustomOrder, forKey: .balanceCustomOrder)
        try container.encode(balanceOrderLocked, forKey: .balanceOrderLocked)
        try container.encode(balanceMenuBarExtraEnabled, forKey: .balanceMenuBarExtraEnabled)
        try container.encode(balanceFloatingPanelEnabled, forKey: .balanceFloatingPanelEnabled)
        try container.encode(balanceFloatingPanelAlwaysOnTop, forKey: .balanceFloatingPanelAlwaysOnTop)
        try container.encode(balanceFloatingPanelDisplayMode, forKey: .balanceFloatingPanelDisplayMode)
        try container.encode(credentialSourceMode, forKey: .credentialSourceMode)
        try container.encode(periodTotalCostEnabled, forKey: .periodTotalCostEnabled)
        try container.encode(reportingRangeMode, forKey: .reportingRangeMode)
        try container.encode(reportingRangeCustomBounds, forKey: .reportingRangeCustomBounds)
        try container.encode(menuBarChartStyle, forKey: .menuBarChartStyle)
        try container.encode(relayLoggingEnabled, forKey: .relayLoggingEnabled)
    }

    /// Returns a copy of preferences with the given balanceConfig applied.
    public func with(balanceConfig: BalanceConfiguration?) -> AppPreferences {
        var copy = self
        copy.balanceConfig = balanceConfig
        return copy
    }
}

public struct AppPreferencesLoadResult {
    public var preferences: AppPreferences
    public var didFallbackToDefaults: Bool
    public var errorMessage: String?

    public init(preferences: AppPreferences, didFallbackToDefaults: Bool, errorMessage: String? = nil) {
        self.preferences = preferences
        self.didFallbackToDefaults = didFallbackToDefaults
        self.errorMessage = errorMessage
    }
}

public final class AppPreferencesStore {
    private let fileStore: SafeFileStore
    private let preferencesRelativePath: String
    private let defaultPreferences: () -> AppPreferences

    public init(
        runtimeRoot: URL = TokenCostPaths.runtimeRoot,
        preferencesRelativePath: String = "config/app-preferences.json",
        defaultPreferences: @escaping () -> AppPreferences = { AppPreferences() }
    ) {
        self.fileStore = SafeFileStore(root: runtimeRoot)
        self.preferencesRelativePath = preferencesRelativePath
        self.defaultPreferences = defaultPreferences
    }

    public func load() -> AppPreferencesLoadResult {
        do {
            let preferences = try fileStore.readCodable(AppPreferences.self, from: preferencesRelativePath)
            return AppPreferencesLoadResult(preferences: preferences, didFallbackToDefaults: false)
        } catch {
            return AppPreferencesLoadResult(
                preferences: defaultPreferences(),
                didFallbackToDefaults: true,
                errorMessage: error.localizedDescription
            )
        }
    }

    public func save(_ preferences: AppPreferences) throws {
        try SettingsBackupRotation.backupIfPresent(
            fileStore: fileStore,
            relativePath: preferencesRelativePath,
            backupDirectory: "config/backups/app-preferences"
        )
        try fileStore.writeCodable(preferences, to: preferencesRelativePath)
    }
}
