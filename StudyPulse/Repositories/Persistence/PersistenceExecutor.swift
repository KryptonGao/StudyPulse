//
//  PersistenceExecutor.swift
//  StudyPulse
//
//  Phase 5 SwiftData execution boundary.
//

import Foundation
import SwiftData
import os

/// Immutable startup payload produced entirely inside the persistence boundary.
/// No `@Model` instance or `ModelContext` crosses this boundary.
nonisolated struct HighFrequencySnapshots: Sendable {
    let grades: [Grade]
    let filteredGrades: [Grade]
    let mistakes: [MistakeNote]
    let filteredMistakes: [MistakeNote]
    let exams: [Exam]
    let filteredExams: [Exam]
    let comprehensiveExams: [comprehensiveExam]
    let filteredComprehensiveExams: [comprehensiveExam]
    let tasks: [TaskItem]
    let filteredTasks: [TaskItem]
}

/// Startup snapshots for the AI Coach history domain.
/// No SwiftData model or `ModelContext` crosses the repository boundary.
nonisolated struct CoachSnapshots: Sendable {
    let goals: [CoachGoal]
    let analyses: [CoachAnalysis]
    let proposals: [CoachProposal]
    let chats: [CoachChat]
    let messages: [CoachConversationMessage]
}

/// Startup snapshots for the long-term time-investment domain.
/// No SwiftData model or `ModelContext` crosses the repository boundary.
nonisolated struct TimeInvestmentSnapshots: Sendable {
    let subjects: [TimeInvestmentSubject]
    let subTasks: [SubTask]
    let rewards: [GoalReward]
}

enum PersistenceDomain: String, Sendable {
    case grades
    case mistakes
    case exams
    case tasks
}

/// The write execution boundary used by the high-frequency repositories. It
/// intentionally reuses `ModelContainer.mainContext` so every repository
/// mutation is serialized with repositories that perform synchronous
/// MainActor CRUD. A few low-frequency startup readers may still use private,
/// read-only contexts.
///
/// Repositories and views only receive value snapshots; persistent models do
/// not escape this boundary.
@MainActor
final class PersistenceExecutor {
    nonisolated static let defaultReadBatchSize = 500
    nonisolated static let defaultWriteBatchSize = 500

    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.chenkai.gao.studypulse",
        category: "Persistence"
    )

    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = modelContainer.mainContext
    }

    // MARK: - Startup reads

    func loadHighFrequencySnapshots(
        activePhaseID: UUID? = nil,
        readBatchSize: Int = defaultReadBatchSize
    ) async throws -> HighFrequencySnapshots {
        let interval = Self.signposter.beginInterval("loadHighFrequencySnapshots")
        defer { Self.signposter.endInterval("loadHighFrequencySnapshots", interval) }

        let grades = try await fetchGrades(batchSize: readBatchSize)
        let mistakes = try await fetchMistakes(batchSize: readBatchSize)
        let exams = try await fetchExams(batchSize: readBatchSize)
        let comprehensiveExams = try await fetchComprehensiveExams(batchSize: readBatchSize)
        let tasks = try await fetchTasks(batchSize: readBatchSize)

        let filteredGrades = activePhaseID == nil
            ? grades
            : try await fetchGrades(activePhaseID: activePhaseID, batchSize: readBatchSize)
        let filteredMistakes = activePhaseID == nil
            ? mistakes
            : try await fetchMistakes(activePhaseID: activePhaseID, batchSize: readBatchSize)
        let filteredExams = activePhaseID == nil
            ? exams
            : try await fetchExams(activePhaseID: activePhaseID, batchSize: readBatchSize)
        let filteredComprehensiveExams = activePhaseID == nil
            ? comprehensiveExams
            : try await fetchComprehensiveExams(activePhaseID: activePhaseID, batchSize: readBatchSize)
        let filteredTasks = activePhaseID == nil
            ? tasks
            : try await fetchTasks(activePhaseID: activePhaseID, batchSize: readBatchSize)

        return HighFrequencySnapshots(
            grades: grades,
            filteredGrades: filteredGrades,
            mistakes: mistakes,
            filteredMistakes: filteredMistakes,
            exams: exams,
            filteredExams: filteredExams,
            comprehensiveExams: comprehensiveExams,
            filteredComprehensiveExams: filteredComprehensiveExams,
            tasks: tasks,
            filteredTasks: filteredTasks
        )
    }

    func fetchGrades(batchSize: Int = defaultReadBatchSize) async throws -> [Grade] {
        try pagedFetch(
            FetchDescriptor<GradeRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]),
            batchSize: batchSize,
            transform: { $0.toSnapshot() }
        )
    }

    func fetchGrades(activePhaseID: UUID?, batchSize: Int = defaultReadBatchSize) async throws -> [Grade] {
        var descriptor = FetchDescriptor<GradeRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let activePhaseID {
            descriptor.predicate = #Predicate { $0.phaseId == activePhaseID }
        }
        return try pagedFetch(descriptor, batchSize: batchSize, transform: { $0.toSnapshot() })
    }

    func fetchMistakes(batchSize: Int = defaultReadBatchSize) async throws -> [MistakeNote] {
        try pagedFetch(
            FetchDescriptor<MistakeNoteRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]),
            batchSize: batchSize,
            transform: { $0.toSnapshot() }
        )
    }

    func fetchMistakes(activePhaseID: UUID?, batchSize: Int = defaultReadBatchSize) async throws -> [MistakeNote] {
        var descriptor = FetchDescriptor<MistakeNoteRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let activePhaseID {
            descriptor.predicate = #Predicate { $0.phaseId == activePhaseID }
        }
        return try pagedFetch(descriptor, batchSize: batchSize, transform: { $0.toSnapshot() })
    }

    func fetchExams(batchSize: Int = defaultReadBatchSize) async throws -> [Exam] {
        try pagedFetch(
            FetchDescriptor<ExamRecord>(sortBy: [SortDescriptor(\.examDate, order: .reverse)]),
            batchSize: batchSize,
            transform: { $0.toSnapshot() }
        )
    }

    func fetchExams(activePhaseID: UUID?, batchSize: Int = defaultReadBatchSize) async throws -> [Exam] {
        var descriptor = FetchDescriptor<ExamRecord>(sortBy: [SortDescriptor(\.examDate, order: .reverse)])
        if let activePhaseID {
            descriptor.predicate = #Predicate { $0.phaseId == activePhaseID }
        }
        return try pagedFetch(descriptor, batchSize: batchSize, transform: { $0.toSnapshot() })
    }

    func fetchComprehensiveExams(
        batchSize: Int = defaultReadBatchSize
    ) async throws -> [comprehensiveExam] {
        try pagedFetch(
            FetchDescriptor<ComprehensiveExamRecord>(
                sortBy: [SortDescriptor(\.examDate, order: .reverse)]
            ),
            batchSize: batchSize,
            transform: { $0.toSnapshot() }
        )
    }

    func fetchComprehensiveExams(
        activePhaseID: UUID?,
        batchSize: Int = defaultReadBatchSize
    ) async throws -> [comprehensiveExam] {
        var descriptor = FetchDescriptor<ComprehensiveExamRecord>(
            sortBy: [SortDescriptor(\.examDate, order: .reverse)]
        )
        if let activePhaseID {
            descriptor.predicate = #Predicate { $0.phaseId == activePhaseID }
        }
        return try pagedFetch(descriptor, batchSize: batchSize, transform: { $0.toSnapshot() })
    }

    func fetchTasks(batchSize: Int = defaultReadBatchSize) async throws -> [TaskItem] {
        try pagedFetch(
            FetchDescriptor<TaskItemRecord>(sortBy: [SortDescriptor(\.dueDate)]),
            batchSize: batchSize,
            transform: { $0.toSnapshot() }
        )
    }

    func fetchTasks(activePhaseID: UUID?, batchSize: Int = defaultReadBatchSize) async throws -> [TaskItem] {
        var descriptor = FetchDescriptor<TaskItemRecord>(sortBy: [SortDescriptor(\.dueDate)])
        if let activePhaseID {
            descriptor.predicate = #Predicate { $0.phaseId == activePhaseID }
        }
        return try pagedFetch(descriptor, batchSize: batchSize, transform: { $0.toSnapshot() })
    }

    // MARK: - Startup reads for low-frequency repositories

    /// Load Coach list data without hydrating the conversation history.
    ///
    /// Messages are intentionally not part of the startup snapshot. Their
    /// `chatID`/`goalID` columns are indexed, so the repository can fetch one
    /// conversation when it is opened. Records from pre-V5 stores have no
    /// denormalized chat ID; only that compatibility subset is decoded once to
    /// complete the migration.
    func loadCoachSnapshots() async throws -> CoachSnapshots {
        let goalRecords = try modelContext.fetch(FetchDescriptor<CoachGoalRecord>())
        let analysisRecords = try modelContext.fetch(
            FetchDescriptor<CoachAnalysisRecord>(
                sortBy: [SortDescriptor(\.calculatedAt, order: .reverse)]
            )
        )
        let proposalRecords = try modelContext.fetch(
            FetchDescriptor<CoachProposalRecord>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
        let chatRecords = try modelContext.fetch(
            FetchDescriptor<CoachChatRecord>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        )

        let goals = decodeCoachRecords(goalRecords, kind: "CoachGoal", id: { $0.id }, decode: { $0.toSnapshot() })
        let analyses = decodeCoachRecords(analysisRecords, kind: "CoachAnalysis", id: { $0.id }, decode: { $0.toSnapshot() })
        let proposals = decodeCoachRecords(proposalRecords, kind: "CoachProposal", id: { $0.id }, decode: { $0.toSnapshot() })
        var didBackfillChats = false
        var chats: [CoachChat] = []
        chats.reserveCapacity(chatRecords.count)
        for record in chatRecords {
            let needsBackfill = record.title == nil || record.isArchived == nil || record.createdAt == nil
            guard let chat = record.toSummary() else {
                Log.data.error(
                    "Coach load skipped unreadable CoachChat id=\(record.id.uuidString, privacy: .public)"
                )
                continue
            }
            chats.append(chat)
            guard needsBackfill else { continue }
            record.goalID = chat.goalID
            record.title = chat.title
            record.isArchived = chat.isArchived
            record.createdAt = chat.createdAt
            didBackfillChats = true
        }

        // V1-V4 message records have a nil chatID because the relation lived
        // only inside payload. This compatibility scan is deliberately
        // one-time; after the index is backfilled, normal launches never
        // fetch the message table just to build the Coach list.
        var migratedMessages: [CoachConversationMessage] = []
        let messageIndexMigrationKey = "studyPulse.coachMessageIndexMigrationV1"
        let shouldBackfillMessageIndex = !UserDefaults.standard.bool(forKey: messageIndexMigrationKey)
        if shouldBackfillMessageIndex {
            let knownChatIDs = Set(chats.map(\.id))
            let indexedMessageRecords = try modelContext.fetch(
                FetchDescriptor<CoachConversationMessageRecord>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
            let legacyMessageRecords = indexedMessageRecords.filter { record in
                guard let chatID = record.chatID else { return true }
                // A short compatibility path for stores written by an early
                // build that denormalized chatID before the chat record existed.
                // Normal records are never opened or decoded here.
                return !knownChatIDs.contains(chatID)
            }
            var migratedChatByGoal: [UUID?: CoachChat] = [:]
            for record in legacyMessageRecords {
                guard let old = record.toSnapshot() else {
                    Log.data.error(
                        "Coach message index migration skipped unreadable record id=\(record.id.uuidString, privacy: .public)"
                    )
                    continue
                }
                let chat: CoachChat
                if let existing = chats.first(where: { $0.id == old.chatID }) {
                    chat = existing
                } else if let existing = migratedChatByGoal[old.goalID] {
                    chat = existing
                } else {
                    let newChat = CoachChat(goalID: old.goalID, title: "New chat")
                    do {
                        modelContext.insert(try CoachChatRecord(from: newChat))
                    } catch {
                        Log.data.error(
                            "Coach message index migration chat encode failed goal=\(old.goalID?.uuidString ?? "nil", privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                        continue
                    }
                    chats.append(newChat)
                    migratedChatByGoal[old.goalID] = newChat
                    chat = newChat
                }
                let migrated = CoachConversationMessage(
                    id: old.id,
                    goalID: old.goalID,
                    chatID: chat.id,
                    role: old.role,
                    content: old.content,
                    createdAt: old.createdAt,
                    isStreaming: old.isStreaming,
                    error: old.error,
                    todoSuggestions: old.todoSuggestions
                )
                do {
                    let payload = try JSONEncoder().encode(migrated)
                    record.chatID = chat.id
                    record.payload = payload
                    migratedMessages.append(migrated)
                } catch {
                    Log.data.error(
                        "Coach message index migration encode failed id=\(record.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }

        if didBackfillChats || !migratedMessages.isEmpty {
            try modelContext.save()
        }
        if shouldBackfillMessageIndex {
            UserDefaults.standard.set(true, forKey: messageIndexMigrationKey)
        }

        return CoachSnapshots(
            goals: goals,
            analyses: analyses,
            proposals: proposals,
            chats: chats,
            messages: migratedMessages
        )
    }

    /// Merge the legacy JSON session store and load bounded session summaries.
    /// Full heart-rate/annotation payloads are hydrated by the repository's
    /// ID/date-window detail APIs only.
    func loadStudySessionSnapshots(mergeLegacyJSONIfNeeded: Bool = true) async throws -> [StudySessionSummary] {
        let migrationKey = "studyPulse.studySessionsLegacyMigrationV2"
        if mergeLegacyJSONIfNeeded && !UserDefaults.standard.bool(forKey: migrationKey) {
            let existing = try modelContext.fetch(FetchDescriptor<StudySessionRecord>())
            let existingIDs = Set(existing.map(\.id))
            let legacySessions = StudySessionStore.load()

            for session in legacySessions where !existingIDs.contains(session.id) {
                modelContext.insert(StudySessionRecord(from: session))
            }

            do {
                try modelContext.save()
                UserDefaults.standard.set(true, forKey: migrationKey)
            } catch {
                Log.data.error(
                    "Legacy study-session merge failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        let descriptor = FetchDescriptor<StudySessionRecord>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        var bounded = descriptor
        bounded.fetchLimit = 365
        let records = try modelContext.fetch(bounded)
        var didBackfill = false
        let summaries = records.compactMap { record -> StudySessionSummary? in
            let needsBackfill = record.durationSeconds == nil
            guard let summary = record.toSummary() else { return nil }
            guard needsBackfill else { return summary }
            record.durationSeconds = summary.durationSeconds
            record.intensityRaw = summary.intensity.rawValue
            record.completed = summary.completed
            record.investmentTargetKindRaw = summary.investmentTarget?.kindRawValue
            record.investmentTargetID = summary.investmentTarget?.rawID
            record.sourceRaw = summary.source.rawValue
            record.timeZoneIdentifier = summary.timeZoneIdentifier
            record.heartRateSampleCount = summary.heartRateSampleCount
            record.difficultyAnnotationCount = summary.difficultyAnnotationCount
            didBackfill = true
            return summary
        }
        if didBackfill { try modelContext.save() }
        return summaries
    }

    /// Fetch and decode all time-investment entities on the SwiftData actor.
    func loadTimeInvestmentSnapshots() async throws -> TimeInvestmentSnapshots {
        let subjects = try modelContext.fetch(FetchDescriptor<TimeInvestmentSubjectRecord>())
            .map { $0.toSnapshot() }
        let subTasks = try modelContext.fetch(FetchDescriptor<SubTaskRecord>())
            .map { $0.toSnapshot() }
        let rewards = try modelContext.fetch(FetchDescriptor<GoalRewardRecord>())
            .compactMap { $0.toSnapshot() }

        return TimeInvestmentSnapshots(
            subjects: subjects,
            subTasks: subTasks,
            rewards: rewards
        )
    }

    // MARK: - Phase-filtered routine and diary reads

    func fetchRoutines(activePhaseID: UUID?, batchSize: Int = defaultReadBatchSize) async throws -> [Routine] {
        var descriptor = FetchDescriptor<RoutineRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        if let activePhaseID {
            descriptor.predicate = #Predicate { $0.phaseId == activePhaseID }
        }
        return try pagedFetch(descriptor, batchSize: batchSize, transform: { $0.toSnapshot() })
    }

    func fetchDiaryEntries(
        activePhaseID: UUID?,
        limit: Int? = 365
    ) async throws -> [DiaryEntry] {
        var descriptor = FetchDescriptor<DiaryEntryRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let activePhaseID {
            descriptor.predicate = #Predicate {
                $0.phaseId == activePhaseID || $0.phaseId == nil
            }
        }
        if let limit {
            descriptor.fetchLimit = max(0, limit)
        }
        // Diary reads are intentionally bounded to the recent window and do
        // not need the generic paged fetch loop.
        return try modelContext.fetch(descriptor).map { $0.toSnapshot() }
    }

    // MARK: - Grade mutations

    func insertGrades(_ values: [Grade]) async throws {
        let interval = Self.signposter.beginInterval("insertGrades")
        defer { Self.signposter.endInterval("insertGrades", interval) }
        try insertInBatches(values, batchSize: Self.defaultWriteBatchSize) {
            GradeRecord(from: $0)
        }
    }

    func upsertGrade(_ value: Grade) async throws {
        let id = value.id
        let descriptor = FetchDescriptor<GradeRecord>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
        modelContext.insert(GradeRecord(from: value))
        try saveIfNeeded()
    }

    func deleteGrade(id: UUID) async throws {
        let descriptor = FetchDescriptor<GradeRecord>(predicate: #Predicate { $0.id == id })
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try saveIfNeeded()
        }
    }

    func deleteAllGrades() async throws -> Int {
        let interval = Self.signposter.beginInterval("deleteAllGrades")
        defer { Self.signposter.endInterval("deleteAllGrades", interval) }
        return try deleteAll(GradeRecord.self)
    }

    // MARK: - Mistake mutations

    func insertMistakes(_ values: [MistakeNote]) async throws {
        let interval = Self.signposter.beginInterval("insertMistakes")
        defer { Self.signposter.endInterval("insertMistakes", interval) }
        try insertInBatches(values, batchSize: Self.defaultWriteBatchSize) {
            MistakeNoteRecord(from: $0)
        }
    }

    func upsertMistake(_ value: MistakeNote) async throws {
        let id = value.id
        let descriptor = FetchDescriptor<MistakeNoteRecord>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
        modelContext.insert(MistakeNoteRecord(from: value))
        try saveIfNeeded()
    }

    func deleteMistakes(ids: Set<UUID>) async throws {
        guard !ids.isEmpty else { return }
        let ids = Array(ids)
        let records = try modelContext.fetch(
            FetchDescriptor<MistakeNoteRecord>(predicate: #Predicate { ids.contains($0.id) })
        )
        try Task.checkCancellation()
        for record in records where ids.contains(record.id) {
            modelContext.delete(record)
        }
        try saveIfNeeded()
    }

    func deleteAllMistakes() async throws -> Int {
        let interval = Self.signposter.beginInterval("deleteAllMistakes")
        defer { Self.signposter.endInterval("deleteAllMistakes", interval) }
        return try deleteAll(MistakeNoteRecord.self)
    }

    // MARK: - Exam mutations

    func insertExams(single: [Exam], comprehensive: [comprehensiveExam]) async throws {
        let interval = Self.signposter.beginInterval("insertExams")
        defer { Self.signposter.endInterval("insertExams", interval) }
        do {
            try Task.checkCancellation()
            for value in single {
                modelContext.insert(ExamRecord(from: value))
            }
            for value in comprehensive {
                modelContext.insert(ComprehensiveExamRecord(from: value))
            }
            try Task.checkCancellation()
            try saveIfNeeded()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func upsertExam(_ value: Exam) async throws {
        let id = value.id
        let descriptor = FetchDescriptor<ExamRecord>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
        modelContext.insert(ExamRecord(from: value))
        try saveIfNeeded()
    }

    func upsertComprehensiveExam(_ value: comprehensiveExam) async throws {
        let id = value.id
        let descriptor = FetchDescriptor<ComprehensiveExamRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
        modelContext.insert(ComprehensiveExamRecord(from: value))
        try saveIfNeeded()
    }

    func deleteExam(id: UUID) async throws {
        let descriptor = FetchDescriptor<ExamRecord>(predicate: #Predicate { $0.id == id })
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try saveIfNeeded()
        }
    }

    func deleteComprehensiveExam(id: UUID) async throws {
        let descriptor = FetchDescriptor<ComprehensiveExamRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try saveIfNeeded()
        }
    }

    func deleteAllExams() async throws -> Int {
        let interval = Self.signposter.beginInterval("deleteAllExams")
        defer { Self.signposter.endInterval("deleteAllExams", interval) }
        let singleCount = try modelContext.fetchCount(FetchDescriptor<ExamRecord>())
        let comprehensiveCount = try modelContext.fetchCount(
            FetchDescriptor<ComprehensiveExamRecord>()
        )
        try Task.checkCancellation()
        try modelContext.delete(model: ExamRecord.self)
        try modelContext.delete(model: ComprehensiveExamRecord.self)
        try saveIfNeeded()
        return singleCount + comprehensiveCount
    }

    // MARK: - Task mutations

    func insertTasks(_ values: [TaskItem]) async throws {
        let interval = Self.signposter.beginInterval("insertTasks")
        defer { Self.signposter.endInterval("insertTasks", interval) }
        try insertInBatches(values, batchSize: Self.defaultWriteBatchSize) {
            TaskItemRecord(from: $0)
        }
    }

    func upsertTask(_ value: TaskItem) async throws {
        let id = value.id
        let descriptor = FetchDescriptor<TaskItemRecord>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
        modelContext.insert(TaskItemRecord(from: value))
        try saveIfNeeded()
    }

    func deleteTask(id: UUID) async throws {
        let descriptor = FetchDescriptor<TaskItemRecord>(predicate: #Predicate { $0.id == id })
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try saveIfNeeded()
        }
    }

    func deleteAllTasks() async throws -> Int {
        let interval = Self.signposter.beginInterval("deleteAllTasks")
        defer { Self.signposter.endInterval("deleteAllTasks", interval) }
        return try deleteAll(TaskItemRecord.self)
    }

    // MARK: - Generic helpers

    private func pagedFetch<Record: PersistentModel, Snapshot: Sendable>(
        _ baseDescriptor: FetchDescriptor<Record>,
        batchSize: Int,
        transform: (Record) -> Snapshot
    ) throws -> [Snapshot] {
        let size = max(1, batchSize)
        var offset = 0
        var result: [Snapshot] = []

        while true {
            try Task.checkCancellation()
            var descriptor = baseDescriptor
            descriptor.fetchLimit = size
            descriptor.fetchOffset = offset
            let page = try modelContext.fetch(descriptor)
            result.append(contentsOf: page.map(transform))
            guard page.count == size else { break }
            offset += page.count
        }
        return result
    }

    private func insertInBatches<Value: Sendable, Record: PersistentModel>(
        _ values: [Value],
        batchSize: Int,
        makeRecord: (Value) -> Record
    ) throws {
        guard !values.isEmpty else { return }
        do {
            let size = max(1, batchSize)
            for start in stride(from: 0, to: values.count, by: size) {
                try Task.checkCancellation()
                let end = min(start + size, values.count)
                for value in values[start..<end] {
                    modelContext.insert(makeRecord(value))
                }
            }
            // One durable save per user operation. Batching bounds cancellation
            // checks and conversion work without exposing partially published state.
            try Task.checkCancellation()
            try saveIfNeeded()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func deleteAll<Record: PersistentModel>(_ type: Record.Type) throws -> Int {
        let count = try modelContext.fetchCount(FetchDescriptor<Record>())
        try Task.checkCancellation()
        try modelContext.delete(model: type)
        try saveIfNeeded()
        return count
    }

    private func saveIfNeeded() throws {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func decodeCoachRecords<Record, Snapshot>(
        _ records: [Record],
        kind: String,
        id: (Record) -> UUID,
        decode: (Record) -> Snapshot?
    ) -> [Snapshot] {
        var result: [Snapshot] = []
        result.reserveCapacity(records.count)
        for record in records {
            if let snapshot = decode(record) {
                result.append(snapshot)
            } else {
                let recordID = id(record).uuidString
                Log.data.error(
                    "Coach load skipped unreadable \(kind, privacy: .public) id=\(recordID, privacy: .public)"
                )
            }
        }
        return result
    }
}

/// Internal capability for repositories that share the persistence boundary.
@MainActor
protocol PersistenceExecutorAttachable: AnyObject {
    func attachPersistenceExecutor(_ executor: PersistenceExecutor)
}

/// Internal additive capability. Public repository protocols remain unchanged.
@MainActor
protocol PersistenceExecutorBacked: PersistenceExecutorAttachable {
    func reloadFilteredFromSwiftData() async
    func flushPendingPersistence() async
    func cancelPendingPersistence()
}
