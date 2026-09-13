//
//  DefaultRoutineRepository.swift
//  StudyPulse
//
//  例程 (Routine) Repository 默认实现。SwiftData 持久化。
//  Default RoutineRepository implementation backed by SwiftData.
//

import Foundation
import SwiftData
import os

/// 例程 (Routine) Repository 默认实现。SwiftData 持久化。
/// Default RoutineRepository implementation backed by SwiftData.
@Observable @MainActor
final class DefaultRoutineRepository: RoutineRepository, PersistenceExecutorBacked {
    /// 全部例程模板
    /// All routine templates.
    var routines: [Routine] = []
    /// 仅 enabled 例程
    /// Enabled-only routines.
    var enabledRoutines: [Routine] {
        routines.filter { $0.enabled }
    }
    /// 按 active phase 过滤后的例程
    /// Routines filtered by the active phase.
    var filteredRoutines: [Routine] = []

    @ObservationIgnored
    private var modelContext: ModelContext?

    /// 用于 background fetch 的容器引用(Sendable)
    /// Container reference for background fetches (Sendable).
    @ObservationIgnored
    private var modelContainer: ModelContainer?

    @ObservationIgnored
    private var executor: PersistenceExecutor?

    /// AppEnvironmentManager(由容器注入,用于读 activePhaseId)
    /// AppEnvironmentManager (injected by the container; used to read `activePhaseId`).
    @ObservationIgnored
    private let envManager: AppEnvironmentManager

    init(envManager: AppEnvironmentManager) {
        self.envManager = envManager
    }

    func attachPersistenceExecutor(_ executor: PersistenceExecutor) {
        self.executor = executor
    }

    // MARK: - Lifecycle
    // MARK: - 生命周期 / Lifecycle

    /// 加载全部例程
    /// Load all routines.
    func loadAll(context: ModelContext) async {
        self.modelContext = context
        self.modelContainer = context.container
        guard let container = modelContainer else { return }
        if executor == nil {
            executor = PersistenceExecutor(modelContainer: container)
        }
        guard let executor else { return }
        do {
            routines = try await executor.fetchRoutines(activePhaseID: nil)
            filteredRoutines = try await executor.fetchRoutines(activePhaseID: envManager.activePhaseId)
        } catch {
            Log.data.error("RoutineRepository load failed: \(error.localizedDescription, privacy: .public)")
        }
        return
        /*
        // detached Task 内创建独立 background ModelContext,fetch + toSnapshot
        // Use an independent background ModelContext inside a detached task.
        let snapshots: [Routine] = await Task.detached(priority: .utility) {
            let ctx = ModelContext(container)
            let entities = (try? ctx.fetch(
                FetchDescriptor<RoutineRecord>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
            )) ?? []
            return entities.map { $0.toSnapshot() }
        }.value
        // 回到 MainActor 赋值
        self.routines = snapshots
        refreshFilteredFromPersistence()
        */
    }

    // MARK: - CRUD
    // MARK: - 增删改查 / CRUD

    /// 新增例程
    /// Add a routine.
    func add(_ routine: Routine) {
        var stored = routine
        if stored.phaseId == nil {
            stored.phaseId = envManager.activePhaseId
        }
        if let context = modelContext {
            context.insert(RoutineRecord(from: stored))
            guard context.saveOrRollback("RoutineRepository.add") else { return }
        }
        routines.append(stored)
        routines.sort { $0.createdAt < $1.createdAt }
        Log.data.info("RoutineRepository added: title=\(stored.title, privacy: .public) type=\(stored.type.rawValue, privacy: .public)")
        Log.record(.info, category: "Data", message: "RoutineRepository added: title=\(stored.title) type=\(stored.type.rawValue)")
        refreshFilteredFromPersistence()
    }

    func add(_ newRoutines: [Routine]) {
        guard !newRoutines.isEmpty else { return }
        let activeId = envManager.activePhaseId
        let stored: [Routine] = newRoutines.map { r in
            var s = r
            if s.phaseId == nil { s.phaseId = activeId }
            return s
        }
        if let context = modelContext {
            for r in stored {
                context.insert(RoutineRecord(from: r))
            }
            guard context.saveOrRollback("RoutineRepository.add(batch)") else { return }
        }
        routines.append(contentsOf: stored)
        routines.sort { $0.createdAt < $1.createdAt }
        Log.data.info("RoutineRepository batch added: count=\(stored.count, privacy: .public)")
        Log.record(.info, category: "Data", message: "RoutineRepository batch added: count=\(stored.count)")
        refreshFilteredFromPersistence()
    }

    func update(_ routine: Routine) {
        if let index = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[index] = routine
            routines.sort { $0.createdAt < $1.createdAt }
        }
        updateRecord(routine)
        refreshFilteredFromPersistence()
        Log.data.info("RoutineRepository updated: title=\(routine.title, privacy: .public) id=\(routine.id.uuidString, privacy: .public)")
        Log.record(.info, category: "Data", message: "RoutineRepository updated: title=\(routine.title) id=\(routine.id.uuidString)")
    }

    func delete(_ id: UUID) {
        removeRecord(id: id)
        routines.removeAll { $0.id == id }
        Log.data.info("RoutineRepository deleted: id=\(id.uuidString, privacy: .public)")
        Log.record(.info, category: "Data", message: "RoutineRepository deleted: id=\(id.uuidString)")
        refreshFilteredFromPersistence()
    }

    func setEnabled(_ id: UUID, enabled: Bool) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index].enabled = enabled
        updateRecord(routines[index])
        Log.data.info("RoutineRepository setEnabled: id=\(id.uuidString, privacy: .public) enabled=\(enabled, privacy: .public)")
    }

    @discardableResult
    func clearAll() -> Int {
        guard let context = modelContext else { return 0 }
        let count = routines.count
        do {
            let entities = try context.fetch(FetchDescriptor<RoutineRecord>())
            for entity in entities { context.delete(entity) }
            try context.save()
        } catch {
            Log.data.error("RoutineRepository clearAll failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
        routines.removeAll()
        Log.data.warning("RoutineRepository clearAll: count=\(count, privacy: .public)")
        Log.record(.warning, category: "Data", message: "RoutineRepository clearAll: count=\(count)")
        refreshFilteredFromPersistence()
        return count
    }

    // MARK: - Internals
    // MARK: - 内部工具 / Internals

    func reloadFilteredFromSwiftData() async {
        guard let executor else { return }
        do {
            filteredRoutines = try await executor.fetchRoutines(
                activePhaseID: envManager.activePhaseId
            )
        } catch is CancellationError {
            Log.data.debug("RoutineRepository filtered load cancelled")
        } catch {
            Log.data.error("RoutineRepository filtered load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var lastPersistenceError: (any Error)? { nil }

    func waitForPendingPersistence() async {}

    func flushPendingPersistence() async {}

    func cancelPendingPersistence() {}

    private func refreshFilteredFromPersistence() {
        guard executor != nil else {
            filteredRoutines = routines
            return
        }
        Task { [weak self] in
            await self?.reloadFilteredFromSwiftData()
        }
    }

    private func removeRecord(id: UUID) {
        guard let context = modelContext else { return }
        do {
            if let entity = try context.fetch(
                FetchDescriptor<RoutineRecord>(predicate: #Predicate { $0.id == id })
            ).first {
                context.delete(entity)
                try context.save()
            }
        } catch {
            context.rollback()
            Log.data.error("RoutineRepository removeRecord failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateRecord(_ routine: Routine) {
        guard let context = modelContext else { return }
        do {
            if let entity = try context.fetch(
                FetchDescriptor<RoutineRecord>(predicate: #Predicate { $0.id == routine.id })
            ).first {
                entity.title = routine.title
                entity.typeRaw = routine.type.rawValue
                entity.subject = routine.subject
                entity.weekdays = routine.weekdays
                entity.startTime = routine.startTime
                entity.endTime = routine.endTime
                entity.enabled = routine.enabled
                entity.createdAt = routine.createdAt
                entity.phaseId = routine.phaseId
                try context.save()
            } else {
                context.insert(RoutineRecord(from: routine))
                try context.save()
            }
        } catch {
            context.rollback()
            Log.data.error("RoutineRepository updateRecord failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
