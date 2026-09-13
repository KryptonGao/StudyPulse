//
//  DefaultDiaryRepository.swift
//  StudyPulse
//
//  学习日记 (DiaryEntry) Repository 默认实现。
//  Default DiaryRepository implementation backed by SwiftData.
//

import Foundation
import SwiftData
import SwiftUI
import os

/// 学习日记 Repository 默认实现。
/// Default DiaryRepository implementation backed by SwiftData.
@Observable @MainActor
final class DefaultDiaryRepository: DiaryRepository, PersistenceExecutorBacked {
    /// 全部日记(按 date desc 排序)
    /// All diary entries, sorted by date desc.
    var diaryEntries: [DiaryEntry] = []
    /// 按 active phase 过滤后的日记缓存
    /// Cached diary entries filtered by the active phase.
    var filteredDiaryEntries: [DiaryEntry] = []

    @ObservationIgnored
    private var modelContext: ModelContext?

    /// 用于 background fetch 的容器引用(Sendable)
    /// Container reference for background fetches (Sendable).
    @ObservationIgnored
    private var modelContainer: ModelContainer?

    @ObservationIgnored
    private var executor: PersistenceExecutor?

    /// AppEnvironmentManager(由容器注入,用于读 activePhaseId + diarySyncToHealthEnabled)
    /// AppEnvironmentManager (injected by the container; used to read
    /// `activePhaseId` + `diarySyncToHealthEnabled`).
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

    /// 加载所有日记
    /// Load all diary entries.
    func loadAll(context: ModelContext) async {
        self.modelContext = context
        self.modelContainer = context.container
        guard let container = modelContainer else { return }
        if executor == nil {
            executor = PersistenceExecutor(modelContainer: container)
        }
        guard let executor else { return }
        do {
            diaryEntries = try await executor.fetchDiaryEntries(activePhaseID: nil)
            filteredDiaryEntries = try await executor.fetchDiaryEntries(
                activePhaseID: envManager.activePhaseId
            )
        } catch {
            Log.data.error("DiaryRepository load failed: \(error.localizedDescription, privacy: .public)")
        }
        return
        /*
        // detached Task 内创建独立 background ModelContext,fetch + toSnapshot
        // Use an independent background ModelContext inside a detached task.
        let snapshots: [DiaryEntry] = await Task.detached(priority: .utility) {
            let ctx = ModelContext(container)
            // fetchLimit=365:一年日记足够;按 date desc 保证拿到最新数据。
            // fetchLimit=365: a year of diary entries is enough; sort date desc to keep the newest.
            var descriptor = FetchDescriptor<DiaryEntryRecord>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchLimit = 365
            let entities = (try? ctx.fetch(descriptor)) ?? []
            return entities.map { $0.toSnapshot() }
        }.value
        // 回到 MainActor 赋值
        self.diaryEntries = snapshots
        refreshFilteredFromPersistence()
        */
    }

    // MARK: - CRUD
    // MARK: - 增删改查 / CRUD

    /// 新增一条日记(若开启同步,触发 Apple Health Mindful Session 写入)
    /// Add one diary entry (triggers Apple Health Mindful Session write if sync is enabled).
    func add(_ entry: DiaryEntry) {
        var stored = entry
        if stored.phaseId == nil {
            stored.phaseId = envManager.activePhaseId
        }
        stored.updatedAt = .now
        if let context = modelContext {
            context.insert(DiaryEntryRecord(from: stored))
            guard context.saveOrRollback("DiaryRepository.add") else { return }
        }
        diaryEntries.append(stored)
        // 保持 date desc 顺序
        diaryEntries.sort { $0.date > $1.date }
        Log.data.info("DiaryRepository added: date=\(stored.date, privacy: .public) mood=\(stored.moodScore, privacy: .public) energy=\(stored.energyScore, privacy: .public)")
        Log.record(.info, category: "Data", message: "DiaryRepository added: mood=\(stored.moodScore) energy=\(stored.energyScore)")
        refreshFilteredFromPersistence()

        // Apple Health Mindful Session 同步(失败仅记日志,不弹窗 — 项目硬约束)
        // Apple Health Mindful Session sync (errors are logged only, never alerted).
        if envManager.preferences.diarySyncToHealthEnabled {
            let start = stored.date
            let end = stored.date.addingTimeInterval(60)
            Task { await HealthKitManager.shared.saveMindfulSession(start: start, end: end) }
        }
    }

    func update(_ entry: DiaryEntry) {
        var stored = entry
        stored.updatedAt = .now
        if let index = diaryEntries.firstIndex(where: { $0.id == stored.id }) {
            diaryEntries[index] = stored
        }
        updateRecord(stored)
        diaryEntries.sort { $0.date > $1.date }
        refreshFilteredFromPersistence()
    }

    func delete(_ entry: DiaryEntry) {
        removeRecord(id: entry.id)
        if let index = diaryEntries.firstIndex(where: { $0.id == entry.id }) {
            diaryEntries.remove(at: index)
        }
        Log.data.info("DiaryRepository deleted: id=\(entry.id.uuidString, privacy: .public)")
        refreshFilteredFromPersistence()
    }

    @discardableResult
    func clearAll() -> Int {
        guard let context = modelContext else { return 0 }
        let count = diaryEntries.count
        do {
            let entities = try context.fetch(FetchDescriptor<DiaryEntryRecord>())
            for entity in entities { context.delete(entity) }
            try context.save()
        } catch {
            Log.data.error("DiaryRepository clearAll failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
        diaryEntries.removeAll()
        Log.data.warning("DiaryRepository clearAll: count=\(count, privacy: .public)")
        Log.record(.warning, category: "Data", message: "DiaryRepository clearAll: count=\(count)")
        refreshFilteredFromPersistence()
        return count
    }

    // MARK: - Query
    // MARK: - 查询 / Query

    /// 取指定时间范围内的日记(按日期升序)
    /// Entries in the given [start, end) range, sorted ascending by date.
    func entriesInRange(_ start: Date, _ end: Date) -> [DiaryEntry] {
        diaryEntries.filter { $0.date >= start && $0.date < end }
            .sorted { $0.date < $1.date }
    }

    /// 今天的日记(取最新一条;按 date 字段判定同日)
    /// Today's diary entry (latest one; "same day" judged by `date` field).
    func todayEntry() -> DiaryEntry? {
        let todayStart = Calendar.current.startOfDay(for: .now)
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        return entriesInRange(todayStart, todayEnd).last
    }

    // MARK: - Phase Filtering
    // MARK: - 阶段过滤 / Phase Filtering

    func reloadFilteredFromSwiftData() async {
        guard let executor else { return }
        do {
            filteredDiaryEntries = try await executor.fetchDiaryEntries(
                activePhaseID: envManager.activePhaseId
            )
        } catch is CancellationError {
            Log.data.debug("DiaryRepository filtered load cancelled")
        } catch {
            Log.data.error("DiaryRepository filtered load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var lastPersistenceError: (any Error)? { nil }

    func waitForPendingPersistence() async {}

    func flushPendingPersistence() async {}

    func cancelPendingPersistence() {}

    private func refreshFilteredFromPersistence() {
        guard executor != nil else {
            filteredDiaryEntries = diaryEntries
            return
        }
        Task { [weak self] in
            await self?.reloadFilteredFromSwiftData()
        }
    }

    // MARK: - SwiftData record helpers
    // MARK: - SwiftData 记录操作 / SwiftData record helpers

    private func removeRecord(id: UUID) {
        guard let context = modelContext else { return }
        do {
            if let entity = try context.fetch(
                FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.id == id })
            ).first {
                context.delete(entity)
                try context.save()
            }
        } catch {
            context.rollback()
            Log.data.error("DiaryRepository removeRecord failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateRecord(_ entry: DiaryEntry) {
        guard let context = modelContext else { return }
        do {
            if let entity = try context.fetch(
                FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.id == entry.id })
            ).first {
                entity.date = entry.date
                entity.moodScore = entry.moodScore
                entity.energyScore = entry.energyScore
                entity.energyTag = entry.energyTag
                entity.content = entry.content
                entity.phaseId = entry.phaseId
                entity.updatedAt = entry.updatedAt
                try context.save()
            } else {
                context.insert(DiaryEntryRecord(from: entry))
                try context.save()
            }
        } catch {
            context.rollback()
            Log.data.error("DiaryRepository updateRecord failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
