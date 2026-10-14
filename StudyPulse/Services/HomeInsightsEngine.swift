//
//  HomeInsightsEngine.swift
//  StudyPulse
//
//  主页图表所需的纯函数聚合:本周专注 / 各科快照 / 心情·睡眠·HRV 序列 / 周活动条。
//  不依赖 SwiftUI,便于单测;由 HomeViewModel.recompute() 调用。
//  Pure aggregations behind the Home charts: weekly focus, subject snapshots,
//  mood / sleep / HRV series and the week activity strip. No SwiftUI dependency.
//

import Foundation

// MARK: - Value types

/// 某一天某强度的专注分钟数(堆叠柱状图的一段)。
/// Minutes focused on a given day at a given intensity (one stacked-bar segment).
nonisolated struct FocusSegment: Identifiable, Equatable, Sendable {
    let date: Date
    let intensity: StudySession.SessionIntensity
    let minutes: Double
    var id: String { "\(date.timeIntervalSince1970)-\(intensity.rawValue)" }
}

/// 一天的专注总分钟数。
/// Total focus minutes for one day.
nonisolated struct DailyFocusPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let minutes: Double
    var id: Date { date }
}

/// 最近 N 天专注汇总(含上一个同长度周期的对比)。
/// Focus summary for the last N days, with the previous equal-length window for comparison.
nonisolated struct WeeklyFocusSummary: Equatable, Sendable {
    /// 升序、补齐空白日的每日总计 / Ascending daily totals with empty days filled in.
    let days: [DailyFocusPoint]
    /// 按强度拆分的堆叠段(只含 minutes > 0) / Stacked segments (minutes > 0 only).
    let segments: [FocusSegment]
    let totalMinutes: Double
    let previousTotalMinutes: Double

    static let empty = WeeklyFocusSummary(days: [], segments: [], totalMinutes: 0, previousTotalMinutes: 0)

    var deltaMinutes: Double { totalMinutes - previousTotalMinutes }
    /// 有任何专注记录(本期)/ Whether the current window has any focus time.
    var hasData: Bool { totalMinutes > 0 }
    var dailyAverageMinutes: Double {
        days.isEmpty ? 0 : totalMinutes / Double(days.count)
    }
}

/// 单科快照:平均得分率 + 最近若干次得分率序列 + 近期变化。
/// Per-subject snapshot: average score rate, recent rate series and recent delta.
nonisolated struct SubjectSnapshot: Identifiable, Equatable, Sendable {
    let subject: String
    /// 平均得分(原始分)/ Average raw score.
    let averageScore: Double
    /// 平均得分率 0...1 / Average score rate.
    let averageRate: Double
    let fullScore: Double
    let count: Int
    /// 最近 N 次得分率(%,升序)/ Recent score rates in percent, ascending.
    let recentRates: [Double]
    /// 最近一次 − 之前均值(百分点);不足 2 次为 nil / Latest minus prior mean (pp); nil under 2 grades.
    let deltaPoints: Double?
    var id: String { subject }
}

/// 一天一个值的序列点(心情 / 睡眠 / HRV 共用)。
/// One value per day (shared by mood / sleep / HRV).
nonisolated struct DailyValuePoint: Identifiable, Equatable, Sendable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// 一周活动条的一格。
/// One cell of the week activity strip.
nonisolated struct WeekStripDay: Identifiable, Equatable, Sendable {
    let date: Date
    let points: Int
    let isToday: Bool
    var id: Date { date }
}

/// 星期 × 时段 热力图的一格(用于习惯洞察)。
/// One weekday × time-slot heatmap cell (habit insight).
nonisolated struct WeekdaySlotCell: Identifiable, Equatable, Sendable {
    /// Calendar.weekday: 1 = Sunday … 7 = Saturday.
    let weekday: Int
    let slot: Int
    let sessionCount: Int
    let avgMinutes: Double
    var id: String { "\(weekday)-\(slot)" }
}

// MARK: - Engine

nonisolated enum HomeInsightsEngine {

    // MARK: Weekly focus

    /// 最近 `days` 天(含今天)的专注分钟,按强度堆叠,并与前一个同长度周期比较。
    /// 只统计 `completed` 且时长 > 0 的会话。
    /// Focus minutes for the last `days` days (today included), stacked by intensity, compared with
    /// the previous equal-length window. Only completed sessions with a positive duration count.
    static func weeklyFocus(
        sessions: [StudySession],
        now: Date = Date(),
        days: Int = 7,
        calendar: Calendar = .current
    ) -> WeeklyFocusSummary {
        guard days > 0 else { return .empty }
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let previousStart = calendar.date(byAdding: .day, value: -days, to: windowStart) else {
            return .empty
        }

        var perDayIntensity: [Date: [StudySession.SessionIntensity: Double]] = [:]
        var previousTotal = 0.0
        for session in sessions where session.completed && session.durationSeconds > 0 {
            let day = calendar.startOfDay(for: session.startDate)
            let minutes = Double(session.durationSeconds) / 60.0
            if day >= windowStart && day <= today {
                perDayIntensity[day, default: [:]][session.intensity, default: 0] += minutes
            } else if day >= previousStart && day < windowStart {
                previousTotal += minutes
            }
        }

        var points: [DailyFocusPoint] = []
        var segments: [FocusSegment] = []
        var total = 0.0
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: windowStart) else { continue }
            let buckets = perDayIntensity[day] ?? [:]
            let dayTotal = buckets.values.reduce(0, +)
            total += dayTotal
            points.append(DailyFocusPoint(date: day, minutes: dayTotal))
            for intensity in StudySession.SessionIntensity.allCases {
                if let minutes = buckets[intensity], minutes > 0 {
                    segments.append(FocusSegment(date: day, intensity: intensity, minutes: minutes))
                }
            }
        }
        return WeeklyFocusSummary(days: points, segments: segments, totalMinutes: total, previousTotalMinutes: previousTotal)
    }

    // MARK: Subject snapshots

    /// 各科快照,按平均得分率升序(最需要关注的在前),最多 `limit` 科。
    /// Per-subject snapshots ordered by average rate ascending (weakest first), up to `limit`.
    /// - Parameter fullScoreProvider: 科目默认满分(成绩自带满分优先)/ default full score per subject.
    @MainActor
    static func subjectSnapshots(
        grades: [Grade],
        fullScoreProvider: (String) -> Double,
        recentCount: Int = 6,
        limit: Int = 5
    ) -> [SubjectSnapshot] {
        let aggregates = SubjectAggregator.aggregate(grades: grades, includeRecentCount: false)
        var snapshots: [SubjectSnapshot] = []
        for (subject, aggregate) in aggregates {
            let subjectFull = max(fullScoreProvider(subject), 1)
            let rates = aggregate.sortedAsc.map { $0.scoreRate(subjectFullScore: subjectFull) * 100 }
            guard !rates.isEmpty else { continue }
            let avgRate = rates.reduce(0, +) / Double(rates.count)
            var delta: Double?
            if rates.count >= 2, let latest = rates.last {
                let prior = rates.dropLast()
                delta = latest - prior.reduce(0, +) / Double(prior.count)
            }
            snapshots.append(SubjectSnapshot(
                subject: subject,
                averageScore: aggregate.average,
                averageRate: avgRate / 100,
                fullScore: subjectFull,
                count: aggregate.count,
                recentRates: Array(rates.suffix(recentCount)),
                deltaPoints: delta
            ))
        }
        snapshots.sort {
            if $0.averageRate != $1.averageRate { return $0.averageRate < $1.averageRate }
            return $0.subject < $1.subject
        }
        return Array(snapshots.prefix(limit))
    }

    // MARK: Daily series

    /// 最近 `days` 天的心情分(1...5);同一天多条取平均;无记录的日子不补点。
    /// Mood score (1...5) over the last `days` days; multiple entries on a day are averaged; gaps stay gaps.
    static func moodSeries(
        entries: [DiaryEntry],
        now: Date = Date(),
        days: Int = 14,
        calendar: Calendar = .current
    ) -> [DailyValuePoint] {
        guard let start = windowStart(now: now, days: days, calendar: calendar) else { return [] }
        var sums: [Date: (total: Double, count: Int)] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            guard day >= start else { continue }
            let current = sums[day] ?? (0, 0)
            sums[day] = (current.total + Double(entry.moodScore), current.count + 1)
        }
        return sums
            .map { DailyValuePoint(date: $0.key, value: $0.value.total / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
    }

    /// 最近 `days` 天的睡眠小时数(升序,忽略缺失 / 非正数)。
    /// Sleep hours over the last `days` days (ascending; missing / non-positive values dropped).
    static func sleepSeries(
        history: [DailyHealthSnapshot],
        now: Date = Date(),
        days: Int = 14,
        calendar: Calendar = .current
    ) -> [DailyValuePoint] {
        series(history: history, now: now, days: days, calendar: calendar) { $0.sleepHours }
    }

    /// 最近 `days` 天的 HRV(SDNN, ms)(升序)。
    /// HRV (SDNN, ms) over the last `days` days (ascending).
    static func hrvSeries(
        history: [DailyHealthSnapshot],
        now: Date = Date(),
        days: Int = 14,
        calendar: Calendar = .current
    ) -> [DailyValuePoint] {
        series(history: history, now: now, days: days, calendar: calendar) { $0.hrv }
    }

    private static func series(
        history: [DailyHealthSnapshot],
        now: Date,
        days: Int,
        calendar: Calendar,
        value: (DailyHealthSnapshot) -> Double?
    ) -> [DailyValuePoint] {
        guard let start = windowStart(now: now, days: days, calendar: calendar) else { return [] }
        var byDay: [Date: Double] = [:]
        for snapshot in history {
            let day = calendar.startOfDay(for: snapshot.date)
            guard day >= start, let v = value(snapshot), v > 0 else { continue }
            byDay[day] = v
        }
        return byDay
            .map { DailyValuePoint(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private static func windowStart(now: Date, days: Int, calendar: Calendar) -> Date? {
        guard days > 0 else { return nil }
        return calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))
    }

    // MARK: Week strip

    /// 以今天为终点的 7 天活动格(升序)。`logs` 用 `DailyActivityLog.totalActivityPoints`。
    /// Seven-day activity strip ending today (ascending), using `DailyActivityLog.totalActivityPoints`.
    static func weekStrip(
        logs: [DailyActivityLog],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WeekStripDay] {
        let today = calendar.startOfDay(for: now)
        var pointsByDay: [Date: Int] = [:]
        for log in logs {
            pointsByDay[calendar.startOfDay(for: log.date), default: 0] += log.totalActivityPoints
        }
        var result: [WeekStripDay] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            result.append(WeekStripDay(date: day, points: pointsByDay[day] ?? 0, isToday: offset == 0))
        }
        return result
    }

    // MARK: Weekday × slot

    /// 把 `WeekdayHourSlotBucket` 转为热力图格子(只含有会话的格子)。
    /// Convert `WeekdayHourSlotBucket`s into heatmap cells (cells with sessions only).
    static func weekdaySlotCells(buckets: [WeekdayHourSlotBucket]) -> [WeekdaySlotCell] {
        buckets.map {
            WeekdaySlotCell(
                weekday: $0.weekday,
                slot: $0.hourSlot.rawValue,
                sessionCount: $0.sessionCount,
                avgMinutes: $0.avgDurationMinutes
            )
        }
    }
}
