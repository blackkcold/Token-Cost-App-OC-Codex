import SwiftUI
import CodexTokenCostCore

struct TotalView: View {
    @ObservedObject var openCodeModel: TokenCostModel
    @ObservedObject var codexModel: CodexSessionModel
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @ObservedObject var balanceManager: BalanceManager
    let palette: TokenCostPalette
    @State private var totalTrendDayRange: Int = 30
    @State private var cachedCodexDailyTokens: [String: Double] = [:]
    @State private var cachedOpenCodeDaily: [String: Double] = [:]
    @State private var cachedHeatmapData: TokenHeatmapData?
    @State private var dailyDataRefreshGeneration = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                overviewCard
                BalanceOverviewCard(
                    snapshots: balanceManager.snapshots,
                    lastRefreshTime: balanceManager.lastRefreshTime,
                    palette: palette,
                    appPreferencesModel: appPreferencesModel
                )
                dailyTrendCard
                tokenHeatmapCard
                openCodeCard
                codexCard
            }
            .padding(20)
        }
        .task {
            await refreshCachedDailyData()
        }
        .onChange(of: codexPayload?.summary.updatedAt ?? "") { _, _ in
            Task { await refreshCachedDailyData() }
        }
        .onChange(of: openCodePayload?.summary.updatedAt ?? "") { _, _ in
            Task { await refreshCachedDailyData() }
        }
    }

    // MARK: - Combined daily trend

    /// Merge OpenCode + Codex daily actual tokens into a single dictionary
    private var combinedDailyTokens: [String: Double] {
        var result = openCodeDailyActualTokens
        for (date, tokens) in codexDailyTokens {
            result[date, default: 0] += tokens
        }
        return result
    }

    private var totalTrendPoints: [TokenTrendChartPoint] {
        let allDates = combinedDailyTokens.keys.sorted()
        return allDates.compactMap { dateString -> TokenTrendChartPoint? in
            guard let date = Self.trendDateFormatter.date(from: dateString),
                  let tokens = combinedDailyTokens[dateString] else { return nil }
            let openCodeVal = openCodeDailyActualTokens[dateString] ?? 0
            let codexVal = codexDailyTokens[dateString] ?? 0
            return TokenTrendChartPoint(
                date: date,
                dateString: dateString,
                actualTokens: tokens,
                tooltipLines: [
                    TokenTrendTooltipLine(
                        color: palette.accent,
                        title: "OpenCode",
                        value: TokenCostFormatters.tokens(openCodeVal)
                    ),
                    TokenTrendTooltipLine(
                        color: palette.accentSecondary,
                        title: "Codex",
                        value: TokenCostFormatters.tokens(codexVal)
                    ),
                    TokenTrendTooltipLine(
                        color: .orange,
                        title: "合计",
                        value: TokenCostFormatters.tokens(tokens)
                    )
                ]
            )
        }
    }

    private var dailyTrendCard: some View {
        let visiblePoints = Array(totalTrendPoints.suffix(totalTrendDayRange))
        return TokenSectionCard(
            title: "每日用量趋势",
            subtitle: "近 \(totalTrendDayRange) 日 · OpenCode + Codex 合计",
            trailing: AnyView(TokenTrendRangePicker(selection: $totalTrendDayRange)),
            palette: palette
        ) {
            if visiblePoints.isEmpty {
                Text("暂无数据")
                    .foregroundStyle(palette.subtitle)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .leading)
            } else {
                TokenTrendChartView(points: visiblePoints, palette: palette)
            }
        }
    }

    // MARK: - Heatmap data

    private var codexDailyTokens: [String: Double] {
        cachedCodexDailyTokens
    }

    private var tokenHeatmapCard: some View {
        TokenSectionCard(
            title: "每日用量热力图",
            subtitle: "过去 52 周 · OpenCode + Codex 合计",
            trailing: nil,
            palette: palette
        ) {
            if let data = cachedHeatmapData {
                TokenHeatmapGrid(
                    data: data,
                    palette: palette
                )
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.6)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }

    private var openCodePayload: DashboardPayload? {
        openCodeModel.selectedPayload
    }

    private var codexPayload: CodexDashboardPayload? {
        codexModel.payload
    }

    private var openCodeSummary: DashboardPayload.Summary? {
        openCodePayload?.summary
    }

    private var hasOllamaCloudEstimate: Bool {
        guard let rows = openCodePayload?.rawData else { return false }
        return hasEligibleOllamaCloudEstimate(rows: rows)
    }

    private var codexSummary: CodexDashboardPayload.Summary? {
        codexPayload?.summary
    }

    private var preferences: AppPreferences {
        appPreferencesModel.preferences
    }

    private var resolvedOpenCodePlan: ResolvedBillingPlan {
        preferences.resolvedBillingPlan(for: .opencode)
    }

    private var resolvedCodexPlan: ResolvedBillingPlan {
        preferences.resolvedBillingPlan(for: .codex)
    }

    private var reportingCostBreakdown: ReportingCostBreakdown? {
        guard let payload = openCodePayload else { return nil }
        return appPreferencesModel.reportingCostBreakdown(for: payload)
    }

    private var reportingRangeBasisLabel: String {
        appPreferencesModel.reportingRangeBasisLabel
    }

    private var codexContributionCost: Double? {
        guard let breakdown = reportingCostBreakdown else { return nil }
        return breakdown.fixedCostByProvider[.codex] ?? 0
    }

    private var openCodeNonCodexCost: Double? {
        guard let breakdown = reportingCostBreakdown else { return nil }
        let codex = breakdown.fixedCostByProvider[.codex] ?? 0
        let remainder = breakdown.totalCost - codex
        return remainder > 0 ? remainder : nil
    }

    private var combinedCost: Double? {
        reportingCostBreakdown?.totalCost
    }

    private var openCodeActualInputTokens: Double? {
        openCodePayload?.totalActualInputTokens
    }

    private var combinedActualInputTokens: Double? {
        let oc = openCodeActualInputTokens ?? 0
        let cx = codexSummary?.totalActualInputTokens ?? 0
        guard openCodeActualInputTokens != nil || codexSummary != nil else { return nil }
        return oc + cx
    }

    /// OpenCode + Codex 合并的完整计费 token 总量
    /// 单端缺失时只累加有数据的一端
    private var combinedTotalActualTokens: Double? {
        let oc = openCodeSummary?.totalActualTokens ?? 0
        let cx = codexSummary?.totalActualTokens ?? 0
        guard openCodeSummary != nil || codexSummary != nil else { return nil }
        return oc + cx
    }

    /// OpenCode 每日 actual tokens（input + output + reasoning），不含 cache
    private var openCodeDailyActualTokens: [String: Double] {
        cachedOpenCodeDaily
    }

    private func refreshCachedDailyData() async {
        dailyDataRefreshGeneration += 1
        let generation = dailyDataRefreshGeneration
        let ocRawData = openCodePayload?.rawData
        let codexPayloadValue = codexPayload
        let result = await Task.detached(priority: .userInitiated) {
            var ocDaily: [String: Double] = [:]
            if let rawData = ocRawData {
                for row in rawData {
                    ocDaily[row.date, default: 0] += (row.input + row.output + row.reasoning)
                }
            }

            let cxDaily: [String: Double]
            if let payload = codexPayloadValue {
                cxDaily = CodexDashboardAnalytics.dailyTrendPoints(from: payload).reduce(into: [:]) { dict, point in
                    dict[point.dateString, default: 0] += point.actualTokens
                }
            } else {
                cxDaily = [:]
            }

            let heatmap = TokenHeatmapBuilder.build(
                fromOpenCodeDaily: ocDaily,
                codexDaily: cxDaily,
                referenceDate: Date()
            )
            return (ocDaily, cxDaily, heatmap)
        }.value

        guard generation == dailyDataRefreshGeneration else { return }

        cachedOpenCodeDaily = result.0
        cachedCodexDailyTokens = result.1
        cachedHeatmapData = result.2
    }

    private var overviewCard: some View {
        TokenSectionCard(
            title: AppLocalization.text("overview.summary.title"),
            subtitle: AppLocalization.text("overview.summary.subtitle"),
            trailing: nil,
            palette: palette
        ) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                TokenMetricCard(
                    title: AppLocalization.text("overview.summary.openCodeCost"),
                    value: openCodeNonCodexCost.map { TokenCostFormatters.currency($0, displayCurrency: appPreferencesModel.preferences.displayCurrency) } ?? AppLocalization.text("common.unavailable"),
                    subtitle: reportingCostBreakdown == nil
                        ? AppLocalization.text("overview.openCode.nonCodexCostSubtitle")
                        : "\(AppLocalization.text("overview.openCode.nonCodexCostSubtitle")) · \(reportingRangeBasisLabel)",
                    tint: palette.accent,
                    palette: palette
                )
                .frame(maxHeight: .infinity, alignment: .topLeading)

                TokenMetricCard(
                    title: AppLocalization.text("overview.summary.codexCost"),
                    value: codexContributionCost.map { TokenCostFormatters.currency($0, displayCurrency: appPreferencesModel.preferences.displayCurrency) } ?? AppLocalization.text("common.unavailable"),
                    subtitle: reportingCostBreakdown == nil
                        ? resolvedCodexPlan.displayName
                        : "\(resolvedCodexPlan.displayName) · \(reportingRangeBasisLabel)",
                    tint: palette.accentSecondary,
                    palette: palette
                )
                .frame(maxHeight: .infinity, alignment: .topLeading)

                    TokenMetricCard(
                        title: AppLocalization.text("overview.summary.totalCost"),
                        value: combinedCost.map { TokenCostFormatters.currency($0, displayCurrency: appPreferencesModel.preferences.displayCurrency) } ?? AppLocalization.text("common.unavailable"),
                        subtitle: reportingCostBreakdown == nil
                            ? AppLocalization.text("overview.summary.totalCostSubtitle")
                            : reportingRangeBasisLabel,
                        tint: .orange,
                        palette: palette
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                TokenMetricCard(
                    title: AppLocalization.text("overview.summary.totalActualTokens"),
                    value: combinedTotalActualTokens.map(TokenCostFormatters.tokens) ?? AppLocalization.text("common.unavailable"),
                    subtitle: AppLocalization.text("overview.summary.totalActualTokensSubtitle"),
                    tint: .green,
                    palette: palette
                )
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var openCodeCard: some View {
        TokenSectionCard(
            title: AppLocalization.text("overview.openCode.title"),
            subtitle: AppLocalization.format("overview.openCode.subtitle", resolvedOpenCodePlan.displayName),
            trailing: nil,
            palette: palette
        ) {
            if let summary = openCodeSummary {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    TokenMetricCard(
                        title: AppLocalization.text("overview.openCode.actualTokens"),
                        value: (openCodeSummary?.totalActualTokens).map(TokenCostFormatters.tokens) ?? AppLocalization.text("common.unavailable"),
                        subtitle: AppLocalization.text("overview.openCode.actualTokensSubtitle"),
                        tint: palette.accent,
                        palette: palette
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                    TokenMetricCard(
                        title: AppLocalization.text("overview.openCode.totalCost"),
                        value: openCodeNonCodexCost.map {
                            TokenCostFormatters.currency($0, displayCurrency: appPreferencesModel.preferences.displayCurrency)
                        } ?? AppLocalization.text("common.unavailable"),
                        subtitle: AppLocalization.text("overview.openCode.nonCodexCostSubtitle"),
                        tint: palette.accentSecondary,
                        palette: palette
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                    TokenMetricCard(
                        title: AppLocalization.text("overview.openCode.cacheTokens"),
                        value: TokenCostFormatters.tokens(summary.totalCacheTokens),
                        subtitle: hasOllamaCloudEstimate
                            ? AppLocalization.text("overview.openCode.cacheTokensSubtitleExcludesEstimate")
                            : AppLocalization.text("overview.openCode.cacheTokensSubtitle"),
                        tint: .green,
                        palette: palette
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                    TokenMetricCard(
                        title: AppLocalization.text("overview.openCode.messages"),
                        value: "\(summary.totalMessages)",
                        subtitle: AppLocalization.format("overview.openCode.activeDaysSubtitle", summary.activeDays),
                        tint: .orange,
                        palette: palette
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                }

                Text(AppLocalization.format(
                    "overview.openCode.dateRange",
                    summary.dateRange.start ?? AppLocalization.text("common.unavailable"),
                    summary.dateRange.end ?? AppLocalization.text("common.unavailable")
                ))
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .padding(.top, 4)
            } else {
                Text(openCodeModel.statusMessage)
                    .foregroundStyle(palette.subtitle)
            }
        }
    }

    private static let trendDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private var codexCard: some View {
        TokenSectionCard(
            title: AppLocalization.text("overview.codex.title"),
            subtitle: AppLocalization.text("overview.codex.subtitle"),
            trailing: nil,
            palette: palette
        ) {
            if let summary = codexSummary {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    TokenMetricCard(
                        title: AppLocalization.text("overview.codex.actualInput"),
                        value: TokenCostFormatters.tokens(summary.totalActualInputTokens),
                        subtitle: AppLocalization.text("overview.codex.actualInputSubtitle"),
                        tint: palette.accent,
                        palette: palette
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                    TokenMetricCard(
                        title: AppLocalization.text("overview.codex.outputTokens"),
                        value: TokenCostFormatters.tokens(summary.totalOutputTokens),
                        subtitle: AppLocalization.text("overview.codex.outputTokensSubtitle"),
                        tint: palette.accentSecondary,
                        palette: palette
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                    TokenMetricCard(
                        title: AppLocalization.text("overview.codex.reasoningTokens"),
                        value: TokenCostFormatters.tokens(summary.totalReasoningOutputTokens),
                        subtitle: AppLocalization.text("overview.codex.reasoningTokensSubtitle"),
                        tint: .purple,
                        palette: palette
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                    TokenMetricCard(
                        title: AppLocalization.text("overview.codex.cachedInput"),
                        value: TokenCostFormatters.tokens(summary.totalCachedInputTokens),
                        subtitle: AppLocalization.text("overview.codex.cachedInputSubtitle"),
                        tint: .orange,
                        palette: palette
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                }
                HStack {
                    Text(AppLocalization.format("overview.codex.sessionCount", summary.sessionCount))
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                    Spacer(minLength: 12)
                    Text(AppLocalization.format("overview.codex.updatedAt", summary.updatedAt))
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                }
                .padding(.top, 4)
            } else {
                Text(codexModel.statusMessage)
                    .foregroundStyle(palette.subtitle)
            }
        }
    }
}

func hasEligibleOllamaCloudEstimate(rows: [DashboardPayload.RawRow]) -> Bool {
    rows.contains { row in
        guard row.provider == "ollama-cloud",
              row.cacheRead == 0,
              row.input > 0,
              row.input.isFinite else {
            return false
        }

        let normalizedModel = OllamaCloudCacheEstimation.normalizedModelName(row.model)
        return normalizedModel == "deepseek-v4-flash" || normalizedModel == "deepseek-v4-pro"
    }
}
