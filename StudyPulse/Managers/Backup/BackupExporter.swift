import Foundation
import SwiftData

nonisolated struct BackupExportResult: Sendable {
    var archiveURL: URL
    var manifest: BackupManifest
}

private struct BackupSourceSnapshot: @unchecked Sendable {
    var subjects: [Subject]
    var grades: [Grade]
    var mistakes: [MistakeNote]
    var exams: [Exam]
    var comprehensiveExams: [comprehensiveExam]
    var tasks: [TaskItem]
    var phases: [StudyPhase]
    var routines: [Routine]
    var routineInstances: [RoutineInstance]
    var diaryEntries: [DiaryEntry]
    var studySessions: [StudySession]
    var timeInvestmentSubjects: [TimeInvestmentSubject]
    var subTasks: [SubTask]
    var goalRewards: [GoalReward]
    var profile: UserProfile
    var plantState: PlantState
    var achievements: AchievementsSnapshot
    var coachGoals: [CoachGoal]
    var coachAnalyses: [CoachAnalysis]
    var coachProposals: [CoachProposal]
    var coachChats: [CoachChat]
    var coachMessages: [CoachConversationMessage]
    var preferences: BackupPreferencesDTO
    var healthHistory: [DailyHealthSnapshot]?
}

@MainActor
enum BackupExporter {
    static func export(
        container: RepositoryContainer,
        options: BackupExportOptions,
        progress: @escaping @MainActor (Double) -> Void = { _ in }
    ) async throws -> BackupExportResult {
        progress(0.03)
        let context = container.modelContainer?.mainContext
        let plant = (try? context?.fetch(FetchDescriptor<PlantStateRecord>()).first?.toSnapshot())
            ?? PlantState(
                currentStage: PlantManager.shared.currentStage,
                history: PlantManager.shared.history,
                lastUpdated: PlantManager.shared.lastUpdated,
                lastActivityAt: PlantManager.shared.lastActivityDate
            )
        // Decode the store's legacy/default Date representation into value
        // types, then let the backup encoder write canonical ISO-8601 dates.
        // Copying health_history.json byte-for-byte would make it incompatible
        // with the backup decoder when the sensitive-history option is enabled.
        let healthHistory = options.includesDerivedHealthData
            ? HealthHistoryStore.load()
            : nil
        let sessions = container.studySessionRepo.allSessionsForBackup().map { session -> StudySession in
            guard !options.includesDerivedHealthData else { return session }
            return StudySession(
                id: session.id,
                startDate: session.startDate,
                durationSeconds: session.durationSeconds,
                intensity: session.intensity,
                completed: session.completed,
                heartRateSamples: nil,
                difficultyAnnotations: session.difficultyAnnotations,
                investmentTarget: session.investmentTarget,
                source: session.source,
                timeZoneIdentifier: session.timeZoneIdentifier
            )
        }
        let source = BackupSourceSnapshot(
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
            studySessions: sessions,
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
            healthHistory: healthHistory
        )
        progress(0.1)
        let result = try await Task.detached(priority: .userInitiated) {
            try buildArchive(source: source, options: options)
        }.value
        progress(1)
        UserDefaults.standard.set(result.manifest.createdAt, forKey: "studyPulse.lastFullBackupAt")
        return result
    }

    private nonisolated static func buildArchive(
        source: BackupSourceSnapshot,
        options: BackupExportOptions
    ) throws -> BackupExportResult {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("StudyPulseBackup-\(UUID().uuidString)", isDirectory: true)
        let dataDirectory = root.appendingPathComponent("data", isDirectory: true)
        let mediaImages = root.appendingPathComponent("media/images", isDirectory: true)
        let mediaAudio = root.appendingPathComponent("media/audio", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

        var files: [String: Data] = [:]
        let encoder = BackupDateCoding.encoder(pretty: true)
        files["data/subjects.json"] = try encoder.encode(source.subjects)
        files["data/grades.jsonl"] = try jsonl(source.grades, updatedAt: { _ in nil })
        files["data/mistakes.jsonl"] = try jsonl(source.mistakes, updatedAt: { _ in nil })
        files["data/exams.jsonl"] = try jsonl(source.exams, updatedAt: { _ in nil })
        files["data/comprehensive_exams.jsonl"] = try jsonl(source.comprehensiveExams, updatedAt: { _ in nil })
        files["data/tasks.jsonl"] = try jsonl(source.tasks, updatedAt: { _ in nil })
        files["data/phases.jsonl"] = try jsonl(source.phases, updatedAt: { _ in nil })
        files["data/routines.jsonl"] = try jsonl(source.routines, updatedAt: { $0.createdAt })
        files["data/routine_instances.jsonl"] = try jsonl(source.routineInstances, updatedAt: { $0.completedAt ?? $0.date })
        files["data/diary_entries.jsonl"] = try jsonl(source.diaryEntries, updatedAt: { $0.updatedAt })
        files["data/study_sessions.jsonl"] = try jsonl(source.studySessions, updatedAt: { $0.startDate })
        files["data/time_investment_subjects.jsonl"] = try jsonl(source.timeInvestmentSubjects, updatedAt: { $0.createdAt })
        files["data/time_investment_subtasks.jsonl"] = try jsonl(source.subTasks, updatedAt: { $0.createdAt })
        files["data/goal_rewards.jsonl"] = try jsonl(source.goalRewards, updatedAt: { $0.unlockedAt ?? $0.createdAt })
        files["data/profile.json"] = try encoder.encode(source.profile)
        files["data/plant_state.json"] = try encoder.encode(source.plantState)
        files["data/achievements.json"] = try encoder.encode(source.achievements)
        files["data/coach_data.jsonl"] = try encodeCoach(source)
        files["data/preferences.json"] = try encoder.encode(source.preferences)
        if let healthHistory = source.healthHistory {
            files["data/health_history.json"] = try encoder.encode(healthHistory)
        }

        for (path, data) in files {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }

        var warnings: [String] = []
        var mediaCount = 0
        var mediaBytes: Int64 = 0
        if options.includesMedia {
            try fm.createDirectory(at: mediaImages, withIntermediateDirectories: true)
            try fm.createDirectory(at: mediaAudio, withIntermediateDirectories: true)
            let imageNames = Set(source.grades.compactMap(\.imageFileName) + [source.profile.avatarFileName].compactMap { $0 })
            let audioNames = Set(source.mistakes.compactMap(\.audioFileName))
            for name in imageNames {
                try copyReferencedMedia(name: name, sourceDirectory: ImageStorage.imagesDirectory(), destination: mediaImages, category: "image", warnings: &warnings, count: &mediaCount, bytes: &mediaBytes)
            }
            for name in audioNames {
                try copyReferencedMedia(name: name, sourceDirectory: AudioStorage.audioDirectoryURL, destination: mediaAudio, category: "audio", warnings: &warnings, count: &mediaCount, bytes: &mediaBytes)
            }
        }

        let counts = recordCounts(source)
        let manifest = BackupManifest(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            recordCounts: counts,
            includesMedia: options.includesMedia,
            includesDerivedHealthData: options.includesDerivedHealthData,
            locale: Locale.current.identifier,
            mediaFileCount: mediaCount,
            mediaBytes: mediaBytes,
            missingMediaCount: warnings.count,
            warnings: warnings
        )
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: root.appendingPathComponent("manifest.json"), options: .atomic)

        var checksumFiles = files
        checksumFiles["manifest.json"] = manifestData
        if options.includesMedia {
            let mediaRoot = root.appendingPathComponent("media")
            if let enumerator = fm.enumerator(at: mediaRoot, includingPropertiesForKeys: [.isRegularFileKey]) {
                while let url = enumerator.nextObject() as? URL,
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    let relative = String(url.path.dropFirst(root.path.count + 1))
                    checksumFiles[relative] = try Data(contentsOf: url)
                }
            }
        }
        let checksums = BackupChecksums(files: checksumFiles.mapValues(BackupChecksum.sha256(data:)))
        try encoder.encode(checksums).write(to: root.appendingPathComponent("checksums.json"), options: .atomic)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let archiveURL = fm.temporaryDirectory.appendingPathComponent("StudyPulse-\(formatter.string(from: manifest.createdAt)).studypulsebackup")
        try? fm.removeItem(at: archiveURL)
        try BackupArchive.create(from: root, at: archiveURL)
        return BackupExportResult(archiveURL: archiveURL, manifest: manifest)
    }

    private nonisolated static func jsonl<T: Codable & Identifiable>(
        _ values: [T],
        updatedAt: (T) -> Date?
    ) throws -> Data where T.ID == UUID {
        try BackupJSONL.encode(values.map { BackupRecordDTO(id: $0.id, updatedAt: updatedAt($0), value: $0) })
    }

    private nonisolated static func encodeCoach(_ source: BackupSourceSnapshot) throws -> Data {
        let encoder = BackupDateCoding.encoder()
        var rows: [BackupCoachRow] = []
        rows += try source.coachGoals.map { BackupCoachRow(kind: .goal, payload: try encoder.encode($0)) }
        rows += try source.coachAnalyses.map { BackupCoachRow(kind: .analysis, payload: try encoder.encode($0)) }
        rows += try source.coachProposals.map { BackupCoachRow(kind: .proposal, payload: try encoder.encode($0)) }
        rows += try source.coachChats.map { BackupCoachRow(kind: .chat, payload: try encoder.encode($0)) }
        rows += try source.coachMessages.map { BackupCoachRow(kind: .message, payload: try encoder.encode($0)) }
        return try BackupJSONL.encode(rows)
    }

    private nonisolated static func copyReferencedMedia(
        name: String,
        sourceDirectory: URL?,
        destination: URL,
        category: String,
        warnings: inout [String],
        count: inout Int,
        bytes: inout Int64
    ) throws {
        guard BackupArchive.isSafeRelativePath(name), URL(fileURLWithPath: name).lastPathComponent == name,
              let sourceDirectory else {
            warnings.append("Unsafe or unavailable \(category): \(name)")
            return
        }
        let source = sourceDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: source.path) else {
            warnings.append("Missing \(category): \(name)")
            return
        }
        var safeName = name
        var target = destination.appendingPathComponent(safeName)
        if FileManager.default.fileExists(atPath: target.path) {
            safeName = "\(UUID().uuidString)-\(name)"
            target = destination.appendingPathComponent(safeName)
        }
        try FileManager.default.copyItem(at: source, to: target)
        count += 1
        bytes += Int64((try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private nonisolated static func recordCounts(_ s: BackupSourceSnapshot) -> [String: Int] {
        [
            "subjects": s.subjects.count, "grades": s.grades.count, "mistakes": s.mistakes.count,
            "exams": s.exams.count, "comprehensiveExams": s.comprehensiveExams.count,
            "tasks": s.tasks.count, "phases": s.phases.count, "routines": s.routines.count,
            "routineInstances": s.routineInstances.count, "diaryEntries": s.diaryEntries.count,
            "studySessions": s.studySessions.count, "profile": 1, "plantState": 1,
            "timeInvestmentSubjects": s.timeInvestmentSubjects.count,
            "subTasks": s.subTasks.count, "goalRewards": s.goalRewards.count,
            "achievements": 1, "coachGoals": s.coachGoals.count,
            "coachAnalyses": s.coachAnalyses.count, "coachProposals": s.coachProposals.count,
            "coachChats": s.coachChats.count, "coachMessages": s.coachMessages.count
        ]
    }
}
