//
//  HomeView.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/3/21.
//
//  主页(Dashboard)。负责:
//  - 顶部欢迎区
//  - 主要统计卡(4 个核心指标)
//  - 用户可配置的动态卡片(快捷操作 / 学习建议 / 趋势图 / 即将考试 / 热力图 等)
//  - 学习报告图片导出(整页 + 单卡分享)
//
//  架构:
//  - HomeViewModel: 派生数据(SRS / recent grades / upcoming exams / chart 选科 / 建议生成)
//  - HomeUIState:   主页 UI 临时状态(分阶段渲染 / modal / 报告导出),聚合在 @State
//  - HomeCards/...: 7 个卡片子 View,各自独立文件
//
//

import SwiftUI
import Charts
import UIKit

// MARK: - 主体 / Main view

/// 主页(Dashboard)主视图,渲染顶部欢迎区、4 个核心统计卡与用户可配置的动态卡片。
/// 内部小节:Init / Layout / Body / Dynamic Cards / 学习报告图片导出。
/// Home dashboard root. Renders the welcome header, four core stat cards,
/// and the user-configurable dynamic card list. Internal sub-MARKs cover
/// init, layout, body, dynamic cards, and report export.
struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(RepositoryContainer.self) private var container
    @State private var viewModel: HomeViewModel
    @Environment(HealthKitManager.self) private var hrvManager: HealthKitManager
    @Environment(AchievementManager.self) private var achievementManager

    /// UI 临时状态聚合(分阶段渲染 / 模态 / 报告导出)。详见 `HomeUIState`。
    @State private var uiState = HomeUIState()

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
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                // 外层用 LazyVStack 避免屏外卡片参与布局
                // Use LazyVStack at the outer level so off-screen cards skip layout
                LazyVStack(spacing: 20) {
                    // 顶部欢迎区域（全宽）
                    WelcomeHeaderCard()
                    // 总览 KPI 卡（全宽，4 个带趋势的指标）
                    if uiState.renderPhase >= 1 {
                        OverviewHeroCard(viewModel: viewModel)
                    }

                    if uiState.renderPhase >= 2 {
                        dynamicCards
                    }
                }
                .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(.systemGroupedBackground).opacity(DesignToken.Opacity.rootBackground))
            .containerBackground(.clear, for: .navigation)
            .debugModeContainer()
            .debugLayoutBoundsAuto()
            .llmDebugHomeButton()
            .navigationTitle("")
            .navigationDestination(for: HomeCardType.self) { type in
                // 只有 .diary 走 NavigationLink 推送;其他卡片各自用 sheet
                // self-contained,不需要 destination。
                // Only .diary is pushed via NavigationLink; other cards use
                // their own sheets and don't need a destination.
                switch type {
                case .diary:
                    DiaryView()
                        .navigationBarTitleDisplayMode(.inline)
                default:
                    EmptyView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        uiState.showingReportOptions = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel("Share Report".localized())
                    .disabled(uiState.isExporting)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: Binding(
                get: { uiState.showingFlashcards },
                set: { uiState.showingFlashcards = $0 }
            )) {
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
            .fullScreenCover(isPresented: Binding(
                get: { uiState.showingExamRoleSimulator },
                set: { uiState.showingExamRoleSimulator = $0 }
            )) {
                ExamRoleSimulatorView(container: container)
                    .environment(container)
            }
            .fullScreenCover(isPresented: Binding(
                get: { uiState.showingExamReversePlanner },
                set: { uiState.showingExamReversePlanner = $0 }
            )) {
                ExamReversePlannerView(container: container)
                    .environment(container)
            }
            .sheet(isPresented: Binding(
                get: { uiState.showingReportOptions },
                set: { uiState.showingReportOptions = $0 }
            )) {
                ReportOptionsSheet { options in
                    generateReport(options: options)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: Binding(
                get: { uiState.showingShareSheet },
                set: { uiState.showingShareSheet = $0 }
            )) {
                if let image = uiState.reportImage {
                    ReportShareSheet(items: [image], subject: "StudyPulse Report")
                } else if let image = uiState.singleCardImage {
                    ReportShareSheet(items: [image], subject: uiState.singleCardTitle)
                }
            }
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
            // 分三帧渲染：欢迎区 → 统计卡 → 动态卡片（含 Charts）
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

    // MARK: - Dynamic Cards

    /// 动态渲染可配置卡片：iPhone 单列，iPad 双列网格（全宽卡片独占一行）
    @ViewBuilder
    private var dynamicCards: some View {
        let layout = HomeLayoutPreference.load()
        // 动态排布:隐藏无信息卡片并按紧迫度自动排序;关闭时沿用用户自定义顺序
        // Dynamic layout: hide empty cards and order by urgency; off keeps the user's custom order
        let enabledTypes = layout.dynamicLayoutEnabled
            ? HomeDynamicLayoutEngine.arrange(enabled: layout.enabledTypes, signals: cardSignals)
            : layout.enabledTypes

        if isRegularWidth {
            // iPad: 按 enabledTypes 顺序渲染；全宽卡片独占一行，其他 2 列成行
            iPadDynamicCards(types: enabledTypes)
        } else {
            // iPhone：LazyVStack 包装 ForEach 让屏外卡片跳过布局
            // iPhone: wrap ForEach in LazyVStack so off-screen cards skip layout
            LazyVStack(spacing: 16) {
                ForEach(enabledTypes, id: \.self) { type in
                    cardView(for: type)
                }
            }
        }
    }

    /// 动态排布所需的数据快照 / Data snapshot feeding the dynamic layout engine.
    private var cardSignals: HomeCardSignals {
        var signals = HomeCardSignals()
        // 占位项("今日无事")不算信息 / the "nothing today" placeholder is not information
        signals.dailyPlanCount = viewModel.dailyPlan.filter { $0.kind != .placeholder }.count
        signals.minimalPlanActive = viewModel.minimalPlan.isActive
        signals.dueFlashcards = viewModel.srsOverview.dueCount
        if let next = viewModel.upcomingExams.map(\.examDate).min() {
            signals.nextExamDays = OverviewHeroCard.daysUntil(next)
        }
        signals.unregisteredExamCount = viewModel.unregisteredExams.count
        signals.weeklyFocusHasData = viewModel.weeklyFocus.totalMinutes + viewModel.weeklyFocus.previousTotalMinutes > 0
        signals.subjectSnapshotCount = viewModel.subjectSnapshots.count
        signals.hasActivityHistory = achievementManager.snapshot.logs.contains { $0.totalActivityPoints > 0 }
        signals.currentStreak = achievementManager.currentStreak
        signals.recentGradeCount = viewModel.recentGrades.count
        signals.healthDataAvailable = hrvManager.hrvEnabled || hrvManager.bodyStatusAuthorized
        signals.hasBodyMindData = viewModel.hasBodyMindData
        signals.diaryEnabled = container.envManager.preferences.diaryEnabled
        signals.hasDiaryToday = container.diaryRepo.todayEntry() != nil
        signals.completedSessionCount = container.studySessionRepo.sessions.filter(\.completed).count
        signals.memoryClimateSubjectCount = viewModel.memoryClimate.subjects.count
        signals.plantEnabled = container.envManager.preferences.plantCardEnabled
        signals.hour = Calendar.current.component(.hour, from: Date())
        return signals
    }

    /// iPad 上的卡片布局：把 enabledTypes 切成"块"——全宽卡片独立成块，
    /// 其余按 2 个一组进网格。这样 heatmap 等宽幅卡片可以出现在任何排序位置。
    @ViewBuilder
    private func iPadDynamicCards(types: [HomeCardType]) -> some View {
        let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
        let chunks = makeChunks(from: types)

        LazyVStack(spacing: 16) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                if chunk.count == 1 && chunk[0].isFullWidth {
                    // 全宽卡片：脱离网格
                    cardView(for: chunk[0])
                } else {
                    // 1-2 个普通卡片：进 2 列网格
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(chunk, id: \.self) { type in
                            cardView(for: type)
                        }
                    }
                }
            }
        }
    }

    /// 把 enabledTypes 切成行块：全宽卡片独占一块，普通卡片每 2 个一块。
    private func makeChunks(from types: [HomeCardType]) -> [[HomeCardType]] {
        var chunks: [[HomeCardType]] = []
        var current: [HomeCardType] = []
        for type in types {
            if type.isFullWidth {
                if !current.isEmpty {
                    chunks.append(current)
                    current = []
                }
                chunks.append([type])
            } else {
                current.append(type)
                if current.count == 2 {
                    chunks.append(current)
                    current = []
                }
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    /// 根据卡片类型返回对应视图；数据不足时自动隐藏
    @ViewBuilder
    private func cardView(for type: HomeCardType) -> some View {
        // 每个分支都用 `.contextMenu` 包一层，支持长按分享该卡片。
        switch type {
        case .dailyPlan:
            DailyPlanCard(items: viewModel.dailyPlan)
                .contextMenu { shareCardMenu(for: type) }
        case .minimalPlan:
            // 仅在状态不佳触发压缩计划时显示,避免与 Top-3 重复占位
            // Shown only when the compressed plan is active, to avoid duplicating Top-3.
            if viewModel.minimalPlan.isActive {
                MinimalCompletionPlanCard(result: viewModel.minimalPlan)
                    .contextMenu { shareCardMenu(for: type) }
            }
        case .studyTimer:
            StudyTimerCard()
                .contextMenu { shareCardMenu(for: type) }
        case .hrvStatus:
            HRVStatusCard()
                .contextMenu { shareCardMenu(for: type) }
        case .unregisteredExamsReminder:
            if !viewModel.unregisteredExams.isEmpty {
                UnregisteredExamsReminderCard(unregisteredExams: viewModel.unregisteredExams)
                    .contextMenu { shareCardMenu(for: type) }
            }
        case .flashcardReview:
            if viewModel.srsOverview.dueCount > 0 {
                FlashcardReviewHomeCard(overview: viewModel.srsOverview) {
                    uiState.showingFlashcards = true
                }
                .contextMenu { shareCardMenu(for: type) }
            }
        case .memoryClimate:
            if !viewModel.memoryClimate.subjects.isEmpty {
                MemoryClimateCard(
                    snapshot: viewModel.memoryClimate,
                    history: viewModel.memoryClimateHistory
                ) {
                    uiState.showingFlashcards = true
                }
                .contextMenu { shareCardMenu(for: type) }
            }
        case .quickActions:
            QuickActionsCard()
                .contextMenu { shareCardMenu(for: type) }
        case .studySuggestions:
            StudySuggestionsCard(viewModel: viewModel)
                .contextMenu { shareCardMenu(for: type) }
        case .trendChart:
            if !viewModel.recentGrades.isEmpty {
                TrendChartCard(viewModel: viewModel)
                    .contextMenu { shareCardMenu(for: type) }
            }
        case .upcomingExams:
            if !viewModel.upcomingExams.isEmpty {
                UpcomingExamsCard()
                    .contextMenu { shareCardMenu(for: type) }
            }
        case .examDayReadiness:
            ExamDayReadinessCard(viewModel: viewModel)
                .contextMenu { shareCardMenu(for: type) }
        case .dailyQuote:
            DailyQuoteCard(quote: QuoteProvider.dailyQuote())
                .contextMenu { shareCardMenu(for: type) }
        case .streakProgress:
            StreakHomeCard()
                .contextMenu { shareCardMenu(for: type) }
        case .recentGrades:
            if !viewModel.recentGrades.isEmpty {
                RecentGradesCard()
                    .contextMenu { shareCardMenu(for: type) }
            }
        case .learningHeatmap:
            LearningHeatmapView()
                .contextMenu { shareCardMenu(for: type) }
        case .plant:
            PlantHomeCard()
                .contextMenu { shareCardMenu(for: type) }
        case .homeAsk:
            // HomeAskCard 自带 Button 弹出 sheet,不参与长按分享(不能导出"输入框"图片)
            HomeAskCard()
        case .diary:
            DiaryHomeCard()
                .contextMenu { shareCardMenu(for: type) }
        case .habitInsight:
            HabitInsightCard()
                .contextMenu { shareCardMenu(for: type) }
        case .brainUsage:
            BrainUsageCard()
                .contextMenu { shareCardMenu(for: type) }
        case .examRoleSimulator:
            ExamRoleSimulatorHomeCard {
                uiState.showingExamRoleSimulator = true
            }
        case .examReversePlanner:
            ExamReversePlannerHomeCard {
                uiState.showingExamReversePlanner = true
            }
        case .weeklyFocus:
            if viewModel.weeklyFocus.totalMinutes + viewModel.weeklyFocus.previousTotalMinutes > 0 {
                WeeklyFocusCard(summary: viewModel.weeklyFocus)
                    .contextMenu { shareCardMenu(for: type) }
            }
        case .subjectSnapshot:
            if !viewModel.subjectSnapshots.isEmpty {
                SubjectSnapshotCard(snapshots: viewModel.subjectSnapshots)
                    .contextMenu { shareCardMenu(for: type) }
            }
        case .bodyMindTrend:
            if viewModel.hasBodyMindData {
                BodyMindTrendCard(
                    mood: viewModel.moodSeries,
                    sleep: viewModel.sleepSeries,
                    hrv: viewModel.hrvSeries
                )
                .contextMenu { shareCardMenu(for: type) }
            }
        }
    }

    /// 单卡片长按分享：contextMenu 内显示的按钮。
    @ViewBuilder
    private func shareCardMenu(for type: HomeCardType) -> some View {
        Button {
            Task { await renderAndShareSingleCard(type: type) }
        } label: {
            Label("Share Report".localized(), systemImage: "square.and.arrow.up")
        }
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

    /// 单卡分享时使用的本地化标题。
    private func cardShareTitle(for type: HomeCardType) -> String {
        switch type {
        case .dailyPlan: return "Today's Top 3".localized()
        case .minimalPlan: return "Minimum Viable Plan".localized()
        case .hrvStatus: return "Recovery Radar".localized()
        case .unregisteredExamsReminder: return "Pending Grades".localized()
        case .flashcardReview: return "Flashcard Review".localized()
        case .memoryClimate: return "memory.climate.title".localized()
        case .quickActions: return "Quick Actions".localized()
        case .studyTimer: return "Study Timer".localized()
        case .studySuggestions: return "Study Suggestions".localized()
        case .trendChart: return "Trend Chart".localized()
        case .upcomingExams: return "Upcoming Exams".localized()
        case .examDayReadiness: return "examReadiness.title".localized()
        case .dailyQuote: return "Daily Quote".localized()
        case .streakProgress: return "Streak Progress".localized()
        case .recentGrades: return "Recent Grades".localized()
        case .learningHeatmap: return "Learning Heatmap".localized()
        case .plant: return "Plant".localized()
        case .homeAsk: return "Ask AI".localized()
        case .diary: return "Study Diary".localized()
        case .habitInsight: return "Habit Insight".localized()
        case .brainUsage: return "Brain Usage".localized()
        case .examRoleSimulator: return "考场人格模拟器".localized()
        case .examReversePlanner: return "exam.reverse.planner.title".localized()
        case .weeklyFocus: return "home.weeklyFocus.title".localized()
        case .subjectSnapshot: return "home.subjects.title".localized()
        case .bodyMindTrend: return "home.bodyMind.title".localized()
        }
    }

    /// 把单卡渲染成 PDF 友好的 SwiftUI 视图。
    /// Wrap the home card into a self-contained view ready for rendering.
    @ViewBuilder
    private func cardShareView(for type: HomeCardType, report: StudyReport) -> some View {
        // 报告内容卡片固定 612pt 宽，上下加 padding 让小卡片也居中。
        // 不同卡片自身可能依赖 environment-injected observable / @Bindable，
        // 这里直接复用 HomeView 的环境上下文。
        VStack {
            Group {
                switch type {
                case .dailyPlan: DailyPlanCard(items: viewModel.dailyPlan)
                case .minimalPlan:
                    if viewModel.minimalPlan.isActive { MinimalCompletionPlanCard(result: viewModel.minimalPlan) }
                    else { Text("No data in this period".localized()) }
                case .studyTimer: StudyTimerCard()
                case .hrvStatus: HRVStatusCard()
                case .unregisteredExamsReminder:
                    if !viewModel.unregisteredExams.isEmpty {
                UnregisteredExamsReminderCard(unregisteredExams: viewModel.unregisteredExams)
            } else {
                        Text("No data in this period".localized())
                    }
                case .flashcardReview:
                    if viewModel.srsOverview.dueCount > 0 {
                        FlashcardReviewHomeCard(overview: viewModel.srsOverview) {}
                    } else {
                        Text("No data in this period".localized())
                    }
                case .memoryClimate:
                    if !viewModel.memoryClimate.subjects.isEmpty {
                        MemoryClimateCard(
                            snapshot: viewModel.memoryClimate,
                            history: viewModel.memoryClimateHistory,
                            onStartReview: {}
                        )
                    } else {
                        Text("No data in this period".localized())
                    }
                case .quickActions: QuickActionsCard()
                case .studySuggestions: StudySuggestionsCard(viewModel: viewModel)
                case .trendChart:
                    if !viewModel.recentGrades.isEmpty {
                        TrendChartCard(viewModel: viewModel)
                    } else {
                        Text("No data in this period".localized())
                    }
                case .upcomingExams:
                    if !viewModel.upcomingExams.isEmpty {
                        UpcomingExamsCard()
                    } else {
                        Text("No data in this period".localized())
                    }
                case .examDayReadiness:
                    ExamDayReadinessCard(viewModel: viewModel)
                case .dailyQuote: DailyQuoteCard(quote: QuoteProvider.dailyQuote())
                case .streakProgress: StreakHomeCard()
                case .recentGrades:
                    if !viewModel.recentGrades.isEmpty {
                        RecentGradesCard()
                    } else {
                        Text("No data in this period".localized())
                    }
                case .learningHeatmap:
                    LearningHeatmapView()
                case .plant:
                    PlantHomeCard()
                case .homeAsk:
                    HomeAskCard()
                case .diary:
                    DiaryHomeCard()
                case .habitInsight:
                    HabitInsightCard()
                case .brainUsage:
                    BrainUsageCard()
                case .examRoleSimulator:
                    ExamRoleSimulatorHomeCard(onOpen: {})
                case .examReversePlanner:
                    ExamReversePlannerHomeCard(onOpen: {})
                case .weeklyFocus:
                    WeeklyFocusCard(summary: viewModel.weeklyFocus)
                case .subjectSnapshot:
                    if !viewModel.subjectSnapshots.isEmpty {
                        SubjectSnapshotCard(snapshots: viewModel.subjectSnapshots)
                    } else {
                        Text("No data in this period".localized())
                    }
                case .bodyMindTrend:
                    if viewModel.hasBodyMindData {
                        BodyMindTrendCard(
                            mood: viewModel.moodSeries,
                            sleep: viewModel.sleepSeries,
                            hrv: viewModel.hrvSeries
                        )
                    } else {
                        Text("No data in this period".localized())
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: ReportRenderer.defaultWidth, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 子组件 / Subcomponents
// HomeView 内的子卡片 View,各自独立成 struct。数据不足时调用方负责不渲染。
// Individual sub-cards used by HomeView.dynamicCards. Callers gate by data presence.

// MARK: - 成绩登记提醒卡片

struct UnregisteredExamsReminderCard: View {
    let unregisteredExams: [Exam]
    @Environment(RepositoryContainer.self) private var container
    @State private var showingAddGrade = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.bubble.fill")
                    .foregroundColor(.orange)
                Text("Register Exam Grades".localized())
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }

            ForEach(unregisteredExams) { exam in
                Button {
                    showingAddGrade = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exam.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                            HStack(spacing: 4) {
                                Text(exam.subject.localized())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("·")
                                    .foregroundColor(.secondary)
                                Text("\(daysSince(exam.examDate)) " + "days ago".localized())
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground).opacity(0.6))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(
            color: Color.black.opacity(0.05),
            radius: 10,
            x: 0,
            y: 4
        )
        .sheet(isPresented: $showingAddGrade) {
            AddGradeView(container: container)
                .environment(container)
                .adaptiveSheet()
        }
    }

    private func daysSince(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }
}

// MARK: - 每日励志卡片
struct DailyQuoteCard: View {
    let quote: String
    @Environment(RepositoryContainer.self) private var container

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 28))
                    .foregroundColor(container.envManager.effectiveAccentPalette.color.opacity(0.6))

                Text(quote)
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
            }
            Spacer()
        }
        .frame(minHeight: 140)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
    }
}

// MARK: - Flashcard Review Home Card

/// 主页「待复习」卡片：显示到期错题数量，引导用户进入闪卡模式
struct FlashcardReviewHomeCard: View {
    let overview: SRSOverview
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.fill")
                        .foregroundStyle(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .font(.title3)
                    Text("Flashcard Review".localized())
                        .font(.system(size: 18, weight: .semibold))
                }
                Spacer()
                if overview.dueCount > 0 {
                    Text("\(overview.dueCount)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red))
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(overview.dueCount)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Due Today".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(overview.upcomingCount)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Upcoming".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button {
                onStart()
            } label: {
                Label("Start Review".localized(), systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.12), Color.blue.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LinearGradient(
                    colors: [.purple.opacity(0.30), .blue.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 工具 / Utilities
// 内部 helper(派生数据重算 ViewModifier)+ SwiftUI 预览。
// Internal helpers (derived-data recompute ViewModifier) + SwiftUI previews.

// MARK: - 派生数据重算 ViewModifier
/// 集中管理 HomeView 4 个缓存的 onAppear / onChange 触发,
/// 避免在 body 链式调用中直接堆 4 个 modifier 导致 SwiftUI 类型推断超时。
private struct DerivedRecomputeModifier: ViewModifier {
    let grades: [Grade]
    let filteredExamSets: [Exam]
    let mistakeNotes: [MistakeNote]
    let recompute: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { recompute() }
            .onChange(of: grades) { _, _ in recompute() }
            .onChange(of: filteredExamSets) { _, _ in recompute() }
            .onChange(of: mistakeNotes) { _, _ in recompute() }
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
