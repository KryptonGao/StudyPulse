import Foundation
import SwiftData
import os

@Observable @MainActor
final class DefaultStudySessionRepository: StudySessionRepository, PersistenceExecutorAttachable {
    private(set) var sessions: [StudySession] = []
    private(set) var sessionSummaries: [StudySessionSummary] = []
    private(set) var totalSessionCount = 0
    private var context: ModelContext?
    private var detailedSessions: [UUID: StudySession] = [:]
    @ObservationIgnored private var persistenceExecutor: PersistenceExecutor?

    func attachPersistenceExecutor(_ executor: PersistenceExecutor) {
        persistenceExecutor = executor
    }

    func loadAll(context: ModelContext) async {
        self.context = context
        let executor = persistenceExecutor ?? PersistenceExecutor(modelContainer: context.container)
        persistenceExecutor = executor
        do {
            let summaries = try await executor.loadStudySessionSnapshots()
            sessionSummaries = summaries
            sessions = summaries.map { $0.asSession() }
            totalSessionCount = (try? context.fetchCount(FetchDescriptor<StudySessionRecord>())) ?? summaries.count
            detailedSessions = [:]
        } catch is CancellationError {
            Log.data.debug("StudySessionRepository startup load cancelled")
        } catch {
            sessions = []
            sessionSummaries = []
            totalSessionCount = 0
            Log.data.error("StudySessionRepository load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func upsert(_ session: StudySession) {
        guard let context else { return }
        if let record = (try? context.fetch(FetchDescriptor<StudySessionRecord>(
            predicate: #Predicate { $0.id == session.id }
        )))?.first {
            record.startDate = session.startDate
            record.durationSeconds = session.durationSeconds
            record.intensityRaw = session.intensity.rawValue
            record.completed = session.completed
            record.investmentTargetKindRaw = session.investmentTarget?.kindRawValue
            record.investmentTargetID = session.investmentTarget?.rawID
            record.sourceRaw = session.source.rawValue
            record.timeZoneIdentifier = session.timeZoneIdentifier
            record.heartRateSampleCount = session.heartRateSamples?.count ?? 0
            record.difficultyAnnotationCount = session.difficultyAnnotations?.count ?? 0
            record.payload = (try? JSONEncoder().encode(session)) ?? Data()
        } else { context.insert(StudySessionRecord(from: session)) }
        try? context.save()
        detailedSessions[session.id] = session
        let summary = StudySessionSummary(from: session)
        if let i = sessionSummaries.firstIndex(where: { $0.id == session.id }) {
            sessionSummaries[i] = summary
            sessions[i] = session
        } else {
            sessionSummaries.append(summary)
            sessions.append(session)
            totalSessionCount += 1
        }
        sessionSummaries.sort { $0.startDate > $1.startDate }
        sessions.sort { $0.startDate > $1.startDate }
    }

    func delete(_ id: UUID) {
        guard let context else { return }
        if let record = (try? context.fetch(FetchDescriptor<StudySessionRecord>(
            predicate: #Predicate { $0.id == id }
        )))?.first {
            context.delete(record)
            try? context.save()
        }
        sessions.removeAll { $0.id == id }
        sessionSummaries.removeAll { $0.id == id }
        detailedSessions.removeValue(forKey: id)
        totalSessionCount = max(0, totalSessionCount - 1)
    }

    func assign(_ ids: Set<UUID>, to target: InvestmentTarget?) {
        guard !ids.isEmpty else { return }
        for id in ids {
            guard let session = session(id: id) else { continue }
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
        if let detailed = detailedSessions[id] { return detailed }
        guard let context,
              let record = (try? context.fetch(
                FetchDescriptor<StudySessionRecord>(predicate: #Predicate { $0.id == id })
              ))?.first,
              let result = record.toSnapshot() else { return nil }
        detailedSessions[id] = result
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index] = result
        }
        return result
    }

    func sessions(from startDate: Date, to endDate: Date?) -> [StudySession] {
        guard let context else {
            return sessions.filter { $0.startDate >= startDate && (endDate == nil || $0.startDate < endDate!) }
        }
        var descriptor: FetchDescriptor<StudySessionRecord>
        if let endDate {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.startDate >= startDate && $0.startDate < endDate },
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.startDate >= startDate },
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
        }
        let result = (try? context.fetch(descriptor))?.compactMap { $0.toSnapshot() } ?? []
        result.forEach { detailedSessions[$0.id] = $0 }
        return result
    }

    func allSessionsForBackup() -> [StudySession] {
        guard let context else { return sessions }
        return (try? context.fetch(FetchDescriptor<StudySessionRecord>()))?.compactMap { $0.toSnapshot() } ?? []
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
        var bounded = descriptor
        bounded.fetchLimit = 365
        let records = ((try? context.fetch(bounded)) ?? [])
        sessionSummaries = records.compactMap { $0.toSummary() }
        sessions = sessionSummaries.map { $0.asSession() }
        totalSessionCount = (try? context.fetchCount(FetchDescriptor<StudySessionRecord>())) ?? records.count
        detailedSessions = [:]
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
