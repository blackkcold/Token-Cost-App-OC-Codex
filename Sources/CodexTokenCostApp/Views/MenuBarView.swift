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
        let matrixCells = matrixCells
        let hasSummary = cost != nil || tokens != nil
        let chartStyle = appPreferencesModel.preferences.menuBarChartStyle

        VStack(alignment: .leading, spacing: 12) {
            header

            if hasSummary {
                TokenThemedDivider(palette: palette)
                summaryOverview(cost: cost, tokens: tokens, messages: messages, sessions: sessions)
            }

            switch chartStyle {
            case .sparkline:
                if points.count >= 2 {
                    TokenThemedDivider(palette: palette)
                    sparklineSection(points: points)
                }
            case .matrix:
                if !matrixCells.isEmpty {
                    TokenThemedDivider(palette: palette)
                    matrixSection(cells: matrixCells)
                }
            }
            if appPreferencesModel.preferences.balanceEnabled,
               !balanceManager.snapshots.isEmpty {
                TokenThemedDivider(palette: palette)
                balanceSummary
            }

            TokenThemedDivider(palette: palette)
            Button {
                balanceFloatingPanelCoordinator.toggleFromMenuBar()
            } label: {
                Label(AppLocalization.text("menu.balanceFloatingPanel.title"), systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .dashboardButtonStyle(
                palette: palette,
                compact: true,
                fallback: appPreferencesModel.preferences.balanceFloatingPanelEnabled
                    ? .settingsGlassProminent
                    : .settingsGlass
            )
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

            TokenThemedDivider(palette: palette)
            HStack(spacing: 8) {
                Button {
                    activateMainWindow()
                } label: {
                    Label(AppLocalization.text("menu.openMainWindow"), systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .dashboardButtonStyle(palette: palette, compact: true, fallback: .settingsGlassProminent)
                .controlSize(.small)

                Button {
                    openCodeModel.rescanSources()
                    codexModel.refresh()
                } label: {
                    Label(AppLocalization.text("menu.refreshAll"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .dashboardButtonStyle(palette: palette, compact: true, fallback: .settingsGlass)
                .controlSize(.small)
                .disabled(openCodeModel.isBootstrapping || openCodeModel.isRefreshing || codexModel.isBootstrapping || codexModel.isRefreshing)

                Button {
                    WindowOpeningSupport.openWindow(id: "settings", openWindow: openWindow)
                } label: {
                    Label(AppLocalization.text("menu.openSettings"), systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .dashboardButtonStyle(palette: palette, compact: true, fallback: .settingsGlass)
                .controlSize(.small)
            }
            TokenThemedDivider(palette: palette)
            HStack {
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 13))
                }
                .dashboardButtonStyle(palette: palette, compact: true, fallback: .plain)
                .help(AppLocalization.text("menu.quit"))
                .accessibilityLabel(AppLocalization.text("menu.quit"))
            }
        }
        .frame(width: 340)
        .padding(TokenSpacing.control)
        .background {
            if palette.usesWorkshopStyle {
                palette.pageBackground
            }
        }
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
                .font(TokenTypography.caption(weight: .bold, palette: palette))
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
            TokenDashboardSymbolMark(
                systemImage: icon,
                tint: tint,
                palette: palette,
                size: 18,
                fontSize: 8
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(TokenTypography.caption(palette: palette))
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(1)
                Text(value ?? fallback)
                    .font(TokenTypography.metric(size: 12, palette: palette))
                    .foregroundStyle(value != nil ? palette.title : palette.subtitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let subtitle {
                    Text(subtitle)
                        .font(TokenTypography.metric(size: 9, weight: .medium, palette: palette))
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: palette.usesWorkshopStyle ? 5 : TokenRadius.compact, style: .continuous)
                .fill(palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: palette.usesWorkshopStyle ? 5 : TokenRadius.compact, style: .continuous)
                        .strokeBorder(
                            palette.cardStroke.opacity(palette.usesWorkshopStyle ? 1 : 0.6),
                            lineWidth: palette.usesWorkshopStyle ? 1.6 : 1
                        )
                )
                .shadow(
                    color: palette.usesWorkshopStyle ? palette.cardShadow.opacity(0.5) : .clear,
                    radius: 0,
                    x: palette.usesWorkshopStyle ? 2 : 0,
                    y: palette.usesWorkshopStyle ? 2 : 0
                )
        )
    }

    private func sparklineSection(points: [SparklinePoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppLocalization.text("menu.weeklyTrend"))
                .font(TokenTypography.caption(weight: .bold, palette: palette))
                .foregroundStyle(palette.subtitle)

            Chart(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Tokens", point.tokens)
                )
                .interpolationMethod(palette.usesWorkshopStyle ? .linear : .monotone)
                .foregroundStyle(palette.usesWorkshopStyle ? palette.accent.opacity(0.08) : palette.accent.opacity(0.12))

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Tokens", point.tokens)
                )
                .interpolationMethod(palette.usesWorkshopStyle ? .linear : .monotone)
                .foregroundStyle(palette.accent)
                .lineStyle(
                    palette.usesWorkshopStyle
                        ? StrokeStyle(lineWidth: 2.5, lineCap: .butt, lineJoin: .miter)
                        : StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )

                if palette.usesWorkshopStyle {
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Tokens", point.tokens)
                    )
                    .symbol(.square)
                    .symbolSize(18)
                    .foregroundStyle(palette.accentSecondary)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 60)
        }
    }

    // MARK: - 4-Week Matrix

    private struct MatrixCell: Identifiable {
        let id: String
        let date: Date
        let tokens: Double
        var intensity: Double
    }

    private var matrixCells: [MatrixCell] {
        guard let rawData = openCodePayload?.rawData, !rawData.isEmpty else { return [] }

        var dailyTotals: [String: Double] = [:]
        for row in rawData {
            dailyTotals[row.date, default: 0] += (row.input + row.output + row.reasoning)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        guard let windowStart = calendar.date(byAdding: .day, value: -27, to: today) else { return [] }

        var cells: [MatrixCell] = []
        var maxTokens: Double = 1
        for dayOffset in 0..<28 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: windowStart) else { continue }
            if date > today { continue }
            let dateString = formatter.string(from: date)
            let tokens = dailyTotals[dateString] ?? 0
            maxTokens = max(maxTokens, tokens)
            cells.append(
                MatrixCell(
                    id: dateString,
                    date: date,
                    tokens: tokens,
                    intensity: 0
                )
            )
        }
        for index in cells.indices {
            cells[index].intensity = cells[index].tokens / maxTokens
        }
        return cells
    }

    private func matrixSection(cells: [MatrixCell]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AppLocalization.text("menu.monthlyMatrix"))
                    .font(TokenTypography.caption(weight: .bold, palette: palette))
                    .foregroundStyle(palette.subtitle)
                Spacer()
                Text(AppLocalization.format("menu.monthlyMatrix.range", 4))
                    .font(TokenTypography.caption2(palette: palette))
                    .foregroundStyle(palette.subtitle)
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(cells) { cell in
                    RoundedRectangle(cornerRadius: palette.usesWorkshopStyle ? 0 : 3, style: .continuous)
                        .fill(matrixColor(intensity: cell.intensity))
                        .aspectRatio(1, contentMode: .fit)
                        .help("\(cell.id): \(Int(cell.tokens)) tokens")
                }
            }

            HStack(spacing: 4) {
                Text(AppLocalization.text("menu.monthlyMatrix.less"))
                    .font(TokenTypography.caption2(palette: palette))
                    .foregroundStyle(palette.subtitle)
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { lvl in
                    RoundedRectangle(cornerRadius: palette.usesWorkshopStyle ? 0 : 2, style: .continuous)
                        .fill(matrixColor(intensity: lvl))
                        .frame(width: 8, height: 8)
                }
                Text(AppLocalization.text("menu.monthlyMatrix.more"))
                    .font(TokenTypography.caption2(palette: palette))
                    .foregroundStyle(palette.subtitle)
            }
        }
    }

    private func matrixColor(intensity: Double) -> Color {
        guard intensity > 0 else {
            return palette.usesWorkshopStyle
                ? palette.surfaceSecondarySolidFill
                : palette.accent.opacity(0.06)
        }
        let clamped = min(max(intensity, 0), 1)
        if palette.usesWorkshopStyle {
            return clamped < 0.5
                ? palette.accentSecondary.opacity(0.30 + clamped)
                : palette.accent.opacity(0.35 + clamped * 0.65)
        }
        return palette.accent.opacity(0.10 + clamped * 0.90)
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
                    .font(TokenTypography.caption(weight: .bold, palette: palette))
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
                .dashboardButtonStyle(palette: palette, compact: true, fallback: .plain)
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
                    .font(TokenTypography.caption(weight: .bold, palette: palette))
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
                                .font(TokenTypography.caption(weight: .medium, palette: palette))
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
            RoundedRectangle(cornerRadius: palette.usesWorkshopStyle ? 5 : 8, style: .continuous)
                .fill(palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: palette.usesWorkshopStyle ? 5 : 8, style: .continuous)
                        .strokeBorder(
                            palette.cardStroke.opacity(palette.usesWorkshopStyle ? 1 : 0.6),
                            lineWidth: palette.usesWorkshopStyle ? 1.6 : 1
                        )
                )
                .shadow(
                    color: palette.usesWorkshopStyle ? palette.cardShadow.opacity(0.5) : .clear,
                    radius: 0,
                    x: palette.usesWorkshopStyle ? 2 : 0,
                    y: palette.usesWorkshopStyle ? 2 : 0
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
                    RoundedRectangle(cornerRadius: palette.usesWorkshopStyle ? 0 : 1.5, style: .continuous)
                        .fill(palette.trackBackground)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: palette.usesWorkshopStyle ? 0 : 1.5, style: .continuous)
                        .fill(cardBarColor(for: pct))
                        .frame(width: geo.size.width * CGFloat(min(pct, 1.0)), height: 5)
                }
            }
            .frame(height: 5)
            .overlay(
                Rectangle()
                    .strokeBorder(
                        palette.usesWorkshopStyle ? palette.surfaceAccessibleStroke : .clear,
                        lineWidth: palette.usesWorkshopStyle ? 0.8 : 0
                    )
            )
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
                .font(TokenTypography.caption2(palette: palette))
                .foregroundStyle(palette.subtitle)
                .lineLimit(1)
        }
        .help(statusMessage)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CodexAppPaths.appDisplayName)
                .font(TokenTypography.headline(weight: .bold, palette: palette))
                .foregroundStyle(palette.title)
            if let cost = combinedCost {
                Text(TokenCostFormatters.currency(cost, displayCurrency: appPreferencesModel.preferences.displayCurrency))
                    .font(TokenTypography.metric(size: 22, weight: .bold, palette: palette))
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
        case .low: return palette.success
        case .moderate: return palette.warning.opacity(0.82)
        case .high: return palette.warning
        case .critical: return palette.danger
        case .exceeded: return palette.danger
        case .unknown: return .gray
        }
    }
}
