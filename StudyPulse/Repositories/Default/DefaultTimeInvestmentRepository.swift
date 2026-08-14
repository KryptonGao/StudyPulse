import Foundation
import SwiftData
import os

@Observable @MainActor
final class DefaultTimeInvestmentRepository: TimeInvestmentRepository, PersistenceExecutorAttachable {
    private(set) var subjects: [TimeInvestmentSubject] = []
    private(set) var subTasks: [SubTask] = []
    private(set) var rewards: [GoalReward] = []
    private var context: ModelContext?
    @ObservationIgnored private var persistenceExecutor: PersistenceExecutor?
    private weak var sessionRepository: (any StudySessionRepository)?

    func attachPersistenceExecutor(_ executor: PersistenceExecutor) {
        persistenceExecutor = executor
    }

    func setSessionRepository(_ repository: any StudySessionRepository) {
        sessionRepository = repository
    }

    func loadAll(context: ModelContext) async {
        self.context = context
        let executor = persistenceExecutor ?? PersistenceExecutor(modelContainer: context.container)
        persistenceExecutor = executor
        do {
            let snapshots = try await executor.loadTimeInvestmentSnapshots()
            subjects = snapshots.subjects.sorted(by: Self.subjectSort)
            subTasks = snapshots.subTasks.sorted(by: Self.subTaskSort)
            rewards = snapshots.rewards.sorted { $0.createdAt < $1.createdAt }
        } catch is CancellationError {
            Log.data.debug("TimeInvestmentRepository startup load cancelled")
        } catch {
            subjects = []
            subTasks = []
            rewards = []
            Log.data.error("TimeInvestmentRepository load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func upsertSubject(_ subject: TimeInvestmentSubject) throws {
        guard let context else { return }
        if let index = subjects.firstIndex(where: { $0.id == subject.id }) {
            subjects[index] = subject
        } else {
            subjects.append(subject)
        }
        subjects.sort(by: Self.subjectSort)
        if let record = try context.fetch(FetchDescriptor<TimeInvestmentSubjectRecord>())
            .first(where: { $0.id == subject.id }) {
            record.apply(subject)
        } else {
            context.insert(TimeInvestmentSubjectRecord(from: subject))
        }
        try context.save()
    }

    func upsertSubTask(_ subTask: SubTask) throws {
        try validate(subTask)
        guard let context else { return }
        if let index = subTasks.firstIndex(where: { $0.id == subTask.id }) {
            subTasks[index] = subTask
        } else {
            subTasks.append(subTask)
        }
        subTasks.sort(by: Self.subTaskSort)
        if let record = try context.fetch(FetchDescriptor<SubTaskRecord>())
            .first(where: { $0.id == subTask.id }) {
            record.apply(subTask)
        } else {
            context.insert(SubTaskRecord(from: subTask))
        }
        try context.save()
    }

    func upsertReward(_ reward: GoalReward) throws {
        guard targetExists(reward.target) else {
            throw TimeInvestmentRepositoryError.invalidRewardTarget
        }
        guard let context else { return }
        if let index = rewards.firstIndex(where: { $0.id == reward.id }) {
            let existingUnlock = rewards[index].unlockedAt
            var permanent = reward
            permanent.unlockedAt = existingUnlock ?? reward.unlockedAt
            rewards[index] = permanent
        } else {
            rewards.append(reward)
        }
        if let value = rewards.first(where: { $0.id == reward.id }) {
            if let record = try context.fetch(FetchDescriptor<GoalRewardRecord>())
                .first(where: { $0.id == reward.id }) {
                record.apply(value)
            } else {
                context.insert(GoalRewardRecord(from: value))
            }
        }
        try context.save()
    }

    func archiveSubject(_ id: UUID, archived: Bool) {
        guard var subject = subjects.first(where: { $0.id == id }) else { return }
        subject.isArchived = archived
        try? upsertSubject(subject)
    }

    func archiveSubTask(_ id: UUID, archived: Bool) {
        guard var subTask = subTasks.first(where: { $0.id == id }) else { return }
        subTask.isArchived = archived
        try? upsertSubTask(subTask)
    }

    func deleteSubject(_ id: UUID) throws {
        let taskIDs = Set(subTasks.filter { $0.subjectID == id }.map(\.id))
        let hasSessions = sessionRepository?.sessions.contains { session in
            switch session.investmentTarget {
            case .subject(let subjectID): return subjectID == id
            case .subTask(let taskID): return taskIDs.contains(taskID)
            case nil: return false
            }
        } ?? false
        guard !subTasks.contains(where: { $0.subjectID == id }),
              !rewards.contains(where: { $0.target == .subject(id) }),
              !hasSessions else {
            throw TimeInvestmentRepositoryError.hasDependencies
        }
        guard let context else { return }
        if let record = try context.fetch(FetchDescriptor<TimeInvestmentSubjectRecord>())
            .first(where: { $0.id == id }) {
            context.delete(record)
        }
        try context.save()
        subjects.removeAll { $0.id == id }
    }

    func deleteSubTask(_ id: UUID) throws {
        let hasSessions = sessionRepository?.sessions.contains {
            $0.investmentTarget == .subTask(id)
        } ?? false
        guard !subTasks.contains(where: { $0.parentSubTaskID == id }),
              !rewards.contains(where: { $0.target == .subTask(id) }),
              !hasSessions else {
            throw TimeInvestmentRepositoryError.hasDependencies
        }
        guard let context else { return }
        if let record = try context.fetch(FetchDescriptor<SubTaskRecord>())
            .first(where: { $0.id == id }) {
            context.delete(record)
        }
        try context.save()
        subTasks.removeAll { $0.id == id }
    }

    func deleteReward(_ id: UUID) {
        guard let context else { return }
        if let record = try? context.fetch(FetchDescriptor<GoalRewardRecord>())
            .first(where: { $0.id == id }) {
            context.delete(record)
            try? context.save()
        }
        rewards.removeAll { $0.id == id }
    }

    @discardableResult
    func evaluateRewards(sessions: [StudySession], now: Date = .now) -> [GoalReward] {
        let result = GoalRewardEvaluator.evaluate(
            rewards: rewards,
            aggregator: TimeInvestmentAggregator(
                subjects: subjects,
                subTasks: subTasks,
                sessions: sessions
            ),
            now: now
        )
        guard !result.newlyUnlocked.isEmpty else { return [] }
        rewards = result.rewards
        for reward in result.newlyUnlocked {
            try? upsertReward(reward)
        }
        return result.newlyUnlocked
    }

    private func validate(_ candidate: SubTask) throws {
        guard subjects.contains(where: { $0.id == candidate.subjectID }) else {
            throw TimeInvestmentRepositoryError.subjectNotFound
        }
        guard candidate.parentSubTaskID != candidate.id else {
            throw TimeInvestmentRepositoryError.invalidHierarchy
        }
        var map = Dictionary(uniqueKeysWithValues: subTasks.map { ($0.id, $0) })
        map[candidate.id] = candidate
        var depth = 1
        var seen: Set<UUID> = [candidate.id]
        var parentID = candidate.parentSubTaskID
        while let id = parentID {
            guard let parent = map[id], parent.subjectID == candidate.subjectID else {
                throw TimeInvestmentRepositoryError.parentNotFound
            }
            guard seen.insert(id).inserted else {
                throw TimeInvestmentRepositoryError.invalidHierarchy
            }
            depth += 1
            guard depth <= 2 else {
                throw TimeInvestmentRepositoryError.invalidHierarchy
            }
            parentID = parent.parentSubTaskID
        }
    }

    private func targetExists(_ target: InvestmentTarget) -> Bool {
        switch target {
        case .subject(let id): return subjects.contains { $0.id == id }
        case .subTask(let id): return subTasks.contains { $0.id == id }
        }
    }

    private static func subjectSort(_ lhs: TimeInvestmentSubject, _ rhs: TimeInvestmentSubject) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.createdAt < rhs.createdAt
    }

    private static func subTaskSort(_ lhs: SubTask, _ rhs: SubTask) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.createdAt < rhs.createdAt
    }
}
