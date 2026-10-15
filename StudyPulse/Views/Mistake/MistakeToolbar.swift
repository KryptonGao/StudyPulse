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

/// 错题列表 toolbar 左侧菜单(复习入口)
/// Mistake list toolbar leading menu (review entry point).
struct MistakeListToolbarLeading: ToolbarContent {
    /// 当前已加入 SRS 的错题总数
    /// Total mistakes currently in the SRS pipeline.
    let totalEnrolled: Int
    /// 当前到期的错题数
    /// Number of due mistakes right now.
    let dueCount: Int
    /// 按标签分桶的 due 错题(显示在菜单里)
    /// Due mistakes bucketed by tag (shown inside the menu).
    let dueTags: [TagDueEntry]
    /// 选择 filter 时的回调
    /// Callback when the user picks a filter.
    let onFilterSelect: (FlashcardFilter) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if totalEnrolled > 0 {
                Menu {
                    Button {
                        onFilterSelect(.dueQueue)
                    } label: {
                        Label("Review All Due".localized(), systemImage: "rectangle.stack")
                    }
                    if !dueTags.isEmpty {
                        Divider()
                        Text("Review by Tag".localized())
                        ForEach(dueTags) { entry in
                            Button {
                                onFilterSelect(.tag(entry.tag))
                            } label: {
                                Label("#\(entry.tag) (\(entry.count))", systemImage: "tag")
                            }
                        }
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "rectangle.stack")
                        if dueCount > 0 {
                            Text("\(dueCount)")
                                .font(.system(size: 10).weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(Color.red)
                                )
                                .offset(x: 8, y: -6)
                        }
                    }
                }
                .accessibilityLabel("Flashcard Review".localized())
            }
        }
    }
}

/// 错题列表 toolbar 右侧(AI Quiz / Tag Graph / PDF / New)
/// Mistake list toolbar trailing group (AI Quiz / Tag Graph / PDF / New).
struct MistakeListToolbarTrailing: ToolbarContent {
    /// 是否存在错题(决定是否显示 PDF 导出按钮)
    /// Whether any mistakes exist (drives whether the PDF export button shows).
    let hasMistakes: Bool
    /// 是否存在标签(决定是否显示 Tag Graph 按钮)
    /// Whether any tags exist (drives whether the tag graph button shows).
    let hasTags: Bool
    /// 打开"标签图谱"
    /// Open the "tag graph".
    let onShowTagGraph: () -> Void
    /// 打开"思维导图"
    /// Open the "mind map".
    let onShowMindMap: () -> Void
    /// 打开"PDF 导出"
    /// Open the "PDF export".
    let onShowPDFExport: () -> Void
    /// 打开"新建错题"sheet
    /// Open the "new mistake" sheet.
    let onShowNewMistake: () -> Void
    /// 打开"AI Quiz"
    /// Open the "AI Quiz".
    let onShowAIQuiz: () -> Void
    /// iPad 上需要 push 而不是 sheet(用于 New 按钮)
    /// iPad uses a push instead of a sheet (for the New button).
    let container: RepositoryContainer

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 12) {
                // 所有工具收进单一「工具」菜单,按用途分组;无错题时对应项置灰而非隐藏,保持可发现
                // All tools live in one grouped "Tools" menu; items that need data are disabled
                // (not hidden) so they stay discoverable.
                Menu {
                    Section("mistake.tools.ai".localized()) {
                        Button(action: onShowAIQuiz) {
                            Label("AI Quiz".localized(), systemImage: "sparkles.rectangle.stack")
                        }
                        Button(action: onShowMindMap) {
                            Label("Auto Mind Map".localized(), systemImage: "arrow.triangle.branch")
                        }
                        .disabled(!hasMistakes)
                    }
                    Section("mistake.tools.organize".localized()) {
                        Button(action: onShowTagGraph) {
                            Label("Tag Graph".localized(), systemImage: "circle.hexagongrid")
                        }
                        .disabled(!hasTags)
                        Button(action: onShowPDFExport) {
                            Label("Export PDF".localized(), systemImage: "square.and.arrow.up")
                        }
                        .disabled(!hasMistakes)
                    }
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                }
                .accessibilityLabel("mistake.tools.menu".localized())

                if UIDevice.current.userInterfaceIdiom == .pad {
                    NavigationLink {
                        NewMistakeSetView(container: container, usesInternalNavigationStack: false)
                            .environment(container)
                            .adaptiveSheet()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Mistake".localized())
                } else {
                    Button(action: onShowNewMistake) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Mistake".localized())
                }
            }
        }
    }
}

/// 错题详情页 toolbar(Edit + Quick Review + AI 菜单)
/// Mistake detail page toolbar (Edit + Quick Review + AI menu).
struct MistakeDetailToolbar: ToolbarContent {
    @Environment(RepositoryContainer.self) private var container
    /// 当前错题的实时版本
    /// Live copy of the current mistake.
    let liveMistake: MistakeNote
    /// LLM 是否已配置(影响 AI 按钮着色)
    /// Whether the LLM is configured (drives the AI button's tint).
    let isLLMConfigured: Bool
    /// Edit 回调
    /// Edit callback.
    let onEdit: () -> Void
    /// Quick Review 回调
    /// Quick review callback.
    let onQuickReview: () -> Void
    /// AI 解析回调
    /// AI analysis callback.
    let onAIAnalysis: () -> Void
    /// AI 同类题回调
    /// AI similar-question callback.
    let onAISimilarQuestion: () -> Void
    /// 错题辩论回调
    /// Mistake debate callback.
    let onAIDebate: () -> Void

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
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: onAIAnalysis) {
                        Label("AI 解析错因".localized(), systemImage: "sparkles")
                    }
                    Button(action: onAISimilarQuestion) {
                        Label("AI 相似题组卷".localized(), systemImage: "doc.badge.gearshape")
                    }
                    Button(action: onAIDebate) {
                        Label("错题辩论".localized(), systemImage: "person.2.wave.2.fill")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("AI".localized())
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.teal.opacity(isLLMConfigured ? 0.18 : 0.08))
                    )
                    .foregroundColor(isLLMConfigured ? .teal : .secondary)
                }
                .accessibilityLabel("AI Analysis".localized())
            }
        }
    }
}
