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

    var body: some View {
        Picker("", selection: $selection) {
            Text("7 日").tag(7)
            Text("30 日").tag(30)
        }
        .pickerStyle(.segmented)
        .frame(width: 100)
    }
}

struct TokenTrendChartView: View {
    let points: [TokenTrendChartPoint]
    let palette: TokenCostPalette

    @State private var hoveredPoint: TokenTrendChartPoint?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value(AppLocalization.text("chart.label.date"), point.date),
                        y: .value(AppLocalization.text("chart.label.actual"), point.actualTokens)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                palette.accent.opacity(0.30),
                                palette.accent.opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value(AppLocalization.text("chart.label.date"), point.date),
                        y: .value(AppLocalization.text("chart.label.actual"), point.actualTokens)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }

                if let hoveredPoint {
                    RuleMark(x: .value(AppLocalization.text("chart.label.date"), hoveredPoint.date))
                        .foregroundStyle(palette.subtitle.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value(AppLocalization.text("chart.label.date"), hoveredPoint.date),
                        y: .value(AppLocalization.text("chart.label.actual"), hoveredPoint.actualTokens)
                    )
                    .symbolSize(60)
                    .foregroundStyle(palette.accent)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
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
            }
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.title)

            ForEach(point.tooltipLines) { line in
                HStack(spacing: 8) {
                    Circle()
                        .fill(line.color)
                        .frame(width: 8, height: 8)
                    Text(line.title)
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                    Spacer(minLength: 0)
                    Text(line.value)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.title)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.cardStroke, lineWidth: 1)
        )
        .shadow(color: palette.cardShadow, radius: 10, x: 0, y: 8)
    }
}
