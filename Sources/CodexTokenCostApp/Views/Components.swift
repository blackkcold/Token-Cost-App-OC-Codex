import SwiftUI
import CodexTokenCostCore

enum TokenCostFormatters {
    private static nonisolated(unsafe) let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static nonisolated(unsafe) let isoFormatterNoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func tokens(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(1)))
    }

    static func millionRate(_ value: Double, displayCurrency: DisplayCurrency = .usd) -> String {
        let symbol = displayCurrency == .cny ? "¥" : "$"
        let rate = displayCurrency == .cny ? value * TokenCostCurrencyService.defaultExchangeRateUSDToCNY : value
        return String(format: "%.2fM/%@", rate / 1_000_000, symbol)
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
        guard let date = isoFormatter.date(from: isoDateString)
            ?? isoFormatterNoFractional.date(from: isoDateString) else {
            return isoDateString
        }
        return displayFormatter.string(from: date)
    }

    static func localDateTime(_ date: Date) -> String {
        displayFormatter.string(from: date)
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

struct TokenCollapsibleSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let trailing: AnyView?
    let palette: TokenCostPalette
    @Binding var isExpanded: Bool
    let content: Content

    init(
        title: String,
        subtitle: String,
        trailing: AnyView? = nil,
        isExpanded: Binding<Bool>,
        palette: TokenCostPalette,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.palette = palette
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        TokenSectionCard(
            title: title,
            subtitle: subtitle,
            trailing: AnyView(
                HStack(spacing: 8) {
                    if let trailing {
                        trailing
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Label(
                            isExpanded ? AppLocalization.text("common.collapse") : AppLocalization.text("common.showMore"),
                            systemImage: isExpanded ? "chevron.up" : "chevron.down"
                        )
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(palette.accent)
                }
            ),
            palette: palette
        ) {
            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}

struct SettingsControlGrid<Content: View>: View {
    let minimumWidth: CGFloat
    let spacing: CGFloat
    let content: Content

    init(
        minimumWidth: CGFloat = 280,
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumWidth = minimumWidth
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: spacing, alignment: .top)],
            alignment: .leading,
            spacing: spacing
        ) {
            content
        }
    }
}

struct SettingsActionWrap<Content: View>: View {
    let minimumWidth: CGFloat
    let spacing: CGFloat
    let content: Content

    init(
        minimumWidth: CGFloat = 170,
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumWidth = minimumWidth
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: spacing, alignment: .top)],
            alignment: .leading,
            spacing: spacing
        ) {
            content
        }
    }
}

struct SettingsControlTile<Content: View>: View {
    let title: String?
    let palette: TokenCostPalette
    let minHeight: CGFloat
    let content: Content

    init(
        title: String? = nil,
        palette: TokenCostPalette,
        minHeight: CGFloat = 58,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.palette = palette
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: title == nil ? 0 : 8) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.subtitle)
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: 16, style: .continuous),
            palette: palette
        )
    }
}

struct SettingsFieldGroup<Content: View>: View {
    let title: String?
    let palette: TokenCostPalette
    let spacing: CGFloat
    let content: Content

    init(
        title: String? = nil,
        palette: TokenCostPalette,
        spacing: CGFloat = 10,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.palette = palette
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.subtitle)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsInlineControlRow<Control: View>: View {
    let title: String
    let palette: TokenCostPalette
    let control: Control

    init(
        title: String,
        palette: TokenCostPalette,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.palette = palette
        self.control = control()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(palette.title)
                    .lineLimit(1)

                Spacer(minLength: 8)

                control
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(palette.title)
                control
            }
        }
    }
}

enum SettingsSurfaceRole {
    case primary
    case secondary
    case warning
}

struct SettingsSurfaceCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let trailing: AnyView?
    let palette: TokenCostPalette
    let role: SettingsSurfaceRole
    let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        trailing: AnyView? = nil,
        role: SettingsSurfaceRole = .primary,
        palette: TokenCostPalette,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.role = role
        self.palette = palette
        self.content = content()
    }

    var body: some View {
        let isPrimary = role == .primary
        let cornerRadius: CGFloat = isPrimary ? 28 : 22
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let contentPadding: CGFloat = isPrimary ? 20 : 16
        let shadow = role == .warning ? Color.black.opacity(0.08) : palette.surfaceShadow
        let stroke = role == .warning ? Color.orange.opacity(0.22) : palette.surfaceStroke
        let glassTint: Color? = role == .warning ? Color.orange.opacity(0.14) : nil

        VStack(alignment: .leading, spacing: title == nil ? 12 : 16) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(palette.title)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(palette.subtitle)
                        }
                    }

                    Spacer(minLength: 0)

                    trailing
                }
            }

            content
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsSurfaceBackgroundModifier(
            shape: shape,
            palette: palette,
            stroke: stroke,
            shadow: shadow,
            glassTint: glassTint,
            role: role
        ))
    }
}

private struct SettingsSurfaceBackgroundModifier: ViewModifier {
    let shape: RoundedRectangle
    let palette: TokenCostPalette
    let stroke: Color
    let shadow: Color
    let glassTint: Color?
    let role: SettingsSurfaceRole
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var usesSolidFallback: Bool {
        reduceTransparency || colorSchemeContrast == .increased
    }

    func body(content: Content) -> some View {
        if usesSolidFallback {
            let fill = role == .secondary ? palette.surfaceSecondarySolidFill : palette.surfaceSolidFill
            let accessibleStroke = role == .warning ? Color.orange.opacity(0.58) : palette.surfaceAccessibleStroke
            content
                .background(shape.fill(fill))
                .overlay(
                    shape.strokeBorder(accessibleStroke, lineWidth: role == .primary ? 1.2 : 1)
                )
                .shadow(color: shadow.opacity(0.55), radius: role == .primary ? 8 : 5, x: 0, y: role == .primary ? 5 : 3)
        } else if #available(macOS 26, *) {
            let glass: Glass = glassTint.map { .regular.tint($0) } ?? .regular
            content
                .glassEffect(glass, in: shape)
                .overlay(
                    shape.strokeBorder(stroke.opacity(role == .secondary ? 0.32 : 0.46), lineWidth: role == .primary ? 0.8 : 0.7)
                )
        } else {
            content
                .background(
                    shape.fill(role == .secondary ? palette.surfaceSecondaryFill : palette.surfaceFill)
                )
                .overlay(
                    shape.strokeBorder(stroke.opacity(role == .secondary ? 0.72 : 1.0), lineWidth: role == .primary ? 1 : 0.8)
                )
                .shadow(color: shadow, radius: role == .primary ? 14 : 10, x: 0, y: role == .primary ? 8 : 6)
        }
    }
}

struct SettingsInsetSurfaceBackgroundModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let palette: TokenCostPalette
    let stroke: Color?
    let lineWidth: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var usesSolidFallback: Bool {
        reduceTransparency || colorSchemeContrast == .increased
    }

    func body(content: Content) -> some View {
        if usesSolidFallback {
            content
                .background(shape.fill(palette.surfaceSecondarySolidFill))
                .overlay(
                    shape.strokeBorder(stroke ?? palette.surfaceAccessibleStroke, lineWidth: max(lineWidth, 1))
                )
        } else {
            content
                .background(shape.fill(palette.surfaceSecondaryFill))
                .overlay(
                    shape.strokeBorder(stroke ?? palette.surfaceInnerStroke, lineWidth: lineWidth)
                )
        }
    }
}

private struct SettingsGlassButtonStyleModifier: ViewModifier {
    let prominent: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var usesSolidFallback: Bool {
        reduceTransparency || colorSchemeContrast == .increased
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !usesSolidFallback {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

struct SettingsSummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let palette: TokenCostPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.subtitle)

                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.title)
                .lineLimit(2)
                .minimumScaleFactor(0.76)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(palette.subtitle)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: 20, style: .continuous),
            palette: palette
        )
    }
}

struct SettingsInfoChip: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    let palette: TokenCostPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.subtitle)
            }

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.title)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: 16, style: .continuous),
            palette: palette
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
            .settingsGlassButtonStyle()
            .controlSize(.small)
            .disabled(clampedPageIndex == 0)

            Button {
                pageIndex = min(clampedPageIndex + 1, pageCount - 1)
            } label: {
                Label(AppLocalization.text("pagination.next"), systemImage: "chevron.right")
            }
            .settingsGlassButtonStyle()
            .controlSize(.small)
            .disabled(clampedPageIndex >= pageCount - 1)
        }
    }
}

extension View {
    func settingsInsetSurface<S: InsettableShape>(
        in shape: S,
        palette: TokenCostPalette,
        stroke: Color? = nil,
        lineWidth: CGFloat = 0.8
    ) -> some View {
        modifier(SettingsInsetSurfaceBackgroundModifier(
            shape: shape,
            palette: palette,
            stroke: stroke,
            lineWidth: lineWidth
        ))
    }

    func settingsGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(SettingsGlassButtonStyleModifier(prominent: prominent))
    }
}

struct AdaptiveSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .frame(maxHeight: 700)
                .presentationSizing(.fitted)
        } else {
            content
                .frame(minWidth: 600, idealWidth: 900, minHeight: 480, idealHeight: 700)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
