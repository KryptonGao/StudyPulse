//
//  ExamView.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/3/23.
//
//  考试列表主视图:列表 / 月历两种模式,可新建/编辑/删除/预测
//  Exam list root view: list or calendar mode, with create / edit / delete / predict.
//

import SwiftUI

// MARK: - 主体 / Main view

/// 考试列表主视图,支持列表 / 月历两种模式,可新建 / 编辑 / 删除 / 预测。
/// 内部小节:内容 / 视图模式切换。
/// Exam list root view. Supports list and calendar modes, plus
/// create / edit / delete / predict flows. Internal sub-MARKs cover
/// content rendering and the view-mode toggle menu.
struct ExamView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var viewModel: ExamViewModel

    init(container: RepositoryContainer) {
        _viewModel = State(initialValue: ExamViewModel.makeDefault(container: container))
    }


    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Exams".localized())
                .navigationBarTitleDisplayMode(.large)
                .background(Color(.systemGroupedBackground).opacity(DesignToken.Opacity.rootBackground))
                .frame(maxWidth: .infinity)
                .toolbar { toolbarContent }
                .modifier(ExamViewSheetsAndDestinations(viewModel: viewModel, container: container))
                .onAppear { viewModel.recompute() }
                .onChange(of: container.examRepo.filteredExamSets) { _, _ in viewModel.recompute() }
                .onChange(of: container.examRepo.filteredComprehensiveExamSets) { _, _ in viewModel.recompute() }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if viewModel.upcomingExams.isEmpty && viewModel.pastExams.isEmpty {
                ContentUnavailableView(
                    "No Exams".localized(),
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Tap '+' to add a new exam.".localized())
                )
                .background(Color(.systemGroupedBackground))
            } else if viewModel.showsCalendar {
                calendarContent
            } else {
                listContent
            }
        }
        .containerBackground(.clear, for: .navigation)
        .debugModeContainer()
        .debugLayoutBoundsAuto()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if !viewModel.pastExams.isEmpty {
                Button {
                    viewModel.showingPastExams = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("\(viewModel.pastExams.count)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            viewModeMenu
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: { viewModel.showingNewExamSet = true }) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New Exam".localized())
        }
        ToolbarItem(placement: .principal) {
            PhaseSelectorView()
        }
    }

    // MARK: - 内容
    // MARK: - Content

    @ViewBuilder
    private var listContent: some View {
        List {
            if viewModel.upcomingExams.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.title2)
                                .foregroundColor(Color(.secondaryLabel))
                            Text("No upcoming exams".localized())
                                .font(.subheadline)
                                .foregroundColor(Color(.secondaryLabel))
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                }
            } else {
                ForEach(viewModel.groupedExams, id: \.0) { sectionTitle, exams in
                    Section(header: Text(sectionTitle)
                        .foregroundColor(Color(.secondaryLabel))
                        .font(.subheadline)
                        .textCase(.none)
                    ) {
                        ForEach(exams.indices, id: \.self) { index in
                            let item = exams[index]

                            if let exam = item as? Exam {
                                ExamRowView(
                                    exam: exam,
                                    onPredict: { viewModel.openPrediction(for: exam) }
                                )
                                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectedExamForDetail = exam
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            viewModel.openPrediction(for: exam)
                                        } label: {
                                            Label("Predict".localized(), systemImage: "chart.line.uptrend.xyaxis")
                                        }
                                        .tint(Color(.systemBlue))

                                        Button(role: .destructive) {
                                            viewModel.deleteExam(exam)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .tint(Color(.systemRed))
                                    }
                            }
                            else if let comprehensive = item as? comprehensiveExam {
                                ComprehensiveExamRowView(
                                    exam: comprehensive,
                                    onPredict: { viewModel.openPrediction(for: comprehensive) }
                                )
                                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectedComprehensiveExam = comprehensive
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            viewModel.openPrediction(for: comprehensive)
                                        } label: {
                                            Label("Predict".localized(), systemImage: "chart.line.uptrend.xyaxis")
                                        }
                                        .tint(Color(.systemPurple))

                                        Button(role: .destructive) {
                                            viewModel.deleteComprehensiveExam(comprehensive)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .tint(Color(.systemRed))
                                    }
                            }
                        }
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var calendarContent: some View {
        ExamCalendarView(
            onSelectExam: { exam in viewModel.selectedExamForDetail = exam },
            onSelectComprehensive: { exam in viewModel.selectedComprehensiveExam = exam }
        )
    }

    // MARK: - 视图模式切换
    // MARK: - View mode toggle

    /// 列表 / 月历 切换的菜单
    /// Menu for toggling between list and calendar mode.
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
            Image(systemName: viewModel.showsCalendar ? "calendar" : "list.bullet")
        }
        .onChange(of: viewModel.viewMode) { _, newValue in
            newValue.saveToDefaults()
        }
    }
}

// MARK: - Sheets & Destinations 修饰器
// MARK: - Sheets & Destinations modifier
//
// 把 5 个 sheet + 2 个 navigationDestination 抽成单独的 ViewModifier,
// 避免 `body` 中链式修饰器过多导致 SwiftUI 类型推导超时。
// Extracted to dodge the "type-check timeout" error on `ExamView.body`.

private struct ExamViewSheetsAndDestinations: ViewModifier {
    @Bindable var viewModel: ExamViewModel
    let container: RepositoryContainer

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $viewModel.showingNewExamSet) {
                NewExamSetView(container: container)
                    .adaptiveSheet()
            }
            .sheet(isPresented: $viewModel.showingPastExams) {
                pastExamsSheet
            }
            .navigationDestination(item: $viewModel.selectedExamForDetail) { exam in
                ExamDetailView(examId: exam.id)
                    .background(Color(.systemBackground))
            }
            .navigationDestination(item: $viewModel.selectedComprehensiveExam) { exam in
                ComprehensiveExamDetailView(exam: exam)
                    .background(Color(.systemBackground))
            }
            .sheet(item: $viewModel.predictionTarget) { target in
                ScorePredictionSheet(
                    exam: target.exam,
                    history: target.history,
                    fullScore: target.fullScore,
                    onDismiss: { viewModel.predictionTarget = nil }
                )
                .adaptiveSheet(detents: [.medium, .large])
            }
            .sheet(item: $viewModel.comprehensivePredictionTarget) { target in
                ComprehensiveScorePredictionSheet(
                    target: target,
                    onDismiss: { viewModel.comprehensivePredictionTarget = nil }
                )
                .adaptiveSheet(detents: [.medium, .large])
            }
    }

    private var pastExamsSheet: some View {
        PastExamsSheet(
            pastExams: viewModel.pastExams,
            onSelectExam: { exam in
                viewModel.showingPastExams = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    viewModel.selectedExamForDetail = exam
                }
            },
            onSelectComprehensive: { exam in
                viewModel.showingPastExams = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    viewModel.selectedComprehensiveExam = exam
                }
            },
            onDeleteExam: { exam in viewModel.deleteExam(exam) },
            onDeleteComprehensive: { exam in viewModel.deleteComprehensiveExam(exam) }
        )
        .adaptiveSheet(detents: [.medium, .large])
    }
}

// MARK: - 子组件 / Subcomponents
// ExamView 的辅助 View 与目标数据类型:预测目标、过去考试 Sheet、列表 / 月历行。
// Auxiliary types and views used by ExamView: prediction target struct,
// past-exams bottom sheet, and the single / comprehensive exam rows.

// MARK: - 预测目标
// MARK: - Prediction target

/// 触发 ScorePredictionSheet 的目标（Identifiable 用于 sheet(item:) 绑定）
/// Target for the ScorePredictionSheet (Identifiable so it can drive `sheet(item:)`).
struct PredictionTarget: Identifiable {
    let id = UUID()
    let exam: Exam
    let history: [Grade]
    let fullScore: Double
}

// MARK: - 过去考试 Sheet
// MARK: - Past exams sheet

/// 过去考试列表 Sheet
/// Bottom sheet listing past (already-occurred) exams.
struct PastExamsSheet: View {
    let pastExams: [Any]
    let onSelectExam: (Exam) -> Void
    let onSelectComprehensive: (comprehensiveExam) -> Void
    let onDeleteExam: (Exam) -> Void
    let onDeleteComprehensive: (comprehensiveExam) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(pastExams.indices, id: \.self) { index in
                    let item = pastExams[index]
                    
                    if let exam = item as? Exam {
                        Button {
                            dismiss()
                            onSelectExam(exam)
                        } label: {
                            pastExamLabel(
                                name: exam.name,
                                subject: exam.subject,
                                date: exam.examDate,
                                mastery: exam.masteryDegree
                            )
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onDeleteExam(exam)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(Color(.systemRed))
                        }
                    } else if let comp = item as? comprehensiveExam {
                        Button {
                            dismiss()
                            onSelectComprehensive(comp)
                        } label: {
                            pastExamLabel(
                                name: comp.name,
                                subject: comp.subject.joined(separator: ", "),
                                date: comp.examDate,
                                mastery: comp.masteryDegree
                            )
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onDeleteComprehensive(comp)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(Color(.systemRed))
                        }
                    }
                }
            }
            .navigationTitle("Past Exams".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized()) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    /// 过去考试行通用标签
    /// Generic row label used by both single and comprehensive past exams.
    private func pastExamLabel(name: String, subject: String, date: Date, mastery: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(Color(.label))
                Text(subject)
                    .font(.caption)
                    .foregroundColor(Color(.secondaryLabel))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundColor(Color(.secondaryLabel))
                Text("\(mastery)%")
                    .font(.caption2)
                    .foregroundColor(mastery >= 60 ? Color(.systemGreen) : Color(.systemOrange))
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - 子视图：普通考试行
// MARK: - Subview: single-subject exam row

/// 列表 / 月历都用的普通考试行(包含天数倒计 / 掌握度 / 预测按钮)
/// Single-subject exam row used by both list and calendar (countdown, mastery, predict button).
struct ExamRowView: View {
    let exam: Exam
    /// 点击"预测"按钮的回调
    /// Callback for tapping the "Predict" button.
    var onPredict: (() -> Void)? = nil
    @State private var animateIn = false

    /// 距离考试还有几天(已过期则 0)
    /// Days remaining until the exam (clamped to 0 for past exams).
    private var daysRemaining: Int {
        let components = Calendar.current.dateComponents([.day], from: Date(), to: exam.examDate)
        return max(0, components.day ?? 0)
    }

    /// 时间进度(0~1):基于 30 天窗口
    /// Time progress (0–1) — based on a 30-day window.
    private var timeProgress: Double {
        min(Double(daysRemaining) / 30.0, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(exam.name)
                    .font(.headline)
                    .foregroundColor(Color(.label))
                    .debugInspectAuto(exam.name, label: "exam name")
                Spacer()
                Text(exam.subject.localized())
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(.systemBlue).opacity(0.15))
                    )
                    .foregroundColor(Color(.systemBlue))
            }

            Group {
                if let endDate = exam.examEndDate, !Calendar.current.isDate(exam.examDate, inSameDayAs: endDate) {
                    Text("\(exam.examDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))")
                } else {
                    Text("\(exam.examDate, style: .date)")
                }
            }
            .font(.caption)
                .foregroundColor(Color(.secondaryLabel))

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time Left".localized())
                        .font(.caption2)
                        .foregroundColor(Color(.secondaryLabel))
                    ProgressView(value: timeProgress, total: 1.0)
                        .tint(timeLeftColor)
                        .scaleEffect(x: 1, y: 1.2, anchor: .center)
                    Text(daysRemaining > 0 ? "\(daysRemaining) " + "days".localized() : "Today!".localized())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(daysRemaining > 2 ? Color(.secondaryLabel) : Color(.systemRed))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Mastery".localized())
                        .font(.caption2)
                        .foregroundColor(Color(.secondaryLabel))
                    ProgressView(value: Double(exam.masteryDegree), total: 100.0)
                        .tint(masteryColor)
                        .scaleEffect(x: 1, y: 1.2, anchor: .center)

                    Text("\(exam.masteryDegree)%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(exam.masteryDegree <= 5 ? Color(.systemRed) : Color(.secondaryLabel))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 预测按钮：放在进度条下方,显眼易找
            // Predict button: placed below the progress bars for visibility.
            if let onPredict = onPredict {
                Button {
                    onPredict()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.caption.weight(.bold))
                        Text("Predict".localized())
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule()
                            .fill(Color(.systemBlue).opacity(0.12))
                    )
                    .foregroundColor(Color(.systemBlue))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))

                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(.systemBlue).opacity(0.25),
                                Color(.systemBlue).opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(
            color: Color.black.opacity(0.05),
            radius: 6,
            x: 0,
            y: 3
        )
        .hoverHighlight()
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 15)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                animateIn = true
            }
        }
        .debugLayoutBoundsAuto()
    }

    private var timeLeftColor: Color {
        if daysRemaining <= 3 {
            return Color(.systemRed)
        } else if daysRemaining <= 7 {
            return Color(.systemOrange)
        } else {
            return Color(.systemGreen)
        }
    }
    
    private var masteryColor: Color {
        if exam.masteryDegree <= 20 {
            return Color(.systemRed)
        } else if exam.masteryDegree <= 60 {
            return Color(.systemOrange)
        } else {
            return Color(.systemGreen)
        }
    }
}

// MARK: - 子视图：综合考试行
// MARK: - Subview: comprehensive exam row

/// 综合考试行(紫色主题),点击"预测"弹总分预测
/// Comprehensive exam row (purple theme); predict button opens the total-score sheet.
struct ComprehensiveExamRowView: View {
    let exam: comprehensiveExam
    /// 点击"预测"按钮的回调
    /// Callback for tapping the "Predict" button.
    var onPredict: (() -> Void)? = nil
    @State private var animateIn = false
    
    private var daysRemaining: Int {
        let components = Calendar.current.dateComponents([.day], from: Date(), to: exam.examDate)
        return max(0, components.day ?? 0)
    }
    
    private var timeProgress: Double {
        min(Double(daysRemaining) / 30.0, 1.0)
    }
    
    private var subjectText: String {
        exam.subject.joined(separator: ", ")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(exam.name.localized())
                    .font(.headline)
                    .foregroundColor(Color(.label))
                    .debugInspectAuto(exam.name, label: "comprehensive exam name")
                Spacer()
                Text(subjectText.localized())
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(.systemPurple).opacity(0.15))
                    )
                    .foregroundColor(Color(.systemPurple))
            }
            
            Group {
                if let endDate = exam.examEndDate, !Calendar.current.isDate(exam.examDate, inSameDayAs: endDate) {
                    Text("\(exam.examDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))")
                } else {
                    Text("\(exam.examDate, style: .date)")
                }
            }
            .font(.caption)
                .foregroundColor(Color(.secondaryLabel))
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time Left".localized())
                        .font(.caption2)
                        .foregroundColor(Color(.secondaryLabel))
                    ProgressView(value: timeProgress, total: 1.0)
                        .tint(timeLeftColor)
                        .scaleEffect(x: 1, y: 1.2, anchor: .center)
                    Text(daysRemaining > 0 ? "\(daysRemaining) " + "days".localized() : "Today!".localized())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(daysRemaining > 2 ? Color(.secondaryLabel) : Color(.systemRed))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mastery".localized())
                        .font(.caption2)
                        .foregroundColor(Color(.secondaryLabel))
                    ProgressView(value: Double(exam.masteryDegree), total: 100.0)
                        .tint(masteryColor)
                        .scaleEffect(x: 1, y: 1.2, anchor: .center)

                    Text("\(exam.masteryDegree)%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(exam.masteryDegree <= 5 ? Color(.systemRed) : Color(.secondaryLabel))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 预测按钮(综合考试,预测总分)
            // Predict button (comprehensive exam → predicts total score).
            if let onPredict = onPredict {
                Button {
                    onPredict()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.caption.weight(.bold))
                        Text("Predict".localized())
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule()
                            .fill(Color(.systemPurple).opacity(0.12))
                    )
                    .foregroundColor(Color(.systemPurple))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))

                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(.systemPurple).opacity(0.25),
                                Color(.systemPurple).opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(
            color: Color.black.opacity(0.05),
            radius: 6,
            x: 0,
            y: 3
        )
        .hoverHighlight()
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 15)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                animateIn = true
            }
        }
        .debugLayoutBoundsAuto()
    }

    private var timeLeftColor: Color {
        if daysRemaining <= 3 {
            return Color(.systemRed)
        } else if daysRemaining <= 7 {
            return Color(.systemOrange)
        } else {
            return Color(.systemGreen)
        }
    }
    
    private var masteryColor: Color {
        if exam.masteryDegree <= 20 {
            return Color(.systemRed)
        } else if exam.masteryDegree <= 60 {
            return Color(.systemOrange)
        } else {
            return Color(.systemGreen)
        }
    }
}

#Preview {
    ExamView(container: RepositoryContainer())
        .environment(RepositoryContainer())
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ExamView(container: RepositoryContainer())
        .environment(RepositoryContainer())
        .preferredColorScheme(.dark)
}

// MARK: - 工具 / Utilities
// 视图模式枚举(UserDefaults 持久化)。
// View-mode enum with UserDefaults persistence.

// MARK: - 视图模式
// MARK: - View mode

/// 考试页面视图模式：列表 / 月历
/// Exam page view mode: list or calendar.
enum ExamViewMode: String, CaseIterable, Identifiable, Codable {
    case list
    case calendar

    var id: String { rawValue }

    /// 显示名称
    @MainActor var displayName: String {
        switch self {
        case .list: return "List".localized()
        case .calendar: return "Calendar".localized()
        }
    }

    /// 工具栏图标
    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .calendar: return "calendar"
        }
    }

    private static let userDefaultsKey = "examViewMode"

    /// 从 UserDefaults 加载，缺失或非法值时默认 list
    static func loadFromDefaults() -> ExamViewMode {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              let mode = ExamViewMode(rawValue: raw) else {
            return .list
        }
        return mode
    }

    /// 持久化到 UserDefaults
    func saveToDefaults() {
        UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
    }
}
