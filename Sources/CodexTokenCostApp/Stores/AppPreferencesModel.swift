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

    var balanceRefreshMinutesBinding: Binding<Int> {
        Binding(
            get: { self.preferences.balanceRefreshMinutes },
            set: { newValue in
                self.updatePreferences { preferences in
                    preferences.balanceRefreshMinutes = max(1, min(newValue, 60))
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
        preferences.balanceConfig ?? BalanceConfiguration()
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
}
