import Foundation
import SwiftData

@MainActor
enum BackupImporter {
    struct ImportResult: Sendable {
        var importedCounts: [String: Int]
        var warnings: [String]
    }

    static func apply(
        validated: ValidatedBackup,
        mode: BackupRestoreMode,
        container: RepositoryContainer,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> ImportResult {
        guard let context = container.modelContainer?.mainContext else {
            throw BackupError.restoreFailed("Persistent store is unavailable")
        }
        // Stop deferred high-frequency writes before taking the restore
        // snapshot. After C-03 all repositories share this main context, so no
        // second ModelContext can race the replacement transaction.
        container.cancelPendingPersistence()
        await container.flushPendingPersistence()
        try Task.checkCancellation()
        progress(0.08)
        var content = validated.content
        if mode == .merge {
            content = merge(content, with: currentContent(container: container, context: context))
        }
        try BackupValidator.validateRelationships(content)
        progress(0.2)

        let mediaResult = try await stageMedia(
            content: content,
            extractedDirectory: validated.extractedDirectory,
            includesMedia: validated.manifest.includesMedia
        )
        defer { mediaResult.cleanup() }
        content = mediaResult.content
        progress(0.4)

        do {
            // Phase 1: prove that every record can be inserted and saved into
            // the production schema without touching the live store.
            try validateInTemporaryStore(content)
            try Task.checkCancellation()

            // Phase 2: delete + insert + save is one SwiftData/SQLite
            // transaction. A failed save rolls the live context back to the
            // pre-restore state.
            try replacePersistentContent(content, context: context)
            progress(0.68)

            // Media is prepared outside the live directories and only moved
            // into place after the database commit succeeds.
            try mediaResult.commit()
            AchievementStore.save(content.achievements)
            container.envManager.preferences = content.preferences.applying(to: container.envManager.preferences)
            if let health = content.healthHistory {
                HealthHistoryStore.save(health)
            }
            try await container.reloadAllAfterBackupRestore()
            progress(0.9)
            let actual = currentContent(container: container, context: context)
            try verifyImported(content, actual: actual)
            progress(1)
            return ImportResult(
                importedCounts: validated.manifest.recordCounts,
                warnings: validated.warnings + mediaResult.warnings
            )
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Preflight the decoded payload against an isolated production-schema
    /// store. Internal visibility keeps this safety boundary directly
    /// regression-testable without mutating a live RepositoryContainer.
    static func validateInTemporaryStore(
        _ content: BackupDecodedContent
    ) throws {
        try validateUniqueIdentifiers(content)
        let schema = ModelContainerFactory.currentSchema
        let configuration = ModelConfiguration(
            "BackupRestoreValidation-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        do {
            let temporaryContainer = try ModelContainer(
                for: schema,
                migrationPlan: StudyPulseMigrationPlan.self,
                configurations: [configuration]
            )
            try insertPersistentContent(content, context: temporaryContainer.mainContext)
            try verifyPersistentCounts(content, context: temporaryContainer.mainContext)
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.restoreFailed(
                "Temporary store validation failed: \(error.localizedDescription)"
            )
        }
    }

    private static func validateUniqueIdentifiers(
        _ c: BackupDecodedContent
    ) throws {
        func requireUnique<T: Identifiable>(
            _ values: [T],
            name: String
        ) throws where T.ID == UUID {
            guard Set(values.map(\.id)).count == values.count else {
                throw BackupError.invalidRelationship("duplicate UUID in \(name)")
            }
        }

        try requireUnique(c.subjects, name: "subjects")
        try requireUnique(c.grades, name: "grades")
        try requireUnique(c.mistakes, name: "mistakes")
        try requireUnique(c.exams, name: "exams")
        try requireUnique(c.comprehensiveExams, name: "comprehensive exams")
        try requireUnique(c.tasks, name: "tasks")
        try requireUnique(c.phases, name: "phases")
        try requireUnique(c.routines, name: "routines")
        try requireUnique(c.routineInstances, name: "routine instances")
        try requireUnique(c.diaryEntries, name: "diary entries")
        try requireUnique(c.studySessions, name: "study sessions")
        try requireUnique(c.timeInvestmentSubjects, name: "time investment subjects")
        try requireUnique(c.subTasks, name: "subtasks")
        try requireUnique(c.goalRewards, name: "goal rewards")
        try requireUnique(c.coachGoals, name: "coach goals")
        try requireUnique(c.coachAnalyses, name: "coach analyses")
        try requireUnique(c.coachProposals, name: "coach proposals")
        try requireUnique(c.coachChats, name: "coach chats")
        try requireUnique(c.coachMessages, name: "coach messages")
    }

    private static func replacePersistentContent(
        _ c: BackupDecodedContent,
        context: ModelContext
    ) throws {
        try deleteAll(SubjectRecord.self, context)
        try deleteAll(GradeRecord.self, context)
        try deleteAll(MistakeNoteRecord.self, context)
        try deleteAll(ExamRecord.self, context)
        try deleteAll(ComprehensiveExamRecord.self, context)
        try deleteAll(TaskItemRecord.self, context)
        try deleteAll(UserProfileRecord.self, context)
        try deleteAll(StudyPhaseRecord.self, context)
        try deleteAll(PlantStateRecord.self, context)
        try deleteAll(RoutineRecord.self, context)
        try deleteAll(RoutineInstanceRecord.self, context)
        try deleteAll(DiaryEntryRecord.self, context)
        try deleteAll(CoachGoalRecord.self, context)
        try deleteAll(CoachAnalysisRecord.self, context)
        try deleteAll(CoachProposalRecord.self, context)
        try deleteAll(CoachConversationMessageRecord.self, context)
        try deleteAll(CoachChatRecord.self, context)
        try deleteAll(StudySessionRecord.self, context)
        try deleteAll(TimeInvestmentSubjectRecord.self, context)
        try deleteAll(SubTaskRecord.self, context)
        try deleteAll(GoalRewardRecord.self, context)
        // These are deliberately excluded derived AI artifacts. Clearing them
        // prevents stale references after a replace restore.
        try deleteAll(ExamAutopsyRecord.self, context)
        try deleteAll(ExamSimulationRecord.self, context)

        try insertPersistentContent(c, context: context)
    }

    private static func insertPersistentContent(
        _ c: BackupDecodedContent,
        context: ModelContext
    ) throws {
        c.subjects.forEach { context.insert(SubjectRecord(from: $0)) }
        c.grades.forEach { context.insert(GradeRecord(from: $0)) }
        c.mistakes.forEach { context.insert(MistakeNoteRecord(from: $0)) }
        c.exams.forEach { context.insert(ExamRecord(from: $0)) }
        c.comprehensiveExams.forEach { context.insert(ComprehensiveExamRecord(from: $0)) }
        c.tasks.forEach { context.insert(TaskItemRecord(from: $0)) }
        context.insert(UserProfileRecord(from: c.profile))
        c.phases.forEach { context.insert(StudyPhaseRecord(from: $0)) }
        context.insert(PlantStateRecord(from: c.plantState, previousStage: c.plantState.currentStage))
        c.routines.forEach { context.insert(RoutineRecord(from: $0)) }
        c.routineInstances.forEach { context.insert(RoutineInstanceRecord(from: $0)) }
        c.diaryEntries.forEach { context.insert(DiaryEntryRecord(from: $0)) }
        c.coachGoals.forEach { context.insert(CoachGoalRecord(from: $0)) }
        c.coachAnalyses.forEach { context.insert(CoachAnalysisRecord(from: $0)) }
        c.coachProposals.forEach { context.insert(CoachProposalRecord(from: $0)) }
        c.coachMessages.forEach { context.insert(CoachConversationMessageRecord(from: $0)) }
        c.coachChats.forEach { context.insert(CoachChatRecord(from: $0)) }
        c.studySessions.forEach { context.insert(StudySessionRecord(from: $0)) }
        c.timeInvestmentSubjects.forEach { context.insert(TimeInvestmentSubjectRecord(from: $0)) }
        c.subTasks.forEach { context.insert(SubTaskRecord(from: $0)) }
        c.goalRewards.forEach { context.insert(GoalRewardRecord(from: $0)) }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw BackupError.restoreFailed(error.localizedDescription)
        }
    }

    private static func verifyPersistentCounts(
        _ c: BackupDecodedContent,
        context: ModelContext
    ) throws {
        let counts: [(String, Int, Int)] = [
            ("subjects", c.subjects.count, try context.fetchCount(FetchDescriptor<SubjectRecord>())),
            ("grades", c.grades.count, try context.fetchCount(FetchDescriptor<GradeRecord>())),
            ("mistakes", c.mistakes.count, try context.fetchCount(FetchDescriptor<MistakeNoteRecord>())),
            ("exams", c.exams.count, try context.fetchCount(FetchDescriptor<ExamRecord>())),
            ("comprehensiveExams", c.comprehensiveExams.count, try context.fetchCount(FetchDescriptor<ComprehensiveExamRecord>())),
            ("tasks", c.tasks.count, try context.fetchCount(FetchDescriptor<TaskItemRecord>())),
            ("phases", c.phases.count, try context.fetchCount(FetchDescriptor<StudyPhaseRecord>())),
            ("routines", c.routines.count, try context.fetchCount(FetchDescriptor<RoutineRecord>())),
            ("routineInstances", c.routineInstances.count, try context.fetchCount(FetchDescriptor<RoutineInstanceRecord>())),
            ("diaryEntries", c.diaryEntries.count, try context.fetchCount(FetchDescriptor<DiaryEntryRecord>())),
            ("studySessions", c.studySessions.count, try context.fetchCount(FetchDescriptor<StudySessionRecord>())),
            ("timeInvestmentSubjects", c.timeInvestmentSubjects.count, try context.fetchCount(FetchDescriptor<TimeInvestmentSubjectRecord>())),
            ("subTasks", c.subTasks.count, try context.fetchCount(FetchDescriptor<SubTaskRecord>())),
            ("goalRewards", c.goalRewards.count, try context.fetchCount(FetchDescriptor<GoalRewardRecord>())),
            ("coachGoals", c.coachGoals.count, try context.fetchCount(FetchDescriptor<CoachGoalRecord>())),
            ("coachAnalyses", c.coachAnalyses.count, try context.fetchCount(FetchDescriptor<CoachAnalysisRecord>())),
            ("coachProposals", c.coachProposals.count, try context.fetchCount(FetchDescriptor<CoachProposalRecord>())),
            ("coachChats", c.coachChats.count, try context.fetchCount(FetchDescriptor<CoachChatRecord>())),
            ("coachMessages", c.coachMessages.count, try context.fetchCount(FetchDescriptor<CoachConversationMessageRecord>())),
        ]
        if let mismatch = counts.first(where: { $0.1 != $0.2 }) {
            throw BackupError.countMismatch(mismatch.0)
        }
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws {
        try context.fetch(FetchDescriptor<T>()).forEach(context.delete)
    }

    private static func currentContent(
        container: RepositoryContainer,
        context: ModelContext
    ) -> BackupDecodedContent {
        let plant = (try? context.fetch(FetchDescriptor<PlantStateRecord>()).first?.toSnapshot())
            ?? PlantState()
        return BackupDecodedContent(
            subjects: container.subjectRepo.subjects,
            grades: container.gradeRepo.grades,
            mistakes: container.mistakeRepo.mistakeSets,
            exams: container.examRepo.examSets,
            comprehensiveExams: container.examRepo.comprehensiveExamSets,
            tasks: container.taskRepo.taskItems,
            phases: container.phaseRepo.phases,
            routines: container.routineRepo.routines,
            routineInstances: container.routineInstanceRepo.allInstances,
            diaryEntries: container.diaryRepo.diaryEntries,
            studySessions: container.studySessionRepo.allSessionsForBackup(),
            timeInvestmentSubjects: container.timeInvestmentRepo.subjects,
            subTasks: container.timeInvestmentRepo.subTasks,
            goalRewards: container.timeInvestmentRepo.rewards,
            profile: container.profileRepo.profile,
            plantState: plant,
            achievements: AchievementManager.shared.snapshot,
            coachGoals: container.coachRepo.goals,
            coachAnalyses: container.coachRepo.analyses,
            coachProposals: container.coachRepo.proposals,
            coachChats: container.coachRepo.chats,
            coachMessages: container.coachRepo.allMessages(),
            preferences: BackupPreferencesDTO(preferences: container.envManager.preferences),
            healthHistory: nil
        )
    }

    /// UUID is the only identity. Timestamped values select the newest side;
    /// values without an updatedAt use the documented deterministic rule
    /// "incoming backup wins".
    private static func merge(
        _ incoming: BackupDecodedContent,
        with current: BackupDecodedContent
    ) -> BackupDecodedContent {
        var result = incoming
        result.subjects = mergeByID(current.subjects, incoming.subjects) { _, new in new }
        result.grades = mergeByID(current.grades, incoming.grades) { _, new in new }
        result.mistakes = mergeByID(current.mistakes, incoming.mistakes) { _, new in new }
        result.exams = mergeByID(current.exams, incoming.exams) { _, new in new }
        result.comprehensiveExams = mergeByID(current.comprehensiveExams, incoming.comprehensiveExams) { _, new in new }
        result.tasks = mergeByID(current.tasks, incoming.tasks) { _, new in new }
        result.phases = mergeByID(current.phases, incoming.phases) { _, new in new }
        result.routines = mergeByID(current.routines, incoming.routines) { old, new in
            new.createdAt >= old.createdAt ? new : old
        }
        result.routineInstances = mergeByID(current.routineInstances, incoming.routineInstances) { _, new in new }
        result.diaryEntries = mergeByID(current.diaryEntries, incoming.diaryEntries) { old, new in
            new.updatedAt >= old.updatedAt ? new : old
        }
        result.studySessions = mergeByID(current.studySessions, incoming.studySessions) { old, new in
            new.startDate >= old.startDate ? new : old
        }
        result.timeInvestmentSubjects = mergeByID(
            current.timeInvestmentSubjects, incoming.timeInvestmentSubjects
        ) { old, new in
            new.createdAt >= old.createdAt ? new : old
        }
        result.subTasks = mergeByID(current.subTasks, incoming.subTasks) { old, new in
            new.createdAt >= old.createdAt ? new : old
        }
        result.goalRewards = mergeByID(current.goalRewards, incoming.goalRewards) { old, new in
            var selected = new.createdAt >= old.createdAt ? new : old
            selected.unlockedAt = old.unlockedAt ?? new.unlockedAt
            return selected
        }
        result.coachGoals = mergeByID(current.coachGoals, incoming.coachGoals) { old, new in
            new.updatedAt >= old.updatedAt ? new : old
        }
        result.coachAnalyses = mergeByID(current.coachAnalyses, incoming.coachAnalyses) { old, new in
            new.calculatedAt >= old.calculatedAt ? new : old
        }
        result.coachProposals = mergeByID(current.coachProposals, incoming.coachProposals) { old, new in
            new.createdAt >= old.createdAt ? new : old
        }
        result.coachChats = mergeByID(current.coachChats, incoming.coachChats) { old, new in
            new.updatedAt >= old.updatedAt ? new : old
        }
        result.coachMessages = mergeByID(current.coachMessages, incoming.coachMessages) { old, new in
            new.createdAt >= old.createdAt ? new : old
        }
        if current.plantState.lastUpdated > incoming.plantState.lastUpdated {
            result.plantState = current.plantState
        }
        return result
    }

    private static func mergeByID<T: Identifiable>(
        _ current: [T],
        _ incoming: [T],
        choose: (T, T) -> T
    ) -> [T] where T.ID == UUID {
        var values = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for value in incoming {
            values[value.id] = values[value.id].map { choose($0, value) } ?? value
        }
        return Array(values.values)
    }

    private struct StagedMediaFile: @unchecked Sendable {
        var stagedURL: URL
        var destinationURL: URL
    }

    private struct MediaStageResult: @unchecked Sendable {
        var content: BackupDecodedContent
        var stagingDirectory: URL?
        var files: [StagedMediaFile]
        var warnings: [String]

        nonisolated func cleanup() {
            guard let stagingDirectory else { return }
            try? FileManager.default.removeItem(at: stagingDirectory)
        }

        @MainActor
        func commit() throws {
            var committed: [URL] = []
            do {
                for file in files {
                    try FileManager.default.createDirectory(
                        at: file.destinationURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    if FileManager.default.fileExists(atPath: file.destinationURL.path) {
                        let sourceHash = try BackupChecksum.sha256(fileURL: file.stagedURL)
                        let destinationHash = try BackupChecksum.sha256(fileURL: file.destinationURL)
                        guard sourceHash == destinationHash else {
                            throw BackupError.restoreFailed(
                                "Media destination changed during restore: \(file.destinationURL.lastPathComponent)"
                            )
                        }
                        try FileManager.default.removeItem(at: file.stagedURL)
                        continue
                    }
                    try FileManager.default.moveItem(
                        at: file.stagedURL,
                        to: file.destinationURL
                    )
                    committed.append(file.destinationURL)
                }
            } catch {
                for url in committed.reversed() {
                    try? FileManager.default.removeItem(at: url)
                }
                throw error
            }
        }
    }

    private static func stageMedia(
        content: BackupDecodedContent,
        extractedDirectory: URL,
        includesMedia: Bool
    ) async throws -> MediaStageResult {
        guard includesMedia else {
            return MediaStageResult(
                content: content,
                stagingDirectory: nil,
                files: [],
                warnings: []
            )
        }
        return try await Task.detached(priority: .userInitiated) {
            var adjusted = content
            let stagingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("StudyPulseRestoreMedia-\(UUID().uuidString)", isDirectory: true)
            var removeStagingOnExit = true
            defer {
                if removeStagingOnExit {
                    try? FileManager.default.removeItem(at: stagingDirectory)
                }
            }
            let stagedImages = stagingDirectory.appendingPathComponent("images", isDirectory: true)
            let stagedAudio = stagingDirectory.appendingPathComponent("audio", isDirectory: true)
            var files: [StagedMediaFile] = []
            var warnings: [String] = []
            var imageMapping: [String: String] = [:]
            var audioMapping: [String: String] = [:]
            let imageSource = extractedDirectory.appendingPathComponent("media/images")
            let audioSource = extractedDirectory.appendingPathComponent("media/audio")
            let imageDestination = ImageStorage.imagesDirectory()
            let audioDestination = AudioStorage.audioDirectoryURL

            let imageNames = Set(adjusted.grades.compactMap(\.imageFileName) + [adjusted.profile.avatarFileName].compactMap { $0 })
            for name in imageNames {
                if let mapped = try stageMediaFile(
                    name,
                    source: imageSource,
                    destination: imageDestination,
                    stagingDestination: stagedImages,
                    files: &files
                ) {
                    imageMapping[name] = mapped
                } else {
                    warnings.append("Missing image: \(name)")
                }
            }
            for name in Set(adjusted.mistakes.compactMap(\.audioFileName)) {
                if let mapped = try stageMediaFile(
                    name,
                    source: audioSource,
                    destination: audioDestination,
                    stagingDestination: stagedAudio,
                    files: &files
                ) {
                    audioMapping[name] = mapped
                } else {
                    warnings.append("Missing audio: \(name)")
                }
            }
            adjusted.grades = adjusted.grades.map {
                var value = $0
                if let old = value.imageFileName { value.imageFileName = imageMapping[old] }
                return value
            }
            if let old = adjusted.profile.avatarFileName {
                adjusted.profile.avatarFileName = imageMapping[old]
            }
            adjusted.mistakes = adjusted.mistakes.map {
                var value = $0
                if let old = value.audioFileName { value.audioFileName = audioMapping[old] }
                return value
            }
            removeStagingOnExit = false
            return MediaStageResult(
                content: adjusted,
                stagingDirectory: stagingDirectory,
                files: files,
                warnings: warnings
            )
        }.value
    }

    private nonisolated static func stageMediaFile(
        _ name: String,
        source: URL,
        destination: URL?,
        stagingDestination: URL,
        files: inout [StagedMediaFile]
    ) throws -> String? {
        guard BackupArchive.isSafeRelativePath(name), URL(fileURLWithPath: name).lastPathComponent == name,
              let destination else { return nil }
        let sourceURL = source.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }
        var finalName = name
        var target = destination.appendingPathComponent(finalName)
        if FileManager.default.fileExists(atPath: target.path) {
            if try BackupChecksum.sha256(fileURL: sourceURL) == BackupChecksum.sha256(fileURL: target) {
                return finalName
            }
            finalName = "\(UUID().uuidString)-\(name)"
            target = destination.appendingPathComponent(finalName)
        }
        try FileManager.default.createDirectory(
            at: stagingDestination,
            withIntermediateDirectories: true
        )
        let stagedURL = stagingDestination.appendingPathComponent(finalName)
        try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
        files.append(StagedMediaFile(stagedURL: stagedURL, destinationURL: target))
        return finalName
    }

    private static func verifyImported(_ expected: BackupDecodedContent, actual: BackupDecodedContent) throws {
        let pairs: [(String, Int, Int)] = [
            ("subjects", expected.subjects.count, actual.subjects.count),
            ("grades", expected.grades.count, actual.grades.count),
            ("mistakes", expected.mistakes.count, actual.mistakes.count),
            ("exams", expected.exams.count, actual.exams.count),
            ("tasks", expected.tasks.count, actual.tasks.count),
            ("phases", expected.phases.count, actual.phases.count),
            ("routines", expected.routines.count, actual.routines.count),
            ("diaryEntries", expected.diaryEntries.count, actual.diaryEntries.count),
            ("studySessions", expected.studySessions.count, actual.studySessions.count),
            ("timeInvestmentSubjects", expected.timeInvestmentSubjects.count, actual.timeInvestmentSubjects.count),
            ("subTasks", expected.subTasks.count, actual.subTasks.count),
            ("goalRewards", expected.goalRewards.count, actual.goalRewards.count),
        ]
        if let mismatch = pairs.first(where: { $0.1 != $0.2 }) {
            throw BackupError.countMismatch(mismatch.0)
        }
    }
}
