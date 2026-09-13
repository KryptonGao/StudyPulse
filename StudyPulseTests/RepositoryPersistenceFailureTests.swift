//
//  RepositoryPersistenceFailureTests.swift
//  StudyPulseTests
//
//  CQ-01: a failed durable write must not look like success, and must leave
//  in-memory snapshots consistent with disk.
//

import XCTest
import SwiftData
@testable import StudyPulse

@MainActor
final class RepositoryPersistenceFailureTests: XCTestCase {
    func testUnattachedExecutorRecordsFailureAndDoesNotPublish() async throws {
        let repository = DefaultTaskRepository(envManager: .shared)
        repository.add([TestDataFixtures.makeTaskItem(title: "No executor")])

        do {
            try await repository.flushPendingPersistence()
            XCTFail("flush must throw when the executor is missing")
        } catch let error as RepositoryPersistenceError {
            XCTAssertEqual(error, .executorNotAttached)
        }
        XCTAssertEqual(repository.lastPersistenceError as? RepositoryPersistenceError, .executorNotAttached)
        XCTAssertTrue(repository.taskItems.isEmpty)
    }

    func testGradeAddFailureDoesNotPublishOrPersist() async throws {
        let (repository, executor, context) = try makeGradeRepository()
        await repository.loadAll(context: context)

        repository.debugFailNextPersistence(RepositoryPersistenceError.mutationFailed("grade save failed"))
        repository.add(TestDataFixtures.makeGrade(score: 88, examName: "Ghost"))
        await repository.waitForPendingPersistence()

        XCTAssertEqual(
            repository.lastPersistenceError as? RepositoryPersistenceError,
            .mutationFailed("grade save failed")
        )
        XCTAssertTrue(repository.grades.isEmpty)
        let persisted = try await executor.fetchGrades()
        XCTAssertTrue(persisted.isEmpty)

        do {
            try await repository.flushPendingPersistence()
            XCTFail("flush must rethrow the recorded failure")
        } catch let error as RepositoryPersistenceError {
            XCTAssertEqual(error, .mutationFailed("grade save failed"))
        }
    }

    func testGradeUpdateFailureRollsMemoryBack() async throws {
        let (repository, executor, context) = try makeGradeRepository()
        await repository.loadAll(context: context)
        let original = TestDataFixtures.makeGrade(score: 70, examName: "Keep")
        repository.add(original)
        try await repository.flushPendingPersistence()

        repository.debugFailNextPersistence(RepositoryPersistenceError.mutationFailed("grade update failed"))
        var updated = original
        updated.score = 99
        repository.update(updated)
        await repository.waitForPendingPersistence()

        XCTAssertEqual(repository.grades.first?.score, 70)
        let persisted = try await executor.fetchGrades()
        XCTAssertEqual(persisted.first?.score, 70)
    }

    func testTaskAddFailureLeavesExistingRowIntact() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let executor = PersistenceExecutor(modelContainer: container)
        let repository = DefaultTaskRepository(envManager: .shared)
        repository.attachPersistenceExecutor(executor)
        await repository.loadAll(context: container.mainContext)

        let existing = TestDataFixtures.makeTaskItem(title: "Keep me")
        repository.add([existing])
        try await repository.flushPendingPersistence()

        repository.debugFailNextPersistence(RepositoryPersistenceError.mutationFailed("task disk full"))
        repository.add([TestDataFixtures.makeTaskItem(title: "Must not stick")])
        await repository.waitForPendingPersistence()

        XCTAssertEqual(repository.taskItems.map(\.id), [existing.id])
        let persisted = try await executor.fetchTasks()
        XCTAssertEqual(persisted.map(\.id), [existing.id])
    }

    func testMistakeDeleteFailureKeepsMemoryAndDisk() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let executor = PersistenceExecutor(modelContainer: container)
        let repository = DefaultMistakeRepository(envManager: .shared)
        repository.attachPersistenceExecutor(executor)
        await repository.loadAll(context: container.mainContext)

        let note = TestDataFixtures.makeMistakeNote(title: "Keep")
        repository.add(note)
        try await repository.flushPendingPersistence()

        repository.debugFailNextPersistence(RepositoryPersistenceError.mutationFailed("mistake delete failed"))
        repository.delete(note)
        await repository.waitForPendingPersistence()

        XCTAssertEqual(repository.mistakeSets.map(\.id), [note.id])
        let persisted = try await executor.fetchMistakes()
        XCTAssertEqual(persisted.map(\.id), [note.id])
    }

    func testExamAddFailureDoesNotPublishNewExam() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let executor = PersistenceExecutor(modelContainer: container)
        let repository = DefaultExamRepository(envManager: .shared)
        repository.attachPersistenceExecutor(executor)
        await repository.loadAll(context: container.mainContext)

        let existing = TestDataFixtures.makeExam(name: "Keep")
        repository.add(single: [existing], comprehensive: [])
        try await repository.flushPendingPersistence()

        repository.debugFailNextPersistence(RepositoryPersistenceError.mutationFailed("exam save failed"))
        repository.add(single: [TestDataFixtures.makeExam(name: "Ghost")], comprehensive: [])
        await repository.waitForPendingPersistence()

        XCTAssertEqual(repository.examSets.map(\.id), [existing.id])
        let persisted = try await executor.fetchExams()
        XCTAssertEqual(persisted.map(\.id), [existing.id])
    }

    func testSuccessfulWriteAfterFailureClearsErrorState() async throws {
        let (repository, executor, context) = try makeGradeRepository()
        await repository.loadAll(context: context)

        repository.debugFailNextPersistence(RepositoryPersistenceError.mutationFailed("first write fails"))
        repository.add(TestDataFixtures.makeGrade(examName: "Fail"))
        await repository.waitForPendingPersistence()
        XCTAssertTrue(repository.grades.isEmpty)

        let kept = TestDataFixtures.makeGrade(examName: "Recovered")
        repository.add(kept)
        try await repository.flushPendingPersistence()
        XCTAssertNil(repository.lastPersistenceError)
        XCTAssertEqual(repository.grades.map(\.id), [kept.id])
        let persisted = try await executor.fetchGrades()
        XCTAssertEqual(persisted.map(\.id), [kept.id])
    }

    private func makeGradeRepository() throws -> (
        DefaultGradeRepository,
        PersistenceExecutor,
        ModelContext
    ) {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let executor = PersistenceExecutor(modelContainer: container)
        let repository = DefaultGradeRepository(envManager: .shared)
        repository.attachPersistenceExecutor(executor)
        return (repository, executor, container.mainContext)
    }
}
