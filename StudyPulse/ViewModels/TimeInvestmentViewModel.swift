//
//  TimeInvestmentViewModel.swift
//  StudyPulse
//

import Foundation
import Combine

@MainActor
final class TimeInvestmentViewModel: ObservableObject {
    struct ProjectSummary: Identifiable, Equatable {
        let subject: TimeInvestmentSubject
        let totalSeconds: Int
        let streak: Int
        var id: UUID { subject.id }
    }

    @Published private(set) var projects: [ProjectSummary] = []
    @Published private(set) var subTasks: [SubTask] = []
    @Published private(set) var rewards: [GoalReward] = []
    @Published private(set) var unassignedSessions: [StudySession] = []
    @Published private(set) var totalAssignedSeconds = 0
    @Published private(set) var globalStreak = 0
    @Published private(set) var newlyUnlockedReward: GoalReward?
    @Published private(set) var errorMessage: String?

    private let container: RepositoryContainer

    init(container: RepositoryContainer) {
        self.container = container
        recompute()
    }

    static func makeDefault(container: RepositoryContainer) -> TimeInvestmentViewModel {
        TimeInvestmentViewModel(container: container)
    }

    var activeSubjects: [TimeInvestmentSubject] {
        container.timeInvestmentRepo.subjects.filter { !$0.isArchived }
    }

    var activeTargets: [InvestmentTarget] {
        let subjectTargets = activeSubjects.map { InvestmentTarget.subject($0.id) }
        let taskTargets = container.timeInvestmentRepo.subTasks
            .filter { task in
                !task.isArchived
                    && activeSubjects.contains(where: { $0.id == task.subjectID })
            }
            .map { InvestmentTarget.subTask($0.id) }
        return subjectTargets + taskTargets
    }

    func recompute(now: Date = .now) {
        let repo = container.timeInvestmentRepo
        let sessions = container.studySessionRepo.sessions
        let aggregator = TimeInvestmentAggregator(
            subjects: repo.subjects,
            subTasks: repo.subTasks,
            sessions: sessions
        )
        projects = repo.subjects
            .filter { !$0.isArchived }
            .map { subject in
                let target = InvestmentTarget.subject(subject.id)
                let targetSessions = aggregator.sessions(for: target)
                return ProjectSummary(
                    subject: subject,
                    totalSeconds: aggregator.totalSeconds(for: target),
                    streak: StudyStreakCalculator.currentStreak(
                        sessions: targetSessions,
                        now: now
                    )
                )
            }
        subTasks = repo.subTasks.filter { !$0.isArchived }
        rewards = repo.rewards
        unassignedSessions = aggregator.unassignedSessions.sorted { $0.startDate > $1.startDate }
        totalAssignedSeconds = aggregator.totalAssignedSeconds
        globalStreak = StudyStreakCalculator.currentStreak(
            sessions: sessions.filter { $0.investmentTarget != nil },
            now: now
        )
    }

    func children(of parentID: UUID?, subjectID: UUID) -> [SubTask] {
        subTasks
            .filter { $0.subjectID == subjectID && $0.parentSubTaskID == parentID }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt < $1.createdAt
            }
    }

    func totalSeconds(for target: InvestmentTarget) -> Int {
        aggregator.totalSeconds(for: target)
    }

    func sessions(for target: InvestmentTarget) -> [StudySession] {
        aggregator.sessions(for: target).sorted { $0.startDate > $1.startDate }
    }

    func streak(for target: InvestmentTarget) -> Int {
        StudyStreakCalculator.currentStreak(sessions: aggregator.sessions(for: target))
    }

    func displayName(for target: InvestmentTarget) -> String {
        switch target {
        case .subject(let id):
            return container.timeInvestmentRepo.subjects.first(where: { $0.id == id })?.name
                ?? "time.investment.unknownProject".localized()
        case .subTask(let id):
            return container.timeInvestmentRepo.subTasks.first(where: { $0.id == id })?.name
                ?? "time.investment.unknownProject".localized()
        }
    }

    func theme(for target: InvestmentTarget) -> TimeInvestmentTheme {
        switch target {
        case .subject(let id):
            return container.timeInvestmentRepo.subjects.first(where: { $0.id == id })?.theme ?? .ocean
        case .subTask(let id):
            guard let subjectID = container.timeInvestmentRepo.subTasks
                .first(where: { $0.id == id })?.subjectID else { return .ocean }
            return container.timeInvestmentRepo.subjects.first(where: { $0.id == subjectID })?.theme ?? .ocean
        }
    }

    func saveSubject(_ subject: TimeInvestmentSubject) {
        perform {
            try container.timeInvestmentRepo.upsertSubject(subject)
        }
    }

    func saveSubTask(_ subTask: SubTask) {
        perform {
            try container.timeInvestmentRepo.upsertSubTask(subTask)
        }
    }

    func saveReward(_ reward: GoalReward) {
        perform {
            try container.timeInvestmentRepo.upsertReward(reward)
            evaluateRewards()
        }
    }

    func archiveSubject(_ id: UUID) {
        container.timeInvestmentRepo.archiveSubject(id, archived: true)
        recompute()
    }

    func archiveSubTask(_ id: UUID) {
        container.timeInvestmentRepo.archiveSubTask(id, archived: true)
        recompute()
    }

    func deleteReward(_ id: UUID) {
        container.timeInvestmentRepo.deleteReward(id)
        recompute()
    }

    func recordManual(
        target: InvestmentTarget,
        startDate: Date,
        durationMinutes: Int
    ) {
        guard durationMinutes >= 1, activeTargets.contains(target) else {
            errorMessage = "time.investment.error.manualSession".localized()
            return
        }
        let session = StudySession(
            id: UUID(),
            startDate: startDate,
            durationSeconds: durationMinutes * 60,
            intensity: .steady,
            completed: true,
            investmentTarget: target,
            source: .manual,
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
        )
        container.studySessionRepo.upsert(session)
        evaluateRewards()
        recompute()
    }

    func saveSession(
        existing: StudySession?,
        target: InvestmentTarget,
        startDate: Date,
        durationMinutes: Int
    ) {
        guard durationMinutes >= 1, activeTargets.contains(target) else {
            errorMessage = "time.investment.error.manualSession".localized()
            return
        }
        let hydrated = existing.flatMap { container.studySessionRepo.session(id: $0.id) } ?? existing
        let session = StudySession(
            id: hydrated?.id ?? UUID(),
            startDate: startDate,
            durationSeconds: durationMinutes * 60,
            intensity: hydrated?.intensity ?? .steady,
            completed: true,
            heartRateSamples: hydrated?.heartRateSamples,
            difficultyAnnotations: hydrated?.difficultyAnnotations,
            investmentTarget: target,
            source: hydrated?.source ?? .manual,
            timeZoneIdentifier: hydrated?.timeZoneIdentifier
                ?? TimeZone.autoupdatingCurrent.identifier
        )
        container.studySessionRepo.upsert(session)
        evaluateRewards()
        recompute()
    }

    func assign(sessionIDs: Set<UUID>, to target: InvestmentTarget?) {
        container.studySessionRepo.assign(sessionIDs, to: target)
        evaluateRewards()
        recompute()
    }

    func deleteSession(_ id: UUID) {
        container.studySessionRepo.delete(id)
        evaluateRewards()
        recompute()
    }

    func updateSession(_ session: StudySession, target: InvestmentTarget) {
        let hydrated = container.studySessionRepo.session(id: session.id) ?? session
        let updated = StudySession(
            id: hydrated.id,
            startDate: hydrated.startDate,
            durationSeconds: hydrated.durationSeconds,
            intensity: hydrated.intensity,
            completed: hydrated.completed,
            heartRateSamples: hydrated.heartRateSamples,
            difficultyAnnotations: hydrated.difficultyAnnotations,
            investmentTarget: target,
            source: hydrated.source,
            timeZoneIdentifier: hydrated.timeZoneIdentifier
        )
        container.studySessionRepo.upsert(updated)
        evaluateRewards()
        recompute()
    }

    func clearError() {
        errorMessage = nil
    }

    func clearUnlockPresentation() {
        newlyUnlockedReward = nil
    }

    private var aggregator: TimeInvestmentAggregator {
        TimeInvestmentAggregator(
            subjects: container.timeInvestmentRepo.subjects,
            subTasks: container.timeInvestmentRepo.subTasks,
            sessions: container.studySessionRepo.sessions
        )
    }

    private func evaluateRewards() {
        let unlocked = container.timeInvestmentRepo.evaluateRewards(
            sessions: container.studySessionRepo.sessions,
            now: .now
        )
        newlyUnlockedReward = unlocked.first
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            recompute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
