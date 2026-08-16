//
//  FlashcardStudyViewModel.swift
//  StudyPulse
//
//  Created by Antigravity on 2026/7/12.
//
//  闪卡学习页 ViewModel。负责按筛选器加载错题队列、驱动翻面/评分流程、
//  累积会话统计,保存手写 + SRS 状态。
//  Flashcard-study VM. Loads mistake queue by filter, drives flip/rating
//  flow, accumulates session stats, persists handwriting + SRS state.
//

import Foundation
import SwiftUI
import PencilKit
import os

@MainActor
@Observable
final class FlashcardStudyViewModel {
    // MARK: - 依赖项 / Dependencies
    private let container: RepositoryContainer
    private let climateHistoryURL: URL?
    /// 触发本次学习的筛选条件 / Filter for this study session.
    let filter: FlashcardFilter

    // MARK: - 输出状态 / Output states
    /// 剩余待复习错题队列 / Remaining mistakes queue.
    var queue: [FlashcardQueueItem] = []
    /// 当前卡片在 queue 中的索引 / Index of the current card.
    var currentIndex: Int = 0
    /// 是否翻到答案面 / Flipped to answer side?
    var isFlipped: Bool = false
    /// 本次会话统计 / Per-session statistics.
    var stats: FlashcardSessionStats = FlashcardSessionStats()
    /// 是否显示总结页 / Show session summary?
    var showingSummary: Bool = false
    /// "再来一次"重新插入的错题 / Mistakes re-queued for "Again".
    var reinsertQueue: [FlashcardQueueItem] = []
    /// 是否显示计算器 / Show calculator?
    var showingCalculator: Bool = false
    /// 是否启用手写板 / Handwriting board enabled?
    var handwritingEnabled: Bool = false
    /// 当前手写画板 / Current PKDrawing.
    var currentDrawing: PKDrawing = PKDrawing()
    /// 本次会话收集的手写 PNG / Handwriting PNGs collected this session.
    var sessionHandwriting: [UUID: Data] = [:]
    /// 当前卡片是否已提交手写 / Has the current card's handwriting been submitted?
    var hasSubmittedCurrent: Bool = false
    /// 是否显示"必须先提交手写"提示 / Show "handwriting required" alert?
    var showHandwritingRequiredAlert: Bool = false

    // MARK: - 初始化 / Initialization
    init(
        container: RepositoryContainer,
        filter: FlashcardFilter,
        handwritingEnabled: Bool = false,
        climateHistoryURL: URL? = nil
    ) {
        self.container = container
        self.filter = filter
        self.handwritingEnabled = handwritingEnabled
        self.climateHistoryURL = climateHistoryURL
        loadQueue()
    }

    // MARK: - 计算属性 / Computed properties
    /// 当前展示的错题(越界返回 nil) / Currently displayed mistake (nil if OOB).
    var currentMistake: MistakeNote? {
        guard currentIndex < queue.count else { return nil }
        return queue[currentIndex].mistake
    }

    var currentQueueItem: FlashcardQueueItem? {
        guard currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    /// 本次会话总题数 / Total cards in this session.
    var totalToReview: Int {
        queue.count + reinsertQueue.count
    }

    /// 完成进度(0.0~1.0) / Completion progress (0.0~1.0).
    var progress: Double {
        guard totalToReview > 0 else { return 0 }
        return Double(stats.reviewed) / Double(totalToReview)
    }

    // MARK: - 操作 / Actions
    /// 根据 `filter` 重新加载队列并重置会话状态
    /// Reload queue by `filter` and reset session state.
    func loadQueue() {
        switch filter {
        case .dueQueue:
            let mistakes = container.mistakeRepo.filteredMistakeSets
            let due = SRSAlgorithm.dueMistakes(from: mistakes)
            let climate = MemoryClimateEngine.generate(
                mistakes: mistakes,
                phaseId: container.envManager.activePhaseId
            )
            queue = ClimateInterleavingEngine.buildQueue(
                due: due,
                allMistakes: mistakes,
                climate: climate
            )
        case .single(let note):
            queue = [.scheduled(note)]
        case .tag(let tag):
            let due = SRSAlgorithm.dueMistakes(from: container.mistakeRepo.mistakeSets)
            queue = MistakeFilter.tagged(due, tag: tag).map(FlashcardQueueItem.scheduled)
        case .remediation(let notes):
            // 补救任务卡片按给定顺序复习，走正常 SM-2，不绕过 SRS 规则。
            queue = notes.map(FlashcardQueueItem.scheduled)
        }
        // 重置会话状态 / Reset all session-scoped state.
        currentIndex = 0
        isFlipped = false
        stats = FlashcardSessionStats()
        reinsertQueue = []
        handwritingEnabled = false
        currentDrawing = PKDrawing()
        hasSubmittedCurrent = false
        sessionHandwriting = [:]
    }

    /// 切换手写板;关闭时清空画板 + 已提交缓存
    /// Toggles the handwriting board; clears drawing + cache on disable.
    func toggleHandwriting() {
        handwritingEnabled.toggle()
        if !handwritingEnabled {
            currentDrawing = PKDrawing()
            hasSubmittedCurrent = false
            if let id = currentMistake?.id {
                sessionHandwriting.removeValue(forKey: id)
            }
        }
    }

    /// 提交当前卡的手写截图(PNG)
    /// Submit the handwriting screenshot (PNG) for the current card.
    func submitHandwriting(pngData: Data) {
        guard let id = currentMistake?.id else { return }
        sessionHandwriting[id] = pngData
        hasSubmittedCurrent = true
        // 隐私安全:仅记 id 和字节数 / Privacy-safe: log id & byte count only.
        Log.view.info("FlashcardStudyViewModel handwriting submitted: mistakeId=\(id.uuidString, privacy: .public) bytes=\(pngData.count, privacy: .public)")
    }

    /// 清除当前卡的手写 / Clear handwriting for the current card.
    func clearHandwriting() {
        guard let id = currentMistake?.id else { return }
        currentDrawing = PKDrawing()
        hasSubmittedCurrent = false
        sessionHandwriting.removeValue(forKey: id)
    }

    /// 处理用户评分:更新 SRS + 记录手写 + 决定是否重抽
    /// Handle a user rating: update SRS, record handwriting, decide on re-queue.
    func handleRating(_ quality: ReviewQuality) {
        guard let current = currentMistake, let currentItem = currentQueueItem else { return }
        stats.record(quality)
        if let pair = currentItem.interference {
            stats.recordEarlyContrast(pair)
        }

        switch currentItem.source {
        case .earlyContrast:
            // Early contrast cards contribute retrieval evidence but must not
            // move the scheduled SRS due date.
            break
        case .scheduled:
            switch filter {
            case .dueQueue, .tag, .remediation:
            // 队列模式:正常推进 SRS / Queue mode: run SRS progression.
                if var state = current.reviewState {
                    state = SRSAlgorithm.apply(quality: quality, to: state, difficulty: current.difficulty)
                    container.mistakeRepo.updateReviewState(current.id, newState: state)
                }
            case .single:
            // 单题模式:只记时间,不参与真实 SRS / Single mode: stamp time only.
                if var state = current.reviewState {
                    state.lastReviewDate = Date()
                    // 强制 1 天后再看 / Force 1-day follow-up.
                    if let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Date()) {
                        state.nextReviewDate = nextDay
                    }
                    container.mistakeRepo.updateReviewState(current.id, newState: state)
                }
            }
        }

        // 不论是否 SRS,都记复习历史 / Always record a review history entry.
        container.mistakeRepo.recordReview(current.id, quality: quality, now: Date())

        // 启用手写时持久化 PNG / If handwriting enabled, persist the PNG.
        if handwritingEnabled, let png = sessionHandwriting[current.id] {
            container.mistakeRepo.recordHandwriting(current.id, pngData: png, quality: quality, now: Date())
        }

        // "再来一次" → 队列模式重抽 / "Again" → re-insert in queue mode.
        if quality == .again, !filter.isSingleMode, !currentItem.isEarlyContrast {
            reinsertQueue.append(currentItem)
        }

        refreshMemoryClimate()
        advance()
    }

    /// 推进到下一张卡片 / Advance to the next card.
    private func advance() {
        isFlipped = false
        let prevId = currentMistake?.id
        currentDrawing = PKDrawing()
        hasSubmittedCurrent = false
        if let id = prevId {
            sessionHandwriting.removeValue(forKey: id)
        }

        // 50ms 延迟:等翻回正面动画播完再切,避免叠加
        // 50ms delay: finish the "flip back" animation before swapping.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            if self.currentIndex < self.queue.count - 1 {
                self.currentIndex += 1
            } else {
                if !self.reinsertQueue.isEmpty {
                    // 主队列走完 → 切到 "再来一次" 队列
                    // Main queue exhausted → switch to "again" queue.
                    self.queue = self.reinsertQueue
                    self.reinsertQueue = []
                    self.currentIndex = 0
                } else {
                    self.finishSession()
                }
            }
        }
    }

    /// 结束本次会话 / End the session.
    func finishSession() {
        stats.endTime = Date()
        showingSummary = true
        SRSReviewNotifications.shared.rescheduleAll(mistakes: container.mistakeRepo.mistakeSets)
    }

    private func refreshMemoryClimate(now: Date = Date()) {
        let snapshot = MemoryClimateEngine.generate(
            mistakes: container.mistakeRepo.filteredMistakeSets,
            phaseId: container.envManager.activePhaseId,
            now: now
        )
        MemoryClimateHistoryStore.upsert(snapshot, at: climateHistoryURL, now: now)
    }
}
