import Foundation
import SwiftUI
import CodexTokenCostCore

@MainActor
final class AppPreferencesModel: ObservableObject {
    @Published var preferences: AppPreferences
    @Published var loadWarningMessage: String?

    private let store: AppPreferencesStore

    init(runtimeRoot: URL = CodexAppPaths.runtimeRoot) {
        self.store = AppPreferencesStore(runtimeRoot: runtimeRoot)
        let loaded = store.load()
        self.preferences = loaded.preferences
        self.loadWarningMessage = loaded.errorMessage
        AppLocalization.setLanguage(loaded.preferences.language)
        if runtimeRoot == CodexAppPaths.runtimeRoot {
            try? CodexAppPaths.ensureRuntimeDirectories()
        }
    }

    func migrateThemeFromSettingsIfNeeded(_ legacyTheme: TokenCostThemeChoice) {
        guard preferences.theme == .ocean, legacyTheme != .ocean else { return }
        updatePreferences { $0.theme = legacyTheme }
    }

    var languageBinding: Binding<AppDisplayLanguage> {
        Binding(
            get: { self.preferences.language },
            set: { newValue in
                self.updatePreferences { preferences in
                    preferences.language = newValue
                }
            }
        )
    }

    var displayCurrencyBinding: Binding<DisplayCurrency> {
        Binding(
            get: { self.preferences.displayCurrency },
            set: { newValue in
                self.updatePreferences { preferences in
                    preferences.displayCurrency = newValue
                }
            }
        )
    }

    var themeBinding: Binding<TokenCostThemeChoice> {
        Binding(
            get: { self.preferences.theme },
            set: { newValue in
                self.updatePreferences { preferences in
                    preferences.theme = newValue
                }
            }
        )
    }

    func billingSelectionBinding(for provider: BillingProvider) -> Binding<BillingPlanSelection> {
        Binding(
            get: { self.preferences.billingSelection(for: provider) },
            set: { newValue in
                self.updatePreferences { preferences in
                    preferences.setBillingSelection(newValue, for: provider)
                }
            }
        )
    }

    func billingPlanOptionBinding(for provider: BillingProvider) -> Binding<String> {
        Binding(
            get: {
                let selection = self.preferences.billingSelection(for: provider)
                if selection.mode == .customMonthlyUSD {
                    return BillingPlanCatalog.customOptionID
                }
                if selection.isSubscribed,
                   !BillingPlanCatalog.isSubscriptionPresetID(selection.presetID) {
                    return BillingPlanCatalog.defaultSubscriptionSelection(for: provider).presetID
                }
                return selection.presetID
            },
            set: { optionID in
                self.updatePreferences { preferences in
                    var current = preferences.billingSelection(for: provider)
                    if optionID == BillingPlanCatalog.customOptionID {
                        let fallbackCost = BillingPlanCatalog.resolve(provider: provider, selection: current).monthlyUSD ?? 1
                        current.mode = .customMonthlyUSD
                        current.customMonthlyUSD = current.customMonthlyUSD ?? fallbackCost
                    } else {
                        current.mode = .preset
                        if BillingPlanCatalog.isSubscriptionPresetID(optionID) {
                            current.presetID = optionID
                        } else {
                            current.presetID = BillingPlanCatalog.defaultSubscriptionSelection(for: provider).presetID
                        }
                        current.customMonthlyUSD = nil
                    }
                    preferences.setBillingSelection(current, for: provider)
                }
            }
        )
    }

    func customBillingCostBinding(for provider: BillingProvider) -> Binding<Double> {
        Binding(
            get: {
                let selection = self.preferences.billingSelection(for: provider)
                let usdCost = selection.customMonthlyUSD ?? BillingPlanCatalog.resolve(provider: provider, selection: selection).monthlyUSD ?? 1
                return TokenCostCurrencyService.convert(usdCost, from: .usd, to: self.preferences.displayCurrency)
            },
            set: { newValue in
                guard newValue.isFinite, newValue > 0 else { return }
                self.updatePreferences { preferences in
                    var selection = preferences.billingSelection(for: provider)
                    selection.mode = .customMonthlyUSD
                    selection.customMonthlyUSD = TokenCostCurrencyService.convert(newValue, from: preferences.displayCurrency, to: .usd)
                    preferences.setBillingSelection(selection, for: provider)
                }
            }
        )
    }

    func subscribedBinding(for provider: BillingProvider) -> Binding<Bool> {
        Binding(
            get: { self.preferences.billingSelection(for: provider).isSubscribed },
            set: { newValue in
                self.updatePreferences { preferences in
                    var selection = preferences.billingSelection(for: provider)
                    if newValue,
                       BillingPlanCatalog.subscriptionPresets(for: provider).isEmpty {
                        return
                    }
                    if newValue,
                       selection.mode == .preset,
                       !BillingPlanCatalog.isSubscriptionPresetID(selection.presetID) {
                        selection = BillingPlanCatalog.defaultSubscriptionSelection(for: provider)
                    }
                    selection.isSubscribed = newValue
                    preferences.setBillingSelection(selection, for: provider)
                }
            }
        )
    }

    var balanceEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.balanceEnabled },
            set: { newValue in
                self.updatePreferences { preferences in
                    preferences.balanceEnabled = newValue
                }
            }
        )
    }

    var balanceRefreshSecondsBinding: Binding<Int> {
        Binding(
            get: { self.preferences.balanceRefreshSeconds },
            set: { newValue in
                self.updatePreferences { preferences in
                    preferences.balanceRefreshSeconds = max(30, min(newValue, 3600))
                }
            }
        )
    }

    var opencodeGoWorkspaceIDBinding: Binding<String> {
        Binding(
            get: { self.preferences.opencodeGoWorkspaceID ?? "" },
            set: { newValue in
                self.updatePreferences { preferences in
                    preferences.opencodeGoWorkspaceID = newValue.isEmpty ? nil : newValue
                }
                let wid = newValue.isEmpty ? nil : newValue
                if let wid {
                    SecureCredentialStore.shared.saveWorkspaceID(wid)
                } else {
                    SecureCredentialStore.shared.deleteWorkspaceID()
                }
            }
        )
    }

    var effectiveBalanceConfiguration: BalanceConfiguration {
        var config = preferences.balanceConfig ?? BalanceConfiguration()
        let ollamaEnabled = preferences.developerMode.ollamaUsageTrackingEnabled
        let hasOllama = config.enabledBalanceProviders.contains(.ollama)
        if ollamaEnabled, !hasOllama {
            config.enabledBalanceProviders.append(.ollama)
        } else if !ollamaEnabled, hasOllama {
            config.enabledBalanceProviders.removeAll { $0 == .ollama }
        }
        return config
    }

    var taskClassificationEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.taskClassificationEnabled },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.taskClassificationEnabled = newValue
                }
            }
        )
    }

    var optimizeEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.optimizeEnabled },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.optimizeEnabled = newValue
                }
            }
        )
    }

    var multiCurrencyEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.multiCurrencyEnabled },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.multiCurrencyEnabled = newValue
                }
            }
        )
    }

    var modelCompareEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.modelCompareEnabled },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.modelCompareEnabled = newValue
                }
            }
        )
    }

    var balanceSortOrderBinding: Binding<BalanceSortOrder> {
        Binding(
            get: { self.preferences.balanceSortOrder },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.balanceSortOrder = newValue
                }
            }
        )
    }

    var balanceDisplayModeBinding: Binding<BalanceDisplayMode> {
        Binding(
            get: { self.preferences.balanceDisplayMode },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.balanceDisplayMode = newValue
                }
            }
        )
    }

    func updatePreferences(_ mutate: (inout AppPreferences) -> Void) {
        var updated = preferences
        mutate(&updated)
        preferences = updated
        AppLocalization.setLanguage(updated.language)
        persistPreferences()
    }

    func updateBalanceConfiguration(_ mutate: (inout BalanceConfiguration) -> Void) {
        updatePreferences { prefs in
            var config = prefs.balanceConfig ?? BalanceConfiguration()
            mutate(&config)
            prefs.balanceConfig = config
        }
    }

    func updateSkillsPanel(showSource: Bool? = nil, showState: Bool? = nil, showTags: Bool? = nil, previewLength: Int? = nil, sortBy: String? = nil) {
        updatePreferences { prefs in
            if let v = showSource { prefs.skillsPanel.showSourceColumn = v }
            if let v = showState { prefs.skillsPanel.showStateColumn = v }
            if let v = showTags { prefs.skillsPanel.showTagsColumn = v }
            if let v = previewLength { prefs.skillsPanel.previewLength = v }
            if let v = sortBy { prefs.skillsPanel.sortBy = v }
        }
    }

    func persistPreferences() {
        do {
            try store.save(preferences)
            loadWarningMessage = nil
        } catch {
            loadWarningMessage = error.localizedDescription
#if DEBUG
            print("[AppPreferencesModel] persistPreferences failed: \(error.localizedDescription)")
#endif
        }
    }


        var developerModeIsEnabledBinding: Binding<Bool> {
            Binding(
                get: { self.preferences.developerMode.isEnabled },
                set: { newValue in
                    self.updatePreferences { prefs in
                        prefs.developerMode.isEnabled = newValue
                    }
                }
            )
        }

    func developerModeToggleBinding(for keyPath: WritableKeyPath<DeveloperModePreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.preferences.developerMode[keyPath: keyPath] },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.developerMode[keyPath: keyPath] = newValue
                }
            }
        )
    }

    let backupService = BackupService()

    @Published var backupRecords: [BackupFileRecord] = []
    @Published var backupOverview: BackupOverview?
    @Published var backupCompleteness: BackupCompletenessReport?
    @Published var unmanagedBakFiles: [BakFileInfo] = []
    @Published var backupIsWorking = false
    @Published var backupLastError: String?

    @Published var configFileGroups: [ConfigFileGroup] = []
    @Published var backupLayerResults: [BackupLayerResult] = []
    @Published var selectedBakFiles: Set<String> = []
    @Published var bakFileSortOrder: BakFileSortOrder = .newestFirst

    var backupDirectoryBinding: Binding<String> {
        Binding(
            get: { self.preferences.backup.backupDirectory },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.backup.backupDirectory = newValue
                }
            }
        )
    }

    var autoBackupEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.backup.autoBackupEnabled },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.backup.autoBackupEnabled = newValue
                }
            }
        )
    }

    var autoBackupIntervalBinding: Binding<BackupInterval> {
        Binding(
            get: { self.preferences.backup.autoBackupInterval },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.backup.autoBackupInterval = newValue
                }
            }
        )
    }

    var autoCleanEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.backup.autoCleanEnabled },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.backup.autoCleanEnabled = newValue
                }
            }
        )
    }

    var autoCleanKeepCountBinding: Binding<Int> {
        Binding(
            get: { self.preferences.backup.autoCleanKeepCount },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.backup.autoCleanKeepCount = max(1, min(newValue, 100))
                }
            }
        )
    }

    func toggleBackupLayer(_ layer: BackupLayer) {
        updatePreferences { prefs in
            if prefs.backup.enabledLayers.contains(layer) {
                prefs.backup.enabledLayers.remove(layer)
            } else {
                prefs.backup.enabledLayers.insert(layer)
            }
        }
    }

    func performBackupConfig(_ fileName: String) {
        backupIsWorking = true
        backupLastError = nil
        Task {
            do {
                let dir = preferences.backup.backupDirectory
                let record = try backupService.backupConfigFile(fileName, to: dir)
                await MainActor.run {
                    updatePreferences { $0.backup.lastBackupDate = Date() }
                    refreshBackupState()
                }
                _ = record
            } catch {
                await MainActor.run {
                    backupLastError = error.localizedDescription
                }
            }
            await MainActor.run { backupIsWorking = false }
        }
    }

    func performBackupAll() {
        backupIsWorking = true
        backupLastError = nil
        Task {
            do {
                let dir = preferences.backup.backupDirectory
                let records = try backupService.backupAllConfigs(
                    to: dir,
                    showDeprecated: preferences.backup.showDeprecatedFiles
                )
                await MainActor.run {
                    updatePreferences { $0.backup.lastBackupDate = Date() }
                    if preferences.backup.autoCleanEnabled {
                        _ = try? backupService.cleanOldBackups(
                            in: dir,
                            keep: preferences.backup.autoCleanKeepCount
                        )
                        updatePreferences { $0.backup.lastCleanDate = Date() }
                    }
                    refreshBackupState()
                }
                _ = records
            } catch {
                await MainActor.run {
                    backupLastError = error.localizedDescription
                }
            }
            await MainActor.run { backupIsWorking = false }
        }
    }

    func performFullLayeredBackup() {
        backupIsWorking = true
        backupLastError = nil
        backupLayerResults = []
        Task {
            do {
                let dir = preferences.backup.backupDirectory
                let result = try backupService.performFullLayeredBackup(
                    to: dir, enabledLayers: preferences.backup.enabledLayers
                )
                await MainActor.run {
                    updatePreferences { $0.backup.lastBackupDate = Date() }
                    backupLayerResults = result.layers
                    if preferences.backup.autoCleanEnabled {
                        try? backupService.rotateFullBackups(
                            in: dir, keep: preferences.backup.maxBackupCount
                        )
                        updatePreferences { $0.backup.lastCleanDate = Date() }
                    }
                    refreshBackupState()
                }
            } catch {
                await MainActor.run {
                    backupLastError = error.localizedDescription
                }
            }
            await MainActor.run { backupIsWorking = false }
        }
    }

    func performBackupConfigGroup(_ group: ConfigFileGroup) {
        backupIsWorking = true
        backupLastError = nil
        Task {
            let dir = preferences.backup.backupDirectory
            for fileStatus in group.files where fileStatus.sourceExists {
                do {
                    _ = try backupService.backupConfigFile(fileStatus.fileName, to: dir)
                } catch {
                    await MainActor.run { backupLastError = error.localizedDescription }
                }
            }
            await MainActor.run {
                updatePreferences { $0.backup.lastBackupDate = Date() }
                refreshBackupState()
                backupIsWorking = false
            }
        }
    }

    func performCleanBackups() {
        backupIsWorking = true
        backupLastError = nil
        Task {
            do {
                let dir = preferences.backup.backupDirectory
                _ = try backupService.cleanOldBackups(
                    in: dir,
                    keep: preferences.backup.autoCleanKeepCount
                )
                await MainActor.run {
                    updatePreferences { $0.backup.lastCleanDate = Date() }
                    refreshBackupState()
                }
            } catch {
                await MainActor.run {
                    backupLastError = error.localizedDescription
                }
            }
            await MainActor.run { backupIsWorking = false }
        }
    }

    var showDeprecatedFilesBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.backup.showDeprecatedFiles },
            set: { newValue in
                self.updatePreferences { $0.backup.showDeprecatedFiles = newValue }
                self.refreshConfigFileGroups()
            }
        )
    }

    var maxBackupCountBinding: Binding<Int> {
        Binding(
            get: { self.preferences.backup.maxBackupCount },
            set: { newValue in
                self.updatePreferences { $0.backup.maxBackupCount = max(1, min(newValue, 50)) }
            }
        )
    }

    func refreshConfigFileGroups() {
        let latestLayered = backupRecords.first { $0.backupType == .layered }
        configFileGroups = BackupService.configFileGroups(
            showDeprecated: preferences.backup.showDeprecatedFiles,
            backupRecords: backupRecords,
            latestLayeredDir: latestLayered?.path
        )
    }

    func toggleBakSelection(_ id: String) {
        if selectedBakFiles.contains(id) {
            selectedBakFiles.remove(id)
        } else {
            selectedBakFiles.insert(id)
        }
    }

    func selectAllBakFiles() {
        selectedBakFiles = Set(unmanagedBakFiles.map { $0.id })
    }

    func deselectAllBakFiles() {
        selectedBakFiles.removeAll()
    }

    func sortBakFiles(_ order: BakFileSortOrder) {
        bakFileSortOrder = order
        unmanagedBakFiles = backupService.listUnmanagedBakFiles(sortOrder: order)
    }

    func trashSelectedBakFiles() {
        let files = unmanagedBakFiles.filter { selectedBakFiles.contains($0.id) }
        guard !files.isEmpty else { return }
        performTrashUnmanagedBakFiles(files)
    }

    func performTrashUnmanagedBakFiles(_ files: [BakFileInfo]) {
        backupIsWorking = true
        backupLastError = nil
        Task {
            do {
                try backupService.trashUnmanagedBakFiles(files)
                await MainActor.run {
                    refreshUnmanagedBakFiles()
                    selectedBakFiles.removeAll()
                }
            } catch {
                await MainActor.run {
                    backupLastError = error.localizedDescription
                }
            }
            await MainActor.run { backupIsWorking = false }
        }
    }

    func deleteBackupRecord(_ record: BackupFileRecord) {
        let url = URL(fileURLWithPath: record.path)
        try? FileManager.default.removeItem(at: url)
        refreshBackupState()
    }

    func refreshBackupState() {
        let dir = preferences.backup.backupDirectory
        backupRecords = backupService.listBackups(in: dir)
        backupOverview = backupService.overview(in: dir)
        backupCompleteness = backupService.verifyCompleteness(in: dir)
        refreshConfigFileGroups()
    }

    func refreshUnmanagedBakFiles() {
        unmanagedBakFiles = backupService.listUnmanagedBakFiles(sortOrder: bakFileSortOrder)
    }
}
