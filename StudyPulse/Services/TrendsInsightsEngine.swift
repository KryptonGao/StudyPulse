//
//  TrendsInsightsEngine.swift
//  StudyPulse
//
//  趋势页的纯函数聚合:整体走势 / 科目行(迷你走势 + 变化)/ 需要关注的原因。
//  Pure-function aggregation for the Trends page: overall trend, per-subject rows
//  (sparkline + delta) and the reason a subject needs attention.
//

import Foundation

/// 总览走势的时间范围 / Time range of the overall trend.
nonisolated enum TrendsRange: String, CaseIterable, Identifiable, Sendable {
    case days30
    case days90
    case year
    case all

    var id: String { rawValue }

    /// 回溯天数;`nil` 表示不限 / Look-back days; `nil` means unbounded.
    var days: Int? {
        switch self {
        case .days30: return 30
        case .days90: return 90
        case .year: return 365
        case .all: return nil
        }
    }
}

/// 总览走势的一个点(某天的平均得分率,0~100)。
/// One point of the overall trend (mean score rate of a day, 0–100).
nonisolated struct OverallTrendPoint: Identifiable, Hashable, Sendable {
    let date: Date
    let value: Double
    var id: Date { date }
}

nonisolated struct OverallTrend: Sendable, Equatable {
    var points: [OverallTrendPoint]
    /// 窗口内平均得分率(0~100);无数据为 nil / Mean rate in window; nil when empty.
    var average: Double?
    /// 与上一个等长窗口相比的变化;缺少对比为 nil / Delta vs previous window of equal length.
    var delta: Double?
    var gradeCount: Int
    var subjectCount: Int
    /// 阶段目标折算的得分率 / Phase goals converted to a score rate.
    var targetRate: Double?

    static let empty = OverallTrend(points: [], average: nil, delta: nil, gradeCount: 0, subjectCount: 0, targetRate: nil)
}

nonisolated struct SubjectTrendRow: Identifiable, Hashable, Sendable {
    let subject: String
    let average: Double
    /// 最近一次得分 / Latest score.
    let latest: Double
    let latestExamName: String
    let latestDate: Date
    /// 最近 6 次得分(升序)/ Last six scores (ascending).
    let spark: [Double]
    /// 最近 3 次均分 − 之前 3 次均分;不足两次为 0 / Recent-3 mean minus previous-3 mean.
    let delta: Double
    var id: String { subject }
}

/// 需要关注的原因 / Why a subject needs attention.
nonisolated struct AttentionInsight: Identifiable, Hashable, Sendable {
    let subject: String
    let average: Double
    let delta: Double
    /// 末尾连续下滑的次数 / Trailing consecutive declines.
    let consecutiveDeclines: Int
    /// 距目标分的差距(目标 − 均分),无目标为 nil / Gap to target.
    let gapToTarget: Double?
    let dueMistakes: Int
    /// 最近的考试距今天数 / Days until the nearest exam of this subject.
    let nextExamInDays: Int?
    var id: String { subject }
}

nonisolated enum TrendsInsightsEngine {

    // MARK: - Overall

    static func overall(
        grades: [Grade],
        fullScores: [String: Double],
        range: TrendsRange,
        targets: [PhaseGoal] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> OverallTrend {
        func rate(_ g: Grade) -> Double {
            g.scoreRate(subjectFullScore: fullScores[g.subject] ?? 100) * 100
        }

        let windowStart: Date? = range.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: now) }
        let inWindow = grades.filter { windowStart == nil || $0.date >= windowStart! }.sorted { $0.date < $1.date }
        guard !inWindow.isEmpty else { return .empty }

        var byDay: [Date: [Double]] = [:]
        for g in inWindow { byDay[calendar.startOfDay(for: g.date), default: []].append(rate(g)) }
        let points = byDay.keys.sorted().map { day -> OverallTrendPoint in
            let values = byDay[day] ?? []
            return OverallTrendPoint(date: day, value: values.reduce(0, +) / Double(values.count))
        }

        let rates = inWindow.map(rate)
        let average = rates.reduce(0, +) / Double(rates.count)

        var delta: Double?
        if let days = range.days, let start = windowStart,
           let prevStart = calendar.date(byAdding: .day, value: -days, to: start) {
            let prev = grades.filter { $0.date >= prevStart && $0.date < start }.map(rate)
            if !prev.isEmpty { delta = average - prev.reduce(0, +) / Double(prev.count) }
        }

        let goalRates = targets.compactMap { goal -> Double? in
            guard goal.targetScore > 0 else { return nil }
            let full = fullScores[goal.subject] ?? 100
            return full > 0 ? goal.targetScore / full * 100 : nil
        }
        let targetRate = goalRates.isEmpty ? nil : goalRates.reduce(0, +) / Double(goalRates.count)

        return OverallTrend(
            points: points,
            average: average,
            delta: delta,
            gradeCount: inWindow.count,
            subjectCount: Set(inWindow.map(\.subject)).count,
            targetRate: targetRate
        )
    }

    /// 排名走势:每天平均名次(越小越好);`delta` 为 窗口均名次 − 上一窗口均名次(负为进步)。
    /// Rank trend: mean rank per day (lower is better); `delta` negative means improving.
    static func rank(
        grades: [Grade],
        range: TrendsRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> OverallTrend {
        let ranked = grades.filter { ($0.ranking ?? 0) > 0 }
        let start: Date? = range.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: now) }
        let inWindow = ranked.filter { start == nil || $0.date >= start! }.sorted { $0.date < $1.date }
        guard !inWindow.isEmpty else { return .empty }

        var byDay: [Date: [Double]] = [:]
        for g in inWindow { byDay[calendar.startOfDay(for: g.date), default: []].append(Double(g.ranking ?? 0)) }
        let points = byDay.keys.sorted().map { day -> OverallTrendPoint in
            let values = byDay[day] ?? []
            return OverallTrendPoint(date: day, value: values.reduce(0, +) / Double(values.count))
        }
        let ranks = inWindow.map { Double($0.ranking ?? 0) }
        let average = ranks.reduce(0, +) / Double(ranks.count)

        var delta: Double?
        if let days = range.days, let start, let prevStart = calendar.date(byAdding: .day, value: -days, to: start) {
            let prev = ranked.filter { $0.date >= prevStart && $0.date < start }.map { Double($0.ranking ?? 0) }
            if !prev.isEmpty { delta = average - prev.reduce(0, +) / Double(prev.count) }
        }
        return OverallTrend(
            points: points, average: average, delta: delta,
            gradeCount: inWindow.count, subjectCount: Set(inWindow.map(\.subject)).count, targetRate: nil
        )
    }

    // MARK: - Subject rows

    static func subjectRows(gradesBySubject: [String: [Grade]]) -> [SubjectTrendRow] {
        var rows: [SubjectTrendRow] = []
        for (subject, raw) in gradesBySubject {
            let grades = raw.sorted { $0.date < $1.date }
            guard let last = grades.last else { continue }
            let scores = grades.map(\.score)
            rows.append(SubjectTrendRow(
                subject: subject,
                average: scores.reduce(0, +) / Double(scores.count),
                latest: last.score,
                latestExamName: last.examName,
                latestDate: last.date,
                spark: Array(scores.suffix(6)),
                delta: recentDelta(scores)
            ))
        }
        // 退步最多的排最前;同变化按名称稳定排序
        return rows.sorted { $0.delta != $1.delta ? $0.delta < $1.delta : $0.subject < $1.subject }
    }

    /// 最近 3 次均分 − 其前 3 次均分 / Mean of last 3 minus mean of the 3 before them.
    static func recentDelta(_ scores: [Double]) -> Double {
        guard scores.count >= 2 else { return 0 }
        let recent = Array(scores.suffix(3))
        let before = Array(scores.dropLast(recent.count).suffix(3))
        guard !before.isEmpty else {
            return (scores[scores.count - 1]) - (scores[scores.count - 2])
        }
        return recent.reduce(0, +) / Double(recent.count) - before.reduce(0, +) / Double(before.count)
    }

    // MARK: - Attention

    static func attention(
        subject: String,
        grades: [Grade],
        target: Double?,
        dueMistakes: Int,
        nextExamInDays: Int?
    ) -> AttentionInsight {
        let scores = grades.sorted { $0.date < $1.date }.map(\.score)
        var declines = 0
        var i = scores.count - 1
        while i > 0, scores[i] < scores[i - 1] { declines += 1; i -= 1 }
        let average = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        return AttentionInsight(
            subject: subject,
            average: average,
            delta: recentDelta(scores),
            consecutiveDeclines: declines,
            gapToTarget: target.map { $0 - average },
            dueMistakes: dueMistakes,
            nextExamInDays: nextExamInDays
        )
    }
}
