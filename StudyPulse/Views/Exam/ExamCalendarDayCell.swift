//
//  ExamCalendarDayCell.swift
//  StudyPulse
//
//  考试日历的单日 cell:支持单日 dots / 多日 span bar / 今日高亮 / 选中态。
//  Per-day cell: single-day dots / multi-day span bar / today highlight / selected state.
//
//  Phase 3 拆分 (2026-07-14):原 `ExamCalendarView.swift` 抽出,可独立预览。
//

import SwiftUI

/// 月历的单个日期 cell。
/// Single-day cell on the month calendar.
struct ExamCalendarDayCell: View {
    let date: Date
    let inMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let items: [CalendarItem]

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle().fill(Color(.systemBlue))
                } else if isToday {
                    Circle()
                        .stroke(Color(.systemBlue), lineWidth: 1.5)
                }
                Text(Calendar.current.component(.day, from: date), format: .number)
                    .scaledFont(size: 14, weight: isToday ? .bold : .medium)
                    .foregroundColor(numberColor)
            }
            .frame(width: 26, height: 26)
            dotsRow
        }
        .frame(maxWidth: .infinity)
        .opacity(inMonth ? 1.0 : 0.32)
    }

    // MARK: - Dots Row / 事件指示行

    @ViewBuilder
    private var dotsRow: some View {
        ZStack {
            if let span = multiDaySpanInfo {
                GeometryReader { proxy in
                    spanBar(width: proxy.size.width, color: span.color,
                            isStart: span.isStart, isEnd: span.isEnd)
                }
                .frame(height: 6)
            }
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { idx in
                    Circle()
                        .fill(dotColor(at: idx))
                        .frame(width: 4, height: 4)
                        .opacity(idx < singleDayDotCount ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: 8)
    }

    @ViewBuilder
    private func spanBar(width: CGFloat, color: Color, isStart: Bool, isEnd: Bool) -> some View {
        let height: CGFloat = 6
        let radius = height / 2
        UnevenRoundedRectangle(cornerRadii: cornerRadii(radius: radius, isStart: isStart, isEnd: isEnd))
            .fill(color.opacity(0.22))
            .frame(width: width, height: height)
    }

    private func cornerRadii(radius: CGFloat, isStart: Bool, isEnd: Bool) -> RectangleCornerRadii {
        if isStart {
            return .init(topLeading: radius, bottomLeading: radius, bottomTrailing: 0, topTrailing: 0)
        } else if isEnd {
            return .init(topLeading: 0, bottomLeading: 0, bottomTrailing: radius, topTrailing: radius)
        }
        return .init(topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0)
    }

    private var singleDayDotCount: Int {
        let allSorted = sortedItemsForDisplay
        if allSorted.isEmpty { return 0 }
        return min(3, allSorted.count)
    }

    private var sortedItemsForDisplay: [CalendarItem] {
        // 优先级:综合考试 > 单科考试 > 作业 > 阅读
        // Priority: comprehensive exam > single-subject exam > homework > reading.
        items.sorted { lhs, rhs in
            if lhs.kind.sortPriority != rhs.kind.sortPriority {
                return lhs.kind.sortPriority < rhs.kind.sortPriority
            }
            return lhs.importance > rhs.importance
        }
    }

    private func dotColor(at index: Int) -> Color {
        let sorted = sortedItemsForDisplay
        guard index < sorted.count else { return .clear }
        return sorted[index].accentColor
    }

    /// 跨日事件 span 信息(只有 multi-day 考试会触发)。
    /// Span info for multi-day items (only multi-day exams).
    private var multiDaySpanInfo: (color: Color, isStart: Bool, isEnd: Bool)? {
        for item in items where item.isMultiDay {
            let isStart = Calendar.current.isDate(date, inSameDayAs: item.start)
            let isEnd = Calendar.current.isDate(date, inSameDayAs: item.end)
            if isStart || isEnd {
                return (item.accentColor, isStart, isEnd)
            }
            if item.start < date && date < item.end {
                return (item.accentColor, false, false)
            }
        }
        return nil
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if isToday { return Color(.systemBlue) }
        if Calendar.current.isDateInWeekend(date) { return Color(.systemRed).opacity(0.85) }
        return Color(.label)
    }
}

// MARK: - Preview / 独立预览入口

#Preview("Empty") {
    ExamCalendarDayCell(
        date: Date(),
        inMonth: true,
        isSelected: false,
        isToday: false,
        items: []
    )
    .frame(width: 60, height: 60)
    .padding()
}

#Preview("Selected") {
    ExamCalendarDayCell(
        date: Date(),
        inMonth: true,
        isSelected: true,
        isToday: false,
        items: []
    )
    .frame(width: 60, height: 60)
    .padding()
}

#Preview("Today") {
    ExamCalendarDayCell(
        date: Date(),
        inMonth: true,
        isSelected: false,
        isToday: true,
        items: []
    )
    .frame(width: 60, height: 60)
    .padding()
}

#Preview("With Items") {
    let cal = Calendar.current
    let start = cal.startOfDay(for: Date())
    let items: [CalendarItem] = [
        CalendarItem(
            id: UUID(), kind: .exam, title: "Math Midterm",
            subject: "Mathematics", importance: 5, isCompleted: false,
            start: start, end: start, isMultiDay: false,
            exam: nil, comprehensiveExam: nil, taskItem: nil
        ),
        CalendarItem(
            id: UUID(), kind: .homework, title: "Read Ch.3",
            subject: "Physics", importance: 3, isCompleted: false,
            start: start, end: start, isMultiDay: false,
            exam: nil, comprehensiveExam: nil, taskItem: nil
        )
    ]
    return ExamCalendarDayCell(
        date: Date(),
        inMonth: true,
        isSelected: false,
        isToday: true,
        items: items
    )
    .frame(width: 60, height: 60)
    .padding()
}
