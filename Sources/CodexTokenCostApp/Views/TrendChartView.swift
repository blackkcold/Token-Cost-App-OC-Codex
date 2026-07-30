import Charts
import SwiftUI
import CodexTokenCostCore

struct TokenTrendTooltipLine: Identifiable {
    var id: String { "\(title)|\(value)" }

    let color: Color
    let title: String
    let value: String
}

struct TokenTrendChartPoint: Identifiable {
    var id: String { dateString }

    let date: Date
    let dateString: String
    let actualTokens: Double
    let tooltipLines: [TokenTrendTooltipLine]
}

struct TokenTrendRangePicker: View {
    @Binding var selection: Int
    let palette: TokenCostPalette

    @ViewBuilder
    var body: some View {
        if palette.usesWorkshopStyle {
            HStack(spacing: 6) {
                workshopRangeButton(title: AppLocalization.text("trend.range.7days"), value: 7)
                workshopRangeButton(title: AppLocalization.text("trend.range.30days"), value: 30)
            }
        } else {
            Picker("", selection: $selection) {
                Text(AppLocalization.text("trend.range.7days")).tag(7)
                Text(AppLocalization.text("trend.range.30days")).tag(30)
            }
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func workshopRangeButton(title: String, value: Int) -> some View {
        let isSelected = selection == value
        return Button {
            selection = value
        } label: {
            Text(title)
                .font(TokenTypography.caption(weight: .bold, palette: palette))
                .foregroundStyle(isSelected ? Color.white : palette.title)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? palette.accent : palette.surfaceSolidFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(palette.surfaceAccessibleStroke, lineWidth: 1.8)
                        )
                        .shadow(
                            color: isSelected ? palette.accentSecondary.opacity(0.55) : palette.surfaceShadow.opacity(0.55),
                            radius: 0,
                            x: 2,
                            y: 2
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct TokenTrendChartView: View {
    let points: [TokenTrendChartPoint]
    let palette: TokenCostPalette

    @State private var hoveredPoint: TokenTrendChartPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value(AppLocalization.text("chart.label.date"), point.date),
                        y: .value(AppLocalization.text("chart.label.actual"), point.actualTokens)
                    )
                    .interpolationMethod(palette.usesWorkshopStyle ? .linear : .monotone)
                    .foregroundStyle(areaStyle)

                    LineMark(
                        x: .value(AppLocalization.text("chart.label.date"), point.date),
                        y: .value(AppLocalization.text("chart.label.actual"), point.actualTokens)
                    )
                    .interpolationMethod(palette.usesWorkshopStyle ? .linear : .monotone)
                    .foregroundStyle(palette.accent)
                    .lineStyle(
                        palette.usesWorkshopStyle
                            ? StrokeStyle(lineWidth: 3, lineCap: .butt, lineJoin: .miter)
                            : StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )

                    if palette.usesWorkshopStyle {
                        PointMark(
                            x: .value(AppLocalization.text("chart.label.date"), point.date),
                            y: .value(AppLocalization.text("chart.label.actual"), point.actualTokens)
                        )
                        .symbol(.square)
                        .symbolSize(28)
                        .foregroundStyle(palette.accentSecondary)
                    }
                }

                if let hoveredPoint {
                    RuleMark(x: .value(AppLocalization.text("chart.label.date"), hoveredPoint.date))
                        .foregroundStyle(palette.usesWorkshopStyle ? palette.accentSecondary : palette.subtitle.opacity(0.55))
                        .lineStyle(
                            palette.usesWorkshopStyle
                                ? StrokeStyle(lineWidth: 2)
                                : StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )

                    PointMark(
                        x: .value(AppLocalization.text("chart.label.date"), hoveredPoint.date),
                        y: .value(AppLocalization.text("chart.label.actual"), hoveredPoint.actualTokens)
                    )
                    .symbolSize(60)
                    .foregroundStyle(palette.accent)
                }
            }
            .chartXAxis { workshopAwareAxisMarks() }
            .chartYAxis { workshopAwareAxisMarks(position: .leading) }
            .frame(height: 260)
            .padding(.top, 4)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                updateSelection(location: location, proxy: proxy, geometry: geometry)
                            case .ended:
                                hoveredPoint = nil
                            }
                        }
                }
            }
            .onChange(of: points.count) { _, _ in
                hoveredPoint = nil
            }

            if let hoveredPoint {
                TokenTrendTooltipCard(point: hoveredPoint, palette: palette)
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing))
                    )
            }
        }
        .animation(TokenMotion.resolved(TokenMotion.micro, reduceMotion: reduceMotion), value: hoveredPoint != nil)
    }

    private var areaStyle: AnyShapeStyle {
        if palette.usesWorkshopStyle {
            return AnyShapeStyle(palette.accent.opacity(0.10))
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    palette.accent.opacity(0.30),
                    palette.accent.opacity(0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @AxisContentBuilder
    private func workshopAwareAxisMarks(position: AxisMarkPosition = .automatic) -> some AxisContent {
        if palette.usesWorkshopStyle {
            AxisMarks(position: position) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(palette.title.opacity(0.20))
                AxisTick(stroke: StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(palette.title)
                AxisValueLabel()
                    .font(TokenTypography.caption2(palette: palette))
                    .foregroundStyle(palette.subtitle)
            }
        } else {
            AxisMarks(position: position)
        }
    }

    private func updateSelection(
        location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrame = proxy.plotFrame else {
            hoveredPoint = nil
            return
        }

        let frame = geometry[plotFrame]
        let x = location.x - frame.origin.x
        guard let selectedDate: Date = proxy.value(atX: x, as: Date.self) else {
            hoveredPoint = nil
            return
        }

        hoveredPoint = points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(selectedDate)) < abs(rhs.date.timeIntervalSince(selectedDate))
        }
    }
}

private struct TokenTrendTooltipCard: View {
    let point: TokenTrendChartPoint
    let palette: TokenCostPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(point.dateString)
                .font(TokenTypography.caption(weight: .bold, palette: palette))
                .foregroundStyle(palette.title)

            ForEach(point.tooltipLines) { line in
                HStack(spacing: 8) {
                    Circle()
                        .fill(line.color)
                        .frame(width: 8, height: 8)
                    Text(line.title)
                        .font(TokenTypography.caption(palette: palette))
                        .foregroundStyle(palette.subtitle)
                    Spacer(minLength: 0)
                    Text(line.value)
                        .font(TokenTypography.caption(weight: .bold, palette: palette))
                        .foregroundStyle(palette.title)
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: palette.usesWorkshopStyle ? 6 : TokenRadius.row, style: .continuous)
                .fill(palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: palette.usesWorkshopStyle ? 6 : TokenRadius.row, style: .continuous)
                        .strokeBorder(
                            palette.cardStroke,
                            lineWidth: palette.usesWorkshopStyle ? palette.cardBorderWidth : 1
                        )
                )
                .shadow(
                    color: palette.cardShadow,
                    radius: palette.usesWorkshopStyle ? palette.shadowRadius : TokenShadow.medium.radius,
                    x: palette.usesWorkshopStyle ? palette.shadowX : 0,
                    y: palette.usesWorkshopStyle ? palette.shadowY : TokenShadow.medium.y
                )
        }
    }
}
