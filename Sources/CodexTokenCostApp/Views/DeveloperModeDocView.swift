import SwiftUI
import CodexTokenCostCore

struct DeveloperModeDocView: View {
    @Environment(\.dismiss) private var dismiss
    let palette: TokenCostPalette

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        overviewSection
                        featuresSection
                        usageSection
                        securitySection
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                HStack {
                    Spacer()
                    Button(AppLocalization.text("settings.action.close")) {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(palette.cardFill)
            }
            .navigationTitle(Text(verbatim: "\u{1F527} \(AppLocalization.text("developerMode.doc.title"))"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.text("settings.action.close")) {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    // MARK: - Overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(AppLocalization.text("developerMode.doc.overviewTitle"))
            Text(AppLocalization.text("developerMode.doc.overviewBody"))
                .font(.callout)
                .foregroundStyle(palette.title)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                principleBadge(icon: "desktopcomputer", text: AppLocalization.text("developerMode.doc.principleLocal"))
                principleBadge(icon: "eye.slash", text: AppLocalization.text("developerMode.doc.principleReadonly"))
                principleBadge(icon: "function", text: AppLocalization.text("developerMode.doc.principleDeterministic"))
                principleBadge(icon: "text.magnifyingglass", text: AppLocalization.text("developerMode.doc.principleExplainable"))
            }
            .padding(.top, 4)
        }
    }

    private func principleBadge(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(palette.accent)
            Text(text)
                .font(.caption2)
                .foregroundStyle(palette.subtitle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.cardFill)
        )
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(AppLocalization.text("developerMode.doc.featuresTitle"))

            featureRow(
                icon: "tag",
                title: AppLocalization.text("settings.developerMode.taskClassification"),
                description: AppLocalization.text("developerMode.doc.taskClassificationDesc"),
                status: .available
            )

            featureRow(
                icon: "externaldrive.badge.checkmark",
                title: AppLocalization.text("settings.developerMode.optimize"),
                description: AppLocalization.text("developerMode.doc.optimizeDesc"),
                status: .available
            )

            featureRow(
                icon: "lock.shield",
                title: AppLocalization.text("settings.developerMode.localGovernance"),
                description: AppLocalization.text("developerMode.doc.localGovernanceDesc"),
                status: .available
            )

            featureRow(
                icon: "chart.bar.xaxis",
                title: AppLocalization.text("settings.developerMode.modelCompare"),
                description: AppLocalization.text("developerMode.doc.modelCompareDesc"),
                status: .available
            )

            featureRow(
                icon: "banknote",
                title: AppLocalization.text("settings.developerMode.multiCurrency"),
                description: AppLocalization.text("developerMode.doc.multiCurrencyDesc"),
                status: .available
            )

            featureRow(
                icon: "brain",
                title: AppLocalization.text("settings.developerMode.aiAnalysisDisabled"),
                description: AppLocalization.text("developerMode.doc.aiAnalysisDesc"),
                status: .comingSoon
            )
        }
    }

    private enum FeatureStatus {
        case available
        case comingSoon
    }

    private func featureRow(icon: String, title: String, description: String, status: FeatureStatus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(palette.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.title)

                    if status == .comingSoon {
                        Text(AppLocalization.text("developerMode.doc.comingSoon"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(.orange.opacity(0.12))
                            )
                    }
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.cardFill)
        )
    }

    // MARK: - Usage

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(AppLocalization.text("developerMode.doc.usageTitle"))

            usageStep(
                step: "1",
                title: AppLocalization.text("developerMode.doc.usageStep1Title"),
                detail: AppLocalization.text("developerMode.doc.usageStep1Detail")
            )

            usageStep(
                step: "2",
                title: AppLocalization.text("developerMode.doc.usageStep2Title"),
                detail: AppLocalization.text("developerMode.doc.usageStep2Detail")
            )

            usageStep(
                step: "3",
                title: AppLocalization.text("developerMode.doc.usageStep3Title"),
                detail: AppLocalization.text("developerMode.doc.usageStep3Detail")
            )
        }
    }

    private func usageStep(step: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(palette.accent))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(AppLocalization.text("developerMode.doc.securityTitle"))

            VStack(alignment: .leading, spacing: 8) {
                securityRow(icon: "checkmark.shield.fill", text: AppLocalization.text("developerMode.doc.securityLocal"))
                securityRow(icon: "checkmark.shield.fill", text: AppLocalization.text("developerMode.doc.securityReadonly"))
                securityRow(icon: "checkmark.shield.fill", text: AppLocalization.text("developerMode.doc.securityNoNetwork"))
                securityRow(icon: "checkmark.shield.fill", text: AppLocalization.text("developerMode.doc.securityNoCredentials"))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.cardFill)
            )
        }
    }

    private func securityRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.green)
            Text(text)
                .font(.caption)
                .foregroundStyle(palette.title)
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline.weight(.semibold))
            .foregroundStyle(palette.accent)
    }
}
