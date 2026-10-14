//
//  HomeDynamicLayoutEngine.swift
//  StudyPulse
//
//  主页动态排布:无信息的卡片隐藏,其余按紧迫度自动排序(纯函数,无 SwiftUI 依赖)。
//  Home dynamic layout: hides cards that carry no information and orders the rest by urgency.
//  Pure functions, no SwiftUI dependency.
//

import Foundation

/// 决定每张卡片「是否有信息 / 紧迫度」所需的数据快照。
/// Snapshot of the data that decides whether each card has information and how urgent it is.
nonisolated struct HomeCardSignals: Equatable, Sendable {
    var dailyPlanCount = 0
    var minimalPlanActive = false
    var dueFlashcards = 0
    /// 最近一场考试距今天数;无即将到来的考试为 nil / Days until the nearest exam; nil when none.
    var nextExamDays: Int? = nil
    var unregisteredExamCount = 0
    var weeklyFocusHasData = false
    var subjectSnapshotCount = 0
    var hasActivityHistory = false
    var currentStreak = 0
    var recentGradeCount = 0
    /// HRV / 身体数据已启用或已授权 / Health data enabled or authorized.
    var healthDataAvailable = false
    var hasBodyMindData = false
    var diaryEnabled = true
    var hasDiaryToday = false
    /// 已完成学习会话数(习惯洞察需要 ≥ 3)/ Completed sessions (habit insight needs ≥ 3).
    var completedSessionCount = 0
    var memoryClimateSubjectCount = 0
    var plantEnabled = true
    /// 当前小时 0...23(用于日记晚间提升)/ Current hour 0...23 (evening diary boost).
    var hour = 12
}

nonisolated enum HomeDynamicLayoutEngine {

    /// 卡片是否有可展示的信息。操作型入口卡(快捷操作 / 计时器 / AI 问答 / 每日金句 /
    /// 脑力用量)始终视为有信息。
    /// Whether the card has something to show. Action-style cards (quick actions, timer, AI ask,
    /// quote, brain usage) always count as informative.
    static func hasInformation(_ type: HomeCardType, signals s: HomeCardSignals) -> Bool {
        switch type {
        case .dailyPlan: return s.dailyPlanCount > 0
        case .minimalPlan: return s.minimalPlanActive
        case .flashcardReview: return s.dueFlashcards > 0
        case .memoryClimate: return s.memoryClimateSubjectCount > 0
        case .upcomingExams, .examDayReadiness, .examReversePlanner, .examRoleSimulator:
            return s.nextExamDays != nil
        case .unregisteredExamsReminder: return s.unregisteredExamCount > 0
        case .weeklyFocus: return s.weeklyFocusHasData
        case .subjectSnapshot: return s.subjectSnapshotCount > 0
        case .learningHeatmap: return s.hasActivityHistory
        case .streakProgress: return s.currentStreak > 0 || s.hasActivityHistory
        case .trendChart, .recentGrades: return s.recentGradeCount > 0
        case .hrvStatus: return s.healthDataAvailable
        case .bodyMindTrend: return s.hasBodyMindData
        case .diary: return s.diaryEnabled
        case .habitInsight: return s.completedSessionCount >= 3
        case .plant: return s.plantEnabled
        case .studySuggestions:
            return s.recentGradeCount > 0 || s.hasBodyMindData || s.dueFlashcards > 0 || s.nextExamDays != nil
        case .quickActions, .studyTimer, .homeAsk, .dailyQuote, .brainUsage: return true
        }
    }

    /// 紧迫度,数值越小越靠前。
    /// Urgency score; lower sorts first.
    static func priority(_ type: HomeCardType, signals s: HomeCardSignals) -> Int {
        let examDays = s.nextExamDays ?? Int.max
        switch type {
        case .minimalPlan: return 0
        case .upcomingExams: return examDays <= 3 ? 0 : (examDays <= 7 ? 2 : 10)
        case .dailyPlan: return 1
        case .unregisteredExamsReminder: return 3
        case .flashcardReview: return s.dueFlashcards >= 20 ? 2 : 4
        case .examDayReadiness: return examDays <= 3 ? 3 : (examDays <= 14 ? 12 : 30)
        case .diary: return (!s.hasDiaryToday && s.hour >= 18) ? 4 : (s.hasDiaryToday ? 18 : 14)
        case .studyTimer: return 6
        case .streakProgress: return 7
        case .weeklyFocus: return 8
        case .subjectSnapshot: return 9
        case .hrvStatus: return 10
        case .memoryClimate: return 11
        case .examReversePlanner: return examDays <= 14 ? 6 : 13
        case .trendChart: return 13
        case .examRoleSimulator: return examDays <= 14 ? 15 : 22
        case .learningHeatmap: return 15
        case .bodyMindTrend: return 16
        case .habitInsight: return 17
        case .studySuggestions: return 19
        case .quickActions: return 20
        case .homeAsk: return 22
        case .plant: return 24
        case .brainUsage: return 25
        case .recentGrades: return 26
        case .dailyQuote: return 30
        }
    }

    /// 过滤掉无信息卡片,并按紧迫度稳定排序;同分时保留传入顺序(用户已存顺序)。
    /// Drops cards without information and stably sorts by urgency; ties keep the incoming order.
    static func arrange(enabled: [HomeCardType], signals: HomeCardSignals) -> [HomeCardType] {
        enabled.enumerated()
            .filter { hasInformation($0.element, signals: signals) }
            .sorted { lhs, rhs in
                let l = priority(lhs.element, signals: signals)
                let r = priority(rhs.element, signals: signals)
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
