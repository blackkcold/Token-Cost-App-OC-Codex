import SwiftUI
import CodexTokenCostCore

extension EnvironmentValues {
    @Entry var tokenCostUsesWorkshopStyle = false
}

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
        let cardPadding: CGFloat = compact ? TokenSpacing.control : TokenSpacing.card
        let valueFontSize: CGFloat = compact ? 19 : 26
        let contentSpacing: CGFloat = compact ? 8 : 10

        VStack(alignment: .leading, spacing: contentSpacing) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(TokenTypography.caption(weight: .semibold, palette: palette))
                    .foregroundStyle(palette.subtitle)

                Spacer(minLength: 0)
            }

            Text(value)
                .font(TokenTypography.metric(size: valueFontSize, palette: palette))
                .foregroundStyle(palette.title)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text(subtitle)
                .font(TokenTypography.caption(palette: palette))
                .foregroundStyle(palette.subtitle)
                .lineLimit(2)
        }
        .padding(cardPadding)
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: palette.cardCornerRadius, style: .continuous)
                .fill(palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: palette.cardCornerRadius, style: .continuous)
                        .strokeBorder(palette.cardStroke, lineWidth: palette.cardBorderWidth)
                )
                .shadow(
                    color: palette.cardShadow,
                    radius: palette.shadowRadius,
                    x: palette.shadowX,
                    y: palette.shadowY
                )
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
                        .font(TokenTypography.headline(palette: palette))
                        .foregroundStyle(palette.title)
                    Text(subtitle)
                        .font(TokenTypography.caption(palette: palette))
                        .foregroundStyle(palette.subtitle)
                }

                Spacer(minLength: 0)

                trailing
            }

            content
        }
        .padding(TokenSpacing.card)
        .accessibilityElement(children: .contain)
        .background(
            RoundedRectangle(cornerRadius: palette.sectionCornerRadius, style: .continuous)
                .fill(palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: palette.sectionCornerRadius, style: .continuous)
                        .strokeBorder(palette.cardStroke, lineWidth: palette.cardBorderWidth)
                )
                .shadow(
                    color: palette.cardShadow,
                    radius: palette.shadowRadius,
                    x: palette.shadowX,
                    y: palette.shadowY
                )
        )
    }
}

struct TokenCollapsibleSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let trailing: AnyView?
    let palette: TokenCostPalette
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        isExpanded.toggle()
                    } label: {
                        Label(
                            isExpanded ? AppLocalization.text("common.collapse") : AppLocalization.text("common.showMore"),
                            systemImage: isExpanded ? "chevron.up" : "chevron.down"
                        )
                        .font(.caption.weight(.medium))
                    }
                    .dashboardButtonStyle(
                        palette: palette,
                        compact: true,
                        fallback: .borderless
                    )
                    .foregroundStyle(palette.accent)
                }
            ),
            palette: palette
        ) {
            if isExpanded {
                content
                    .transition(TokenMotion.disclosureTransition(reduceMotion: reduceMotion))
            }
        }
        .animation(TokenMotion.resolved(TokenMotion.expand, reduceMotion: reduceMotion), value: isExpanded)
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
        minHeight: CGFloat = 48,
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
                    .font(TokenTypography.caption(weight: .semibold, palette: palette))
                    .foregroundStyle(palette.subtitle)
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .padding(TokenSpacing.small)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: palette.cardCornerRadius, style: .continuous),
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
                    .font(TokenTypography.caption(weight: .semibold, palette: palette))
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
                    .font(TokenTypography.caption(palette: palette))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)

                Spacer(minLength: 8)

                control
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(TokenTypography.caption(palette: palette))
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
        let cornerRadius: CGFloat = isPrimary ? palette.sectionCornerRadius : palette.cardCornerRadius
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let contentPadding: CGFloat = isPrimary ? TokenSpacing.section : TokenSpacing.card
        let shadow = role == .warning ? palette.surfaceShadow : palette.surfaceShadow
        let stroke = role == .warning ? Color.orange.opacity(0.22) : palette.surfaceStroke
        let glassTint: Color? = role == .warning ? Color.orange.opacity(0.14) : nil

        VStack(alignment: .leading, spacing: title == nil ? 12 : 16) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(TokenTypography.headline(palette: palette))
                            .foregroundStyle(palette.title)
                        if let subtitle {
                            Text(subtitle)
                                .font(TokenTypography.caption(palette: palette))
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
        if palette.usesWorkshopStyle {
            let fill = role == .secondary ? palette.surfaceSecondarySolidFill : palette.surfaceSolidFill
            let accessibleStroke = role == .warning ? Color.orange.opacity(0.58) : palette.surfaceAccessibleStroke
            content
                .background(
                    shape
                        .fill(fill)
                        .overlay(
                            shape.strokeBorder(
                                accessibleStroke,
                                lineWidth: palette.surfaceBorderWidth
                            )
                        )
                        .shadow(
                            color: shadow,
                            radius: palette.shadowRadius,
                            x: palette.shadowX,
                            y: palette.shadowY
                        )
                )
        } else if usesSolidFallback {
            let fill = role == .secondary ? palette.surfaceSecondarySolidFill : palette.surfaceSolidFill
            let accessibleStroke = role == .warning ? Color.orange.opacity(0.58) : palette.surfaceAccessibleStroke
            content
                .background(shape.fill(fill))
                .overlay(
                    shape.strokeBorder(
                        accessibleStroke,
                        lineWidth: role == .primary ? 1.2 : 1
                    )
                )
                .shadow(
                    color: shadow.opacity(0.55),
                    radius: role == .primary ? TokenShadow.medium.radius : TokenShadow.small.radius,
                    x: 0,
                    y: role == .primary ? TokenShadow.medium.y : TokenShadow.small.y
                )
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
                .shadow(
                    color: shadow,
                    radius: role == .primary ? TokenShadow.large.radius : TokenShadow.medium.radius,
                    x: 0,
                    y: role == .primary ? TokenShadow.large.y : TokenShadow.medium.y
                )
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
        if usesSolidFallback || palette.usesWorkshopStyle {
            content
                .background(shape.fill(palette.surfaceSecondarySolidFill))
                .overlay(
                    shape.strokeBorder(
                        stroke ?? palette.surfaceAccessibleStroke,
                        lineWidth: palette.usesWorkshopStyle
                            ? palette.surfaceBorderWidth
                            : max(lineWidth, 1)
                    )
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
    @Environment(\.tokenCostUsesWorkshopStyle) private var usesWorkshopStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var usesSolidFallback: Bool {
        reduceTransparency || colorSchemeContrast == .increased
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesWorkshopStyle {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        } else if #available(macOS 26, *), !usesSolidFallback {
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

enum TokenDashboardButtonFallback {
    case automatic
    case borderless
    case plain
    case settingsGlass
    case settingsGlassProminent
}

private struct WorkshopDashboardButtonStyle: ButtonStyle {
    let palette: TokenCostPalette
    let compact: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TokenTypography.caption(weight: .bold, palette: palette))
            .foregroundStyle(isEnabled ? palette.title : palette.subtitle.opacity(0.62))
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.vertical, compact ? 4 : 6)
            .background(
                RoundedRectangle(cornerRadius: compact ? 5 : 7, style: .continuous)
                    .fill(configuration.isPressed ? palette.accentSoft : palette.surfaceSolidFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: compact ? 5 : 7, style: .continuous)
                            .strokeBorder(
                                isEnabled ? palette.surfaceAccessibleStroke : palette.surfaceInnerStroke,
                                lineWidth: compact ? 1.8 : palette.surfaceBorderWidth
                            )
                    )
                    .shadow(
                        color: isEnabled ? palette.surfaceShadow.opacity(0.72) : .clear,
                        radius: 0,
                        x: configuration.isPressed ? 0 : 3,
                        y: configuration.isPressed ? 0 : 3
                    )
            )
            .offset(
                x: configuration.isPressed ? 2 : 0,
                y: configuration.isPressed ? 2 : 0
            )
            .opacity(isEnabled ? 1 : 0.72)
            .contentShape(Rectangle())
            .animation(
                TokenMotion.resolved(TokenMotion.micro, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

private struct DashboardButtonStyleModifier: ViewModifier {
    let palette: TokenCostPalette
    let compact: Bool
    let fallback: TokenDashboardButtonFallback

    @ViewBuilder
    func body(content: Content) -> some View {
        if palette.usesWorkshopStyle {
            content.buttonStyle(WorkshopDashboardButtonStyle(palette: palette, compact: compact))
        } else {
            switch fallback {
            case .automatic:
                content
            case .borderless:
                content.buttonStyle(.borderless)
            case .plain:
                content.buttonStyle(.plain)
            case .settingsGlass:
                content.settingsGlassButtonStyle()
            case .settingsGlassProminent:
                content.settingsGlassButtonStyle(prominent: true)
            }
        }
    }
}

struct TokenDashboardSymbolMark: View {
    let systemImage: String
    let tint: Color
    let palette: TokenCostPalette
    var size: CGFloat = 24
    var fontSize: CGFloat = 11

    @ViewBuilder
    var body: some View {
        if palette.usesWorkshopStyle {
            Image(systemName: systemImage)
                .font(.system(size: fontSize, weight: .black))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(palette.surfaceSolidFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(tint, lineWidth: 1.6)
                )
                .shadow(color: tint.opacity(0.28), radius: 0, x: 2, y: 2)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }
}

struct TokenThemedDivider: View {
    let palette: TokenCostPalette

    @ViewBuilder
    var body: some View {
        if palette.usesWorkshopStyle {
            Rectangle()
                .fill(palette.surfaceAccessibleStroke)
                .frame(height: 2)
                .accessibilityHidden(true)
        } else {
            Divider()
        }
    }
}

struct WorkshopToggleStyle: ToggleStyle {
    let palette: TokenCostPalette

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: TokenSpacing.small) {
                configuration.label
                Spacer(minLength: TokenSpacing.small)
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.caption.weight(.black))
                    .foregroundStyle(configuration.isOn ? palette.accentSecondary : palette.subtitle)
            }
            .font(TokenTypography.caption(weight: .bold, palette: palette))
            .foregroundStyle(palette.title)
            .padding(.horizontal, TokenSpacing.small)
            .padding(.vertical, TokenSpacing.xSmall)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isOn ? palette.accentSoft : palette.surfaceSolidFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(palette.surfaceAccessibleStroke, lineWidth: 1.6)
                    )
                    .shadow(color: palette.surfaceShadow.opacity(0.58), radius: 0, x: 2, y: 2)
            )
        }
        .buttonStyle(.plain)
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
                .font(TokenTypography.metric(size: 26, palette: palette))
                .foregroundStyle(palette.title)
                .lineLimit(2)
                .minimumScaleFactor(0.76)

            Text(subtitle)
                .font(TokenTypography.caption(palette: palette))
                .foregroundStyle(palette.subtitle)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TokenSpacing.card)
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: palette.sectionCornerRadius, style: .continuous),
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
                    .font(TokenTypography.caption(weight: .semibold, palette: palette))
                    .foregroundStyle(palette.subtitle)
            }

            Text(value)
                .font(TokenTypography.caption(weight: .medium, palette: palette))
                .foregroundStyle(palette.title)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, TokenSpacing.control)
        .padding(.vertical, TokenSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: palette.cardCornerRadius, style: .continuous),
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
                    .font(TokenTypography.subheadline(weight: .medium, palette: palette))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(valueLabel ?? TokenCostFormatters.tokens(value))
                    .font(TokenTypography.subheadline(weight: .semibold, palette: palette))
                    .foregroundStyle(palette.title)
            }

            TokenProgressBar(
                value: total > 0 ? value / total : 0,
                tint: tint,
                palette: palette,
                height: 8
            )

            if !suffix.isEmpty {
                Text(suffix)
                    .font(TokenTypography.caption2(palette: palette))
                    .foregroundStyle(palette.subtitle)
            }
        }
    }
}

struct TokenProgressBar: View {
    let value: Double
    let tint: Color
    let palette: TokenCostPalette
    var height: CGFloat = 6
    var minimumVisibleWidth: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            if palette.usesWorkshopStyle {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(palette.surfaceSecondarySolidFill)
                    Rectangle()
                        .fill(tint)
                        .frame(width: max(proxy.size.width * clampedValue, clampedValue > 0 ? minimumVisibleWidth : 0))
                }
                .overlay(
                    Rectangle()
                        .strokeBorder(palette.surfaceAccessibleStroke, lineWidth: 1.2)
                )
            } else {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(palette.trackBackground)
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(tint.gradient)
                        .frame(width: max(proxy.size.width * clampedValue, clampedValue > 0 ? minimumVisibleWidth : 0))
                }
            }
        }
        .frame(height: height)
        .animation(
            reduceMotion || !hasAppeared ? nil : TokenMotion.progress,
            value: clampedValue
        )
        .onAppear { hasAppeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AppLocalization.text("common.progress")))
        .accessibilityValue(Text(TokenCostFormatters.percent(clampedValue)))
    }
}

struct TokenStatusPill: View {
    let title: String
    let tint: Color
    let palette: TokenCostPalette
    var systemImage: String?

    @ViewBuilder
    var body: some View {
        if palette.usesWorkshopStyle {
            label
                .foregroundStyle(palette.title)
                .padding(.horizontal, TokenSpacing.small)
                .padding(.vertical, TokenSpacing.xSmall)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(tint, lineWidth: 1.6)
                        )
                        .shadow(color: tint.opacity(0.32), radius: 0, x: 2, y: 2)
                )
                .accessibilityElement(children: .combine)
        } else {
            label
                .foregroundStyle(tint)
                .padding(.horizontal, TokenSpacing.small)
                .padding(.vertical, TokenSpacing.xSmall)
                .background(tint.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.8))
                .accessibilityElement(children: .combine)
        }
    }

    private var label: some View {
        HStack(spacing: TokenSpacing.xSmall) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(palette.usesWorkshopStyle ? .black : .semibold))
            }
            Text(title)
                .font(TokenTypography.caption(weight: .semibold, palette: palette))
        }
    }
}

struct SourceStatusPill: View {
    let source: TokenCostSource
    let palette: TokenCostPalette

    var body: some View {
        TokenStatusPill(title: label, tint: foreground, palette: palette)
    }

    private var foreground: Color {
        switch source.status {
        case .available: return palette.accent
        case .locked: return palette.warning
        case .unsupported: return palette.warning.opacity(0.82)
        case .missing: return palette.danger
        case .unknown: return palette.subtitle
        }
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
                .font(TokenTypography.caption(palette: palette))
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
                .font(TokenTypography.caption(palette: palette))
                .foregroundStyle(palette.subtitle)

            Button {
                pageIndex = max(clampedPageIndex - 1, 0)
            } label: {
                Label(AppLocalization.text("pagination.previous"), systemImage: "chevron.left")
            }
            .dashboardButtonStyle(palette: palette, compact: true, fallback: .settingsGlass)
            .controlSize(.small)
            .disabled(clampedPageIndex == 0)

            Button {
                pageIndex = min(clampedPageIndex + 1, pageCount - 1)
            } label: {
                Label(AppLocalization.text("pagination.next"), systemImage: "chevron.right")
            }
            .dashboardButtonStyle(palette: palette, compact: true, fallback: .settingsGlass)
            .controlSize(.small)
            .disabled(clampedPageIndex >= pageCount - 1)
        }
    }
}

extension View {
    func dashboardButtonStyle(
        palette: TokenCostPalette,
        compact: Bool = false,
        fallback: TokenDashboardButtonFallback = .automatic
    ) -> some View {
        modifier(DashboardButtonStyleModifier(
            palette: palette,
            compact: compact,
            fallback: fallback
        ))
    }

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
