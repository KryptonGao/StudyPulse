//
//  SpacedRepetition.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/6/27.
//

import Foundation
import SwiftUI

// MARK: - Review State

/// 错题的 SRS（间隔重复）状态。
/// 嵌套在 `MistakeNote.reviewState` 中，`nil` 表示未加入复习队列。
/// SM-2 算法使用的核心字段：repetitions（连续答对次数）、easeFactor（难度系数）、
/// intervalDays（下一次复习间隔天数）、nextReviewDate（下次复习日期）。
nonisolated struct ReviewState: Codable, Equatable, Hashable, Sendable {
    /// 连续答对次数（Again 会重置为 0）
    var repetitions: Int
    /// 难度系数 SM-2 EF，初始 2.5，最小 1.3
    var easeFactor: Double
    /// 当前复习间隔（天）
    var intervalDays: Int
    /// 下次复习日期
    var nextReviewDate: Date
    /// 上次复习日期（首次入队时为 nil）
    var lastReviewDate: Date?
    /// 累计「Again」次数
    var lapses: Int

    init(
        repetitions: Int = 0,
        easeFactor: Double = 2.5,
        intervalDays: Int = 0,
        nextReviewDate: Date,
        lastReviewDate: Date? = nil,
        lapses: Int = 0
    ) {
        self.repetitions = repetitions
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.nextReviewDate = nextReviewDate
        self.lastReviewDate = lastReviewDate
        self.lapses = lapses
    }

    /// 创建一个「明天到期」的初始状态
    static func initial(now: Date = Date()) -> ReviewState {
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return ReviewState(nextReviewDate: nextDay)
    }
}

// MARK: - Review Quality

/// SM-2 自评档位（4 档按钮，对应 Anki 经典交互）
/// 由于包含 Color 字段（SwiftUI 类型），不能为 nonisolated。
enum ReviewQuality: Int, CaseIterable, Identifiable, Codable {
    case again = 1   // 忘了，重新学习
    case hard = 3    // 模糊，记忆吃力
    case good = 4    // 记得，难度适中
    case easy = 5    // 轻松，长期掌握

    var id: Int { rawValue }

    /// 短标签（按钮显示）
    var shortTitle: String {
        switch self {
        case .again: return "Again".localized()
        case .hard:  return "Hard".localized()
        case .good:  return "Good".localized()
        case .easy:  return "Easy".localized()
        }
    }

    /// 详细描述（用于 Tooltip / 副标题）
    var description: String {
        switch self {
        case .again: return "I forgot".localized()
        case .hard:  return "It was tough".localized()
        case .good:  return "I remembered".localized()
        case .easy:  return "Effortless".localized()
        }
    }

    /// SM-2 难度对应的展示色（视图层使用）
    var color: Color {
        switch self {
        case .again: return .red
        case .hard:  return .orange
        case .good:  return .blue
        case .easy:  return .green
        }
    }
}

// MARK: - SRS Overview

/// SRS 队列统计概览
nonisolated struct SRSOverview: Equatable {
    /// 已到期、需复习的张数
    var dueCount: Int
    /// 7 天内即将到期的张数（不含 due）
    var upcomingCount: Int
    /// 累计入队的张数
    var totalEnrolled: Int

    static let empty = SRSOverview(dueCount: 0, upcomingCount: 0, totalEnrolled: 0)
}

// MARK: - SM-2 Algorithm

/// SM-2 间隔重复算法（pure Swift，nonisolated）
/// 参考：Piotr Wozniak, "Optimization of repetition spacing in the practice of learning" (1990)
/// 经典 Anki 实现：4 档按钮 → quality 1 / 3 / 4 / 5。
nonisolated enum SRSAlgorithm {
    /// 最小难度系数（Anki 规定 1.3）
    static let minEaseFactor: Double = 1.3
    /// intervalDays 硬上限(2 年):防止连续 easy 指数增长溢出,
    /// 保证 nextReviewDate 的日期加法不会回退。
    /// Hard cap for intervalDays (2 years): prevents unbounded exponential
    /// growth from repeated `easy` reviews, which would overflow
    /// `date(byAdding:)` and collapse nextReviewDate to `now`.
    static let maxIntervalDays: Int = 730
    /// 默认初始难度系数
    static let defaultEaseFactor: Double = 2.5
    /// 「未来 7 天」窗口，用于 upcoming 统计
    static let upcomingWindowDays: Int = 7
    /// 难度乘子表（1-5 星 → intervalDays 乘子）。
    /// 用户自评难度在 SM-2 算完 intervalDays 之后再次缩放:
    /// - 1 星(简单)→ 0.5×:更频繁复习
    /// - 3 星(中等)→ 1.0×:无影响
    /// - 5 星(困难)→ 1.6×:拉长间隔
    /// 0 / 缺省视为 1.0。
    /// Difficulty multipliers (1-5 stars → intervalDays multiplier).
    /// Applied AFTER SM-2 computes intervalDays:
    /// - 1★ (easy) → 0.5×: review more often
    /// - 3★ (medium) → 1.0×: no change
    /// - 5★ (hard) → 1.6×: stretch intervals
    /// 0 / missing treated as 1.0.
    static let difficultyMultipliers: [Int: Double] = [
        1: 0.5,
        2: 0.75,
        3: 1.0,
        4: 1.3,
        5: 1.6
    ]

    /// 取难度乘子（未评 / 越界 → 1.0）
    /// Multiplier for a given difficulty (0 / out-of-range → 1.0).
    static func difficultyMultiplier(for difficulty: Int) -> Double {
        difficultyMultipliers[difficulty] ?? 1.0
    }

    /// 根据自评档位计算下一状态
    /// - Parameters:
    ///   - quality: 自评档位
    ///   - state: 当前状态
    ///   - difficulty: 用户自评难度 1-5;0 = 未评(乘子 1.0)
    ///   - now: 评估时间（默认 Date()，便于测试）
    /// - Returns: 更新后的状态
    static func apply(quality: ReviewQuality, to state: ReviewState, difficulty: Int = 0, now: Date = Date()) -> ReviewState {
        var newState = state
        newState.lastReviewDate = now

        switch quality {
        case .again:
            // 答错：重置为学习模式
            newState.repetitions = 0
            newState.intervalDays = 1
            newState.lapses += 1
            // EF 轻微下调（不要重置太狠）
            newState.easeFactor = max(minEaseFactor, state.easeFactor - 0.20)

        case .hard:
            // 答得吃力：少量拉长间隔，EF 略降
            newState.repetitions = state.repetitions + 1
            if newState.repetitions == 1 {
                newState.intervalDays = 1
            } else if newState.repetitions == 2 {
                newState.intervalDays = 4
            } else {
                let prevInterval = max(1, state.intervalDays)
                newState.intervalDays = max(1, Int((Double(prevInterval) * 1.2).rounded()))
            }
            newState.easeFactor = max(minEaseFactor, state.easeFactor - 0.15)

        case .good:
            // 标准 SM-2 公式
            newState.repetitions = state.repetitions + 1
            switch newState.repetitions {
            case 1:
                newState.intervalDays = 1
            case 2:
                newState.intervalDays = 6
            default:
                let prevInterval = max(1, state.intervalDays)
                newState.intervalDays = Int((Double(prevInterval) * state.easeFactor).rounded())
            }

        case .easy:
            // 答得轻松：间隔大幅拉长，EF 上升
            newState.repetitions = state.repetitions + 1
            switch newState.repetitions {
            case 1:
                newState.intervalDays = 4
            case 2:
                newState.intervalDays = 7
            default:
                let prevInterval = max(1, state.intervalDays)
                let bonus = Double(prevInterval) * state.easeFactor * 1.3
                newState.intervalDays = Int(bonus.rounded())
            }
            newState.easeFactor = min(3.0, state.easeFactor + 0.15)
        }

        // 难度后置调权:在 SM-2 算完 intervalDays 之后按用户难度乘子再次缩放。
        // Post-SM-2 difficulty scaling: rescale intervalDays by the user's
        // self-rated difficulty multiplier. 0 (unrated) → 1.0 (no change).
        let multiplier = difficultyMultiplier(for: difficulty)
        if multiplier != 1.0 {
            newState.intervalDays = max(1, Int((Double(newState.intervalDays) * multiplier).rounded()))
        }

        // 统一硬上限:good/easy/难度乘子全路径封顶,防止间隔无界增长。
        // Unified hard cap across good/easy/difficulty-multiplier paths.
        newState.intervalDays = min(Self.maxIntervalDays, max(1, newState.intervalDays))

        // 计算下次复习日期（基于今天的 09:00，避免深夜推送）
        let baseDate = Calendar.current.startOfDay(for: now)
        guard let nextDate = Calendar.current.date(byAdding: .day, value: newState.intervalDays, to: baseDate) else {
            newState.nextReviewDate = now
            return newState
        }
        // 把时间统一到 09:00（上午 9 点提醒）
        var components = Calendar.current.dateComponents([.year, .month, .day], from: nextDate)
        components.hour = 9
        components.minute = 0
        newState.nextReviewDate = Calendar.current.date(from: components) ?? nextDate

        return newState
    }

    /// 取出当前应复习的错题（已 opt-in 且 nextReviewDate <= now）
    /// - Parameters:
    ///   - notes: 全部错题
    ///   - now: 评估时间
    /// - Returns: 按 nextReviewDate 升序的错题列表
    static func dueMistakes(from notes: [MistakeNote], now: Date = Date()) -> [MistakeNote] {
        notes
            .filter { note in
                guard let state = note.reviewState else { return false }
                return state.nextReviewDate <= now
            }
            .sorted { (a, b) in
                guard let sa = a.reviewState, let sb = b.reviewState else { return false }
                if sa.nextReviewDate != sb.nextReviewDate {
                    return sa.nextReviewDate < sb.nextReviewDate
                }
                return a.date > b.date  // 题目本身更近的优先
            }
    }

    /// 队列总览统计
    static func overview(from notes: [MistakeNote], now: Date = Date()) -> SRSOverview {
        let enrolled = notes.filter { $0.reviewState != nil }
        let due = enrolled.filter {
            guard let state = $0.reviewState else { return false }
            return state.nextReviewDate <= now
        }
        let upcomingThreshold = Calendar.current.date(byAdding: .day, value: upcomingWindowDays, to: now) ?? now
        let upcoming = enrolled.filter {
            guard let state = $0.reviewState else { return false }
            return state.nextReviewDate > now && state.nextReviewDate <= upcomingThreshold
        }
        return SRSOverview(
            dueCount: due.count,
            upcomingCount: upcoming.count,
            totalEnrolled: enrolled.count
        )
    }
}

// MARK: - MistakeNote 扩展

extension MistakeNote {
    /// 是否已加入 SRS 复习队列
    var isInReviewQueue: Bool { reviewState != nil }
}
