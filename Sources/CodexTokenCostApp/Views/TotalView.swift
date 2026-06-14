import SwiftUI
import CodexTokenCostCore

struct TotalView: View {
    @ObservedObject var openCodeModel: TokenCostModel
    @ObservedObject var codexModel: CodexSessionModel
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @ObservedObject var balanceManager: BalanceManager
    let palette: TokenCostPalette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                overviewCard
                BalanceOverviewCard(
                    snapshots: balanceManager.snapshots,
                    lastRefreshTime: balanceManager.lastRefreshTime,
                    palette: palette
                )
                openCodeCard
                tokenHeatmapCard
                codexCard
            }
            .padding(20)
        }
        .task {
            openCodeModel.bootstrapIfNeeded()
            codexModel.bootstrapIfNeeded()
        }
    }

    // MARK: - Heatmap data

    private var codexDailyTokens: [String: Double] {
        guard let payload = codexPayload else { return [:] }
        return CodexDashboardAnalytics.dailyTrendPoints(from: payload).reduce(into: [:]) { dict, point in
            dict[point.dateString, default: 0] += point.actualTokens
        }
    }

    private var tokenHeatmapCard: some View {
        TokenSectionCard(
            title: "每日用量热力图",
            subtitle: "过去 52 周 · OpenCode + Codex 合计",
            trailing: nil,
            palette: palette
        ) {
            TokenHeatmapGrid(
                data: TokenHeatmapBuilder.build(
                    fromOpenCodeDaily: openCodeDailyActualTokens,
                    codexDaily: codexDailyTokens,
                    referenceDate: Date()
                ),
                palette: palette
            )
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

    private var codexOverviewCost: Double? {
        resolvedCodexPlan.isSubscribed ? resolvedCodexPlan.monthlyUSD : nil
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
        guard let rawData = openCodePayload?.rawData else { return [:] }
        var result: [String: Double] = [:]
        for row in rawData {
            result[row.date, default: 0] += (row.input + row.output + row.reasoning)
        }
        return result
    }

    private var combinedCost: Double? {
        guard let payload = openCodePayload else { return nil }
        return preferences.combinedMonthlyCost(payload: payload)
    }

    private var nonCodexMonthlyCost: Double? {
        guard let payload = openCodePayload else { return nil }
        return preferences.nonCodexMonthlyCost(payload: payload)
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
                    value: nonCodexMonthlyCost.map { TokenCostFormatters.currency($0, displayCurrency: appPreferencesModel.preferences.displayCurrency) } ?? AppLocalization.text("common.unavailable"),
                    subtitle: AppLocalization.text("overview.openCode.nonCodexCostSubtitle"),
                    tint: palette.accent,
                    palette: palette
                )
                .frame(maxHeight: .infinity, alignment: .topLeading)

                TokenMetricCard(
                    title: AppLocalization.text("overview.summary.codexCost"),
                    value: codexOverviewCost.map { TokenCostFormatters.monthlyCurrency($0, displayCurrency: appPreferencesModel.preferences.displayCurrency) } ?? AppLocalization.text("common.unavailable"),
                    subtitle: resolvedCodexPlan.displayName,
                    tint: palette.accentSecondary,
                    palette: palette
                )
                .frame(maxHeight: .infinity, alignment: .topLeading)

                TokenMetricCard(
                    title: AppLocalization.text("overview.summary.totalCost"),
                    value: combinedCost.map { TokenCostFormatters.currency($0, displayCurrency: appPreferencesModel.preferences.displayCurrency) } ?? AppLocalization.text("common.unavailable"),
                    subtitle: AppLocalization.text("overview.summary.totalCostSubtitle"),
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
                        value: nonCodexMonthlyCost.map {
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
                        subtitle: AppLocalization.text("overview.openCode.cacheTokensSubtitle"),
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
