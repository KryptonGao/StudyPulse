//
//  HomeViewModel.swift
//  StudyPulse
//
//  首页 ViewModel。负责 4 个核心派生数据的重算 + 图表选科 + 建议生成。
//  渲染/分享(imageRenderer)是 UI 关注点,保留在 View 层。
//  Home-page VM. Recomputes 4 core derived datasets, picks the chart
//  subject, and generates study suggestions. Rendering/sharing stays in
//  the View.
//
//  Created for MVVM refactor (2026-07-05).
//  Updated for Repository pattern (2026-07-05).
//

import Foundation
import SwiftUI

/// 学科选择规则(图表卡片的"聚焦"模式)
/// Subject-selection rule (the chart card's "focus" mode).
enum SubjectSelectionRule: Equatable {
    case lowestScore
    case mostGrades
    case recentMost
    case mostImprovement
    case random

    /// 规则的用户可见名 / User-visible, localized name.
    var displayName: String {
        switch self {
        case .lowestScore: return "Focus: Weakest".localized()
        case .mostGrades:  return "Focus: Most Data".localized()
        case .recentMost:  return "Focus: Recent".localized()
        case .mostImprovement: return "Focus: Improving".localized()
        case .random:      return "Random".localized()
        }
    }
}

/// 首页 ViewModel。负责派生数据重算、图表选科、学习建议生成
/// (不参与 UI 渲染 / 分享 sheet 控制)。
/// Home-page VM. Recomputes derived data, picks the chart subject, and
/// generates study suggestions (does NOT own UI/share-sheet state).
@MainActor
@Observable
final class HomeViewModel {

    // MARK: - 依赖项 / Dependencies
    private let container: RepositoryContainer
    private let hrvManager: HealthKitManager

    // MARK: - 输出状态(View 只读) / Output state (read-only for View)
    /// SRS 总览 / SRS overview.
    private(set) var srsOverview: SRSOverview = .empty
    /// 最近的 5 条成绩(按时间倒序) / Most recent 5 grades (newest first).
    private(set) var recentGrades: [Grade] = []
    /// 14 天内的即将到来的考试 / Upcoming exams within 14 days.
    private(set) var upcomingExams: [Exam] = []
    /// 3~7 天前发生过、但还没登记的考试 / Unregistered exams (3–7 days ago).
    private(set) var unregisteredExams: [Exam] = []
    /// 今日 Top-3 计划(2026-07-09) / Today's Top-3 plan (2026-07-09).
    private(set) var dailyPlan: [DailyPlanItem] = []
    /// 状态不佳时的压缩计划；未触发时为空。
    private(set) var minimalPlan: MinimalPlanResult = MinimalPlanResult(isActive: false, reason: "", items: [], totalMinutes: 0)
    /// 今日记忆气候与当前阶段近 90 天历史。
    private(set) var memoryClimate: MemoryClimateSnapshot = .empty()
    private(set) var memoryClimateHistory: [MemoryClimateSnapshot] = []

    /// 考前状态预测与最近 14 天恢复分曲线。
    private(set) var examReadiness: [ExamDayReadiness] = []
    private(set) var recoveryPoints: [DailyRecoveryPoint] = []
    /// 最近 14 天倦怠评估；无健康授权或样本不足时仍返回 low + 引导文案。
    private(set) var burnoutAssessment: BurnoutAssessment?
    private(set) var burnoutSuggestion: StudySuggestion?

    /// 图表卡片的当前规则 + 选中科目 / Current chart rule & subject.
    private(set) var chartRule: SubjectSelectionRule = .lowestScore
    private(set) var chartSelectedSubject: String? = nil

    /// 上一次 recompute 时的输入签名(用于 dirty flag:相同输入则跳过重算)。
    /// 8 个 `.recomputeOn*` modifier 在同一 RunLoop tick 内可能多次触发 `recompute()`,
    /// 这个签名比对把"一次用户操作触发 2-3 次重算"降到 1 次(首次实际重算,后续被跳过)。
    /// Signature of the last recompute's inputs (dirty flag: skip recompute when inputs match).
    /// The 8 `.recomputeOn*` modifiers may trigger `recompute()` multiple times in the same
    /// RunLoop tick; this signature reduces "2-3 recomputes per user action" to 1
    /// (first call computes, the rest are skipped).
    private var lastRecomputeSignature: Int = 0

    // MARK: - 初始化 / Initialization
    init(container: RepositoryContainer, hrvManager: HealthKitManager) {
        self.container = container
        self.hrvManager = hrvManager
    }

    /// 工厂方法 / Factory.
    static func makeDefault(container: RepositoryContainer) -> HomeViewModel {
        HomeViewModel(
            container: container,
            hrvManager: HealthKitManager.shared
        )
    }

    // MARK: - 业务方法:派生数据重算 / Business: derived-data recompute
    /// 一次性刷新 4 个缓存(SRS / recent grades / upcoming / unregistered)
    /// One-shot refresh of 4 caches.
    ///
    /// 内部用 dirty flag:输入签名与上次相同时直接 return,避免一次用户操作触发 2-3 次完整重算。
    /// Dirty flag: when the input signature matches the last recompute,return immediately —
    /// avoids the 2-3 full recomputes that one user action would otherwise trigger.
    func recompute() {
        let grades = container.gradeRepo.grades
        let mistakes = container.mistakeRepo.mistakeSets
        let filteredExams = container.examRepo.filteredExamSets
        let taskItems = container.taskRepo.filteredTaskItems
        let routineInstances = container.routineInstanceRepo.allInstances
        let sessions = container.studySessionRepo.sessions
        let diaryEntries = container.diaryRepo.diaryEntries
        let healthHistory = hrvManager.dailyHealthHistory

        // Dirty flag: 比对输入签名,相同则跳过重算。
        let sig = recomputeSignature(
            grades: grades, mistakes: mistakes, exams: filteredExams,
            tasks: taskItems, instances: routineInstances,
            sessions: sessions, diaryEntries: diaryEntries, healthHistory: healthHistory,
            readiness: hrvManager.readiness, bodyStatus: hrvManager.bodyStatus,
            chartRule: chartRule
        )
        if sig == lastRecomputeSignature { return }
        lastRecomputeSignature = sig

        // SRS
        srsOverview = SRSAlgorithm.overview(from: mistakes)

        // Recent grades: 按时间倒序取前 5 / Newest 5 by date desc.
        let sortedGradesDesc = grades.sorted { $0.date > $1.date }
        recentGrades = Array(sortedGradesDesc.prefix(5))

        // Upcoming exams: 14 天内 / Within 14 days.
        upcomingExams = ExamFilter.examsWithinDays(14, exams: filteredExams)

        // Unregistered exams: 已过 3-7 天 / 3–7 days ago, still ungraded.
        unregisteredExams = ExamFilter.unregisteredExams(
            startDaysAgo: -3,
            endDaysAgo: -7,
            grades: grades,
            exams: filteredExams
        )

        let recovery = RecoveryTrendEngine.analyze(
            snapshots: healthHistory,
            baselines: hrvManager.personalBaselines,
            age: container.profileRepo.profile.age,
            todayHRVCategory: hrvManager.readiness.category
        )
        recoveryPoints = recovery.points
        examReadiness = ExamDayReadinessEngine.predict(
            exams: filteredExams,
            snapshots: healthHistory,
            sessions: sessions,
            baselines: hrvManager.personalBaselines,
            age: container.profileRepo.profile.age,
            todayHRVCategory: hrvManager.readiness.category
        )
        let burnout = BurnoutDetectionEngine.assess(
            snapshots: healthHistory,
            sessions: sessions,
            diaryEntries: diaryEntries,
            baselines: hrvManager.personalBaselines,
            age: container.profileRepo.profile.age,
            healthAuthorized: hrvManager.hrvEnabled
                && hrvManager.hrvOnboardingCompleted
                && hrvManager.isAuthorized,
            todayHRVCategory: hrvManager.readiness.category
        )
        burnoutAssessment = burnout
        burnoutSuggestion = burnout.riskLevel == .low ? nil : StudySuggestion(
            icon: "exclamationmark.triangle.fill",
            title: "burnout.title".localized(),
            description: ([burnout.advice] + burnout.triggers.map(\.detail)).joined(separator: " · "),
            priority: .high,
            color: .red
        )

        // 今日 Top-3 计划(2026-07-09) / Today's Top-3 plan.
        let planContext = DailyPlanContext(
            grades: grades,
            mistakeSets: mistakes,
            examSets: filteredExams,
            taskItems: taskItems,
            routineInstances: routineInstances,
            hrvReadiness: hrvManager.readiness,
            hrvBodyStatus: hrvManager.bodyStatus
        )
        dailyPlan = DailyPlanEngine.generate(from: planContext, max: 3)

        let minimalContext = MinimalPlanContext(
            mistakeSets: mistakes,
            examSets: filteredExams,
            taskItems: taskItems,
            routineInstances: routineInstances,
            hrvReadiness: hrvManager.readiness,
            hrvBodyStatus: hrvManager.bodyStatus
        )
        minimalPlan = MinimalCompletionPlanEngine.generate(from: minimalContext)

        // 今日记忆气候：同日同阶段幂等覆盖，并加载当前阶段 90 天历史。
        memoryClimate = MemoryClimateEngine.generate(
            mistakes: container.mistakeRepo.filteredMistakeSets,
            phaseId: container.envManager.activePhaseId
        )
        memoryClimateHistory = MemoryClimateHistoryStore
            .upsert(memoryClimate)
            .filter { $0.phaseId == container.envManager.activePhaseId }

        // 图表选中科目可能因数据变化失效,刷新
        // Selected chart subject may be stale → refresh.
        applyChartRule(chartRule)
    }

    /// 计算 recompute 输入的签名(用 Hasher combine 元素 id + count)。
    /// 同一进程内 `Hasher()` 的 seed 稳定,适合 dirty flag 比对。
    /// Compute the input signature for `recompute` (Hasher over element ids + counts).
    /// `Hasher()` seed is stable within a single process, suitable for dirty-flag comparison.
    private func recomputeSignature(
        grades: [Grade], mistakes: [MistakeNote], exams: [Exam],
        tasks: [TaskItem], instances: [RoutineInstance],
        sessions: [StudySession], diaryEntries: [DiaryEntry],
        healthHistory: [DailyHealthSnapshot],
        readiness: HRVReadiness, bodyStatus: BodyStatus,
        chartRule: SubjectSelectionRule
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(grades.count)
        for g in grades { hasher.combine(g.id) }
        hasher.combine(mistakes.count)
        for m in mistakes {
            hasher.combine(m.id)
            hasher.combine(m.subject)
            hasher.combine(m.phaseId)
            hasher.combine(m.masteryScore)
            hasher.combine(m.tags)
            hasher.combine(m.reviewState)
            hasher.combine(m.masteryHistory)
        }
        hasher.combine(container.envManager.activePhaseId)
        hasher.combine(exams.count)
        // 整体 combine(合成 Hashable 覆盖全部字段):编辑 checklist/examReview/
        // location*/countdownNotifyDays/examDate 等不改 id 的更新也能触发重算。
        // Whole-struct combine (synthesized Hashable covers all fields) so
        // in-place edits (checklist/review/location/dates) still change the signature.
        for e in exams { hasher.combine(e) }
        hasher.combine(tasks.count)
        for t in tasks { hasher.combine(t) }
        hasher.combine(instances.count)
        for i in instances { hasher.combine(i.id) }
        hasher.combine(sessions.count)
        for session in sessions {
            hasher.combine(session.id)
            hasher.combine(session.startDate)
            hasher.combine(session.durationSeconds)
            hasher.combine(session.intensity.rawValue)
            hasher.combine(session.completed)
        }
        hasher.combine(diaryEntries.count)
        for entry in diaryEntries {
            hasher.combine(entry.id)
            hasher.combine(entry.date)
            hasher.combine(entry.moodScore)
            hasher.combine(entry.energyScore)
            hasher.combine(entry.updatedAt)
        }
        hasher.combine(healthHistory.count)
        for snapshot in healthHistory {
            hasher.combine(snapshot.date)
            hasher.combine(snapshot.hrv)
            hasher.combine(snapshot.restingHeartRate)
            hasher.combine(snapshot.respiratoryRate)
            hasher.combine(snapshot.sleepHours)
            hasher.combine(snapshot.deepSleepHours)
            hasher.combine(snapshot.remSleepHours)
            hasher.combine(snapshot.exerciseMinutes)
        }
        hasher.combine(readiness.zScore)
        hasher.combine(readiness.todayHRV)
        hasher.combine(readiness.baselineMean)
        hasher.combine(readiness.baselineSampleCount)
        hasher.combine(readiness.category.rawValue)
        hasher.combine(readiness.suggestion)
        hasher.combine(bodyStatus.restingHeartRate)
        hasher.combine(bodyStatus.latestHeartRate)
        hasher.combine(bodyStatus.respiratoryRate)
        hasher.combine(bodyStatus.lastNightSleepHours)
        hasher.combine(bodyStatus.deepSleepHours)
        hasher.combine(bodyStatus.remSleepHours)
        hasher.combine(bodyStatus.sleepQuality.rawValue)
        hasher.combine(bodyStatus.exerciseMinutesToday)
        hasher.combine(bodyStatus.isUsable)
        hasher.combine(chartRule)
        return hasher.finalize()
    }

    // MARK: - 业务方法:图表选择 / Business: chart subject selection
    /// 用户切换聚焦规则 / User switches the focus rule.
    func selectChartSubject(rule: SubjectSelectionRule) {
        chartRule = rule
        applyChartRule(rule)
    }

    /// 根据当前规则 + 数据重新计算选中科目
    /// Recompute the selected subject from rule + data.
    private func applyChartRule(_ rule: SubjectSelectionRule) {
        let grades = container.gradeRepo.grades
        let activeSubjects = Set(grades.map { $0.subject })
        guard !activeSubjects.isEmpty else {
            chartSelectedSubject = nil
            return
        }
        // 单次 O(n) 分组聚合 / Single-pass group + aggregate.
        let aggregates = SubjectAggregator.aggregate(
            grades: grades,
            subjects: activeSubjects
        )
        switch rule {
        case .lowestScore:
            chartSelectedSubject = aggregates.min { $0.value.average < $1.value.average }?.key
        case .mostGrades:
            chartSelectedSubject = aggregates.max { $0.value.count < $1.value.count }?.key
        case .recentMost:
            chartSelectedSubject = aggregates.max { $0.value.recentCount < $1.value.recentCount }?.key
        case .mostImprovement:
            // 改进分 = (last - first);至少 2 条成绩
            // Improvement = last - first; needs ≥ 2 grades.
            chartSelectedSubject = aggregates.compactMap { (subject, agg) -> (String, Double)? in
                guard let first = agg.sortedAsc.first,
                      let last = agg.sortedAsc.last,
                      agg.sortedAsc.count >= 2 else { return nil }
                return (subject, last.score - first.score)
            }.max { $0.1 < $1.1 }?.0
        case .random:
            chartSelectedSubject = activeSubjects.randomElement()
        }
    }

    /// 查询某科目的全部成绩(chart card 用) / All grades for a subject.
    func gradesForSubject(_ subject: String) -> [Grade]? {
        let grades = container.gradeRepo.grades.filter { $0.subject == subject }
        return grades.isEmpty ? nil : grades
    }

    // MARK: - 业务方法:学习建议 / Business: study suggestions
    /// 生成学习建议列表 / Generate study suggestions.
    func generateSuggestions(limit: Int = 3) -> [StudySuggestion] {
        let context = buildSuggestionsContext()
        let localSuggestions = SuggestionEngine.generate(from: context, max: limit)
        guard let burnoutSuggestion else { return localSuggestions }
        return Array(([burnoutSuggestion] + localSuggestions).prefix(limit))
    }

    /// 构造学习建议上下文(供 LLM 增强使用)
    /// Build the suggestions context (also for LLM augmentation).
    func buildSuggestionsContext() -> StudySuggestionsContext {
        let body = StudyReadinessAlgorithm.recommend(
            hrvEnabled: hrvManager.hrvEnabled,
            hrvOnboardingCompleted: hrvManager.hrvOnboardingCompleted,
            isAuthorized: hrvManager.isAuthorized,
            hrv: hrvManager.readiness,
            bodyStatus: hrvManager.bodyStatus,
            baselines: hrvManager.personalBaselines,
            age: container.profileRepo.profile.age
        )
        return StudySuggestionsContext(
            grades: container.gradeRepo.grades,
            mistakeSets: container.mistakeRepo.mistakeSets,
            examSets: container.examRepo.filteredExamSets,
            profile: container.profileRepo.profile,
            bodyStatusSuggestion: body
        )
    }
}
