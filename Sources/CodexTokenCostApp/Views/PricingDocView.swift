import SwiftUI
import CodexTokenCostCore

struct PricingDocView: View {
    @Environment(\.dismiss) private var dismiss
    let palette: TokenCostPalette
    @State private var sections: [DocSection] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            renderSection(section)
                        }
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
            .navigationTitle(Text(verbatim: "\u{1F4C4} \(AppLocalization.text("settings.billing.pricingDoc"))"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.text("settings.action.close")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadAndParseMarkdown()
            }
        }

        .frame(minWidth: 780, minHeight: 560)
    }

    @ViewBuilder
    private func renderSection(_ section: DocSection) -> some View {
        switch section {
        case .heading(let level, let text):
            switch level {
            case 1:
                Text(verbatim: text)
                    .font(.title.weight(.bold))
                    .foregroundStyle(palette.title)
                    .padding(.bottom, 8)
            case 2:
                Text(verbatim: text)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
            default:
                Text(verbatim: text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.title)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
            }

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: 3)
                Text(verbatim: text)
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.cardFill)
            )
            .padding(.vertical, 8)

        case .table(let headers, let rows):
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                        Text(verbatim: header)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.title)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: idx == 0 ? 180 : (idx == headers.count - 1 ? .infinity : 130), alignment: .leading)
                    }
                }
                .background(palette.cardFill)

                Divider()
                    .overlay(palette.cardStroke)

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                            Text(verbatim: cell)
                                .font(.caption)
                                .foregroundStyle(colIdx == 0 ? palette.title : palette.subtitle)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: colIdx == 0 ? 180 : (colIdx == headers.count - 1 ? .infinity : 130), alignment: .leading)
                        }
                    }
                    if rowIdx < rows.count - 1 {
                        Divider()
                            .overlay(palette.cardStroke.opacity(0.4))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(palette.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.bottom, 16)

        case .paragraph(let text):
            Text(verbatim: text)
                .font(.callout)
                .foregroundStyle(palette.title)
                .padding(.vertical, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum DocSection {
    case heading(level: Int, text: String)
    case blockquote(String)
    case table(headers: [String], rows: [[String]])
    case paragraph(String)
}

private extension PricingDocView {

    func loadAndParseMarkdown() {
        guard let url = Bundle.module.url(forResource: "Pricing", withExtension: "md"),
              let content = try? String(contentsOf: url) else {
            sections = [.paragraph("Pricing documentation not found.")]
            return
        }
        sections = parseMarkdown(content)
    }

    func parseMarkdown(_ raw: String) -> [DocSection] {
        let lines = raw.components(separatedBy: .newlines)
        var result: [DocSection] = []
        var tableLines: [String] = []
        var inTable = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if inTable {
                    result.append(contentsOf: buildTable(from: tableLines))
                    tableLines = []
                    inTable = false
                }
                continue
            }

            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") {
                if inTable {
                    result.append(contentsOf: buildTable(from: tableLines))
                    tableLines = []
                    inTable = false
                }
                let level = trimmed.hasPrefix("### ") ? 3 : trimmed.hasPrefix("## ") ? 2 : 1
                let text = String(trimmed.dropFirst(level == 3 ? 4 : (level == 2 ? 3 : 2)))
                result.append(.heading(level: level, text: text))
                continue
            }

            if trimmed.hasPrefix("> ") {
                if inTable {
                    result.append(contentsOf: buildTable(from: tableLines))
                    tableLines = []
                    inTable = false
                }
                result.append(.blockquote(String(trimmed.dropFirst(2))))
                continue
            }

            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                inTable = true
                tableLines.append(trimmed)
                continue
            }

            if inTable && trimmed.contains("---") && trimmed.hasPrefix("|") {
                continue
            }

            if inTable {
                result.append(contentsOf: buildTable(from: tableLines))
                tableLines = []
                inTable = false
            }

            result.append(.paragraph(trimmed))
        }

        if inTable {
            result.append(contentsOf: buildTable(from: tableLines))
        }

        return result
    }

    func buildTable(from lines: [String]) -> [DocSection] {
        let contentLines = lines.filter { line in
            let cells = parseTableRow(line)
            if cells.isEmpty { return true }
            let isSeparator = cells.allSatisfy { cell in
                cell.allSatisfy { c in c == "-" || c == ":" || c == " " }
            }
            return !isSeparator
        }

        guard contentLines.count >= 2 else {
            return contentLines.isEmpty ? [] : contentLines.map { .paragraph($0) }
        }

        let headerRow = parseTableRow(contentLines[0])
        let dataRows = contentLines.dropFirst(1).map { parseTableRow($0) }
        let validRows = dataRows.filter { $0.count == headerRow.count }

        guard !headerRow.isEmpty, !validRows.isEmpty else {
            return contentLines.map { .paragraph($0) }
        }

        return [.table(headers: headerRow, rows: validRows)]
    }

    func parseTableRow(_ line: String) -> [String] {
        let withoutEdges = line.dropFirst().dropLast()
        return withoutEdges.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
