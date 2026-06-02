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
        let tokens = combinedInputTokens
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
        guard let openCodeTokens = openCodePayload?.totalActualInputTokens,
              let codexTokens = codexPayload?.summary.totalActualInputTokens else { return nil }
        return openCodeTokens + codexTokens
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
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title.contains("Token Cost") || $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Balance Summary

    private var balanceSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("实时余额")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.subtitle)

            ForEach(balanceManager.snapshots) { snapshot in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(gradientColor(for: snapshot.gradient))
                            .frame(width: 5, height: 5)
                        Text(snapshot.provider.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.title)
                    }

                    if snapshot.primaryWindowUsagePercent != nil {
                        HStack(spacing: 4) {
                            if let pct = snapshot.primaryWindowUsagePercent {
                                miniBar(label: snapshot.primaryWindowLabel, pct: pct)
                            }
                            if let pct = snapshot.secondaryWindowUsagePercent {
                                miniBar(label: snapshot.secondaryWindowLabel, pct: pct)
                            }
                            if let pct = snapshot.tertiaryWindowUsagePercent {
                                miniBar(label: snapshot.tertiaryWindowLabel, pct: pct)
                            }
                        }
                    } else if let cost = snapshot.totalCostUSD {
                        Text("$\(String(format: "%.2f", cost)) 累计")
                            .font(.caption2)
                            .foregroundStyle(palette.subtitle)
                    } else {
                        Text(snapshot.shortSummary)
                            .font(.caption2)
                            .foregroundStyle(palette.subtitle)
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    Task { await balanceManager.refresh() }
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

    private func miniBar(label: String?, pct: Double) -> some View {
        HStack(spacing: 2) {
            if let label {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(palette.subtitle)
                    .frame(width: 18, alignment: .leading)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(palette.trackBackground)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(gradientColor(for: pct < 0.5 ? .low : pct < 0.8 ? .moderate : pct < 0.95 ? .high : .critical))
                        .frame(width: geo.size.width * CGFloat(min(pct, 1.0)), height: 5)
                }
            }
            .frame(width: 36, height: 5)
            Text("\(Int(pct * 100))%")
                .font(.system(size: 9))
                .foregroundStyle(palette.subtitle)
                .frame(width: 24, alignment: .trailing)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CodexAppPaths.appDisplayName)
                .font(.headline)
                .foregroundStyle(palette.title)

            Text(openCodeModel.statusMessage)
                .font(.caption)
                .foregroundStyle(palette.subtitle)
                .lineLimit(2)

            Text(codexModel.statusMessage)
                .font(.caption2)
                .foregroundStyle(palette.subtitle)
                .lineLimit(2)

            if let source = openCodeModel.selectedSource, let payload = openCodeModel.selectedPayload {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.title)
                        Text(TokenCostFormatters.tokens(payload.summary.totalActualTokens))
                            .font(.caption)
                            .foregroundStyle(palette.subtitle)
                    }
                    Spacer()
                }
            } else if let payload = codexModel.payload {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLocalization.text("common.codex"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.title)
                        Text(TokenCostFormatters.tokens(payload.summary.totalActualTokens))
                            .font(.caption)
                            .foregroundStyle(palette.subtitle)
                    }
                    Spacer()
                }
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
