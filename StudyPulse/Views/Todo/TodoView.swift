//
//  TodoView.swift
//  StudyPulse
//
//  「待办」页：统一展示日常作业、阅读材料与考试日程。
//
//  Created by Chenkai Gao on 2026/3/21.
//

import SwiftUI

// MARK: - 工具 / Utilities
// 筛选 chip 类型(TodoTypeFilter)与四象配色。
// Filter chip type with its 4 accent colors.

// MARK: - 类型筛选

/// 列表顶部的类型筛选 chip
enum TodoTypeFilter: Hashable, CaseIterable {
    case all
    case exam
    case homework
    case reading
    case routine

    var label: String {
        switch self {
        case .all: return "All".localized()
        case .exam: return "Exams".localized()
        case .homework: return "Homework".localized()
        case .reading: return "Reading".localized()
        case .routine: return "Routine".localized()
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "list.bullet"
        case .exam: return "calendar"
        case .homework: return "pencil.and.list.clipboard"
        case .reading: return "book.fill"
        case .routine: return "repeat"
        }
    }
}

// MARK: - 主体 / Main view

/// 「待办」主页:统一展示日常作业、阅读材料与考试日程。
/// 内部小节:Body / 列表内容 / 日历内容 / 视图模式菜单 / 新增菜单 / 行为。
/// Todo root. Unified view of homework, reading, and exam schedules.
/// Internal sub-MARKs cover body, list content, calendar content, view-mode
/// menu, add menu, and tap/completion behavior.
struct TodoView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.detailPane) private var pane
    @State private var viewModel: TodoViewModel

    init(container: RepositoryContainer) {
        _viewModel = State(initialValue: TodoViewModel.makeDefault(container: container))
    }

    // MARK: - Body

    var body: some View {
        TwoPane(masterWidth: 430, placeholderTitle: "todo.v2.pane.placeholder".localized(), placeholderIcon: "checklist") {
            content
        }
    }

    private var content: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Todo".localized())
                .navigationBarTitleDisplayMode(.large)
                .background(Color(.systemGroupedBackground).opacity(DesignToken.Opacity.rootBackground))
                .containerBackground(.clear, for: .navigation)
                .debugModeContainer()
                .debugLayoutBoundsAuto()
                .frame(maxWidth: .infinity)
                .toolbar { toolbarContent }
                .onAppear { viewModel.recompute() }
                .onChange(of: viewModel.typeFilter) { _, _ in viewModel.recompute() }
                .onChange(of: container.examRepo.filteredExamSets) { _, _ in viewModel.recompute() }
                .onChange(of: container.examRepo.comprehensiveExamSets) { _, _ in viewModel.recompute() }
                .onChange(of: container.taskRepo.taskItems) { _, _ in viewModel.recompute() }
                .onChange(of: container.routineInstanceRepo.allInstances) { _, _ in viewModel.recompute() }
                .onChange(of: container.routineRepo.filteredRoutines) { _, _ in viewModel.recompute() }
                .onChange(of: container.envManager.activePhaseId) { _, _ in viewModel.recompute() }
                .modifier(TodoViewSheetsAndDestinations(viewModel: viewModel, container: container))
                .onAppear {
                    container.refreshTaskCompletionStatesFromReminders()
                }
        }
    }

    private var isTotallyEmpty: Bool {
        viewModel.allEntries.isEmpty && viewModel.pastEntries.isEmpty && viewModel.typeFilter == .all
    }

    /// 主内容:空 / 日历 / 时间轴。拆开避免 ViewBuilder 推导超时。
    /// Main content: empty / calendar / agenda. Split to avoid type-check timeouts.
    @ViewBuilder
    private var mainContent: some View {
        if isTotallyEmpty {
            emptyState
        } else if viewModel.viewMode == .calendar {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.section) {
                    PhaseBar()
                    typeChips
                    calendarContent
                }
                .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
                .padding(.vertical)
                .adaptiveMaxWidth(900)
            }
        } else {
            agendaContent
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Items".localized(), systemImage: "checklist")
        } description: {
            Text("Tap '+' to add a homework, reading material, or exam.".localized())
        } actions: {
            addMenu
                .menuStyle(.button)
                .buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) { viewModeButton }
        ToolbarItem(placement: .navigationBarTrailing) { addMenu }
    }

    private var typeChips: some View {
        ChipBar(items: TodoTypeFilter.allCases.map { filter in
            ChipItem(id: filter, title: filter.label, systemImage: filter == .all ? nil : filter.systemImage,
                     count: count(for: filter))
        }, selection: $viewModel.typeFilter)
    }

    private func count(for filter: TodoTypeFilter) -> Int {
        let c = viewModel.typeCounts
        switch filter {
        case .all: return c.all
        case .exam: return c.exam
        case .homework: return c.homework
        case .reading: return c.reading
        case .routine: return c.routine
        }
    }

    // MARK: - 时间轴

    @ViewBuilder
    private var agendaContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.section) {
                    PhaseBar()

                    TodoWeekStrip(days: viewModel.weekStrip, selected: viewModel.selectedDay) { day in
                        viewModel.selectedDay = day
                        if let target = viewModel.agendaDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) && $0.kind != .later }) {
                            withAnimation(.snappy) { proxy.scrollTo(target.id, anchor: .top) }
                        }
                    }

                    if !viewModel.pastEntries.isEmpty {
                        InlineBanner(
                            systemImage: "exclamationmark.triangle.fill",
                            message: Text(String(format: "todo.v2.overdue".localized(), viewModel.pastEntries.count)),
                            actionTitle: "todo.v2.overdue.action".localized(),
                            tint: .orange
                        ) { viewModel.showingPastSheet = true }
                    }

                    typeChips

                    if viewModel.agendaDays.isEmpty {
                        ContentUnavailableView(
                            "No upcoming items".localized(),
                            systemImage: "checklist"
                        )
                        .padding(.vertical, 24)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(viewModel.agendaDays) { day in
                                dayBlock(day).id(day.id)
                            }
                        }
                    }

                    completedFold
                }
                .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
                .padding(.vertical)
                .adaptiveMaxWidth(900)
            }
        }
    }

    @ViewBuilder
    private func dayBlock(_ day: AgendaDay) -> some View {
        TodoDayHeader(day: day)
        ForEach(day.entries) { entry in
            agendaItem(entry, showDate: day.kind == .later)
        }
    }

    @ViewBuilder
    private func agendaItem(_ entry: TodoEntry, showDate: Bool) -> some View {
        Group {
            if entry.isExamLike {
                HStack(alignment: .top, spacing: 10) {
                    Color.clear.frame(width: 54, height: 1)
                    TodoExamCard(
                        entry: entry,
                        onTap: { tapped(entry) },
                        onPlan: entry.exam.map { exam in { viewModel.planningExam = exam } }
                    )
                }
            } else {
                TodoAgendaRow(entry: entry, onTap: { tapped(entry) }, onToggle: { toggleCompletion(of: entry) })
            }
        }
        .contextMenu {
            if entry.kind == .homework || entry.kind == .reading || entry.kind == .routine {
                Button { toggleCompletion(of: entry) } label: {
                    if entry.isCompleted {
                        Label("Pending".localized(), systemImage: "circle")
                    } else {
                        Label("Done".localized(), systemImage: "checkmark")
                    }
                }
            }
            Button(role: .destructive) { viewModel.deleteTodoEntry(entry) } label: {
                Label("Delete".localized(), systemImage: "trash")
            }
        }
    }

    /// 底部「已完成 N 项」折叠区 / Bottom "N completed" fold.
    @ViewBuilder
    private var completedFold: some View {
        if !viewModel.completedEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy) { viewModel.showCompleted.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                        Text(String(format: "todo.v2.completed".localized(), viewModel.completedEntries.count))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(viewModel.showCompleted ? 180 : 0))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                if viewModel.showCompleted {
                    ForEach(viewModel.completedEntries) { entry in
                        agendaItem(entry, showDate: true)
                    }
                }
            }
        }
    }

    // MARK: - 日历内容

    @ViewBuilder
    private var calendarContent: some View {
        ExamCalendarView(
            onSelectExam: { exam in openExam(exam) },
            onSelectComprehensive: { exam in openComprehensive(exam) },
            onSelectTask: { task in openTask(task) },
            typeFilter: calendarFilter
        )
    }

    private var calendarFilter: CalendarItemKindFilter {
        switch viewModel.typeFilter {
        case .all: return .all
        case .exam: return .exam
        case .homework: return .homework
        case .reading: return .reading
        // 日历视图不支持周期性例程,回退到全部
        case .routine: return .all
        }
    }

    // MARK: - 视图模式 / View mode

    /// 时间轴 ⇄ 月历 / Agenda ⇄ month calendar.
    private var viewModeButton: some View {
        Button {
            withAnimation(.snappy) {
                viewModel.viewMode = viewModel.viewMode == .calendar ? .list : .calendar
            }
            viewModel.viewMode.saveToDefaults()
        } label: {
            Image(systemName: viewModel.viewMode == .calendar ? "list.bullet" : "calendar")
        }
        .accessibilityLabel("View Mode".localized())
    }

    // MARK: - 新增菜单

    private var addMenu: some View {
        Menu {
            Button {
                viewModel.showingNewExam = true
            } label: {
                Label("New Exam".localized(), systemImage: "calendar.badge.plus")
            }
            Button {
                viewModel.showingNewTask = .homework
            } label: {
                Label("New Homework".localized(), systemImage: "pencil.and.list.clipboard")
            }
            Button {
                viewModel.showingNewTask = .reading
            } label: {
                Label("New Reading".localized(), systemImage: "book.fill")
            }
            Button {
                viewModel.showingNewRoutine = true
            } label: {
                Label("New Routine".localized(), systemImage: "repeat")
            }
        } label: {
            Image(systemName: "plus")
        }
    }

    // MARK: - 行为

    /// 双栏时把详情放到右栏,否则走 NavigationStack push。
    /// In a two-pane the detail goes to the right pane; otherwise it is pushed.
    private func openExam(_ exam: Exam) {
        if let pane {
            pane.show(id: exam.id, content: AnyView(ExamDetailView(examId: exam.id)))
        } else {
            viewModel.selectedExam = exam
        }
    }

    private func openComprehensive(_ exam: comprehensiveExam) {
        if let pane {
            pane.show(id: exam.id, content: AnyView(ComprehensiveExamDetailView(exam: exam)))
        } else {
            viewModel.selectedComprehensive = exam
        }
    }

    private func openTask(_ task: TaskItem) {
        if let pane {
            pane.show(id: task.id, content: AnyView(TaskDetailView(task: task)))
        } else {
            viewModel.selectedTask = task
        }
    }

    private func tapped(_ entry: TodoEntry) {
        switch entry.kind {
        case .exam:
            if let exam = entry.exam { openExam(exam) }
        case .comprehensiveExam:
            if let comp = entry.comprehensiveExam { openComprehensive(comp) }
        case .homework, .reading:
            if let task = entry.taskItem { openTask(task) }
        case .routine:
            if let r = entry.routine { viewModel.selectedRoutine = r }
        }
    }

    private func toggleCompletion(of entry: TodoEntry) {
        switch entry.kind {
        case .homework, .reading:
            guard let task = entry.taskItem else { return }
            viewModel.toggleCompletion(for: task)
        case .routine:
            guard let inst = entry.routineInstance else { return }
            viewModel.toggleCompletion(for: inst)
        default:
            break
        }
    }
}

// MARK: - 子组件 / Subcomponents
// TodoView 调用的辅助 Sheet(过去条目列表 + 类型图标 / 文案 / 配色 helper)。
// Auxiliary sheet and per-kind icon / label / color helpers used by TodoView.

// MARK: - 过期条目 Sheet

struct PastItemsSheet: View {
    let pastEntries: [TodoEntry]
    let onSelectExam: (Exam) -> Void
    let onSelectComprehensive: (comprehensiveExam) -> Void
    let onSelectTask: (TaskItem) -> Void
    let onSelectRoutine: (Routine) -> Void
    let onDeleteEntry: (TodoEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(pastEntries) { entry in
                    Button {
                        dismiss()
                        switch entry.kind {
                        case .exam:
                            if let exam = entry.exam { onSelectExam(exam) }
                        case .comprehensiveExam:
                            if let comp = entry.comprehensiveExam { onSelectComprehensive(comp) }
                        case .homework, .reading:
                            if let task = entry.taskItem { onSelectTask(task) }
                        case .routine:
                            if let r = entry.routine { onSelectRoutine(r) }
                        }
                    } label: {
                        pastRow(entry: entry)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onDeleteEntry(entry)
                        } label: {
                            Label("Delete".localized(), systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
            .navigationTitle("Past Items".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized()) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func pastRow(entry: TodoEntry) -> some View {
        HStack {
            typeIcon(for: entry)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline)
                    .foregroundColor(Color(.label))
                Text(entry.subject)
                    .font(.caption)
                    .foregroundColor(Color(.secondaryLabel))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.date, style: .date)
                    .font(.caption)
                    .foregroundColor(Color(.secondaryLabel))
                Text(typeLabel(for: entry))
                    .font(.caption2)
                    .foregroundColor(typeColor(for: entry))
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func typeIcon(for entry: TodoEntry) -> some View {
        switch entry.kind {
        case .exam:
            Image(systemName: "calendar")
                .foregroundColor(Color(.systemBlue))
        case .comprehensiveExam:
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundColor(Color(.systemPurple))
        case .homework:
            Image(systemName: "pencil.and.list.clipboard")
                .foregroundColor(Color(.systemGreen))
        case .reading:
            Image(systemName: "book.fill")
                .foregroundColor(Color(.systemIndigo))
        case .routine:
            Image(systemName: "repeat")
                .foregroundColor(Color(.systemIndigo))
        }
    }

    private func typeLabel(for entry: TodoEntry) -> String {
        switch entry.kind {
        case .exam: return "Exam".localized()
        case .comprehensiveExam: return "Compre.".localized()
        case .homework: return "Homework".localized()
        case .reading: return "Reading".localized()
        case .routine: return "Routine".localized()
        }
    }

    private func typeColor(for entry: TodoEntry) -> Color {
        switch entry.kind {
        case .exam: return Color(.systemBlue)
        case .comprehensiveExam: return Color(.systemPurple)
        case .homework: return Color(.systemGreen)
        case .reading: return Color(.systemIndigo)
        case .routine: return Color(.systemIndigo)
        }
    }
}

#Preview {
    let container = RepositoryContainer()
    TodoView(container: container)
        .environment(container)
        .preferredColorScheme(.light)
}

// MARK: - Sheets & Destinations 修饰器 / Sheets & Destinations modifier
//
// 把 3 个 sheet + 3 个 navigationDestination 抽成单独的 ViewModifier,
// 避免 `body` 中链式修饰器过多导致 SwiftUI 类型推导超时。
// Extracted to dodge the "type-check timeout" error on `TodoView.body`.

private struct TodoViewSheetsAndDestinations: ViewModifier {
    @Bindable var viewModel: TodoViewModel
    let container: RepositoryContainer

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $viewModel.showingNewExam) {
                NewExamSetView(container: container)
                    .adaptiveSheet()
            }
            .sheet(item: $viewModel.showingNewTask) { taskType in
                NewTaskView(initialType: taskType)
                    .adaptiveSheet()
            }
            .sheet(isPresented: $viewModel.showingNewRoutine) {
                RoutineEditorSheet(container: container, editing: nil)
                    .adaptiveSheet()
            }
            .sheet(item: $viewModel.selectedRoutine) { routine in
                RoutineEditorSheet(container: container, editing: routine)
                    .adaptiveSheet()
            }
            .sheet(isPresented: $viewModel.showingPastSheet) {
                pastItemsSheet
            }
            .fullScreenCover(item: $viewModel.planningExam) { exam in
                ExamReversePlannerView(container: container, examId: exam.id)
            }
            .navigationDestination(item: $viewModel.selectedExam) { exam in
                ExamDetailView(examId: exam.id)
                    .background(Color(.systemBackground))
            }
            .navigationDestination(item: $viewModel.selectedComprehensive) { exam in
                ComprehensiveExamDetailView(exam: exam)
                    .background(Color(.systemBackground))
            }
            .navigationDestination(item: $viewModel.selectedTask) { task in
                TaskDetailView(task: task)
                    .background(Color(.systemBackground))
            }
    }

    private var pastItemsSheet: some View {
        PastItemsSheet(
            pastEntries: viewModel.pastEntries,
            onSelectExam: { exam in
                viewModel.showingPastSheet = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    viewModel.selectedExam = exam
                }
            },
            onSelectComprehensive: { exam in
                viewModel.showingPastSheet = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    viewModel.selectedComprehensive = exam
                }
            },
            onSelectTask: { task in
                viewModel.showingPastSheet = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    viewModel.selectedTask = task
                }
            },
            onSelectRoutine: { routine in
                viewModel.showingPastSheet = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    viewModel.selectedRoutine = routine
                }
            },
            onDeleteEntry: { entry in viewModel.deleteTodoEntry(entry) }
        )
        .adaptiveSheet(detents: [.medium, .large])
    }
}
