import SwiftUI
import CodexTokenCostCore

enum CodexDashboardPage: String, CaseIterable, Identifiable {
    case total
    case opencode
    case codex
    case skills

    var id: String { rawValue }
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
    @State private var selectedPage: CodexDashboardPage = .total
    @State private var didOpenCodexSourcePrompt = false
    @State private var showCredentialBootstrapError = false
    @State private var credentialBootstrapErrorMessage = ""

    private var palette: TokenCostPalette {
        TokenCostPalette(theme: appPreferencesModel.preferences.theme)
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
                        .transition(.move(edge: .top).combined(with: .opacity))
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
                        Label(AppLocalization.text("tab.total"), systemImage: "square.grid.2x2")
                    }

                    OpenCodePageView(
                        model: openCodeModel,
                        appPreferencesModel: appPreferencesModel,
                        balanceManager: balanceManager,
                        palette: palette
                    )
                        .tag(CodexDashboardPage.opencode)
                        .tabItem {
                            Label(AppLocalization.text("tab.opencode"), systemImage: "externaldrive")
                        }

                    CodexPageView(model: codexModel, balanceManager: balanceManager, appPreferencesModel: appPreferencesModel, palette: palette)
                        .tag(CodexDashboardPage.codex)
                        .tabItem {
                            Label(AppLocalization.text("tab.codex"), systemImage: "terminal")
                        }

                    OpenCodeSkillsPageView(model: skillsModel, palette: palette)
                        .tag(CodexDashboardPage.skills)
                        .tabItem {
                            Label(AppLocalization.text("tab.skills"), systemImage: "gearshape.2")
                        }
                }
                .task {
                    openCodeModel.bootstrapIfNeeded()
                    codexModel.bootstrapIfNeeded()
                    openCodexSourcePromptIfNeeded()
                    updateChecker.checkForUpdate()
                    if appPreferencesModel.preferences.balanceEnabled {
                        let mode = appPreferencesModel.preferences.credentialSourceMode
                        let bootstrapResult = await CredentialBootstrapService.shared.bootstrap(mode: mode)
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
        .animation(.easeInOut(duration: 0.25), value: isAnyRefreshing)
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
                Label(AppLocalization.text("tab.action.refreshAll"), systemImage: "arrow.clockwise")
            }
            .disabled(isAnyRefreshing)
        case .opencode:
            Button {
                openCodeModel.rescanSources()
            } label: {
                Label(AppLocalization.text("sidebar.action.rescan"), systemImage: "arrow.clockwise")
            }
            .disabled(openCodeModel.isBootstrapping || openCodeModel.isRefreshing)
        case .codex:
            Button {
                codexModel.refresh()
            } label: {
                Label(AppLocalization.text("settings.action.refreshCodex"), systemImage: "arrow.clockwise")
            }
            .disabled(codexModel.isBootstrapping || codexModel.isRefreshing)
        case .skills:
            Button {
                skillsModel.refresh()
            } label: {
                Label(AppLocalization.text("skills.action.refresh"), systemImage: "arrow.clockwise")
            }
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
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                Text(AppLocalization.text("update.checkForUpdates"))
                    .font(.caption2)
            }

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
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
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
                    Text(AppLocalization.text("update.label"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(palette.accent.opacity(0.1)))
                        .overlay(Capsule().stroke(palette.accent.opacity(0.2)))
                }
                .help(version)

                Button {
                    updateChecker.dismissUpdate()
                } label: {
                    Text(AppLocalization.text("update.later"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .downloading(let progress):
            Button {} label: {
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
            }
            .disabled(true)
            .help(AppLocalization.format("update.downloading", Int(progress * 100)))

        case .downloadComplete:
            Button {
                updateChecker.installUpdate()
            } label: {
                Text(AppLocalization.text("update.install"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(palette.accent))
            }

        case .error:
            Button {
                updateChecker.startDownload()
            } label: {
                Text(AppLocalization.text("update.retry"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.red.opacity(0.1)))
                    .overlay(Capsule().stroke(Color.red.opacity(0.2)))
            }
            .help(updateChecker.errorMessage)
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
