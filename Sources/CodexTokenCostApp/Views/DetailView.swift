import Charts
import SwiftUI
import CodexTokenCostCore

struct DetailView: View {
    @ObservedObject var model: TokenCostModel
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @ObservedObject var balanceManager: BalanceManager
    let palette: TokenCostPalette

    @State private var detailSortField: TokenCostDetailSortField = .date
    @State private var detailSortDirection: TokenCostSortDirection = .descending
    @State private var detailPageIndex = 0
    @State private var stackedPageIndex = 0
    @State private var modelComparisonExpanded = false
    @State private var distributionCardHeight: CGFloat = 0
    @State private var trendDayRange: Int = 30

    private let recentWindowLimit = 100
    private let sectionPageSize = 20
    private let modelComparisonCollapsedLimit = 10
    private var overviewColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 140), spacing: 12), count: 5)
    }
    private var cacheColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 150), spacing: 12), count: 5)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let source = model.selectedSource {
                    sourceHeader(source)

                    if let payload = model.selectedPayload {
                        let analytics = TokenCostDashboardAnalytics(
                            payload: payload,
                            showZeroUsageXiaomiProvider: model.settings.showZeroUsageXiaomiProvider,
                            billingOverridesByProviderKey: appPreferencesModel.preferences.billingOverridesByProviderKey()
                        )

                        overviewSection(analytics)
                        trendSection(analytics)
                        cacheSection(analytics)
                        providerRankingSection(analytics)
                        modelComparisonSection(analytics)
                        distributionSection(analytics)
                        stackedSection(analytics)
                        detailSection(analytics)

                        BalanceOverviewCard(
                            snapshots: balanceManager.snapshots.filter {
                                $0.provider == .opencodeGo || $0.provider == .opencodeZen
                            },
                            lastRefreshTime: balanceManager.lastRefreshTime,
                            palette: palette
                        )
                    } else if model.isBootstrapping || model.isRefreshing {
                        loadingCard
                    } else {
                        emptyPayloadCard(source: source)
                    }
                } else {
                    emptyStateCard
                }
            }
            .padding(20)
        }
        .task {
            model.bootstrapIfNeeded()
            model.refreshSelectedSourceIfNeeded()
        }
        .onChange(of: model.selectedPayload?.summary.updatedAt ?? "") { _, _ in
            detailPageIndex = 0
            stackedPageIndex = 0
            modelComparisonExpanded = false
        }
    }

    private func sourceHeader(_ source: TokenCostSource) -> some View {
        TokenSectionCard(
            title: source.name,
            subtitle: source.displayPath,
            trailing: AnyView(SourceStatusPill(source: source, palette: palette)),
            palette: palette
        ) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                TokenMetricCard(
                    title: AppLocalization.text("detail.source.status"),
                    value: source.statusMessage,
                    subtitle: source.isReadOnly ? AppLocalization.text("common.readOnly") : AppLocalization.text("common.writable"),
                    tint: palette.accent,
                    palette: palette
                )
                .frame(maxHeight: .infinity, alignment: .topLeading)

                TokenMetricCard(
                    title: AppLocalization.text("detail.source.modifiedAt"),
                    value: TokenCostFormatters.localDateTime(source.lastModified),
                    subtitle: "\(source.sourceFamily.displayName) · \(source.locationKind.displayName)",
                    tint: palette.accentSecondary,
                    palette: palette
                )
                .frame(maxHeight: .infinity, alignment: .topLeading)

                TokenMetricCard(
                    title: AppLocalization.text("detail.source.path"),
                    value: source.sourceURL.lastPathComponent,
                    subtitle: source.locationURL?.path ?? source.displayPath,
                    tint: .orange,
                    palette: palette
                )
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func overviewSection(_ analytics: TokenCostDashboardAnalytics) -> some View {
        TokenSectionCard(
            title: AppLocalization.text("detail.overview.title"),
            subtitle: AppLocalization.text("detail.overview.subtitle"),
            trailing: nil,
            palette: palette
        ) {
            LazyVGrid(columns: overviewColumns, spacing: 12) {
                TokenMetricCard(
                    title: AppLocalization.text("detail.overview.actualTokens"),
                    value: TokenCostFormatters.tokens(analytics.overview.totalActualTokens),
                    subtitle: AppLocalization.format("detail.overview.actualTokensSubtitle", analytics.overview.totalMessages),
                    tint: palette.accent,
                    palette: palette,
                    compact: true
                )
                TokenMetricCard(
                    title: AppLocalization.text("detail.overview.totalCost"),
                    value: TokenCostFormatters.currency(analytics.overview.totalCost, displayCurrency: appPreferencesModel.preferences.displayCurrency),
                    subtitle: AppLocalization.text("detail.overview.totalCostSubtitle"),
                    tint: .green,
                    palette: palette,
                    compact: true
                )
                TokenMetricCard(
                    title: AppLocalization.text("detail.overview.dailyAverage"),
                    value: TokenCostFormatters.tokens(analytics.overview.dailyAverage),
                    subtitle: AppLocalization.format("detail.overview.activeDays", analytics.overview.activeDays),
                    tint: palette.accentSecondary,
                    palette: palette,
                    compact: true
                )
                TokenMetricCard(
                    title: AppLocalization.text("detail.overview.monthlyEstimate"),
                    value: TokenCostFormatters.tokens(analytics.overview.monthlyEstimate),
                    subtitle: AppLocalization.text("detail.overview.monthlyEstimateSubtitle"),
                    tint: .orange,
                    palette: palette,
                    compact: true
                )
                TokenMetricCard(
                    title: AppLocalization.text("detail.overview.averagePerRequest"),
                    value: TokenCostFormatters.tokens(analytics.overview.averagePerRequest),
                    subtitle: AppLocalization.text("detail.overview.averagePerRequestSubtitle"),
                    tint: .purple,
                    palette: palette,
                    compact: true
                )
            }
        }
    }

    private func trendSection(_ analytics: TokenCostDashboardAnalytics) -> some View {
        let points = Array(analytics.trendPoints.suffix(trendDayRange)).map(openCodeTrendPoint)
        return TokenSectionCard(
            title: AppLocalization.text("detail.trend.title"),
            subtitle: "\(AppLocalization.text("detail.trend.subtitle")) · 近 \(trendDayRange) 日",
            trailing: AnyView(TokenTrendRangePicker(selection: $trendDayRange)),
            palette: palette
        ) {
            if points.isEmpty {
                Text(AppLocalization.text("common.noData"))
                    .foregroundStyle(palette.subtitle)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                TokenTrendChartView(points: points, palette: palette)
            }
        }
    }

    private func cacheSection(_ analytics: TokenCostDashboardAnalytics) -> some View {
        TokenSectionCard(
            title: AppLocalization.text("detail.cache.title"),
            subtitle: AppLocalization.text("detail.cache.subtitle"),
            trailing: nil,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: cacheColumns, spacing: 12) {
                    TokenMetricCard(
                        title: AppLocalization.text("detail.cache.hit"),
                        value: TokenCostFormatters.tokens(analytics.cache.cacheReadTokens),
                        subtitle: AppLocalization.text("detail.cache.hitSubtitle"),
                        tint: .green,
                        palette: palette
                    )
                    TokenMetricCard(
                        title: AppLocalization.text("detail.cache.write"),
                        value: TokenCostFormatters.tokens(analytics.cache.cacheWriteTokens),
                        subtitle: AppLocalization.text("detail.cache.writeSubtitle"),
                        tint: .orange,
                        palette: palette
                    )
                    TokenMetricCard(
                        title: AppLocalization.text("detail.cache.total"),
                        value: TokenCostFormatters.tokens(analytics.cache.totalCacheTokens),
                        subtitle: AppLocalization.text("detail.cache.totalSubtitle"),
                        tint: palette.accentSecondary,
                        palette: palette
                    )
                    TokenMetricCard(
                        title: AppLocalization.text("detail.cache.hitRate"),
                        value: TokenCostFormatters.percent(analytics.cache.cacheHitRate),
                        subtitle: AppLocalization.text("detail.cache.hitRateSubtitle"),
                        tint: palette.accent,
                        palette: palette
                    )
                    TokenMetricCard(
                        title: AppLocalization.text("detail.cache.savedCost"),
                        value: TokenCostFormatters.currency(analytics.cache.cacheSavedCost, displayCurrency: appPreferencesModel.preferences.displayCurrency),
                        subtitle: AppLocalization.text("detail.cache.savedCostSubtitle"),
                        tint: .purple,
                        palette: palette
                    )
                }

                VStack(spacing: 10) {
                    ForEach(analytics.providerCacheRows) { row in
                        DistributionRow(
                            title: row.displayName,
                            value: row.cacheReadTokens,
                            total: max(row.actualTokens + row.cacheReadTokens, 1),
                            tint: TokenCostSeriesPalette.color(for: row.colorKey),
                            palette: palette,
                            suffix: "\(row.cacheWriteLabel) · \(TokenCostFormatters.percent(row.cacheRate))"
                        )
                    }
                }
            }
        }
    }

    private func providerRankingSection(_ analytics: TokenCostDashboardAnalytics) -> some View {
        TokenSectionCard(
            title: AppLocalization.text("detail.providerRank.title"),
            subtitle: AppLocalization.text("detail.providerRank.subtitle"),
            trailing: nil,
            palette: palette
        ) {
            if analytics.providerRankRows.isEmpty {
                Text(AppLocalization.text("common.noData"))
                    .foregroundStyle(palette.subtitle)
            } else {
                VStack(spacing: 10) {
                    let maxRatio = analytics.providerRankRows.map(\.tokensPerDollar).max() ?? 1
                    ForEach(analytics.providerRankRows) { row in
                        DistributionRow(
                            title: row.displayName,
                            value: row.tokensPerDollar,
                            total: max(maxRatio, 1),
                            tint: TokenCostSeriesPalette.color(for: row.colorKey),
                            palette: palette,
                            suffix: providerRankSuffix(row),
                            valueLabel: TokenCostFormatters.millionRate(row.tokensPerDollar)
                        )
                    }
                }
            }
        }
    }

    private func modelComparisonSection(_ analytics: TokenCostDashboardAnalytics) -> some View {
        let rows = modelComparisonRows(for: analytics)
        let subtitle = modelComparisonExpanded
            ? AppLocalization.format("detail.modelComparison.subtitleFull", analytics.modelComparisonRows.count)
            : AppLocalization.format("detail.modelComparison.subtitleCollapsed", modelComparisonCollapsedLimit)

        return TokenSectionCard(
            title: AppLocalization.text("detail.modelComparison.title"),
            subtitle: subtitle,
            trailing: modelComparisonTrailing(for: analytics),
            palette: palette
        ) {
            if rows.isEmpty {
                Text(AppLocalization.text("common.noData"))
                    .foregroundStyle(palette.subtitle)
            } else {
                VStack(spacing: 10) {
                    let maxRatio = rows.map(\.tokensPerDollar).max() ?? 1
                    ForEach(rows) { row in
                        DistributionRow(
                            title: row.displayName,
                            value: row.tokensPerDollar,
                            total: max(maxRatio, 1),
                            tint: TokenCostSeriesPalette.color(for: row.colorKey),
                            palette: palette,
                            suffix: "\(row.provider) · \(modelCostLabel(row))",
                            valueLabel: TokenCostFormatters.millionRate(row.tokensPerDollar)
                        )
                    }

                    if appPreferencesModel.preferences.developerMode.modelCompareEnabled {
                        Text(AppLocalization.text("developerMode.modelCompare.disclaimer"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func distributionSection(_ analytics: TokenCostDashboardAnalytics) -> some View {
        let modelSlices = analytics.modelSlices
        let providerSlices = analytics.providerSlices
        return HStack(alignment: .top, spacing: 16) {
            pieCard(
                title: AppLocalization.text("detail.distribution.models.title"),
                subtitle: AppLocalization.text("detail.distribution.models.subtitle"),
                slices: modelSlices
            )
            .frame(maxWidth: .infinity)
            .background(GeometryReader { geo in
                Color.clear.preference(key: DistributionCardHeightKey.self, value: geo.size.height)
            })
            .frame(minHeight: distributionCardHeight)

            pieCard(
                title: AppLocalization.text("detail.distribution.providers.title"),
                subtitle: AppLocalization.text("detail.distribution.providers.subtitle"),
                slices: providerSlices
            )
            .frame(maxWidth: .infinity)
            .background(GeometryReader { geo in
                Color.clear.preference(key: DistributionCardHeightKey.self, value: geo.size.height)
            })
            .frame(minHeight: distributionCardHeight)
        }
        .onPreferenceChange(DistributionCardHeightKey.self) { value in
            distributionCardHeight = max(distributionCardHeight, value)
        }
    }

    private func stackedSection(_ analytics: TokenCostDashboardAnalytics) -> some View {
        let window = recentStackedWindow(from: analytics)
        let pageCount = max((window.dates.count + sectionPageSize - 1) / sectionPageSize, 1)
        let clampedPage = min(max(stackedPageIndex, 0), pageCount - 1)
        let startIndex = clampedPage * sectionPageSize
        let endIndex = min(startIndex + sectionPageSize, window.dates.count)
        let visibleDates = Array(window.dates[startIndex..<endIndex])
        let visibleDateIndexes = Array(startIndex..<endIndex)
        let maxTotal = window.dates.indices
            .map { dayTotal(at: $0, series: window.series) }
            .max() ?? 1

        return TokenSectionCard(
            title: AppLocalization.text("detail.stacked.title"),
            subtitle: AppLocalization.format("detail.stacked.subtitle", recentWindowLimit),
            trailing: nil,
            palette: palette
        ) {
            if window.series.isEmpty || window.dates.isEmpty {
                Text(AppLocalization.text("common.noData"))
                    .foregroundStyle(palette.subtitle)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    stackedLegend(window.series)
                    VStack(spacing: 8) {
                        ForEach(Array(visibleDates.enumerated()), id: \.offset) { offset, dateLabel in
                            let index = visibleDateIndexes[offset]
                            StackedDayRow(
                                dateLabel: dateLabel,
                                total: dayTotal(at: index, series: window.series),
                                maxTotal: max(maxTotal, 1),
                                series: window.series,
                                dateIndex: index
                            )
                        }
                    }
                    PaginationControls(
                        pageIndex: $stackedPageIndex,
                        itemCount: window.dates.count,
                        pageSize: sectionPageSize,
                        palette: palette,
                        title: AppLocalization.text("detail.stacked.paginationTitle")
                    )
                }
            }
        }
    }

    private func detailSection(_ analytics: TokenCostDashboardAnalytics) -> some View {
        let windowRows = recentDetailWindowRows(from: analytics)
        let rows = sortDetailRows(
            windowRows,
            field: detailSortField,
            direction: detailSortDirection
        )
        let pageCount = max((rows.count + sectionPageSize - 1) / sectionPageSize, 1)
        let clampedPage = min(max(detailPageIndex, 0), pageCount - 1)
        let startIndex = clampedPage * sectionPageSize
        let endIndex = min(startIndex + sectionPageSize, rows.count)
        let visibleRows = Array(rows[startIndex..<endIndex])

        return TokenSectionCard(
            title: AppLocalization.text("detail.sessions.title"),
            subtitle: AppLocalization.format("detail.sessions.subtitle", windowRows.count),
            trailing: AnyView(detailSortControls),
            palette: palette
        ) {
            if visibleRows.isEmpty {
                Text(AppLocalization.text("common.noData"))
                    .foregroundStyle(palette.subtitle)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal) {
                        VStack(spacing: 8) {
                            detailHeaderRow
                            ForEach(visibleRows) { row in
                                detailRow(row)
                            }
                        }
                        .frame(minWidth: 1090, alignment: .leading)
                    }
                    PaginationControls(
                        pageIndex: $detailPageIndex,
                        itemCount: rows.count,
                        pageSize: sectionPageSize,
                        palette: palette,
                        title: AppLocalization.text("detail.sessions.paginationTitle")
                    )
                }
            }
        }
    }

    private var detailSortControls: some View {
        HStack(spacing: 8) {
            Picker(AppLocalization.text("detail.sort.field"), selection: $detailSortField) {
                ForEach(TokenCostDetailSortField.allCases) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: detailSortField) { _, newValue in
                if newValue == .date {
                    detailSortDirection = .descending
                } else {
                    detailSortDirection = .descending
                }
                detailPageIndex = 0
            }

            Button {
                detailSortDirection = detailSortDirection == .descending ? .ascending : .descending
                detailPageIndex = 0
            } label: {
                Label(detailSortDirection.displayName, systemImage: detailSortDirection.systemImage)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var detailHeaderRow: some View {
        HStack(spacing: 12) {
            sortButton(title: AppLocalization.text("sort.detail.date"), field: .date, width: 96)
            sortButton(title: AppLocalization.text("sort.detail.model"), field: .model, width: 150)
            sortButton(title: AppLocalization.text("sort.detail.provider"), field: .provider, width: 132)
            sortButton(title: AppLocalization.text("sort.detail.input"), field: .input, width: 88, alignment: .trailing)
            sortButton(title: AppLocalization.text("sort.detail.output"), field: .output, width: 88, alignment: .trailing)
            sortButton(title: AppLocalization.text("sort.detail.cacheRead"), field: .cacheRead, width: 100, alignment: .trailing)
            sortButton(title: AppLocalization.text("sort.detail.cacheWrite"), field: .cacheWrite, width: 100, alignment: .trailing)
            sortButton(title: AppLocalization.text("sort.detail.total"), field: .total, width: 98, alignment: .trailing)
            sortButton(title: AppLocalization.text("sort.detail.cost"), field: .cost, width: 96, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(palette.subtitle)
        .padding(.horizontal, 12)
    }

    private func sortButton(
        title: String,
        field: TokenCostDetailSortField,
        width: CGFloat,
        alignment: Alignment = .leading
    ) -> some View {
        Button {
            if detailSortField == field {
                detailSortDirection = detailSortDirection == .descending ? .ascending : .descending
            } else {
                detailSortField = field
                detailSortDirection = field == .date ? .descending : .descending
            }
            detailPageIndex = 0
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if detailSortField == field {
                    Image(systemName: detailSortDirection.systemImage)
                        .font(.caption2)
                }
            }
            .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    private func detailRow(_ row: DashboardPayload.RawRow) -> some View {
        HStack(spacing: 12) {
            Text(row.date).frame(width: 96, alignment: .leading)
            Text(row.model).frame(width: 150, alignment: .leading).lineLimit(1)
            Text(row.provider).frame(width: 132, alignment: .leading).lineLimit(1)
            Text(TokenCostFormatters.tokens(row.input)).frame(width: 88, alignment: .trailing)
            Text(TokenCostFormatters.tokens(row.output)).frame(width: 88, alignment: .trailing)
            Text(TokenCostFormatters.tokens(row.cacheRead)).frame(width: 100, alignment: .trailing)
            Text(TokenCostFormatters.tokens(row.cacheWrite)).frame(width: 100, alignment: .trailing)
            Text(TokenCostFormatters.tokens(row.total)).frame(width: 98, alignment: .trailing)
            Text(row.cost > 0 ? TokenCostFormatters.currency(row.cost, displayCurrency: appPreferencesModel.preferences.displayCurrency) : "-")
                .frame(width: 96, alignment: .trailing)
                .foregroundStyle(row.cost > 0 ? .green : palette.subtitle)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.cardStroke.opacity(0.65), lineWidth: 1)
        )
    }

    private func pieCard(
        title: String,
        subtitle: String,
        slices: [TokenCostDashboardAnalytics.DistributionSlice]
    ) -> some View {
        TokenSectionCard(title: title, subtitle: subtitle, trailing: nil, palette: palette) {
            if slices.isEmpty {
                Text(AppLocalization.text("common.noData"))
                    .foregroundStyle(palette.subtitle)
            } else {
                let total = slices.reduce(0) { $0 + $1.value }
                VStack(alignment: .leading, spacing: 14) {
                    ZStack {
                        Chart(slices) { slice in
                            SectorMark(
                                angle: .value("Token", slice.value),
                                innerRadius: .ratio(0.62),
                                angularInset: 1.2
                            )
                            .foregroundStyle(TokenCostSeriesPalette.color(for: slice.colorKey))
                        }
                        .frame(height: 220)

                        VStack(spacing: 4) {
                            Text(AppLocalization.text("common.total"))
                                .font(.caption)
                                .foregroundStyle(palette.subtitle)
                            Text(TokenCostFormatters.tokens(total))
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundStyle(palette.title)
                        }
                    }

                    VStack(spacing: 8) {
                        ForEach(slices) { slice in
                            PieLegendRow(
                                title: slice.label,
                                value: slice.value,
                                percentage: slice.percentage,
                                color: TokenCostSeriesPalette.color(for: slice.colorKey),
                                palette: palette
                            )
                        }
                    }
                }
            }
        }
    }

    private func stackedLegend(_ series: [DetailStackSeries]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
            ForEach(Array(series.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(item.isOther ? TokenCostSeriesPalette.otherColor() : TokenCostSeriesPalette.color(forRank: index))
                        Circle()
                            .strokeBorder(palette.cardStroke.opacity(0.95), lineWidth: 1.2)
                    }
                    .frame(width: 10, height: 10)
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(palette.accentSoft, in: Capsule())
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(palette.cardStroke.opacity(0.9), lineWidth: 1.1)
                )
            }
        }
    }

    private func providerRankSuffix(_ row: TokenCostDashboardAnalytics.ProviderRankRow) -> String {
        let costText = providerCostLabel(row)
        let actualText = TokenCostFormatters.tokens(row.actualTokens)
        return AppLocalization.format("detail.providerRank.suffix", actualText, costText)
    }

    private func providerCostLabel(_ row: TokenCostDashboardAnalytics.ProviderRankRow) -> String {
        guard let cost = row.effectiveCost else {
            return AppLocalization.text("detail.providerRank.noPricing")
        }
        let dc = appPreferencesModel.preferences.displayCurrency
        if row.isSynthetic {
            return AppLocalization.format("detail.providerRank.apiPricing", TokenCostFormatters.currency(cost, displayCurrency: dc))
        }
        if row.isSubscription {
            return AppLocalization.format("detail.providerRank.subscriptionPricing", TokenCostFormatters.currency(cost, displayCurrency: dc))
        }
        return TokenCostFormatters.currency(cost, displayCurrency: dc)
    }

    private func modelCostLabel(_ row: TokenCostDashboardAnalytics.ModelComparisonRow) -> String {
        guard row.allocatedCost > 0 else {
            return AppLocalization.text("detail.providerRank.noPricing")
        }
        return TokenCostFormatters.currency(row.allocatedCost, displayCurrency: appPreferencesModel.preferences.displayCurrency)
    }

    private func openCodeTrendPoint(_ point: TokenCostDashboardAnalytics.TrendPoint) -> TokenTrendChartPoint {
        TokenTrendChartPoint(
            date: point.date,
            dateString: point.dateString,
            actualTokens: point.actualTokens,
            tooltipLines: [
                TokenTrendTooltipLine(
                    color: palette.accent,
                    title: AppLocalization.text("detail.tooltip.actualTokens"),
                    value: TokenCostFormatters.tokens(point.actualTokens)
                ),
                TokenTrendTooltipLine(
                    color: .green,
                    title: AppLocalization.text("detail.tooltip.cacheHit"),
                    value: TokenCostFormatters.tokens(point.cacheReadTokens)
                ),
                TokenTrendTooltipLine(
                    color: .orange,
                    title: AppLocalization.text("detail.tooltip.cacheWrite"),
                    value: TokenCostFormatters.tokens(point.cacheWriteTokens)
                )
            ]
        )
    }

    private func dayTotal(at index: Int, series: [DetailStackSeries]) -> Double {
        series.reduce(0) { partialResult, item in
            partialResult + (item.values[safe: index] ?? 0)
        }
    }

    private func modelComparisonRows(for analytics: TokenCostDashboardAnalytics) -> [TokenCostDashboardAnalytics.ModelComparisonRow] {
        if modelComparisonExpanded {
            return analytics.modelComparisonRows
        }
        return Array(analytics.modelComparisonRows.prefix(modelComparisonCollapsedLimit))
    }

    private func modelComparisonTrailing(for analytics: TokenCostDashboardAnalytics) -> AnyView? {
        guard analytics.modelComparisonRows.count > modelComparisonCollapsedLimit else {
            return nil
        }

        return AnyView(
            Button {
                modelComparisonExpanded.toggle()
            } label: {
                Label(
                    modelComparisonExpanded ? AppLocalization.text("common.collapse") : AppLocalization.text("common.showMore"),
                    systemImage: modelComparisonExpanded ? "chevron.up" : "chevron.down"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        )
    }

    private func recentDetailWindowRows(from analytics: TokenCostDashboardAnalytics) -> [DashboardPayload.RawRow] {
        Array(
            analytics.sortedDetailRows(sortField: .date, direction: .descending)
                .prefix(recentWindowLimit)
        )
    }

    private func sortDetailRows(
        _ rows: [DashboardPayload.RawRow],
        field: TokenCostDetailSortField,
        direction: TokenCostSortDirection
    ) -> [DashboardPayload.RawRow] {
        let sorted = rows.sorted { lhs, rhs in
            compareDetailRows(lhs, rhs, field: field)
        }
        return direction == .ascending ? sorted : Array(sorted.reversed())
    }

    private func compareDetailRows(
        _ lhs: DashboardPayload.RawRow,
        _ rhs: DashboardPayload.RawRow,
        field: TokenCostDetailSortField
    ) -> Bool {
        switch field {
        case .date:
            return compareString(lhs.date, rhs.date)
        case .model:
            return compareString(lhs.model, rhs.model)
        case .provider:
            return compareString(lhs.provider, rhs.provider)
        case .input:
            return compareNumeric(lhs.input, rhs.input)
        case .output:
            return compareNumeric(lhs.output, rhs.output)
        case .cacheRead:
            return compareNumeric(lhs.cacheRead, rhs.cacheRead)
        case .cacheWrite:
            return compareNumeric(lhs.cacheWrite, rhs.cacheWrite)
        case .total:
            return compareNumeric(lhs.total, rhs.total)
        case .cost:
            return compareNumeric(lhs.cost, rhs.cost)
        }
    }

    private func compareString(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private func compareNumeric(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs < rhs
    }

    private func recentStackedWindow(from analytics: TokenCostDashboardAnalytics) -> RecentStackedWindow {
        let windowRows = recentDetailWindowRows(from: analytics)
        let groupedByDate = Dictionary(grouping: windowRows, by: \.date)
        let sortedDates = groupedByDate.keys.sorted(by: >)

        var totalByModel: [String: Double] = [:]
        for row in windowRows {
            let key = stackedModelKey(row.model)
            totalByModel[key, default: 0] += row.total
        }

        let topModelKeys = totalByModel
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
                }
                return lhs.1 > rhs.1
            }
            .prefix(8)
            .map { $0.0 }

        let topModelSet = Set(topModelKeys)
        var series: [DetailStackSeries] = topModelKeys.map { modelKey in
            let values = sortedDates.map { date in
                groupedByDate[date, default: []].reduce(0) { partialResult, row in
                    stackedModelKey(row.model) == modelKey ? partialResult + row.total : partialResult
                }
            }
            return DetailStackSeries(
                label: modelKey,
                values: values,
                total: values.reduce(0, +),
                colorKey: modelKey,
                isOther: false
            )
        }

        let otherValues = sortedDates.map { date in
            groupedByDate[date, default: []].reduce(0) { partialResult, row in
                topModelSet.contains(stackedModelKey(row.model)) ? partialResult : partialResult + row.total
            }
        }

        if otherValues.contains(where: { $0 > 0 }) {
            series.append(
                DetailStackSeries(
                    label: AppLocalization.text("common.other"),
                    values: otherValues,
                    total: otherValues.reduce(0, +),
                    colorKey: "other-models",
                    isOther: true
                )
            )
        }

        return RecentStackedWindow(dates: sortedDates, series: series)
    }

    private func stackedModelKey(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private var loadingCard: some View {
        TokenSectionCard(title: AppLocalization.text("detail.loading.title"), subtitle: AppLocalization.text("detail.loading.subtitle"), trailing: nil, palette: palette) {
            HStack {
                ProgressView()
                Text(AppLocalization.text("common.pleaseWait"))
                    .foregroundStyle(palette.subtitle)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        }
    }

    private func emptyPayloadCard(source: TokenCostSource) -> some View {
        TokenSectionCard(title: AppLocalization.text("detail.emptyData.title"), subtitle: source.statusMessage, trailing: nil, palette: palette) {
            Text(AppLocalization.text("detail.emptyData.body"))
                .foregroundStyle(palette.subtitle)
                .frame(maxWidth: .infinity, minHeight: 140)
        }
    }

    private var emptyStateCard: some View {
        TokenSectionCard(title: AppLocalization.text("detail.emptyState.title"), subtitle: AppLocalization.text("detail.emptyState.subtitle"), trailing: nil, palette: palette) {
            VStack(spacing: 12) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(palette.subtitle)
                Text(AppLocalization.text("detail.emptyState.body"))
                    .foregroundStyle(palette.subtitle)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        }
    }
}

private struct RecentStackedWindow {
    var dates: [String]
    var series: [DetailStackSeries]
}

private struct DetailStackSeries: Identifiable {
    var id: String { colorKey }

    var label: String
    var values: [Double]
    var total: Double
    var colorKey: String
    var isOther: Bool
}

private struct DistributionCardHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PieLegendRow: View {
    let title: String
    let value: Double
    let percentage: Double
    let color: Color
    let palette: TokenCostPalette

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.title)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(TokenCostFormatters.tokens(value))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.title)

            Text(TokenCostFormatters.percent(percentage))
                .font(.caption)
                .foregroundStyle(palette.subtitle)
                .frame(width: 54, alignment: .trailing)
        }
    }
}

private struct StackedDayRow: View {
    let dateLabel: String
    let total: Double
    let maxTotal: Double
    let series: [DetailStackSeries]
    let dateIndex: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(dateLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let dayValues = series.map { $0.values[safe: dateIndex] ?? 0 }
                let totalForDay = dayValues.reduce(0, +)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.primary.opacity(0.06))

                    HStack(spacing: 1) {
                        ForEach(Array(series.enumerated()), id: \.offset) { index, item in
                            let value = item.values[safe: dateIndex] ?? 0
                            if value > 0 {
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(item.isOther ? TokenCostSeriesPalette.otherColor() : TokenCostSeriesPalette.color(forRank: index))
                                    .frame(width: width * (value / max(maxTotal, 1)))
                            }
                        }
                    }
                    .frame(width: width * (totalForDay / max(maxTotal, 1)), alignment: .leading)
                }
            }
            .frame(height: 12)

            Text(TokenCostFormatters.tokens(total))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
