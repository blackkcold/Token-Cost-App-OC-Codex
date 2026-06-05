import SwiftUI
import CodexTokenCostCore

struct BalanceOverviewCard: View {
    let snapshots: [BalanceSnapshot]
    let lastRefreshTime: Date?
    let palette: TokenCostPalette
    @State private var expanded = true

    private var availableSnapshots: [BalanceSnapshot] {
        snapshots.filter(\.isAvailable)
    }

    private var unavailableSnapshots: [BalanceSnapshot] {
        snapshots.filter { !$0.isAvailable }
    }

    var body: some View {
        if snapshots.isEmpty {
            TokenSectionCard(
                title: "实时余额",
                subtitle: "暂未拉取余额数据。请前往设置开启余额监控并点击刷新。",
                trailing: nil,
                palette: palette
            ) {
                Text("余额数据将在首次刷新后显示。")
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
            }
        } else {
            TokenSectionCard(
                title: "实时余额",
                subtitle: lastRefreshTime.map {
                    "上次刷新：\(TokenCostFormatters.localDateTime(ISO8601DateFormatter().string(from: $0)))"
                } ?? "尚未刷新",
                trailing: AnyView(
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                        } label: {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                    }
                ),
                palette: palette
            ) {
                if expanded {
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

    private func balanceRow(_ snapshot: BalanceSnapshot) -> some View {
        let showWindows = snapshot.primaryWindowUsagePercent != nil || snapshot.quotaWindows != nil
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

                if showWindows {
                    if let primary = snapshot.primaryWindowUsagePercent {
                        windowProgressBar(label: snapshot.primaryWindowLabel ?? "", pct: primary)
                    }
                    if let secondary = snapshot.secondaryWindowUsagePercent {
                        windowProgressBar(label: snapshot.secondaryWindowLabel ?? "", pct: secondary)
                    }
                    if let tertiary = snapshot.tertiaryWindowUsagePercent {
                        windowProgressBar(label: snapshot.tertiaryWindowLabel ?? "", pct: tertiary)
                    }
                } else if showCostOnly {
                    if let cost = snapshot.totalCostUSD {
                        Text("90天累计 $\(String(format: "%.2f", cost))")
                            .font(.caption)
                            .foregroundStyle(palette.subtitle)
                    }
                    if let avg = snapshot.avgCostPerDayUSD {
                        Text("日均 $\(String(format: "%.2f", avg))")
                            .font(.caption2)
                            .foregroundStyle(palette.subtitle)
                    }
                } else if showValueEntries {
                    if let entries = snapshot.valueEntries {
                        ForEach(entries) { entry in
                            HStack(spacing: 6) {
                                Text(entry.currencyCode ?? "")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.accent)
                                Text(String(format: "%.2f", entry.amount))
                                    .font(.caption)
                                    .foregroundStyle(palette.title)
                                if let granted = entry.grantedAmount {
                                    Text("(赠 \(String(format: "%.2f", granted)))")
                                        .font(.caption2)
                                        .foregroundStyle(palette.subtitle)
                                }
                            }
                        }
                    }
                } else if let pct = snapshot.usagePercent {
                    windowProgressBar(label: nil, pct: pct)
                }
            }

            Spacer()

            Text(showCostOnly || showValueEntries ? "余额" : snapshot.gradient.label)
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

    private func windowProgressBar(label: String?, pct: Double) -> some View {
        let color = gradientColor(for: pct < 0.5 ? UsageGradient.low : pct < 0.8 ? .moderate : pct < 0.95 ? .high : .critical)
        return HStack(spacing: 6) {
            if let label {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.subtitle)
                    .frame(width: 36, alignment: .leading)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(palette.trackBackground)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(pct, 1.0)), height: 6)
                }
            }
            .frame(height: 6)
            Text("\(Int(pct * 100))%")
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.subtitle)
                .frame(width: 36, alignment: .trailing)
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
            }
            Spacer()
            Text("不可用")
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
