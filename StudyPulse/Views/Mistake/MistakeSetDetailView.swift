//
//  MistakeSetDetailView.swift
//  StudyPulse
//
//  错题详情页:展示 + AI 入口(快速复习 / AI 解析 / 深入探讨 / 同类题)。
//  顶部 MasteryCurveView 展示掌握度曲线,下方是字段列表 + 题图。
//
//  Mistake detail page: display + AI entry points (quick review / AI
//  analysis / deep discussion / similar question).
//  Top of the page is the MasteryCurveView; below it is a field list
//  and the question image(s).
//
//  Phase 3 拆分 (2026-07-14):原 555 行单文件 → orchestrator 留本文件,
//  拆出 2 个独立子文件:
//  - MistakeSetHeaderSection.swift  (MasteryCurve + Details)
//  - MistakeSetContentSection.swift (4 段 Markdown:原题/错因/错解/正解)
//
//  本文件只剩:主 View 编排 + AI 入口(sheets / cover) + ThumbnailImageView / SuggestedMistakeCard 通用组件。
//

import SwiftUI
import UIKit
import SwiftStreamingMarkdown

/// 错题详情页:由 `MistakeView` 推入,集中展示错题字段 + 多个 AI 入口。
/// Mistake detail page: pushed by `MistakeView`, shows the mistake's
/// fields plus a range of AI entry points.
struct MistakeSetDetailView: View {
    /// 传入的错题(以 id 为准从 repo 拿最新数据)
    /// Injected mistake (uses the id to fetch the latest copy from the repo).
    let mistakeSet: MistakeNote
    @Environment(RepositoryContainer.self) private var container
    /// 是否弹出编辑 sheet
    /// Whether to present the edit sheet.
    @State private var showingEditSheet = false
    /// 是否弹出快速复习 sheet
    /// Whether to present the quick-review sheet.
    @State private var showingQuickReview = false
    /// 是否弹出 AI 解析 sheet
    /// Whether to present the AI analysis sheet.
    @State private var showingAIAnalysis = false
    /// 是否弹出 AI 深入讨论 sheet
    /// Whether to present the deep-discussion sheet.
    @State private var showingAIDiscussion = false
    /// 是否弹出 AI 同类题 sheet
    /// Whether to present the similar-question sheet.
    @State private var showingAISimilarQuestion = false
    /// 是否弹出 AI 错题辩论 sheet
    /// Whether to present the AI mistake-debate sheet.
    @State private var showingAIDebate = false
    /// 最近一次成功的 AI 解析(供"深入探讨"sheet 当作 initial assistant 消息)
    /// Most recent successful AI analysis (used as the initial assistant
    /// message in the deep-discussion sheet).
    @State private var lastAIAnalysis: String? = nil
    @State private var correctionPlan: MistakeCorrectionPlan? = nil

    /// 实时从 repo 取最新版本的错题(repo 是单一数据源,避免 caller 拿到旧拷贝)
    /// Live copy of the mistake from the repo (the repo is the single
    /// source of truth, so we don't use a stale injected copy).
    private var liveMistake: MistakeNote {
        container.mistakeRepo.mistakeSets.first(where: { $0.id == mistakeSet.id }) ?? mistakeSet
    }

    var body: some View {
        List {
            // 顶部 header 区块:掌握度曲线 + 错题基本字段
            // Top header block: mastery curve + basic fields.
            MistakeSetHeaderSection(mistake: liveMistake, tintColor: container.envManager.effectiveAccentColor)

            // 主体内容:原题 / 错因 / 错解 / 正解 四段 Markdown
            // Main content: 4 markdown sections (question / reason / wrong / correct).
            MistakeSetContentSection(mistake: liveMistake)

            KnowledgeDepthEntrySection(mistakeID: liveMistake.id, container: container)

            MistakeCorrectionPlanSection(summary: derivedPatternSummary, plan: $correctionPlan)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(liveMistake.title)
        .navigationBarTitleDisplayMode(.inline)
        // iPad / 横屏下限制最大宽度 820pt,避免一行太长
        // On iPad / landscape, cap the max width at 820pt to avoid overly long lines.
        .adaptiveMaxWidth(820)
        .toolbar {
            MistakeDetailToolbar(
                liveMistake: liveMistake,
                isLLMConfigured: container.envManager.llmConfig.isConfigured,
                onEdit: { showingEditSheet = true },
                onQuickReview: { showingQuickReview = true },
                onAIAnalysis: { showingAIAnalysis = true },
                onAISimilarQuestion: { showingAISimilarQuestion = true },
                onAIDebate: { showingAIDebate = true }
            )
        }
        // 编辑 sheet
        // Edit sheet.
        .sheet(isPresented: $showingEditSheet) {
            MistakeDetailEditView(container: container, mistakeSet: liveMistake)
                .adaptiveSheet()
        }
        // AI 解析 sheet:
        // - onInsert: 把 AI 的"正确思路"塞回正解字段(空则替换,否则追加)
        // - onAnalysisComplete: 缓存完整 LLM 输出,供"深入探讨"用
        // - onDiscuss: 关掉当前 sheet,延迟 0.3s 弹出讨论 sheet
        // AI analysis sheet:
        // - onInsert: pushes the AI "correct approach" back into the
        //   correct-solution field (replaces if empty, appends otherwise).
        // - onAnalysisComplete: caches the full LLM output for "deep discussion".
        // - onDiscuss: closes this sheet, then opens the discussion sheet after 0.3s.
        .sheet(isPresented: $showingAIAnalysis) {
            MistakeAIAnalysisSheet(
                subject: liveMistake.subject,
                title: liveMistake.title,
                question: liveMistake.originalQuestion,
                wrongSolution: liveMistake.wrongSolution,
                correctSolution: liveMistake.correctSolution,
                reason: liveMistake.errorReason,
                onInsert: { insight in
                    var updated = liveMistake
                    let trimmed = insight.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        let correctApproach = MistakeAnalysisLLM.parseCorrectApproach(from: trimmed)
                        if !correctApproach.isEmpty {
                            if updated.correctSolution.isEmpty {
                                updated.correctSolution = correctApproach
                            } else {
                                updated.correctSolution += "\n\n---\n\n" + correctApproach
                            }
                        }

                        let errorReason = MistakeAnalysisLLM.parseErrorReason(from: trimmed)
                        if !errorReason.isEmpty {
                            if updated.errorReason.isEmpty {
                                updated.errorReason = errorReason
                            } else {
                                updated.errorReason += "\n\n---\n\n" + errorReason
                            }
                        }

                        let extractedTags = MistakeAnalysisLLM.parseTags(from: trimmed)
                        for tag in extractedTags {
                            if !updated.tags.contains(tag) {
                                updated.tags.append(tag)
                            }
                        }
                        container.mistakeRepo.update(updated)
                    }
                },
                onAnalysisComplete: { fullText in
                    lastAIAnalysis = fullText
                },
                onPatternDecision: { state in
                    MistakePatternResolutionStore.shared.set(state, for: liveMistake.id)
                },
                onDiscuss: { context, lastAnalysis in
                    showingAIAnalysis = false
                    // 0.3s 延迟,避免 sheet 状态机冲突
                    // 0.3s delay to avoid sheet state-machine conflicts.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        showingAIDiscussion = true
                    }
                }
            )
            .adaptiveSheet()
        }
        // "深入探讨" sheet:在 AI 解析之上多轮对话
        // "Deep discussion" sheet: multi-turn chat on top of the AI analysis.
        .sheet(isPresented: $showingAIDiscussion) {
            AIDiscussionSheet(
                title: "AI 解析 · 深入探讨".localized(),
                context: buildMistakeDiscussionContext(),
                initialAssistantMessage: lastAIAnalysis,
                onDismiss: { showingAIDiscussion = false }
            )
            .adaptiveSheet(detents: [.large])
        }
        .sheet(isPresented: $showingAIDebate) {
            MistakeDebateSheet(
                mistake: liveMistake,
                onDismiss: { showingAIDebate = false }
            )
            .environment(container)
            .adaptiveSheet(detents: [.large])
        }
        // AI 同类题 flow
        // AI similar-question flow.
        .sheet(isPresented: $showingAISimilarQuestion) {
            AISimilarQuestionFlowView(originalMistake: liveMistake)
                .environment(container)
                .adaptiveSheet()
        }
        // 快速复习:以全屏 cover 形式弹闪卡
        // Quick review: presents the flashcard flow as a full-screen cover.
        .fullScreenCover(isPresented: $showingQuickReview) {
            NavigationStack {
                FlashcardStudyView(container: container, filter: .single(liveMistake))
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                showingQuickReview = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .accessibilityLabel("Close".localized())
                        }
                    }
            }
        }
        // 每次进入页面记一次曝光(exposureCount 影响 SRS 调度)
        // Record one exposure on appear (exposureCount drives SRS scheduling).
        .onAppear {
            container.mistakeRepo.recordExposure(mistakeSet.id)
            correctionPlan = MistakeCorrectionPlanStore.shared.plan
        }
    }

    private var derivedPatternSummary: MistakePatternSummary? {
        guard let match = MistakePatternEngine.classify(
            liveMistake,
            userState: MistakePatternResolutionStore.shared.states[liveMistake.id]
        ) else { return nil }
        return MistakePatternEngine.summaries(
            from: container.mistakeRepo.filteredMistakeSets,
            userStates: MistakePatternResolutionStore.shared.states
        ).first { $0.pattern == match.pattern }
    }

    private func buildMistakeDiscussionContext() -> String {
        // 把错题打包成 LLM 可读的多行 block:
        // 1. metadata(学科/日期/难度/掌握度/标签/曝光)
        // 2. 四个 markdown 段(原题/错因/错解/正解)
        // 3. 上一次的 AI 解析(只读,显式标记,避免 LLM 重复说一次)
        // Pack the mistake into an LLM-readable multi-line block:
        // 1. metadata (subject / date / difficulty / mastery / tags / exposure)
        // 2. four markdown sections (question / reason / wrong / correct)
        // 3. previous AI analysis (read-only, marked explicitly so the LLM
        //    won't re-derive the same conclusion).
        let m = liveMistake
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        var lines: [String] = []
        lines.append("错题 ID:\(m.id.uuidString)")
        lines.append("学科:\(m.subject.isEmpty ? "(无)" : m.subject)")
        lines.append("标题:\(m.title)")
        lines.append("来源:\(m.source.isEmpty ? "(无)" : m.source)")
        lines.append("日期:\(f.string(from: m.date))")
        lines.append("难度:\(m.difficulty)/5")
        lines.append("掌握度:\(String(format: "%.0f%%", m.masteryScore * 100))")
        lines.append("曝光次数:\(m.exposureCount)")
        if !m.tags.isEmpty {
            lines.append("标签:\(m.tags.joined(separator: ", "))")
        }
        // 内部小函数:只在非空时才把某段拼进 context
        // Local helper: only appends a section if its body is non-empty.
        func block(_ title: String, _ body: String) {
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("")
                lines.append("--- \(title) ---")
                lines.append(body)
            }
        }
        block("原题", m.originalQuestion)
        block("错因", m.errorReason)
        block("错误解法", m.wrongSolution)
        block("正确解法", m.correctSolution)
        if let last = lastAIAnalysis, !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("--- 上一次 AI 解析(只读) ---")
            lines.append(last)
        }
        return lines.joined(separator: "\n")
    }
}

/// 缩略图视图(异步解码 + ImageCache,共享给"原题/错因/错解/正解"四段)
/// Thumbnail view (async decode + ImageCache).
struct ThumbnailImageView: View {
    let data: Data
    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let image = uiImage {
                ZoomableImageView(image: image)
            } else {
                ProgressView()
                    .task {
                        await loadImage()
                    }
            }
        }
    }

    private func loadImage() async {
        if let cached = ImageCache.shared.getImage(data) {
            uiImage = cached
            return
        }
        let task = Task.detached(priority: .userInitiated) {
            ImageCache.thumbnail(from: data, maxDimension: 300)
        }
        let thumbnail = await task.value
        guard let thumb = thumbnail else { return }
        ImageCache.shared.putImage(thumb, data)
        await MainActor.run { uiImage = thumb }
    }
}

// MARK: - Suggested Mistake Card / 建议错题卡
// (SubjectMistakesView.swift 也引用它,所以放在本 orchestrator 里以避免循环引用)

/// 学科下错题二级页里的"建议复习"卡
/// "Suggested for review" card on the per-subject drill-down page.
struct SuggestedMistakeCard: View {
    let mistake: MistakeNote
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var animateIn = false

    var reviewPriority: String {
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()

        if mistake.date > oneWeekAgo {
            return "🔴 High Priority".localized()
        } else if mistake.date < oneMonthAgo {
            return "🟡 Review Soon".localized()
        } else {
            return "🟢 Normal".localized()
        }
    }

    var daysSinceAdded: String {
        let components = Calendar.current.dateComponents([.day], from: mistake.date, to: Date())
        let days = components.day ?? 0
        if days == 0 {
            return "Today".localized()
        } else if days == 1 {
            return "Yesterday".localized()
        } else {
            return "\(days) " + "days ago".localized()
        }
    }

    private var cardWidth: CGFloat {
        sizeClass == .regular ? 220 : 180
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)

                Text(reviewPriority)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Spacer()

                if mistake.difficulty > 0 {
                    HStack(spacing: 1) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= mistake.difficulty ? "star.fill" : "star")
                                .scaledFont(size: 9)
                                .foregroundStyle(i <= mistake.difficulty ? Color.orange : Color.gray.opacity(0.3))
                        }
                    }
                }
            }

            Text(mistake.title)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)

            if !mistake.subject.isEmpty {
                Text(mistake.subject.localized())
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.systemPurple).opacity(0.15))
                    .foregroundColor(Color(.systemPurple))
                    .cornerRadius(4)
            }

            if !mistake.tags.isEmpty {
                TagChipsView(tags: mistake.tags, compact: true, maxVisible: 2)
            }

            if !mistake.originalQuestion.isEmpty {
                Text(mistake.originalQuestion)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text(daysSinceAdded)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(width: cardWidth)
        .cardSkin()
        .opacity(animateIn ? 1 : 0)
        .offset(x: animateIn ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.1)) {
                animateIn = true
            }
        }
    }
}

#Preview {
    let m = MistakeNote(
        title: "二次函数顶点公式",
        subject: "Mathematics",
        originalQuestion: "已知 f(x) = x² - 4x + 3,求顶点坐标。",
        source: "数学课本",
        date: Date(),
        errorReason: "忘记配方",
        wrongSolution: "x = -b/2a = 2",
        correctSolution: "顶点 (2, -1)",
        tags: ["跳步", "计算粗心"]
    )
    NavigationStack {
        MistakeSetDetailView(mistakeSet: m)
    }
    .environment(RepositoryContainer())
}
