//
//  SuggestionEngine.swift
//  StudyPulse
//
//  从 grades / mistakes / exams / 身体状态 派生学习建议的纯函数服务。
// 抽取自原 HomeView.StudySuggestionsCard.generateSuggestions() 及其 7 个 find* 方法。
//
//  Created for MVVM refactor (2026-07-05).
//

import Foundation
import SwiftUI

/// 学习建议生成上下文。所有输入由调用方提供,engine 自身不做 IO / 不依赖环境。
/// `StudySuggestion` generation context. All inputs are supplied by the
/// caller; the engine does no I/O and has no environment dependencies.
struct StudySuggestionsContext {
    let grades: [Grade]
    let mistakeSets: [MistakeNote]
    let examSets: [Exam]
    let profile: UserProfile
    /// 身体状态驱动的建议(由 `StudyReadinessAlgorithm.recommend(...)` 产出)
    /// Body-driven suggestion (produced by `StudyReadinessAlgorithm.recommend(...)`).
    let bodyStatusSuggestion: StudySuggestion?
    /// 当前日期(便于测试固定时间)
    /// Current date (injectable for tests).
    let now: Date
    /// "未来 N 天内即将考试"窗口,默认 14
    /// "Upcoming exams in next N days" window (default 14).
    let upcomingWindowDays: Int
    /// "今天或明天有考试"窗口,默认 1
    /// "Exam today/tomorrow" window (default 1).
    let urgentWindowDays: Int

    init(
        grades: [Grade],
        mistakeSets: [MistakeNote],
        examSets: [Exam],
        profile: UserProfile,
        bodyStatusSuggestion: StudySuggestion?,
        now: Date = Date(),
        upcomingWindowDays: Int = 14,
        urgentWindowDays: Int = 1
    ) {
        self.grades = grades
        self.mistakeSets = mistakeSets
        self.examSets = examSets
        self.profile = profile
        self.bodyStatusSuggestion = bodyStatusSuggestion
        self.now = now
        self.upcomingWindowDays = upcomingWindowDays
        self.urgentWindowDays = urgentWindowDays
    }
}

/// 学习建议生成器。纯函数,无副作用。
/// `StudySuggestion` generator. Pure, side-effect free.
/// 内部复用 `SubjectAggregator` 一次扫描。
/// Reuses `SubjectAggregator` to avoid scanning `grades` more than once.
enum SuggestionEngine {

    /// 生成按优先级排序的建议列表(最多 `max` 条)。
    /// Generate suggestions sorted by priority, capped at `max`.
    /// - Returns: 优先级 high > medium > low,按添加顺序
    ///   Priority: high > medium > low, in append order within the same priority.
    static func generate(
        from context: StudySuggestionsContext,
        max: Int = 3
    ) -> [StudySuggestion] {
        // 单次聚合 grades,所有 find* 复用同一份结果
        let aggregates = SubjectAggregator.aggregate(
            grades: context.grades,
            includeRecentCount: false
        )
        // 聚合 mistakes(按 subject 计数)
        let mistakeCounts = mistakeCountsBySubject(context.mistakeSets)

        var suggestions: [StudySuggestion] = []

        // 1) 身体状况(优先于纯成绩建议)
        if let body = context.bodyStatusSuggestion {
            suggestions.append(body)
        }

        // 2) 弱科
        if let weak = findWeakSubject(aggregates: aggregates) {
            suggestions.append(StudySuggestion(
                icon: "exclamationmark.triangle.fill",
                title: String(format: "Focus on %@".localized(), weak.localized()),
                description: "Your scores in this subject are lower than average. Spend more time reviewing key concepts.".localized(),
                priority: .high,
                color: .yellow
            ))
        }

        // 3) 今天/明天有考试
        if let urgentCount = urgentExamsCount(
            examSets: context.examSets,
            now: context.now,
            windowDays: context.urgentWindowDays
        ), urgentCount > 0 {
            suggestions.append(StudySuggestion(
                icon: "timer",
                title: "Exam is almost here!".localized(),
                description: String(format: "You have %d exam(s) today or tomorrow. Review your notes now!".localized(), urgentCount),
                priority: .high,
                color: .red
            ))
        }

        // 4) 持续下滑
        if let declining = findDecliningTrend(aggregates: aggregates) {
            suggestions.append(StudySuggestion(
                icon: "chart.line.downtrend.xyaxis",
                title: String(format: "%@ scores are slipping".localized(), declining.localized()),
                description: "Your recent scores in this subject show a downward trend. Identify what's causing the gap.".localized(),
                priority: .high,
                color: .orange
            ))
        }

        // 5) 错题未复习 / 错题很多
        let unreviewedMistakes = findUnreviewedMistakeSubjects(
            aggregates: aggregates,
            mistakeCounts: mistakeCounts
        )
        if !unreviewedMistakes.isEmpty {
            suggestions.append(StudySuggestion(
                icon: "doc.text.magnifyingglass",
                title: "Unreviewed Mistakes".localized(),
                description: String(format: "You have mistakes in %@ that haven't been reviewed. Go through them before the next exam.".localized(), unreviewedMistakes.joined(separator: ", ").localized()),
                priority: .high,
                color: .purple
            ))
        } else if context.mistakeSets.count >= 5 {
            suggestions.append(StudySuggestion(
                icon: "book.fill",
                title: "Review Mistakes".localized(),
                description: String(format: "You have %d mistake note(s). Regular review helps prevent similar errors.".localized(), context.mistakeSets.count),
                priority: .medium,
                color: .purple
            ))
        }

        // 6) 未来 N 天有考试
        let upcomingCount = upcomingExamsCount(
            examSets: context.examSets,
            now: context.now,
            windowDays: context.upcomingWindowDays
        )
        if upcomingCount > 0 {
            suggestions.append(StudySuggestion(
                icon: "calendar",
                title: "Upcoming Exams".localized(),
                description: String(format: "%d exam(s) in the next 2 weeks. Organize your review by subject priority.".localized(), upcomingCount),
                priority: .medium,
                color: .blue
            ))
        }

        // 7) 持续进步
        if let improving = findImprovingTrend(aggregates: aggregates) {
            suggestions.append(StudySuggestion(
                icon: "chart.line.uptrend.xyaxis",
                title: String(format: "%@ is improving!".localized(), improving.localized()),
                description: "Your scores are trending upward. Keep the momentum!".localized(),
                priority: .medium,
                color: .green
            ))
        }

        // 8) 错题密集科目
        if let mistakeHeavy = findMistakeHeavySubject(
            aggregates: aggregates,
            mistakeCounts: mistakeCounts
        ) {
            suggestions.append(StudySuggestion(
                icon: "text.badge.checkmark",
                title: String(format: "Deep dive into %@".localized(), mistakeHeavy.localized()),
                description: "You have many mistakes in this subject. Categorize your errors to find the root pattern.".localized(),
                priority: .medium,
                color: .orange
            ))
        }

        // 9) 7 天没录入新成绩
        if let lastGradeDate = context.grades.map({ $0.date }).max(),
           Calendar.current.dateComponents([.day], from: lastGradeDate, to: context.now).day ?? 0 >= 7 {
            suggestions.append(StudySuggestion(
                icon: "clock.arrow.circlepath",
                title: "Keep the streak going!".localized(),
                description: "No new grades in the past week. Regular tracking helps you spot trends early.".localized(),
                priority: .low,
                color: .cyan
            ))
        }

        // 10) 强势科
        if let strong = findStrongSubject(aggregates: aggregates) {
            suggestions.append(StudySuggestion(
                icon: "hand.thumbsup.fill",
                title: String(format: "Great at %@!".localized(), strong.localized()),
                description: "Keep up the good work! You're performing really well in this subject.".localized(),
                priority: .low,
                color: .green
            ))
        }

        // 11) 数据太少
        if context.grades.count < 5 {
            suggestions.append(StudySuggestion(
                icon: "plus.circle.fill",
                title: "Add More Grades".localized(),
                description: "Tracking more grades will help you get better insights into your learning progress.".localized(),
                priority: .low,
                color: .cyan
            ))
        }

        // 12) 学科失衡
        if let imbalanced = findImbalancedStudy(aggregates: aggregates) {
            suggestions.append(StudySuggestion(
                icon: "scalemass",
                title: "Balance your subjects".localized(),
                description: String(format: "You have significantly more grades in %@ than other subjects. Don't neglect the rest.".localized(), imbalanced.localized()),
                priority: .low,
                color: .teal
            ))
        }

        return Array(suggestions.prefix(max))
    }

    // MARK: - Helpers
    // MARK: - 工具方法 / Helpers

    /// 错题按 subject 计数(单次扫)
    /// Mistake count per subject (single scan).
    static func mistakeCountsBySubject(_ mistakeSets: [MistakeNote]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for m in mistakeSets {
            counts[m.subject, default: 0] += 1
        }
        return counts
    }

    // MARK: - 7 个独立 find*(全部纯函数,可单独被 ViewModel 调用)
    // MARK: - 7 个独立 find*(全部纯函数,可单独被 ViewModel 调用) / 7 standalone find* helpers (all pure, callable from any view model)

    /// 平均分最低的科目(样本数 >= 2 才有意义)
    /// 同分时按科目名字典序取首个,保证确定性。
    /// Lowest-average subject (only with >= 2 samples).
    /// Ties break by subject name (ascending) for determinism.
    static func findWeakSubject(aggregates: [String: SubjectAggregate]) -> String? {
        let qualified = SubjectAggregator.qualifiedAggregates(aggregates, minCount: 2)
        return qualified.min {
            ($0.value.average, $0.key) < ($1.value.average, $1.key)
        }?.key
    }

    /// 平均分最高的科目(样本数 >= 2)
    /// 同分时按科目名字典序取首个,保证确定性。
    /// Highest-average subject (only with >= 2 samples).
    /// Ties break by subject name (ascending) for determinism.
    static func findStrongSubject(aggregates: [String: SubjectAggregate]) -> String? {
        let qualified = SubjectAggregator.qualifiedAggregates(aggregates, minCount: 2)
        return qualified.min {
            ($1.value.average, $0.key) < ($0.value.average, $1.key)
        }?.key
    }

    /// 最近 3 次成绩严格下滑 ≥ 5 分
    /// 多候选时取降幅最大者,同幅按科目名字典序,保证确定性。
    /// Subject whose last 3 scores strictly decline by >= 5 points.
    /// Picks the largest drop; ties break by subject name (ascending).
    static func findDecliningTrend(aggregates: [String: SubjectAggregate]) -> String? {
        var candidates: [(subject: String, drop: Double)] = []
        for (subject, agg) in aggregates where agg.sortedAsc.count >= 3 {
            let last3 = Array(agg.sortedAsc.suffix(3))
            // last3.count 已知 == 3(外层 guard 保证),仍用 guard 防御未来改逻辑时退化
            guard let s0 = last3.dropFirst(0).first?.score,
                  let s1 = last3.dropFirst(1).first?.score,
                  let s2 = last3.dropFirst(2).first?.score else { continue }
            if s0 > s1, s1 > s2, s0 - s2 >= 5 {
                candidates.append((subject, s0 - s2))
            }
        }
        return candidates.min {
            ($1.drop, $0.subject) < ($0.drop, $1.subject)
        }?.subject
    }

    /// 最近 3 次成绩严格进步 ≥ 5 分
    /// 多候选时取涨幅最大者,同幅按科目名字典序,保证确定性。
    /// Subject whose last 3 scores strictly improve by >= 5 points.
    /// Picks the largest gain; ties break by subject name (ascending).
    static func findImprovingTrend(aggregates: [String: SubjectAggregate]) -> String? {
        var candidates: [(subject: String, gain: Double)] = []
        for (subject, agg) in aggregates where agg.sortedAsc.count >= 3 {
            let last3 = Array(agg.sortedAsc.suffix(3))
            guard let s0 = last3.dropFirst(0).first?.score,
                  let s1 = last3.dropFirst(1).first?.score,
                  let s2 = last3.dropFirst(2).first?.score else { continue }
            if s0 < s1, s1 < s2, s2 - s0 >= 5 {
                candidates.append((subject, s2 - s0))
            }
        }
        return candidates.min {
            ($1.gain, $0.subject) < ($0.gain, $1.subject)
        }?.subject
    }

    /// 错题 ≥ 3 但成绩为 0 的科目(前 2 个,按科目名字典序,保证确定性)
    /// Subjects with >= 3 mistakes but 0 recorded grades (top 2, name-sorted).
    static func findUnreviewedMistakeSubjects(
        aggregates: [String: SubjectAggregate],
        mistakeCounts: [String: Int]
    ) -> [String] {
        var unreviewed: [String] = []
        for (subject, count) in mistakeCounts where count >= 3 {
            let gradeCount = aggregates[subject]?.count ?? 0
            if gradeCount == 0 {
                unreviewed.append(subject)
            }
        }
        return Array(unreviewed.sorted().prefix(2))
    }

    /// 错题 ≥ 5 且错题数 > 成绩数 × 2 的科目
    /// 多候选时按科目名字典序取首个,保证确定性。
    /// Subject where mistakes >= 5 AND mistakes > grades × 2.
    /// Ties break by subject name (ascending) for determinism.
    static func findMistakeHeavySubject(
        aggregates: [String: SubjectAggregate],
        mistakeCounts: [String: Int]
    ) -> String? {
        let allSubjects = Set(mistakeCounts.keys).union(aggregates.keys)
        let matched = allSubjects.filter { subject in
            let mc = mistakeCounts[subject] ?? 0
            let gc = aggregates[subject]?.count ?? 0
            return mc >= 5 && mc > gc * 2
        }
        return matched.min()
    }

    /// 学科失衡:某科成绩数 > 其余科目平均的 3 倍
    /// 同数量时按科目名字典序取首个,保证确定性。
    /// Subject imbalance: a subject's grade count > 3 × the average of the rest.
    /// Ties break by subject name (ascending) for determinism.
    static func findImbalancedStudy(aggregates: [String: SubjectAggregate]) -> String? {
        guard aggregates.count >= 3 else { return nil }
        let sorted = aggregates
            .map { (subject: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.subject < rhs.subject
            }
        guard let max = sorted.first else { return nil }
        let others = Array(sorted.dropFirst())
        let total = others.reduce(0) { $0 + $1.count }
        let avgOthers = others.isEmpty ? 0 : total / others.count
        guard max.count > avgOthers * 3 else { return nil }
        return max.subject
    }

    // MARK: - Exam-window helpers
    // MARK: - Exam-window helpers / 考试窗口工具

    /// 未来 N 天内的考试数量
    /// Number of exams in the next `windowDays` days.
    static func upcomingExamsCount(
        examSets: [Exam],
        now: Date = Date(),
        windowDays: Int
    ) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: windowDays, to: now) ?? now
        return examSets.filter { $0.examDate > now && $0.examDate <= cutoff }.count
    }

    /// 今天/明天有考试的数量
    /// Number of exams today or tomorrow (`nil` if zero).
    static func urgentExamsCount(
        examSets: [Exam],
        now: Date = Date(),
        windowDays: Int = 1
    ) -> Int? {
        var count = 0
        for exam in examSets {
            for offset in 0...windowDays {
                let day = Calendar.current.date(byAdding: .day, value: offset, to: now) ?? now
                if Calendar.current.isDate(exam.examDate, inSameDayAs: day) {
                    count += 1
                    break
                }
            }
        }
        return count > 0 ? count : nil
    }
}
