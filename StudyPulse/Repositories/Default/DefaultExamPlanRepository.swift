import Foundation
import SwiftData

@Observable @MainActor
final class DefaultExamPlanRepository: ExamPlanRepository {
    private(set) var goals: [ExamGoal] = []
    private(set) var plans: [ExamPlan] = []
    private var context: ModelContext?

    func loadAll(context: ModelContext) async {
        self.context = context
        let goalDescriptor = FetchDescriptor<ExamGoalRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let planDescriptor = FetchDescriptor<ExamPlanRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        var boundedPlanDescriptor = planDescriptor
        boundedPlanDescriptor.fetchLimit = 50
        let goalRecords = (try? context.fetch(goalDescriptor)) ?? []
        var didBackfill = false
        goals = goalRecords.compactMap { record in
            let needsBackfill = record.examName == nil || record.examDate == nil
            guard let summary = record.toSummary() else { return nil }
            guard needsBackfill else { return summary }
            record.examName = summary.examName
            record.subject = summary.subject
            record.examDate = summary.examDate
            record.currentScore = summary.currentScore
            record.targetScore = summary.targetScore
            record.fullScore = summary.fullScore
            record.phaseId = summary.phaseId
            didBackfill = true
            return summary
        }
        let planRecords = (try? context.fetch(boundedPlanDescriptor)) ?? []
        plans = planRecords.compactMap { record in
            let needsBackfill = record.improvementTarget == nil || record.summary == nil
            guard let summary = record.toSummary() else { return nil }
            guard needsBackfill else { return summary }
            record.improvementTarget = summary.improvementTarget
            record.summary = summary.summary
            record.modelInfo = summary.modelInfo
            didBackfill = true
            return summary
        }
        if didBackfill { try? context.save() }
    }

    func upsertGoal(_ goal: ExamGoal) {
        guard let context else { return }
        if let record = (try? context.fetch(FetchDescriptor<ExamGoalRecord>(
            predicate: #Predicate { $0.id == goal.id }
        )))?.first {
            record.createdAt = goal.createdAt
            record.examName = goal.examName
            record.subject = goal.subject
            record.examDate = goal.examDate
            record.currentScore = goal.currentScore
            record.targetScore = goal.targetScore
            record.fullScore = goal.fullScore
            record.phaseId = goal.phaseId
            record.payload = (try? JSONEncoder().encode(goal)) ?? Data()
        } else {
            context.insert(ExamGoalRecord(from: goal))
        }
        try? context.save()

        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index] = goal
        } else {
            goals.append(goal)
        }
        goals.sort { $0.createdAt > $1.createdAt }
    }

    func deleteGoal(_ goal: ExamGoal) {
        plans.removeAll { $0.examGoalID == goal.id }
        goals.removeAll { $0.id == goal.id }
        guard let context else { return }

        let goalRecords = (try? context.fetch(FetchDescriptor<ExamGoalRecord>(
            predicate: #Predicate { $0.id == goal.id }
        ))) ?? []
        goalRecords.forEach(context.delete)
        let planRecords = (try? context.fetch(FetchDescriptor<ExamPlanRecord>(
            predicate: #Predicate { $0.examGoalID == goal.id }
        ))) ?? []
        planRecords.forEach(context.delete)
        try? context.save()
    }

    func upsertPlan(_ plan: ExamPlan) {
        guard let context else { return }
        if let record = (try? context.fetch(FetchDescriptor<ExamPlanRecord>(
            predicate: #Predicate { $0.id == plan.id }
        )))?.first {
            record.examGoalID = plan.examGoalID
            record.createdAt = plan.createdAt
            record.improvementTarget = plan.improvementTarget
            record.summary = plan.summary
            record.modelInfo = plan.modelInfo
            record.payload = (try? JSONEncoder().encode(plan)) ?? Data()
        } else {
            context.insert(ExamPlanRecord(from: plan))
        }
        try? context.save()

        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        } else {
            plans.append(plan)
        }
        plans.sort { $0.createdAt > $1.createdAt }
        if plans.count > 50 { plans = Array(plans.prefix(50)) }
    }

    func deletePlan(_ plan: ExamPlan) {
        plans.removeAll { $0.id == plan.id }
        guard let context,
              let record = (try? context.fetch(FetchDescriptor<ExamPlanRecord>(
                predicate: #Predicate { $0.id == plan.id }
              )))?.first else { return }
        context.delete(record)
        try? context.save()
    }

    func plan(id: UUID) -> ExamPlan? {
        guard let context,
              let record = (try? context.fetch(
                FetchDescriptor<ExamPlanRecord>(predicate: #Predicate { $0.id == id })
              ))?.first else { return nil }
        return record.toSnapshot()
    }

    func latestPlan(for goalID: UUID) -> ExamPlan? {
        guard let context else {
            return plans.filter { $0.examGoalID == goalID }.max { $0.createdAt < $1.createdAt }
        }
        var descriptor = FetchDescriptor<ExamPlanRecord>(
            predicate: #Predicate { $0.examGoalID == goalID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.toSnapshot()
    }
}
