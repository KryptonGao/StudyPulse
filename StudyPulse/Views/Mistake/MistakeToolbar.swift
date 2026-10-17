//
//  MistakeToolbar.swift
//  StudyPulse
//
//  错题相关的 ToolbarContent 集合,按"列表 / 详情"两种上下文拆开:
//  - MistakeListToolbarLeading  : 顶部左边的"复习队列"入口(带 due count 红点)
//  - MistakeListToolbarTrailing : 顶部右边的"工具菜单(AI Quiz / Mind Map / Tag Graph / PDF) + New"
//  - MistakeDetailToolbar       : 详情页右侧的"Edit / Quick Review / AI"组合
//
//  Mistake-related ToolbarContent collection, split by context:
//  - MistakeListToolbarLeading  : top-left "review queue" entry (with due-count red dot)
//  - MistakeListToolbarTrailing : top-right "AI Quiz / Tag Graph / PDF / New"
//  - MistakeDetailToolbar       : detail page's "Edit / Quick Review / AI" group
//

import SwiftUI

/// "按标签复习"行(挂在 leading 菜单里)
/// "Review by tag" entry (used inside the leading menu).
struct TagDueEntry: Identifiable {
    var id: String { tag }
    /// 标签名
    /// Tag name.
    let tag: String
    /// 该标签的 due 错题数
    /// Number of due mistakes under the tag.
    let count: Int
}





/// 错题详情页 toolbar(Edit + Quick Review;AI 动作在页面底部浮动栏)
/// Mistake detail page toolbar (Edit + Quick Review; AI actions live in the bottom bar).
struct MistakeDetailToolbar: ToolbarContent {
    @Environment(RepositoryContainer.self) private var container
    /// 当前错题的实时版本
    /// Live copy of the current mistake.
    let liveMistake: MistakeNote
    /// Edit 回调
    /// Edit callback.
    let onEdit: () -> Void
    /// Quick Review 回调
    /// Quick review callback.
    let onQuickReview: () -> Void

    var body: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarTrailing) {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    NavigationLink {
                        MistakeDetailEditView(
                            container: container,
                            mistakeSet: liveMistake,
                            usesInternalNavigationStack: false
                        )
                        .adaptiveSheet()
                    } label: {
                        Text("Edit".localized())
                    }
                } else {
                    Button("Edit".localized(), action: onEdit)
                }
            }
            if liveMistake.isInReviewQueue {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onQuickReview) {
                        Image(systemName: "rectangle.stack")
                    }
                    .accessibilityLabel("Quick Review".localized())
                }
            }
        }
    }
}
