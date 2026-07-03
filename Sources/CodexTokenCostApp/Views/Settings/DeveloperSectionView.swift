import SwiftUI
import CodexTokenCostCore

struct DeveloperSectionView: View {
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    let palette: TokenCostPalette
    @Binding var isDeveloperDocPresented: Bool

    @State private var optimizeFindings: [DeveloperFinding] = []
    @State private var hasScanned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            developerModeToggle
            optimizeSection
            localGovernanceSection
            ollamaUsageTrackingSection
            aiAnalysisSection
            docButton
        }
    }

    // MARK: - 总开关

    private var developerModeToggle: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("settings.developerMode.detail.title"),
            subtitle: AppLocalization.text("settings.developerMode.detail.subtitle"),
            role: .primary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    AppLocalization.text("settings.developerMode.enableToggle"),
                    isOn: appPreferencesModel.developerModeIsEnabledBinding
                )
                .font(.subheadline)
                .foregroundStyle(palette.title)

                Text(AppLocalization.text("settings.developerMode.description"))
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
            }
        }
    }

    // MARK: - 存储优化扫描

    private var optimizeSection: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("settings.developerMode.optimize"),
            subtitle: AppLocalization.text("developerMode.optimize.findings"),
            role: optimizeFindings.isEmpty ? .secondary : .warning,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        optimizeFindings = OptimizeScanner.scan()
                        hasScanned = true
                    } label: {
                        Label(AppLocalization.text("developerMode.optimize.scan"), systemImage: "magnifyingglass")
                    }
                    .settingsGlassButtonStyle(prominent: true)
                    .controlSize(.small)

                    if hasScanned {
                        Text("\(optimizeFindings.count) \("developerMode.optimize.findings".localized)")
                            .font(.caption)
                            .foregroundStyle(palette.subtitle)
                    }

                    Spacer()
                }

                if hasScanned {
                    if optimizeFindings.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(AppLocalization.text("settings.developerMode.optimize.noIssues"))
                                .font(.caption)
                                .foregroundStyle(palette.subtitle)
                        }
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(optimizeFindings) { finding in
                                    findingRow(finding)
                                }
                            }
                        }
                        .frame(maxHeight: 300)
                    }
                }
            }
        }
    }

    private func findingRow(_ finding: DeveloperFinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: findingIcon(for: finding.category))
                    .font(.caption2)
                    .foregroundStyle(findingColor(for: finding.category))
                    .frame(width: 16)
                Text(finding.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.title)
            }
            Text(finding.detail)
                .font(.caption2)
                .foregroundStyle(palette.subtitle)
                .fixedSize(horizontal: false, vertical: true)
            Text(finding.suggestion)
                .font(.caption2)
                .foregroundStyle(palette.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.05)))
    }

    private func findingIcon(for category: DeveloperFinding.FindingCategory) -> String {
        switch category {
        case .staleSnapshot: return "clock.badge.exclamationmark"
        case .excessBackup: return "externaldrive.badge.plus"
        case .largeSessionDir: return "folder.badge.gearshape"
        case .configFragmentation: return "doc.on.doc"
        case .staleLatest: return "arrow.clockwise"
        }
    }

    private func findingColor(for category: DeveloperFinding.FindingCategory) -> Color {
        switch category {
        case .staleSnapshot: return .orange
        case .excessBackup: return .yellow
        case .largeSessionDir: return .red
        case .configFragmentation: return .orange
        case .staleLatest: return .orange
        }
    }

    // MARK: - 本地治理

    private var localGovernanceSection: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("settings.developerMode.governance.title"),
            subtitle: AppLocalization.text("settings.developerMode.governance.subtitle"),
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    AppLocalization.text("settings.developerMode.localGovernance"),
                    isOn: appPreferencesModel.developerModeToggleBinding(for: \.localGovernanceEnabled)
                )
                .font(.subheadline)
                .foregroundStyle(palette.title)

                Divider().opacity(0.3)

                governanceRow(
                    icon: "folder",
                    title: AppLocalization.text("settings.developerMode.governance.configDir"),
                    path: "~/.config/opencode"
                )
                governanceRow(
                    icon: "gearshape.2",
                    title: AppLocalization.text("settings.developerMode.governance.skillsDir"),
                    path: "~/.config/opencode/skills"
                )
                governanceRow(
                    icon: "terminal",
                    title: AppLocalization.text("settings.developerMode.governance.sessionDir"),
                    path: "~/.codex/sessions"
                )
            }
        }
    }

    private func governanceRow(icon: String, title: String, path: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(palette.accent)
                .frame(width: 16)
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.title)
            Spacer()
            Text(verbatim: path)
                .font(.caption2)
                .foregroundStyle(palette.subtitle)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Ollama 用量追踪 gate

    @ViewBuilder
    private var ollamaUsageTrackingSection: some View {
        if appPreferencesModel.preferences.developerMode.isEnabled {
            SettingsSurfaceCard(
                title: "Ollama Cloud 用量追踪",
                subtitle: "实验性功能：通过 Keychain 存储的 cookie 查询 ollama.com/settings 用量",
                role: .secondary,
                palette: palette
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        "启用 Ollama 用量追踪",
                        isOn: appPreferencesModel.developerModeToggleBinding(for: \.ollamaUsageTrackingEnabled)
                    )
                    .font(.subheadline)
                    .foregroundStyle(palette.title)

                    Text("启用后在余额监控设置中可见 Ollama Cloud 行，并支持从浏览器自动导入 cookie。")
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - AI 分析

    private var aiAnalysisSection: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("settings.developerMode.aiAnalysis"),
            subtitle: AppLocalization.text("settings.developerMode.aiAnalysisDisabled"),
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                    Text(AppLocalization.text("settings.developerMode.aiAnalysisDisabled"))
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                    Spacer()
                    Text("Phase 4")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.subtitle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(palette.subtitle.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    // MARK: - 文档按钮

    private var docButton: some View {
        HStack {
            Spacer()
            Button {
                isDeveloperDocPresented = true
            } label: {
                Label(AppLocalization.text("settings.developerMode.doc.button"), systemImage: "doc.text")
            }
            .settingsGlassButtonStyle(prominent: false)
            .controlSize(.small)
        }
    }
}

private extension String {
    var localized: String {
        AppLocalization.text(self)
    }
}
