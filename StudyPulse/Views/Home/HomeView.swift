//
//  HomeView.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/3/21.
//
//  主页(Dashboard)。固定五区,自上而下回答「现在做什么 → 今天有什么 → 进展如何 → 身心如何 → 长期成长」:
//  1. 头部 + 「现在」主卡 + 快捷动作坞(`HomeHeaderSection` / `HomeNowCard` / `QuickActionsCard`)
//  2. 今日(`HomeTodaySection`:计划清单 / 闪卡 / 待登记成绩 / 考试倒计时)
//  3. 进展(`HomeProgressSection`:KPI + 分段图表 + 学习建议)
//  4. 身心(`HomeBodyMindSection`:恢复分 / 指标 / 一键心情 / 最佳学习窗口)
//  5. 成长(`HomeGrowthSection`:植物 + 迷你热力图)
//  底部悬浮 `HomeAskPanel`(AI 提问条)。各区块内的子模块仍受 `HomeLayoutPreference` 开关控制,区块顺序固定。
//  Home dashboard with five fixed zones, top to bottom: "do now → today → progress → body & mind →
//  growth", plus a floating Ask bar. Sub-modules inside each zone are still gated by the
//  `HomeLayoutPreference` toggles; the zone order itself is fixed.
//
//  架构 / Architecture:
//  - HomeViewModel: 派生数据 / derived data
//  - HomeUIState:   临时 UI 状态(分阶段渲染 / modal / 报告导出)/ ephemeral UI state
//  - HomeRoute:     类型化导航目标,统一在此注册 destination / typed navigation targets registered here
//

import SwiftUI
import UIKit

// MARK: - 主体 / Main view

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.selectAppTab) private var selectAppTab
    @Environment(RepositoryContainer.self) private var container
    @State private var viewModel: HomeViewModel
    @Environment(HealthKitManager.self) private var hrvManager: HealthKitManager
    @Environment(AchievementManager.self) private var achievementManager

    /// UI 临时状态聚合(分阶段渲染 / 模态 / 报告导出)。详见 `HomeUIState`。
    @State private var uiState = HomeUIState()
    /// 类型化导航栈 / Typed navigation path.
    @State private var path: [HomeRoute] = []
    /// 「现在」主卡与「今日」清单共享的候选下标 / Candidate index shared by the Now hero and the Today list.
    @State private var nowIndex = 0

    // MARK: - Init

    init(container: RepositoryContainer) {
        _viewModel = State(initialValue: HomeViewModel.makeDefault(container: container))
    }

    // MARK: - Layout

    private var isRegularWidth: Bool {
        sizeClass == .regular || isIPad
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .adaptiveMaxWidth(isRegularWidth ? 1100 : 720)
                    .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground).opacity(DesignToken.Opacity.rootBackground))
            .containerBackground(.clear, for: .navigation)
            .safeAreaInset(edge: .bottom, spacing: 0) { askBarSpacer }
            .overlay(alignment: .bottom) { askPanel }
            .debugModeContainer()
            .debugLayoutBoundsAuto()
            .llmDebugHomeButton()
            .navigationTitle("")
            .navigationDestination(for: HomeRoute.self) { route in
                destination(for: route)
            }
            .toolbar {
                // 设置入口:不再只藏在头像里
                // Settings entry: no longer hidden behind the avatar only.
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel("Settings".localized())
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        uiState.showingAIMode = true
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel("aiMode.entry.label".localized())
                }
                ToolbarItem(placement: .topBarTrailing) {
                    shareMenu
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .modifier(HomeCoversAndSheets(uiState: $uiState, container: container, generateReport: generateReport))
            .alert("Report export failed".localized(), isPresented: alertBinding) {
                Button("OK".localized(), role: .cancel) { }
            } message: {
                Text(uiState.reportErrorMessage ?? "")
            }
            .recomputeOnAppear(viewModel: viewModel)
            .recomputeOnGradesChange(viewModel: viewModel, grades: container.gradeRepo.grades)
            .recomputeOnExamsChange(viewModel: viewModel, examSets: container.examRepo.filteredExamSets)
            .recomputeOnMistakesChange(viewModel: viewModel, mistakeSets: container.mistakeRepo.mistakeSets)
            .recomputeOnTasksChange(viewModel: viewModel, taskItems: container.taskRepo.filteredTaskItems)
            .recomputeOnRoutinesChange(viewModel: viewModel, routines: container.routineRepo.routines)
            .recomputeOnRoutineInstancesChange(viewModel: viewModel, instances: container.routineInstanceRepo.allInstances)
            .recomputeOnHRVChange(viewModel: viewModel, readiness: hrvManager.readiness)
            .recomputeOnBodyStatusChange(
                viewModel: viewModel,
                bodyStatus: hrvManager.bodyStatus,
                healthHistory: hrvManager.dailyHealthHistory
            )
            .overlay {
                if uiState.isRenderingReport {
                    ZStack {
                        Color.black.opacity(0.15)
                        ProgressView()
                            .scaleEffect(1.4)
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .transition(.opacity)
                    .zIndex(99)
                }
            }
        }
        .task {
            // 分三帧渲染:头部 + 主卡 → 今日 / 进展 → 身心 / 成长(含 Charts)
            try? await Task.sleep(nanoseconds: 50_000_000)
            uiState.renderPhase = 1
            try? await Task.sleep(nanoseconds: 50_000_000)
            uiState.renderPhase = 2
        }
    }

    /// 错误 alert 的可逆绑定(缩短表达式,避免类型检查超时)
    private var alertBinding: Binding<Bool> {
        Binding(
            get: { uiState.reportErrorMessage != nil },
            set: { if !$0 { uiState.reportErrorMessage = nil } }
        )
    }

    // MARK: - Zones

    @ViewBuilder
    private var content: some View {
        let layout = HomeLayoutPreference.load()
        let spacing = DesignToken.Spacing.cardSpacing
        LazyVStack(spacing: spacing) {
            HomeHeaderSection(
                recoveryScore: viewModel.recoveryScore,
                showsQuote: layout.isEnabled(.dailyQuote)
            )
            if uiState.renderPhase >= 1 {
                if layout.isEnabled(.dailyPlan) {
                    HomeNowCard(
                        viewModel: viewModel,
                        candidateIndex: $nowIndex,
                        showsRings: layout.isEnabled(.streakProgress),
                        onOpenItem: openPlanItem
                    )
                }
                if layout.isEnabled(.quickActions) {
                    QuickActionsCard()
                }
            }
            if uiState.renderPhase >= 2 {
                zones(layout: layout)
            }
        }
    }

    @ViewBuilder
    private func zones(layout: HomeLayoutPreference) -> some View {
        let spacing = DesignToken.Spacing.cardSpacing
        let today = HomeTodaySection(
            viewModel: viewModel,
            options: HomeTodayOptions(
                showsPlan: layout.isEnabled(.dailyPlan),
                showsFlashcards: layout.isEnabled(.flashcardReview),
                showsUnregisteredBanner: layout.isEnabled(.unregisteredExamsReminder),
                showsExams: layout.isEnabled(.upcomingExams),
                showsSimulator: layout.isEnabled(.examRoleSimulator),
                showsReversePlanner: layout.isEnabled(.examReversePlanner)
            ),
            candidateIndex: nowIndex,
            onOpenItem: openPlanItem,
            onStartFlashcards: { uiState.showingFlashcards = true },
            onOpenSimulator: { uiState.showingExamRoleSimulator = true },
            onOpenReversePlanner: { uiState.showingExamReversePlanner = true }
        )
        let progress = HomeProgressSection(
            viewModel: viewModel,
            options: HomeProgressOptions(
                showsWeeklyFocus: layout.isEnabled(.weeklyFocus),
                showsSubjects: layout.isEnabled(.subjectSnapshot),
                showsRecentGrades: layout.isEnabled(.recentGrades),
                showsSuggestion: layout.isEnabled(.studySuggestions)
            )
        )
        let bodyMind = HomeBodyMindSection(
            viewModel: viewModel,
            options: HomeBodyMindOptions(
                showsRecovery: layout.isEnabled(.hrvStatus),
                showsDiary: layout.isEnabled(.diary),
                showsHabit: layout.isEnabled(.habitInsight)
            )
        )
        let growth = HomeGrowthSection(
            options: HomeGrowthOptions(
                showsPlant: layout.isEnabled(.plant),
                showsHeatmap: layout.isEnabled(.learningHeatmap)
            )
        )

        if isRegularWidth {
            // iPad:今日 | 进展 并排,身心 | 成长 并排由 Grid 自适应;成长含 40 周热力图,独占整行
            // iPad: Today | Progress side by side; Body & Mind full row; Growth (40-week heatmap) full row.
            Grid(alignment: .top, horizontalSpacing: spacing, verticalSpacing: spacing) {
                GridRow(alignment: .top) {
                    today
                    progress
                }
                GridRow {
                    bodyMind.gridCellColumns(2)
                }
                GridRow {
                    growth.gridCellColumns(2)
                }
            }
        } else {
            today
            progress
            bodyMind
            growth
        }
    }

    /// 给收起态提问条预留的底部空间(面板本身以 overlay 呈现,展开时不推动内容)。
    /// Bottom space reserved for the collapsed ask bar (the panel itself is an overlay, so expanding never pushes content).
    @ViewBuilder
    private var askBarSpacer: some View {
        if HomeLayoutPreference.load().isEnabled(.homeAsk) {
            Color.clear
                .frame(height: HomeAskPanel.collapsedHeight + 8 + 6)
        }
    }

    @ViewBuilder
    private var askPanel: some View {
        if HomeLayoutPreference.load().isEnabled(.homeAsk) {
            HomeAskPanel(container: container)
                .frame(maxWidth: isRegularWidth ? 560 : .infinity)
                .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
                .padding(.bottom, 6)
        }
    }

    // MARK: - Navigation

    @ViewBuilder
    private func destination(for route: HomeRoute) -> some View {
        switch route {
        case .diary:
            DiaryView()
                .navigationBarTitleDisplayMode(.inline)
        case .plant:
            PlantDetailView()
        case .achievements:
            AchievementsView()
        case .bodyMindDetail:
            HomeBodyMindDetailView(viewModel: viewModel) {
                uiState.showingFlashcards = true
            }
        case .exam(let id):
            ExamDetailView(examId: id)
        case .task(let id):
            if let task = container.taskRepo.taskItems.first(where: { $0.id == id }) {
                TaskDetailView(task: task)
            }
        case .mistake(let id):
            if let note = container.mistakeRepo.mistakeSets.first(where: { $0.id == id }) {
                MistakeSetDetailView(mistakeSet: note)
            }
        }
    }

    /// 计划项点击路由:有明确实体的推入详情,SRS 进闪卡,例程按类型分流。
    /// Plan-item routing: entities push their detail, SRS opens flashcards, routines branch by type.
    private func openPlanItem(_ item: DailyPlanItem) {
        switch item.sourceRef {
        case .exam(let id): path.append(.exam(id))
        case .task(let id): path.append(.task(id))
        case .mistake(let id): path.append(.mistake(id))
        case .routineInstance, .routineTemplate:
            if item.kind == .srsReview {
                uiState.showingFlashcards = true
            } else {
                selectAppTab(.todo)
            }
        case .none:
            switch item.kind {
            case .srsReview: uiState.showingFlashcards = true
            case .recovery: path.append(.bodyMindDetail)
            default: break
            }
        }
    }

    // MARK: - 分享 / Share

    /// 仍支持单卡分享的卡片(自带完整外观、不含交互控件)。
    /// Cards that still support single-card sharing (self-contained, no interactive controls).
    private static let shareableTypes: [HomeCardType] = [
        .weeklyFocus, .subjectSnapshot, .learningHeatmap, .plant, .hrvStatus,
    ]

    private func hasVisibleContent(_ type: HomeCardType) -> Bool {
        switch type {
        case .weeklyFocus: return viewModel.weeklyFocus.totalMinutes + viewModel.weeklyFocus.previousTotalMinutes > 0
        case .subjectSnapshot: return !viewModel.subjectSnapshots.isEmpty
        case .plant:
            // 植物有两个开关:主页布局(.plant)+ 外观设置(plantCardEnabled)。
            // 分享菜单与页面所见一致,两者都开才提供单卡分享。
            // Plant has two switches: home layout (.plant) and Appearance (plantCardEnabled);
            // the share menu mirrors the page, so both must be on.
            return HomeLayoutPreference.load().isEnabled(.plant)
                && container.envManager.preferences.plantCardEnabled
        default: return true
        }
    }

    private var shareableCards: [HomeCardType] {
        Self.shareableTypes.filter(hasVisibleContent)
    }

    /// 工具栏分享菜单:整页报告 + 逐卡分享。
    /// Toolbar share menu: full report + per-card share.
    @ViewBuilder
    private var shareMenu: some View {
        Menu {
            Button {
                uiState.showingReportOptions = true
            } label: {
                Label("Share Report".localized(), systemImage: "doc.richtext")
            }
            let cards = shareableCards
            if !cards.isEmpty {
                Divider()
                Section("home.share.card.section".localized()) {
                    ForEach(cards, id: \.self) { type in
                        Button {
                            Task { await renderAndShareSingleCard(type: type) }
                        } label: {
                            Label(cardShareTitle(for: type), systemImage: type.icon)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel("Share Report".localized())
        .disabled(uiState.isExporting || uiState.isRenderingReport)
    }

    // MARK: - 学习报告图片导出

    /// 渲染并分享整页学习报告。
    /// Render the full report and present the share sheet.
    @MainActor
    private func generateReport(options: ReportOptions) {
        uiState.isRenderingReport = true
        Task {
            defer { uiState.isRenderingReport = false }
            let report = StudyReport.make(
                from: container,
                hrvManager: hrvManager,
                start: options.startDate,
                end: options.endDate
            )
            let view = ReportContentView(report: report)
            guard let image = ReportRenderer.render(view) else {
                uiState.reportErrorMessage = "Report export failed".localized()
                Log.record(.error, category: "Export", message: "整页报告渲染失败 / Full report render returned nil")
                return
            }
            // PNG 始终可用；JPEG 编码在外部保存时再处理。
            uiState.reportImage = image
            uiState.singleCardImage = nil
            // 短暂延迟，确保 isRendering 状态先变化（让 ProgressView 闪一下再消失）
            try? await Task.sleep(nanoseconds: 80_000_000)
            uiState.showingShareSheet = true
            Log.record(.info, category: "Export", message: "整页报告已生成 / Full report generated: size=\(Int(image.size.width))x\(Int(image.size.height))")
        }
    }

    /// 渲染并分享单张 Home 卡片。
    /// Render a single Home card and present the share sheet.
    @MainActor
    private func renderAndShareSingleCard(type: HomeCardType) async {
        uiState.isRenderingReport = true
        defer { uiState.isRenderingReport = false }
        let snapshot = StudyReport.make(
                from: container,
            hrvManager: hrvManager,
            start: Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date(),
            end: Date()
        )
        let title = cardShareTitle(for: type)
        // 关键:ImageRenderer 不会自动继承调用方的环境。
        // 各 Home 卡片普遍依赖 environment-injected observable(HealthKitManager / StudyTimerManager /
        // AchievementManager / LLMClient)与 @Environment(RepositoryContainer.self)、
        // @Environment(\.colorScheme) 等,缺一就在 body 评估时崩溃。
        // 这里在渲染前显式注入这些环境对象,确保单卡能成功快照成图片。
        // ImageRenderer doesn't auto-inherit the calling view's environment;
        // cards rely on environment-injected observable / @Environment so we must inject them
        // explicitly before rasterizing — otherwise SwiftUI crashes with
        // "missing as an ancestor of this view" / "No observable object of type X".
        let view = cardShareView(for: type, report: snapshot)
            .environment(container)
            .environment(hrvManager)
            .environment(StudyTimerManager.shared)
            .environment(AchievementManager.shared)
            .environment(LLMClient.shared)
            // 导出模式:卡片内 iOS 26 glassEffect 会变成透明导致发灰、Menu 系统
            // 指示器在 ImageRenderer 里渲染成黄底红禁止占位符,这里注入标记让
            // 卡片走纯色 + 纯文本替身。
            // Export mode: cards replace iOS 26 glassEffect with opaque backgrounds
            // and replace interactive Menu with plain text, so the rendered image
            // doesn't come out gray or with the yellow "prohibited" placeholder.
            .exportMode(true)
        guard let image = ReportRenderer.render(view) else {
            uiState.reportErrorMessage = "Report export failed".localized()
            Log.record(.error, category: "Export", message: "单卡渲染失败 / Single card render returned nil: type=\(type.rawValue)")
            return
        }
        uiState.singleCardImage = image
        uiState.singleCardTitle = title
        uiState.reportImage = nil
        try? await Task.sleep(nanoseconds: 80_000_000)
        uiState.showingShareSheet = true
        Log.record(.info, category: "Export", message: "单卡已生成 / Single card generated: type=\(type.rawValue) size=\(Int(image.size.width))x\(Int(image.size.height))")
    }

    /// 单卡片分享时使用的本地化标题。
    private func cardShareTitle(for type: HomeCardType) -> String {
        switch type {
        case .hrvStatus: return "Recovery Radar".localized()
        case .learningHeatmap: return "Learning Heatmap".localized()
        case .plant: return "Plant".localized()
        case .weeklyFocus: return "home.weeklyFocus.title".localized()
        case .subjectSnapshot: return "home.subjects.title".localized()
        default: return type.displayName
        }
    }

    /// 把单卡渲染成可导出的 SwiftUI 视图。
    /// Wrap the card into a self-contained view ready for rendering.
    @ViewBuilder
    private func cardShareView(for type: HomeCardType, report: StudyReport) -> some View {
        // 报告内容卡片固定 612pt 宽,上下加 padding 让小卡片也居中。
        VStack {
            Group {
                switch type {
                case .hrvStatus: HRVStatusCard()
                case .learningHeatmap: LearningHeatmapView()
                case .plant: PlantHomeCard()
                case .weeklyFocus: WeeklyFocusCard(summary: viewModel.weeklyFocus)
                case .subjectSnapshot:
                    if !viewModel.subjectSnapshots.isEmpty {
                        SubjectSnapshotCard(snapshots: viewModel.subjectSnapshots)
                    } else {
                        Text("No data in this period".localized())
                    }
                default:
                    Text("No data in this period".localized())
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: ReportRenderer.defaultWidth, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Covers & sheets

/// 把全屏模态与 sheet 收进独立 ViewModifier,避免 `body` 链式修饰器过长导致类型推导超时。
/// Groups the full-screen covers and sheets into a ViewModifier so `body`'s modifier chain stays short.
private struct HomeCoversAndSheets: ViewModifier {
    @Binding var uiState: HomeUIState
    let container: RepositoryContainer
    let generateReport: (ReportOptions) -> Void
    @Environment(HealthKitManager.self) private var hrvManager: HealthKitManager

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $uiState.showingAIMode) {
                AIModeRootView(container: container, hrvManager: hrvManager)
                    .environment(container)
                    .environment(hrvManager)
            }
            .fullScreenCover(isPresented: $uiState.showingFlashcards) {
                NavigationStack {
                    FlashcardStudyView(container: container)
                        .environment(container)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button {
                                    uiState.showingFlashcards = false
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .accessibilityLabel("Close".localized())
                            }
                        }
                }
            }
            .fullScreenCover(isPresented: $uiState.showingExamRoleSimulator) {
                ExamRoleSimulatorView(container: container)
                    .environment(container)
            }
            .fullScreenCover(isPresented: $uiState.showingExamReversePlanner) {
                ExamReversePlannerView(container: container)
                    .environment(container)
            }
            .sheet(isPresented: $uiState.showingReportOptions) {
                ReportOptionsSheet { options in
                    generateReport(options)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $uiState.showingShareSheet) {
                if let image = uiState.reportImage {
                    ReportShareSheet(items: [image], subject: "StudyPulse Report")
                } else if let image = uiState.singleCardImage {
                    ReportShareSheet(items: [image], subject: uiState.singleCardTitle)
                }
            }
    }
}

// MARK: - Previews
#Preview {
    HomeView(container: RepositoryContainer())
        .environment(RepositoryContainer())
        .environment(HealthKitManager.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    HomeView(container: RepositoryContainer())
        .environment(RepositoryContainer())
        .environment(HealthKitManager.shared)
        .preferredColorScheme(.dark)
}
