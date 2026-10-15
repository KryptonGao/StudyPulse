//
//  DiaryCalendarDayCell.swift
//  StudyPulse
//
//  学习日记日历的单日 cell:
//  - 26pt 圆心数字(不会因垂直空间被压缩成 "...")
//  - 下方 13pt mood emoji(若有日记)
//  - isSelected 蓝色填充,isToday 蓝色描边
//
//  Per-day cell on the diary calendar:
//  - 26pt circular day number (never gets squeezed into "..." by vertical space).
//  - 13pt mood emoji below the number when an entry exists.
//  - Blue fill when selected; blue ring when today.
//

import SwiftUI

struct DiaryCalendarDayCell: View {
    let date: Date
    let inMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    /// 当日日记(若多条,取首条用于显示 emoji/mood 颜色)
    /// Entries on this day (uses the first to show emoji / mood color).
    let entry: DiaryEntry?

    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    /// mood 1-5 → 背景色调(有日记时,选中/未选中各一种)
    /// mood 1-5 → background color (different shade when selected).
    private var moodTint: Color {
        guard let entry else { return Color(.tertiarySystemFill).opacity(0.5) }
        return DiaryCalendarPalette.color(forMood: entry.moodScore)
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(moodTint)
                } else if entry != nil {
                    Circle()
                        .fill(moodTint.opacity(0.55))
                } else if isToday {
                    Circle()
                        .stroke(Color(.systemBlue), lineWidth: 1.5)
                }

                Text("\(dayNumber)")
                    .scaledFont(size: 14, weight: isToday ? .bold : .medium)
                    .foregroundColor(numberColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 26, height: 26)

            if let entry {
                Text(entry.moodEmoji)
                    .scaledFont(size: 13)
                    .lineLimit(1)
            } else {
                // 占位保证 cell 高度一致,避免选中/非选中抖动
                // Spacer keeps the cell height consistent.
                Color.clear.frame(height: 13)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(inMonth ? 1.0 : 0.32)
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if isToday { return Color(.systemBlue) }
        if entry != nil { return .white }
        return Color(.label)
    }
}

// MARK: - Preview

#Preview("Empty") {
    DiaryCalendarDayCell(
        date: Date(),
        inMonth: true,
        isSelected: false,
        isToday: false,
        entry: nil
    )
    .frame(width: 60, height: 60)
    .padding()
}

#Preview("With Entry") {
    let entry = DiaryEntry(date: Date(), moodScore: 4, energyScore: 3, energyTag: "专注", content: "")
    return DiaryCalendarDayCell(
        date: Date(),
        inMonth: true,
        isSelected: false,
        isToday: true,
        entry: entry
    )
    .frame(width: 60, height: 60)
    .padding()
}

#Preview("Selected") {
    let entry = DiaryEntry(date: Date(), moodScore: 5, energyScore: 4, energyTag: "平静", content: "")
    return DiaryCalendarDayCell(
        date: Date(),
        inMonth: true,
        isSelected: true,
        isToday: false,
        entry: entry
    )
    .frame(width: 60, height: 60)
    .padding()
}
