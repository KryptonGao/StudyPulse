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
    @State private var viewModel: TodoViewModel

    init(container: RepositoryContainer) {
        _viewModel = State(initialValue: TodoViewModel.makeDefault(container: container))
    }

    // MARK: - Body

    var body: some View {
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
                .onChange(of: viewModel.showCompleted) { _, _ in viewModel.recompute() }
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

    /// 三段式主内容:空 / 日历 / 列表。拆为独立 View 避免 ViewBuilder 推导超时。
    /// Three-way main content: empty / calendar / list. Split out to avoid SwiftUI type-check timeout.
    @ViewBuilder
    private var mainContent: some View {
        if viewModel.allEntries.isEmpty && viewModel.pastEntries.isEmpty {
            VStack(spacing: 0) {
                filterChips
                emptyState
            }
        } else if viewModel.viewMode == .calendar {
            VStack(spacing: 0) {
                filterChips
                ScrollView {
                    calendarContent
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            listContent
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Items".localized(), systemImage: "checklist")
        } description: {
            Text("Tap '+' to add a homework, reading material, or exam.".localized())
        } actions: {
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
                Label("Add First Item".localized(), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if !viewModel.pastEntries.isEmpty {
                Button {
                    viewModel.showingPastSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("\(viewModel.pastEntries.count)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.showCompleted.toggle()
                }
            } label: {
                Image(systemName: viewModel.showCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                    .foregroundColor(viewModel.showCompleted ? Color(.systemGreen) : .accentColor)
            }
            .accessibilityLabel("Show Completed".localized())
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            viewModeMenu
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            addMenu
        }
        ToolbarItem(placement: .principal) {
            PhaseSelectorView()
        }
    }

    /// 渲染在「待办」标题正下方的水平滚动筛选 chip 行
    @ViewBuilder
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(TodoTypeFilter.allCases, id: \.self) { filter in
                    chip(for: filter)
                }
            }
            .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
            .padding(.vertical, 10)
        }
        // 筛选栏不设独立背景:与 Todo 页面根背景(Color(.systemGroupedBackground).opacity(rootBackground))保持一致,
        // 避免出现与页面主体不一致的灰色色带。
        // No dedicated background: keep the filter bar in sync with the Todo page
        // root background instead of painting an opaque gray band.
    }

    @ViewBuilder
    private func chip(for filter: TodoTypeFilter) -> some View {
        let selected = viewModel.typeFilter == filter
        let accent = chipAccent(for: filter)
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.typeFilter = filter
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: filter.systemImage)
                    .font(.footnote)
                Text(filter.label)
                    .font(.footnote)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                if #available(iOS 26, *) {
                    Color.clear.glassEffect(.regular, in: Capsule())
                } else {
                    Capsule().fill(.regularMaterial)
                }
            }
            .overlay(
                Capsule()
                    .fill(selected ? accent.opacity(0.18) : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(selected ? accent : Color.clear, lineWidth: selected ? 1.5 : 0)
            )
            .foregroundColor(Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func chipAccent(for filter: TodoTypeFilter) -> Color {
        switch filter {
        case .all:       return Color(red: 0.00, green: 0.42, blue: 1.00)
        case .exam:      return Color(red: 0.58, green: 0.18, blue: 1.00)
        case .homework:  return Color(red: 0.05, green: 0.72, blue: 0.28)
        case .reading:   return Color(red: 0.00, green: 0.62, blue: 0.92)
        case .routine:   return Color(red: 0.35, green: 0.34, blue: 0.84)
        }
    }

    // MARK: - 列表内容

    @ViewBuilder
    private var listContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterChips
                    .padding(.bottom, 16)

                if viewModel.upcomingEntries.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "checklist")
                                .font(.title2)
                                .foregroundColor(Color(.secondaryLabel))
                            Text("No upcoming items".localized())
                                .font(.subheadline)
                                .foregroundColor(Color(.secondaryLabel))
                        }
                        .padding(.vertical, 40)
                        Spacer()
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(viewModel.groupedUpcoming, id: \.0) { sectionTitle, entries in
                            sectionHeader(sectionTitle)
                            LazyVStack(spacing: 12) {
                                ForEach(entries) { entry in
                                    TodoRowView(
                                        entry: entry,
                                        onTap: { tapped(entry) },
                                        onToggleCompletion: { toggleCompletion(of: entry) }
                                    )
                                    .contextMenu {
                                        if entry.kind == .homework || entry.kind == .reading || entry.kind == .routine {
                                            Button {
                                                toggleCompletion(of: entry)
                                            } label: {
                                                if entry.isCompleted {
                                                    Label("Pending".localized(), systemImage: "circle")
                                                } else {
                                                    Label("Done".localized(), systemImage: "checkmark")
                                                }
                                            }
                                        }
                                        Button(role: .destructive) {
                                            viewModel.deleteTodoEntry(entry)
                                        } label: {
                                            Label("Delete".localized(), systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundColor(Color(.secondaryLabel))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
    }

    // MARK: - 日历内容

    @ViewBuilder
    private var calendarContent: some View {
        ExamCalendarView(
            onSelectExam: { exam in viewModel.selectedExam = exam },
            onSelectComprehensive: { exam in viewModel.selectedComprehensive = exam },
            onSelectTask: { task in viewModel.selectedTask = task },
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

    // MARK: - 视图模式菜单

    private var viewModeMenu: some View {
        Menu {
            Picker("View Mode".localized(), selection: $viewModel.viewMode) {
                ForEach(ExamViewMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: viewModel.viewMode == .calendar ? "calendar" : "list.bullet")
        }
        .onChange(of: viewModel.viewMode) { _, newValue in
            newValue.saveToDefaults()
        }
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

    private func tapped(_ entry: TodoEntry) {
        switch entry.kind {
        case .exam:
            if let exam = entry.exam { viewModel.selectedExam = exam }
        case .comprehensiveExam:
            if let comp = entry.comprehensiveExam { viewModel.selectedComprehensive = comp }
        case .homework, .reading:
            if let task = entry.taskItem { viewModel.selectedTask = task }
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
