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
        TokenCostPalette(theme: appPreferencesModel.preferences.theme)
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
            .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
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
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 8, height: 8)

                    Text(AppLocalization.text("balance.title"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.title)
                }

                Text(lastRefreshSubtitle)
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
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
            HStack(alignment: .center, spacing: 6) {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 6, height: 6)

                Text(AppLocalization.text("balance.title"))
                    .font(.system(size: BalanceFloatingPanelLayout.minimalPanelTitleFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                ProviderLogoMark(provider: .opencodeGo, size: 18, tint: palette.accent)
                    .frame(width: 24, height: 24)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(palette.accentSoft)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.text("balance.empty.title"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.title)

                    Text(AppLocalization.text("balance.empty.subtitle"))
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                }
            }

            Text(AppLocalization.text("balance.empty.body"))
                .font(.caption)
                .foregroundStyle(palette.subtitle)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BalanceFloatingPanelLayout.tilePaddingNormal)
        .background {
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

    private var minimalEmptyState: some View {
        HStack(alignment: .center, spacing: 8) {
            ProviderLogoMark(provider: .opencodeGo, size: 16, tint: palette.accent)
                .frame(width: 20, height: 20)
                .padding(4)
                .background(
                    Circle()
                        .fill(palette.accentSoft)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.text("balance.empty.title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)

                Text(AppLocalization.text("balance.notRefreshed"))
                    .font(.caption2)
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: BalanceFloatingPanelLayout.minimalTileHeight, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.tileCornerRadius, style: .continuous)
                .fill(palette.surfaceSolidFill)
                .overlay(
                    RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.tileCornerRadius, style: .continuous)
                        .strokeBorder(palette.surfaceStroke.opacity(0.9), lineWidth: 1)
                )
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
                Circle()
                    .fill(hovered.wrappedValue ? palette.surfaceSolidFill.opacity(0.72) : .clear)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                hovered.wrappedValue ? palette.surfaceAccessibleStroke.opacity(0.35) : .clear,
                                lineWidth: 1
                            )
                    )

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
            .contentShape(Circle())
        }
        .buttonStyle(.liquidGlass)
        .disabled(isBusy)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text(accessibilityHelp ?? accessibilityValue))
        .help(accessibilityHelp ?? "\(accessibilityLabel) · \(accessibilityValue)")
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                hovered.wrappedValue = hovering
            }
        }
    }

    private var shellBackdrop: some View {
        Group {
            if #available(macOS 26, *) {
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
        .overlay(
            RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.shellCornerRadius, style: .continuous)
                .strokeBorder(palette.surfaceAccessibleStroke.opacity(0.55), lineWidth: BalanceFloatingPanelLayout.shellStrokeWidth)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.shellCornerRadius, style: .continuous)
                .strokeBorder(palette.surfaceAccessibleStroke.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: palette.surfaceShadow, radius: 18, x: 0, y: 10)
    }
}
