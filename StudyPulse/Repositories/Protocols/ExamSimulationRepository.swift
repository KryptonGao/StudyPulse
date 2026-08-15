import Foundation
import SwiftData

@MainActor
protocol ExamSimulationRepository: AnyObject, Sendable {
    var simulations: [ExamSimulation] { get }
    func loadAll(context: ModelContext) async
    func upsert(_ simulation: ExamSimulation)
    func delete(_ simulation: ExamSimulation)
    func simulation(id: UUID) -> ExamSimulation?
    func latestRunningSimulation() -> ExamSimulation?
    func recentCompleted(limit: Int) -> [ExamSimulation]
    func recentAnalyzed(limit: Int) -> [ExamSimulation]
}

extension ExamSimulationRepository {
    var latest: ExamSimulation? {
        simulations.max { $0.createdAt < $1.createdAt }
    }

    var analyzedSimulations: [ExamSimulation] {
        recentAnalyzed(limit: 50)
    }
}
