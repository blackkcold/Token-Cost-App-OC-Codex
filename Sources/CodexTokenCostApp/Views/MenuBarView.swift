import AppKit
import Charts
import SwiftUI
import CodexTokenCostCore

struct MenuBarView: View {
    @ObservedObject var openCodeModel: TokenCostModel
    @ObservedObject var codexModel: CodexSessionModel
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @ObservedObject var balanceManager: BalanceManager
    let balanceFloatingPanelCoordinator: BalanceFloatingPanelCoordinator
    let palette: TokenCostPalette
    @Environment(\.openWindow) private var openWindow

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
                balanceFloatingPanelCoordinator.toggleFromMenuBar()
            } label: {
                Label(AppLocalization.text("menu.balanceFloatingPanel.title"), systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .settingsGlassButtonStyle(prominent: appPreferencesModel.preferences.balanceFloatingPanelEnabled)
            .controlSize(.small)
            .help(
                appPreferencesModel.preferences.balanceFloatingPanelEnabled
                ? AppLocalization.text("menu.balanceFloatingPanel.hide")
                : AppLocalization.text("menu.balanceFloatingPanel.show")
            )
            .accessibilityLabel(
                appPreferencesModel.preferences.balanceFloatingPanelEnabled
                ? AppLocalization.text("menu.balanceFloatingPanel.hide")
                : AppLocalization.text("menu.balanceFloatingPanel.show")
            )

            Divider()
            HStack(spacing: 8) {
                Button {
                    activateMainWindow()
                } label: {
                    Label(AppLocalization.text("menu.openMainWindow"), systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .settingsGlassButtonStyle(prominent: true)
                .controlSize(.small)

                Button {
                    openCodeModel.rescanSources()
                    codexModel.refresh()
                } label: {
                    Label(AppLocalization.text("menu.refreshAll"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .settingsGlassButtonStyle(prominent: false)
                .controlSize(.small)
                .disabled(openCodeModel.isBootstrapping || openCodeModel.isRefreshing || codexModel.isBootstrapping || codexModel.isRefreshing)

                Button {
                    WindowOpeningSupport.openWindow(id: "settings", openWindow: openWindow)
                } label: {
                    Label(AppLocalization.text("menu.openSettings"), systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .settingsGlassButtonStyle(prominent: false)
                .controlSize(.small)
            }
            Divider()
            HStack {
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help(AppLocalization.text("menu.quit"))
                .accessibilityLabel(AppLocalization.text("menu.quit"))
            }
        }
        .frame(width: 340)
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

    private var reportingCostBreakdown: ReportingCostBreakdown? {
        guard let payload = openCodePayload else { return nil }
        return appPreferencesModel.reportingCostBreakdown(for: payload)
    }

    private var combinedCost: Double? {
        reportingCostBreakdown?.totalCost
    }

    private var totalCostBasisLabel: String? {
        guard combinedCost != nil else { return nil }
        return appPreferencesModel.reportingRangeBasisLabel
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
                    tint: palette.accent,
                    subtitle: totalCostBasisLabel
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
        tint: Color,
        subtitle: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(1)
                Text(value ?? fallback)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(value != nil ? palette.title : palette.subtitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
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
            .frame(height: 60)
        }
    }

    private func activateMainWindow() {
        WindowOpeningSupport.openWindow(id: "main", openWindow: openWindow)
    }

    // MARK: - Balance Summary

    private var sortedSnapshots: [BalanceSnapshot] {
        appPreferencesModel.sortBalanceSnapshots(balanceManager.snapshots)
    }

    private var balanceSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AppLocalization.text("balance.title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.subtitle)
                Spacer()
                Button {
                    Task { await balanceManager.refresh(force: true) }
                } label: {
                    if balanceManager.isRefreshing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(balanceManager.isRefreshing ? palette.subtitle : palette.accent)
                .disabled(balanceManager.isRefreshing)
                .help(AppLocalization.text("menu.refreshBalance"))
                .accessibilityLabel(AppLocalization.text("menu.refreshBalance"))
            }

            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Array(stride(from: 0, to: sortedSnapshots.count, by: 2)), id: \.self) { startIndex in
                    GridRow {
                        balanceCard(sortedSnapshots[startIndex])
                        if startIndex + 1 < sortedSnapshots.count {
                            balanceCard(sortedSnapshots[startIndex + 1])
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let rateLabel = consumptionRateLabel(for: snapshot) {
                    Text(rateLabel.text)
                        .font(.caption2)
                        .foregroundStyle(rateLabel.isPending
                                        ? palette.subtitle.opacity(0.4)
                                        : palette.accent.opacity(0.75))
                        .fixedSize(horizontal: true, vertical: false)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            if snapshot.isAvailable {
                if let windows = snapshot.quotaWindows, !windows.isEmpty {
                    ForEach(windows) { w in
                        cardBar(
                            label: w.label,
                            pct: displayRatio(for: w),
                            resetAt: w.resetAt,
                            windowSeconds: w.windowSeconds
                        )
                    }
                } else if let entries = snapshot.valueEntries, !entries.isEmpty {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(BalanceMenuBarExtraSupport.amountText(for: entry))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(palette.title)
                                .lineLimit(1)
                            if let burnRateText = BalanceMenuBarExtraSupport.burnRateText(for: entry) {
                                Text(burnRateText)
                                    .font(.caption2)
                                    .foregroundStyle(palette.accent.opacity(0.8))
                                    .lineLimit(1)
                            }
                            if let granted = entry.grantedAmount {
                                Text(AppLocalization.format("balance.value.grantedShort", String(format: "%.0f", granted)))
                                    .font(.caption2)
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
                    Text(AppLocalization.format("balance.cost.total", String(format: "%.2f", cost)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.title)
                    if let avg = snapshot.avgCostPerDayUSD {
                        Text(AppLocalization.format("balance.cost.dailyAverage", String(format: "%.2f", avg)))
                            .font(.caption2)
                            .foregroundStyle(palette.subtitle)
                    }
                } else if let pct = snapshot.usagePercent {
                    cardBar(label: nil, pct: displayRatio(for: pct))
                }
            } else {
                Text(snapshot.errorMessage ?? AppLocalization.text("common.unavailable"))
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        windowSeconds: Int? = nil
    ) -> some View {
        let isShortWindow: Bool = {
            guard let ws = windowSeconds else { return false }
            return ws < 86400
        }()
        let countdownText: String? = {
            guard isShortWindow, let resetAt else { return nil }
            let remaining = max(0, resetAt.timeIntervalSinceNow)
            if remaining <= 0 { return AppLocalization.text("balance.rate.countdownSoon") }
            if remaining < 60 { return "<1m" }
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            if hours > 0 { return "\(hours)h\(minutes)m" }
            return "\(minutes)m"
        }()
        return HStack(spacing: 2) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .fixedSize(horizontal: true, vertical: false)
                    .minimumScaleFactor(0.9)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(palette.trackBackground)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(cardBarColor(for: pct))
                        .frame(width: geo.size.width * CGFloat(min(pct, 1.0)), height: 5)
                }
            }
            .frame(height: 5)
            .layoutPriority(-1)
            Text(pct >= 0.995 ? AppLocalization.text("balance.rate.fullShort") : "\(Int(pct * 100))")
                .font(.caption)
                .foregroundStyle(palette.subtitle)
                .fixedSize(horizontal: true, vertical: false)
                .minimumScaleFactor(0.9)
                .lineLimit(1)
            if let countdownText {
                Text(countdownText)
                    .font(.caption)
                    .foregroundStyle(palette.subtitle.opacity(0.6))
                    .minimumScaleFactor(0.9)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func consumptionRateLabel(for snapshot: BalanceSnapshot) -> (text: String, isPending: Bool)? {
        guard let windows = snapshot.quotaWindows, !windows.isEmpty else { return nil }

        let shortest = windows.min {
            ($0.windowSeconds ?? Int.max) < ($1.windowSeconds ?? Int.max)
        }
        guard let window = shortest else { return nil }

        if let rate = window.consumptionRate, rate.confidence > 0 {
            let isShort = (window.windowSeconds ?? Int.max) < 86400
            let text = isShort
                ? AppLocalization.format("balance.rate.perHour", rate.perHour)
                : AppLocalization.format("balance.rate.perDay", rate.perDay)
            return (text, false)
        }

        return (AppLocalization.text("balance.rate.pending"), true)
    }

    private func cardBarColor(for pct: Double) -> Color {
        BalanceMenuBarExtraSupport.quotaColor(
            forDisplayRatio: pct,
            displayMode: appPreferencesModel.preferences.balanceDisplayMode,
            palette: palette
        )
    }

    private func displayRatio(for window: BalanceQuotaWindow) -> Double {
        BalanceMenuBarExtraSupport.displayRatio(for: window, displayMode: appPreferencesModel.preferences.balanceDisplayMode)
    }

    private func displayRatio(for pct: Double) -> Double {
        BalanceMenuBarExtraSupport.displayRatio(for: pct, displayMode: appPreferencesModel.preferences.balanceDisplayMode)
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
            if let cost = combinedCost {
                Text(TokenCostFormatters.currency(cost, displayCurrency: appPreferencesModel.preferences.displayCurrency))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.accent)
            }
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
