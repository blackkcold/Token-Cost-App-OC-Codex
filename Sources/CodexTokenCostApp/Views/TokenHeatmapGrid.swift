import SwiftUI
import CodexTokenCostCore

struct TokenHeatmapGrid: View {
    let data: TokenHeatmapData
    let palette: TokenCostPalette

    private let spacing: CGFloat = 3
    private let legendHeight: CGFloat = 12
    private let legendTopSpacing: CGFloat = 8

    private var cardHeight: CGFloat { 136 }
    private var sortedCells: [TokenHeatmapCell] {
        data.allCells.sorted { $0.date < $1.date }
    }

    var body: some View {
        GeometryReader { geometry in
            let cells = sortedCells
            let gridHeight = max(0, geometry.size.height - legendHeight - legendTopSpacing)
            let layout = heatmapLayout(cellCount: cells.count, width: geometry.size.width, height: gridHeight)
            let columns = Array(
                repeating: GridItem(.fixed(layout.cellSize), spacing: spacing),
                count: layout.columnCount
            )

            VStack(alignment: .leading, spacing: legendTopSpacing) {
                LazyVGrid(columns: columns, alignment: .center, spacing: spacing) {
                    ForEach(cells) { cell in
                        RoundedRectangle(cornerRadius: max(1, layout.cellSize * 0.14))
                            .fill(heatmapColor(intensity: cell.intensity))
                            .frame(width: layout.cellSize, height: layout.cellSize)
                            .help("\(cell.dateString): \(Int(cell.tokenCount)) tokens")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: gridHeight, maxHeight: gridHeight, alignment: .center)

                HStack(spacing: 4) {
                    Text("少").font(.system(size: 8)).foregroundStyle(palette.subtitle)
                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { lvl in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(heatmapColor(intensity: lvl))
                            .frame(width: 8, height: 8)
                    }
                    Text("多").font(.system(size: 8)).foregroundStyle(palette.subtitle)
                }
                .frame(height: legendHeight)
            }
        }
        .frame(height: cardHeight)
    }

    private func heatmapLayout(cellCount: Int, width: CGFloat, height: CGFloat) -> HeatmapLayout {
        let count = max(cellCount, 1)
        let safeWidth = max(width, 1)
        let safeHeight = max(height, 1)
        var best = HeatmapLayout(columnCount: 1, cellSize: 0)

        for columnCount in 1...count {
            let rowCount = Int(ceil(Double(count) / Double(columnCount)))
            let horizontalSpacing = CGFloat(max(columnCount - 1, 0)) * spacing
            let verticalSpacing = CGFloat(max(rowCount - 1, 0)) * spacing
            let availableWidth = safeWidth - horizontalSpacing
            let availableHeight = safeHeight - verticalSpacing
            guard availableWidth > 0, availableHeight > 0 else { continue }

            let cellSize = min(availableWidth / CGFloat(columnCount), availableHeight / CGFloat(rowCount))
            if cellSize > best.cellSize {
                best = HeatmapLayout(columnCount: columnCount, cellSize: cellSize)
            }
        }

        return HeatmapLayout(
            columnCount: best.columnCount,
            cellSize: max(2, best.cellSize)
        )
    }

    private func heatmapColor(intensity: Double) -> Color {
        guard intensity > 0 else { return palette.accent.opacity(0.06) }
        return palette.accent.opacity(0.10 + min(max(intensity, 0), 1) * 0.90)
    }
}

private struct HeatmapLayout {
    let columnCount: Int
    let cellSize: CGFloat
}
