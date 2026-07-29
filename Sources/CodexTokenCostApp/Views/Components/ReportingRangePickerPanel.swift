import SwiftUI
import CodexTokenCostCore

struct ReportingRangePickerPanel: View {
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    let palette: TokenCostPalette

    @State private var visibleMonth = Date()
    @State private var pendingStart: Date?

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            weekdayHeader
            monthGrid
            footer
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsInsetSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous), palette: palette)
        .onAppear {
            ensureUsableBoundsIfNeeded()
            syncVisibleMonthFromSelection()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.text("settings.billing.reportingRange.customTitle"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.title)

                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                calendarNavButton(
                                    systemImage: "chevron.left",
                                    label: AppLocalization.text("settings.billing.reportingRange.previousMonth")
                                ) {
                                    shiftVisibleMonth(by: -1)
                                }

                Text(monthTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.title)
                    .frame(minWidth: 128)

                calendarNavButton(
                                    systemImage: "chevron.right",
                                    label: AppLocalization.text("settings.billing.reportingRange.nextMonth")
                                ) {
                                    shiftVisibleMonth(by: 1)
                                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.subtitle)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .center), count: 7),
            spacing: 4
        ) {
            ForEach(monthCells) { cell in
                Button {
                    handleDateTap(cell.date)
                } label: {
                    CalendarDayCell(
                        date: cell.date,
                        isInDisplayedMonth: cell.isInDisplayedMonth,
                        isToday: calendar.isDateInToday(cell.date),
                        isSelectedStart: isSelectedStart(cell.date),
                        isSelectedEnd: isSelectedEnd(cell.date),
                        isInCommittedRange: isInCommittedRange(cell.date),
                        palette: palette
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(footerTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.title)
                    .lineLimit(2)

                Text(footerDetail)
                    .font(.caption2)
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                pendingStart = nil
                appPreferencesModel.resetReportingRangeCustomBounds()
                syncVisibleMonthFromSelection()
            } label: {
                Label(
                    AppLocalization.text("settings.billing.reportingRange.reset"),
                    systemImage: "arrow.counterclockwise"
                )
            }
            .buttonStyle(.borderless)
            .foregroundStyle(palette.accent)
            .accessibilityIdentifier("billing.reportingRange.resetButton")
        }
    }

    private var headerSubtitle: String {
        if pendingStart != nil {
            return AppLocalization.text("settings.billing.reportingRange.summaryDetail.customUnset")
        }

        if let start = committedSelectionStart, let end = committedSelectionEnd {
            return AppLocalization.format(
                "settings.billing.reportingRange.summary.customValid",
                start.formatted(date: .abbreviated, time: .omitted),
                end.formatted(date: .abbreviated, time: .omitted)
            )
        }

        return AppLocalization.text("settings.billing.reportingRange.summary.customUnset")
    }

    private var footerTitle: String {
        if let pendingStart {
            return "\(AppLocalization.text("settings.billing.reportingRange.start")) \(pendingStart.formatted(date: .abbreviated, time: .omitted))"
        }

        if let start = committedSelectionStart, let end = committedSelectionEnd {
            return AppLocalization.format(
                "settings.billing.reportingRange.summary.customValid",
                start.formatted(date: .abbreviated, time: .omitted),
                end.formatted(date: .abbreviated, time: .omitted)
            )
        }

        return AppLocalization.text("settings.billing.reportingRange.summary.customUnset")
    }

    private var footerDetail: String {
        if pendingStart != nil {
            return AppLocalization.text("settings.billing.reportingRange.summaryDetail.customUnset")
        }

        if committedSelectionStart != nil, committedSelectionEnd != nil {
            return AppLocalization.text("settings.billing.reportingRange.summaryDetail.customValid")
        }

        return AppLocalization.text("settings.billing.reportingRange.summaryDetail.customUnset")
    }

    private var visibleMonthStart: Date {
        calendar.dateInterval(of: .month, for: visibleMonth)?.start ?? calendar.startOfDay(for: visibleMonth)
    }

    private var monthTitle: String {
        visibleMonthStart.formatted(.dateTime.month(.wide).year())
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return [] }
        let offset = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    private var monthCells: [MonthCell] {
        let start = gridStartDate()
        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return MonthCell(date: date, isInDisplayedMonth: calendar.isDate(date, equalTo: visibleMonthStart, toGranularity: .month))
        }
    }

    private var committedSelectionStart: Date? {
        appPreferencesModel.preferences.reportingRangeCustomBounds.start
    }

    private var committedSelectionEnd: Date? {
        appPreferencesModel.preferences.reportingRangeCustomBounds.end
    }

    private func ensureUsableBoundsIfNeeded() {
        guard appPreferencesModel.preferences.reportingRangeMode == .custom else { return }
        guard !committedBoundsAreUsable else {
            return
        }
        appPreferencesModel.resetReportingRangeCustomBounds()
    }

    private var committedBoundsAreUsable: Bool {
        guard let start = committedSelectionStart, let end = committedSelectionEnd else { return false }
        return start <= end
    }

    private func syncVisibleMonthFromSelection() {
        let referenceDate = committedSelectionStart ?? Date()
        visibleMonth = calendar.dateInterval(of: .month, for: referenceDate)?.start ?? calendar.startOfDay(for: referenceDate)
    }

    private func gridStartDate() -> Date {
        let monthStart = visibleMonthStart
        let weekday = calendar.component(.weekday, from: monthStart)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: monthStart) ?? monthStart
    }

    private func shiftVisibleMonth(by offset: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: offset, to: visibleMonthStart) else { return }
        visibleMonth = shifted
    }

    private func handleDateTap(_ date: Date) {
        let dayStart = calendar.startOfDay(for: date)
        if let pendingStart {
            appPreferencesModel.setReportingRangeCustomBounds(start: pendingStart, end: dayStart)
            self.pendingStart = nil
            return
        }

        pendingStart = dayStart
    }

    private func isSelectedStart(_ date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        if let pendingStart {
            return calendar.isDate(day, inSameDayAs: pendingStart)
        }

        guard let start = committedSelectionStart else { return false }
        return calendar.isDate(day, inSameDayAs: start)
    }

    private func isSelectedEnd(_ date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard pendingStart == nil, let end = committedSelectionEnd else { return false }
        return calendar.isDate(day, inSameDayAs: end)
    }

    private func isInCommittedRange(_ date: Date) -> Bool {
        guard pendingStart == nil,
              let start = committedSelectionStart,
              let end = committedSelectionEnd else { return false }

        let day = calendar.startOfDay(for: date)
        let lower = calendar.startOfDay(for: min(start, end))
        let upper = calendar.startOfDay(for: max(start, end))
        return day > lower && day < upper
    }

    private func calendarNavButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .settingsInsetSurface(in: RoundedRectangle(cornerRadius: 8, style: .continuous), palette: palette)
        .accessibilityLabel(Text(label))
    }
}

private struct MonthCell: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool

    var id: Date { date }
}

private struct CalendarDayCell: View {
    let date: Date
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let isSelectedStart: Bool
    let isSelectedEnd: Bool
    let isInCommittedRange: Bool
    let palette: TokenCostPalette

    var body: some View {
        let isSelected = isSelectedStart || isSelectedEnd
        let fill: Color = {
            if isSelected { return palette.accentSoft }
            if isInCommittedRange { return palette.accent.opacity(0.08) }
            return .clear
        }()
        let foreground: Color = {
            if isSelected { return palette.accent }
            return isInDisplayedMonth ? palette.title : palette.subtitle.opacity(0.72)
        }()

        Text(String(calendar.component(.day, from: date)))
            .font(.caption.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isToday ? palette.accentSecondary.opacity(isInDisplayedMonth ? 1 : 0.6) : (isSelected ? palette.accent : Color.clear), lineWidth: isToday || isSelected ? 1 : 0)
            )
            .opacity(isInDisplayedMonth ? 1 : 0.58)
            .accessibilityLabel(Text(date.formatted(date: .abbreviated, time: .omitted)))
    }

    private var calendar: Calendar {
        Calendar.autoupdatingCurrent
    }
}
