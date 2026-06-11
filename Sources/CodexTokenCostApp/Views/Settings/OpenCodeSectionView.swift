import SwiftUI
import CodexTokenCostCore

struct OpenCodeSectionView: View {
    @ObservedObject var openCodeModel: TokenCostModel
    let palette: TokenCostPalette
    let listPageSize: Int
    @Binding var scanRootsPageIndex: Int
    @Binding var manualDatabasePageIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            scanRootsCard
            manualDatabasesCard
            scanSettingsCard
        }
    }

    // MARK: - Scan roots card

    private var scanRootsCard: some View {
        let roots = openCodeModel.settings.scanRoots
        let pageCount = max((roots.count + listPageSize - 1) / listPageSize, 1)
        let clampedPage = min(max(scanRootsPageIndex, 0), pageCount - 1)
        let startIndex = clampedPage * listPageSize
        let endIndex = min(startIndex + listPageSize, roots.count)
        let paginatedRoots = roots.isEmpty ? [] : Array(roots[startIndex..<endIndex])

        return SettingsSurfaceCard(
            title: "settings.scanRoots.title".localized,
            subtitle: "\("settings.scanRoots.subtitle".localized) (\(roots.count))",
            role: .primary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if roots.isEmpty {
                    Text("settings.empty.scanRoots".localized)
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
                                openCodeModel.removeScanRoot(at: IndexSet(integer: realIndex))
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
                    pageIndex: $scanRootsPageIndex,
                    itemCount: roots.count,
                    pageSize: listPageSize,
                    palette: palette,
                    title: "settings.pagination.installRoots".localized
                )

                HStack(spacing: 10) {
                    Button {
                        openCodeModel.addScanRoot()
                    } label: {
                        Label("settings.action.addInstallDirectory".localized, systemImage: "plus")
                    }
                    .settingsGlassButtonStyle(prominent: true)
                    .controlSize(.small)

                    Button {
                        openCodeModel.rescanSources()
                    } label: {
                        Label("settings.action.rescan".localized, systemImage: "arrow.clockwise")
                    }
                    .settingsGlassButtonStyle(prominent: false)
                    .controlSize(.small)
                    .disabled(openCodeModel.isRefreshing)

                    if openCodeModel.isRefreshing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 20, height: 20)
                    }
                }
            }
        }
    }

    // MARK: - Manual databases card

    private var manualDatabasesCard: some View {
        let paths = openCodeModel.settings.manualDatabasePaths
        let pageCount = max((paths.count + listPageSize - 1) / listPageSize, 1)
        let clampedPage = min(max(manualDatabasePageIndex, 0), pageCount - 1)
        let startIndex = clampedPage * listPageSize
        let endIndex = min(startIndex + listPageSize, paths.count)
        let paginatedPaths = paths.isEmpty ? [] : Array(paths[startIndex..<endIndex])

        return SettingsSurfaceCard(
            title: "settings.manualDatabase.title".localized,
            subtitle: "\("settings.manualDatabase.subtitle".localized) (\(paths.count))",
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if paths.isEmpty {
                    Text("settings.empty.manualDatabase".localized)
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
                                openCodeModel.removeDatabasePath(at: IndexSet(integer: realIndex))
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
                    pageIndex: $manualDatabasePageIndex,
                    itemCount: paths.count,
                    pageSize: listPageSize,
                    palette: palette,
                    title: "settings.pagination.manualDatabase".localized
                )

                HStack(spacing: 10) {
                    Button {
                        openCodeModel.addDatabaseFile()
                    } label: {
                        Label("settings.action.addDatabaseFile".localized, systemImage: "plus")
                    }
                    .settingsGlassButtonStyle(prominent: true)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Scan settings card

    private var scanSettingsCard: some View {
        SettingsSurfaceCard(
            title: "settings.source.title".localized,
            subtitle: "settings.source.subtitle".localized,
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsControlGrid(minimumWidth: 220) {
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        Toggle("settings.source.autoRescan".localized, isOn: Binding(
                            get: { openCodeModel.settings.autoRescan },
                            set: { v in openCodeModel.updateSettings { $0.autoRescan = v } }
                        ))
                    }

                    SettingsControlTile(palette: palette, minHeight: 54) {
                        SettingsInlineControlRow(title: AppLocalization.format("settings.source.scanDepth", openCodeModel.settings.maxScanDepth), palette: palette) {
                            Picker("", selection: Binding(
                                get: { openCodeModel.settings.maxScanDepth },
                                set: { v in openCodeModel.updateSettings { $0.maxScanDepth = v } }
                            )) {
                                ForEach(1...6, id: \.self) { depth in
                                    Text("\(depth)").tag(depth)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 160)
                        }
                    }

                    SettingsControlTile(palette: palette, minHeight: 54) {
                        SettingsInlineControlRow(title: AppLocalization.format("settings.source.snapshotRetention", openCodeModel.settings.snapshotRetentionCount), palette: palette) {
                            HStack(spacing: 6) {
                                Stepper("", value: Binding(
                                    get: { openCodeModel.settings.snapshotRetentionCount },
                                    set: { v in openCodeModel.updateSettings { $0.snapshotRetentionCount = v } }
                                ), in: 1...20)
                                .labelsHidden()
                                Text("\(openCodeModel.settings.snapshotRetentionCount)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(palette.title)
                                    .frame(minWidth: 24)
                            }
                        }
                    }
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
