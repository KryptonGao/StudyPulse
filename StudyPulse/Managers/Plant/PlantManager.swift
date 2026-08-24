//
//  PlantManager.swift
//  StudyPulse
//
//  主页植物状态机中央协调器。
//  Central coordinator for the home plant card.
//
//  - @MainActor @Observable 单例
//  - 订阅 AchievementManager.shared.snapshot 变化 → 触发 recomputeStage()
//  - 提供 recordActivity() 钩子（从 RepositoryContainer.addGrade/addMistake 触发）
//  - 不重新实现"每日活跃判定"，仅消费 AchievementManager 的数据
//  - 用 @ObservationIgnored 隔离 SwiftData context 等内部状态
//

import Foundation
import SwiftData
import os

@MainActor
@Observable
final class PlantManager {
    static let shared = PlantManager()

    // MARK: - Published (Observable) state

    /// 当前阶段（PlantHomeCard / PlantDetailView 订阅此属性自动刷新）。
    /// Current stage. Views observe this to re-render.
    private(set) var currentStage: PlantStage = .seed

    /// 最近一次更新时间（用于"刚刚解锁"提示）。
    private(set) var lastUpdated: Date = .distantPast

    /// 阶段切换历史（最多 50 条）。
    private(set) var history: [PlantStageTransition] = []

    /// 上一次 recordActivity 触达时间（用于 Debug 面板展示）。
    private(set) var lastActivityAt: Date?

    /// 是否有未消费的 withered 状态（仅在 derived-with-out-history 时为 true）。
    /// True when derive produced withered but the view hasn't picked it up.
    private(set) var needsTransition: Bool = false

    // MARK: - Non-observable internal state

    @ObservationIgnored
    private var achievementObservationTask: Task<Void, Never>?

    @ObservationIgnored
    private var modelContext: ModelContext?              // SwiftData 主上下文(由 attach() 注入)

    @ObservationIgnored
    private var bootstrapComplete: Bool = false         // attach 完成后才允许 recompute

    @ObservationIgnored
    private var lastDerivedStage: PlantStage = .seed    // 上一次 derive 阶段(用于检测 withered → reborn)

    // MARK: - Init

    private init() {
        // 等 attach() 注入 modelContext
        Log.plant.debug("PlantManager 初始化 / PlantManager init (singleton)")
    }

    // MARK: - Bootstrap

    /// 由 RepositoryContainer.asyncInit() 在 isReady = true 之后调用一次。
    /// 负责：加载 SwiftData 记录、订阅 AchievementManager、跑一次 derive。
    func attach(container: RepositoryContainer) {
        guard let modelContainer = container.modelContainer else {
            Log.plant.error("PlantManager.attach 失败 / attach failed: modelContainer is nil")
            return
        }
        let context = modelContainer.mainContext
        self.modelContext = context

        loadFromSwiftData(context: context)
        subscribeToAchievementManager()
        bootstrapComplete = true

        // 首次跑一次 derive
        recomputeStage()
        Log.plant.info("PlantManager bootstrap 完成 / bootstrap done: stage=\(self.currentStage.rawValue, privacy: .public) history=\(self.history.count)")
    }

    /// 注入 mock modelContext（仅用于单测 / Preview）。
    /// Inject a mock model context (for unit tests / Preview only).
    func attachForPreview(context: ModelContext, initialStage: PlantStage = .seed) {
        self.modelContext = context
        self.currentStage = initialStage
        self.lastUpdated = Date()
        self.bootstrapComplete = true
    }

    // MARK: - Activity Hook (called from RepositoryContainer)

    /// 上一次 recordActivity 触达时间。
    var lastActivityDate: Date? { lastActivityAt }

    /// 记录一次用户活动（录入成绩 / 添加错题 / 完成专注）。
    /// 无论 plantCardEnabled 是否关闭，都会执行（用于 reborn 判定 + Debug 追踪）。
    /// Always runs regardless of plantCardEnabled; required for reborn transition
    /// when the user re-enables the card after withering.
    func recordActivity(trigger: ActivityTrigger) {
        lastActivityAt = Date()
        Log.plant.debug("recordActivity / trigger=\(trigger.rawValue, privacy: .public)")

        // 不立即重算（achievement 还没更新）；交给 AchievementManager 的 $snapshot sink 触发。
        // Derive is triggered by the AchievementManager subscription, not here.
    }

    // MARK: - Stage Computation

    /// 读取 AchievementManager 的最新 snapshot，重新计算 stage。
    /// Recompute the current stage from the AchievementManager snapshot.
    func recomputeStage() {
        guard bootstrapComplete else { return }

        let snapshot = AchievementManager.shared.snapshot
        let streak = snapshot.streak
        let todayLog = AchievementManager.shared.todayLog
        let todayActive = snapshot.config.isActiveDay(todayLog)

        // Debug 模拟值优先；nil 则用 AchievementManager 真实值。
        // Debug simulations take precedence over real AchievementManager data.
        let simRecord = currentRecord()
        let effectiveStreak = simRecord?.simulatedStreakOverride ?? streak.current
        let effectiveLastActive = simRecord?.simulatedLastActiveDate ?? streak.lastActiveDate
        let effectiveTotalActive = streak.totalActiveDays // 不模拟 totalActiveDays

        let previouslyWithered = (lastDerivedStage == .withered)

        let derived = PlantStage.derive(
            streak: effectiveStreak,
            totalActiveDays: effectiveTotalActive,
            todayActive: todayActive,
            lastActiveDate: effectiveLastActive,
            previouslyWithered: previouslyWithered
        )

        // Debug 强制覆盖（最高优先级）
        // Debug force override (highest priority).
        let finalStage: PlantStage
        if let override = historyLastForceOverride() {
            finalStage = override
        } else {
            finalStage = derived
        }

        let now = Date()
        if finalStage != currentStage {
            let transition = PlantStageTransition(
                fromStage: currentStage,
                toStage: finalStage,
                date: now,
                trigger: "derive"
            )
            history.append(transition)
            // 限制历史长度
            if history.count > 50 {
                history.removeFirst(history.count - 50)
            }
            currentStage = finalStage
            lastUpdated = now
            needsTransition = true
            Log.plant.info("阶段切换 / Stage transition: \(transition.fromStage.rawValue, privacy: .public) → \(transition.toStage.rawValue, privacy: .public) trigger=\(transition.trigger, privacy: .public)")
        }

        lastDerivedStage = finalStage
        persist()
    }

    /// 标记"刚刚的 transition 已被 view 消费"。
    /// Mark the latest transition as consumed by the view layer.
    func consumeTransition() {
        needsTransition = false
    }

    // MARK: - Debug Force Override

    /// Debug 用：强制设置当前阶段（绕过 derive 逻辑）。传 nil 清除覆盖。
    /// Debug only: force-set the current stage; nil clears the override.
    func setForceOverride(_ stage: PlantStage?) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<PlantStateRecord>()
        guard let record = try? context.fetch(descriptor).first else { return }

        record.forceOverrideRaw = stage?.rawValue
        guard context.saveOrRollback("PlantManager.setForceOverride") else { return }

        if let stage {
            currentStage = stage
            Log.plant.warning("Debug 强制覆盖阶段 / Force override: -> \(stage.rawValue, privacy: .public)")
        } else {
            Log.plant.info("Debug 清除强制覆盖 / Clear override; will re-derive on next recompute")
            recomputeStage()
        }
    }

    /// 当前是否处于 force override 状态。
    var hasForceOverride: Bool {
        historyLastForceOverride() != nil
    }

    /// 读取最近一次保存的 forceOverride（从 SwiftData record）。
    private func historyLastForceOverride() -> PlantStage? {
        currentRecord()?.forceOverrideRaw.flatMap(PlantStage.init(rawValue:))
    }

    // MARK: - Debug Simulation

    /// 模拟"连续打卡 N 天"（仅用于 Debug 面板，临时覆盖 derive 用的 streak.current）。
    /// Simulate a streak of N days. Pass `nil` to clear.
    func setSimulatedStreak(_ value: Int?) {
        guard let record = currentRecord() else { return }
        record.simulatedStreakOverride = value
        try? modelContext?.save()
        recomputeStage()
        Log.plant.info("Debug 模拟 streak / Simulated streak: \(value.map(String.init) ?? "nil", privacy: .public)")
    }

    /// 模拟"距上次活跃 N 天"（临时把 lastActiveDate 推回到 N 天前）。
    /// 传 0 表示今天；传 nil 清除模拟（恢复真实 lastActiveDate）。
    func setSimulatedDaysSinceLastActive(_ days: Int?) {
        guard let record = currentRecord() else { return }
        if let days {
            let date = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-Double(days) * 86_400)
            record.simulatedLastActiveDate = date
        } else {
            record.simulatedLastActiveDate = nil
        }
        try? modelContext?.save()
        recomputeStage()
        Log.plant.info("Debug 模拟断签天数 / Simulated days since last active: \(days.map(String.init) ?? "nil", privacy: .public)")
    }

    /// 清除所有 Debug 模拟（streak + lastActiveDate），并保留 forceOverride。
    func clearAllSimulations() {
        guard let record = currentRecord() else { return }
        record.simulatedStreakOverride = nil
        record.simulatedLastActiveDate = nil
        try? modelContext?.save()
        recomputeStage()
        Log.plant.info("Debug 清除全部模拟 / Cleared all simulations")
    }

    /// 清空历史切换记录（不影响 forceOverride / 模拟值）。
    func clearHistory() {
        history.removeAll()
        persist()
        Log.plant.info("Debug 清空历史 / Cleared plant history")
    }

    /// 一键重置：清除 stage / 历史 / override / 模拟值，回到首次启动状态。
    /// 注意：不修改 SwiftData 记录（保留 record 但重置全部字段），下次 derive 会自然走回 seed。
    func resetToSeed() {
        guard let record = currentRecord() else { return }
        currentStage = .seed
        lastDerivedStage = .seed
        history.removeAll()
        lastUpdated = Date()
        lastActivityAt = nil
        record.currentStageRaw = PlantStage.seed.rawValue
        record.previousStageRaw = PlantStage.seed.rawValue
        record.historyData = nil
        record.forceOverrideRaw = nil
        record.simulatedStreakOverride = nil
        record.simulatedLastActiveDate = nil
        try? modelContext?.save()
        Log.plant.warning("Debug 一键重置 / Reset to seed")
    }

    /// 当前是否在模拟 streak。
    var hasSimulatedStreak: Bool {
        currentRecord()?.simulatedStreakOverride != nil
    }

    /// 当前是否在模拟 lastActiveDate。
    var hasSimulatedLastActive: Bool {
        currentRecord()?.simulatedLastActiveDate != nil
    }

    // MARK: - SwiftData Persistence

    /// 读取单条 PlantStateRecord（不存在则返回 nil）。
    func currentRecord() -> PlantStateRecord? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<PlantStateRecord>()
        return try? context.fetch(descriptor).first
    }

    private func loadFromSwiftData(context: ModelContext) {
        let descriptor = FetchDescriptor<PlantStateRecord>()
        if let record = try? context.fetch(descriptor).first {
            let snapshot = record.toSnapshot()
            self.currentStage = snapshot.currentStage
            self.history = snapshot.history
            self.lastUpdated = snapshot.lastUpdated
            self.lastActivityAt = snapshot.lastActivityAt
            self.lastDerivedStage = record.previousStage
            Log.plant.debug("从 SwiftData 加载 / Loaded from SwiftData: stage=\(self.currentStage.rawValue, privacy: .public) history=\(self.history.count)")
        } else {
            // 首启：插入 seed 记录
            let initial = PlantState(currentStage: .seed, lastUpdated: Date())
            let record = PlantStateRecord(from: initial, previousStage: .seed)
            context.insert(record)
            context.saveOrRollback("PlantManager.bootstrap(seed)")
            self.currentStage = .seed
            self.history = []
            self.lastUpdated = Date()
            self.lastDerivedStage = .seed
            Log.plant.info("首启：插入初始 seed 记录 / First launch: inserted initial seed record")
        }
    }

    private func persist() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<PlantStateRecord>()
        guard let record = try? context.fetch(descriptor).first else { return }

        let snapshot = PlantState(
            currentStage: currentStage,
            history: history,
            lastUpdated: lastUpdated,
            forceOverride: record.forceOverrideRaw.flatMap(PlantStage.init(rawValue:)),
            lastActivityAt: lastActivityAt
        )
        let data: Data? = snapshot.history.isEmpty ? nil : try? JSONEncoder().encode(snapshot.history)
        record.currentStageRaw = snapshot.currentStage.rawValue
        record.historyData = data
        record.lastUpdated = snapshot.lastUpdated
        record.lastActivityAt = snapshot.lastActivityAt
        record.previousStageRaw = lastDerivedStage.rawValue
        context.saveOrRollback("PlantManager.persist")
    }

    // MARK: - AchievementManager Subscription

    private func subscribeToAchievementManager() {
        // 通过 NotificationCenter 监听 `achievementsSnapshotDidChange` 通知,
        // 替代原 1.5s polling(每分钟 40 次 MainActor 唤醒)。
        // Snapshot 是用户主动操作(录入成绩 / 错题复习 / 完成专注)后才变化的,事件驱动完全足够。
        // 仍保留 `currentSignature()` 比对:同一个 snapshot 变化但 streak 未变时跳过 derive。
        // Listen to `achievementsSnapshotDidChange` via NotificationCenter (replaces the
        // 1.5s polling that woke the main actor 40 times per minute).
        // Snapshot only changes on user actions (grade / mistake review / focus session),
        // so event-driven observation is sufficient.
        // `currentSignature()` is still compared to skip derive when streak didn't change.
        achievementObservationTask?.cancel()
        var lastSig = currentSignature()
        achievementObservationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .achievementsSnapshotDidChange) {
                guard !Task.isCancelled, let self else { return }
                let sig = self.currentSignature()
                if sig != lastSig {
                    lastSig = sig
                    self.recomputeStage()
                }
            }
        }
        Log.plant.debug("订阅 AchievementManager 变化 / Subscribed to AchievementManager via NotificationCenter")
    }

    /// 当前 AchievementManager 状态的轻量签名(用于变化检测)。
    private func currentSignature() -> String {
        let s = AchievementManager.shared.snapshot.streak
        let t = AchievementManager.shared.todayLog
        return "\(s.current)|\(s.totalActiveDays)|\(s.lastActiveDate.map { "\($0.timeIntervalSince1970)" } ?? "nil")|\(t.totalActivityPoints)"
    }
}

// MARK: - ActivityTrigger

extension PlantManager {
    /// 触发 recordActivity 的来源（仅用于日志分类，不影响 derive 逻辑）。
    @MainActor
    enum ActivityTrigger: String, Sendable {
        case grade
        case mistake
        case focus
    }
}
