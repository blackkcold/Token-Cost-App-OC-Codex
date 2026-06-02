import SwiftUI
import CodexTokenCostCore

enum TokenCostFormatters {
    static func tokens(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(1)))
    }

    static func millionRate(_ value: Double) -> String {
        String(format: "%.2fM/$", value / 1_000_000)
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }

    static func currency(_ value: Double, displayCurrency: DisplayCurrency = .usd) -> String {
        BillingPlanCatalog.formatCurrency(value, displayCurrency: displayCurrency)
    }

    static func monthlyCurrency(_ value: Double, displayCurrency: DisplayCurrency = .usd) -> String {
        "\(currency(value, displayCurrency: displayCurrency))\(AppLocalization.text("unit.perMonth"))"
    }

    static func localDateTime(_ isoDateString: String?) -> String {
        guard let isoDateString else { return AppLocalization.text("common.unavailable") }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = isoFormatter.date(from: isoDateString)
            ?? ISO8601DateFormatter().date(from: isoDateString) else {
            return isoDateString
        }
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

struct TokenMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
    let palette: TokenCostPalette
    let compact: Bool

    init(
        title: String,
        value: String,
        subtitle: String,
        tint: Color,
        palette: TokenCostPalette,
        compact: Bool = false
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.tint = tint
        self.palette = palette
        self.compact = compact
    }

    var body: some View {
        let cardPadding: CGFloat = compact ? 12 : 16
        let valueFontSize: CGFloat = compact ? 19 : 26
        let contentSpacing: CGFloat = compact ? 8 : 10

        VStack(alignment: .leading, spacing: contentSpacing) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.subtitle)

                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: valueFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.title)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(palette.subtitle)
                .lineLimit(2)
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(palette.cardStroke, lineWidth: 1)
                )
                .shadow(color: palette.cardShadow, radius: 14, x: 0, y: 8)
        )
    }
}

struct TokenSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let trailing: AnyView?
    let palette: TokenCostPalette
    let content: Content

    init(
        title: String,
        subtitle: String,
        trailing: AnyView?,
        palette: TokenCostPalette,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.palette = palette
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(palette.title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                }

                Spacer(minLength: 0)

                trailing
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(palette.cardStroke, lineWidth: 1)
                )
                .shadow(color: palette.cardShadow, radius: 16, x: 0, y: 10)
        )
    }
}

struct DistributionRow: View {
    let title: String
    let value: Double
    let total: Double
    let tint: Color
    let palette: TokenCostPalette
    var suffix: String = ""
    var valueLabel: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(valueLabel ?? TokenCostFormatters.tokens(value))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.title)
            }

            GeometryReader { proxy in
                let ratio = total > 0 ? min(max(value / total, 0), 1) : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(palette.trackBackground)
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(tint.gradient)
                        .frame(width: proxy.size.width * ratio)
                }
            }
            .frame(height: 8)

            if !suffix.isEmpty {
                Text(suffix)
                    .font(.caption2)
                    .foregroundStyle(palette.subtitle)
            }
        }
    }
}

struct SourceStatusPill: View {
    let source: TokenCostSource
    let palette: TokenCostPalette

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch source.status {
        case .available: return palette.accent
        case .locked: return .orange
        case .unsupported: return .yellow
        case .missing: return .red
        case .unknown: return palette.subtitle
        }
    }

    private var background: Color {
        foreground.opacity(0.14)
    }

    private var label: String {
        switch source.status {
        case .available: return AppLocalization.text("source.statusPill.available")
        case .locked: return AppLocalization.text("source.statusPill.locked")
        case .unsupported: return AppLocalization.text("source.statusPill.unsupported")
        case .missing: return AppLocalization.text("source.statusPill.missing")
        case .unknown: return AppLocalization.text("source.statusPill.unknown")
        }
    }
}

struct PaginationControls: View {
    @Binding var pageIndex: Int
    let itemCount: Int
    let pageSize: Int
    let palette: TokenCostPalette
    var title: String = AppLocalization.text("pagination.title")

    private var pageCount: Int {
        max((itemCount + pageSize - 1) / pageSize, 1)
    }

    private var clampedPageIndex: Int {
        min(max(pageIndex, 0), pageCount - 1)
    }

    private var startIndex: Int {
        guard itemCount > 0 else { return 0 }
        return clampedPageIndex * pageSize + 1
    }

    private var endIndex: Int {
        guard itemCount > 0 else { return 0 }
        return min((clampedPageIndex + 1) * pageSize, itemCount)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.subtitle)

            Spacer(minLength: 0)

            Text(AppLocalization.format(
                "pagination.summary",
                clampedPageIndex + 1,
                pageCount,
                itemCount,
                startIndex,
                endIndex
            ))
                .font(.caption)
                .foregroundStyle(palette.subtitle)

            Button {
                pageIndex = max(clampedPageIndex - 1, 0)
            } label: {
                Label(AppLocalization.text("pagination.previous"), systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(clampedPageIndex == 0)

            Button {
                pageIndex = min(clampedPageIndex + 1, pageCount - 1)
            } label: {
                Label(AppLocalization.text("pagination.next"), systemImage: "chevron.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(clampedPageIndex >= pageCount - 1)
        }
    }
}
