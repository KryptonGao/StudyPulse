//
//  AIStudyDataEngine.swift
//  StudyPulse
//
//  Pure-function aggregation for AI Mode. The same snapshot feeds the data
//  pages and the LLM context, so numbers shown to the user and numbers sent
//  to the model can never drift apart. No SwiftUI, no repositories.
//

import Foundation

// MARK: - Grades

nonisolated enum AIGradeRange: String, CaseIterable, Identifiable, Sendable, Hashable {
    case days30
    case days90
    case phase

    var id: String { rawValue }

    var trendsRange: TrendsRange {
        switch self {
        case .days30: return .days30
        case .days90: return .days90
        case .phase: return .all
        }
    }

    var scope: AIDateScope {
        switch self {
        case .days30: return .last30Days
        case .days90: return .last90Days
        case .phase: return .phaseAll
        }
    }
}

nonisolated struct AIGradeSubjectRow: Identifiable, Equatable, Sendable {
    let subject: String
    /// Mean raw score within the range.
    let averageScore: Double
    let latestScore: Double
    let latestExamName: String
    let latestDate: Date
    let fullScore: Double
    /// Mean score rate 0...100.
    let averageRate: Double
    /// Raw-score change (recent 3 vs previous 3 within the range).
    let delta: Double
    let count: Int
    var id: String { subject }
}

nonisolated struct AIGradesSnapshot: Equatable, Sendable {
    var range: AIGradeRange
    var trend: OverallTrend
    var rows: [AIGradeSubjectRow]
    var gradeCount: Int
    var isEmpty: Bool { gradeCount == 0 }
    /// Fewer than two grade records: no trend can be stated.
    var hasEnoughForTrend: Bool { gradeCount >= 2 }

    static func empty(range: AIGradeRange) -> AIGradesSnapshot {
        AIGradesSnapshot(range: range, trend: .empty, rows: [], gradeCount: 0)
    }
}

// MARK: - Mistakes

nonisolated struct AIMistakeRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let subject: String
    /// 0...1
    let mastery: Double
    /// Negative = overdue, 0 = today, nil = not enrolled in SRS.
    let daysUntilReview: Int?
}

nonisolated struct AIMistakePatternRow: Identifiable, Equatable, Sendable {
    let pattern: MistakePattern
    let count: Int
    let subjects: [String]
    var id: String { pattern.rawValue }
}

nonisolated struct AIMistakesSnapshot: Equatable, Sendable {
    /// Mastery at or above this value counts as "mastered".
    static let masteredThreshold = 0.8

    var total: Int
    var masteredCount: Int
    var review: MistakeReviewBreakdown
    var subjects: [MistakeSubjectSummary]
    var priority: [AIMistakeRow]
    var patterns: [AIMistakePatternRow]
    var isEmpty: Bool { total == 0 }

    static let empty = AIMistakesSnapshot(
        total: 0, masteredCount: 0, review: .empty, subjects: [], priority: [], patterns: []
    )
}

// MARK: - Exams

nonisolated struct AIExamRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let subjects: [String]
    let date: Date
    let daysUntil: Int
    let importance: Int
    /// 0...100
    let mastery: Int
    let checklistDone: Int?
    let checklistTotal: Int?
    let isComprehensive: Bool
}

nonisolated struct AIExamPlanSummary: Equatable, Sendable {
    let examName: String
    let subject: String
    let summary: String
    let createdAt: Date
}

nonisolated struct AIExamsSnapshot: Equatable, Sendable {
    var upcoming: [AIExamRow]
    var pastCount: Int
    var plan: AIExamPlanSummary?
    var isEmpty: Bool { upcoming.isEmpty && pastCount == 0 }

    static let empty = AIExamsSnapshot(upcoming: [], pastCount: 0, plan: nil)
}

// MARK: - Time

nonisolated struct AITimeProjectRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let seconds: Int
}

nonisolated struct AITimeSnapshot: Equatable, Sendable {
    var weekSeconds: Int
    var previousWeekSeconds: Int
    var days: [DailyFocusPoint]
    var projects: [AITimeProjectRow]
    var streak: Int
    var unassignedCount: Int
    var completedSessionCount: Int
    var isEmpty: Bool { completedSessionCount == 0 }

    static let empty = AITimeSnapshot(
        weekSeconds: 0, previousWeekSeconds: 0, days: [], projects: [], streak: 0,
        unassignedCount: 0, completedSessionCount: 0
    )
}

// MARK: - Health

nonisolated enum AIHealthState: Equatable, Sendable {
    case disabled
    case unauthorized
    case loading
    case insufficient
    case available
}

nonisolated struct AIHealthSnapshot: Equatable, Sendable {
    var state: AIHealthState
    /// 0...100, only when `state == .available`.
    var recoveryScore: Int?
    var readinessCategory: String?
    var hrvZScore: Double?
    var todayHRV: Double?
    var restingHeartRate: Double?
    var respiratoryRate: Double?
    var sleepHours: Double?
    var restorativeSleepHours: Double?
    var exerciseMinutes: Double?

    static let disabled = AIHealthSnapshot(state: .disabled)

    init(
        state: AIHealthState,
        recoveryScore: Int? = nil,
        readinessCategory: String? = nil,
        hrvZScore: Double? = nil,
        todayHRV: Double? = nil,
        restingHeartRate: Double? = nil,
        respiratoryRate: Double? = nil,
        sleepHours: Double? = nil,
        restorativeSleepHours: Double? = nil,
        exerciseMinutes: Double? = nil
    ) {
        self.state = state
        self.recoveryScore = recoveryScore
        self.readinessCategory = readinessCategory
        self.hrvZScore = hrvZScore
        self.todayHRV = todayHRV
        self.restingHeartRate = restingHeartRate
        self.respiratoryRate = respiratoryRate
        self.sleepHours = sleepHours
        self.restorativeSleepHours = restorativeSleepHours
        self.exerciseMinutes = exerciseMinutes
    }
}

/// Raw health inputs flattened out of `HealthKitManager` so this file stays
/// independent of HealthKit-facing types.
nonisolated struct AIHealthInput: Equatable, Sendable {
    var hrvEnabled: Bool
    var onboardingCompleted: Bool
    var isAuthorized: Bool
    var isLoading: Bool
    /// `HRVReadiness.Category.rawValue`
    var readinessCategory: String
    var hrvZScore: Double?
    var todayHRV: Double?
    var bodyUsable: Bool
    var restingHeartRate: Double?
    var respiratoryRate: Double?
    var sleepHours: Double?
    var restorativeSleepHours: Double?
    var exerciseMinutes: Double?
    /// Output of `BodyRadarValues.compute(...).recoveryScore` (nil when guards fail).
    var recoveryScore: Int?
}

// MARK: - Diary

nonisolated struct AIDiaryLatest: Equatable, Sendable {
    let id: UUID
    let date: Date
    let moodScore: Int
    let energyScore: Int
    let energyTag: String
    let excerpt: String
}

nonisolated struct AIDiarySnapshot: Equatable, Sendable {
    var latest: AIDiaryLatest?
    var moodSeries: [DailyValuePoint]
    var averageMood: Double?
    var streak: Int
    var entryCount30: Int
    var isEmpty: Bool { latest == nil }

    static let empty = AIDiarySnapshot(latest: nil, moodSeries: [], averageMood: nil, streak: 0, entryCount30: 0)
}

// MARK: - Whole snapshot

nonisolated struct AIStudyDataSnapshot: Equatable, Sendable {
    /// One entry per `AIGradeRange` so the page and the LLM context can use any range.
    var gradesByRange: [AIGradeRange: AIGradesSnapshot] = [:]
    var mistakes: AIMistakesSnapshot = .empty
    var exams: AIExamsSnapshot = .empty
    var time: AITimeSnapshot = .empty
    var health: AIHealthSnapshot = .disabled
    var diary: AIDiarySnapshot = .empty
    var phaseName: String?
    var phaseId: UUID?
    var generatedAt: Date = Date()

    func grades(_ range: AIGradeRange) -> AIGradesSnapshot {
        gradesByRange[range] ?? .empty(range: range)
    }
}

// MARK: - Engine

nonisolated enum AIStudyDataEngine {

    // MARK: Grades

    static func grades(
        grades: [Grade],
        fullScores: [String: Double],
        range: AIGradeRange,
        targets: [PhaseGoal] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AIGradesSnapshot {
        let trend = TrendsInsightsEngine.overall(
            grades: grades, fullScores: fullScores, range: range.trendsRange,
            targets: targets, now: now, calendar: calendar
        )
        let lower = range.trendsRange.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: now) }
        let inRange = grades.filter { lower == nil || $0.date >= lower! }
        guard !inRange.isEmpty else { return .empty(range: range) }

        var bySubject: [String: [Grade]] = [:]
        for grade in inRange { bySubject[grade.subject, default: []].append(grade) }

        let trendRows = TrendsInsightsEngine.subjectRows(gradesBySubject: bySubject)
        var rows: [AIGradeSubjectRow] = []
        for row in trendRows {
            let subjectGrades = bySubject[row.subject] ?? []
            let fallbackFull = fullScores[row.subject] ?? 100
            let latestGrade = subjectGrades.max { $0.date < $1.date }
            let full = latestGrade?.fullScore ?? fallbackFull
            let rates = subjectGrades.map { $0.scoreRate(subjectFullScore: fallbackFull) * 100 }
            let averageRate = rates.reduce(0, +) / Double(max(rates.count, 1))
            rows.append(AIGradeSubjectRow(
                subject: row.subject,
                averageScore: row.average,
                latestScore: row.latest,
                latestExamName: row.latestExamName,
                latestDate: row.latestDate,
                fullScore: full,
                averageRate: averageRate,
                delta: row.delta,
                count: subjectGrades.count
            ))
        }
        return AIGradesSnapshot(range: range, trend: trend, rows: rows, gradeCount: inRange.count)
    }

    static func allGrades(
        grades: [Grade],
        fullScores: [String: Double],
        targets: [PhaseGoal] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AIGradeRange: AIGradesSnapshot] {
        var result: [AIGradeRange: AIGradesSnapshot] = [:]
        for range in AIGradeRange.allCases {
            result[range] = Self.grades(
                grades: grades, fullScores: fullScores, range: range,
                targets: targets, now: now, calendar: calendar
            )
        }
        return result
    }

    // MARK: Mistakes

    static func mistakes(
        mistakes: [MistakeNote],
        now: Date = Date(),
        calendar: Calendar = .current,
        priorityLimit: Int = 5
    ) -> AIMistakesSnapshot {
        guard !mistakes.isEmpty else { return .empty }
        let mastered = mistakes.filter { $0.masteryScore >= AIMistakesSnapshot.masteredThreshold }.count
        let review = MistakeHomeEngine.review(mistakes: mistakes, now: now, calendar: calendar)
        let subjects = MistakeHomeEngine.subjectSummaries(mistakes: mistakes, now: now)

        // Priority: due/overdue first (earliest next review), then lowest mastery.
        let unmastered = mistakes.filter { $0.masteryScore < AIMistakesSnapshot.masteredThreshold }
        let sorted = unmastered.sorted { lhs, rhs in
            let l = MistakeHomeEngine.daysUntilReview(lhs, now: now, calendar: calendar)
            let r = MistakeHomeEngine.daysUntilReview(rhs, now: now, calendar: calendar)
            switch (l, r) {
            case let (a?, b?) where a != b: return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                if lhs.masteryScore != rhs.masteryScore { return lhs.masteryScore < rhs.masteryScore }
                return lhs.date > rhs.date
            }
        }
        let priority = sorted.prefix(priorityLimit).map { note in
            AIMistakeRow(
                id: note.id,
                title: note.title,
                subject: note.subject,
                mastery: note.masteryScore,
                daysUntilReview: MistakeHomeEngine.daysUntilReview(note, now: now, calendar: calendar)
            )
        }
        let patterns = MistakePatternEngine.summaries(from: mistakes, now: now).prefix(3).map {
            AIMistakePatternRow(pattern: $0.pattern, count: $0.count, subjects: $0.subjects)
        }
        return AIMistakesSnapshot(
            total: mistakes.count,
            masteredCount: mastered,
            review: review,
            subjects: subjects,
            priority: Array(priority),
            patterns: Array(patterns)
        )
    }

    // MARK: Exams

    static func exams(
        entries: [TodoEntry],
        goals: [ExamGoal],
        plans: [ExamPlan],
        activePhaseId: UUID?,
        now: Date = Date(),
        calendar: Calendar = .current,
        limit: Int = 6
    ) -> AIExamsSnapshot {
        var rows: [AIExamRow] = []
        var past = 0
        for entry in entries {
            switch entry.kind {
            case .exam:
                guard let exam = entry.exam else { continue }
                let days = TodoAgendaEngine.daysUntil(exam.examDate, now: now, calendar: calendar)
                if days < 0 { past += 1; continue }
                let progress = TodoAgendaEngine.checklistProgress(exam)
                rows.append(AIExamRow(
                    id: exam.id, name: exam.name, subjects: [exam.subject], date: exam.examDate,
                    daysUntil: days, importance: exam.importance, mastery: exam.masteryDegree,
                    checklistDone: progress?.done, checklistTotal: progress?.total, isComprehensive: false
                ))
            case .comprehensiveExam:
                guard let exam = entry.comprehensiveExam else { continue }
                let days = TodoAgendaEngine.daysUntil(exam.examDate, now: now, calendar: calendar)
                if days < 0 { past += 1; continue }
                rows.append(AIExamRow(
                    id: exam.id, name: exam.name, subjects: exam.subject, date: exam.examDate,
                    daysUntil: days, importance: exam.importance, mastery: exam.masteryDegree,
                    checklistDone: nil, checklistTotal: nil, isComprehensive: true
                ))
            default:
                continue
            }
        }
        rows.sort { $0.date < $1.date }

        // Latest plan among goals that belong to the active phase.
        let phaseGoals = goals.filter { activePhaseId == nil || $0.phaseId == activePhaseId }
        var summary: AIExamPlanSummary?
        for plan in plans.sorted(by: { $0.createdAt > $1.createdAt }) {
            guard let goal = phaseGoals.first(where: { $0.id == plan.examGoalID }) else { continue }
            let text = plan.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            summary = AIExamPlanSummary(
                examName: goal.examName, subject: goal.subject, summary: text, createdAt: plan.createdAt
            )
            break
        }
        return AIExamsSnapshot(upcoming: Array(rows.prefix(limit)), pastCount: past, plan: summary)
    }

    // MARK: Time

    static func time(
        sessions: [StudySession],
        subjects: [TimeInvestmentSubject],
        subTasks: [SubTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AITimeSnapshot {
        let completed = sessions.filter { $0.completed && $0.durationSeconds > 0 }
        guard !completed.isEmpty else { return .empty }
        let aggregator = TimeInvestmentAggregator(subjects: subjects, subTasks: subTasks, sessions: sessions)
        let weekly = aggregator.weekly(now: now, calendar: calendar)
        let focus = HomeInsightsEngine.weeklyFocus(sessions: sessions, now: now, days: 7, calendar: calendar)
        let projects = weekly.rows.map { AITimeProjectRow(id: $0.subject.id, name: $0.subject.name, seconds: $0.seconds) }
        return AITimeSnapshot(
            weekSeconds: weekly.totalSeconds,
            previousWeekSeconds: weekly.previousTotalSeconds,
            days: focus.days,
            projects: projects,
            streak: StudyStreakCalculator.currentStreak(sessions: sessions, now: now, calendar: calendar),
            unassignedCount: weekly.unassignedCount,
            completedSessionCount: completed.count
        )
    }

    // MARK: Health

    static func health(_ input: AIHealthInput) -> AIHealthSnapshot {
        guard input.hrvEnabled, input.onboardingCompleted else { return .disabled }
        guard input.isAuthorized else { return AIHealthSnapshot(state: .unauthorized) }
        if input.isLoading || input.readinessCategory == "loading" {
            return AIHealthSnapshot(state: .loading)
        }
        guard let score = input.recoveryScore else {
            return AIHealthSnapshot(state: .insufficient, readinessCategory: input.readinessCategory)
        }
        return AIHealthSnapshot(
            state: .available,
            recoveryScore: score,
            readinessCategory: input.readinessCategory,
            hrvZScore: input.hrvZScore,
            todayHRV: input.todayHRV,
            restingHeartRate: input.restingHeartRate,
            respiratoryRate: input.respiratoryRate,
            sleepHours: input.sleepHours,
            restorativeSleepHours: input.restorativeSleepHours,
            exerciseMinutes: input.exerciseMinutes
        )
    }

    // MARK: Diary

    static func diary(
        entries: [DiaryEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AIDiarySnapshot {
        guard let latestEntry = entries.max(by: { ($0.date, $0.updatedAt) < ($1.date, $1.updatedAt) }) else {
            return .empty
        }
        let excerptSource = latestEntry.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let latest = AIDiaryLatest(
            id: latestEntry.id,
            date: latestEntry.date,
            moodScore: latestEntry.moodScore,
            energyScore: latestEntry.energyScore,
            energyTag: latestEntry.energyTag,
            excerpt: String(excerptSource.prefix(160))
        )
        let series = HomeInsightsEngine.moodSeries(entries: entries, now: now, days: 14, calendar: calendar)
        let thirtyStart = calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        let recent = entries.filter { $0.date >= thirtyStart }
        let average: Double? = recent.isEmpty
            ? nil
            : recent.map { Double($0.moodScore) }.reduce(0, +) / Double(recent.count)
        return AIDiarySnapshot(
            latest: latest,
            moodSeries: series,
            averageMood: average,
            streak: diaryStreak(entries: entries, now: now, calendar: calendar),
            entryCount30: recent.count
        )
    }

    /// Consecutive days with at least one diary entry, ending today — or
    /// yesterday when today has no entry yet (so an unfinished day does not
    /// reset the streak).
    static func diaryStreak(
        entries: [DiaryEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let days = Set(entries.map { calendar.startOfDay(for: $0.date) })
        guard !days.isEmpty else { return 0 }
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
