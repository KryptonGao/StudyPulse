//
//  DefaultRoutineInstanceRepository.swift
//  StudyPulse
//
//  例程实例 (RoutineInstance) Repository 默认实现。SwiftData 持久化。
//  Default RoutineInstanceRepository implementation backed by SwiftData.
//

import Foundation
import SwiftData
import os

/// 例程实例 (RoutineInstance) Repository 默认实现。SwiftData 持久化。
/// Default RoutineInstanceRepository implementation backed by SwiftData.
@Observable @MainActor
final class DefaultRoutineInstanceRepository: RoutineInstanceRepository {
    /// 全部实例（按 date desc）
    /// All instances, sorted by date desc.
    var allInstances: [RoutineInstance] = []
    /// 当日实例（dateKey == today）
    /// Today's instances (dateKey == today).
    var todayInstances: [RoutineInstance] = []
    /// 当前进行中的实例（startTime <= now < endTime）
    /// Currently active instances (startTime <= now < endTime).
    var activeInstances: [RoutineInstance] = []

    @ObservationIgnored
    private var modelContext: ModelContext?

    /// 用于 background fetch 的容器引用(Sendable)
    /// Container reference for background fetches (Sendable).
    @ObservationIgnored
    private var modelContainer: ModelContainer?

    init() {}

    // MARK: - Lifecycle
    // MARK: - 生命周期 / Lifecycle

    /// 加载全部实例
    /// Load all instances.
    func loadAll(context: ModelContext) async {
        self.modelContext = context
        self.modelContainer = context.container
        guard let container = modelContainer else { return }
        // detached Task 内创建独立 background ModelContext,fetch + toSnapshot
        // Use an independent background ModelContext inside a detached task.
        let snapshots: [RoutineInstance] = await Task.detached(priority: .utility) {
            let ctx = ModelContext(container)
            // fetchLimit=200:取最近 200 个 instance(覆盖近 2-3 个月)。
            // fetchLimit=200: take the 200 most recent instances (covers ~2-3 months).
            var descriptor = FetchDescriptor<RoutineInstanceRecord>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchLimit = 200
            let entities = (try? ctx.fetch(descriptor)) ?? []
            return entities.map { $0.toSnapshot() }
        }.value
        // 回到 MainActor 赋值
        self.allInstances = snapshots
        recomputeDerived()
    }

    // MARK: - CRUD
    // MARK: - 增删改查 / CRUD

    /// 幂等 spawn：业务层已查 in-memory，这里再保险一次 SwiftData 查重
    /// Idempotent spawn: business layer already checks in-memory, this re-checks SwiftData.
    @discardableResult
    func spawnIfMissing(_ instance: RoutineInstance) -> Bool {
        // 幂等检查:业务层先查 in-memory,这里再保险一次 SwiftData 查重
        // Idempotency check: business layer first, then SwiftData fallback.
        if allInstances.contains(where: { $0.idempotencyKey == instance.idempotencyKey }) {
            return false
        }
        if let context = modelContext {
            // 防御:即便 in-memory 没命中,持久层也查一遍
            let key = instance.idempotencyKey
            let existing = try? context.fetch(
                FetchDescriptor<RoutineInstanceRecord>(predicate: #Predicate { $0.idempotencyKey == key })
            )
            if let existing = existing, !existing.isEmpty {
                return false
            }
            context.insert(RoutineInstanceRecord(from: instance))
            guard context.saveOrRollback("RoutineInstanceRepository.spawnIfMissing") else { return false }
        }
        allInstances.append(instance)
        allInstances.sort { $0.date > $1.date }
        recomputeDerived()
        Log.data.info("RoutineInstanceRepository spawned: routineId=\(instance.routineId.uuidString, privacy: .public) dateKey=\(instance.dateKey, privacy: .public)")
        Log.record(.info, category: "Data", message: "RoutineInstanceRepository spawned: routineId=\(instance.routineId.uuidString) dateKey=\(instance.dateKey)")
        return true
    }

    func update(_ instance: RoutineInstance) {
        if let index = allInstances.firstIndex(where: { $0.id == instance.id }) {
            allInstances[index] = instance
        }
        updateRecord(instance)
        recomputeDerived()
    }

    func setCompletion(_ id: UUID, isCompleted: Bool) {
        guard let index = allInstances.firstIndex(where: { $0.id == id }) else { return }
        allInstances[index].isCompleted = isCompleted
        allInstances[index].completedAt = isCompleted ? Date() : nil
        updateRecord(allInstances[index])
        Log.data.info("RoutineInstanceRepository setCompletion: id=\(id.uuidString, privacy: .public) completed=\(isCompleted, privacy: .public)")
    }

    func delete(_ id: UUID) {
        removeRecord(id: id)
        allInstances.removeAll { $0.id == id }
        recomputeDerived()
    }

    @discardableResult
    func cleanupStale(olderThanDays days: Int) -> Int {
        guard let context = modelContext else { return 0 }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let cutoffKey = RoutineInstance.dateKeyString(for: cutoff)
        do {
            let entities = try context.fetch(
                FetchDescriptor<RoutineInstanceRecord>(predicate: #Predicate { $0.dateKey < cutoffKey })
            )
            for e in entities { context.delete(e) }
            try context.save()
            allInstances.removeAll { $0.dateKey < cutoffKey }
            recomputeDerived()
            return entities.count
        } catch {
            Log.data.error("RoutineInstanceRepository cleanupStale failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    // MARK: - Internals
    // MARK: - 内部工具 / Internals

    /// 重新计算 todayInstances / activeInstances
    /// Recompute todayInstances / activeInstances.
    func recomputeDerived() {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let todayKey = RoutineInstance.dateKeyString(for: now)
        todayInstances = allInstances.filter { $0.dateKey == todayKey }
        activeInstances = allInstances.filter { inst in
            inst.startTime <= now && inst.endTime > now
        }
        _ = todayStart  // reserved for future date-bucket queries
    }

    private func removeRecord(id: UUID) {
        guard let context = modelContext else { return }
        do {
            if let entity = try context.fetch(
                FetchDescriptor<RoutineInstanceRecord>(predicate: #Predicate { $0.id == id })
            ).first {
                context.delete(entity)
                try context.save()
            }
        } catch {
            Log.data.error("RoutineInstanceRepository removeRecord failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateRecord(_ instance: RoutineInstance) {
        guard let context = modelContext else { return }
        do {
            if let entity = try context.fetch(
                FetchDescriptor<RoutineInstanceRecord>(predicate: #Predicate { $0.id == instance.id })
            ).first {
                entity.title = instance.title
                entity.typeRaw = instance.type.rawValue
                entity.subject = instance.subject
                entity.startTime = instance.startTime
                entity.endTime = instance.endTime
                entity.isCompleted = instance.isCompleted
                entity.completedAt = instance.completedAt
                entity.spawnedMistakeCount = instance.spawnedMistakeCount
                try context.save()
            }
        } catch {
            Log.data.error("RoutineInstanceRepository updateRecord failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
