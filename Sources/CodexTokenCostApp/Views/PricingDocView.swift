import SwiftUI
import CodexTokenCostCore

struct PricingDocView: View {
    @Environment(\.dismiss) private var dismiss
    let palette: TokenCostPalette

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerNote

                    ForEach(BillingProvider.allCases) { provider in
                        providerPricingCard(provider)
                    }

                    mimoCreditsCard
                    totalCostExplanation
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(Text(verbatim: "\u{1F4C4} \(AppLocalization.text("settings.billing.pricingDoc"))"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.text("settings.action.close")) {
                        dismiss()
                    }
                }
            }
        }
        .modifier(AdaptiveSheetSizing())
    }

    // MARK: - Header

    private var headerNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本文档为 App 内置只读参考。实际价格可能变更，设置页提供「自定义 USD 月费」作为兜底。")
                .font(.callout)
                .foregroundStyle(palette.subtitle)
            Text("总成本 = 已启用固定订阅费用 + 未订阅部分 API 估算成本；若所有订阅关闭，总成本全部按 API 定价估算。")
                .font(.caption)
                .foregroundStyle(palette.subtitle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.accent.opacity(0.08))
        )
    }

    // MARK: - Provider Card

    private func providerPricingCard(_ provider: BillingProvider) -> some View {
        let presets = BillingPlanCatalog.presets(for: provider)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(provider.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.accent)
                Spacer()
            }

            VStack(spacing: 0) {
                tableHeaderRow(provider: provider)

                Divider().overlay(palette.cardStroke)

                ForEach(Array(presets.enumerated()), id: \.element.id) { idx, preset in
                    tableRow(preset: preset, provider: provider)
                    if idx < presets.count - 1 {
                        Divider().overlay(palette.cardStroke.opacity(0.4))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.cardFill)
        )
    }

    @ViewBuilder
    private func tableHeaderRow(provider: BillingProvider) -> some View {
        HStack(spacing: 0) {
            Text("档位")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.title)
                .frame(minWidth: 90, maxWidth: 150, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            Text("费用")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.title)
                .frame(minWidth: 70, maxWidth: 110, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            Text("说明")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .background(palette.cardFill)
    }

    private func tableRow(preset: BillingPlanPreset, provider: BillingProvider) -> some View {
        HStack(spacing: 0) {
            Text(preset.name)
                .font(.caption)
                .foregroundStyle(palette.title)
                .frame(minWidth: 90, maxWidth: 150, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            Text(preset.displayPrice)
                .font(.caption)
                .foregroundStyle(palette.accent)
                .frame(minWidth: 70, maxWidth: 110, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            Text(preset.usageNote)
                .font(.caption)
                .foregroundStyle(palette.subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
    }

    // MARK: - MiMo Credits Card

    private var mimoCreditsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MiMo Credits 消耗规则")
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.accent)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("模型").font(.caption.weight(.semibold)).foregroundStyle(palette.title)
                        .frame(minWidth: 80, maxWidth: 130, alignment: .leading).padding(8)
                    Text("缓存命中").font(.caption.weight(.semibold)).foregroundStyle(palette.title)
                        .frame(minWidth: 70, maxWidth: 110, alignment: .leading).padding(8)
                    Text("缓存未命中（输入）").font(.caption.weight(.semibold)).foregroundStyle(palette.title)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    Text("输出").font(.caption.weight(.semibold)).foregroundStyle(palette.title)
                        .frame(minWidth: 70, maxWidth: 110, alignment: .leading).padding(8)
                }
                .background(palette.cardFill)

                Divider().overlay(palette.cardStroke)

                mimoCreditRow(model: "mimo-v2.5", hit: "2 Credits", miss: "100 Credits", output: "200 Credits")
                Divider().overlay(palette.cardStroke.opacity(0.4))
                mimoCreditRow(model: "mimo-v2.5-pro", hit: "2.5 Credits", miss: "300 Credits", output: "600 Credits")
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("MiMo 套餐是 Credit 包，不是无限请求包；Agent 多轮工具调用会快速消耗额度，实际耐用程度取决于模型、上下文长度、工具调用次数和缓存命中。夜间（0:00-8:00 北京时间）消耗系数 0.8x。")
                .font(.caption)
                .foregroundStyle(palette.subtitle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.cardFill)
        )
    }

    private func mimoCreditRow(model: String, hit: String, miss: String, output: String) -> some View {
        HStack(spacing: 0) {
            Text(model).font(.caption).foregroundStyle(palette.title)
                .frame(minWidth: 80, maxWidth: 130, alignment: .leading).padding(8)
            Text(hit).font(.caption).foregroundStyle(palette.subtitle)
                .frame(minWidth: 70, maxWidth: 110, alignment: .leading).padding(8)
            Text(miss).font(.caption).foregroundStyle(palette.subtitle)
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            Text(output).font(.caption).foregroundStyle(palette.subtitle)
                .frame(minWidth: 70, maxWidth: 110, alignment: .leading).padding(8)
        }
    }

    // MARK: - Total Cost Explanation

    private var totalCostExplanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App 总计费口径")
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.accent)

            VStack(alignment: .leading, spacing: 6) {
                formulaLine("费用", "input × inputPrice + output × outputPrice + reasoning × reasoningPrice")
                formulaLine("", "+ cacheRead × cacheReadPrice + cacheWrite × cacheWritePrice")
                Divider().opacity(0.3)
                formulaLine("实际输入 (OpenCode)", "input（已是非缓存值，不做减法）")
                formulaLine("实际输入 (Codex)", "max(inputTokens - cachedInputTokens, 0)")
                formulaLine("缓存命中率", "cacheRead / (actualTokens + cacheRead)")
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.cardFill)
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.cardFill)
        )
    }

    private func formulaLine(_ label: String, _ formula: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.title)
                    .frame(minWidth: 80, maxWidth: 140, alignment: .trailing)
            } else {
                Spacer().frame(minWidth: 80, maxWidth: 140)
            }
            Text(formula)
                .font(.caption.monospaced())
                .foregroundStyle(palette.subtitle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
