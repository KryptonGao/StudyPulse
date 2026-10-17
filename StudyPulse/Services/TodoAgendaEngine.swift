//
//  TodoAgendaEngine.swift
//  StudyPulse
//
//  待办页的纯函数聚合:按「日」分组的时间轴 / 本周周条 / 各类型计数 / 考试倒数。
//  Pure aggregation for the Todo page: a day-based agenda, the week strip,
//  per-type counts and exam countdown.
//

import Foundation

/// 时间轴上一组的类别 / Kind of an agenda group.
nonisolated enum AgendaDayKind: Hashable, Sendable {
    case today
    case tomorrow
    /// 未来 7 天内的具体某天 / A concrete day within the next week.
    case day
    /// 更远的合并组 / Everything beyond the next week.
    case later
}

nonisolated struct AgendaDay: Identifiable, Equatable, Sendable {
    /// 当天 0 点;`.later` 组用其第一项的日期 / Start of day; for `.later` the first entry's day.
    let date: Date
    let kind: AgendaDayKind
    let entries: [TodoEntry]

    var id: String { kind == .later ? "later" : "day-\(Int(date.timeIntervalSince1970))" }
    var completedCount: Int { entries.filter(\.isCompleted).count }
}

/// 周条上的一格 / One cell of the week strip.
nonisolated struct TodoWeekDay: Identifiable, Equatable, Sendable {
    let date: Date
    let isToday: Bool
    /// 当天条目类型(去重、最多 3 个,用于彩点)/ Distinct kinds that day (max 3, drives the dots).
    let kinds: [TodoEntryKind]
    let count: Int
    var id: Date { date }
}

nonisolated struct TodoTypeCounts: Equatable, Sendable {
    var all = 0
    var exam = 0
    var homework = 0
    var reading = 0
    var routine = 0
}

nonisolated enum TodoAgendaEngine {
    /// 距今多少天内逐日展示 / Days shown one-by-one before collapsing into "later".
    static let dayByDayHorizon = 7

    /// 把未完成 / 已完成的未来条目按日分组。过期(今天之前)的不在这里。
    /// Groups upcoming entries by day; past entries are excluded.
    static func agenda(
        entries: [TodoEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AgendaDay] {
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: dayByDayHorizon, to: today) else { return [] }

        var byDay: [Date: [TodoEntry]] = [:]
        var later: [TodoEntry] = []
        for entry in entries where entry.date >= today {
            let day = calendar.startOfDay(for: entry.date)
            if day <= horizon { byDay[day, default: []].append(entry) } else { later.append(entry) }
        }

        var result: [AgendaDay] = byDay.keys.sorted().map { day in
            let kind: AgendaDayKind
            if calendar.isDate(day, inSameDayAs: today) {
                kind = .today
            } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
                      calendar.isDate(day, inSameDayAs: tomorrow) {
                kind = .tomorrow
            } else {
                kind = .day
            }
            return AgendaDay(date: day, kind: kind, entries: (byDay[day] ?? []).sorted(by: sortByTime))
        }
        if !later.isEmpty {
            let sorted = later.sorted(by: sortByTime)
            result.append(AgendaDay(date: calendar.startOfDay(for: sorted[0].date), kind: .later, entries: sorted))
        }
        return result
    }

    /// 当日内:有具体时间的按时间,同刻按标题 / Within a day: by time, then title.
    private static func sortByTime(_ a: TodoEntry, _ b: TodoEntry) -> Bool {
        if a.date != b.date { return a.date < b.date }
        return a.title < b.title
    }

    /// 以周一为起点的本周 7 天 / The 7 days of the current week, Monday first.
    static func weekStrip(
        entries: [TodoEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TodoWeekDay] {
        var cal = calendar
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: today)          // 1 = Sunday
        let offsetFromMonday = (weekday + 5) % 7
        guard let monday = cal.date(byAdding: .day, value: -offsetFromMonday, to: today) else { return [] }

        var byDay: [Date: [TodoEntry]] = [:]
        for entry in entries where !entry.isCompleted {
            byDay[cal.startOfDay(for: entry.date), default: []].append(entry)
        }

        var days: [TodoWeekDay] = []
        for i in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: i, to: monday) else { continue }
            let items = byDay[day] ?? []
            var kinds: [TodoEntryKind] = []
            for item in items where !kinds.contains(item.kind) && kinds.count < 3 { kinds.append(item.kind) }
            days.append(TodoWeekDay(date: day, isToday: day == today, kinds: kinds, count: items.count))
        }
        return days
    }

    /// 各类型数量(未完成)/ Incomplete counts per type.
    static func counts(entries: [TodoEntry]) -> TodoTypeCounts {
        var c = TodoTypeCounts()
        for entry in entries where !entry.isCompleted {
            c.all += 1
            switch entry.kind {
            case .exam, .comprehensiveExam: c.exam += 1
            case .homework: c.homework += 1
            case .reading: c.reading += 1
            case .routine: c.routine += 1
            }
        }
        return c
    }

    /// 距考试天数(按日历日算,0 = 今天);已过为负 / Calendar days until the date; negative if past.
    static func daysUntil(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// 考前清单完成进度;无清单为 nil / Checklist progress; nil without a checklist.
    static func checklistProgress(_ exam: Exam) -> (done: Int, total: Int)? {
        guard !exam.checklist.isEmpty else { return nil }
        return (exam.checklist.filter(\.isChecked).count, exam.checklist.count)
    }
}
