import Foundation

nonisolated struct BackupDecodedContent: @unchecked Sendable {
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

nonisolated struct ValidatedBackup: @unchecked Sendable {
    var manifest: BackupManifest
    var content: BackupDecodedContent
    var extractedDirectory: URL
    var warnings: [String]

    func cleanup() {
        try? FileManager.default.removeItem(at: extractedDirectory)
    }
}

nonisolated enum BackupValidator {
    static let requiredFiles = [
        "manifest.json", "checksums.json", "data/subjects.json", "data/grades.jsonl",
        "data/mistakes.jsonl", "data/exams.jsonl", "data/comprehensive_exams.jsonl",
        "data/tasks.jsonl", "data/phases.jsonl", "data/routines.jsonl",
        "data/routine_instances.jsonl", "data/diary_entries.jsonl",
        "data/study_sessions.jsonl", "data/profile.json", "data/plant_state.json",
        "data/achievements.json", "data/coach_data.jsonl", "data/preferences.json",
    ]

    static func validate(archiveURL: URL, password: String? = nil) async throws -> ValidatedBackup {
        try await Task.detached(priority: .userInitiated) {
            try validateSynchronously(archiveURL: archiveURL, password: password)
        }.value
    }

    static func validateSynchronously(archiveURL: URL, password: String? = nil) throws -> ValidatedBackup {
        let fm = FileManager.default
        let workspace = fm.temporaryDirectory.appendingPathComponent("StudyPulseRestore-\(UUID().uuidString)", isDirectory: true)
        var decryptedZip: URL?
        defer {
            if let decryptedZip {
                try? fm.removeItem(at: decryptedZip)
            }
        }
        do {
            let zipURL: URL
            if try BackupEncryption.isEncryptedEnvelope(at: archiveURL) {
                let tempZip = fm.temporaryDirectory.appendingPathComponent(
                    "StudyPulseDecrypt-\(UUID().uuidString).zip"
                )
                decryptedZip = tempZip
                try BackupEncryption.decryptFile(
                    from: archiveURL,
                    to: tempZip,
                    password: password
                )
                zipURL = tempZip
            } else {
                zipURL = archiveURL
            }
            try BackupArchive.extractSafely(from: zipURL, to: workspace)
            for path in requiredFiles where !fm.fileExists(atPath: workspace.appendingPathComponent(path).path) {
                if path == "manifest.json" { throw BackupError.missingManifest }
                throw BackupError.missingRequiredFile(path)
            }

            let decoder = BackupDateCoding.decoder()
            let manifest = try decode(BackupManifest.self, at: "manifest.json", root: workspace, decoder: decoder)
            guard manifest.formatIdentifier == BackupManifest.expectedFormatIdentifier else {
                throw BackupError.invalidFormatIdentifier
            }
            guard manifest.formatVersion == BackupManifest.currentFormatVersion else {
                throw BackupError.unsupportedFormatVersion(manifest.formatVersion)
            }
            let actuallyEncrypted = decryptedZip != nil
            guard manifest.encrypted == actuallyEncrypted else {
                throw BackupError.encryptionInconsistent
            }

            let checksums = try decode(BackupChecksums.self, at: "checksums.json", root: workspace, decoder: decoder)
            guard checksums.algorithm.uppercased() == "SHA-256" else {
                throw BackupError.malformedData("checksums.json")
            }
            for (path, expected) in checksums.files {
                guard BackupArchive.isSafeRelativePath(path) else { throw BackupError.dangerousPath(path) }
                let url = workspace.appendingPathComponent(path)
                guard fm.fileExists(atPath: url.path) else { throw BackupError.missingRequiredFile(path) }
                guard try BackupChecksum.sha256(fileURL: url) == expected.lowercased() else {
                    throw BackupError.checksumMismatch(path)
                }
            }
            for path in requiredFiles where path != "checksums.json" && checksums.files[path] == nil {
                throw BackupError.missingRequiredFile("checksum:\(path)")
            }

            let integrityURL = workspace.appendingPathComponent("integrity.json")
            if fm.fileExists(atPath: integrityURL.path) {
                let integrity = try decode(BackupIntegrity.self, at: "integrity.json", root: workspace, decoder: decoder)
                try BackupChecksum.verifyIntegrity(integrity, checksums: checksums, password: password)
            } else if actuallyEncrypted {
                // AES-GCM already authenticated the outer envelope. SHA-256
                // checksums remain a corruption check only.
            } else {
                throw BackupError.missingAuthentication
            }

            let subjects = try decode([Subject].self, at: "data/subjects.json", root: workspace, decoder: decoder)
            let grades: [Grade] = try decodeJSONL("data/grades.jsonl", root: workspace)
            let mistakes: [MistakeNote] = try decodeJSONL("data/mistakes.jsonl", root: workspace)
            let exams: [Exam] = try decodeJSONL("data/exams.jsonl", root: workspace)
            let comps: [comprehensiveExam] = try decodeJSONL("data/comprehensive_exams.jsonl", root: workspace)
            let tasks: [TaskItem] = try decodeJSONL("data/tasks.jsonl", root: workspace)
            let phases: [StudyPhase] = try decodeJSONL("data/phases.jsonl", root: workspace)
            let routines: [Routine] = try decodeJSONL("data/routines.jsonl", root: workspace)
            let instances: [RoutineInstance] = try decodeJSONL("data/routine_instances.jsonl", root: workspace)
            let diary: [DiaryEntry] = try decodeJSONL("data/diary_entries.jsonl", root: workspace)
            let sessions: [StudySession] = try decodeJSONL("data/study_sessions.jsonl", root: workspace)
            let investmentSubjects: [TimeInvestmentSubject] = try decodeOptionalJSONL(
                "data/time_investment_subjects.jsonl", root: workspace
            )
            let subTasks: [SubTask] = try decodeOptionalJSONL(
                "data/time_investment_subtasks.jsonl", root: workspace
            )
            let rewards: [GoalReward] = try decodeOptionalJSONL(
                "data/goal_rewards.jsonl", root: workspace
            )
            let profile = try decode(UserProfile.self, at: "data/profile.json", root: workspace, decoder: decoder)
            let plant = try decode(PlantState.self, at: "data/plant_state.json", root: workspace, decoder: decoder)
            let achievements = try decode(AchievementsSnapshot.self, at: "data/achievements.json", root: workspace, decoder: decoder)
            let preferences = try decode(BackupPreferencesDTO.self, at: "data/preferences.json", root: workspace, decoder: decoder)
            let coach = try decodeCoach(at: workspace.appendingPathComponent("data/coach_data.jsonl"))
            let health: [DailyHealthSnapshot]?
            let healthURL = workspace.appendingPathComponent("data/health_history.json")
            if manifest.includesDerivedHealthData, fm.fileExists(atPath: healthURL.path) {
                let data = try Data(contentsOf: healthURL)
                do {
                    health = try decoder.decode([DailyHealthSnapshot].self, from: data)
                } catch {
                    // Compatibility with early v1 backups that copied the
                    // app's legacy JSON file using Foundation's default Date
                    // representation instead of canonical ISO-8601.
                    do {
                        health = try JSONDecoder().decode([DailyHealthSnapshot].self, from: data)
                    } catch {
                        throw BackupError.malformedData("data/health_history.json")
                    }
                }
            } else {
                health = nil
            }

            let content = BackupDecodedContent(
                subjects: subjects, grades: grades, mistakes: mistakes, exams: exams,
                comprehensiveExams: comps, tasks: tasks, phases: phases, routines: routines,
                routineInstances: instances, diaryEntries: diary, studySessions: sessions,
                timeInvestmentSubjects: investmentSubjects, subTasks: subTasks, goalRewards: rewards,
                profile: profile, plantState: plant, achievements: achievements,
                coachGoals: coach.goals, coachAnalyses: coach.analyses,
                coachProposals: coach.proposals, coachChats: coach.chats,
                coachMessages: coach.messages, preferences: preferences, healthHistory: health
            )
            try validateRelationships(content)
            try validateCounts(manifest.recordCounts, content)
            return ValidatedBackup(
                manifest: manifest,
                content: content,
                extractedDirectory: workspace,
                warnings: manifest.warnings
            )
        } catch {
            try? fm.removeItem(at: workspace)
            throw error
        }
    }

    private static func decode<T: Decodable>(
        _ type: T.Type, at path: String, root: URL, decoder: JSONDecoder
    ) throws -> T {
        do {
            return try decoder.decode(type, from: Data(contentsOf: root.appendingPathComponent(path)))
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.malformedData(path)
        }
    }

    private static func decodeJSONL<T: Codable & Identifiable>(
        _ path: String, root: URL
    ) throws -> [T] where T.ID == UUID {
        let data: Data
        do {
            data = try Data(contentsOf: root.appendingPathComponent(path))
        } catch {
            throw BackupError.malformedData(path)
        }
        let rows = try BackupJSONL.decode(BackupRecordDTO<T>.self, from: data, path: path)
        guard rows.allSatisfy({ $0.id == $0.value.id }) else {
            throw BackupError.invalidRelationship("record id mismatch in \(path)")
        }
        guard Set(rows.map(\.id)).count == rows.count else {
            throw BackupError.invalidRelationship("duplicate UUID in \(path)")
        }
        return rows.map(\.value)
    }

    private static func decodeOptionalJSONL<T: Codable & Identifiable>(
        _ path: String, root: URL
    ) throws -> [T] where T.ID == UUID {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) else {
            return []
        }
        return try decodeJSONL(path, root: root)
    }

    private static func decodeCoach(at url: URL) throws -> (
        goals: [CoachGoal], analyses: [CoachAnalysis], proposals: [CoachProposal],
        chats: [CoachChat], messages: [CoachConversationMessage]
    ) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.malformedData("data/coach_data.jsonl")
        }
        let rows = try BackupJSONL.decode(BackupCoachRow.self, from: data, path: "data/coach_data.jsonl")
        let decoder = BackupDateCoding.decoder()
        var goals: [CoachGoal] = []
        var analyses: [CoachAnalysis] = []
        var proposals: [CoachProposal] = []
        var chats: [CoachChat] = []
        var messages: [CoachConversationMessage] = []
        do {
            for row in rows {
                switch row.kind {
                case .goal: goals.append(try decoder.decode(CoachGoal.self, from: row.payload))
                case .analysis: analyses.append(try decoder.decode(CoachAnalysis.self, from: row.payload))
                case .proposal: proposals.append(try decoder.decode(CoachProposal.self, from: row.payload))
                case .chat: chats.append(try decoder.decode(CoachChat.self, from: row.payload))
                case .message: messages.append(try decoder.decode(CoachConversationMessage.self, from: row.payload))
                }
            }
        } catch {
            throw BackupError.malformedData("data/coach_data.jsonl")
        }
        return (goals, analyses, proposals, chats, messages)
    }

    static func validateRelationships(_ c: BackupDecodedContent) throws {
        let phaseIDs = Set(c.phases.map(\.id))
        let referencedPhaseIDs =
            c.grades.compactMap(\.phaseId) + c.mistakes.compactMap(\.phaseId)
            + c.exams.compactMap(\.phaseId) + c.comprehensiveExams.compactMap(\.phaseId)
            + c.tasks.compactMap(\.phaseId) + c.routines.compactMap(\.phaseId)
            + c.diaryEntries.compactMap(\.phaseId)
        guard referencedPhaseIDs.allSatisfy(phaseIDs.contains) else {
            throw BackupError.invalidRelationship("unknown phase UUID")
        }
        let routineIDs = Set(c.routines.map(\.id))
        guard c.routineInstances.allSatisfy({ routineIDs.contains($0.routineId) }) else {
            throw BackupError.invalidRelationship("unknown routine UUID")
        }
        let examIDs = Set(c.exams.map(\.id))
        guard c.grades.compactMap(\.examId).allSatisfy(examIDs.contains) else {
            throw BackupError.invalidRelationship("unknown exam UUID")
        }
        let goalIDs = Set(c.coachGoals.map(\.id))
        let chatIDs = Set(c.coachChats.map(\.id))
        guard c.coachChats.compactMap(\.goalID).allSatisfy(goalIDs.contains),
              c.coachMessages.allSatisfy({ chatIDs.contains($0.chatID) }),
              c.coachMessages.compactMap(\.goalID).allSatisfy(goalIDs.contains) else {
            throw BackupError.invalidRelationship("Coach goal or chat UUID")
        }

        let investmentSubjectIDs = Set(c.timeInvestmentSubjects.map(\.id))
        let subTaskIDs = Set(c.subTasks.map(\.id))
        guard c.subTasks.allSatisfy({ investmentSubjectIDs.contains($0.subjectID) }) else {
            throw BackupError.invalidRelationship("unknown time investment subject UUID")
        }
        // 重复 id 的备份不 trap;后续层级校验仍会按首条展开 / Duplicate ids must not trap here.
        let subTaskMap = Dictionary(c.subTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for task in c.subTasks {
            var seen: Set<UUID> = [task.id]
            var parentID = task.parentSubTaskID
            var depth = 1
            while let id = parentID {
                guard let parent = subTaskMap[id],
                      parent.subjectID == task.subjectID,
                      seen.insert(id).inserted else {
                    throw BackupError.invalidRelationship("invalid subtask hierarchy")
                }
                depth += 1
                guard depth <= 2 else {
                    throw BackupError.invalidRelationship("subtask hierarchy exceeds maximum depth")
                }
                parentID = parent.parentSubTaskID
            }
        }
        func validTarget(_ target: InvestmentTarget) -> Bool {
            switch target {
            case .subject(let id): return investmentSubjectIDs.contains(id)
            case .subTask(let id): return subTaskIDs.contains(id)
            }
        }
        guard c.goalRewards.allSatisfy({ validTarget($0.target) }),
              c.studySessions.compactMap(\.investmentTarget).allSatisfy(validTarget) else {
            throw BackupError.invalidRelationship("unknown time investment target UUID")
        }
    }

    static func validateCounts(_ expected: [String: Int], _ c: BackupDecodedContent) throws {
        let actual: [String: Int] = [
            "subjects": c.subjects.count, "grades": c.grades.count, "mistakes": c.mistakes.count,
            "exams": c.exams.count, "comprehensiveExams": c.comprehensiveExams.count,
            "tasks": c.tasks.count, "phases": c.phases.count, "routines": c.routines.count,
            "routineInstances": c.routineInstances.count, "diaryEntries": c.diaryEntries.count,
            "studySessions": c.studySessions.count, "profile": 1, "plantState": 1,
            "timeInvestmentSubjects": c.timeInvestmentSubjects.count,
            "subTasks": c.subTasks.count, "goalRewards": c.goalRewards.count,
            "achievements": 1, "coachGoals": c.coachGoals.count,
            "coachAnalyses": c.coachAnalyses.count, "coachProposals": c.coachProposals.count,
            "coachChats": c.coachChats.count, "coachMessages": c.coachMessages.count,
        ]
        for (key, count) in actual {
            if let expectedCount = expected[key], expectedCount != count {
                throw BackupError.countMismatch(key)
            }
        }
    }
}
