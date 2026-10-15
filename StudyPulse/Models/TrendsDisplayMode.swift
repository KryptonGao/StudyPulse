//
//  TrendsDisplayMode.swift
//  StudyPulse
//
//  趋势页卡片 / 科目详情的显示模式(取代原先用字符串 "score" / "ranking" 存储的状态)。
//  Trends card / subject-detail display mode (replaces the former "score" / "ranking" string state).
//

import Foundation

/// 趋势页显示模式:分数 或 排名。
/// Trends display mode: score or ranking.
nonisolated enum TrendsDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case score
    case ranking

    var id: String { rawValue }

    /// SF Symbol 图标
    var icon: String {
        switch self {
        case .score: "chart.bar.fill"
        case .ranking: "trophy.fill"
        }
    }

    /// 本地化名称(复用已有的 "Score" / "Ranking" 键)
    /// Localized name (reuses the existing "Score" / "Ranking" keys).
    @MainActor var localizedName: String {
        switch self {
        case .score: "Score".localized()
        case .ranking: "Ranking".localized()
        }
    }
}
