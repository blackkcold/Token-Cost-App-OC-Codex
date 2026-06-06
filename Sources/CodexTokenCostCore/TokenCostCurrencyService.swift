import Foundation

/// Centralized currency conversion and formatting service.
/// Consolidates all USD/CNY conversion logic previously scattered across BillingPlanCatalog.
public enum TokenCostCurrencyService {
    public static let canonicalBase: DisplayCurrency = .usd
    public static let defaultExchangeRateUSDToCNY: Double = 7.2

    /// Convert amount between currencies.
    public static func convert(_ amount: Double, from: DisplayCurrency = .usd, to: DisplayCurrency) -> Double {
        switch (from, to) {
        case (.usd, .usd): return amount
        case (.cny, .cny): return amount
        case (.usd, .cny): return amount * defaultExchangeRateUSDToCNY
        case (.cny, .usd): return amount / defaultExchangeRateUSDToCNY
        }
    }

    /// Format amount for display in the given currency.
    public static func format(_ amount: Double, currency: DisplayCurrency) -> String {
        switch currency {
        case .usd: return formatUSD(amount)
        case .cny: return formatCNY(amount)
        }
    }

    // MARK: - Private

    private static func formatUSD(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static func formatCNY(_ value: Double) -> String {
        String(format: "¥%.2f", value)
    }
}
