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
        refreshDiscoverySources(using: currentSettings)

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
                    self.refreshDiscoverySources(using: currentSettings)
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
                    self.refreshDiscoverySources(using: currentSettings)
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
        payload = snapshotStore.loadLatest(settings: settings)
        refreshDiscoverySources()

        if settings.autoRescan {
            refresh()
        } else if payload == nil {
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
        settings.sourceRoots = deduplicatedCanonicalPaths(from: settings.sourceRoots)
        settings.manualSourcePaths = deduplicatedCanonicalPaths(from: settings.manualSourcePaths)
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

    private func refreshDiscoverySources(using currentSettings: TokenCostSettings? = nil) {
        let settings = currentSettings ?? self.settings
        discoverySources = buildDiscoverySources(for: settings)
    }

    private func buildDiscoverySources(for settings: TokenCostSettings) -> [TokenCostSource] {
        let profile = settings.profile
        var seenIDs = Set<String>()
        var sources: [TokenCostSource] = []

        for root in settings.effectiveSourceRoots {
            appendDirectorySources(
                for: root,
                profile: profile,
                maxDepth: settings.maxScanDepth,
                maxCandidates: settings.maxScanCandidates,
                seenIDs: &seenIDs,
                into: &sources
            )
        }

        for path in settings.effectiveManualSourcePaths {
            appendManualSource(
                for: path,
                profile: profile,
                seenIDs: &seenIDs,
                into: &sources
            )
        }

        return sources.sorted { lhs, rhs in
            if lhs.status == rhs.status {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return statusRank(lhs.status) < statusRank(rhs.status)
        }
    }

    private func appendDirectorySources(
        for path: String,
        profile: TokenCostSourceProfile,
        maxDepth: Int,
        maxCandidates: Int,
        seenIDs: inout Set<String>,
        into sources: inout [TokenCostSource]
    ) {
        let normalized = TokenCostPathUtilities.canonicalURL(from: path)
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: normalized.path, isDirectory: &isDirectory)

        guard exists else {
            appendIfNeeded(
                makeCodexSource(
                    sourceURL: normalized,
                    locationURL: normalized,
                    locationKind: .directory,
                    profile: profile,
                    status: .missing,
                    statusMessageKind: .missingDefaultLocation,
                    isDefault: true
                ),
                seenIDs: &seenIDs,
                into: &sources
            )
            return
        }

        if isDirectory.boolValue {
            let discoveredFiles = discoverSessionFiles(
                in: normalized,
                profile: profile,
                maxDepth: maxDepth,
                maxCandidates: maxCandidates
            )

            if discoveredFiles.isEmpty {
                appendIfNeeded(
                makeCodexSource(
                    sourceURL: normalized,
                    locationURL: normalized,
                    locationKind: .directory,
                    profile: profile,
                    status: .missing,
                    statusMessageKind: .missingDirectoryFiles,
                    isDefault: true
                ),
                seenIDs: &seenIDs,
                into: &sources
            )
                return
            }

            for fileURL in discoveredFiles {
                appendIfNeeded(
                makeCodexSource(
                    sourceURL: fileURL,
                    locationURL: normalized,
                    locationKind: .file,
                    profile: profile,
                    status: fileStatus(for: fileURL, profile: profile),
                    statusMessageKind: fileStatusMessageKind(for: fileURL, profile: profile),
                    isDefault: false
                ),
                seenIDs: &seenIDs,
                into: &sources
            )
            }
            return
        }

        appendManualSource(
            for: normalized.path,
            profile: profile,
            seenIDs: &seenIDs,
            into: &sources
        )
    }

    private func appendManualSource(
        for path: String,
        profile: TokenCostSourceProfile,
        seenIDs: inout Set<String>,
        into sources: inout [TokenCostSource]
    ) {
        let normalized = TokenCostPathUtilities.canonicalURL(from: path)
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: normalized.path, isDirectory: &isDirectory)

        if exists == false {
            appendIfNeeded(
                makeCodexSource(
                    sourceURL: normalized,
                    locationURL: normalized,
                    locationKind: .file,
                    profile: profile,
                    status: .missing,
                    statusMessageKind: .missingPath,
                    isDefault: false
                ),
                seenIDs: &seenIDs,
                into: &sources
            )
            return
        }

        if isDirectory.boolValue {
            let discoveredFiles = discoverSessionFiles(
                in: normalized,
                profile: profile,
                maxDepth: profile.maxScanDepth,
                maxCandidates: profile.maxScanCandidates
            )

            if discoveredFiles.isEmpty {
                appendIfNeeded(
                makeCodexSource(
                    sourceURL: normalized,
                    locationURL: normalized,
                    locationKind: .directory,
                    profile: profile,
                    status: .missing,
                    statusMessageKind: .missingDirectoryFiles,
                    isDefault: false
                ),
                seenIDs: &seenIDs,
                into: &sources
            )
                return
            }

            for fileURL in discoveredFiles {
                appendIfNeeded(
                makeCodexSource(
                    sourceURL: fileURL,
                    locationURL: normalized,
                    locationKind: .file,
                    profile: profile,
                    status: fileStatus(for: fileURL, profile: profile),
                    statusMessageKind: fileStatusMessageKind(for: fileURL, profile: profile),
                    isDefault: false
                ),
                seenIDs: &seenIDs,
                into: &sources
            )
            }
            return
        }

        appendIfNeeded(
            makeCodexSource(
                sourceURL: normalized,
                locationURL: normalized,
                locationKind: .file,
                profile: profile,
                status: fileStatus(for: normalized, profile: profile),
                statusMessageKind: fileStatusMessageKind(for: normalized, profile: profile),
                isDefault: false
            ),
            seenIDs: &seenIDs,
            into: &sources
        )
    }

    private func appendIfNeeded(
        _ source: TokenCostSource,
        seenIDs: inout Set<String>,
        into sources: inout [TokenCostSource]
    ) {
        guard seenIDs.insert(source.id).inserted else {
            return
        }
        sources.append(source)
    }

    private func discoverSessionFiles(
        in root: URL,
        profile: TokenCostSourceProfile,
        maxDepth: Int,
        maxCandidates: Int
    ) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let itemURL as URL in enumerator {
            let canonical = TokenCostPathUtilities.canonicalURL(itemURL)
            guard TokenCostPathUtilities.isDescendant(canonical, of: root) else {
                continue
            }
            let relativeDepth = canonical.pathComponents.count - root.pathComponents.count
            if relativeDepth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            guard profile.matchesCandidateFile(canonical) else {
                continue
            }

            results.append(canonical)
            if results.count >= maxCandidates {
                break
            }
        }
        return results.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.path < rhs.path
            }
            return lhsDate > rhsDate
        }
    }

    private func makeCodexSource(
        sourceURL: URL,
        locationURL: URL?,
        locationKind: TokenCostSourceLocationKind,
        profile: TokenCostSourceProfile,
        status: TokenCostSourceStatus,
        statusMessageKind: TokenCostSourceStatusMessageKind,
        isDefault: Bool
    ) -> TokenCostSource {
        let normalized = TokenCostPathUtilities.canonicalURL(sourceURL)
        return TokenCostSource(
            id: TokenCostPaths.stableIdentifier(for: normalized.path),
            name: displayName(for: normalized, kind: locationKind, isDefault: isDefault),
            sourceFamily: profile.family,
            locationKind: locationKind,
            sourceURL: normalized,
            locationURL: locationURL.map(TokenCostPathUtilities.canonicalURL),
            status: status,
            statusMessageKind: statusMessageKind,
            lastModified: modificationDate(for: normalized),
            isReadOnly: true
        )
    }

    private func fileStatus(for url: URL, profile: TokenCostSourceProfile) -> TokenCostSourceStatus {
        guard profile.matchesCandidateFile(url) else {
            return .unsupported
        }
        if fileManager.isReadableFile(atPath: url.path) {
            return .available
        }
        return .locked
    }

    private func fileStatusMessageKind(for url: URL, profile: TokenCostSourceProfile) -> TokenCostSourceStatusMessageKind {
        guard profile.matchesCandidateFile(url) else {
            return .fileFormatMismatch
        }
        if fileManager.isReadableFile(atPath: url.path) {
            return .fileReadable
        }
        return .fileUnreadable
    }

    private func displayName(for url: URL, kind: TokenCostSourceLocationKind, isDefault: Bool) -> String {
        if isDefault {
            return url.lastPathComponent.isEmpty ? settings.profile.sourceRootsLabel : url.lastPathComponent
        }
        switch kind {
        case .directory:
            return url.lastPathComponent.isEmpty ? AppLocalization.text("settings.codex.discovery.directoryFallback") : url.lastPathComponent
        case .file:
            let fileName = url.deletingPathExtension().lastPathComponent
            return fileName.isEmpty ? url.lastPathComponent : fileName
        }
    }

    private func modificationDate(for url: URL) -> String? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else {
            return nil
        }
        return ISO8601DateFormatter().string(from: date)
    }

    private func statusRank(_ status: TokenCostSourceStatus) -> Int {
        switch status {
        case .available: return 0
        case .locked: return 1
        case .unsupported: return 2
        case .missing: return 3
        case .unknown: return 4
        }
    }
}
