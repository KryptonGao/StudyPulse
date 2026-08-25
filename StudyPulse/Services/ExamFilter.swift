//
//  ExamFilter.swift
//  StudyPulse
//
//  考试列表/分桶相关的纯函数。
// 抽取自 ExamView.allExamsSorted / upcomingExams / pastExams / groupedExams
// 以及 TodoView.recomputeEntries 的 upcomingEntries 分桶逻辑。
//
//  Created for MVVM refactor (2026-07-05).
//

import Foundation

/// 考试分桶后的一段(时间窗口 + 窗口内所有考试项)
/// One bucket in a bucketed exam list (a time window + its exams).
struct ExamBucket {
    /// 区间标题(本地化)
    /// Bucket title (localized).
    let title: String
    /// 区间内的考试项
    /// Exams inside the bucket.
    let items: [ExamItem]
}

/// 用于跨视图复用的"考试项"统一类型。
/// 既能装单科 Exam 也能装综合 comprehensiveExam。
/// Unified "exam item" used across views. Wraps either a single-subject
/// `Exam` or a `comprehensiveExam`.
enum ExamItem: Hashable {
    case single(Exam)
    case comprehensive(comprehensiveExam)

    var date: Date {
        switch self {
        case .single(let e): return e.examDate
        case .comprehensive(let e): return e.examDate
        }
    }

    var id: UUID {
        switch self {
        case .single(let e): return e.id
        case .comprehensive(let e): return e.id
        }
    }
}

/// 考试筛选/分桶服务。纯函数。
/// Exam filter / bucketing. Pure functions.
enum ExamFilter {

    // MARK: - 合并排序
    // MARK: - 合并排序 / Merge and sort

    /// 把单科和综合考试合并,按 examDate 升序。
    /// Merge single + comprehensive exams, sorted by `examDate` asc.
    static func mergeAndSort(
        single: [Exam],
        comprehensive: [comprehensiveExam]
    ) -> [ExamItem] {
        var items: [ExamItem] = []
        items.reserveCapacity(single.count + comprehensive.count)
        items.append(contentsOf: single.map(ExamItem.single))
        items.append(contentsOf: comprehensive.map(ExamItem.comprehensive))
        return items.sorted { $0.date < $1.date }
    }

    // MARK: - past / upcoming 拆分
    // MARK: - past / upcoming 拆分 / Past vs upcoming

    /// 已过期考试(日期 < 今天 0 点)
    /// Past exams (date < today's start-of-day).
    static func pastItems(from items: [ExamItem], now: Date = Date()) -> [ExamItem] {
        let todayStart = Calendar.current.startOfDay(for: now)
        return items.filter { $0.date < todayStart }
    }

    /// 即将到来(日期 >= 今天 0 点)
    /// Upcoming exams (date >= today's start-of-day).
    static func upcomingItems(from items: [ExamItem], now: Date = Date()) -> [ExamItem] {
        let todayStart = Calendar.current.startOfDay(for: now)
        return items.filter { $0.date >= todayStart }
    }

    // MARK: - 未来考试按时间窗口分桶(Week / Month / Later)
    // MARK: - 未来考试按时间窗口分桶(Week / Month / Later) / Bucket upcoming by window

    /// 未来考试按 "1 Week / 1 Month / Later" 分桶。
    /// Bucket upcoming exams into "Within 1 Week / Within 1 Month / Later".
    /// - Returns: 非空桶的列表,顺序: Week → Month → Later
    ///   List of non-empty buckets, in order: Week → Month → Later.
    static func bucketUpcomingItems(
        from items: [ExamItem],
        now: Date = Date()
    ) -> [ExamBucket] {
        let upcoming = upcomingItems(from: items, now: now)
        guard let oneWeekLater = Calendar.current.date(byAdding: .day, value: 7, to: now),
              let oneMonthLater = Calendar.current.date(byAdding: .month, value: 1, to: now) else {
            return []
        }
        var week: [ExamItem] = []
        var month: [ExamItem] = []
        var later: [ExamItem] = []
        week.reserveCapacity(upcoming.count)
        for item in upcoming {
            if item.date <= oneWeekLater {
                week.append(item)
            } else if item.date <= oneMonthLater {
                month.append(item)
            } else {
                later.append(item)
            }
        }
        var result: [ExamBucket] = []
        if !week.isEmpty { result.append(ExamBucket(title: "Within 1 Week".localized(), items: week)) }
        if !month.isEmpty { result.append(ExamBucket(title: "Within 1 Month".localized(), items: month)) }
        if !later.isEmpty { result.append(ExamBucket(title: "Later".localized(), items: later)) }
        return result
    }

    // MARK: - N 天内 / 已过 N 天 但未登记
    // MARK: - N 天内 / 已过 N 天 但未登记 / Within N days / past N days unregistered

    /// 未来 N 天内的考试(14 = 14 天,0 = 全部未来)
    /// Exams within the next `days` days (0 = all upcoming).
    static func examsWithinDays(
        _ days: Int,
        exams: [Exam],
        now: Date = Date()
    ) -> [Exam] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: days, to: now) else {
            return []
        }
        return exams
            .filter { $0.examDate > now && $0.examDate <= cutoff }
            .sorted { $0.examDate < $1.examDate }
    }

    /// 已过 startDays ~ endDays 之间、但未在 grades 中登记的考试。
    /// Past exams in the [`endDaysAgo`, `startDaysAgo`] window that have no
    /// matching grade in `grades` yet.
    /// - Parameters:
    ///   - startDaysAgo: 时间窗口起点(负数,例如 -3 = 3 天前)
    ///     Window start (negative; e.g. -3 = 3 days ago).
    ///   - endDaysAgo: 时间窗口终点(负数,例如 -7 = 7 天前)
    ///     Window end (negative; e.g. -7 = 7 days ago).
    ///   - grades: 已登记成绩
    ///     Already-recorded grades.
    ///   - exams: 待查的考试列表
    ///     Candidate exams to scan.
    static func unregisteredExams(
        startDaysAgo: Int,
        endDaysAgo: Int,
        grades: [Grade],
        exams: [Exam],
        now: Date = Date()
    ) -> [Exam] {
        let startOfToday = Calendar.current.startOfDay(for: now)
        guard let windowStart = Calendar.current.date(byAdding: .day, value: startDaysAgo, to: startOfToday),
              let windowEnd = Calendar.current.date(byAdding: .day, value: endDaysAgo, to: startOfToday) else {
            return []
        }
        // 预建 key 集合(subject+examName+dayBucket)
        var registeredKeys = Set<String>()
        registeredKeys.reserveCapacity(grades.count)
        for g in grades {
            let dayBucket = dayBucketKey(for: g.date)
            registeredKeys.insert("\(g.subject)|\(g.examName)|\(dayBucket)")
        }
        return exams.filter { exam in
            guard exam.examDate < windowStart && exam.examDate >= windowEnd else { return false }
            let dayBucket = dayBucketKey(for: exam.examDate)
            return !registeredKeys.contains("\(exam.subject)|\(exam.examName)|\(dayBucket)")
        }.sorted { $0.examDate < $1.examDate }
    }

    /// 用 `Calendar.startOfDay` 归一化为"日桶"标识。
    /// Normalize a date to its calendar-day bucket so DST days aren't split
    /// across two fixed-86400s buckets (a DST day is 23h/25h).
    private static func dayBucketKey(for date: Date) -> String {
        let start = Calendar.current.startOfDay(for: date)
        return String(Int(start.timeIntervalSince1970))
    }
}
