import OSLog

/// Unified balance logging based on `os.Logger`.
///
/// Log level convention:
/// - `.debug`   — Sample storage, rate computation details (DEBUG-only)
/// - `.info`    — Refresh start/complete events
/// - `.notice`  — Window reset detection, fallback degradation
/// - `.error`   — Provider unavailable, network errors
/// - `.fault`   — UserDefaults read/write failures
enum BalanceLog {
    static let general = Logger(subsystem: "com.token-cost-app.oc-codex", category: "balance")
    static let calculator = Logger(subsystem: "com.token-cost-app.oc-codex", category: "balance.calculator")
    static let amountCalculator = Logger(subsystem: "com.token-cost-app.oc-codex", category: "balance.amount-calculator")
    static let provider = Logger(subsystem: "com.token-cost-app.oc-codex", category: "balance.provider")
    static let relay = Logger(subsystem: "com.token-cost-app.oc-codex", category: "relay")
}