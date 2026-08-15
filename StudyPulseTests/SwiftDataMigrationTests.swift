import Foundation
import SwiftData
import XCTest
@testable import StudyPulse

@MainActor
final class SwiftDataMigrationTests: XCTestCase {
    func testV3StoreMigratesToV5AndAcceptsTimeInvestmentRecords() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("studypulse.store")

        do {
            let schema = Schema(versionedSchema: StudyPulseSchemaV3.self)
            let configuration = ModelConfiguration(
                "StudyPulse",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            container.mainContext.insert(SubjectRecord(from: Subject(name: "Existing")))
            try container.mainContext.save()
        }

        let schema = Schema(versionedSchema: StudyPulseSchemaV5.self)
        let configuration = ModelConfiguration(
            "StudyPulse",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let migrated = try ModelContainer(
            for: schema,
            migrationPlan: StudyPulseMigrationPlan.self,
            configurations: [configuration]
        )
        XCTAssertEqual(
            try migrated.mainContext.fetchCount(FetchDescriptor<SubjectRecord>()),
            1
        )
        migrated.mainContext.insert(
            TimeInvestmentSubjectRecord(
                from: TimeInvestmentSubject(name: "Long-term Chemistry")
            )
        )
        try migrated.mainContext.save()
        XCTAssertEqual(
            try migrated.mainContext.fetchCount(
                FetchDescriptor<TimeInvestmentSubjectRecord>()
            ),
            1
        )
    }

    func testV1StoreMigratesToV2WithoutChangingUserEntityCountsOrKeyFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("studypulse.store")
        let fixture = try createV1Store(at: storeURL)

        let v2Schema = Schema(versionedSchema: StudyPulseSchemaV2.self)
        let v2Configuration = ModelConfiguration(
            "StudyPulse",
            schema: v2Schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let migrated = try ModelContainer(
            for: v2Schema,
            migrationPlan: StudyPulseMigrationPlan.self,
            configurations: [v2Configuration]
        )
        let context = migrated.mainContext

        XCTAssertEqual(userEntityCounts(in: context), fixture.counts)

        let subject = try XCTUnwrap(context.fetch(FetchDescriptor<SubjectRecord>()).first)
        XCTAssertEqual(subject.id, fixture.subjectID)
        XCTAssertEqual(subject.name, "Mathematics")
        XCTAssertEqual(subject.displayName, "数学")
        XCTAssertEqual(subject.fullScore, 150)

        let grade = try XCTUnwrap(context.fetch(FetchDescriptor<GradeRecord>()).first)
        XCTAssertEqual(grade.id, fixture.gradeID)
        XCTAssertEqual(grade.subject, "Mathematics")
        XCTAssertEqual(grade.score, 137)
        XCTAssertEqual(grade.examName, "V1 Migration Exam")

        let mistake = try XCTUnwrap(context.fetch(FetchDescriptor<MistakeNoteRecord>()).first)
        XCTAssertEqual(mistake.title, "V1 preserved mistake")
        XCTAssertEqual(mistake.correctSolution, "Preserved answer")
        XCTAssertEqual(mistake.tags, ["migration", "critical"])

        let exam = try XCTUnwrap(context.fetch(FetchDescriptor<ExamRecord>()).first)
        XCTAssertEqual(exam.locationSchool, "Migration School")
        XCTAssertEqual(exam.locationSeat, "A-17")

        let profile = try XCTUnwrap(context.fetch(FetchDescriptor<UserProfileRecord>()).first)
        XCTAssertEqual(profile.username, "migration-user")
        XCTAssertEqual(profile.targetSchool, "Preserved University")

        let plant = try XCTUnwrap(context.fetch(FetchDescriptor<PlantStateRecord>()).first)
        XCTAssertEqual(plant.currentStageRaw, PlantStage.bloom.rawValue)
        XCTAssertEqual(plant.previousStageRaw, PlantStage.bud.rawValue)
    }

    func testFailedReplacementCanRestoreOriginalStoreBundleByteForByte() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("studypulse.store")
        let originals: [String: Data] = [
            "studypulse.store": Data("original-store".utf8),
            "studypulse.store-wal": Data("original-wal".utf8),
            "studypulse.store-shm": Data("original-shm".utf8),
        ]
        for (name, data) in originals {
            try data.write(to: directory.appendingPathComponent(name))
        }

        let backup = try XCTUnwrap(
            ModelContainerFactory.backupStoreBundle(at: storeURL)
        )

        // Simulate files left behind by a failed replacement/migration attempt.
        try Data("failed-new-store".utf8).write(to: storeURL)
        try Data("failed-new-wal".utf8).write(
            to: directory.appendingPathComponent("studypulse.store-wal")
        )

        try ModelContainerFactory.restoreStoreBundle(backup, at: storeURL)

        for (name, expectedData) in originals {
            let restored = try Data(
                contentsOf: directory.appendingPathComponent(name)
            )
            XCTAssertEqual(restored, expectedData, "\(name) was not restored")
        }
        XCTAssertTrue(
            fm.fileExists(
                atPath: backup.directory
                    .appendingPathComponent("failed-replacement/studypulse.store")
                    .path
            )
        )
    }

    private struct V1Fixture {
        let counts: [String: Int]
        let subjectID: UUID
        let gradeID: UUID
    }

    private func createV1Store(at storeURL: URL) throws -> V1Fixture {
        // Reproduce the store format shipped before a migration plan existed:
        // the same V1 model list, created through the unversioned initializer.
        let schema = Schema(StudyPulseSchemaV1.models)
        let configuration = ModelConfiguration(
            "StudyPulse",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let subjectID = UUID()
        let gradeID = UUID()
        let phaseID = UUID()
        let routineID = UUID()

        context.insert(SubjectRecord(
            id: subjectID,
            name: "Mathematics",
            enabled: true,
            fullScore: 150,
            displayName: "数学"
        ))
        context.insert(GradeRecord(
            id: gradeID,
            subject: "Mathematics",
            score: 137,
            rawScore: 135,
            ranking: 3,
            importance: 5,
            image: nil,
            imageFileName: "paper.jpg",
            date: now,
            examName: "V1 Migration Exam",
            examId: nil,
            fullScore: 150,
            phaseId: phaseID
        ))
        context.insert(MistakeNoteRecord(
            id: UUID(),
            title: "V1 preserved mistake",
            subject: "Mathematics",
            originalQuestion: "Question",
            source: "V1",
            date: now,
            errorReason: "Reason",
            wrongSolution: "Wrong",
            correctSolution: "Preserved answer",
            srsRepetitions: 2,
            srsEaseFactor: 2.5,
            srsIntervalDays: 6,
            srsNextReviewDate: now,
            srsLastReviewDate: now,
            srsLapses: 1,
            questionImagesData: [],
            reasonImagesData: [],
            wrongSolutionImagesData: [],
            correctSolutionImagesData: [],
            phaseId: phaseID,
            difficulty: 4,
            tags: ["migration", "critical"]
        ))
        context.insert(ExamRecord(
            id: UUID(),
            name: "V1 Final",
            examDate: now,
            examEndDate: now.addingTimeInterval(7_200),
            importance: 5,
            subject: "Mathematics",
            examName: "Final",
            masteryDegree: 82,
            timeSlotStart: now,
            timeSlotEnd: now.addingTimeInterval(7_200),
            phaseId: phaseID,
            locationSchool: "Migration School",
            locationClassroom: "Room 2",
            locationSeat: "A-17"
        ))
        context.insert(ComprehensiveExamRecord(
            id: UUID(),
            name: "V1 Comprehensive",
            examDate: now,
            examEndDate: nil,
            importance: 4,
            subjects: ["Mathematics", "Physics"],
            examName: "Joint Exam",
            masteryDegree: 76,
            subjectTimeSlotsData: nil,
            phaseId: phaseID
        ))
        context.insert(TaskItemRecord(
            id: UUID(),
            title: "V1 Task",
            typeRaw: TaskType.homework.rawValue,
            dueDate: now,
            reminderDate: now,
            subject: "Mathematics",
            importance: 4,
            notes: "Preserve this",
            isCompleted: false,
            reminderEventId: nil,
            reminderCalendarId: nil,
            createdAt: now,
            phaseId: phaseID
        ))
        context.insert(UserProfileRecord(
            id: UUID(),
            username: "migration-user",
            age: 17,
            educationLevel: "High School",
            educationSystem: "CN",
            region: "Shanghai",
            selectedSubjectsData: nil,
            theme: "system",
            avatarFileName: nil,
            realName: "Migration Tester",
            grade: "12",
            className: "1",
            schoolName: "Migration School",
            studentId: "V1-001",
            enrollmentYear: 2023,
            examYear: 2026,
            educationStage: "highSchool",
            regionCode: "CN-SH",
            gender: "",
            targetSchool: "Preserved University",
            targetScore: 690
        ))
        context.insert(StudyPhaseRecord(
            id: phaseID,
            name: "V1 Phase",
            startDate: now,
            endDate: now.addingTimeInterval(86_400 * 100),
            isArchived: false,
            archivedAt: nil,
            goalsData: nil,
            createdAt: now
        ))
        context.insert(PlantStateRecord(
            id: UUID(),
            currentStageRaw: PlantStage.bloom.rawValue,
            lastUpdated: now,
            previousStageRaw: PlantStage.bud.rawValue
        ))
        context.insert(RoutineRecord(
            id: routineID,
            title: "V1 Routine",
            typeRaw: RoutineType.mistakeReview.rawValue,
            subject: "Mathematics",
            weekdays: [2, 4, 6],
            startTime: now,
            endTime: now.addingTimeInterval(3_600),
            enabled: true,
            createdAt: now,
            phaseId: phaseID
        ))
        context.insert(RoutineInstanceRecord(
            id: UUID(),
            idempotencyKey: "\(routineID.uuidString)|20250615",
            routineId: routineID,
            title: "V1 Routine",
            typeRaw: RoutineType.mistakeReview.rawValue,
            subject: "Mathematics",
            startTime: now,
            endTime: now.addingTimeInterval(3_600),
            date: now,
            dateKey: "20250615",
            isCompleted: true,
            completedAt: now,
            spawnedMistakeCount: 3
        ))
        context.insert(DiaryEntryRecord(
            id: UUID(),
            date: now,
            moodScore: 4,
            energyScore: 5,
            energyTag: "focused",
            content: "V1 diary content",
            phaseId: phaseID,
            createdAt: now,
            updatedAt: now
        ))
        let coachGoal = CoachGoal(
            title: "V1 Coach Goal",
            subjects: [
                CoachGoalSubject(
                    subject: "Mathematics",
                    baselineScore: 120,
                    targetScore: 140,
                    fullScore: 150
                ),
            ],
            targetDate: now.addingTimeInterval(86_400 * 60),
            updatedAt: now
        )
        let coachAnalysis = CoachAnalysis(
            goalID: coachGoal.id,
            goalVersion: 1,
            calculatedAt: now,
            decision: .continueGoal,
            weightedPredicted: 136,
            weightedLowerBound: 130,
            weightedUpperBound: 142,
            successProbability: 0.72,
            predictions: [],
            risks: ["V1 risk"],
            evidence: ["V1 evidence"],
            dataFingerprint: "v1-fingerprint"
        )
        let coachProposal = CoachProposal(
            goalID: coachGoal.id,
            goalVersion: 1,
            analysisID: coachAnalysis.id,
            conclusion: "V1 proposal",
            rationale: "Preserve rationale",
            items: [],
            createdAt: now
        )
        let coachChat = CoachChat(
            goalID: coachGoal.id,
            title: "V1 chat",
            createdAt: now,
            updatedAt: now
        )
        context.insert(CoachGoalRecord(from: coachGoal))
        context.insert(CoachAnalysisRecord(from: coachAnalysis))
        context.insert(CoachProposalRecord(from: coachProposal))
        context.insert(CoachChatRecord(from: coachChat))
        context.insert(CoachConversationMessageRecord(from:
            CoachConversationMessage(
                goalID: coachGoal.id,
                chatID: coachChat.id,
                role: .assistant,
                content: "V1 message",
                createdAt: now
            )
        ))
        context.insert(StudySessionRecord(from:
            StudySession(
                id: UUID(),
                startDate: now,
                durationSeconds: 2_700,
                intensity: .deepFocus,
                completed: true
            )
        ))
        context.insert(ExamAutopsyRecord(from:
            ExamAutopsy(
                examId: UUID(),
                subject: "Mathematics",
                lastError: nil
            )
        ))
        context.insert(ExamSimulationRecord(from:
            ExamSimulation(
                subject: "Mathematics",
                createdAt: now,
                durationSeconds: 1_200,
                status: .completed,
                totalScore: 88
            )
        ))

        try context.save()
        return V1Fixture(
            counts: userEntityCounts(in: context),
            subjectID: subjectID,
            gradeID: gradeID
        )
    }

    private func userEntityCounts(in context: ModelContext) -> [String: Int] {
        [
            "SubjectRecord": (try? context.fetchCount(FetchDescriptor<SubjectRecord>())) ?? -1,
            "GradeRecord": (try? context.fetchCount(FetchDescriptor<GradeRecord>())) ?? -1,
            "MistakeNoteRecord": (try? context.fetchCount(FetchDescriptor<MistakeNoteRecord>())) ?? -1,
            "ExamRecord": (try? context.fetchCount(FetchDescriptor<ExamRecord>())) ?? -1,
            "ComprehensiveExamRecord": (try? context.fetchCount(FetchDescriptor<ComprehensiveExamRecord>())) ?? -1,
            "TaskItemRecord": (try? context.fetchCount(FetchDescriptor<TaskItemRecord>())) ?? -1,
            "UserProfileRecord": (try? context.fetchCount(FetchDescriptor<UserProfileRecord>())) ?? -1,
            "StudyPhaseRecord": (try? context.fetchCount(FetchDescriptor<StudyPhaseRecord>())) ?? -1,
            "PlantStateRecord": (try? context.fetchCount(FetchDescriptor<PlantStateRecord>())) ?? -1,
            "RoutineRecord": (try? context.fetchCount(FetchDescriptor<RoutineRecord>())) ?? -1,
            "RoutineInstanceRecord": (try? context.fetchCount(FetchDescriptor<RoutineInstanceRecord>())) ?? -1,
            "DiaryEntryRecord": (try? context.fetchCount(FetchDescriptor<DiaryEntryRecord>())) ?? -1,
            "CoachGoalRecord": (try? context.fetchCount(FetchDescriptor<CoachGoalRecord>())) ?? -1,
            "CoachAnalysisRecord": (try? context.fetchCount(FetchDescriptor<CoachAnalysisRecord>())) ?? -1,
            "CoachProposalRecord": (try? context.fetchCount(FetchDescriptor<CoachProposalRecord>())) ?? -1,
            "CoachConversationMessageRecord": (try? context.fetchCount(FetchDescriptor<CoachConversationMessageRecord>())) ?? -1,
            "CoachChatRecord": (try? context.fetchCount(FetchDescriptor<CoachChatRecord>())) ?? -1,
            "StudySessionRecord": (try? context.fetchCount(FetchDescriptor<StudySessionRecord>())) ?? -1,
            "ExamAutopsyRecord": (try? context.fetchCount(FetchDescriptor<ExamAutopsyRecord>())) ?? -1,
            "ExamSimulationRecord": (try? context.fetchCount(FetchDescriptor<ExamSimulationRecord>())) ?? -1,
        ]
    }
}
