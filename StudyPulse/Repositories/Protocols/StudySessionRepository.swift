import Foundation
import SwiftData

@MainActor
protocol StudySessionRepository: AnyObject, Sendable {
    var sessions: [StudySession] { get }
    /// Bounded list-facing metadata. The values contain no telemetry arrays.
    var sessionSummaries: [StudySessionSummary] { get }
    var totalSessionCount: Int { get }
    func loadAll(context: ModelContext) async
    func upsert(_ session: StudySession)
    func delete(_ id: UUID)
    func assign(_ ids: Set<UUID>, to target: InvestmentTarget?)
    func session(id: UUID) -> StudySession?
    func sessions(from startDate: Date, to endDate: Date?) -> [StudySession]
    func allSessionsForBackup() -> [StudySession]
    func refreshFromLegacyJSON()
}
