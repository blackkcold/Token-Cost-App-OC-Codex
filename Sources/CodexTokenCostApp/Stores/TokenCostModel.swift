import AppKit
import Foundation
import CodexTokenCostCore
import SwiftUI

@MainActor
final class TokenCostModel: ObservableObject {
    private enum StatusState: Sendable {
        case waitingInitialization
        case settingsLoadFallback
        case refreshingSource(String)
        case refreshedSource(String)
        case refreshingFailed
        case scanningSources
        case noAvailableDatabase
        case sourceUnavailable(TokenCostSourceStatusMessageKind)
        case settingsSaveFailed
    }

    @Published var settings: TokenCostSettings
    @Published var sources: [TokenCostSource] = []
    @Published var selectedSourceID: String?
    @Published var payloadsBySourceID: [String: DashboardPayload] = [:]
    @Published var isBootstrapping = false
    @Published var isRefreshing = false
    @Published var lastErrorMessage: String?
    @Published var settingsLoadWarningMessage: String?
    @Published private var statusState: StatusState = .waitingInitialization

    private let settingsStore: SettingsStore
    private let snapshotStore: SnapshotStore
    private var didBootstrap = false

    init() {
        self.settingsStore = SettingsStore(runtimeRoot: CodexAppPaths.runtimeRoot)
        self.snapshotStore = SnapshotStore(runtimeRoot: CodexAppPaths.runtimeRoot)
        let loadedSettings = settingsStore.load()
        self.settings = loadedSettings.settings
        self.selectedSourceID = loadedSettings.settings.selectedSourceID
        self.settingsLoadWarningMessage = loadedSettings.errorMessage
        self.lastErrorMessage = loadedSettings.errorMessage
        self.statusState = loadedSettings.errorMessage == nil ? .waitingInitialization : .settingsLoadFallback
        try? CodexAppPaths.ensureRuntimeDirectories()
    }

    var statusMessage: String {
        switch statusState {
        case .waitingInitialization:
            return AppLocalization.text("status.opencode.waitingInitialization")
        case .settingsLoadFallback:
            return AppLocalization.text("status.opencode.settingsLoadFallback")
        case .refreshingSource(let sourceName):
            return AppLocalization.format("status.opencode.refreshingSource", sourceName)
        case .refreshedSource(let sourceName):
            return AppLocalization.format("status.opencode.refreshedSource", sourceName)
        case .refreshingFailed:
            return AppLocalization.text("status.opencode.refreshingFailed")
        case .scanningSources:
            return AppLocalization.text("status.opencode.scanningSources")
        case .noAvailableDatabase:
            return AppLocalization.text("status.opencode.noAvailableDatabase")
        case .sourceUnavailable(let kind):
            return kind.displayName
        case .settingsSaveFailed:
            return AppLocalization.text("status.opencode.settingsSaveFailed")
        }
    }

    var selectedSource: TokenCostSource? {
        guard let selectedSourceID else { return nil }
        return sources.first(where: { $0.id == selectedSourceID })
    }

    var selectedPayload: DashboardPayload? {
        guard let selectedSourceID else { return nil }
        return payloadsBySourceID[selectedSourceID]
    }

    var hasSources: Bool {
        !sources.isEmpty
    }

    var canRefreshSelectedSource: Bool {
        selectedSource?.isAvailable == true && !isRefreshing
    }

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        Task { @MainActor in await bootstrap() }
    }

    func refreshSelectedSourceIfNeeded() {
        guard selectedPayload == nil else { return }
        refreshSelectedSource()
    }

    func rescanSources() {
        Task { @MainActor in await rescanSourcesAndRestoreSelection(triggerRefresh: true) }
    }

    func refreshSelectedSource() {
        guard !isRefreshing, let source = selectedSource else {
            return
        }

        guard source.isAvailable else {
            lastErrorMessage = source.statusMessage
            statusState = .sourceUnavailable(source.statusMessageKind)
            if let cached = snapshotStore.loadLatest(sourceID: source.id) {
                payloadsBySourceID[source.id] = cached
            }
            return
        }

        isRefreshing = true
        statusState = .refreshingSource(source.name)
        lastErrorMessage = nil

        let databasePath = source.databaseURL.path
        let sourceID = source.id
        let sourceName = source.name
        let snapshotRetention = settings.snapshotRetentionCount

        Task.detached(priority: .userInitiated) { [weak self, databasePath, sourceID, sourceName, snapshotRetention] in
            do {
                let payload = try TokenDatabaseClient().loadPayload(from: URL(fileURLWithPath: databasePath))
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    self.payloadsBySourceID[sourceID] = payload
                    try? self.snapshotStore.saveLatest(payload, sourceID: sourceID, retention: snapshotRetention)
                    if self.selectedSourceID == sourceID {
                        self.statusState = .refreshedSource(sourceName)
                    }
                    self.lastErrorMessage = nil
                    self.isRefreshing = false
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    self.lastErrorMessage = message
                    self.statusState = .refreshingFailed
                    self.isRefreshing = false
                }
            }
        }
    }

    func selectSource(id: String?) {
        selectedSourceID = id
        settings.selectedSourceID = id
        persistSettings()

        if let id, let cached = snapshotStore.loadLatest(sourceID: id) {
            payloadsBySourceID[id] = cached
        }

        if let source = selectedSource, source.isAvailable {
            refreshSelectedSource()
        } else if let source = selectedSource {
            lastErrorMessage = source.statusMessage
            statusState = .sourceUnavailable(source.statusMessageKind)
        }
    }

    func addScanRoot() {
        let panel = NSOpenPanel()
        panel.title = AppLocalization.text("dialog.opencode.selectInstallDirectory.title")
        panel.prompt = AppLocalization.text("dialog.action.addDirectory")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.message = AppLocalization.text("dialog.opencode.selectInstallDirectory.message")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let path = url.path
        guard !settings.scanRoots.contains(path) else {
            return
        }

        settings.scanRoots.append(path)
        persistSettings()
        rescanSources()
    }

    func addDatabaseFile() {
        let panel = NSOpenPanel()
        panel.title = AppLocalization.text("dialog.opencode.selectDatabaseFile.title")
        panel.prompt = AppLocalization.text("dialog.action.addFile")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = []
        panel.message = AppLocalization.text("dialog.opencode.selectDatabaseFile.message")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let path = url.path
        guard !settings.manualDatabasePaths.contains(path) else {
            return
        }

        settings.manualDatabasePaths.append(path)
        persistSettings()
        rescanSources()
    }

    func removeScanRoot(at offsets: IndexSet) {
        settings.scanRoots.remove(atOffsets: offsets)
        persistSettings()
        rescanSources()
    }

    func removeDatabasePath(at offsets: IndexSet) {
        settings.manualDatabasePaths.remove(atOffsets: offsets)
        persistSettings()
        rescanSources()
    }

    func resetSettingsToDefaults() {
        settings = TokenCostSettings()
        selectedSourceID = nil
        settings.selectedSourceID = nil
        payloadsBySourceID.removeAll()
        persistSettings()
        rescanSources()
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
        selectedSourceID = loadedSettings.settings.selectedSourceID
        settingsLoadWarningMessage = loadedSettings.errorMessage
        if let warning = loadedSettings.errorMessage {
            lastErrorMessage = warning
            statusState = .settingsLoadFallback
        }
        await rescanSourcesAndRestoreSelection(
            triggerRefresh: true,
            persistSelection: !loadedSettings.didFallbackToDefaults
        )
    }

    private func rescanSourcesAndRestoreSelection(triggerRefresh: Bool, persistSelection: Bool = true) async {
        statusState = .scanningSources
        let currentSettings = settings
        let discovered = await Task.detached(priority: .userInitiated) {
            SourceDiscoveryService().discover(settings: currentSettings)
        }.value

        sources = discovered

        let preferredSelection: String? = {
            if let selectedSourceID, discovered.contains(where: { $0.id == selectedSourceID }) {
                return selectedSourceID
            }
            if let saved = settings.selectedSourceID, discovered.contains(where: { $0.id == saved }) {
                return saved
            }
            return discovered.first?.id
        }()

        selectedSourceID = preferredSelection
        settings.selectedSourceID = preferredSelection
        if persistSelection {
            persistSettings()
        }

        if let selectedSourceID {
            if let cached = snapshotStore.loadLatest(sourceID: selectedSourceID) {
                payloadsBySourceID[selectedSourceID] = cached
            }
        }

        if triggerRefresh {
            if let source = selectedSource, source.isAvailable {
                refreshSelectedSource()
            } else if let source = selectedSource {
                lastErrorMessage = source.statusMessage
                statusState = .sourceUnavailable(source.statusMessageKind)
            } else {
                statusState = .noAvailableDatabase
            }
        }
    }

    func persistSettings() {
        settings.maxScanDepth = max(settings.maxScanDepth, 1)
        settings.maxScanCandidates = max(settings.maxScanCandidates, 1)
        settings.snapshotRetentionCount = min(max(settings.snapshotRetentionCount, 1), 20)
        do {
            try settingsStore.save(settings)
            settingsLoadWarningMessage = nil
        } catch {
            let message = error.localizedDescription
            lastErrorMessage = message
            statusState = .settingsSaveFailed
#if DEBUG
            print("[TokenCostModel] persistSettings failed: \(message)")
#endif
        }
    }

    func updateSettings(_ mutate: (inout TokenCostSettings) -> Void) {
        mutate(&settings)
        persistSettings()
    }
}
