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
        content = mediaResult.content
        progress(0.4)

        do {
            try replacePersistentContent(content, context: context)
            progress(0.68)
            AchievementStore.save(content.achievements)
            container.envManager.preferences = content.preferences.applying(to: container.envManager.preferences)
            if let health = content.healthHistory {
                HealthHistoryStore.save(health)
            }
            await container.reloadAllAfterBackupRestore()
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
            for url in mediaResult.createdFiles { try? FileManager.default.removeItem(at: url) }
            throw error
        }
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
            throw BackupError.restoreFailed(error.localizedDescription)
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
        var values = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for value in incoming {
            values[value.id] = values[value.id].map { choose($0, value) } ?? value
        }
        return Array(values.values)
    }

    private struct MediaStageResult: @unchecked Sendable {
        var content: BackupDecodedContent
        var createdFiles: [URL]
        var warnings: [String]
    }

    private static func stageMedia(
        content: BackupDecodedContent,
        extractedDirectory: URL,
        includesMedia: Bool
    ) async throws -> MediaStageResult {
        guard includesMedia else {
            return MediaStageResult(content: content, createdFiles: [], warnings: [])
        }
        return try await Task.detached(priority: .userInitiated) {
            var adjusted = content
            var created: [URL] = []
            var warnings: [String] = []
            var imageMapping: [String: String] = [:]
            var audioMapping: [String: String] = [:]
            let imageSource = extractedDirectory.appendingPathComponent("media/images")
            let audioSource = extractedDirectory.appendingPathComponent("media/audio")
            let imageDestination = ImageStorage.imagesDirectory()
            let audioDestination = AudioStorage.audioDirectoryURL

            let imageNames = Set(adjusted.grades.compactMap(\.imageFileName) + [adjusted.profile.avatarFileName].compactMap { $0 })
            for name in imageNames {
                if let mapped = try importMedia(name, source: imageSource, destination: imageDestination, created: &created) {
                    imageMapping[name] = mapped
                } else {
                    warnings.append("Missing image: \(name)")
                }
            }
            for name in Set(adjusted.mistakes.compactMap(\.audioFileName)) {
                if let mapped = try importMedia(name, source: audioSource, destination: audioDestination, created: &created) {
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
            return MediaStageResult(content: adjusted, createdFiles: created, warnings: warnings)
        }.value
    }

    private nonisolated static func importMedia(
        _ name: String,
        source: URL,
        destination: URL?,
        created: inout [URL]
    ) throws -> String? {
        guard BackupArchive.isSafeRelativePath(name), URL(fileURLWithPath: name).lastPathComponent == name,
              let destination else { return nil }
        let sourceURL = source.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var finalName = name
        var target = destination.appendingPathComponent(finalName)
        if FileManager.default.fileExists(atPath: target.path) {
            if try BackupChecksum.sha256(fileURL: sourceURL) == BackupChecksum.sha256(fileURL: target) {
                return finalName
            }
            finalName = "\(UUID().uuidString)-\(name)"
            target = destination.appendingPathComponent(finalName)
        }
        try FileManager.default.copyItem(at: sourceURL, to: target)
        created.append(target)
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
