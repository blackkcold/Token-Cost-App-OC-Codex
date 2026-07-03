import AppKit
import Charts
import SwiftUI
import CodexTokenCostCore

struct MenuBarView: View {
    @ObservedObject var openCodeModel: TokenCostModel
    @ObservedObject var codexModel: CodexSessionModel
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @ObservedObject var balanceManager: BalanceManager
    let palette: TokenCostPalette
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let cost = combinedCost
        let tokens = combinedTotalActualTokens
        let messages = openCodePayload?.summary.totalMessages
        let sessions = codexPayload?.summary.sessionCount
        let points = sparklinePoints
        let hasSummary = cost != nil || tokens != nil

        VStack(alignment: .leading, spacing: 12) {
            header

            if hasSummary {
                Divider()
                summaryOverview(cost: cost, tokens: tokens, messages: messages, sessions: sessions)
            }

            if points.count >= 2 {
                Divider()
                sparklineSection(points: points)
            }

            if appPreferencesModel.preferences.balanceEnabled,
               !balanceManager.snapshots.isEmpty {
                Divider()
                balanceSummary
            }

            Divider()

            Button {
                activateMainWindow()
            } label: {
                Label(AppLocalization.text("menu.openMainWindow"), systemImage: "window")
            }

            Button {
                openCodeModel.rescanSources()
                codexModel.refresh()
            } label: {
                Label(AppLocalization.text("menu.refreshAll"), systemImage: "arrow.clockwise")
            }
            .disabled(openCodeModel.isBootstrapping || openCodeModel.isRefreshing || codexModel.isBootstrapping || codexModel.isRefreshing)

            Button {
                NSApp.setActivationPolicy(.regular)
                openSettings()
            } label: {
                Label(AppLocalization.text("menu.openSettings"), systemImage: "gearshape")
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(AppLocalization.text("menu.quit"), systemImage: "xmark.circle")
            }
        }
        .frame(width: 290)
        .padding(12)
    }

    // MARK: - Data Accessors

    private var openCodePayload: DashboardPayload? {
        openCodeModel.selectedPayload
    }

    private var codexPayload: CodexDashboardPayload? {
        codexModel.payload
    }

    private var resolvedOpenCodePlan: ResolvedBillingPlan {
        appPreferencesModel.preferences.resolvedBillingPlan(for: .opencode)
    }

    // MARK: - Summary Computed Properties

    private var openCodeOverviewCost: Double? {
        guard let payload = openCodePayload else { return nil }
        return appPreferencesModel.preferences.openCodeOverviewCost(payload: payload)
    }

    private var combinedCost: Double? {
        guard let payload = openCodePayload else { return nil }
        return appPreferencesModel.preferences.combinedMonthlyCost(payload: payload)
    }

    private var combinedInputTokens: Double? {
        let oc = openCodePayload?.totalActualInputTokens ?? 0
        let cx = codexPayload?.summary.totalActualInputTokens ?? 0
        guard openCodePayload?.totalActualInputTokens != nil || codexPayload?.summary.totalActualInputTokens != nil else { return nil }
        return oc + cx
    }

    private var combinedTotalActualTokens: Double? {
        let oc = openCodePayload?.summary.totalActualTokens ?? 0
        let cx = codexPayload?.summary.totalActualTokens ?? 0
        guard openCodePayload?.summary != nil || codexPayload?.summary != nil else { return nil }
        return oc + cx
    }

    // MARK: - Sparkline

    private struct SparklinePoint: Identifiable {
        let id: String
        let date: Date
        let dateLabel: String
        let tokens: Double
    }

    private var sparklinePoints: [SparklinePoint] {
        guard let rawData = openCodePayload?.rawData, !rawData.isEmpty else { return [] }

        var dailyTotals: [String: Double] = [:]
        for row in rawData {
            dailyTotals[row.date, default: 0] += (row.input + row.output + row.reasoning)
        }

        let sorted = dailyTotals.sorted { $0.key > $1.key }.prefix(7)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return sorted.compactMap { dateStr, tokens in
            guard let date = formatter.date(from: dateStr) else { return nil }
            return SparklinePoint(id: dateStr, date: date, dateLabel: dateStr, tokens: tokens)
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Section Views

    private func summaryOverview(
        cost: Double?,
        tokens: Double?,
        messages: Int?,
        sessions: Int?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.text("overview.summary.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.subtitle)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 6) {
                miniMetricCard(
                    icon: "dollarsign.circle",
                    label: AppLocalization.text("overview.summary.totalCost"),
                    value: cost.map { TokenCostFormatters.currency($0, displayCurrency: appPreferencesModel.preferences.displayCurrency) },
                    fallback: AppLocalization.text("common.unavailable"),
                    tint: palette.accent
                )
                miniMetricCard(
                    icon: "text.word.spacing",
                    label: AppLocalization.text("overview.summary.totalActualTokens"),
                    value: tokens.map(TokenCostFormatters.tokens),
                    fallback: AppLocalization.text("common.unavailable"),
                    tint: .green
                )
                miniMetricCard(
                    icon: "message",
                    label: AppLocalization.text("tab.opencode"),
                    value: messages.map { "\($0)" },
                    fallback: AppLocalization.text("common.unavailable"),
                    tint: palette.accentSecondary
                )
                miniMetricCard(
                    icon: "terminal",
                    label: AppLocalization.text("tab.codex"),
                    value: sessions.map { "\($0)" },
                    fallback: AppLocalization.text("common.unavailable"),
                    tint: .orange
                )
            }
        }
    }

    private func miniMetricCard(
        icon: String,
        label: String,
        value: String?,
        fallback: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(tint)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(1)
                Text(value ?? fallback)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(value != nil ? palette.title : palette.subtitle)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(palette.cardStroke.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private func sparklineSection(points: [SparklinePoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppLocalization.text("menu.weeklyTrend"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.subtitle)

            Chart(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Tokens", point.tokens)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(palette.accent.opacity(0.12))

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Tokens", point.tokens)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(palette.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 44)
        }
    }

    private func activateMainWindow() {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                NotificationCenter.default.post(name: .openMainWindow, object: nil)
            }
        }
    }

    // MARK: - Balance Summary

    private var sortedSnapshots: [BalanceSnapshot] {
        let order = appPreferencesModel.preferences.balanceSortOrder
        return balanceManager.snapshots.sorted { a, b in
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

    private var balanceSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("实时余额")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.subtitle)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ], spacing: 6) {
                ForEach(sortedSnapshots) { snapshot in
                    balanceCard(snapshot)
                }
            }

            HStack {
                Spacer()
                Button {
                    Task { await balanceManager.refresh(force: true) }
                } label: {
                    HStack(spacing: 4) {
                        if balanceManager.isRefreshing {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        }
                        Text(AppLocalization.text("menu.refreshBalance"))
                    }
                    .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(balanceManager.isRefreshing ? palette.subtitle : palette.accent)
                .disabled(balanceManager.isRefreshing)
            }
        }
    }

    private func balanceCard(_ snapshot: BalanceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(snapshot.isAvailable ? gradientColor(for: snapshot.gradient) : Color.gray.opacity(0.5))
                    .frame(width: 5, height: 5)
                Text(snapshot.provider.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)
            }

            if snapshot.isAvailable {
                if let windows = snapshot.quotaWindows, !windows.isEmpty {
                    ForEach(windows) { w in
                        cardBar(
                            label: w.label,
                            pct: displayRatio(for: w),
                            resetAt: w.resetAt,
                            windowSeconds: w.windowSeconds,
                            consumptionRate: w.consumptionRate
                        )
                    }
                } else if let entries = snapshot.valueEntries, !entries.isEmpty {
                    ForEach(entries) { entry in
                        HStack(spacing: 3) {
                            if let code = entry.currencyCode, !code.isEmpty {
                                Text(code)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(gradientColor(for: .low))
                            }
                            Text(String(format: "%.2f", entry.amount))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(palette.title)
                                .lineLimit(1)
                            if let granted = entry.grantedAmount {
                                Text("(赠\(String(format: "%.0f", granted)))")
                                    .font(.system(size: 8))
                                    .foregroundStyle(palette.subtitle)
                                    .lineLimit(1)
                            }
                        }
                    }
                } else if let primaryPct = snapshot.primaryWindowUsagePercent {
                    cardBar(label: snapshot.primaryWindowLabel, pct: displayRatio(for: primaryPct))
                    if let pct = snapshot.secondaryWindowUsagePercent {
                        cardBar(label: snapshot.secondaryWindowLabel, pct: displayRatio(for: pct))
                    }
                    if let pct = snapshot.tertiaryWindowUsagePercent {
                        cardBar(label: snapshot.tertiaryWindowLabel, pct: displayRatio(for: pct))
                    }
                } else if let cost = snapshot.totalCostUSD {
                    Text("$\(String(format: "%.2f", cost)) 累计")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.title)
                    if let avg = snapshot.avgCostPerDayUSD {
                        Text("日均 $\(String(format: "%.2f", avg))")
                            .font(.system(size: 8))
                            .foregroundStyle(palette.subtitle)
                    }
                } else if let pct = snapshot.usagePercent {
                    cardBar(label: nil, pct: displayRatio(for: pct))
                }
            } else {
                Text(snapshot.errorMessage ?? "不可用")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(palette.cardStroke.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private func cardBar(
        label: String?,
        pct: Double,
        resetAt: Date? = nil,
        windowSeconds: Int? = nil,
        consumptionRate: ConsumptionRate? = nil
    ) -> some View {
        let isShortWindow: Bool = {
            guard let ws = windowSeconds else { return false }
            return ws < 86400
        }()
        let countdownText: String? = {
            guard isShortWindow, let resetAt else { return nil }
            let remaining = max(0, resetAt.timeIntervalSinceNow)
            if remaining <= 0 { return "即将" }
            if remaining < 60 { return "<1m" }
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            if hours > 0 { return "\(hours)h\(minutes)m" }
            return "\(minutes)m"
        }()
        let rateText: String? = {
            guard isShortWindow,
                  let consumptionRate,
                  consumptionRate.confidence > 0 else { return nil }
            return String(format: "~%.1f%%/h", consumptionRate.perHour)
        }()
        let showPending = isShortWindow && (consumptionRate == nil || consumptionRate?.confidence == 0)

        return HStack(spacing: 2) {
            if let label {
                Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(palette.subtitle)
                    .frame(width: 24, alignment: .leading)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(palette.trackBackground)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(cardBarColor(for: pct))
                        .frame(width: geo.size.width * CGFloat(min(pct, 1.0)), height: 4)
                }
            }
            .frame(height: 4)
            Text(pct >= 0.995 ? "满" : "\(Int(pct * 100))")
                .font(.system(size: 8))
                .foregroundStyle(palette.subtitle)
                .frame(width: 16, alignment: .trailing)
                .minimumScaleFactor(0.6)
            if let countdownText {
                Text(countdownText)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(palette.subtitle.opacity(0.6))
                    .minimumScaleFactor(0.6)
            }
            if let rateText {
                Text(rateText)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(palette.accent.opacity(0.75))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } else if showPending {
                Text(AppLocalization.text("balance.rate.pending"))
                    .font(.system(size: 7))
                    .foregroundStyle(palette.subtitle.opacity(0.4))
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private func cardBarColor(for pct: Double) -> Color {
        if appPreferencesModel.preferences.balanceDisplayMode == .remaining {
            if pct > 0.5 { return gradientColor(for: .low) }
            if pct > 0.2 { return gradientColor(for: .moderate) }
            if pct > 0.05 { return gradientColor(for: .high) }
            return gradientColor(for: .critical)
        }
        if pct < 0.5 { return gradientColor(for: .low) }
        if pct < 0.8 { return gradientColor(for: .moderate) }
        if pct < 0.95 { return gradientColor(for: .high) }
        return gradientColor(for: .critical)
    }

    private func displayRatio(for window: BalanceQuotaWindow) -> Double {
        let mode = appPreferencesModel.preferences.balanceDisplayMode
        switch mode {
        case .used: return window.usedRatio ?? 0
        case .remaining: return window.remainingRatio ?? (1.0 - (window.usedRatio ?? 0))
        }
    }

    private func displayRatio(for pct: Double) -> Double {
        switch appPreferencesModel.preferences.balanceDisplayMode {
        case .used: return pct
        case .remaining: return 1.0 - pct
        }
    }

    private func statusIndicator(
        label: String, hasPayload: Bool, isBusy: Bool, statusMessage: String
    ) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(hasPayload ? Color.green : (isBusy ? palette.accent : palette.subtitle.opacity(0.5)))
                .frame(width: 5, height: 5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(palette.subtitle)
                .lineLimit(1)
        }
        .help(statusMessage)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CodexAppPaths.appDisplayName)
                .font(.headline)
                .foregroundStyle(palette.title)
            HStack(spacing: 12) {
                statusIndicator(
                    label: "OpenCode",
                    hasPayload: openCodeModel.selectedPayload != nil,
                    isBusy: openCodeModel.isBootstrapping || openCodeModel.isRefreshing,
                    statusMessage: openCodeModel.statusMessage
                )
                statusIndicator(
                    label: "Codex",
                    hasPayload: codexModel.payload != nil,
                    isBusy: codexModel.isBootstrapping || codexModel.isRefreshing,
                    statusMessage: codexModel.statusMessage
                )
            }
        }
    }

    private func gradientColor(for gradient: UsageGradient) -> Color {
        switch gradient {
        case .unused: return .gray
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .critical: return .red
        case .exceeded: return .red
        case .unknown: return .gray
        }
    }
}
