import Foundation
import SwiftUI
import CodexTokenCostCore

@MainActor
final class AppPreferencesModel: ObservableObject {
    @Published var preferences: AppPreferences
    @Published var loadWarningMessage: String?

    private let store: AppPreferencesStore
    private var shouldMigrateLegacyThemeFromSourceSettings: Bool

    init(runtimeRoot: URL = CodexAppPaths.runtimeRoot) {
        self.store = AppPreferencesStore(runtimeRoot: runtimeRoot)
        let loaded = store.load()
        self.preferences = loaded.preferences
        self.loadWarningMessage = loaded.errorMessage
        self.shouldMigrateLegacyThemeFromSourceSettings = loaded.didFallbackToDefaults
        AppLocalization.setLanguage(loaded.preferences.language)
        if runtimeRoot == CodexAppPaths.runtimeRoot {
            try? CodexAppPaths.ensureRuntimeDirectories()
        }
    }

    func migrateThemeFromSettingsIfNeeded(_ legacyTheme: TokenCostThemeChoice) {
        guard shouldMigrateLegacyThemeFromSourceSettings else { return }
        shouldMigrateLegacyThemeFromSourceSettings = false
        guard legacyTheme != .ocean else { return }
        updatePreferences {
            $0.accentPalette = legacyTheme.accentPalette
            $0.appearanceMode = legacyTheme.appearanceMode
        }
    }

    struct LocalCredentialSnapshot {
        let workspaceID: String?
        let goCookie: String?
        let ollamaCookie: String?
    }

    func localCredentialSnapshot() -> LocalCredentialSnapshot {
        let local = LocalCredentialService.shared
        return LocalCredentialSnapshot(
            workspaceID: local.getWorkspaceID(),
            goCookie: local.getAuthCookie(),
            ollamaCookie: local.getOllamaCookie()
        )
    }

    func saveLocalGoCredentials(workspaceID: String?, cookie: String?) {
        let normalizedWorkspaceID = normalizedLocalCredentialValue(workspaceID)
        let normalizedCookie = normalizedLocalCredentialValue(cookie)
        LocalCredentialService.shared.saveGoCredentials(workspaceID: normalizedWorkspaceID, cookie: normalizedCookie)
        CredentialBootstrapService.shared.updateCachedGoCookie(normalizedCookie, workspaceID: normalizedWorkspaceID)
    }

    func clearLocalGoCookiePreservingWorkspaceID() {
        let workspaceID = normalizedLocalCredentialValue(LocalCredentialService.shared.getWorkspaceID())
        LocalCredentialService.shared.saveGoCredentials(workspaceID: workspaceID, cookie: nil)
        CredentialBootstrapService.shared.updateCachedGoCookie(nil, workspaceID: workspaceID)
    }

    func saveLocalOllamaCookie(_ cookie: String?) {
        let normalizedCookie = normalizedLocalCredentialValue(cookie)
        guard let normalizedCookie else {
            LocalCredentialService.shared.saveOllamaCookie("")
            CredentialBootstrapService.shared.updateCachedOllamaCookie(nil)
            return
        }

        LocalCredentialService.shared.saveOllamaCookie(normalizedCookie)
        CredentialBootstrapService.shared.updateCachedOllamaCookie(normalizedCookie)
    }

    func clearLocalOllamaCookie() {
        LocalCredentialService.shared.saveOllamaCookie("")
        CredentialBootstrapService.shared.updateCachedOllamaCookie(nil)
    }

    private func normalizedLocalCredentialValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func reportingRangeCustomBoundsAreUsable(_ bounds: ReportingRangeCustomBounds) -> Bool {
        guard let start = bounds.start, let end = bounds.end else { return false }
        return start <= end
    }

    private func monthReportingRangeCustomBounds(referenceDate: Date = Date()) -> ReportingRangeCustomBounds {
        let calendar = Calendar.autoupdatingCurrent
        if let monthInterval = calendar.dateInterval(of: .month, for: referenceDate) {
            let end = calendar.date(byAdding: .second, value: -1, to: monthInterval.end) ?? monthInterval.end
            return ReportingRangeCustomBounds(start: monthInterval.start, end: end)
        }

        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: referenceDate) ?? referenceDate
        return ReportingRangeCustomBounds(start: start, end: end)
    }

    private func normalizedReportingRangeCustomBounds(start: Date, end: Date) -> ReportingRangeCustomBounds {
        let calendar = Calendar.autoupdatingCurrent
        let lower = min(start, end)
        let upper = max(start, end)
        let normalizedStart = calendar.startOfDay(for: lower)
        let normalizedEnd: Date
        if let dayInterval = calendar.dateInterval(of: .day, for: upper) {
            normalizedEnd = calendar.date(byAdding: .second, value: -1, to: dayInterval.end) ?? dayInterval.end
        } else {
            normalizedEnd = upper
        }
        return ReportingRangeCustomBounds(start: normalizedStart, end: normalizedEnd)
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

    var accentPaletteBinding: Binding<TokenCostAccentPalette> {
        Binding(
            get: { self.preferences.accentPalette },
            set: { newValue in
                self.updatePreferences { preferences in
                    preferences.accentPalette = newValue
                }
            }
        )
    }

    var appearanceModeBinding: Binding<TokenCostAppearanceMode> {
        Binding(
            get: { self.preferences.appearanceMode },
            set: { newValue in
                self.updatePreferences { preferences in
                    preferences.appearanceMode = newValue
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

    private var periodDebounceTask: Task<Void, Never>?

    private func updatePreferencesDebounced(_ mutate: @escaping (inout AppPreferences) -> Void) {
        var updated = preferences
        mutate(&updated)
        preferences = updated
        AppLocalization.setLanguage(updated.language)
        periodDebounceTask?.cancel()
        periodDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            persistPreferences()
        }
    }

    func periodGranularityBinding(for provider: BillingProvider) -> Binding<PeriodGranularity> {
        Binding(
            get: { self.preferences.billingSelection(for: provider).periodGranularity },
            set: { newValue in
                self.updatePreferences { preferences in
                    var selection = preferences.billingSelection(for: provider)
                    selection.periodGranularity = newValue
                    preferences.setBillingSelection(selection, for: provider)
                }
            }
        )
    }

    func periodStartBinding(for provider: BillingProvider) -> Binding<Date> {
        Binding(
            get: {
                self.preferences.billingSelection(for: provider).periodStart
                    ?? self.defaultCustomPeriodTrackingDates().start
            },
            set: { newValue in
                self.updatePreferencesDebounced { preferences in
                    var selection = preferences.billingSelection(for: provider)
                    selection.hasPeriodTracking = true
                    selection.periodPreset = nil
                    if let end = selection.periodEnd, end < newValue {
                        selection.periodEnd = newValue
                    }
                    if selection.periodEnd == nil {
                        selection.periodEnd = newValue
                    }
                    selection.periodStart = newValue
                    preferences.setBillingSelection(selection, for: provider)
                }
            }
        )
    }

    func periodEndBinding(for provider: BillingProvider) -> Binding<Date> {
        Binding(
            get: {
                self.preferences.billingSelection(for: provider).periodEnd
                    ?? self.defaultCustomPeriodTrackingDates().end
            },
            set: { newValue in
                self.updatePreferencesDebounced { preferences in
                    var selection = preferences.billingSelection(for: provider)
                    selection.hasPeriodTracking = true
                    selection.periodPreset = nil
                    if let start = selection.periodStart, start > newValue {
                        selection.periodStart = newValue
                    }
                    if selection.periodStart == nil {
                        selection.periodStart = newValue
                    }
                    selection.periodEnd = newValue
                    preferences.setBillingSelection(selection, for: provider)
                }
            }
        )
    }

    private func defaultCustomPeriodTrackingDates(referenceDate: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, end)
    }

    func hasPeriodTrackingBinding(for provider: BillingProvider) -> Binding<Bool> {
        Binding(
            get: { self.preferences.billingSelection(for: provider).hasPeriodTracking },
            set: { newValue in
                if newValue {
                    let current = self.preferences.billingSelection(for: provider)
                    if current.periodStart == nil, current.periodEnd == nil {
                        self.initializeMonthlyPeriodTracking(for: provider)
                        return
                    }
                }

                self.updatePreferences { preferences in
                    var selection = preferences.billingSelection(for: provider)
                    selection.hasPeriodTracking = newValue
                    preferences.setBillingSelection(selection, for: provider)
                }
            }
        )
    }

    func periodPresetBinding(for provider: BillingProvider) -> Binding<PeriodPreset?> {
        Binding(
            get: { self.preferences.billingSelection(for: provider).periodPreset },
            set: { newValue in
                guard let newValue else {
                    self.prepareCustomPeriodTracking(for: provider)
                    return
                }

                self.applyPeriodPreset(newValue, for: provider)
            }
        )
    }

    func applyPeriodPreset(_ preset: PeriodPreset, for provider: BillingProvider) {
        updatePreferences { preferences in
            var selection = preferences.billingSelection(for: provider)
            let now = Date()
            let calendar = Calendar.autoupdatingCurrent
            let endDate: Date
            switch preset {
            case .monthly:
                endDate = calendar.date(byAdding: .month, value: 1, to: now) ?? now
            case .quarterly:
                endDate = calendar.date(byAdding: .month, value: 3, to: now) ?? now
            case .yearly:
                endDate = calendar.date(byAdding: .year, value: 1, to: now) ?? now
            }
            selection.hasPeriodTracking = true
            selection.periodStart = now
            selection.periodEnd = endDate
            selection.periodPreset = preset
            selection.periodGranularity = .month
            preferences.setBillingSelection(selection, for: provider)
        }
    }

    func clearCustomPeriodDates(for provider: BillingProvider) {
        updatePreferences { preferences in
            var selection = preferences.billingSelection(for: provider)
            selection.periodStart = nil
            selection.periodEnd = nil
            selection.periodPreset = nil
            preferences.setBillingSelection(selection, for: provider)
        }
    }

    func resetCustomPeriodDates(for provider: BillingProvider) {
        updatePreferences { preferences in
            var selection = preferences.billingSelection(for: provider)
            selection.hasPeriodTracking = true
            selection.periodStart = nil
            selection.periodEnd = nil
            selection.periodPreset = nil
            preferences.setBillingSelection(selection, for: provider)
        }
    }

    private func prepareCustomPeriodTracking(for provider: BillingProvider) {
        updatePreferences { preferences in
            var selection = preferences.billingSelection(for: provider)
            selection.hasPeriodTracking = true
            selection.periodPreset = nil

            if let start = selection.periodStart,
               let end = selection.periodEnd,
               start <= end {
                preferences.setBillingSelection(selection, for: provider)
                return
            }

            let defaults = defaultCustomPeriodTrackingDates()
            selection.periodStart = defaults.start
            selection.periodEnd = defaults.end
            preferences.setBillingSelection(selection, for: provider)
        }
    }

    func initializeMonthlyPeriodTracking(for provider: BillingProvider) {
        updatePreferences { preferences in
            var selection = preferences.billingSelection(for: provider)
            let now = Date()
            let calendar = Calendar.autoupdatingCurrent
            selection.hasPeriodTracking = true
            selection.periodStart = now
            selection.periodEnd = calendar.date(byAdding: .month, value: 1, to: now) ?? now
            selection.periodPreset = .monthly
            selection.periodGranularity = .month
            preferences.setBillingSelection(selection, for: provider)
        }
    }

    var reportingRangeModeBinding: Binding<ReportingRangeMode> {
        Binding(
            get: { self.preferences.reportingRangeMode },
            set: { newValue in
                if newValue == .custom, !self.reportingRangeCustomBoundsAreUsable(self.preferences.reportingRangeCustomBounds) {
                    self.updatePreferences { prefs in
                        prefs.reportingRangeMode = .custom
                        prefs.reportingRangeCustomBounds = self.monthReportingRangeCustomBounds()
                    }
                    return
                }

                self.updatePreferences { prefs in
                    prefs.reportingRangeMode = newValue
                }
            }
        )
    }

    var reportingRangeCustomStartBinding: Binding<Date?> {
        Binding(
            get: { self.preferences.reportingRangeCustomBounds.start },
            set: { newValue in
                self.updatePreferencesDebounced { prefs in
                    prefs.reportingRangeMode = .custom
                    prefs.reportingRangeCustomBounds.start = newValue
                }
            }
        )
    }

    var reportingRangeCustomEndBinding: Binding<Date?> {
        Binding(
            get: { self.preferences.reportingRangeCustomBounds.end },
            set: { newValue in
                self.updatePreferencesDebounced { prefs in
                    prefs.reportingRangeMode = .custom
                    prefs.reportingRangeCustomBounds.end = newValue
                }
            }
        )
    }

    func resetReportingRangeCustomBounds() {
        updatePreferences { prefs in
            prefs.reportingRangeMode = .custom
            prefs.reportingRangeCustomBounds = monthReportingRangeCustomBounds()
        }
    }

    func setReportingRangeCustomBounds(start: Date, end: Date) {
        updatePreferences { prefs in
            prefs.reportingRangeMode = .custom
            prefs.reportingRangeCustomBounds = normalizedReportingRangeCustomBounds(start: start, end: end)
        }
    }

    func initializeReportingRangeCustomBounds() {
        updatePreferences { prefs in
            prefs.reportingRangeMode = .custom
            prefs.reportingRangeCustomBounds = monthReportingRangeCustomBounds()
        }
    }

    var reportingRangeBasisLabel: String {
        switch preferences.reportingRangeMode {
        case .allAvailable: return AppLocalization.text("settings.billing.reportingRange.mode.allAvailable")
        case .currentMonth: return AppLocalization.text("settings.billing.reportingRange.mode.currentMonth")
        case .last30Days: return AppLocalization.text("settings.billing.reportingRange.mode.last30Days")
        case .custom: return AppLocalization.text("settings.billing.reportingRange.mode.custom")
        }
    }

    func reportingRangeDateRange(for payload: DashboardPayload) -> (start: Date, end: Date)? {
        AppPreferences.resolveReportingRange(
            mode: preferences.reportingRangeMode,
            customBounds: preferences.reportingRangeCustomBounds,
            payload: payload
        )
    }

    func reportingCostBreakdown(for payload: DashboardPayload) -> ReportingCostBreakdown? {
        guard let range = reportingRangeDateRange(for: payload) else { return nil }
        return preferences.reportingCostBreakdown(payload: payload, reportingStart: range.start, reportingEnd: range.end)
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

    var balanceMenuBarExtraEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.balanceMenuBarExtraEnabled },
            set: { newValue in
                guard newValue != self.preferences.balanceMenuBarExtraEnabled else { return }
                self.updatePreferences { preferences in
                    preferences.balanceMenuBarExtraEnabled = newValue
                }
            }
        )
    }

    /// 专用余额 MenuBarExtra 的可见性：需同时开启余额菜单栏项与开发者模式。
    /// 写入仍落到 balanceMenuBarExtraEnabled，避免在开发者模式关闭时丢失用户偏好。
    var balanceMenuBarExtraVisibleBinding: Binding<Bool> {
        Binding(
            get: {
                self.preferences.balanceMenuBarExtraEnabled
                    && self.preferences.developerMode.isEnabled
            },
            set: { newValue in
                guard newValue != self.preferences.balanceMenuBarExtraEnabled else { return }
                self.updatePreferences { preferences in
                    preferences.balanceMenuBarExtraEnabled = newValue
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
            get: {
                self.localCredentialSnapshot().workspaceID
                    ?? self.preferences.opencodeGoWorkspaceID
                    ?? ""
            },
            set: { newValue in
                self.saveLocalGoCredentials(workspaceID: newValue, cookie: self.localCredentialSnapshot().goCookie)
            }
        )
    }

    var effectiveBalanceConfiguration: BalanceConfiguration {
        preferences.balanceConfig ?? BalanceConfiguration()
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

    var balanceCustomOrderBinding: Binding<[BalanceProviderKind]> {
        Binding(
            get: { self.preferences.balanceCustomOrder },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.balanceCustomOrder = newValue
                }
            }
        )
    }

    var balanceOrderLockedBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.balanceOrderLocked },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.balanceOrderLocked = newValue
                }
            }
        )
    }

    var balanceFloatingPanelEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.balanceFloatingPanelEnabled },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.balanceFloatingPanelEnabled = newValue
                }
            }
        )
    }

    var balanceFloatingPanelAlwaysOnTopBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.balanceFloatingPanelAlwaysOnTop },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.balanceFloatingPanelAlwaysOnTop = newValue
                }
            }
        )
    }

    var balanceFloatingPanelDisplayModeBinding: Binding<BalanceFloatingPanelDisplayMode> {
        Binding(
            get: { self.preferences.balanceFloatingPanelDisplayMode },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.balanceFloatingPanelDisplayMode = newValue
                }
            }
        )
    }

    var credentialSourceModeBinding: Binding<CredentialSourceMode> {
        Binding(
            get: { self.preferences.credentialSourceMode },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.credentialSourceMode = newValue
                }
                CredentialBootstrapService.shared.clearCache()
            }
        )
    }

    var periodTotalCostEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.periodTotalCostEnabled },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.periodTotalCostEnabled = newValue
                }
            }
        )
    }

    var menuBarChartStyleBinding: Binding<MenuBarChartStyle> {
        Binding(
            get: { self.preferences.menuBarChartStyle },
            set: { newValue in
                self.updatePreferences { prefs in
                    prefs.menuBarChartStyle = newValue
                }
            }
        )
    }

    func normalizedBalanceProviderOrder() -> [BalanceProviderKind] {
        let defaultOrder = BalanceProviderKind.allCases.sorted { $0.sortOrder < $1.sortOrder }
        let defaultProviders = Set(defaultOrder)
        var seen = Set<BalanceProviderKind>()
        let customOrder = preferences.balanceCustomOrder.filter { provider in
            defaultProviders.contains(provider) && seen.insert(provider).inserted
        }
        let customProviders = Set(customOrder)
        return customOrder + defaultOrder.filter { !customProviders.contains($0) }
    }

    func balanceProviderOrder(
        moving visibleProviders: [BalanceProviderKind],
        fromOffsets offsets: IndexSet,
        toOffset target: Int
    ) -> [BalanceProviderKind] {
        let providerOrder = normalizedBalanceProviderOrder()
        let providerSet = Set(providerOrder)
        var seen = Set<BalanceProviderKind>()
        var reorderedVisibleProviders = visibleProviders.filter { provider in
            providerSet.contains(provider) && seen.insert(provider).inserted
        }

        guard !reorderedVisibleProviders.isEmpty else { return providerOrder }

        var validOffsets = IndexSet()
        for offset in offsets where reorderedVisibleProviders.indices.contains(offset) {
            validOffsets.insert(offset)
        }
        guard !validOffsets.isEmpty else { return providerOrder }

        let boundedTarget = min(max(target, 0), reorderedVisibleProviders.count)
        reorderedVisibleProviders.move(fromOffsets: validOffsets, toOffset: boundedTarget)

        var visibleProviderIterator = reorderedVisibleProviders.makeIterator()
        let visibleProviderSet = Set(reorderedVisibleProviders)
        return providerOrder.map { provider in
            guard visibleProviderSet.contains(provider) else { return provider }
            return visibleProviderIterator.next() ?? provider
        }
    }

    func sortBalanceSnapshots(_ snapshots: [BalanceSnapshot]) -> [BalanceSnapshot] {
        let customOrder = preferences.balanceCustomOrder
        if !customOrder.isEmpty {
            let providerRanks = Dictionary(
                uniqueKeysWithValues: normalizedBalanceProviderOrder().enumerated().map { index, provider in
                    (provider, index)
                }
            )
            return snapshots.sorted { a, b in
                let aRank = providerRanks[a.provider] ?? Int.max
                let bRank = providerRanks[b.provider] ?? Int.max
                if aRank != bRank { return aRank < bRank }
                return a.provider.sortOrder < b.provider.sortOrder
            }
        }

        let order = preferences.balanceSortOrder
        return snapshots.sorted { a, b in
            switch order {
            case .quotaFirst:
                if a.isQuotaType != b.isQuotaType { return a.isQuotaType }
                return a.provider.sortOrder < b.provider.sortOrder
            case .balanceFirst:
                if a.isBalanceType != b.isBalanceType { return a.isBalanceType }
                return a.provider.sortOrder < b.provider.sortOrder
            case .byProvider:
                return a.provider.sortOrder < b.provider.sortOrder
            }
        }
    }

    func resetBalanceCustomOrder() {
        updatePreferences { prefs in
            prefs.balanceCustomOrder = []
            prefs.balanceOrderLocked = true
        }
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
    @Published var launchdTaskLoaded: Bool = false
    @Published var bakDiffResults: [String: BakDiffResult] = [:]

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
                self.refreshBackupState()
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

    var scheduledTaskEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.backup.scheduledTaskEnabled },
            set: { newValue in
                self.updatePreferences { $0.backup.scheduledTaskEnabled = newValue }
                self.applyLaunchdTaskState(newValue)
            }
        )
    }

    func refreshLaunchdTaskState() {
        launchdTaskLoaded = backupService.isLaunchdTaskLoaded()
    }

    private func applyLaunchdTaskState(_ enabled: Bool) {
        backupIsWorking = true
        backupLastError = nil
        Task {
            do {
                let backup = preferences.backup
                try backupService.setLaunchdTaskEnabled(
                    enabled,
                    config: LaunchdTaskConfiguration(
                        interval: backup.autoBackupInterval,
                        backupDirectory: backup.backupDirectory,
                        keepCount: backup.autoCleanKeepCount,
                        enabledLayers: backup.enabledLayers
                    )
                )
                await MainActor.run {
                    refreshLaunchdTaskState()
                }
            } catch {
                await MainActor.run {
                    backupLastError = error.localizedDescription
                    updatePreferences { $0.backup.scheduledTaskEnabled = !enabled }
                }
            }
            await MainActor.run { backupIsWorking = false }
        }
    }

    func diffBakFile(_ bak: BakFileInfo) -> BakDiffResult {
        let result = backupService.diffBakFile(bak)
        bakDiffResults[bak.id] = result
        return result
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
        backupCompleteness = backupService.verifyCompleteness(
            in: dir,
            showDeprecated: preferences.backup.showDeprecatedFiles
        )
        refreshConfigFileGroups()
        refreshLaunchdTaskState()
    }

    func refreshUnmanagedBakFiles() {
        unmanagedBakFiles = backupService.listUnmanagedBakFiles(sortOrder: bakFileSortOrder)
        bakDiffResults.removeAll()
    }
}
