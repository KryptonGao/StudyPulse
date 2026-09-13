//
//  DefaultGradeRepository.swift
//  StudyPulse
//

import Foundation
import SwiftData
import os

@Observable @MainActor
final class DefaultGradeRepository: GradeRepository, PersistenceExecutorBacked {
    var grades: [Grade] = []
    var filteredGrades: [Grade] = []
    @ObservationIgnored var lastPersistenceError: (any Error)?

    @ObservationIgnored private let envManager: AppEnvironmentManager
    @ObservationIgnored private var executor: PersistenceExecutor?
    @ObservationIgnored private let persistenceQueue = RepositoryPersistenceQueue(domain: "GradeRepository")

    init(envManager: AppEnvironmentManager) {
        self.envManager = envManager
    }

    func attachPersistenceExecutor(_ executor: PersistenceExecutor) {
        self.executor = executor
    }

    func loadAll(context: ModelContext) async {
        if executor == nil {
            executor = PersistenceExecutor(modelContainer: context.container)
        }
        await reloadFromSwiftData()
    }

    func reloadFromSwiftData() async {
        guard let executor else { return }
        await persistenceQueue.wait()
        do {
            let snapshots = try await executor.fetchGrades()
            let filtered = try await executor.fetchGrades(activePhaseID: envManager.activePhaseId)
            try Task.checkCancellation()
            publish(snapshots, filtered: filtered)
        } catch is CancellationError {
            Log.data.debug("GradeRepository load cancelled")
        } catch {
            Log.data.error("GradeRepository load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func publishStartupSnapshots(_ snapshots: [Grade]) {
        publish(snapshots, filtered: snapshots)
    }

    func publishStartupSnapshots(_ snapshots: [Grade], filtered: [Grade]) {
        publish(snapshots, filtered: filtered)
    }

    /// Inline-image migration is now folded into normal updates instead of
    /// accessing a ModelContext on MainActor. Kept for protocol compatibility.
    @discardableResult
    func migrateInlineImagesIfNeeded() -> Int {
        let migrated = grades.reduce(into: [Grade]()) { result, grade in
            guard let data = grade.image, grade.imageFileName == nil else { return }
            let filename = "grade_\(grade.id.uuidString).jpg"
            guard ImageStorage.save(data, filename: filename) else { return }
            var updated = grade
            updated.image = nil
            updated.imageFileName = filename
            result.append(updated)
        }
        guard !migrated.isEmpty else { return 0 }
        enqueue { executor in
            for grade in migrated {
                try Task.checkCancellation()
                try await executor.upsertGrade(grade)
            }
            var next = self.grades
            // 同 id 重复(损坏数据/竞态)时保留首条,避免 trap / Keep first on duplicate ids.
            let updates = Dictionary(migrated.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for index in next.indices {
                if let value = updates[next[index].id] { next[index] = value }
            }
            await self.publishFromPersistence(next, executor: executor)
        }
        return migrated.count
    }

    func add(_ grade: Grade) {
        add([grade])
    }

    func add(_ newGrades: [Grade]) {
        guard !newGrades.isEmpty else { return }
        let activeID = envManager.activePhaseId
        let stored = newGrades.map { grade in
            var value = grade
            if value.phaseId == nil { value.phaseId = activeID }
            return value
        }
        enqueue { executor in
            try await executor.insertGrades(stored)
            await self.publishFromPersistence(
                (self.grades + stored).sorted { $0.date > $1.date },
                executor: executor
            )
            Log.data.info("GradeRepository batch persisted: count=\(stored.count, privacy: .public)")
        }
    }

    func update(_ grade: Grade) {
        enqueue { executor in
            try await executor.upsertGrade(grade)
            var next = self.grades
            if let index = next.firstIndex(where: { $0.id == grade.id }) {
                next[index] = grade
            } else {
                next.append(grade)
            }
            await self.publishFromPersistence(next.sorted { $0.date > $1.date }, executor: executor)
        }
    }

    func delete(_ grade: Grade) {
        enqueue { executor in
            try await executor.deleteGrade(id: grade.id)
            if let filename = grade.imageFileName {
                ImageStorage.delete(filename: filename)
            }
            let next = self.grades.filter { $0.id != grade.id }
            await self.publishFromPersistence(next, executor: executor)
        }
    }

    @discardableResult
    func clearAll() -> Int {
        let expectedCount = grades.count
        let imageNames = grades.compactMap(\.imageFileName)
        enqueue { executor in
            _ = try await executor.deleteAllGrades()
            for filename in imageNames {
                ImageStorage.delete(filename: filename)
            }
            self.publish([], filtered: [])
        }
        return expectedCount
    }

    func reloadFilteredFromSwiftData() async {
        guard let executor else { return }
        do {
            filteredGrades = try await executor.fetchGrades(activePhaseID: envManager.activePhaseId)
        } catch is CancellationError {
            Log.data.debug("GradeRepository filtered load cancelled")
        } catch {
            Log.data.error("GradeRepository filtered load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func waitForPendingPersistence() async {
        await persistenceQueue.wait()
    }

    func flushPendingPersistence() async throws {
        try await persistenceQueue.flush()
    }

    func cancelPendingPersistence() {
        persistenceQueue.cancel()
    }

    func debugFailNextPersistence(_ error: any Error) {
        persistenceQueue.debugNextOperationError = error
    }

    private func publish(_ snapshots: [Grade], filtered: [Grade]) {
        grades = snapshots
        filteredGrades = filtered
    }

    private func publishFromPersistence(
        _ snapshots: [Grade],
        executor: PersistenceExecutor
    ) async {
        do {
            let filtered = try await executor.fetchGrades(activePhaseID: envManager.activePhaseId)
            publish(snapshots, filtered: filtered)
        } catch is CancellationError {
            Log.data.debug("GradeRepository filtered refresh cancelled")
        } catch {
            Log.data.error("GradeRepository filtered refresh failed: \(error.localizedDescription, privacy: .public)")
            let activeID = envManager.activePhaseId
            publish(snapshots, filtered: snapshots.filter { $0.phaseId == nil || $0.phaseId == activeID })
        }
    }

    private func enqueue(
        _ operation: @escaping @MainActor @Sendable (PersistenceExecutor) async throws -> Void
    ) {
        persistenceQueue.enqueue(
            executor: executor,
            captureRestore: { [self] in
                let snapshots = self.grades
                let filtered = self.filteredGrades
                return { self.publish(snapshots, filtered: filtered) }
            },
            onSettled: { [self] error in
                self.lastPersistenceError = error
            },
            operation: operation
        )
    }
}
