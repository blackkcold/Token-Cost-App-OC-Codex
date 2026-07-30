import SwiftUI
import CodexTokenCostCore

enum BalanceWorkshopChartLayout {
    static let normalSegmentCount = 10
    static let compactSegmentCount = 5

    static func normalized(_ value: Double) -> Double {
        guard value.isFinite, !value.isNaN else { return 0 }
        return min(max(value, 0), 1)
    }

    static func segmentFills(for value: Double, segmentCount: Int) -> [SegmentFill] {
        guard segmentCount > 0 else { return [] }

        let scaledValue = normalized(value) * Double(segmentCount)
        return (0..<segmentCount).map { index in
            SegmentFill(
                index: index,
                ratio: min(max(scaledValue - Double(index), 0), 1)
            )
        }
    }
}

struct WorkshopBalancePanelBackdrop: View {
    let palette: TokenCostPalette

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                palette.surfaceSolidFill

                Canvas { context, size in
                    drawGrid(context: &context, size: size)
                    drawCornerMarks(context: &context, size: size)
                }

                Rectangle()
                    .fill(palette.accent)
                    .frame(width: min(118, proxy.size.width * 0.28), height: 5)

                Rectangle()
                    .fill(palette.accentSecondary)
                    .frame(width: 5, height: min(82, proxy.size.height * 0.30))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        let spacing: CGFloat = 22

        for x in stride(from: CGFloat.zero, through: size.width, by: spacing) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        for y in stride(from: CGFloat.zero, through: size.height, by: spacing) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }

        context.stroke(path, with: .color(palette.title.opacity(0.055)), lineWidth: 1)
    }

    private func drawCornerMarks(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        let inset: CGFloat = 12
        let length: CGFloat = 18

        path.move(to: CGPoint(x: inset, y: inset + length))
        path.addLine(to: CGPoint(x: inset, y: inset))
        path.addLine(to: CGPoint(x: inset + length, y: inset))

        path.move(to: CGPoint(x: size.width - inset - length, y: size.height - inset))
        path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
        path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset - length))

        context.stroke(
            path,
            with: .color(palette.surfaceAccessibleStroke.opacity(0.28)),
            style: StrokeStyle(lineWidth: 2, lineCap: .square, lineJoin: .miter)
        )
    }
}

struct WorkshopBalanceTitleMark: View {
    let title: String
    let subtitle: String?
    let palette: TokenCostPalette
    var compact = false

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 7 : 10) {
            ZStack {
                Rectangle()
                    .fill(palette.accent)
                    .overlay(
                        Rectangle()
                            .strokeBorder(palette.surfaceAccessibleStroke, lineWidth: compact ? 1.5 : 2)
                    )

                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: compact ? 10 : 13, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: compact ? 24 : 32, height: compact ? 24 : 32)

            VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                Text(title.uppercased())
                    .font(TokenTypography.metric(size: compact ? 12 : 15, weight: .black, palette: palette))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let subtitle, !subtitle.isEmpty, !compact {
                    Text(subtitle)
                        .font(TokenTypography.caption2(weight: .semibold, palette: palette))
                        .foregroundStyle(palette.subtitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
        }
    }
}

struct WorkshopBalanceProviderMark: View {
    let provider: BalanceProviderKind
    let palette: TokenCostPalette
    var size: CGFloat = 22
    var plateSize: CGFloat = 38

    var body: some View {
        ProviderLogoMark(provider: provider, size: size, tint: palette.title)
            .frame(width: plateSize, height: plateSize)
            .background {
                Rectangle()
                    .fill(palette.surfaceSolidFill)
                    .overlay(
                        Rectangle()
                            .strokeBorder(palette.surfaceAccessibleStroke, lineWidth: 2)
                    )
                    .shadow(color: palette.accentSecondary.opacity(0.72), radius: 0, x: 3, y: 3)
            }
    }
}

struct WorkshopBalanceStatusStamp: View {
    let title: String
    let tint: Color
    let palette: TokenCostPalette

    var body: some View {
        Text(title.uppercased())
            .font(TokenTypography.metric(size: 9, weight: .black, palette: palette))
            .foregroundStyle(palette.title)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background {
                Rectangle()
                    .fill(tint.opacity(0.18))
                    .overlay(
                        Rectangle()
                            .strokeBorder(palette.surfaceAccessibleStroke, lineWidth: 1.5)
                    )
            }
    }
}

struct WorkshopBalanceQuotaMeter: View {
    let value: Double
    let tint: Color
    let palette: TokenCostPalette
    var segmentCount = BalanceWorkshopChartLayout.normalSegmentCount
    var height: CGFloat = 9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false

    private var segmentFills: [SegmentFill] {
        BalanceWorkshopChartLayout.segmentFills(for: value, segmentCount: segmentCount)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segmentFills, id: \.index) { segment in
                GeometryReader { proxy in
                    let displayedRatio = isRevealed ? segment.ratio : 0

                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(palette.trackBackground.opacity(0.88))
                            .overlay(
                                Rectangle()
                                    .strokeBorder(palette.surfaceAccessibleStroke.opacity(0.46), lineWidth: 0.7)
                            )

                        Rectangle()
                            .fill(segment.index.isMultiple(of: 2) ? tint : tint.opacity(0.78))
                            .frame(width: proxy.size.width * displayedRatio)
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 0.28),
                                value: displayedRatio
                            )
                    }
                }
            }
        }
        .frame(height: height)
        .onAppear { isRevealed = true }
        .accessibilityHidden(true)
    }
}

struct WorkshopBalanceCurrencyStamp: View {
    let symbols: String
    let palette: TokenCostPalette

    var body: some View {
        Text(symbols)
            .font(TokenTypography.metric(size: 10, weight: .black, palette: palette))
            .foregroundStyle(palette.title)
            .tracking(1)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background {
                Rectangle()
                    .fill(palette.accentSecondary.opacity(0.22))
                    .overlay(
                        Rectangle()
                            .strokeBorder(palette.surfaceAccessibleStroke, lineWidth: 1.5)
                    )
            }
            .accessibilityHidden(true)
    }
}
