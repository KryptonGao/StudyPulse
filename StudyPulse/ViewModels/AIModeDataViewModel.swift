//
//  AIModeDataViewModel.swift
//  StudyPulse
//
//  Owns the six data snapshots shown in AI Mode's data pages and sent as chat
//  context. Reads the phase-filtered repository paths (the same ones the
//  Trends / Mistakes / Todo pages use), never the unfiltered arrays.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class AIModeDataViewModel {

    struct SidebarMeta: Equatable {
        var subjectCount = 0
        var dueMistakeCount = 0
        var upcomingExamCount = 0
    }

    private let container: RepositoryContainer
    private let hrvManager: HealthKitManager

    private(set) var snapshot = AIStudyDataSnapshot()
    private(set) var meta = SidebarMeta()
    /// Page-level selection for the grades chart.
    var gradeRange: AIGradeRange = .days30

    init(container: RepositoryContainer, hrvManager: HealthKitManager) {
        self.container = container
        self.hrvManager = hrvManager
    }

    static func makeDefault(container: RepositoryContainer, hrvManager: HealthKitManager) -> AIModeDataViewModel {
        AIModeDataViewModel(container: container, hrvManager: hrvManager)
    }

    // MARK: Change detection

    /// Cheap signature of every input. Read inside a view body so Observation
    /// re-evaluates it when a repository changes; the view then calls `recompute()`.
    var inputSignature: Int {
        var hasher = Hasher()
        hasher.combine(container.envManager.activePhaseId)
        let grades = container.gradeRepo.filteredGrades
        hasher.combine(grades.count)
        for g in grades { hasher.combine(g.id); hasher.combine(g.score); hasher.combine(g.date) }
        let mistakes = container.mistakeRepo.filteredMistakeSets
        hasher.combine(mistakes.count)
        for m in mistakes {
            hasher.combine(m.id)
            hasher.combine(m.masteryScore)
            hasher.combine(m.reviewState?.nextReviewDate)
        }
        let exams = container.examRepo.filteredExamSets
        hasher.combine(exams.count)
        for e in exams { hasher.combine(e.id); hasher.combine(e.examDate); hasher.combine(e.masteryDegree) }
        hasher.combine(container.examRepo.filteredComprehensiveExamSets.count)
        let diary = container.diaryRepo.filteredDiaryEntries
        hasher.combine(diary.count)
        for d in diary { hasher.combine(d.id); hasher.combine(d.updatedAt) }
        let sessions = container.studySessionRepo.sessions
        hasher.combine(sessions.count)
        hasher.combine(sessions.last?.id)
        hasher.combine(container.timeInvestmentRepo.subjects.count)
        hasher.combine(container.examPlanRepo.plans.count)
        hasher.combine(hrvManager.hrvEnabled)
        hasher.combine(hrvManager.isAuthorized)
        hasher.combine(hrvManager.readiness.category.rawValue)
        hasher.combine(hrvManager.readiness.todayHRV)
        hasher.combine(hrvManager.bodyStatus.lastNightSleepHours)
        hasher.combine(hrvManager.bodyStatus.restingHeartRate)
        return hasher.finalize()
    }

    // MARK: Recompute

    func recompute(now: Date = Date()) {
        let calendar = Calendar.current
        let grades = container.gradeRepo.filteredGrades
        let mistakes = container.mistakeRepo.filteredMistakeSets
        let diary = container.diaryRepo.filteredDiaryEntries
        let phase = container.phaseRepo.activePhase
        let sessions = container.studySessionRepo.sessions
        let activePhaseId = container.envManager.activePhaseId

        var fullScores: [String: Double] = [:]
        for subject in Set(grades.map(\.subject)) {
            fullScores[subject] = container.fullScore(for: subject)
        }

        var next = AIStudyDataSnapshot()
        next.phaseName = phase?.name
        next.phaseId = activePhaseId
        next.generatedAt = now
        next.gradesByRange = AIStudyDataEngine.allGrades(
            grades: grades, fullScores: fullScores, targets: phase?.goals ?? [], now: now, calendar: calendar
        )
        next.mistakes = AIStudyDataEngine.mistakes(mistakes: mistakes, now: now, calendar: calendar)
        next.exams = AIStudyDataEngine.exams(
            entries: container.todoEntries(includeCompleted: true, phaseId: activePhaseId),
            goals: container.examPlanRepo.goals,
            plans: container.examPlanRepo.plans,
            activePhaseId: activePhaseId,
            now: now,
            calendar: calendar
        )
        next.time = AIStudyDataEngine.time(
            sessions: sessions,
            subjects: container.timeInvestmentRepo.subjects,
            subTasks: container.timeInvestmentRepo.subTasks,
            now: now,
            calendar: calendar
        )
        next.health = AIStudyDataEngine.health(healthInput(mistakes: mistakes, diary: diary, now: now))
        next.diary = AIStudyDataEngine.diary(entries: diary, now: now, calendar: calendar)
        snapshot = next

        meta = SidebarMeta(
            subjectCount: Set(grades.map(\.subject)).count,
            dueMistakeCount: next.mistakes.review.total,
            upcomingExamCount: next.exams.upcoming.count
        )
    }

    /// Same guard conditions as `HomeViewModel.computeRecoveryScore`.
    private func healthInput(mistakes: [MistakeNote], diary: [DiaryEntry], now: Date) -> AIHealthInput {
        let category = hrvManager.readiness.category
        let hrvUsable = category == .excellent || category == .normal || category == .low
        var score: Int?
        if hrvManager.hrvEnabled, hrvManager.hrvOnboardingCompleted, hrvManager.isAuthorized,
           hrvManager.bodyStatus.isUsable || hrvUsable {
            let calendar = Calendar.current
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
            let annotations = container.studySessionRepo
                .sessions(from: weekAgo, to: now)
                .flatMap { $0.difficultyAnnotations ?? [] }
            let recentMoods = diary.filter { $0.date >= calendar.startOfDay(for: weekAgo) }
            score = BodyRadarValues.compute(
                hrv: hrvManager.readiness,
                body: hrvManager.bodyStatus,
                baselines: hrvManager.personalBaselines,
                age: container.profileRepo.profile.age,
                mistakes: mistakes,
                recentAnnotations: annotations,
                recentMoodEntries: recentMoods
            ).recoveryScore
        }
        let body = hrvManager.bodyStatus
        return AIHealthInput(
            hrvEnabled: hrvManager.hrvEnabled,
            onboardingCompleted: hrvManager.hrvOnboardingCompleted,
            isAuthorized: hrvManager.isAuthorized,
            isLoading: false,
            readinessCategory: category.rawValue,
            hrvZScore: hrvManager.readiness.zScore,
            todayHRV: hrvManager.readiness.todayHRV,
            bodyUsable: body.isUsable,
            restingHeartRate: body.restingHeartRate,
            respiratoryRate: body.respiratoryRate,
            sleepHours: body.lastNightSleepHours,
            restorativeSleepHours: (body.deepSleepHours == nil && body.remSleepHours == nil)
                ? nil
                : (body.deepSleepHours ?? 0) + (body.remSleepHours ?? 0),
            exerciseMinutes: body.exerciseMinutesToday,
            recoveryScore: score
        )
    }

    // MARK: Record existence (for references to deleted data)

    func existingRecordIDs() -> Set<UUID> {
        var ids = Set<UUID>()
        container.mistakeRepo.mistakeSets.forEach { ids.insert($0.id) }
        container.examRepo.examSets.forEach { ids.insert($0.id) }
        container.examRepo.comprehensiveExamSets.forEach { ids.insert($0.id) }
        container.diaryRepo.diaryEntries.forEach { ids.insert($0.id) }
        container.timeInvestmentRepo.subjects.forEach { ids.insert($0.id) }
        container.gradeRepo.grades.forEach { ids.insert($0.id) }
        return ids
    }

    // MARK: Convenience for pages

    var currentGrades: AIGradesSnapshot { snapshot.grades(gradeRange) }
}
