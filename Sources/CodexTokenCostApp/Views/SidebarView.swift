import SwiftUI
import CodexTokenCostCore

struct SidebarView: View {
    @ObservedObject var model: TokenCostModel
    let palette: TokenCostPalette

    private var selectionBinding: Binding<TokenCostSource.ID?> {
        Binding(
            get: { model.selectedSourceID },
            set: { model.selectSource(id: $0) }
        )
    }

    var body: some View {
        List(selection: selectionBinding) {
            Section(AppLocalization.text("sidebar.section.sources")) {
                ForEach(model.sources) { source in
                    SidebarSourceRow(source: source, palette: palette)
                        .tag(Optional(source.id))
                }
            }

            Section(AppLocalization.text("sidebar.section.scanRoots")) {
                ForEach(model.settings.scanRoots, id: \.self) { path in
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(CodexAppPaths.appDisplayName)
        .safeAreaInset(edge: .bottom) {
            SidebarFooter(model: model, palette: palette)
        }
    }
}

private struct SidebarSourceRow: View {
    let source: TokenCostSource
    let palette: TokenCostPalette

    var body: some View {
        HStack(spacing: 10) {
            TokenDashboardSymbolMark(
                systemImage: iconName,
                tint: color,
                palette: palette,
                size: 22,
                fontSize: 10
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .lineLimit(1)

                Text(source.displayPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch source.status {
        case .available: return "externaldrive.badge.checkmark"
        case .locked: return "lock.circle"
        case .unsupported: return "exclamationmark.triangle"
        case .missing: return "questionmark.diamond"
        case .unknown: return "circle.dashed"
        }
    }

    private var color: Color {
        switch source.status {
        case .available: return palette.accent
        case .locked: return palette.warning
        case .unsupported: return palette.warning.opacity(0.82)
        case .missing: return palette.danger
        case .unknown: return palette.subtitle
        }
    }
}

private struct SidebarFooter: View {
    @ObservedObject var model: TokenCostModel
    let palette: TokenCostPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack(spacing: 8) {
                TokenDashboardSymbolMark(
                    systemImage: model.isRefreshing ? "arrow.triangle.2.circlepath" : "checkmark.shield.fill",
                    tint: model.isRefreshing ? palette.accent : palette.success,
                    palette: palette,
                    size: 24,
                    fontSize: 11
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(palette.title)
                        .lineLimit(2)
                    if let error = model.lastErrorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(palette.subtitle)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(
                RoundedRectangle(cornerRadius: palette.cardCornerRadius, style: .continuous)
                    .fill(palette.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: palette.cardCornerRadius, style: .continuous)
                            .strokeBorder(palette.cardStroke, lineWidth: palette.cardBorderWidth)
                    )
                    .shadow(
                        color: palette.cardShadow,
                        radius: palette.shadowRadius,
                        x: palette.shadowX,
                        y: palette.shadowY
                    )
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .background {
            if palette.usesWorkshopStyle {
                palette.surfaceSecondarySolidFill
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }
}
