import CodexTokenCostCore
import Foundation

@MainActor
final class RelayDashboardAnalyticsProvider: RelayAnalyticsProviding {
    private weak var openCodeModel: TokenCostModel?
    private weak var preferencesModel: AppPreferencesModel?

    init(openCodeModel: TokenCostModel, preferencesModel: AppPreferencesModel) {
        self.openCodeModel = openCodeModel
        self.preferencesModel = preferencesModel
    }

    func currentAnalytics() async -> TokenCostDashboardAnalytics? {
        guard let openCodeModel,
              let preferencesModel,
              let payload = openCodeModel.selectedPayload
        else { return nil }

        let preferences = preferencesModel.preferences
        let result = preferences.filteredPayloadWithReportingOverrides(
            payload: payload,
            mode: preferences.reportingRangeMode,
            customBounds: preferences.reportingRangeCustomBounds
        )
        let effectivePayload: DashboardPayload
        let overrides: [String: Double]
        if let result {
            effectivePayload = result.payload
            overrides = result.overrides
        } else {
            effectivePayload = payload
            overrides = preferences.billingOverridesByProviderKey()
        }
        let showZero = openCodeModel.settings.showZeroUsageXiaomiProvider
        return await Task.detached(priority: .utility) {
            TokenCostDashboardAnalytics(
                payload: effectivePayload,
                showZeroUsageXiaomiProvider: showZero,
                billingOverridesByProviderKey: overrides
            )
        }.value
    }
}
