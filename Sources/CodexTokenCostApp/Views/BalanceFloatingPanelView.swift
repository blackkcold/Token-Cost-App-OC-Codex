import SwiftUI
import CodexTokenCostCore

struct BalanceFloatingPanelView: View {
    @ObservedObject var balanceManager: BalanceManager
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var refreshButtonHovered = false
    @State private var displayModeButtonHovered = false
    @State private var pinButtonHovered = false
    @State private var closeButtonHovered = false

    let onRequestClose: () -> Void

    private var palette: TokenCostPalette {
        TokenCostPalette(accentPalette: appPreferencesModel.preferences.accentPalette)
    }

    private var displayMode: BalanceFloatingPanelDisplayMode {
        appPreferencesModel.preferences.balanceFloatingPanelDisplayMode
    }

    private var nextDisplayMode: BalanceFloatingPanelDisplayMode {
        displayMode == .normal ? .minimal : .normal
    }

    private var displayModeToggleLabel: String {
        displayMode == .normal
            ? AppLocalization.text("balance.floatingPanel.displayMode.compact")
            : AppLocalization.text("balance.floatingPanel.displayMode.expand")
    }

    private var displayModeToggleValue: String {
        displayMode == .normal
            ? AppLocalization.text("settings.balance.floatingPanel.displayMode.normal")
            : AppLocalization.text("settings.balance.floatingPanel.displayMode.minimal")
    }

    private var displayModeToggleHelp: String {
        displayMode == .normal
            ? AppLocalization.text("balance.floatingPanel.displayMode.compact.help")
            : AppLocalization.text("balance.floatingPanel.displayMode.expand.help")
    }

    private var displayModeToggleImageName: String {
        displayMode == .normal ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
    }

    private var sortedSnapshots: [BalanceSnapshot] {
        appPreferencesModel.sortBalanceSnapshots(balanceManager.snapshots)
    }

    private var lastRefreshSubtitle: String {
        balanceManager.lastRefreshTime.map {
            AppLocalization.format("balance.lastRefresh", TokenCostFormatters.localDateTime($0))
        } ?? AppLocalization.text("balance.notRefreshed")
    }

    var body: some View {
        let panelSize = BalanceFloatingPanelLayout.panelSize(for: displayMode, providerCount: sortedSnapshots.count)

        panelBody(width: panelSize.width)
            .id(displayMode)
            .transition(.opacity)
            .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
            .preferredColorScheme(appPreferencesModel.preferences.appearanceMode.preferredColorScheme)
            .animation(TokenMotion.resolved(TokenMotion.contentSwap, reduceMotion: reduceMotion), value: displayMode)
    }

    @ViewBuilder
    private func panelBody(width: CGFloat) -> some View {
        if displayMode == .normal {
            panelShell(width: width)
        } else {
            minimalPanelShell()
        }
    }

    private func panelShell(width: CGFloat) -> some View {
        let columns = BalanceFloatingPanelLayout.gridColumns(
            for: width,
            providerCount: sortedSnapshots.count,
            displayMode: displayMode
        )

        return VStack(alignment: .leading, spacing: BalanceFloatingPanelLayout.sectionSpacing) {
            widgetHeader

            if sortedSnapshots.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: columns,
                        alignment: .leading,
                        spacing: BalanceFloatingPanelLayout.tileSpacing
                    ) {
                        ForEach(sortedSnapshots) { snapshot in
                            BalanceProviderCardView(snapshot: snapshot, palette: palette, displayMode: appPreferencesModel.preferences.balanceDisplayMode)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(BalanceFloatingPanelLayout.contentPadding)
        .background {
            shellBackdrop
        }
    }

    private func minimalPanelShell() -> some View {
        return VStack(alignment: .leading, spacing: BalanceFloatingPanelLayout.minimalPanelHeaderSpacing) {
            minimalWidgetHeader

            if sortedSnapshots.isEmpty {
                minimalEmptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(
                        alignment: .top,
                        spacing: BalanceFloatingPanelLayout.minimalTileSpacing
                    ) {
                        ForEach(sortedSnapshots) { snapshot in
                            BalanceMinimalProviderTile(snapshot: snapshot, palette: palette, displayMode: appPreferencesModel.preferences.balanceDisplayMode)
                                .frame(
                                    width: BalanceFloatingPanelLayout.minimalTileWidth,
                                    height: BalanceFloatingPanelLayout.minimalTileHeight,
                                    alignment: .topLeading
                                )
                        }
                    }
                    .padding(.bottom, 1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(BalanceFloatingPanelLayout.contentPadding)
        .background {
            shellBackdrop
        }
    }

    private var widgetHeader: some View {
        HStack(alignment: .top, spacing: BalanceFloatingPanelLayout.headerSpacing) {
            if palette.usesWorkshopStyle {
                WorkshopBalanceTitleMark(
                    title: AppLocalization.text("balance.title"),
                    subtitle: lastRefreshSubtitle,
                    palette: palette
                )
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle()
                            .fill(palette.accent)
                            .frame(width: 8, height: 8)

                        Text(AppLocalization.text("balance.title"))
                            .font(TokenTypography.subheadline(weight: .bold, palette: palette))
                            .foregroundStyle(palette.title)
                    }

                    Text(lastRefreshSubtitle)
                        .font(TokenTypography.caption(palette: palette))
                        .foregroundStyle(palette.subtitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                panelActionButton(
                    accessibilityLabel: AppLocalization.text("menu.refreshBalance"),
                    accessibilityValue: balanceManager.isRefreshing ? AppLocalization.text("common.refreshing") : AppLocalization.text("common.ready"),
                    systemImage: "arrow.clockwise",
                    tint: balanceManager.isRefreshing ? palette.subtitle : palette.accent,
                    isBusy: balanceManager.isRefreshing,
                    size: BalanceFloatingPanelLayout.panelActionButtonSize,
                    hovered: $refreshButtonHovered
                ) {
                    Task { await balanceManager.refresh(force: true) }
                }

                displayModeToggleButton(
                    size: BalanceFloatingPanelLayout.panelActionButtonSize,
                    imageFontSize: 12
                )

                panelActionButton(
                    accessibilityLabel: appPreferencesModel.preferences.balanceFloatingPanelAlwaysOnTop
                        ? AppLocalization.text("balance.floatingPanel.unpin")
                        : AppLocalization.text("balance.floatingPanel.pin"),
                    accessibilityValue: appPreferencesModel.preferences.balanceFloatingPanelAlwaysOnTop
                        ? AppLocalization.text("balance.floatingPanel.pinned")
                        : AppLocalization.text("balance.floatingPanel.unpinned"),
                    systemImage: appPreferencesModel.preferences.balanceFloatingPanelAlwaysOnTop ? "pin.fill" : "pin",
                    tint: appPreferencesModel.preferences.balanceFloatingPanelAlwaysOnTop ? palette.accent : palette.subtitle,
                    isBusy: false,
                    size: BalanceFloatingPanelLayout.panelActionButtonSize,
                    hovered: $pinButtonHovered
                ) {
                    appPreferencesModel.updatePreferences { preferences in
                        preferences.balanceFloatingPanelAlwaysOnTop.toggle()
                    }
                }

                panelActionButton(
                    accessibilityLabel: AppLocalization.text("settings.action.close"),
                    accessibilityValue: AppLocalization.text("menu.balanceFloatingPanel.hide"),
                    systemImage: "xmark",
                    tint: palette.subtitle,
                    isBusy: false,
                    size: BalanceFloatingPanelLayout.panelActionButtonSize,
                    hovered: $closeButtonHovered,
                    action: onRequestClose
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var minimalWidgetHeader: some View {
        HStack(alignment: .center, spacing: BalanceFloatingPanelLayout.minimalPanelHeaderSpacing) {
            if palette.usesWorkshopStyle {
                WorkshopBalanceTitleMark(
                    title: AppLocalization.text("balance.title"),
                    subtitle: nil,
                    palette: palette,
                    compact: true
                )
            } else {
                HStack(alignment: .center, spacing: 6) {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 6, height: 6)

                    Text(AppLocalization.text("balance.title"))
                        .font(TokenTypography.metric(
                            size: BalanceFloatingPanelLayout.minimalPanelTitleFontSize,
                            weight: .bold,
                            palette: palette
                        ))
                        .foregroundStyle(palette.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                panelActionButton(
                    accessibilityLabel: AppLocalization.text("menu.refreshBalance"),
                    accessibilityValue: balanceManager.isRefreshing ? AppLocalization.text("common.refreshing") : AppLocalization.text("common.ready"),
                    systemImage: "arrow.clockwise",
                    tint: balanceManager.isRefreshing ? palette.subtitle : palette.accent,
                    isBusy: balanceManager.isRefreshing,
                    size: BalanceFloatingPanelLayout.minimalPanelButtonSize,
                    imageFontSize: 10,
                    hovered: $refreshButtonHovered
                ) {
                    Task { await balanceManager.refresh(force: true) }
                }

                displayModeToggleButton(
                    size: BalanceFloatingPanelLayout.minimalPanelButtonSize,
                    imageFontSize: 10
                )

                panelActionButton(
                    accessibilityLabel: appPreferencesModel.preferences.balanceFloatingPanelAlwaysOnTop
                        ? AppLocalization.text("balance.floatingPanel.unpin")
                        : AppLocalization.text("balance.floatingPanel.pin"),
                    accessibilityValue: appPreferencesModel.preferences.balanceFloatingPanelAlwaysOnTop
                        ? AppLocalization.text("balance.floatingPanel.pinned")
                        : AppLocalization.text("balance.floatingPanel.unpinned"),
                    systemImage: appPreferencesModel.preferences.balanceFloatingPanelAlwaysOnTop ? "pin.fill" : "pin",
                    tint: appPreferencesModel.preferences.balanceFloatingPanelAlwaysOnTop ? palette.accent : palette.subtitle,
                    isBusy: false,
                    size: BalanceFloatingPanelLayout.minimalPanelButtonSize,
                    imageFontSize: 10,
                    hovered: $pinButtonHovered
                ) {
                    appPreferencesModel.updatePreferences { preferences in
                        preferences.balanceFloatingPanelAlwaysOnTop.toggle()
                    }
                }

                panelActionButton(
                    accessibilityLabel: AppLocalization.text("settings.action.close"),
                    accessibilityValue: AppLocalization.text("menu.balanceFloatingPanel.hide"),
                    systemImage: "xmark",
                    tint: palette.subtitle,
                    isBusy: false,
                    size: BalanceFloatingPanelLayout.minimalPanelButtonSize,
                    imageFontSize: 10,
                    hovered: $closeButtonHovered,
                    action: onRequestClose
                )
            }
        }
    }

    private func displayModeToggleButton(size: CGFloat, imageFontSize: CGFloat) -> some View {
        panelActionButton(
            accessibilityLabel: displayModeToggleLabel,
            accessibilityValue: displayModeToggleValue,
            accessibilityHelp: displayModeToggleHelp,
            systemImage: displayModeToggleImageName,
            tint: palette.subtitle,
            isBusy: false,
            size: size,
            imageFontSize: imageFontSize,
            hovered: $displayModeButtonHovered
        ) {
            let newMode = nextDisplayMode
            appPreferencesModel.updatePreferences { preferences in
                preferences.balanceFloatingPanelDisplayMode = newMode
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if palette.usesWorkshopStyle {
                    WorkshopBalanceProviderMark(
                        provider: .opencodeGo,
                        palette: palette,
                        size: 18,
                        plateSize: 34
                    )
                } else {
                    ProviderLogoMark(provider: .opencodeGo, size: 18, tint: palette.accent)
                        .frame(width: 24, height: 24)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(palette.accentSoft)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.text("balance.empty.title"))
                        .font(TokenTypography.subheadline(weight: .bold, palette: palette))
                        .foregroundStyle(palette.title)

                    Text(AppLocalization.text("balance.empty.subtitle"))
                        .font(TokenTypography.caption(palette: palette))
                        .foregroundStyle(palette.subtitle)
                }
            }

            Text(AppLocalization.text("balance.empty.body"))
                .font(TokenTypography.caption(palette: palette))
                .foregroundStyle(palette.subtitle)
                .lineLimit(4)

            if palette.usesWorkshopStyle {
                WorkshopBalanceQuotaMeter(
                    value: 0.36,
                    tint: palette.accentSecondary,
                    palette: palette,
                    segmentCount: BalanceWorkshopChartLayout.normalSegmentCount,
                    height: 8
                )
                .frame(maxWidth: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BalanceFloatingPanelLayout.tilePaddingNormal)
        .background {
            if palette.usesWorkshopStyle {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.surfaceSecondarySolidFill.opacity(0.86))
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .fill(palette.accentSecondary)
                            .frame(width: 42, height: 4)
                            .padding(.leading, 14)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(palette.surfaceAccessibleStroke, lineWidth: 2)
                    )
                    .shadow(color: palette.surfaceShadow.opacity(0.72), radius: 0, x: 3, y: 3)
            } else {
                RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.tileCornerRadius, style: .continuous)
                    .fill(palette.surfaceSolidFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.tileCornerRadius, style: .continuous)
                            .strokeBorder(palette.surfaceStroke.opacity(0.95), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.tileCornerRadius, style: .continuous)
                            .strokeBorder(palette.surfaceAccessibleStroke.opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: palette.surfaceShadow, radius: 14, x: 0, y: 8)
            }
        }
    }

    private var minimalEmptyState: some View {
        HStack(alignment: .center, spacing: 8) {
            if palette.usesWorkshopStyle {
                WorkshopBalanceProviderMark(
                    provider: .opencodeGo,
                    palette: palette,
                    size: 14,
                    plateSize: 28
                )
            } else {
                ProviderLogoMark(provider: .opencodeGo, size: 16, tint: palette.accent)
                    .frame(width: 20, height: 20)
                    .padding(4)
                    .background(
                        Circle()
                            .fill(palette.accentSoft)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.text("balance.empty.title"))
                    .font(TokenTypography.caption(weight: .bold, palette: palette))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)

                Text(AppLocalization.text("balance.notRefreshed"))
                    .font(TokenTypography.caption2(palette: palette))
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: BalanceFloatingPanelLayout.minimalTileHeight, alignment: .leading)
        .padding(10)
        .background {
            if palette.usesWorkshopStyle {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.surfaceSecondarySolidFill.opacity(0.86))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(palette.surfaceAccessibleStroke, lineWidth: 1.8)
                    )
                    .shadow(color: palette.surfaceShadow.opacity(0.68), radius: 0, x: 2, y: 2)
            } else {
                RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.tileCornerRadius, style: .continuous)
                    .fill(palette.surfaceSolidFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.tileCornerRadius, style: .continuous)
                            .strokeBorder(palette.surfaceStroke.opacity(0.9), lineWidth: 1)
                    )
            }
        }
    }

    private func panelActionButton(
        accessibilityLabel: String,
        accessibilityValue: String,
        accessibilityHelp: String? = nil,
        systemImage: String,
        tint: Color,
        isBusy: Bool,
        size: CGFloat,
        imageFontSize: CGFloat = 12,
        hovered: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Group {
                    if palette.usesWorkshopStyle {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(hovered.wrappedValue ? palette.accentSoft : palette.surfaceSecondarySolidFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(palette.surfaceAccessibleStroke, lineWidth: 2)
                            )
                            .shadow(color: palette.surfaceShadow.opacity(0.58), radius: 0, x: 2, y: 2)
                    } else {
                        Circle()
                            .fill(hovered.wrappedValue ? palette.surfaceSolidFill.opacity(0.72) : .clear)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        hovered.wrappedValue ? palette.surfaceAccessibleStroke.opacity(0.35) : .clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                }

                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(tint)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: imageFontSize, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.liquidGlass)
        .disabled(isBusy)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text(accessibilityHelp ?? accessibilityValue))
        .help(accessibilityHelp ?? "\(accessibilityLabel) · \(accessibilityValue)")
        .onHover { hovering in
            withAnimation(TokenMotion.resolved(TokenMotion.micro, reduceMotion: reduceMotion)) {
                hovered.wrappedValue = hovering
            }
        }
    }

    private var shellBackdrop: some View {
        Group {
            if palette.usesWorkshopStyle {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.surfaceSolidFill)
                    .overlay {
                        WorkshopBalancePanelBackdrop(palette: palette)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(palette.surfaceAccessibleStroke, lineWidth: 2.5)
                    )
                    .shadow(color: palette.surfaceShadow.opacity(0.68), radius: 0, x: 5, y: 5)
            } else if #available(macOS 26, *) {
                RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.shellCornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        .regular.tint(palette.accentSoft),
                        in: .rect(cornerRadius: BalanceFloatingPanelLayout.shellCornerRadius)
                    )
            } else {
                VisualEffectBackground(
                    cornerRadius: BalanceFloatingPanelLayout.shellCornerRadius,
                    material: .hudWindow
                )
            }
        }
        .overlay {
            if !palette.usesWorkshopStyle {
                RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.shellCornerRadius, style: .continuous)
                    .strokeBorder(
                        palette.surfaceAccessibleStroke.opacity(0.55),
                        lineWidth: BalanceFloatingPanelLayout.shellStrokeWidth
                    )
            }
        }
        .overlay {
            if !palette.usesWorkshopStyle {
                RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.shellCornerRadius, style: .continuous)
                    .strokeBorder(palette.surfaceAccessibleStroke.opacity(0.35), lineWidth: 0.5)
            }
        }
        .shadow(
            color: palette.usesWorkshopStyle ? .clear : palette.surfaceShadow,
            radius: palette.usesWorkshopStyle ? 0 : 18,
            x: 0,
            y: palette.usesWorkshopStyle ? 0 : 10
        )
    }
}
