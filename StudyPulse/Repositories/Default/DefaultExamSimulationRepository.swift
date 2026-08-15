import Foundation
import SwiftData

@Observable @MainActor
final class DefaultExamSimulationRepository: ExamSimulationRepository {
    private(set) var simulations: [ExamSimulation] = []
    private var context: ModelContext?

    func loadAll(context: ModelContext) async {
        self.context = context
        let descriptor = FetchDescriptor<ExamSimulationRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        var bounded = descriptor
        bounded.fetchLimit = 50
        let records = (try? context.fetch(bounded)) ?? []
        var didBackfill = false
        simulations = records.compactMap { record in
            let needsBackfill = record.subject == nil || record.statusRaw == nil || record.questionCount == nil
            guard let summary = record.toSummary() else { return nil }
            guard needsBackfill else { return summary }
            record.subject = summary.subject
            record.startedAt = summary.startedAt
            record.endedAt = summary.endedAt
            record.durationSeconds = summary.durationSeconds
            record.statusRaw = summary.status.rawValue
            record.totalScore = summary.totalScore
            if let full = record.toSnapshot() {
                record.questionCount = full.questionRecords.count
                record.answeredCount = full.answeredCount
                record.hasAnalysis = full.analysis != nil
            }
            didBackfill = true
            return summary
        }
        if didBackfill { try? context.save() }
    }

    func upsert(_ simulation: ExamSimulation) {
        guard let context else { return }
        if let record = (try? context.fetch(FetchDescriptor<ExamSimulationRecord>(
            predicate: #Predicate { $0.id == simulation.id }
        )))?.first {
            record.createdAt = simulation.createdAt
            record.subject = simulation.subject
            record.startedAt = simulation.startedAt
            record.endedAt = simulation.endedAt
            record.durationSeconds = simulation.durationSeconds
            record.statusRaw = simulation.status.rawValue
            record.totalScore = simulation.totalScore
            record.questionCount = simulation.questionRecords.count
            record.answeredCount = simulation.answeredCount
            record.hasAnalysis = simulation.analysis != nil
            record.payload = (try? JSONEncoder().encode(simulation)) ?? Data()
        } else {
            context.insert(ExamSimulationRecord(from: simulation))
        }
        try? context.save()

        if let index = simulations.firstIndex(where: { $0.id == simulation.id }) {
            simulations[index] = simulation
        } else {
            simulations.append(simulation)
        }
        simulations.sort { $0.createdAt > $1.createdAt }
        if simulations.count > 50 { simulations = Array(simulations.prefix(50)) }
    }

    func simulation(id: UUID) -> ExamSimulation? {
        guard let context,
              let record = (try? context.fetch(
                FetchDescriptor<ExamSimulationRecord>(predicate: #Predicate { $0.id == id })
              ))?.first else { return nil }
        return record.toSnapshot()
    }

    func latestRunningSimulation() -> ExamSimulation? {
        guard let context else {
            return simulations.first(where: { $0.status == .running })
        }
        var descriptor = FetchDescriptor<ExamSimulationRecord>(
            predicate: #Predicate { $0.statusRaw == "running" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.toSnapshot()
    }

    func recentCompleted(limit: Int) -> [ExamSimulation] {
        fetchFull(limit: limit) { status in
            status != .preparing && status != .running
        }
    }

    func recentAnalyzed(limit: Int) -> [ExamSimulation] {
        fetchFull(limit: limit) { status in
            status != .preparing && status != .running
        }.filter { $0.analysis != nil && $0.isValidCompletedSession }
    }

    private func fetchFull(
        limit: Int,
        matching: (ExamSimulationStatus) -> Bool
    ) -> [ExamSimulation] {
        guard let context else {
            return simulations.filter { matching($0.status) }.prefix(max(0, limit)).map { $0 }
        }
        var descriptor = FetchDescriptor<ExamSimulationRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // Fetch a small metadata window; only completed candidates are then
        // hydrated and decoded below.
        descriptor.fetchLimit = max(50, limit)
        let records = (try? context.fetch(descriptor)) ?? []
        var result: [ExamSimulation] = []
        for record in records {
            guard result.count < max(0, limit) else { break }
            let status: ExamSimulationStatus?
            if let raw = record.statusRaw {
                status = ExamSimulationStatus(rawValue: raw)
            } else {
                status = record.toSnapshot()?.status
            }
            guard let status, matching(status), let snapshot = record.toSnapshot() else { continue }
            result.append(snapshot)
        }
        return result
    }

    func delete(_ simulation: ExamSimulation) {
        simulations.removeAll { $0.id == simulation.id }
        guard let context,
              let record = (try? context.fetch(FetchDescriptor<ExamSimulationRecord>(
                predicate: #Predicate { $0.id == simulation.id }
              )))?.first else { return }
        context.delete(record)
        try? context.save()
    }
}
