//
//  DefaultMistakeRepository.swift
//  StudyPulse
//

import Foundation
import SwiftData
import SwiftUI
import os

@Observable @MainActor
final class DefaultMistakeRepository: MistakeRepository, PersistenceExecutorBacked {
    var mistakeSets: [MistakeNote] = []
    var filteredMistakeSets: [MistakeNote] = []
    @ObservationIgnored var lastPersistenceError: (any Error)?

    @ObservationIgnored private let envManager: AppEnvironmentManager
    @ObservationIgnored private var executor: PersistenceExecutor?
    @ObservationIgnored private let persistenceQueue = RepositoryPersistenceQueue(domain: "MistakeRepository")

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
        guard let executor else { return }
        await persistenceQueue.wait()
        do {
            let snapshots = try await executor.fetchMistakes()
            let filtered = try await executor.fetchMistakes(activePhaseID: envManager.activePhaseId)
            try Task.checkCancellation()
            publish(snapshots, filtered: filtered)
        } catch is CancellationError {
            Log.data.debug("MistakeRepository load cancelled")
        } catch {
            Log.data.error("MistakeRepository load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func publishStartupSnapshots(_ snapshots: [MistakeNote]) {
        publish(snapshots, filtered: snapshots)
    }

    func publishStartupSnapshots(_ snapshots: [MistakeNote], filtered: [MistakeNote]) {
        publish(snapshots, filtered: filtered)
    }

    func add(_ mistake: MistakeNote) {
        add([mistake])
    }

    func add(_ newMistakes: [MistakeNote]) {
        guard !newMistakes.isEmpty else { return }
        let activeID = envManager.activePhaseId
        let stored = newMistakes.map { note in
            var value = note
            if value.phaseId == nil { value.phaseId = activeID }
            return value
        }
        enqueue { executor in
            try await executor.insertMistakes(stored)
            await self.publishFromPersistence(
                (self.mistakeSets + stored).sorted { $0.date > $1.date },
                executor: executor
            )
            Log.data.info("MistakeRepository batch persisted: count=\(stored.count, privacy: .public)")
        }
    }

    func update(_ mistake: MistakeNote) {
        persistAndPublish(mistake)
    }

    func delete(_ mistake: MistakeNote) {
        delete(ids: [mistake.id], titles: [mistake.title])
    }

    func delete(at offsets: IndexSet, in set: inout [MistakeNote]) {
        let removed = offsets.compactMap { set.indices.contains($0) ? set[$0] : nil }
        set.remove(atOffsets: offsets)
        delete(ids: Set(removed.map(\.id)), titles: removed.map(\.title))
    }

    @discardableResult
    func clearAll() -> Int {
        let expectedCount = mistakeSets.count
        let ids = mistakeSets.map(\.id)
        enqueue { executor in
            _ = try await executor.deleteAllMistakes()
            for id in ids {
                SRSReviewNotifications.shared.cancel(for: id)
            }
            self.publish([], filtered: [])
        }
        return expectedCount
    }

    func allTags() -> [String] {
        MistakeFilter.allTags(mistakeSets)
    }

    func tagCounts() -> [(tag: String, count: Int)] {
        MistakeFilter.tagCounts(mistakeSets)
    }

    func updateReviewState(_ mistakeId: UUID, newState: ReviewState?) {
        guard var note = mistakeSets.first(where: { $0.id == mistakeId }) else { return }
        note.reviewState = newState
        persistAndPublish(note)
    }

    func recordExposure(_ mistakeId: UUID) {
        guard var note = mistakeSets.first(where: { $0.id == mistakeId }) else { return }
        note.exposureCount += 1
        persistAndPublish(note)
    }

    func recordReview(_ mistakeId: UUID, quality: ReviewQuality, now: Date) {
        guard var note = mistakeSets.first(where: { $0.id == mistakeId }) else { return }
        let result = MasteryAlgorithm.apply(
            oldScore: note.masteryScore,
            exposureCount: note.exposureCount,
            quality: quality,
            now: now
        )
        note.exposureCount += 1
        note.masteryScore = result.score
        note.masteryHistory.append(result.entry)
        if note.masteryHistory.count > 200 {
            note.masteryHistory.removeFirst(note.masteryHistory.count - 200)
        }
        persistAndPublish(note)
    }

    func recordHandwriting(
        _ mistakeId: UUID,
        pngData: Data,
        quality: ReviewQuality?,
        now: Date
    ) {
        guard var note = mistakeSets.first(where: { $0.id == mistakeId }) else { return }
        note.handwritingHistory.append(
            HandwritingAnswerEntry(
                timestamp: now,
                imageData: pngData,
                quality: quality?.rawValue ?? 0
            )
        )
        persistAndPublish(note)
    }

    func reloadFilteredFromSwiftData() async {
        guard let executor else { return }
        do {
            filteredMistakeSets = try await executor.fetchMistakes(activePhaseID: envManager.activePhaseId)
        } catch is CancellationError {
            Log.data.debug("MistakeRepository filtered load cancelled")
        } catch {
            Log.data.error("MistakeRepository filtered load failed: \(error.localizedDescription, privacy: .public)")
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

    private func persistAndPublish(_ note: MistakeNote) {
        enqueue { executor in
            try await executor.upsertMistake(note)
            var next = self.mistakeSets
            if let index = next.firstIndex(where: { $0.id == note.id }) {
                next[index] = note
            } else {
                next.append(note)
            }
            await self.publishFromPersistence(next.sorted { $0.date > $1.date }, executor: executor)
        }
    }

    private func delete(ids: Set<UUID>, titles: [String]) {
        guard !ids.isEmpty else { return }
        enqueue { executor in
            try await executor.deleteMistakes(ids: ids)
            for id in ids {
                SRSReviewNotifications.shared.cancel(for: id)
            }
            let next = self.mistakeSets.filter { !ids.contains($0.id) }
            await self.publishFromPersistence(next, executor: executor)
            Log.data.info("MistakeRepository deleted: \(titles.joined(separator: ", "), privacy: .public)")
        }
    }

    private func publish(_ snapshots: [MistakeNote], filtered: [MistakeNote]) {
        mistakeSets = snapshots
        filteredMistakeSets = filtered
    }

    private func publishFromPersistence(
        _ snapshots: [MistakeNote],
        executor: PersistenceExecutor
    ) async {
        do {
            let filtered = try await executor.fetchMistakes(activePhaseID: envManager.activePhaseId)
            publish(snapshots, filtered: filtered)
        } catch is CancellationError {
            Log.data.debug("MistakeRepository filtered refresh cancelled")
        } catch {
            Log.data.error("MistakeRepository filtered refresh failed: \(error.localizedDescription, privacy: .public)")
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
                let snapshots = self.mistakeSets
                let filtered = self.filteredMistakeSets
                return { self.publish(snapshots, filtered: filtered) }
            },
            onSettled: { [self] error in
                self.lastPersistenceError = error
            },
            operation: operation
        )
    }
}
