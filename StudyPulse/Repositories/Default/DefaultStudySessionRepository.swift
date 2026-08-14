import Foundation
import SwiftData
import os

@Observable @MainActor
final class DefaultStudySessionRepository: StudySessionRepository, PersistenceExecutorAttachable {
    private(set) var sessions: [StudySession] = []
    private var context: ModelContext?
    @ObservationIgnored private var persistenceExecutor: PersistenceExecutor?

    func attachPersistenceExecutor(_ executor: PersistenceExecutor) {
        persistenceExecutor = executor
    }

    func loadAll(context: ModelContext) async {
        self.context = context
        let executor = persistenceExecutor ?? PersistenceExecutor(modelContainer: context.container)
        persistenceExecutor = executor
        do {
            sessions = try await executor.loadStudySessionSnapshots()
        } catch is CancellationError {
            Log.data.debug("StudySessionRepository startup load cancelled")
        } catch {
            sessions = []
            Log.data.error("StudySessionRepository load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func upsert(_ session: StudySession) {
        guard let context else { return }
        if let record = (try? context.fetch(FetchDescriptor<StudySessionRecord>()))?.first(where: { $0.id == session.id }) {
            record.startDate = session.startDate
            record.payload = (try? JSONEncoder().encode(session)) ?? Data()
        } else { context.insert(StudySessionRecord(from: session)) }
        try? context.save()
        if let i = sessions.firstIndex(where: { $0.id == session.id }) { sessions[i] = session }
        else { sessions.append(session) }
        sessions.sort { $0.startDate > $1.startDate }
    }

    func delete(_ id: UUID) {
        guard let context else { return }
        if let record = (try? context.fetch(FetchDescriptor<StudySessionRecord>()))?
            .first(where: { $0.id == id }) {
            context.delete(record)
            try? context.save()
        }
        sessions.removeAll { $0.id == id }
    }

    func assign(_ ids: Set<UUID>, to target: InvestmentTarget?) {
        guard !ids.isEmpty else { return }
        for session in sessions where ids.contains(session.id) {
            upsert(
                StudySession(
                    id: session.id,
                    startDate: session.startDate,
                    durationSeconds: session.durationSeconds,
                    intensity: session.intensity,
                    completed: session.completed,
                    heartRateSamples: session.heartRateSamples,
                    difficultyAnnotations: session.difficultyAnnotations,
                    investmentTarget: target,
                    source: session.source,
                    timeZoneIdentifier: session.timeZoneIdentifier
                )
            )
        }
    }

    func session(id: UUID) -> StudySession? {
        sessions.first { $0.id == id }
    }

    func refreshFromLegacyJSON() {
        guard let context else { return }
        mergeLegacyJSONIfNeeded(context: context, force: true)
        reload(context: context)
    }

    private func reload(context: ModelContext) {
        let descriptor = FetchDescriptor<StudySessionRecord>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        sessions = ((try? context.fetch(descriptor)) ?? []).compactMap { $0.toSnapshot() }
    }

    private func mergeLegacyJSONIfNeeded(context: ModelContext, force: Bool = false) {
        let key = "studyPulse.studySessionsLegacyMigrationV2"
        guard force || !UserDefaults.standard.bool(forKey: key) else { return }
        let existing = (try? context.fetch(FetchDescriptor<StudySessionRecord>())) ?? []
        let existingIDs = Set(existing.map(\.id))
        for session in StudySessionStore.load() where !existingIDs.contains(session.id) {
            context.insert(StudySessionRecord(from: session))
        }
        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            Log.data.error("Legacy study-session merge failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
