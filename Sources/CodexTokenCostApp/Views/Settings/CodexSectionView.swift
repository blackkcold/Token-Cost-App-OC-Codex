import SwiftUI
import CodexTokenCostCore

struct CodexSectionView: View {
    @ObservedObject var codexModel: CodexSessionModel
    let palette: TokenCostPalette
    let listPageSize: Int
    @Binding var codexDiscoveryPageIndex: Int
    @Binding var codexRootsPageIndex: Int
    @Binding var codexManualPageIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            discoverySourcesCard
            sourceRootsCard
            manualSourcesCard
            codexSettingsCard
        }
    }

    // MARK: - Discovery sources card

    private var discoverySourcesCard: some View {
        let sources = codexModel.discoverySources
        let pageCount = max((sources.count + listPageSize - 1) / listPageSize, 1)
        let clampedPage = min(max(codexDiscoveryPageIndex, 0), pageCount - 1)
        let startIndex = clampedPage * listPageSize
        let endIndex = min(startIndex + listPageSize, sources.count)
        let paginatedSources = sources.isEmpty ? [] : Array(sources[startIndex..<endIndex])

        return SettingsSurfaceCard(
            title: "settings.codex.discovery.title".localized,
            subtitle: "\("settings.codex.discovery.body".localized) (\(sources.count))",
            role: .primary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if sources.isEmpty {
                    Text("settings.codex.discovery.empty".localized)
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                } else {
                    ForEach(paginatedSources) { source in
                        HStack(spacing: 8) {
                            Image(systemName: source.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(source.isAvailable ? .green : .orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: source.name)
                                    .font(.caption)
                                    .foregroundStyle(palette.title)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    SourceStatusPill(source: source, palette: palette)
                                    if let origin = source.originURL {
                                        Text(verbatim: abbreviatePath(origin.path))
                                            .font(.system(size: 9))
                                            .foregroundStyle(palette.subtitle)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.05)))
                    }
                }

                PaginationControls(
                    pageIndex: $codexDiscoveryPageIndex,
                    itemCount: sources.count,
                    pageSize: listPageSize,
                    palette: palette,
                    title: "settings.pagination.discoverySources".localized
                )

                HStack(spacing: 10) {
                    Button {
                        codexModel.refresh()
                    } label: {
                        Label("settings.action.refreshCodex".localized, systemImage: "arrow.clockwise")
                    }
                    .settingsGlassButtonStyle(prominent: true)
                    .controlSize(.small)
                    .disabled(codexModel.isRefreshing)

                    if codexModel.isRefreshing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 20, height: 20)
                    }
                }
            }
        }
    }

    // MARK: - Source roots card

    private var sourceRootsCard: some View {
        let roots = codexModel.settings.effectiveSourceRoots
        let pageCount = max((roots.count + listPageSize - 1) / listPageSize, 1)
        let clampedPage = min(max(codexRootsPageIndex, 0), pageCount - 1)
        let startIndex = clampedPage * listPageSize
        let endIndex = min(startIndex + listPageSize, roots.count)
        let paginatedRoots = roots.isEmpty ? [] : Array(roots[startIndex..<endIndex])

        return SettingsSurfaceCard(
            title: "settings.codex.roots.title".localized,
            subtitle: "\("settings.codex.sources.subtitle".localized) (\(roots.count))",
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if roots.isEmpty {
                    Text("settings.empty.codexRoots".localized)
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                } else {
                    ForEach(Array(paginatedRoots.enumerated()), id: \.offset) { offset, path in
                        let realIndex = startIndex + offset
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.caption2)
                                .foregroundStyle(palette.accent)
                            Text(verbatim: abbreviatePath(path))
                                .font(.caption)
                                .foregroundStyle(palette.title)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                codexModel.removeSourceRoot(at: IndexSet(integer: realIndex))
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.05)))
                    }
                }

                PaginationControls(
                    pageIndex: $codexRootsPageIndex,
                    itemCount: roots.count,
                    pageSize: listPageSize,
                    palette: palette,
                    title: "settings.pagination.codexRoots".localized
                )

                HStack(spacing: 10) {
                    Button {
                        codexModel.addSourceRoot()
                    } label: {
                        Label("settings.action.addSessionDirectory".localized, systemImage: "plus")
                    }
                    .settingsGlassButtonStyle(prominent: true)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Manual sources card

    private var manualSourcesCard: some View {
        let paths = codexModel.settings.effectiveManualSourcePaths
        let pageCount = max((paths.count + listPageSize - 1) / listPageSize, 1)
        let clampedPage = min(max(codexManualPageIndex, 0), pageCount - 1)
        let startIndex = clampedPage * listPageSize
        let endIndex = min(startIndex + listPageSize, paths.count)
        let paginatedPaths = paths.isEmpty ? [] : Array(paths[startIndex..<endIndex])

        return SettingsSurfaceCard(
            title: "settings.codex.manual.title".localized,
            subtitle: "\("settings.codex.sources.subtitle".localized) (\(paths.count))",
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if paths.isEmpty {
                    Text("settings.empty.codexManual".localized)
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                } else {
                    ForEach(Array(paginatedPaths.enumerated()), id: \.offset) { offset, path in
                        let realIndex = startIndex + offset
                        HStack(spacing: 8) {
                            Image(systemName: "doc")
                                .font(.caption2)
                                .foregroundStyle(palette.accentSecondary)
                            Text(verbatim: abbreviatePath(path))
                                .font(.caption)
                                .foregroundStyle(palette.title)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                codexModel.removeSourcePath(at: IndexSet(integer: realIndex))
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.05)))
                    }
                }

                PaginationControls(
                    pageIndex: $codexManualPageIndex,
                    itemCount: paths.count,
                    pageSize: listPageSize,
                    palette: palette,
                    title: "settings.pagination.codexManual".localized
                )

                HStack(spacing: 10) {
                    Button {
                        codexModel.addSourceFile()
                    } label: {
                        Label("settings.action.addSessionFile".localized, systemImage: "plus")
                    }
                    .settingsGlassButtonStyle(prominent: true)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Codex settings card

    private var codexSettingsCard: some View {
        SettingsSurfaceCard(
            title: "settings.codex.title".localized,
            subtitle: "settings.codex.subtitle".localized,
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsControlGrid(minimumWidth: 220) {
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        Toggle("settings.codex.autoRescan".localized, isOn: Binding(
                            get: { codexModel.settings.autoRescan },
                            set: { v in codexModel.updateSettings { $0.autoRescan = v } }
                        ))
                    }

                    SettingsControlTile(palette: palette, minHeight: 54) {
                        SettingsInlineControlRow(title: AppLocalization.format("settings.source.scanDepth", codexModel.settings.maxScanDepth), palette: palette) {
                            Picker("", selection: Binding(
                                get: { codexModel.settings.maxScanDepth },
                                set: { v in codexModel.updateSettings { $0.maxScanDepth = v } }
                            )) {
                                ForEach(1...8, id: \.self) { depth in
                                    Text("\(depth)").tag(depth)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 200)
                        }
                    }

                    SettingsControlTile(palette: palette, minHeight: 54) {
                        SettingsInlineControlRow(title: AppLocalization.format("settings.codex.snapshotRetention", codexModel.settings.snapshotRetentionCount), palette: palette) {
                            HStack(spacing: 6) {
                                Stepper("", value: Binding(
                                    get: { codexModel.settings.snapshotRetentionCount },
                                    set: { v in codexModel.updateSettings { $0.snapshotRetentionCount = v } }
                                ), in: 1...20)
                                .labelsHidden()
                                Text("\(codexModel.settings.snapshotRetentionCount)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(palette.title)
                                    .frame(minWidth: 24)
                            }
                        }
                    }
                }

                if let warning = codexModel.settingsLoadWarningMessage, !warning.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(verbatim: warning)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Helpers

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}

private extension String {
    var localized: String {
        AppLocalization.text(self)
    }
}
