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

public struct AppPreferences: Codable, Equatable, Sendable {
    public var language: AppDisplayLanguage
    public var billingSelectionsByProvider: [String: BillingPlanSelection]
    public var balanceEnabled: Bool
    public var balanceRefreshMinutes: Int
    public var opencodeGoWorkspaceID: String?
    public var theme: TokenCostThemeChoice
    public var displayCurrency: DisplayCurrency
    public var skillsPanel: SkillsPanelPreferences

    public init(
        language: AppDisplayLanguage = .zhHans,
        billingSelectionsByProvider: [String: BillingPlanSelection] = [:],
        balanceEnabled: Bool = false,
        balanceRefreshMinutes: Int = 10,
        opencodeGoWorkspaceID: String? = nil,
        theme: TokenCostThemeChoice = .ocean,
        displayCurrency: DisplayCurrency = .usd,
        skillsPanel: SkillsPanelPreferences = SkillsPanelPreferences()
    ) {
        self.language = language
        self.billingSelectionsByProvider = billingSelectionsByProvider
        self.balanceEnabled = balanceEnabled
        self.balanceRefreshMinutes = balanceRefreshMinutes
        self.opencodeGoWorkspaceID = opencodeGoWorkspaceID
        self.theme = theme
        self.displayCurrency = displayCurrency
        self.skillsPanel = skillsPanel
    }

    private enum CodingKeys: String, CodingKey {
        case language
        case billingSelectionsByProvider
        case balanceEnabled = "balance_enabled"
        case balanceRefreshMinutes = "balance_refresh_minutes"
        case opencodeGoWorkspaceID = "opencode_go_workspace_id"
        case theme
        case displayCurrency
        case skillsPanel
    }

    private enum DecodingKeys: String, CodingKey {
        case language
        case billingSelectionsByProvider
        case balanceEnabled
        case balanceRefreshMinutes
        case opencodeGoWorkspaceID = "opencodeGoWorkspaceId"
        case theme
        case displayCurrency
        case skillsPanel
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
        self.balanceRefreshMinutes = try container.decodeIfPresent(Int.self, forKey: .balanceRefreshMinutes)
            ?? legacyContainer?.decodeIfPresent(Int.self, forKey: .balanceRefreshMinutes)
            ?? 10
        self.opencodeGoWorkspaceID = try container.decodeIfPresent(String.self, forKey: .opencodeGoWorkspaceID)
            ?? legacyContainer?.decodeIfPresent(String.self, forKey: .opencodeGoWorkspaceID)
        self.theme = try container.decodeIfPresent(TokenCostThemeChoice.self, forKey: .theme) ?? .ocean
        self.displayCurrency = try container.decodeIfPresent(DisplayCurrency.self, forKey: .displayCurrency) ?? .usd
        self.skillsPanel = try container.decodeIfPresent(SkillsPanelPreferences.self, forKey: .skillsPanel) ?? SkillsPanelPreferences()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(language, forKey: .language)
        try container.encode(billingSelectionsByProvider, forKey: .billingSelectionsByProvider)
        try container.encode(balanceEnabled, forKey: .balanceEnabled)
        try container.encode(balanceRefreshMinutes, forKey: .balanceRefreshMinutes)
        try container.encodeIfPresent(opencodeGoWorkspaceID, forKey: .opencodeGoWorkspaceID)
        try container.encode(theme, forKey: .theme)
        try container.encode(displayCurrency, forKey: .displayCurrency)
        try container.encode(skillsPanel, forKey: .skillsPanel)
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
        try backupExistingPreferencesIfNeeded()
        try fileStore.writeCodable(preferences, to: preferencesRelativePath)
    }

    private func backupExistingPreferencesIfNeeded() throws {
        let currentURL = try fileStore.resolve(preferencesRelativePath)
        guard FileManager.default.fileExists(atPath: currentURL.path) else {
            return
        }

        let backupDirectory = try fileStore.resolve("config/backups/app-preferences")
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let baseName = URL(fileURLWithPath: preferencesRelativePath)
            .deletingPathExtension()
            .lastPathComponent
        let backupURL = backupDirectory.appendingPathComponent("\(baseName)-\(timestamp()).json")
        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.copyItem(at: currentURL, to: backupURL)
        rotateBackups(in: backupDirectory, keep: 10)
    }

    private func rotateBackups(in directory: URL, keep: Int) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let sorted = urls.sorted { lhs, rhs in
            let lhDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rhDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return lhDate > rhDate
        }
        guard sorted.count > keep else { return }
        for url in sorted.dropFirst(keep) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        let raw = formatter.string(from: Date())
        return raw
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }
}
