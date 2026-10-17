//
//  MistakeViewModel.swift
//  StudyPulse
//
//  Created by Antigravity on 2026/7/12.
//
//  错题列表页 ViewModel。负责按搜索词分组 + SRS 总览 + PDF 导出流。
//  Mistake-list page VM. Search grouping, SRS overview, PDF export flow.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class MistakeViewModel {
    // MARK: - 依赖项 / Dependencies
    private let container: RepositoryContainer
    @ObservationIgnored private var patternStateObservationTask: Task<Void, Never>?

    // MARK: - 输入 & 界面状态 / Input & UI states
    /// 顶部搜索框的当前文本 / Current search field text.
    var searchText: String = ""
    /// 是否显示"新增错题"弹窗 / Show the "new mistake" sheet?
    var showingNewMistakeSet = false
    /// 是否显示闪卡学习页 / Show flashcard study page?
    var showingFlashcards = false
    /// 闪卡页的筛选器 / Flashcard filter.
    var flashcardFilter: FlashcardFilter = .dueQueue
    /// 是否显示标签关系图 sheet / Show tag-graph sheet?
    var showingTagGraph = false
    /// 是否显示智能思维导图 sheet / Show Auto Mind Map sheet?
    var showingAutoMindMap = false

    // MARK: - PDF 导出状态 / PDF export state
    var showingPDFExportSheet = false
    var pendingPDFSnapshot: MistakePDFSnapshot?
    var isExportingPDF = false
    var pdfDocument: MistakePDFDocument?
    var pdfErrorMessage: String? {
        didSet {
            if pdfErrorMessage != nil {
                // 任意错误都会自动打开错误 alert / Auto-open alert on error.
                showingExportError = true
            }
        }
    }
    var showingExportError = false

    // MARK: - 输出状态 / Output states
    /// 当前过滤 + 搜索后的分组结果(按科目分桶)
    /// Filtered + searched group result (bucketed by subject).
    private(set) var groups: MistakeGroups = .empty
    /// SRS 总览 / SRS overview.
    private(set) var srsOverview: SRSOverview = .empty
    private(set) var patternSummaries: [MistakePatternSummary] = []
    /// 今日复习分解 / Today's review breakdown.
    private(set) var review: MistakeReviewBreakdown = .empty
    /// 科目汇总(到期多的在前) / Subject summaries (most due first).
    private(set) var subjectSummaries: [MistakeSubjectSummary] = []
    /// 最近新增 / Recently added.
    private(set) var recentMistakes: [MistakeNote] = []
    /// 搜索结果(平铺,按日期降序) / Flat search results, newest first.
    private(set) var searchResults: [MistakeNote] = []

    // MARK: - 初始化 / Initialization
    init(container: RepositoryContainer) {
        self.container = container
        patternStateObservationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .mistakePatternStateDidChange) {
                guard !Task.isCancelled else { return }
                self?.recompute()
            }
        }
    }

    /// 工厂方法 / Factory.
    static func makeDefault(container: RepositoryContainer) -> MistakeViewModel {
        MistakeViewModel(container: container)
    }

    // MARK: - 业务逻辑 / Business logic
    /// 集中重算 `groups` + `srsOverview` / Recompute groups & srsOverview.
    func recompute() {
        let filteredMistakes = container.mistakeRepo.filteredMistakeSets
        groups = MistakeFilter.group(
            mistakes: filteredMistakes,
            searchText: searchText
        )
        srsOverview = SRSAlgorithm.overview(from: filteredMistakes)
        review = MistakeHomeEngine.review(mistakes: filteredMistakes)
        subjectSummaries = MistakeHomeEngine.subjectSummaries(mistakes: filteredMistakes)
        recentMistakes = MistakeHomeEngine.recent(mistakes: filteredMistakes, limit: 4)
        searchResults = groups.filteredSubjects
            .flatMap { groups.bySubject[$0] ?? [] }
            .sorted { $0.date > $1.date }
        let parsed = MistakeFilter.parseSearchQuery(searchText)
        let patternMistakes = (parsed.tags.isEmpty && parsed.text.isEmpty)
            ? filteredMistakes
            : filteredMistakes.filter { MistakeFilter.matches($0, parsed: parsed) }
        patternSummaries = MistakePatternEngine.summaries(
            from: patternMistakes,
            userStates: MistakePatternResolutionStore.shared.states
        )
    }

    /// 单科目内的搜索(代理到 Service) / Per-subject search (delegated).
    func searchInSubject(_ mistakes: [MistakeNote]) -> [MistakeNote] {
        MistakeFilter.searchInSubject(mistakes, searchText: searchText)
    }

    /// 复习建议(代理到 Service) / Review suggestions (delegated).
    func suggestedForReview(_ mistakes: [MistakeNote]) -> [MistakeNote] {
        MistakeFilter.suggestedForReview(mistakes)
    }

    /// 各标签下"到期可复习"的错题计数(按数量降序)
    /// Per-tag counts of "due for review" (descending).
    func topTagsDue() -> [TagDueEntry] {
        let due = SRSAlgorithm.dueMistakes(from: container.mistakeRepo.mistakeSets)
        let tags = MistakeFilter.allTags(container.mistakeRepo.filteredMistakeSets)
        var entries: [TagDueEntry] = []
        for tag in tags {
            let count = MistakeFilter.tagged(due, tag: tag).count
            if count > 0 {
                entries.append(TagDueEntry(tag: tag, count: count))
            }
        }
        return entries.sorted { $0.count > $1.count }
    }

    /// 处理 PDF 导出:先尝试生成 snapshot,失败时记录错误
    /// Handle PDF export: try to build the snapshot, log error on failure.
    func handlePDFExport(options: MistakeExportOptions) {
        guard let snapshot = MistakePDFSnapshot.make(
            from: container,
            selection: options.selection,
            includeImages: options.includeImages
        ) else {
            pdfErrorMessage = "No mistakes match the current selection.".localized()
            return
        }
        pendingPDFSnapshot = snapshot
    }

    /// 准备好 PDF 文档并延迟一帧后打开分享 sheet
    /// Prepare the PDF doc and open the share sheet after a 1-frame delay.
    func presentPDFExportSheet(data: Data) {
        let fileName = "StudyPulse_Mistakes_\(DateFormatters.fileTimestamp.string(from: Date())).pdf"
        pdfDocument = MistakePDFDocument(data: data, fileName: fileName)
        // 50ms 延迟:等 SwiftUI 绑定到 pdfDocument 完成后再开 sheet
        // 50ms delay: let SwiftUI finish binding before opening the sheet.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self.isExportingPDF = true
        }
    }

    /// 取出某科目下的错题(SubjectMistakesView 用)
    /// Return mistakes under a subject (used by SubjectMistakesView).
    func viewModelSubjectMistakes(subject: String) -> [MistakeNote] {
        groups.bySubject[subject] ?? []
    }

    /// 记录导出 / 分享结果(成功 / 失败)
    /// Log the export / share result.
    func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Log.record(.info, category: "Export", message: "错题 PDF 分享成功 / Mistake PDF shared: url=\(url.path)")
        case .failure(let error):
            Log.record(.error, category: "Export", message: "错题 PDF 分享失败 / Mistake PDF share failed: \(error.localizedDescription)")
        }
        // 100ms 延迟:让分享 sheet 关闭动画结束后再清掉 pdfDocument
        // 100ms delay: wait for share-sheet close animation to finish.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self.pdfDocument = nil
        }
    }
}

private extension MistakeGroups {
    /// 空分组占位(初始值) / Empty-group placeholder (initial value).
    static let empty = MistakeGroups(
        bySubject: [:],
        sortedSubjects: [],
        filteredSubjects: [],
        totalCount: 0
    )
}
