//
//  WeekdaySlotHeatmap.swift
//  StudyPulse
//
//  星期 × 时段 热力图(7 列 × 5 行):颜色深浅 = 该格 90 天累计专注分钟。
//  Weekday × time-slot heatmap (7 columns × 5 rows): shade = total focus minutes over 90 days.
//

import SwiftUI

struct WeekdaySlotHeatmap: View {
    let cells: [WeekdaySlotCell]
    var tint: Color = .accentColor

    /// 周一起始的 Calendar.weekday 顺序 / Monday-first `Calendar.weekday` order.
    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    private var totals: [String: Double] {
        var dict: [String: Double] = [:]
        for cell in cells {
            dict[cell.id] = Double(cell.sessionCount) * cell.avgMinutes
        }
        return dict
    }

    var body: some View {
        let totals = totals
        let maxTotal = max(totals.values.max() ?? 0, 1)
        let symbols = Calendar.current.veryShortWeekdaySymbols
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Color.clear.frame(width: 44, height: 1)
                ForEach(Self.weekdayOrder, id: \.self) { weekday in
                    Text(symbols[weekday - 1])
                        .scaledFont(size: 10, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(HabitInsight.HourSlot.allCases, id: \.self) { slot in
                HStack(spacing: 4) {
                    Text(slot.displayName.localized())
                        .scaledFont(size: 10)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 44, alignment: .leading)
                    ForEach(Self.weekdayOrder, id: \.self) { weekday in
                        let value = totals["\(weekday)-\(slot.rawValue)"] ?? 0
                        RoundedRectangle(cornerRadius: 4)
                            .fill(value <= 0 ? Color(.tertiarySystemFill) : tint.opacity(0.2 + 0.8 * value / maxTotal))
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                    }
                }
            }
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Text("home.habit.less".localized())
                    .scaledFont(size: 10).foregroundStyle(.secondary)
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { ratio in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ratio == 0 ? Color(.tertiarySystemFill) : tint.opacity(0.2 + 0.8 * ratio))
                        .frame(width: 10, height: 10)
                }
                Text("home.habit.more".localized())
                    .scaledFont(size: 10).foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("WeekdaySlotHeatmap") {
    WeekdaySlotHeatmap(cells: [
        WeekdaySlotCell(weekday: 2, slot: 0, sessionCount: 6, avgMinutes: 40),
        WeekdaySlotCell(weekday: 4, slot: 3, sessionCount: 9, avgMinutes: 35),
        WeekdaySlotCell(weekday: 7, slot: 2, sessionCount: 3, avgMinutes: 50)
    ], tint: .blue)
    .padding()
}
