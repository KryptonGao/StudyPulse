//
//  ExamCalendarItemRow.swift
//  StudyPulse
//
//  选中日后底部面板的单个事件行:类型条 + 标题 + 学科 + 重要度星。
//  Single event row inside the selected-day bottom panel: kind bar + title + subject + importance stars.
//
//  Phase 3 拆分 (2026-07-14):原 `ExamCalendarView.swift` 抽出,可独立预览。
//

import SwiftUI

/// 选中日底部面板的单个事件行 / Single event row in the selected-day panel.
struct ExamCalendarItemRow: View {
    let item: CalendarItem
    /// 用于计算多日 label 的"第 N/N 天"的参考日期(通常 = 选中日)
    /// Reference date for the multi-day "Day N/M" label (typically = selected day).
    let referenceDate: Date

    var body: some View {
        HStack(spacing: 10) {
            // 类型条(4pt 宽)/ Type bar (4pt wide).
            RoundedRectangle(cornerRadius: 3)
                .fill(item.accentColor)
                .frame(width: 4, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: item.kind.systemImage)
                        .font(.caption2)
                        .foregroundColor(item.accentColor)
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Color(.label))
                        .lineLimit(1)
                    if !item.isSingleDay {
                        Text(multiDayLabel)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(item.accentColor.opacity(0.15))
                            )
                            .foregroundColor(item.accentColor)
                    }
                }
                Text(item.subject)
                    .font(.caption)
                    .foregroundColor(Color(.secondaryLabel))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                ForEach(0..<item.importance, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .scaledFont(size: 6)
                        .foregroundColor(.yellow)
                }
                if item.importance < 5 {
                    ForEach(0..<(5 - item.importance), id: \.self) { _ in
                        Image(systemName: "star")
                            .scaledFont(size: 6)
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background {
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.tertiarySystemGroupedBackground))
            }
        }
    }

    /// 多日事件的"Day N/M" 标签
    /// Multi-day "Day N/M" label.
    private var multiDayLabel: String {
        if item.isSingleDay { return "" }
        let calendar = Calendar.current
        let totalDays = (calendar.dateComponents([.day], from: item.start, to: item.end).day ?? 0) + 1
        let dayIndex = (calendar.dateComponents([.day], from: item.start, to: referenceDate).day ?? 0) + 1
        let clamped = min(max(dayIndex, 1), totalDays)
        let template = "Day %d/%d".localized()
        return String(format: template, clamped, totalDays)
    }
}

// MARK: - Preview / 独立预览入口

#Preview("Single-day") {
    let cal = Calendar.current
    let start = cal.startOfDay(for: Date())
    return VStack(spacing: 12) {
        ExamCalendarItemRow(
            item: CalendarItem(
                id: UUID(), kind: .exam, title: "Math Midterm",
                subject: "Mathematics", importance: 5, isCompleted: false,
                start: start, end: start, isMultiDay: false,
                exam: nil, comprehensiveExam: nil, taskItem: nil
            ),
            referenceDate: start
        )
        ExamCalendarItemRow(
            item: CalendarItem(
                id: UUID(), kind: .homework, title: "Ch.3 Exercises 1-20",
                subject: "Mathematics", importance: 3, isCompleted: false,
                start: start, end: start, isMultiDay: false,
                exam: nil, comprehensiveExam: nil, taskItem: nil
            ),
            referenceDate: start
        )
        ExamCalendarItemRow(
            item: CalendarItem(
                id: UUID(), kind: .reading, title: "Read Physics Ch.5",
                subject: "Physics", importance: 2, isCompleted: false,
                start: start, end: start, isMultiDay: false,
                exam: nil, comprehensiveExam: nil, taskItem: nil
            ),
            referenceDate: start
        )
    }
    .padding()
}

#Preview("Multi-day") {
    let cal = Calendar.current
    let start = cal.startOfDay(for: Date())
    let end = cal.date(byAdding: .day, value: 2, to: start)!
    return VStack(spacing: 12) {
        ExamCalendarItemRow(
            item: CalendarItem(
                id: UUID(), kind: .comprehensiveExam, title: "Midterm Week",
                subject: "Mathematics + Physics + Chemistry",
                importance: 5, isCompleted: false,
                start: start, end: end, isMultiDay: true,
                exam: nil, comprehensiveExam: nil, taskItem: nil
            ),
            referenceDate: start
        )
        ExamCalendarItemRow(
            item: CalendarItem(
                id: UUID(), kind: .comprehensiveExam, title: "Midterm Week",
                subject: "Mathematics + Physics + Chemistry",
                importance: 5, isCompleted: false,
                start: start, end: end, isMultiDay: true,
                exam: nil, comprehensiveExam: nil, taskItem: nil
            ),
            referenceDate: cal.date(byAdding: .day, value: 1, to: start)!
        )
    }
    .padding()
}
