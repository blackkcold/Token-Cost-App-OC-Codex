import SwiftUI
import CodexTokenCostCore

enum CodexDashboardPage: String, CaseIterable, Identifiable {
    case total
    case opencode
    case codex
    case skills

    var id: String { rawValue }

    func systemImage(usesWorkshopStyle: Bool) -> String {
        guard usesWorkshopStyle else {
            switch self {
            case .total: return "square.grid.2x2"
            case .opencode: return "externaldrive"
            case .codex: return "terminal"
            case .skills: return "gearshape.2"
            }
        }

        switch self {
        case .total: return "rectangle.3.group.fill"
        case .opencode: return "externaldrive.fill.badge.checkmark"
        case .codex: return "apple.terminal.fill"
        case .skills: return "wrench.and.screwdriver.fill"
        }
    }
}

struct ContentView: View {
    @ObservedObject var openCodeModel: TokenCostModel
    @ObservedObject var codexModel: CodexSessionModel
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @ObservedObject var balanceManager: BalanceManager
    @ObservedObject var updateChecker: UpdateCheckerModel
    @ObservedObject var skillsModel: OpenCodeSkillsModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPage: CodexDashboardPage = .total
    @State private var didOpenCodexSourcePrompt = false
    @State private var showCredentialBootstrapError = false
    @State private var credentialBootstrapErrorMessage = ""

    private var palette: TokenCostPalette {
        TokenCostPalette(accentPalette: appPreferencesModel.preferences.accentPalette)
    }

    private var isAnyRefreshing: Bool {
        openCodeModel.isBootstrapping || openCodeModel.isRefreshing
            || codexModel.isBootstrapping || codexModel.isRefreshing
    }

    var body: some View {
        ZStack {
            palette.pageBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if isAnyRefreshing {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(palette.accent)
                        .transition(TokenMotion.disclosureTransition(reduceMotion: reduceMotion))
                        .padding(.horizontal, 4)
                }

                TabView(selection: $selectedPage) {
                    TotalView(
                        openCodeModel: openCodeModel,
                        codexModel: codexModel,
                        appPreferencesModel: appPreferencesModel,
                        balanceManager: balanceManager,
                        palette: palette
                    )
                    .tag(CodexDashboardPage.total)
                    .tabItem {
                        Label(
                            AppLocalization.text("tab.total"),
                            systemImage: CodexDashboardPage.total.systemImage(usesWorkshopStyle: palette.usesWorkshopStyle)
                        )
                    }

                    OpenCodePageView(
                        model: openCodeModel,
                        appPreferencesModel: appPreferencesModel,
                        balanceManager: balanceManager,
                        palette: palette
                    )
                        .tag(CodexDashboardPage.opencode)
                        .tabItem {
                            Label(
                                AppLocalization.text("tab.opencode"),
                                systemImage: CodexDashboardPage.opencode.systemImage(usesWorkshopStyle: palette.usesWorkshopStyle)
                            )
                        }

                    CodexPageView(model: codexModel, balanceManager: balanceManager, appPreferencesModel: appPreferencesModel, palette: palette)
                        .tag(CodexDashboardPage.codex)
                        .tabItem {
                            Label(
                                AppLocalization.text("tab.codex"),
                                systemImage: CodexDashboardPage.codex.systemImage(usesWorkshopStyle: palette.usesWorkshopStyle)
                            )
                        }

                    OpenCodeSkillsPageView(model: skillsModel, palette: palette)
                        .tag(CodexDashboardPage.skills)
                        .tabItem {
                            Label(
                                AppLocalization.text("tab.skills"),
                                systemImage: CodexDashboardPage.skills.systemImage(usesWorkshopStyle: palette.usesWorkshopStyle)
                            )
                        }
                }
                .task {
                    openCodeModel.bootstrapIfNeeded()
                    codexModel.bootstrapIfNeeded()
                    openCodexSourcePromptIfNeeded()
                    updateChecker.checkForUpdate()
                    if appPreferencesModel.preferences.balanceEnabled {
                        let mode = appPreferencesModel.preferences.credentialSourceMode
                        let providers = Set(appPreferencesModel.effectiveBalanceConfiguration.enabledBalanceProviders)
                        let bootstrapResult = await CredentialBootstrapService.shared.bootstrap(
                            mode: mode,
                            enabledProviders: providers
                        )
                        if case .failed(let error) = bootstrapResult {
                            credentialBootstrapErrorMessage = error
                            showCredentialBootstrapError = true
                        }
                        await balanceManager.refresh()
                    }
                }
                .onChange(of: codexModel.shouldPromptForSourceConfirmation) { _, shouldPrompt in
                    guard shouldPrompt else { return }
                    openCodexSourcePromptIfNeeded()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                toolbarRefreshButton
                updateControls
            }
        }
        .animation(TokenMotion.resolved(TokenMotion.expand, reduceMotion: reduceMotion), value: isAnyRefreshing)
        .alert(AppLocalization.text("balance.bootstrap.error.title"), isPresented: $showCredentialBootstrapError) {
            Button(AppLocalization.text("settings.action.close"), role: .cancel) {}
        } message: {
            Text(credentialBootstrapErrorMessage)
        }
        .onChange(of: updateChecker.state) { _, newState in
            if case .upToDate = newState {
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    updateChecker.dismissUpdate()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                appPreferencesModel.persistPreferences()
                openCodeModel.persistSettings()
                codexModel.persistSettings()
            } else if newPhase == .active,
                      appPreferencesModel.preferences.balanceEnabled,
                      balanceManager.shouldRefresh(intervalSeconds: appPreferencesModel.preferences.balanceRefreshSeconds) {
                Task { await balanceManager.refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appWillRelaunchForUpdate)) { _ in
            appPreferencesModel.persistPreferences()
            openCodeModel.persistSettings()
            codexModel.persistSettings()
        }
    }

    @ViewBuilder
    private var toolbarRefreshButton: some View {
        switch selectedPage {
        case .total:
            Button {
                openCodeModel.rescanSources()
                codexModel.refresh()
            } label: {
                dashboardActionLabel(
                    AppLocalization.text("tab.action.refreshAll"),
                    systemImage: "arrow.clockwise",
                    tint: palette.accent
                )
            }
            .dashboardButtonStyle(palette: palette, compact: true)
            .disabled(isAnyRefreshing)
        case .opencode:
            Button {
                openCodeModel.rescanSources()
            } label: {
                dashboardActionLabel(
                    AppLocalization.text("sidebar.action.rescan"),
                    systemImage: "arrow.clockwise",
                    tint: palette.accent
                )
            }
            .dashboardButtonStyle(palette: palette, compact: true)
            .disabled(openCodeModel.isBootstrapping || openCodeModel.isRefreshing)
        case .codex:
            Button {
                codexModel.refresh()
            } label: {
                dashboardActionLabel(
                    AppLocalization.text("settings.action.refreshCodex"),
                    systemImage: "arrow.clockwise",
                    tint: palette.accent
                )
            }
            .dashboardButtonStyle(palette: palette, compact: true)
            .disabled(codexModel.isBootstrapping || codexModel.isRefreshing)
        case .skills:
            Button {
                skillsModel.refresh()
            } label: {
                dashboardActionLabel(
                    AppLocalization.text("skills.action.refresh"),
                    systemImage: "arrow.clockwise",
                    tint: palette.accent
                )
            }
            .dashboardButtonStyle(palette: palette, compact: true)
            .disabled(skillsModel.isRefreshing)
        }
    }

    @ViewBuilder
    private var updateControls: some View {
        switch updateChecker.state {
        case .idle:
            Button {
                updateChecker.manualCheck()
            } label: {
                dashboardActionLabel(
                    AppLocalization.text("update.checkForUpdates"),
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: palette.accentSecondary
                )
            }
            .dashboardButtonStyle(palette: palette, compact: true)

        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                Text(AppLocalization.text("update.checking"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .upToDate(let version):
            HStack(spacing: 4) {
                TokenDashboardSymbolMark(
                    systemImage: "checkmark",
                    tint: palette.success,
                    palette: palette,
                    size: 20,
                    fontSize: 9
                )
                Text(AppLocalization.format("update.upToDate", version))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
            }

        case .updateAvailable(let version):
            HStack(spacing: 6) {
                Button {
                    updateChecker.startDownload()
                } label: {
                    if palette.usesWorkshopStyle {
                        Text(AppLocalization.text("update.label"))
                    } else {
                        Text(AppLocalization.text("update.label"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(palette.accent.opacity(0.1)))
                            .overlay(Capsule().stroke(palette.accent.opacity(0.2)))
                    }
                }
                .dashboardButtonStyle(palette: palette, compact: true)
                .help(version)

                Button {
                    updateChecker.dismissUpdate()
                } label: {
                    Text(AppLocalization.text("update.later"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .dashboardButtonStyle(palette: palette, compact: true)
            }

        case .downloading(let progress):
            Text(AppLocalization.text("update.label"))
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.accent.opacity(0.06))
                            Capsule()
                                .fill(palette.accent.opacity(0.2))
                                .frame(width: max(CGFloat(0), geo.size.width * progress))
                        }
                    }
                }
                .overlay(Capsule().stroke(palette.accent.opacity(0.2)))
                .accessibilityElement()
                .accessibilityLabel(Text(AppLocalization.text("update.label")))
                .accessibilityValue(Text(AppLocalization.format("update.downloading", Int(progress * 100))))
                .help(AppLocalization.format("update.downloading", Int(progress * 100)))

        case .downloadComplete:
            Button {
                updateChecker.installUpdate()
            } label: {
                if palette.usesWorkshopStyle {
                    Text(AppLocalization.text("update.install"))
                } else {
                    Text(AppLocalization.text("update.install"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(palette.accent))
                }
            }
            .dashboardButtonStyle(palette: palette, compact: true)

        case .error:
            Button {
                updateChecker.startDownload()
            } label: {
                if palette.usesWorkshopStyle {
                    Text(AppLocalization.text("update.retry"))
                } else {
                    Text(AppLocalization.text("update.retry"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(palette.danger)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(palette.danger.opacity(0.1)))
                        .overlay(Capsule().stroke(palette.danger.opacity(0.2)))
                }
            }
            .dashboardButtonStyle(palette: palette, compact: true)
            .help(updateChecker.errorMessage)
        }
    }

    @ViewBuilder
    private func dashboardActionLabel(
        _ title: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        if palette.usesWorkshopStyle {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(tint)
                Text(title)
                    .font(TokenTypography.caption(weight: .bold, palette: palette))
            }
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    private func openCodexSourcePromptIfNeeded() {
        guard codexModel.shouldPromptForSourceConfirmation, !didOpenCodexSourcePrompt else {
            return
        }
        didOpenCodexSourcePrompt = true
        WindowOpeningSupport.openWindow(id: "settings", openWindow: openWindow)
    }
}
