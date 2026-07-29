import SwiftUI
import CodexTokenCostCore

struct BalanceOverviewCard: View {
    let snapshots: [BalanceSnapshot]
    let lastRefreshTime: Date?
    let palette: TokenCostPalette
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @State private var expanded = true

    private var availableSnapshots: [BalanceSnapshot] {
        appPreferencesModel.sortBalanceSnapshots(snapshots.filter(\.isAvailable))
    }

    private var unavailableSnapshots: [BalanceSnapshot] {
        appPreferencesModel.sortBalanceSnapshots(snapshots.filter { !$0.isAvailable })
    }

    var body: some View {
        if snapshots.isEmpty {
            TokenSectionCard(
                title: AppLocalization.text("balance.empty.title"),
                subtitle: AppLocalization.text("balance.empty.subtitle"),
                trailing: nil,
                palette: palette
            ) {
                Text(AppLocalization.text("balance.empty.body"))
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
            }
        } else {
            TokenSectionCard(
                title: AppLocalization.text("balance.title"),
                subtitle: lastRefreshTime.map {
                    AppLocalization.format("balance.lastRefresh", TokenCostFormatters.localDateTime($0))
                } ?? AppLocalization.text("balance.notRefreshed"),
                trailing: AnyView(
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                        } label: {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .help("Expand or collapse balance details")
                    }
                ),
                palette: palette
            ) {
                if expanded {
                    if !appPreferencesModel.preferences.balanceOrderLocked {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    appPreferencesModel.balanceOrderLockedBinding.wrappedValue = true
                                }
                            } label: {
                                Label(AppLocalization.text("balance.order.lock"), systemImage: "lock.fill")
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                            .foregroundStyle(palette.subtitle)
                        }
                        .padding(.horizontal, 4)
                        List {
                            ForEach(availableSnapshots) { snapshot in
                                balanceRow(snapshot)
                            }
                            .onMove { offsets, target in
                                // `offsets`/`target` are indices into `ForEach(availableSnapshots)`,
                                // while the persisted order must still preserve hidden/unavailable providers.
                                let order = appPreferencesModel.balanceProviderOrder(
                                    moving: availableSnapshots.map(\.provider),
                                    fromOffsets: offsets,
                                    toOffset: target
                                )
                                appPreferencesModel.balanceCustomOrderBinding.wrappedValue = order
                            }
                            ForEach(unavailableSnapshots) { snapshot in
                                unavailableRow(snapshot)
                            }
                        }
                        .listStyle(.plain)
                        .frame(minHeight: 150, maxHeight: 600)
                        .scrollContentBackground(.hidden)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(availableSnapshots) { snapshot in
                                balanceRow(snapshot)
                            }
                            ForEach(unavailableSnapshots) { snapshot in
                                unavailableRow(snapshot)
                            }
                        }
                    }
                }
            }
        }
    }

    private var displayMode: BalanceDisplayMode {
        appPreferencesModel.preferences.balanceDisplayMode
    }

    private func balanceRow(_ snapshot: BalanceSnapshot) -> some View {
        let hasQuotaWindows = snapshot.quotaWindows != nil && !(snapshot.quotaWindows?.isEmpty ?? true)
        let hasLegacyWindows = snapshot.primaryWindowUsagePercent != nil
        let showCostOnly = snapshot.usagePercent == nil && snapshot.totalCostUSD != nil
        let showValueEntries = snapshot.valueEntries != nil && !(snapshot.valueEntries?.isEmpty ?? true)

        return HStack(spacing: 12) {
            Circle()
                .fill(gradientColor(for: snapshot.gradient))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.provider.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.title)

                if hasQuotaWindows, let windows = snapshot.quotaWindows {
                    ForEach(windows) { window in
                        windowProgressBar(
                            label: window.label,
                            usedRatio: window.usedRatio,
                            remainingRatio: window.remainingRatio,
                            resetAt: window.resetAt,
                            windowSeconds: window.windowSeconds,
                            consumptionRate: window.consumptionRate
                        )
                    }
                } else if hasLegacyWindows {
                    if let primary = snapshot.primaryWindowUsagePercent {
                        windowProgressBar(label: snapshot.primaryWindowLabel ?? "", usedRatio: primary, remainingRatio: nil)
                    }
                    if let secondary = snapshot.secondaryWindowUsagePercent {
                        windowProgressBar(label: snapshot.secondaryWindowLabel ?? "", usedRatio: secondary, remainingRatio: nil)
                    }
                    if let tertiary = snapshot.tertiaryWindowUsagePercent {
                        windowProgressBar(label: snapshot.tertiaryWindowLabel ?? "", usedRatio: tertiary, remainingRatio: nil)
                    }
                } else if showCostOnly {
                    if let cost = snapshot.totalCostUSD {
                        Text(AppLocalization.format("balance.total90Days", TokenCostFormatters.currency(cost)))
                            .font(.caption)
                            .foregroundStyle(palette.subtitle)
                    }
                    if let avg = snapshot.avgCostPerDayUSD {
                        Text(AppLocalization.format("balance.dailyAverage", TokenCostFormatters.currency(avg)))
                            .font(.caption2)
                            .foregroundStyle(palette.subtitle)
                    }
                } else if showValueEntries {
                    if let entries = snapshot.valueEntries {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(BalanceMenuBarExtraSupport.amountText(for: entry))
                                    .font(.caption)
                                    .foregroundStyle(palette.title)
                                if let burnRateText = BalanceMenuBarExtraSupport.burnRateText(for: entry) {
                                    Text(burnRateText)
                                        .font(.caption2)
                                        .foregroundStyle(palette.accent.opacity(0.8))
                                }
                                if let granted = entry.grantedAmount {
                                    Text(AppLocalization.format("balance.value.grantedShort", String(format: "%.2f", granted)))
                                        .font(.caption2)
                                        .foregroundStyle(palette.subtitle)
                                }
                            }
                        }
                    }
                } else if let pct = snapshot.usagePercent {
                    windowProgressBar(label: nil, usedRatio: pct, remainingRatio: nil)
                }
            }

            Spacer()

            Text(showCostOnly || showValueEntries ? AppLocalization.text("balance.balance") : snapshot.gradient.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(gradientColor(for: (showCostOnly || showValueEntries) ? .low : snapshot.gradient))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(gradientColor(for: (showCostOnly || showValueEntries) ? .low : snapshot.gradient).opacity(0.12))
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(palette.cardStroke, lineWidth: 1)
                )
        )
    }

    private func windowProgressBar(
        label: String?,
        usedRatio: Double?,
        remainingRatio: Double?,
        resetAt: Date? = nil,
        windowSeconds: Int? = nil,
        consumptionRate: ConsumptionRate? = nil
    ) -> some View {
        let displayRatioValue: Double
        if let used = usedRatio {
            displayRatioValue = BalanceMenuBarExtraSupport.displayRatio(for: used, displayMode: displayMode)
        } else if let remaining = remainingRatio {
            displayRatioValue = BalanceMenuBarExtraSupport.displayRatio(for: 1.0 - remaining, displayMode: displayMode)
        } else {
            displayRatioValue = 0
        }
        let clamped = min(max(displayRatioValue, 0), 1)
        let color = BalanceMenuBarExtraSupport.quotaColor(
            forDisplayRatio: clamped,
            displayMode: displayMode,
            palette: palette
        )
        let countdownText: String? = {
            guard let resetAt, windowSeconds != nil else { return nil }
            let remaining = max(0, resetAt.timeIntervalSinceNow)
            if remaining <= 0 { return AppLocalization.text("balance.rate.countdownSoon") }
            if remaining < 60 { return "<1m" }
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            if hours > 0 {
                return AppLocalization.format("balance.rate.countdown", "\(hours)h\(minutes)m")
            }
            return AppLocalization.format("balance.rate.countdown", "\(minutes)m")
        }()
        let rateText: String? = {
            guard let rate = consumptionRate, rate.confidence > 0 else { return nil }
            if let windowSeconds, windowSeconds >= 86400 {
                return AppLocalization.format("balance.rate.perDay", rate.perDay)
            }
            return AppLocalization.format("balance.rate.perHour", rate.perHour)
        }()
        let showPending = consumptionRate == nil || consumptionRate?.confidence == 0

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let label {
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(palette.subtitle)
                        .frame(minWidth: 36, idealWidth: 48, alignment: .leading)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(palette.trackBackground)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(clamped), height: 6)
                    }
                }
                .frame(height: 6)
                Text(TokenCostFormatters.percent(clamped))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.subtitle)
                    .frame(width: 44, alignment: .trailing)
            }
            HStack(spacing: 8) {
                if let countdownText {
                    Text(countdownText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.subtitle.opacity(0.7))
                }
                if let rateText {
                    Text(rateText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.accent.opacity(0.8))
                } else if showPending {
                    Text(AppLocalization.text("balance.rate.pending"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.subtitle.opacity(0.5))
                }
            }
            .padding(.leading, label != nil ? 42 : 0)
        }
    }

    private func unavailableRow(_ snapshot: BalanceSnapshot) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.provider.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.title)
                if let reason = snapshot.errorMessage {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                }
                if let hint = snapshot.errorRecoveryHint, !hint.isEmpty {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(palette.subtitle)
                }
            }
            Spacer()
            if snapshot.errorRequiresReimport {
                Button(AppLocalization.text("balance.error.reimport")) {}
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .foregroundStyle(palette.accent)
            }
            Text(AppLocalization.text("balance.unavailable"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.gray)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.gray.opacity(0.12))
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(palette.cardStroke, lineWidth: 1)
                )
        )
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
