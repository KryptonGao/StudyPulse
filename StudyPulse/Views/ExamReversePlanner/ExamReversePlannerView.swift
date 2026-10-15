import SwiftUI

struct ExamReversePlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ExamReversePlannerViewModel
    @State private var showingExitConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingEditor = false
    @State private var editorGoal: ExamGoal?
    @State private var prefilledGoal: ExamGoal?

    init(container: RepositoryContainer) {
        _viewModel = State(initialValue: ExamReversePlannerViewModel.makeDefault(container: container))
        _editorGoal = State(initialValue: nil)
        _prefilledGoal = State(initialValue: nil)
    }

    init(container: RepositoryContainer, examId: UUID) {
        let exam = container.examRepo.examSets.first { $0.id == examId }
        let prefilled = exam.map {
            let subject = $0.subject
            return ExamGoal(
                examName: $0.name,
                subject: subject,
                examDate: $0.examDate,
                currentScore: 0,
                targetScore: 0,
                fullScore: container.subjectRepo.subjects.first { $0.name == subject }?.fullScore ?? 100,
                phaseId: $0.phaseId
            )
        }
        _viewModel = State(initialValue: ExamReversePlannerViewModel.makeDefault(container: container))
        _editorGoal = State(initialValue: nil)
        _prefilledGoal = State(initialValue: prefilled)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .loading:
                    AIWaitingView(
                        title: "exam.reverse.planner.generating".localized(),
                        messages: [
                            "exam.reverse.planner.waiting.1".localized(),
                            "exam.reverse.planner.waiting.2".localized(),
                            "exam.reverse.planner.waiting.3".localized()
                        ],
                        onCancel: { viewModel.cancelGeneration() }
                    )
                case .success:
                    if let goal = viewModel.selectedGoal, let plan = viewModel.currentPlan {
                        resultView(goal: goal, plan: plan)
                    } else {
                        landingView
                    }
                case .failure, .idle:
                    if showingEditor {
                        editorView
                    } else if let goal = viewModel.selectedGoal, let plan = viewModel.currentPlan {
                        resultView(goal: goal, plan: plan)
                    } else {
                        landingView
                    }
                }
            }
            .navigationTitle("exam.reverse.planner.title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingExitConfirmation = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close".localized())
                    .disabled(viewModel.phase == .loading)
                }
                if !showingEditor && viewModel.phase != .loading {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editorGoal = nil
                            prefilledGoal = nil
                            showingEditor = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add".localized())
                    }
                }
            }
        }
        .onAppear {
            if let prefilledGoal, viewModel.goals.isEmpty {
                editorGoal = prefilledGoal
                showingEditor = true
            }
        }
        .alert("exam.reverse.planner.exit.title".localized(), isPresented: $showingExitConfirmation) {
            Button("取消".localized(), role: .cancel) { }
            Button("关闭".localized(), role: .destructive) { dismiss() }
        } message: {
            Text("exam.reverse.planner.exit.message".localized())
        }
        .alert("exam.reverse.planner.delete.title".localized(), isPresented: $showingDeleteConfirmation) {
            Button("取消".localized(), role: .cancel) { }
            Button("删除".localized(), role: .destructive) {
                if let plan = viewModel.currentPlan { viewModel.deletePlan(plan) }
            }
        } message: {
            Text("exam.reverse.planner.delete.message".localized())
        }
        .alert("提示".localized(), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("好".localized()) { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var landingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
                if viewModel.goals.isEmpty {
                    ContentUnavailableView(
                        "exam.reverse.planner.empty".localized(),
                        systemImage: "calendar.badge.clock",
                        description: Text("exam.reverse.planner.empty.detail".localized())
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(viewModel.goals) { goal in
                        Button {
                            viewModel.selectGoal(goal)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(goal.examName).font(DesignToken.Font.bodyBold)
                                    Text(goal.subject).font(DesignToken.Font.caption).foregroundStyle(.secondary)
                                    Text(String(format: "exam.reverse.planner.gap".localized(), goal.targetScore - goal.currentScore))
                                        .font(DesignToken.Font.caption).foregroundStyle(.teal)
                                }
                                Spacer()
                                Text(String(format: "exam.reverse.planner.days".localized(), daysRemaining(for: goal)))
                                    .font(DesignToken.Font.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(DesignToken.Spacing.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSkin()
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { viewModel.deleteGoal(goal) } label: {
                                Label("删除目标".localized(), systemImage: "trash")
                            }
                        }
                    }
                }
                Button {
                    editorGoal = nil
                    prefilledGoal = nil
                    showingEditor = true
                } label: {
                    Label("exam.reverse.planner.new.goal".localized(), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            }
            .padding(.horizontal, DesignToken.Spacing.secondaryHorizontal)
            .padding(.vertical, DesignToken.Spacing.large)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var editorView: some View {
        ExamGoalEditorView(
            viewModel: viewModel,
            existingGoal: editorGoal,
            initialGoal: prefilledGoal
        ) { _ in
            prefilledGoal = nil
            editorGoal = nil
            showingEditor = false
        }
    }

    private func resultView(goal: ExamGoal, plan: ExamPlan) -> some View {
        ExamPlanResultView(
            goal: goal,
            plan: plan,
            onRegenerate: { Task { await viewModel.generatePlan(for: goal) } },
            onDelete: { showingDeleteConfirmation = true },
            onEditGoal: {
                editorGoal = goal
                showingEditor = true
            }
        )
    }

    private func daysRemaining(for goal: ExamGoal) -> Int {
        max(0, Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: goal.examDate)
        ).day ?? 0)
    }
}
