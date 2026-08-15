import Foundation
import SwiftData

@MainActor
protocol ExamPlanRepository: AnyObject, Sendable {
    var goals: [ExamGoal] { get }
    var plans: [ExamPlan] { get }
    func loadAll(context: ModelContext) async
    func upsertGoal(_ goal: ExamGoal)
    func deleteGoal(_ goal: ExamGoal)
    func upsertPlan(_ plan: ExamPlan)
    func deletePlan(_ plan: ExamPlan)
    func plan(id: UUID) -> ExamPlan?
    func latestPlan(for goalID: UUID) -> ExamPlan?
}

extension ExamPlanRepository {
    func plans(for goalID: UUID) -> [ExamPlan] {
        plans
            .filter { $0.examGoalID == goalID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // `latestPlan(for:)` is a repository requirement so it can hydrate the
    // selected plan by ID instead of relying on a startup payload snapshot.
}
