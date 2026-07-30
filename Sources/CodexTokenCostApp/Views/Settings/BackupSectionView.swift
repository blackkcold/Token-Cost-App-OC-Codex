import SwiftUI
import CodexTokenCostCore

struct BackupSectionView: View {
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    let palette: TokenCostPalette

    @State private var showBakCleanConfirmation = false
    @State private var showTrashConfirmation = false
    @State private var bakFilesToTrash: [BakFileInfo] = []
    @State private var showBakViewer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            configFileGroupCards
            deprecatedToggle
            backupOverviewSection
            completenessSection
            layeredStatusDisclosureGroup
            backupFileListDisclosureGroup
            unmanagedBakSection
            externalBackupSection
        }
        .onAppear {
            appPreferencesModel.refreshBackupState()
            appPreferencesModel.refreshUnmanagedBakFiles()
        }
        .sheet(isPresented: $showBakViewer) {
            bakViewerSheet
        }
        .alert("settings.backup.cleanBakConfirm".localized, isPresented: $showBakCleanConfirmation) {
            Button("settings.action.cancel".localized, role: .cancel) {}
            Button("settings.backup.moveToTrash".localized, role: .destructive) {
                appPreferencesModel.performTrashUnmanagedBakFiles(appPreferencesModel.unmanagedBakFiles)
            }
        } message: {
            Text("settings.backup.cleanBakConfirmMessage".localized)
        }
        .alert("settings.backup.trashConfirm".localized, isPresented: $showTrashConfirmation) {
            Button("settings.action.cancel".localized, role: .cancel) {}
            Button("settings.backup.moveToTrash".localized, role: .destructive) {
                appPreferencesModel.performTrashUnmanagedBakFiles(bakFilesToTrash)
            }
        } message: {
            Text("settings.backup.removeSelectedConfirm".localized)
        }
    }

    // MARK: - 配置文件分组卡片

    private var configFileGroupCards: some View {
        SettingsSurfaceCard(
            title: "settings.backup.configFilesTitle".localized,
            subtitle: "settings.backup.configFilesSubtitle".localized,
            role: .primary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(appPreferencesModel.configFileGroups) { group in
                    configGroupCard(group)
                }
            }
        }
    }

    private func configGroupCard(_ group: ConfigFileGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.groupName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(group.isDeprecated ? .orange : palette.title)
                if group.isDeprecated {
                    Text(AppLocalization.text("settings.backup.deprecated"))
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.7))
                }
                Spacer()
                if group.anyBackedUp {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.success)
                        .font(.caption)
                } else if group.files.contains(where: { !$0.sourceExists }) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(palette.warning)
                        .font(.caption)
                }
            }

            Divider().opacity(0.3)

            ForEach(group.files) { file in
                HStack(spacing: 8) {
                    Circle()
                        .fill(file.sourceExists ? .green : .orange)
                        .frame(width: 6, height: 6)
                    Text(verbatim: file.fileName)
                        .font(.caption)
                        .foregroundStyle(palette.title)
                    Text(file.sourceExists ? "settings.backup.sourceExists".localized : "settings.backup.sourceMissing".localized)
                        .font(.caption2)
                        .foregroundStyle(file.sourceExists ? .green : .orange)
                    if file.hasBackup, let date = file.lastBackupDate {
                        Text("· \(formattedDate(date))")
                            .font(.caption2)
                            .foregroundStyle(palette.subtitle)
                    }
                    Spacer()
                    if file.sourceExists {
                        Button("settings.backup.backupThisFile".localized) {
                            appPreferencesModel.performBackupConfig(file.fileName)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .foregroundStyle(palette.accent)
                        .disabled(appPreferencesModel.backupIsWorking)
                    }
                }
                .padding(.horizontal, 4)
            }

            HStack {
                Spacer()
                if group.files.contains(where: { $0.sourceExists }) {
                    Button("settings.backup.backupGroup".localized) {
                        appPreferencesModel.performBackupConfigGroup(group)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.accentSecondary)
                    .disabled(appPreferencesModel.backupIsWorking)
                } else {
                    Text("settings.backup.noSourceAvailable".localized)
                        .font(.caption2)
                        .foregroundStyle(palette.subtitle)
                }
            }
        }
        .padding(10)
        .settingsInsetSurface(in: RoundedRectangle(cornerRadius: 10), palette: palette)
    }

    // MARK: - 弃用文件开关

    private var deprecatedToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("settings.backup.showDeprecated".localized, isOn: appPreferencesModel.showDeprecatedFilesBinding)
                .font(.caption)
                .foregroundStyle(palette.title)
            Text("settings.backup.showDeprecatedDesc".localized)
                .font(.caption2)
                .foregroundStyle(palette.subtitle)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 未管理 .bak 文件（多选管理）

    private var unmanagedBakSection: some View {
        SettingsSurfaceCard(
            title: "settings.backup.bakManageTitle".localized,
            subtitle: "settings.backup.bakSortOrder".localized,
            role: appPreferencesModel.unmanagedBakFiles.isEmpty ? .secondary : .warning,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 8) {
                bakSortControls

                if appPreferencesModel.unmanagedBakFiles.isEmpty {
                    Text("settings.backup.noUnmanagedBak".localized)
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(appPreferencesModel.unmanagedBakFiles) { bak in
                                bakFileRow(bak)
                            }
                        }
                    }
                    .frame(maxHeight: 260)

                    Divider().opacity(0.3)

                    HStack(spacing: 8) {
                        Button("settings.backup.bakSelectAll".localized) {
                            appPreferencesModel.selectAllBakFiles()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .foregroundStyle(palette.accent)

                        Button("settings.backup.bakDeselectAll".localized) {
                            appPreferencesModel.deselectAllBakFiles()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .foregroundStyle(palette.accent)

                        Spacer()

                        Button {
                            bakFilesToTrash = appPreferencesModel.unmanagedBakFiles.filter {
                                appPreferencesModel.selectedBakFiles.contains($0.id)
                            }
                            if !bakFilesToTrash.isEmpty { showTrashConfirmation = true }
                        } label: {
                            Label(
                                "\("settings.backup.bakRemoveSelected".localized) (\(appPreferencesModel.selectedBakFiles.count))",
                                systemImage: "trash"
                            )
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .foregroundStyle(appPreferencesModel.selectedBakFiles.isEmpty ? palette.subtitle : .red)
                        .disabled(appPreferencesModel.selectedBakFiles.isEmpty)

                        Button("settings.backup.bakViewAll".localized) {
                            showBakViewer = true
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .foregroundStyle(palette.accentSecondary)
                    }
                }
            }
        }
    }

    private var bakSortControls: some View {
        HStack(spacing: 8) {
            ForEach(BakFileSortOrder.allCases) { order in
                Button(order.displayName) {
                    appPreferencesModel.sortBakFiles(order)
                }
                .buttonStyle(.borderless)
                .font(.caption2.weight(appPreferencesModel.bakFileSortOrder == order ? .semibold : .regular))
                .foregroundStyle(appPreferencesModel.bakFileSortOrder == order ? palette.accent : palette.subtitle)
            }
            Spacer()
            Text("\("settings.backup.unmanagedBakCount".localized): \(appPreferencesModel.unmanagedBakFiles.count)")
                .font(.caption2)
                .foregroundStyle(palette.warning)
        }
    }

    private func bakFileRow(_ bak: BakFileInfo) -> some View {
        HStack(spacing: 6) {
            Button {
                appPreferencesModel.toggleBakSelection(bak.id)
            } label: {
                Image(systemName: appPreferencesModel.selectedBakFiles.contains(bak.id)
                    ? "checkmark.square.fill" : "square")
                    .foregroundStyle(appPreferencesModel.selectedBakFiles.contains(bak.id) ? palette.accent : palette.subtitle)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Select backup file \(bak.fileName)")

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: bak.fileName)
                    .font(.caption2)
                    .foregroundStyle(palette.title)
                    .lineLimit(1)
                if let date = bak.displayDate {
                    Text(formattedDate(date))
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                }
            }
            Spacer()
            Text(verbatim: bak.sizeFormatted)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.05)))
    }

    // MARK: - .bak 查看器 Sheet

    private var bakViewerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("settings.backup.bakManageTitle".localized)
                    .font(.headline)
                    .foregroundStyle(palette.title)
                Spacer()
                Button("settings.action.close".localized) {
                    showBakViewer = false
                }
                .buttonStyle(.borderless)
            }
            .padding()

            bakSortControls
                .padding(.horizontal)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(appPreferencesModel.unmanagedBakFiles) { bak in
                        bakFileRow(bak)
                    }
                }
                .padding(.horizontal)
            }

            Divider()
            HStack {
                Button("settings.backup.bakSelectAll".localized) {
                    appPreferencesModel.selectAllBakFiles()
                }
                .buttonStyle(.borderless).font(.caption)
                Button("settings.backup.bakDeselectAll".localized) {
                    appPreferencesModel.deselectAllBakFiles()
                }
                .buttonStyle(.borderless).font(.caption)
                Spacer()
                Button {
                    bakFilesToTrash = appPreferencesModel.unmanagedBakFiles.filter {
                        appPreferencesModel.selectedBakFiles.contains($0.id)
                    }
                    if !bakFilesToTrash.isEmpty { showTrashConfirmation = true }
                } label: {
                    Label("\("settings.backup.bakRemoveSelected".localized) (\(appPreferencesModel.selectedBakFiles.count))", systemImage: "trash")
                }
                .buttonStyle(.borderless).font(.caption)
                .foregroundStyle(appPreferencesModel.selectedBakFiles.isEmpty ? palette.subtitle : .red)
                .disabled(appPreferencesModel.selectedBakFiles.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - 外部备份管理

    private var externalBackupSection: some View {
        SettingsSurfaceCard(
            title: "settings.backup.externalTitle".localized,
            subtitle: "settings.backup.externalSubtitle".localized,
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                backupDirectoryRow

                SettingsControlGrid(minimumWidth: 220) {
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        Toggle("settings.backup.autoBackup".localized, isOn: appPreferencesModel.autoBackupEnabledBinding)
                    }
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        SettingsInlineControlRow(title: "settings.backup.interval".localized, palette: palette) {
                            Picker("", selection: appPreferencesModel.autoBackupIntervalBinding) {
                                ForEach(BackupInterval.allCases) { interval in
                                    Text(interval.displayName).tag(interval)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 200)
                        }
                    }
                }

                SettingsControlGrid(minimumWidth: 220) {
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        Toggle("settings.backup.autoClean".localized, isOn: appPreferencesModel.autoCleanEnabledBinding)
                    }
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        SettingsInlineControlRow(title: "settings.backup.keepCount".localized, palette: palette) {
                            Picker("", selection: appPreferencesModel.autoCleanKeepCountBinding) {
                                Text("4").tag(4)
                                Text("5").tag(5)
                                Text("10").tag(10)
                                Text("20").tag(20)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 200)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        appPreferencesModel.performFullLayeredBackup()
                    } label: {
                        Label("settings.backup.layeredBackup".localized, systemImage: "gearshape.2")
                    }
                    .settingsGlassButtonStyle(prominent: true)
                    .controlSize(.small)
                    .disabled(appPreferencesModel.backupIsWorking)

                    Button {
                        appPreferencesModel.performBackupAll()
                    } label: {
                        Label("settings.backup.backupNowConfig".localized, systemImage: "arrow.up.doc")
                    }
                    .settingsGlassButtonStyle(prominent: false)
                    .controlSize(.small)
                    .disabled(appPreferencesModel.backupIsWorking)

                    Button {
                        appPreferencesModel.performCleanBackups()
                    } label: {
                        Label("settings.backup.cleanNow".localized, systemImage: "trash")
                    }
                    .settingsGlassButtonStyle(prominent: false)
                    .controlSize(.small)
                    .disabled(appPreferencesModel.backupIsWorking)

                    if appPreferencesModel.backupIsWorking {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 20, height: 20)
                    }
                }

                layerSelectionSection

                if let error = appPreferencesModel.backupLastError {
                    Text(verbatim: error)
                        .font(.caption2)
                        .foregroundStyle(palette.danger)
                }

                Text("settings.backup.layeredSensitive".localized)
                    .font(.caption)
                    .foregroundStyle(palette.subtitle.opacity(0.6))
            }
        }
    }

    private var backupDirectoryRow: some View {
        SettingsControlTile(
            title: "settings.backup.directory".localized,
            palette: palette,
            minHeight: 64
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(verbatim: abbreviatePath(appPreferencesModel.preferences.backup.backupDirectory))
                        .font(.caption)
                        .foregroundStyle(palette.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("settings.action.selectDirectory".localized) { selectBackupDirectory() }
                        .buttonStyle(.borderless).font(.caption).foregroundStyle(palette.accent)
                    Button("settings.backup.createDirectory".localized) { createBackupDirectory() }
                        .buttonStyle(.borderless).font(.caption).foregroundStyle(palette.accentSecondary)
                }
                let dirURL = URL(fileURLWithPath: appPreferencesModel.preferences.backup.backupDirectory)
                let exists = FileManager.default.fileExists(atPath: dirURL.path)
                HStack(spacing: 4) {
                    Circle().fill(exists ? .green : .orange).frame(width: 6, height: 6)
                    Text(exists ? "settings.backup.directoryExists".localized : "settings.backup.directoryNotExists".localized)
                        .font(.caption2).foregroundStyle(palette.subtitle)
                }
            }
        }
    }

    // MARK: - 分层备份层选择

    private var layerSelectionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("settings.backup.configureLayers".localized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.subtitle)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 4) {
                ForEach(Array(BackupLayer.allCases)) { layer in
                    Button {
                        appPreferencesModel.toggleBackupLayer(layer)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: layer.iconName)
                                .font(.caption2)
                                .foregroundStyle(palette.accent)
                                .frame(width: 16)
                            Text(layer.displayName)
                                .font(.caption2)
                                .foregroundStyle(palette.title)
                            Spacer()
                            Image(systemName: appPreferencesModel.preferences.backup.enabledLayers.contains(layer)
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.caption2)
                                .foregroundStyle(appPreferencesModel.preferences.backup.enabledLayers.contains(layer)
                                                 ? .green : palette.subtitle)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var layeredStatusDisclosureGroup: some View {
        if !appPreferencesModel.backupLayerResults.isEmpty {
            DisclosureGroup {
                VStack(spacing: 4) {
                    ForEach(appPreferencesModel.backupLayerResults) { layer in
                        HStack(spacing: 8) {
                            Image(systemName: layer.isSuccessful ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(layer.isSuccessful ? .green : .red)
                            Text(layer.layer.displayName)
                                .font(.caption)
                                .foregroundStyle(palette.title)
                            Spacer()
                            Text(verbatim: layer.sizeFormatted)
                                .font(.caption2)
                                .foregroundStyle(palette.subtitle)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.04)))
                    }
                }
                .padding(.top, 4)
            } label: {
                Text(AppLocalization.format("settings.backup.layeredFileCount", appPreferencesModel.backupLayerResults.reduce(0) { $0 + $1.fileCount }))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.title)
            }
        }
    }

    @ViewBuilder
    private var backupFileListDisclosureGroup: some View {
        if !appPreferencesModel.backupRecords.isEmpty {
            DisclosureGroup {
                VStack(spacing: 6) {
                    ForEach(appPreferencesModel.backupRecords.prefix(10)) { record in
                        HStack(spacing: 8) {
                            Image(systemName: record.backupType == .layered ? "folder" : "doc")
                                .font(.caption2)
                                .foregroundStyle(record.backupType == .layered ? palette.accentSecondary : palette.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: record.fileName)
                                    .font(.caption)
                                    .foregroundStyle(palette.title)
                                    .lineLimit(1)
                                Text(verbatim: ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file) + " · " + formattedDate(record.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(palette.subtitle)
                            }
                            Spacer()
                            Button {
                                appPreferencesModel.deleteBackupRecord(record)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption2)
                                    .foregroundStyle(palette.danger)
                            }
                            .buttonStyle(.borderless)
                            .help("Delete backup record")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.05)))
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("settings.backup.fileListTitle".localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.title)
            }
        }
    }

    // MARK: - 备份概览

    @ViewBuilder
    private var backupOverviewSection: some View {
        if let overview = appPreferencesModel.backupOverview {
            SettingsSurfaceCard(
                title: "settings.backup.overviewTitle".localized,
                subtitle: "settings.backup.overviewSubtitle".localized,
                role: .secondary,
                palette: palette
            ) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    SettingsSummaryCard(
                        title: "settings.backup.fullBackupCount".localized,
                        value: "\(overview.layeredBackupCount)",
                        subtitle: "",
                        systemImage: "folder",
                        tint: palette.accentSecondary,
                        palette: palette
                    )
                    SettingsSummaryCard(
                        title: "settings.backup.configBackupCount".localized,
                        value: "\(overview.flatFileCount)",
                        subtitle: "",
                        systemImage: "doc.on.doc",
                        tint: palette.accent,
                        palette: palette
                    )
                    SettingsSummaryCard(
                        title: "settings.backup.totalSize".localized,
                        value: overview.totalSizeFormatted,
                        subtitle: "",
                        systemImage: "externaldrive",
                        tint: palette.accentSecondary,
                        palette: palette
                    )
                    SettingsSummaryCard(
                        title: "settings.backup.lastBackupTime".localized,
                        value: overview.lastBackupDate.map { formattedDate($0) } ?? "settings.backup.never".localized,
                        subtitle: "",
                        systemImage: "clock",
                        tint: .green,
                        palette: palette
                    )
                }
            }
        } else {
            SettingsSurfaceCard(
                title: "settings.backup.overviewTitle".localized,
                subtitle: "settings.backup.overviewSubtitle".localized,
                role: .secondary,
                palette: palette
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .font(.title2)
                        .foregroundStyle(palette.subtitle)
                    Text("settings.backup.noBackupOverview".localized)
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                    Text("settings.backup.noBackupOverviewHint".localized)
                        .font(.caption2)
                        .foregroundStyle(palette.accent)
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }
        }
    }

    // MARK: - 完备性测验

    @ViewBuilder
    private var completenessSection: some View {
        if let report = appPreferencesModel.backupCompleteness {
            SettingsSurfaceCard(
                title: "settings.backup.completenessTitle".localized,
                subtitle: "\("settings.backup.coverage".localized): \(report.coveragePercent) (\(report.expectedFiles.count)/\("settings.backup.fileCount".localized))",
                role: report.isComplete ? .secondary : .warning,
                palette: palette
            ) {
                VStack(spacing: 6) {
                    if !report.groupReports.isEmpty {
                        ForEach(Array(report.groupReports.keys.sorted()), id: \.self) { groupId in
                            let isComplete = report.groupReports[groupId] ?? false
                            let groupName = groupDisplayName(groupId)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isComplete ? .green : .orange)
                                    .frame(width: 6, height: 6)
                                Text(verbatim: groupName)
                                    .font(.caption)
                                    .foregroundStyle(palette.title)
                                Spacer()
                                Text(isComplete ? "settings.backup.groupBackedUp".localized : "settings.backup.groupNotBackedUp".localized)
                                    .font(.caption2)
                                    .foregroundStyle(isComplete ? .green : .orange)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.04)))
                        }
                    } else {
                        ForEach(report.expectedFiles, id: \.self) { file in
                            let isBackedUp = report.backedUpFiles.contains(file)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isBackedUp ? .green : .red)
                                    .frame(width: 6, height: 6)
                                Text(verbatim: file)
                                    .font(.caption)
                                    .foregroundStyle(palette.title)
                                Spacer()
                                Text(isBackedUp ? "✓" : "✗")
                                    .font(.caption)
                                    .foregroundStyle(isBackedUp ? .green : .red)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.04)))
                        }
                    }
                }
            }
        } else {
            SettingsSurfaceCard(
                title: "settings.backup.completenessTitle".localized,
                subtitle: "settings.backup.completenessHint".localized,
                role: .secondary,
                palette: palette
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.title2)
                        .foregroundStyle(palette.subtitle)
                    Text("settings.backup.noCompletenessReport".localized)
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                    Text("settings.backup.noCompletenessReportHint".localized)
                        .font(.caption2)
                        .foregroundStyle(palette.accent)
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }
        }
    }

    // MARK: - Helpers

    private func groupDisplayName(_ id: String) -> String {
        switch id {
        case "opencode": return AppLocalization.text("settings.backup.group.opencode")
        case "omo": return AppLocalization.text("settings.backup.group.omo")
        case "agents": return AppLocalization.text("settings.backup.group.agents")
        case "deprecated": return AppLocalization.text("settings.backup.group.deprecated")
        default: return id
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func selectBackupDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "settings.backup.selectDirectoryMessage".localized
        panel.prompt = "settings.action.selectDirectory".localized
        if panel.runModal() == .OK, let url = panel.url {
            appPreferencesModel.backupDirectoryBinding.wrappedValue = url.path
            appPreferencesModel.refreshBackupState()
        }
    }

    private func createBackupDirectory() {
        let dir = appPreferencesModel.preferences.backup.backupDirectory
        let url = URL(fileURLWithPath: dir)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            appPreferencesModel.refreshBackupState()
        }
    }
}

private extension String {
    var localized: String {
        AppLocalization.text(self)
    }
}
