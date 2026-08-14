//
//  PersistenceExecutor.swift
//  StudyPulse
//
//  Phase 5 SwiftData execution boundary.
//

import Foundation
import SwiftData
import os

/// Immutable startup payload produced entirely inside the SwiftData actor.
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
/// No SwiftData model or `ModelContext` crosses the actor boundary.
nonisolated struct CoachSnapshots: Sendable {
    let goals: [CoachGoal]
    let analyses: [CoachAnalysis]
    let proposals: [CoachProposal]
    let chats: [CoachChat]
    let messages: [CoachConversationMessage]
}

/// Startup snapshots for the long-term time-investment domain.
/// No SwiftData model or `ModelContext` crosses the actor boundary.
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

/// The only execution context used by the high-frequency repositories for
/// SwiftData fetches and mutations. Repositories and views only receive value
/// snapshots.
@ModelActor
actor PersistenceExecutor {
    nonisolated static let defaultReadBatchSize = 500
    nonisolated static let defaultWriteBatchSize = 500

    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.chenkai.gao.studypulse",
        category: "Persistence"
    )

    // MARK: - Startup reads

    func loadHighFrequencySnapshots(
        activePhaseID: UUID? = nil,
        readBatchSize: Int = defaultReadBatchSize
    ) throws -> HighFrequencySnapshots {
        let interval = Self.signposter.beginInterval("loadHighFrequencySnapshots")
        defer { Self.signposter.endInterval("loadHighFrequencySnapshots", interval) }

        let grades = try fetchGrades(batchSize: readBatchSize)
        let mistakes = try fetchMistakes(batchSize: readBatchSize)
        let exams = try fetchExams(batchSize: readBatchSize)
        let comprehensiveExams = try fetchComprehensiveExams(batchSize: readBatchSize)
        let tasks = try fetchTasks(batchSize: readBatchSize)

        let filteredGrades = activePhaseID == nil
            ? grades
            : try fetchGrades(activePhaseID: activePhaseID, batchSize: readBatchSize)
        let filteredMistakes = activePhaseID == nil
            ? mistakes
            : try fetchMistakes(activePhaseID: activePhaseID, batchSize: readBatchSize)
        let filteredExams = activePhaseID == nil
            ? exams
            : try fetchExams(activePhaseID: activePhaseID, batchSize: readBatchSize)
        let filteredComprehensiveExams = activePhaseID == nil
            ? comprehensiveExams
            : try fetchComprehensiveExams(activePhaseID: activePhaseID, batchSize: readBatchSize)
        let filteredTasks = activePhaseID == nil
            ? tasks
            : try fetchTasks(activePhaseID: activePhaseID, batchSize: readBatchSize)

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

    func fetchGrades(batchSize: Int = defaultReadBatchSize) throws -> [Grade] {
        try pagedFetch(
            FetchDescriptor<GradeRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]),
            batchSize: batchSize,
            transform: { $0.toSnapshot() }
        )
    }

    func fetchGrades(activePhaseID: UUID?, batchSize: Int = defaultReadBatchSize) throws -> [Grade] {
        var descriptor = FetchDescriptor<GradeRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let activePhaseID {
            descriptor.predicate = #Predicate { $0.phaseId == activePhaseID }
        }
        return try pagedFetch(descriptor, batchSize: batchSize, transform: { $0.toSnapshot() })
    }

    func fetchMistakes(batchSize: Int = defaultReadBatchSize) throws -> [MistakeNote] {
        try pagedFetch(
            FetchDescriptor<MistakeNoteRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]),
            batchSize: batchSize,
            transform: { $0.toSnapshot() }
        )
    }

    func fetchMistakes(activePhaseID: UUID?, batchSize: Int = defaultReadBatchSize) throws -> [MistakeNote] {
        var descriptor = FetchDescriptor<MistakeNoteRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let activePhaseID {
            descriptor.predicate = #Predicate { $0.phaseId == activePhaseID }
        }
        return try pagedFetch(descriptor, batchSize: batchSize, transform: { $0.toSnapshot() })
    }

    func fetchExams(batchSize: Int = defaultReadBatchSize) throws -> [Exam] {
        try pagedFetch(
            FetchDescriptor<ExamRecord>(sortBy: [SortDescriptor(\.examDate, order: .reverse)]),
            batchSize: batchSize,
            transform: { $0.toSnapshot() }
        )
    }

    func fetchExams(activePhaseID: UUID?, batchSize: Int = defaultReadBatchSize) throws -> [Exam] {
        var descriptor = FetchDescriptor<ExamRecord>(sortBy: [SortDescriptor(\.examDate, order: .reverse)])
        if let activePhaseID {
            descriptor.predicate = #Predicate { $0.phaseId == activePhaseID }
        }
        return try pagedFetch(descriptor, batchSize: batchSize, transform: { $0.toSnapshot() })
    }

    func fetchComprehensiveExams(
        batchSize: Int = defaultReadBatchSize
    ) throws -> [comprehensiveExam] {
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
    ) throws -> [comprehensiveExam] {
        var descriptor = FetchDescriptor<ComprehensiveExamRecord>(
            sortBy: [SortDescriptor(\.examDate, order: .reverse)]
        )
        if let activePhaseID {
            descriptor.predicate = #Predicate { $0.phaseId == activePhaseID }
        }
        return try pagedFetch(descriptor, batchSize: batchSize, transform: { $0.toSnapshot() })
    }

    func fetchTasks(batchSize: Int = defaultReadBatchSize) throws -> [TaskItem] {
        try pagedFetch(
            FetchDescriptor<TaskItemRecord>(sortBy: [SortDescriptor(\.dueDate)]),
            batchSize: batchSize,
            transform: { $0.toSnapshot() }
        )
    }

    func fetchTasks(activePhaseID: UUID?, batchSize: Int = defaultReadBatchSize) throws -> [TaskItem] {
        var descriptor = FetchDescriptor<TaskItemRecord>(sortBy: [SortDescriptor(\.dueDate)])
        if let activePhaseID {
            descriptor.predicate = #Predicate { $0.phaseId == activePhaseID }
        }
        return try pagedFetch(descriptor, batchSize: batchSize, transform: { $0.toSnapshot() })
    }

    // MARK: - Startup reads for low-frequency repositories

    /// Fetch and decode all Coach history on the SwiftData actor.
    ///
    /// Legacy messages without a persisted chat are migrated here as part of
    /// the same background transaction, so `DefaultCoachRepository.loadAll`
    /// only publishes value snapshots on the MainActor.
    func loadCoachSnapshots() throws -> CoachSnapshots {
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
        let messageRecords = try modelContext.fetch(
            FetchDescriptor<CoachConversationMessageRecord>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
        )
        let chatRecords = try modelContext.fetch(
            FetchDescriptor<CoachChatRecord>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        )

        let goals = goalRecords.compactMap { $0.toSnapshot() }
        let analyses = analysisRecords.compactMap { $0.toSnapshot() }
        let proposals = proposalRecords.compactMap { $0.toSnapshot() }
        var messages = messageRecords.compactMap { $0.toSnapshot() }
        var chats = chatRecords.compactMap { $0.toSnapshot() }

        // Keep the historical migration semantics, but perform the record
        // writes and JSON encoding on this actor rather than MainActor.
        let legacyGoalIDs = Set(messages.compactMap { message in
            chats.contains(where: { $0.id == message.chatID }) ? nil : message.goalID
        })
        var didMigrateLegacyMessages = false
        for goalID in legacyGoalIDs {
            let legacy = messages.filter { message in
                message.goalID == goalID && !chats.contains { chat in chat.id == message.chatID }
            }
            guard !legacy.isEmpty else { continue }

            let chat = CoachChat(goalID: goalID, title: "New chat")
            chats.append(chat)
            modelContext.insert(CoachChatRecord(from: chat))

            for old in legacy {
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
                if let index = messages.firstIndex(where: { $0.id == old.id }) {
                    messages[index] = migrated
                }
                if let record = messageRecords.first(where: { $0.id == old.id }) {
                    record.payload = (try? JSONEncoder().encode(migrated)) ?? Data()
                }
            }
            didMigrateLegacyMessages = true
        }

        if didMigrateLegacyMessages {
            try modelContext.save()
        }

        return CoachSnapshots(
            goals: goals,
            analyses: analyses,
            proposals: proposals,
            chats: chats,
            messages: messages
        )
    }

    /// Merge the legacy JSON session store and load the complete SwiftData
    /// session history on the SwiftData actor.
    func loadStudySessionSnapshots(mergeLegacyJSONIfNeeded: Bool = true) throws -> [StudySession] {
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
        return try modelContext.fetch(descriptor).compactMap { $0.toSnapshot() }
    }

    /// Fetch and decode all time-investment entities on the SwiftData actor.
    func loadTimeInvestmentSnapshots() throws -> TimeInvestmentSnapshots {
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

    func fetchRoutines(activePhaseID: UUID?, batchSize: Int = defaultReadBatchSize) throws -> [Routine] {
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
    ) throws -> [DiaryEntry] {
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

    func insertGrades(_ values: [Grade]) throws {
        let interval = Self.signposter.beginInterval("insertGrades")
        defer { Self.signposter.endInterval("insertGrades", interval) }
        try insertInBatches(values, batchSize: Self.defaultWriteBatchSize) {
            GradeRecord(from: $0)
        }
    }

    func upsertGrade(_ value: Grade) throws {
        let id = value.id
        let descriptor = FetchDescriptor<GradeRecord>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
        modelContext.insert(GradeRecord(from: value))
        try saveIfNeeded()
    }

    func deleteGrade(id: UUID) throws {
        let descriptor = FetchDescriptor<GradeRecord>(predicate: #Predicate { $0.id == id })
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try saveIfNeeded()
        }
    }

    func deleteAllGrades() throws -> Int {
        let interval = Self.signposter.beginInterval("deleteAllGrades")
        defer { Self.signposter.endInterval("deleteAllGrades", interval) }
        return try deleteAll(GradeRecord.self)
    }

    // MARK: - Mistake mutations

    func insertMistakes(_ values: [MistakeNote]) throws {
        let interval = Self.signposter.beginInterval("insertMistakes")
        defer { Self.signposter.endInterval("insertMistakes", interval) }
        try insertInBatches(values, batchSize: Self.defaultWriteBatchSize) {
            MistakeNoteRecord(from: $0)
        }
    }

    func upsertMistake(_ value: MistakeNote) throws {
        let id = value.id
        let descriptor = FetchDescriptor<MistakeNoteRecord>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
        modelContext.insert(MistakeNoteRecord(from: value))
        try saveIfNeeded()
    }

    func deleteMistakes(ids: Set<UUID>) throws {
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

    func deleteAllMistakes() throws -> Int {
        let interval = Self.signposter.beginInterval("deleteAllMistakes")
        defer { Self.signposter.endInterval("deleteAllMistakes", interval) }
        return try deleteAll(MistakeNoteRecord.self)
    }

    // MARK: - Exam mutations

    func insertExams(single: [Exam], comprehensive: [comprehensiveExam]) throws {
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

    func upsertExam(_ value: Exam) throws {
        let id = value.id
        let descriptor = FetchDescriptor<ExamRecord>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
        modelContext.insert(ExamRecord(from: value))
        try saveIfNeeded()
    }

    func upsertComprehensiveExam(_ value: comprehensiveExam) throws {
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

    func deleteExam(id: UUID) throws {
        let descriptor = FetchDescriptor<ExamRecord>(predicate: #Predicate { $0.id == id })
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try saveIfNeeded()
        }
    }

    func deleteComprehensiveExam(id: UUID) throws {
        let descriptor = FetchDescriptor<ComprehensiveExamRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try saveIfNeeded()
        }
    }

    func deleteAllExams() throws -> Int {
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

    func insertTasks(_ values: [TaskItem]) throws {
        let interval = Self.signposter.beginInterval("insertTasks")
        defer { Self.signposter.endInterval("insertTasks", interval) }
        try insertInBatches(values, batchSize: Self.defaultWriteBatchSize) {
            TaskItemRecord(from: $0)
        }
    }

    func upsertTask(_ value: TaskItem) throws {
        let id = value.id
        let descriptor = FetchDescriptor<TaskItemRecord>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
        modelContext.insert(TaskItemRecord(from: value))
        try saveIfNeeded()
    }

    func deleteTask(id: UUID) throws {
        let descriptor = FetchDescriptor<TaskItemRecord>(predicate: #Predicate { $0.id == id })
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try saveIfNeeded()
        }
    }

    func deleteAllTasks() throws -> Int {
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
}

/// Internal capability for repositories that can share the SwiftData actor.
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
