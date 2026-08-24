//
//  RepositoryContainerTests.swift
//  StudyPulseTests
//
//  验证测试基础设施（TestFixtures, MockRepositoryHub, TestModelContainerFactory, RepositoryContainer 编排）
//  Verifies the testing infrastructure works properly across Mock and In-Memory modes.
//

import XCTest
import SwiftData
@testable import StudyPulse

@MainActor
final class RepositoryContainerTests: XCTestCase {

    func test_cancelledProductionInitializationNeverMarksContainerReady() async throws {
        let modelContainer = try TestModelContainerFactory.makeInMemoryContainer()
        let container = RepositoryContainer()
        let initialization = Task { @MainActor in
            await Task.yield()
            try await container.asyncInit(using: modelContainer)
        }

        initialization.cancel()
        do {
            try await initialization.value
            XCTFail("Expected RepositoryContainer initialization cancellation")
        } catch is CancellationError {
            // Expected: cancellation propagates to the SwiftUI .task owner.
        }

        XCTAssertFalse(container.isReady)
    }

    // MARK: - TestDataFixtures 验证

    func test_testDataFixtures_createsValidEntitiesWithDefaults() {
        let grade = TestDataFixtures.makeGrade(subject: "Physics", score: 95.0)
        XCTAssertEqual(grade.subject, "Physics")
        XCTAssertEqual(grade.score, 95.0)
        XCTAssertEqual(grade.importance, 3)

        let exam = TestDataFixtures.makeExam(name: "Midterm Physics", subject: "Physics")
        XCTAssertEqual(exam.name, "Midterm Physics")
        XCTAssertEqual(exam.subject, "Physics")

        let mistake = TestDataFixtures.makeMistakeNote(title: "Force Vector Error", subject: "Physics")
        XCTAssertEqual(mistake.title, "Force Vector Error")
        XCTAssertEqual(mistake.subject, "Physics")
        XCTAssertEqual(mistake.tags, ["Calculus", "Integral"])

        let task = TestDataFixtures.makeTaskItem(title: "Read Chapter 3", type: .reading)
        XCTAssertEqual(task.title, "Read Chapter 3")
        XCTAssertEqual(task.type, .reading)
        XCTAssertFalse(task.isCompleted)

        let phase = TestDataFixtures.makeStudyPhase(name: "2026 Spring")
        XCTAssertEqual(phase.name, "2026 Spring")
        XCTAssertFalse(phase.isArchived)

        let subject = TestDataFixtures.makeSubject(name: "Math", displayName: "数学")
        XCTAssertEqual(subject.name, "Math")
        XCTAssertEqual(subject.displayName, "数学")
        XCTAssertEqual(subject.fullScore, 150.0)

        let routine = TestDataFixtures.makeRoutine(title: "Daily Review", type: .mistakeReview)
        XCTAssertEqual(routine.title, "Daily Review")
        XCTAssertTrue(routine.enabled)

        let instance = TestDataFixtures.makeRoutineInstance(title: "Daily Review Instance", spawnedMistakeCount: 3)
        XCTAssertEqual(instance.title, "Daily Review Instance")
        XCTAssertEqual(instance.spawnedMistakeCount, 3)
    }

    // MARK: - Mock 模式容器与 MockHub 验证

    func test_mockContainer_tracksCRUDAndDelegatesProperly() {
        let (container, mocks) = TestRepositoryContainerFactory.makeMockContainer()

        // 初始状态
        XCTAssertEqual(container.gradeRepo.grades.count, 0)
        XCTAssertEqual(mocks.grade.addCalledCount, 0)

        // 添加成绩
        let grade = TestDataFixtures.makeGrade(subject: "Math", score: 88.0)
        container.addGrade(grade)

        XCTAssertEqual(mocks.grade.addCalledCount, 1)
        XCTAssertEqual(container.gradeRepo.grades.count, 1)
        XCTAssertEqual(mocks.grade.lastAddedGrade?.subject, "Math")

        // 添加错题
        let mistake = TestDataFixtures.makeMistakeNote(title: "Derivatives Mistake")
        container.addMistake(mistake)
        XCTAssertEqual(mocks.mistake.addCalledCount, 1)
        XCTAssertEqual(container.mistakeRepo.mistakeSets.count, 1)
    }

    func test_mockContainer_bulkClearData_clearsSpecifiedCategories() {
        let (container, mocks) = TestRepositoryContainerFactory.makeMockContainer()

        container.addGrade(TestDataFixtures.makeGrade())
        container.addGrade(TestDataFixtures.makeGrade())
        container.addMistake(TestDataFixtures.makeMistakeNote())
        container.addTask(TestDataFixtures.makeTaskItem())

        XCTAssertEqual(container.gradeRepo.grades.count, 2)
        XCTAssertEqual(container.mistakeRepo.mistakeSets.count, 1)
        XCTAssertEqual(container.taskRepo.taskItems.count, 1)

        // 执行批量清空（清除 grades 和 tasks）
        let results = container.bulkClearData(categories: [.grades, .tasks])

        XCTAssertEqual(mocks.grade.clearAllCalledCount, 1)
        XCTAssertEqual(mocks.task.clearAllCalledCount, 1)
        XCTAssertEqual(mocks.mistake.clearAllCalledCount, 0) // 错题不应该被清空

        XCTAssertEqual(container.gradeRepo.grades.count, 0)
        XCTAssertEqual(container.taskRepo.taskItems.count, 0)
        XCTAssertEqual(container.mistakeRepo.mistakeSets.count, 1) // 保留
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - In-Memory Real 容器集成验证

    func test_inMemoryRealContainer_initializesAndPerformsCRUD() async throws {
        let container = try await TestRepositoryContainerFactory.makeInMemoryRealContainer()
        XCTAssertTrue(container.isReady)

        // 添加成绩和待办，验证真实 Repository 与 In-Memory ModelContainer 交互
        let grade = TestDataFixtures.makeGrade(subject: "English", score: 92.0)
        container.addGrade(grade)
        await container.flushPendingPersistence()
        XCTAssertEqual(container.gradeRepo.grades.count, 1)
        XCTAssertEqual(container.gradeRepo.grades.first?.subject, "English")

        // 验证 TodoEntries 跨域聚合
        let task = TestDataFixtures.makeTaskItem(title: "English Essay", type: .homework, dueDate: Date().addingTimeInterval(3600))
        container.addTask(task)

        let exam = TestDataFixtures.makeExam(name: "Midterm English", subject: "English")
        container.addExams(single: [exam], comprehensive: [])
        await container.flushPendingPersistence()

        let entries = container.todoEntries(includeCompleted: false)
        // 应该聚合了 1 个 Task + 1 个 Exam
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains(where: { $0.title == "English Essay" }))
        XCTAssertTrue(entries.contains(where: { $0.title == "Midterm English" }))
    }

    func test_inMemoryRealContainer_updatesReloadsAndDeletesPersistedGrade() async throws {
        let container = try await TestRepositoryContainerFactory.makeInMemoryRealContainer()
        let original = TestDataFixtures.makeGrade(subject: "Physics", score: 72)

        container.addGrade(original)
        var updated = original
        updated.score = 91
        container.gradeRepo.update(updated)

        await container.gradeRepo.reloadFromSwiftData()
        XCTAssertEqual(container.gradeRepo.grades.first(where: { $0.id == original.id })?.score, 91)

        container.deleteGrade(updated)
        await container.gradeRepo.reloadFromSwiftData()
        XCTAssertNil(container.gradeRepo.grades.first(where: { $0.id == original.id }))
    }
}
