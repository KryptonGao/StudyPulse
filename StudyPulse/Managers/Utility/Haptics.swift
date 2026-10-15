//
//  Haptics.swift
//  StudyPulse
//
//  统一触觉反馈入口。所有「保存成功 / 完成 / 评分」类操作都经此处,避免各处散落
//  `UIImpactFeedbackGenerator`,也方便将来加「关闭触觉」开关。
//  Single entry point for haptic feedback. Save / complete / rating actions go through here
//  instead of scattered `UIImpactFeedbackGenerator` calls, which also makes a future
//  "disable haptics" preference a one-line change.
//

import UIKit

@MainActor
enum Haptics {
    /// 保存 / 完成 / 解锁等「成功」反馈 / Success feedback for save, complete, unlock.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 需要注意但非错误(例如闪卡评分「忘了」)/ Heads-up that isn't an error (e.g. flashcard "Again").
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// 操作失败 / Failure feedback.
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// 选项切换、评分选择等轻量确认 / Light confirmation for selection changes and ratings.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 按压类轻 / 中 / 重冲击 / Light / medium / heavy impact for press-style interactions.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
