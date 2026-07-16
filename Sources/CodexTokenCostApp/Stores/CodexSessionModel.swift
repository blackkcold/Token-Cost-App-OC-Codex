import AppKit
import Foundation
import CodexTokenCostCore

@MainActor
final class CodexSessionModel: ObservableObject {
    private enum StatusState: Sendable {
        case waitingInitialization
        case settingsLoadFallback
        case refreshing
        case refreshed
        case refreshFailedWithSnapshot
        case refreshFailed
        case waitingManualRefresh
        case loadedLocalSnapshot
        case emptyPayload(hasReadableSource: Bool)
        case settingsSaveFailed
    }

    @Published var settings: TokenCostSettings
    @Published var payload: CodexDashboardPayload?
    @Published var discoverySources: [TokenCostSource] = []
    @Published var isBootstrapping = false
    @Published var isRefreshing = false
    @Published var lastErrorMessage: String?
    @Published var settingsLoadWarningMessage: String?
    @Published var shouldPromptForSourceConfirmation = false
    @Published private var statusState: StatusState = .waitingInitialization

    private let fileManager = FileManager.default
    private let settingsStore: SettingsStore
    private let snapshotStore: CodexSnapshotStore
    private var didBootstrap = false
    private var discoveryGeneration = 0

    init() {
        self.settingsStore = SettingsStore(
            runtimeRoot: CodexAppPaths.runtimeRoot,
            settingsRelativePath: "config/codex-settings.json",
            defaultSettings: { TokenCostSettings.codexDefaults() }
        )
        self.snapshotStore = CodexSnapshotStore(runtimeRoot: CodexAppPaths.runtimeRoot)
        let loadedSettings = settingsStore.load()
        self.settings = loadedSettings.settings.sourceFamily == .codex ? loadedSettings.settings : TokenCostSettings.codexDefaults()
        self.settingsLoadWarningMessage = loadedSettings.errorMessage
        self.lastErrorMessage = loadedSettings.errorMessage
        self.statusState = loadedSettings.errorMessage == nil ? .waitingInitialization : .settingsLoadFallback
        try? CodexAppPaths.ensureRuntimeDirectories()
    }

    var statusMessage: String {
        switch statusState {
        case .waitingInitialization:
            return AppLocalization.text("status.codex.waitingInitialization")
        case .settingsLoadFallback:
            return AppLocalization.text("status.codex.settingsLoadFallback")
        case .refreshing:
            return AppLocalization.text("status.codex.refreshing")
        case .refreshed:
            return AppLocalization.text("status.codex.refreshed")
        case .refreshFailedWithSnapshot:
            return AppLocalization.text("status.codex.refreshFailedWithSnapshot")
        case .refreshFailed:
            return AppLocalization.text("status.codex.refreshFailed")
        case .waitingManualRefresh:
            return AppLocalization.text("status.codex.waitingManualRefresh")
        case .loadedLocalSnapshot:
            return AppLocalization.text("status.codex.loadedLocalSnapshot")
        case .emptyPayload(let hasReadableSource):
            return hasReadableSource
                ? AppLocalization.text("status.codex.emptyPayloadReadable")
                : AppLocalization.text("status.codex.emptyPayloadUnreadable")
        case .settingsSaveFailed:
            return AppLocalization.text("status.codex.settingsSaveFailed")
        }
    }

    var canRefresh: Bool {
        !isRefreshing
    }

    var sourceRootsDescription: String {
        let roots = settings.effectiveSourceRoots
        if roots.isEmpty {
            return AppLocalization.text("codex.sources.none")
        }
        return roots.joined(separator: " · ")
    }

    var manualSourcePathsDescription: String {
        let paths = settings.effectiveManualSourcePaths
        if paths.isEmpty {
            return AppLocalization.text("codex.manualSources.none")
        }
        return paths.joined(separator: " · ")
    }

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        Task { @MainActor in await bootstrap() }
    }

    func refreshIfNeeded() {
        guard settings.autoRescan else { return }
        if let payload, payload.summary.sessionCount > 0 {
            return
        }
        refresh()
    }

    func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        statusState = .refreshing
        lastErrorMessage = nil
        shouldPromptForSourceConfirmation = false

        let currentSettings = settings

        Task.detached(priority: .userInitiated) { [weak self, currentSettings] in
            do {
                let payload = try CodexHelperRunner.loadPayload(settings: currentSettings)
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    self.payload = payload
                    try? self.snapshotStore.saveLatest(
                        payload,
                        settings: currentSettings,
                        retention: currentSettings.snapshotRetentionCount
                    )
                    self.lastErrorMessage = nil
                    if payload.summary.sessionCount == 0 {
                        self.shouldPromptForSourceConfirmation = true
                        self.statusState = .emptyPayload(hasReadableSource: self.hasReadableCodexSource())
                    } else {
                        self.statusState = .refreshed
                        self.shouldPromptForSourceConfirmation = false
                    }
                    self.isRefreshing = false
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    let fallbackPayload = self.snapshotStore.loadLatest(settings: currentSettings)
                    self.payload = fallbackPayload ?? self.payload
                    self.lastErrorMessage = message
                    if fallbackPayload != nil {
                        self.statusState = .refreshFailedWithSnapshot
                    } else {
                        self.statusState = .refreshFailed
                    }
                    self.shouldPromptForSourceConfirmation = (self.payload?.summary.sessionCount ?? 0) == 0
                    self.isRefreshing = false
                }
            }
        }
    }

    func updateSettings(_ mutate: (inout TokenCostSettings) -> Void) {
        mutate(&settings)
        normalizeSettings()
        persistSettings()
        refreshDiscoverySources()
        shouldPromptForSourceConfirmation = (payload?.summary.sessionCount ?? 0) == 0
    }

    func addSourceRoot() {
        let panel = NSOpenPanel()
        panel.title = AppLocalization.text("dialog.codex.selectSessionDirectory.title")
        panel.prompt = AppLocalization.text("dialog.action.addDirectory")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.message = AppLocalization.text("dialog.codex.selectSessionDirectory.message")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let canonicalPath = TokenCostPathUtilities.canonicalURL(url).path
        guard !settings.effectiveSourceRoots.contains(canonicalPath) else {
            return
        }

        settings.sourceRoots.append(canonicalPath)
        persistSettings()
        refreshDiscoverySources()
        refresh()
    }

    func addSourceFile() {
        let panel = NSOpenPanel()
        panel.title = AppLocalization.text("dialog.codex.selectSessionFile.title")
        panel.prompt = AppLocalization.text("dialog.action.addFile")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.message = AppLocalization.text("dialog.codex.selectSessionFile.message")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let canonicalPath = TokenCostPathUtilities.canonicalURL(url).path
        guard !settings.effectiveManualSourcePaths.contains(canonicalPath) else {
            return
        }

        settings.manualSourcePaths.append(canonicalPath)
        persistSettings()
        refreshDiscoverySources()
        refresh()
    }

    func removeSourceRoot(at offsets: IndexSet) {
        settings.sourceRoots.remove(atOffsets: offsets)
        persistSettings()
        refreshDiscoverySources()
        refresh()
    }

    func removeSourcePath(at offsets: IndexSet) {
        settings.manualSourcePaths.remove(atOffsets: offsets)
        persistSettings()
        refreshDiscoverySources()
        refresh()
    }

    func resetSettingsToDefaults() {
        settings = TokenCostSettings.codexDefaults()
        persistSettings()
        refreshDiscoverySources()
        refresh()
    }

    private func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }

        statusState = settingsLoadWarningMessage == nil ? .waitingInitialization : .settingsLoadFallback
        do {
            try CodexAppPaths.ensureRuntimeDirectories()
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        let loadedSettings = settingsStore.load()
        settings = loadedSettings.settings
        normalizeSettings()
        settingsLoadWarningMessage = loadedSettings.errorMessage
        if let warning = loadedSettings.errorMessage {
            lastErrorMessage = warning
            statusState = .settingsLoadFallback
        }
        let capturedSettings = settings
        let shouldAutoRescan = settings.autoRescan
        let runtimeRoot = CodexAppPaths.runtimeRoot
        Task { [weak self] in
            let loadedPayload = await Task.detached(priority: .userInitiated) {
                let store = CodexSnapshotStore(runtimeRoot: runtimeRoot)
                return store.loadLatest(settings: capturedSettings)
            }.value
            guard let self else { return }
            if self.isRefreshing {
                if self.payload == nil {
                    self.payload = loadedPayload
                }
                return
            }
            if shouldAutoRescan, self.payload != nil {
                return
            }
            self.payload = loadedPayload
            self.evaluatePostLoadState()
        }
        refreshDiscoverySources()

        if settings.autoRescan {
            refresh()
        }
    }

    private func evaluatePostLoadState() {
        if payload == nil {
            shouldPromptForSourceConfirmation = true
            statusState = .waitingManualRefresh
        } else if payload?.summary.sessionCount == 0 {
            shouldPromptForSourceConfirmation = true
            statusState = .emptyPayload(hasReadableSource: hasReadableCodexSource())
        } else {
            shouldPromptForSourceConfirmation = (payload?.summary.sessionCount ?? 0) == 0
            statusState = .loadedLocalSnapshot
        }
    }

    private func normalizeSettings() {
        if settings.sourceFamily != .codex {
            settings.sourceFamily = .codex
        }
        settings.snapshotRetentionCount = min(max(settings.snapshotRetentionCount, 1), 20)
        settings.maxScanDepth = min(max(settings.maxScanDepth, 1), 12)
        settings.maxScanCandidates = min(max(settings.maxScanCandidates, 1), 1000)
        settings.sourceRoots = deduplicatedCanonicalPaths(from: settings.sourceRoots)
            .filter { TokenCostPathUtilities.isSafeScanRoot(TokenCostPathUtilities.canonicalURL(from: $0)) }
        settings.manualSourcePaths = deduplicatedCanonicalPaths(from: settings.manualSourcePaths)
            .filter { TokenCostPathUtilities.isSafeScanRoot(TokenCostPathUtilities.canonicalURL(from: $0)) }
    }

    private func deduplicatedCanonicalPaths(from paths: [String]) -> [String] {
        var seen = Set<String>()
        var results: [String] = []
        for path in paths {
            let canonical = TokenCostPathUtilities.canonicalPathString(from: path)
            guard seen.insert(canonical).inserted else {
                continue
            }
            results.append(canonical)
        }
        return results
    }

    func persistSettings() {
        normalizeSettings()
        do {
            try settingsStore.save(settings)
            settingsLoadWarningMessage = nil
        } catch {
            let message = error.localizedDescription
            lastErrorMessage = message
            statusState = .settingsSaveFailed
#if DEBUG
            print("[CodexSessionModel] persistSettings failed: \(message)")
#endif
        }
    }

    private func hasReadableCodexSource() -> Bool {
        discoverySources.contains { $0.status == .available }
    }

    private func refreshDiscoverySources() {
        discoveryGeneration += 1
        let capturedGeneration = discoveryGeneration
        let currentSettings = settings

        Task.detached(priority: .userInitiated) { [capturedGeneration, currentSettings] in
            let service = CodexSessionDiscoveryService()
            let sources = service.discover(settings: currentSettings)

            await MainActor.run {
                guard capturedGeneration == self.discoveryGeneration else {
                    return
                }
                self.discoverySources = sources
            }
        }
    }
}
