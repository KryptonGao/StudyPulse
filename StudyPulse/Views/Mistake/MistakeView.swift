//
//  MistakeView.swift
//  StudyPulse
//
//  错题主页:今日复习主卡 → 工具列 → 弱点 → 科目 → 最近新增。
//  搜索时收起为平铺的匹配结果。
//
//  Mistake home: today's review hero → tool row → weak spots → subjects →
//  recent additions. Searching collapses to a flat list of matches.
//

import SwiftUI
import UniformTypeIdentifiers

/// 错题主页(挂在主 tab 上),驱动 `MistakeViewModel`。
/// Mistake home screen (mounted on the main tab), drives `MistakeViewModel`.
struct MistakeView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// 主 ViewModel(过滤 / 分组 / SRS / 搜索)
    /// Main view model (filter / grouping / SRS / search).
    @State private var viewModel: MistakeViewModel
    /// Knowledge-gap scan VM. The local scan is immediate; AI enhancement is
    /// started once per mistake-set fingerprint.
    @State private var knowledgeFaultViewModel: KnowledgeFaultLineViewModel
    /// 是否显示 AI Quiz setup sheet
    /// Whether the AI Quiz setup sheet is showing.
    @State private var showingAIQuizSetup = false

    init(container: RepositoryContainer) {
        _viewModel = State(initialValue: MistakeViewModel.makeDefault(container: container))
        _knowledgeFaultViewModel = State(initialValue: KnowledgeFaultLineViewModel.makeDefault(container: container))
    }

    // MARK: - Empty State / 空态

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
                "No Mistakes".localized(),
                systemImage: "exclamationmark.triangle",
                description: Text("Tap '+' to add a new mistake note.".localized())
            )
            Spacer()
        }
    }

    // MARK: - List Content / 列表内容

    private var isSearching: Bool { !viewModel.searchText.isEmpty }

    private var allTags: [String] { MistakeFilter.allTags(container.mistakeRepo.filteredMistakeSets) }

    private func startReview(_ filter: FlashcardFilter) {
        viewModel.flashcardFilter = filter
        viewModel.showingFlashcards = true
    }

    @ViewBuilder
    private var listView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.section) {
                PhaseBar()
                if isSearching {
                    MistakeRecentList(
                        title: "Search Results".localized(),
                        trailing: String(format: "mistake.v2.search.count".localized(), viewModel.searchResults.count),
                        mistakes: viewModel.searchResults
                    )
                    if viewModel.searchResults.isEmpty {
                        ContentUnavailableView.search(text: viewModel.searchText)
                    }
                } else {
                    browseContent
                }
            }
            .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
            .padding(.vertical)
            .frame(maxWidth: .infinity)
            .adaptiveMaxWidth(900)
        }
    }

    @ViewBuilder
    private var browseContent: some View {
        MistakeReviewHeroCard(
            breakdown: viewModel.review,
            dueTags: viewModel.topTagsDue(),
            onStart: startReview
        )

        MistakeToolsRow(tools: [
            .init(id: "quiz", title: "AI Quiz".localized(), icon: "sparkles.rectangle.stack", tint: .purple) { showingAIQuizSetup = true },
            .init(id: "tags", title: "Tag Graph".localized(), icon: "circle.hexagongrid", tint: .teal, enabled: !allTags.isEmpty) { viewModel.showingTagGraph = true },
            .init(id: "map", title: "Auto Mind Map".localized(), icon: "arrow.triangle.branch", tint: .green) { viewModel.showingAutoMindMap = true },
            .init(id: "pdf", title: "Export PDF".localized(), icon: "square.and.arrow.up", tint: .indigo) { viewModel.showingPDFExportSheet = true }
        ])

        MistakeWeakSpotsRow(
            faultLine: knowledgeFaultViewModel.repeatedFaultLines.first,
            pattern: viewModel.patternSummaries.first,
            patterns: viewModel.patternSummaries,
            container: container
        )

        MistakeSubjectList(
            summaries: viewModel.subjectSummaries,
            mistakesBySubject: viewModel.groups.bySubject,
            onShowTags: allTags.isEmpty ? nil : { viewModel.showingTagGraph = true }
        )

        if !allTags.isEmpty {
            MistakeTagSectionView(
                tags: allTags,
                searchText: $viewModel.searchText,
                onShowTagGraph: { viewModel.showingTagGraph = true }
            )
        }

        MistakeRecentList(
            title: "mistake.v2.zone.recent".localized(),
            trailing: String(format: "mistake.v2.recent.all".localized(), viewModel.groups.totalCount),
            mistakes: viewModel.recentMistakes
        )
    }

    // MARK: - Sheets & Covers / Sheet & Cover

    @ViewBuilder
    private var sheetsAndCovers: some View {
        // 这里用 Color.clear 挂所有 sheet / fileExporter,
        // 真正显示由 viewModel 里的多个 bool 决定。
        // A Color.clear that hosts every sheet / fileExporter; visibility
        // is driven by the viewModel's booleans.
        Color.clear
            // 新建错题 sheet
            // New mistake sheet.
            .sheet(isPresented: $viewModel.showingNewMistakeSet) {
                NewMistakeSetView(container: container)
                    .adaptiveSheet()
            }
            // PDF 导出选项 sheet
            // PDF export options sheet.
            .sheet(isPresented: $viewModel.showingPDFExportSheet) {
                MistakePDFExportSheet { options in
                    viewModel.handlePDFExport(options: options)
                }
                .adaptiveSheet()
            }
            // 真正的 PDF 生成进度页(由 viewModel 准备好的 snapshot 驱动)
            // Actual PDF generation progress page (driven by the snapshot
            // prepared by the viewModel).
            .sheet(item: $viewModel.pendingPDFSnapshot) { snapshot in
                MistakePDFGenerationView(
                    snapshot: snapshot,
                    onCompleted: { data in
                        viewModel.presentPDFExportSheet(data: data)
                    },
                    onError: { message in
                        viewModel.pdfErrorMessage = message
                    }
                )
                .interactiveDismissDisabled(true)
            }
            // 导出失败 alert
            // Export-failed alert.
            .alert("Export Failed".localized(), isPresented: $viewModel.showingExportError) {
                Button("OK".localized()) { viewModel.pdfErrorMessage = nil }
            } message: {
                Text(viewModel.pdfErrorMessage ?? "")
            }
            // Save-to-Files 弹层(fileExporter)
            // Save-to-Files panel (fileExporter).
            .fileExporter(
                isPresented: $viewModel.isExportingPDF,
                document: viewModel.pdfDocument,
                contentType: .pdf,
                defaultFilename: viewModel.pdfDocument?.fileName
            ) { result in
                viewModel.handleExportResult(result)
            }
    }

    @ViewBuilder
    private var fullScreenCovers: some View {
        // 全屏 cover 集合(FlashcardStudyView / TagGraphView)
        // Full-screen cover collection (FlashcardStudyView / TagGraphView).
        Color.clear
            // 闪卡学习:全屏,点左上 x 关闭
            // Flashcard study: full screen, tap top-left x to close.
            .fullScreenCover(isPresented: $viewModel.showingFlashcards) {
                NavigationStack {
                    FlashcardStudyView(container: container, filter: viewModel.flashcardFilter)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button {
                                    viewModel.showingFlashcards = false
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .accessibilityLabel("Close".localized())
                            }
                        }
                }
            }
            // 标签图谱:点节点 → 把 #tag 写回 searchText,然后关闭
            // Tag graph: tapping a node writes "#tag" back to searchText and closes.
            .fullScreenCover(isPresented: $viewModel.showingTagGraph) {
                TagGraphView(
                    mistakes: container.mistakeRepo.filteredMistakeSets,
                    onSelectTag: { tag in
                        viewModel.searchText = "#\(tag)"
                        viewModel.showingTagGraph = false
                    }
                )
            }
            // 智能思维导图:全屏
            // Auto Mind Map: full screen cover.
            .fullScreenCover(isPresented: $viewModel.showingAutoMindMap) {
                AutoMindMapView(
                    mistakes: container.mistakeRepo.filteredMistakeSets,
                    contextTitle: "My Mistakes".localized()
                )
                .environment(container)
            }
    }


    // MARK: - Body / 主体

    var body: some View {
        TwoPane(placeholderTitle: "mistake.v2.pane.placeholder".localized(), placeholderIcon: "exclamationmark.triangle") {
            content
        }
    }

    private var content: some View {
        NavigationStack {
            ZStack {
                // 主体内容:无错题时显示空态,否则显示 listView
                // Main content: empty state when no mistakes, otherwise listView.
                Group {
                    if container.mistakeRepo.filteredMistakeSets.isEmpty {
                        emptyView
                    } else {
                        listView
                    }
                }

                // sheets / fullScreenCover 用 0x0 的隐藏容器挂在 ZStack 里,
                // 这样它们不会影响布局但仍受 navigationStack 控制
                // Sheets / fullScreenCovers are hosted in 0x0 hidden containers
                // inside the ZStack so they don't affect layout but are still
                // controlled by the navigation stack.
                sheetsAndCovers.frame(width: 0, height: 0).hidden()
                fullScreenCovers.frame(width: 0, height: 0).hidden()
            }
            // iOS 26+ 上让 nav bar 背景透明
            // On iOS 26+ make the nav bar background transparent.
            .containerBackground(.clear, for: .navigation)
            .debugModeContainer()
            .debugLayoutBoundsAuto()
            .navigationTitle("Mistakes".localized())
            .navigationBarTitleDisplayMode(.large)
            // 搜索栏:同时影响"subjectsList"标题 + 学科列表过滤
            // Search bar: drives both the "subjectsList" header and
            // the subject list filtering.
            .searchable(text: $viewModel.searchText, prompt: "Search subjects or mistakes...".localized())
            .onAppear {
                viewModel.recompute()
                knowledgeFaultViewModel.recompute()
            }
            .onChange(of: viewModel.searchText) { _, _ in viewModel.recompute() }
            .onChange(of: container.mistakeRepo.filteredMistakeSets) { _, _ in
                viewModel.recompute()
                knowledgeFaultViewModel.recompute()
            }
            .toolbar {
                // 导航栏只留主动作:新建错题;其余工具都在页面里可见
                // The nav bar keeps only the primary action; every tool is visible on the page.
                ToolbarItem(placement: .topBarTrailing) {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        NavigationLink {
                            NewMistakeSetView(container: container, usesInternalNavigationStack: false)
                                .environment(container)
                                .adaptiveSheet()
                        } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New Mistake".localized())
                    } else {
                        Button { viewModel.showingNewMistakeSet = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("New Mistake".localized())
                    }
                }
            }
            .background(Color(.systemGroupedBackground).opacity(DesignToken.Opacity.rootBackground))
        }
        .sheet(isPresented: $showingAIQuizSetup) {
            AIQuizSetupView()
                .environment(container)
                .interactiveDismissDisabled(true)
                .adaptiveSheet()
        }
    }
}
