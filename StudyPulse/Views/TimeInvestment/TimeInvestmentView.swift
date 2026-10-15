import SwiftUI
import UIKit

private enum TimeInvestmentSheet: Identifiable {
    case subject(TimeInvestmentSubject?)
    case subTask(subjectID: UUID, parentID: UUID?, editing: SubTask?)
    case reward
    case session(StudySession?)
    case unassigned

    var id: String {
        switch self {
        case .subject(let value): return "subject-\(value?.id.uuidString ?? "new")"
        case .subTask(let subjectID, let parentID, let editing):
            return "subtask-\(subjectID)-\(parentID?.uuidString ?? "root")-\(editing?.id.uuidString ?? "new")"
        case .reward: return "reward"
        case .session(let value): return "session-\(value?.id.uuidString ?? "new")"
        case .unassigned: return "unassigned"
        }
    }
}

struct TimeInvestmentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(RepositoryContainer.self) private var container
    @StateObject private var viewModel: TimeInvestmentViewModel
    @State private var presentedSheet: TimeInvestmentSheet?
    @State private var expandedSubjects = Set<UUID>()
    @State private var expandedSubTasks = Set<UUID>()

    init(container: RepositoryContainer) {
        _viewModel = StateObject(
            wrappedValue: TimeInvestmentViewModel.makeDefault(container: container)
        )
    }

    private var columns: [GridItem] {
        sizeClass == .regular
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible())]
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DesignToken.Spacing.cardSpacing) {
                rewardCard

                if viewModel.projects.isEmpty {
                    emptyProjects
                } else {
                    LazyVGrid(columns: columns, spacing: DesignToken.Spacing.large) {
                        ForEach(viewModel.projects) { summary in
                            projectCard(summary)
                        }
                    }
                }
            }
            .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
            .padding(.vertical, DesignToken.Spacing.large)
        }
        .background(
            Color(.systemGroupedBackground)
                .opacity(DesignToken.Opacity.rootBackground)
        )
        .navigationTitle("time.investment.title".localized())
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !viewModel.unassignedSessions.isEmpty {
                    Button {
                        presentedSheet = .unassigned
                    } label: {
                        Image(systemName: "tray.full.fill")
                    }
                    .accessibilityLabel("time.investment.unassigned".localized())
                }

                Menu {
                    Button {
                        presentedSheet = .subject(nil)
                    } label: {
                        Label("time.investment.addProject".localized(), systemImage: "folder.badge.plus")
                    }
                    Button {
                        presentedSheet = .session(nil)
                    } label: {
                        Label("time.investment.manualLog".localized(), systemImage: "clock.badge.plus")
                    }
                    .disabled(viewModel.activeTargets.isEmpty)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add".localized())
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            sheetView(sheet)
                .environment(container)
                .adaptiveSheet()
        }
        .alert(
            "time.investment.error.title".localized(),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("OK".localized(), role: .cancel) { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let reward = viewModel.newlyUnlockedReward {
                RewardUnlockToast(reward: reward) {
                    viewModel.clearUnlockPresentation()
                }
                .padding(.top, DesignToken.Spacing.small)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear { viewModel.recompute() }
        .onChange(of: container.studySessionRepo.sessions) { _, _ in viewModel.recompute() }
        .onChange(of: container.timeInvestmentRepo.subjects) { _, _ in viewModel.recompute() }
        .onChange(of: container.timeInvestmentRepo.subTasks) { _, _ in viewModel.recompute() }
        .onChange(of: container.timeInvestmentRepo.rewards) { _, _ in viewModel.recompute() }
    }

    private var rewardCard: some View {
        RewardGoalCard(
            rewards: viewModel.rewards,
            progress: { reward in
                let total = viewModel.totalSeconds(for: reward.target)
                return min(1, Double(total) / Double(max(1, reward.thresholdSeconds)))
            },
            targetName: viewModel.displayName,
            onAdd: { presentedSheet = .reward },
            onDelete: viewModel.deleteReward
        )
    }

    private var emptyProjects: some View {
        ContentUnavailableView {
            Label("time.investment.empty.title".localized(), systemImage: "hourglass")
        } description: {
            Text("time.investment.empty.description".localized())
        } actions: {
            Button("time.investment.addProject".localized()) {
                presentedSheet = .subject(nil)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 56)
    }

    private func projectCard(_ summary: TimeInvestmentViewModel.ProjectSummary) -> some View {
        let subject = summary.subject
        let themeColor = Color(hex: subject.theme.colorHex)
        let children = viewModel.children(of: nil, subjectID: subject.id)
        let expanded = expandedSubjects.contains(subject.id)

        return VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            HStack {
                Label(
                    String(format: "time.investment.streak.format".localized(), summary.streak),
                    systemImage: "flame.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(summary.streak > 0 ? .orange : .secondary)
                Spacer()
                Text(
                    String(
                        format: "time.investment.since.format".localized(),
                        subject.startDate.formatted(date: .abbreviated, time: .omitted)
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: DesignToken.Spacing.medium) {
                Image(systemName: subject.symbolName)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(themeColor)
                    .frame(width: 44, height: 44)
                    .background(themeColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: DesignToken.Spacing.tiny) {
                    Text(subject.name)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text("\(children.count) " + "time.investment.subprojects".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: DesignToken.Spacing.small)

                Text(TimeInvestmentFormatter.hoursBadge(seconds: summary.totalSeconds))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(subject.theme == .sunshine ? .black : .white)
                    .padding(.horizontal, DesignToken.Spacing.medium)
                    .padding(.vertical, DesignToken.Spacing.small)
                    .background(themeColor, in: RoundedRectangle(cornerRadius: DesignToken.CornerRadius.medium))
                    .contentTransition(.numericText())
            }

            HStack {
                NavigationLink {
                    TimeInvestmentProjectDetailView(
                        subject: subject,
                        viewModel: viewModel,
                        onEditSession: { presentedSheet = .session($0) }
                    )
                } label: {
                    Label("time.investment.details".localized(), systemImage: "chart.bar.xaxis")
                }
                .font(.subheadline.weight(.semibold))

                Spacer()

                Menu {
                    Button {
                        presentedSheet = .subTask(
                            subjectID: subject.id,
                            parentID: nil,
                            editing: nil
                        )
                    } label: {
                        Label("time.investment.addSubproject".localized(), systemImage: "plus")
                    }
                    Button {
                        presentedSheet = .subject(subject)
                    } label: {
                        Label("Edit".localized(), systemImage: "pencil")
                    }
                    Button {
                        viewModel.archiveSubject(subject.id)
                    } label: {
                        Label("time.investment.archive".localized(), systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("More".localized())

                if !children.isEmpty {
                    Button {
                        animate {
                            if expanded {
                                expandedSubjects.remove(subject.id)
                            } else {
                                expandedSubjects.insert(subject.id)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(
                        expanded
                            ? "time.investment.collapse".localized()
                            : "time.investment.expand".localized()
                    )
                }
            }

            if expanded {
                VStack(spacing: DesignToken.Spacing.small) {
                    ForEach(children) { child in
                        subTaskRow(child, depth: 1, themeColor: themeColor)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
        .accessibilityElement(children: .contain)
    }

    private func subTaskRow(_ task: SubTask, depth: Int, themeColor: Color) -> AnyView {
        let children = viewModel.children(of: task.id, subjectID: task.subjectID)
        let expanded = expandedSubTasks.contains(task.id)

        return AnyView(VStack(spacing: DesignToken.Spacing.small) {
            HStack(spacing: DesignToken.Spacing.small) {
                Rectangle()
                    .fill(themeColor.opacity(0.35))
                    .frame(width: 3)
                    .clipShape(Capsule())
                Image(systemName: depth == 1 ? "arrow.turn.down.right" : "circle.fill")
                    .scaledFont(size: depth == 1 ? 12 : 6)
                    .foregroundStyle(themeColor)
                    .frame(width: 18)
                Text(task.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer()
                Text(
                    TimeInvestmentFormatter.compactDuration(
                        seconds: viewModel.totalSeconds(for: .subTask(task.id))
                    )
                )
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(themeColor)
                Menu {
                    if depth < 2 {
                        Button {
                            presentedSheet = .subTask(
                                subjectID: task.subjectID,
                                parentID: task.id,
                                editing: nil
                            )
                        } label: {
                            Label("time.investment.addSubproject".localized(), systemImage: "plus")
                        }
                    }
                    Button {
                        presentedSheet = .subTask(
                            subjectID: task.subjectID,
                            parentID: task.parentSubTaskID,
                            editing: task
                        )
                    } label: {
                        Label("Edit".localized(), systemImage: "pencil")
                    }
                    Button {
                        viewModel.archiveSubTask(task.id)
                    } label: {
                        Label("time.investment.archive".localized(), systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 34, height: 44)
                }
                if !children.isEmpty {
                    Button {
                        animate {
                            if expanded {
                                expandedSubTasks.remove(task.id)
                            } else {
                                expandedSubTasks.insert(task.id)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .frame(width: 34, height: 44)
                    }
                    .accessibilityLabel("a11y.toggleSubtasks".localized())
                }
            }
            .padding(.leading, CGFloat(depth - 1) * DesignToken.Spacing.large)

            if expanded {
                ForEach(children) { child in
                    subTaskRow(child, depth: depth + 1, themeColor: themeColor)
                }
            }
        })
    }

    @ViewBuilder
    private func sheetView(_ sheet: TimeInvestmentSheet) -> some View {
        switch sheet {
        case .subject(let editing):
            TimeInvestmentSubjectEditor(
                editing: editing,
                nextSortOrder: viewModel.projects.count,
                onSave: viewModel.saveSubject
            )
        case .subTask(let subjectID, let parentID, let editing):
            SubTaskEditor(
                subjectID: subjectID,
                parentID: parentID,
                editing: editing,
                allSubTasks: viewModel.subTasks,
                onSave: viewModel.saveSubTask
            )
        case .reward:
            GoalRewardEditor(
                viewModel: viewModel,
                onSave: viewModel.saveReward
            )
        case .session(let existing):
            StudySessionEditor(
                existing: existing,
                viewModel: viewModel,
                onSave: viewModel.saveSession
            )
        case .unassigned:
            UnassignedSessionsView(viewModel: viewModel)
        }
    }

    private func animate(_ changes: () -> Void) {
        if reduceMotion {
            changes()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 1), changes)
        }
    }
}

private struct RewardGoalCard: View {
    let rewards: [GoalReward]
    let progress: (GoalReward) -> Double
    let targetName: (InvestmentTarget) -> String
    let onAdd: () -> Void
    let onDelete: (UUID) -> Void

    private var featured: GoalReward? {
        rewards
            .filter { $0.unlockedAt == nil }
            .sorted { (1 - progress($0)) < (1 - progress($1)) }
            .first
            ?? rewards.sorted { ($0.unlockedAt ?? .distantPast) > ($1.unlockedAt ?? .distantPast) }.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            HStack {
                Text("🎁 " + "time.investment.myRewards".localized())
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                Button("time.investment.addReward".localized() + " +", action: onAdd)
                    .font(.subheadline.weight(.semibold))
            }

            if let reward = featured {
                HStack(spacing: DesignToken.Spacing.medium) {
                    Image(systemName: reward.symbolName)
                        .font(.title2)
                        .foregroundStyle(reward.unlockedAt == nil ? .purple : .green)
                        .frame(width: 46, height: 46)
                        .background(
                            (reward.unlockedAt == nil ? Color.purple : .green).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: DesignToken.CornerRadius.medium)
                        )
                    VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reward.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(targetName(reward.target))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: reward.unlockedAt == nil ? "lock.fill" : "checkmark.seal.fill")
                                .foregroundStyle(
                                    reward.unlockedAt == nil ? Color.secondary : Color.green
                                )
                        }
                        if reward.unlockedAt == nil {
                            ProgressView(value: progress(reward))
                                .tint(.purple)
                            Text(
                                String(
                                    format: "time.investment.reward.progress".localized(),
                                    Int((progress(reward) * 100).rounded())
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("time.investment.reward.unlocked".localized())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        onDelete(reward.id)
                    } label: {
                        Label("Delete".localized(), systemImage: "trash")
                    }
                }
            } else {
                HStack(spacing: DesignToken.Spacing.medium) {
                    Image(systemName: "gift")
                        .font(.title2)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("time.investment.reward.empty.title".localized())
                            .font(.subheadline.weight(.semibold))
                        Text("time.investment.reward.empty.description".localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
    }
}

private struct RewardUnlockToast: View {
    let reward: GoalReward
    let dismiss: () -> Void
    @State private var didTriggerFeedback = false

    var body: some View {
        Button(action: dismiss) {
            HStack(spacing: DesignToken.Spacing.medium) {
                Image(systemName: reward.symbolName)
                    .font(.title2)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("time.investment.reward.unlocked".localized())
                        .font(.headline)
                    Text(reward.title)
                        .font(.subheadline)
                }
                Spacer()
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(DesignToken.Spacing.large)
            .frame(maxWidth: 440)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignToken.CornerRadius.large))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignToken.Spacing.large)
        .onAppear {
            guard !didTriggerFeedback else { return }
            didTriggerFeedback = true
            Haptics.success()
        }
    }
}

private struct TimeInvestmentProjectDetailView: View {
    let subject: TimeInvestmentSubject
    @ObservedObject var viewModel: TimeInvestmentViewModel
    let onEditSession: (StudySession) -> Void

    private var target: InvestmentTarget { .subject(subject.id) }
    private var sessions: [StudySession] {
        viewModel.sessions(for: target)
    }
    private var todaySeconds: Int {
        sessions.filter { Calendar.current.isDateInToday($0.startDate) }
            .reduce(0) { $0 + $1.durationSeconds }
    }
    private var weekSeconds: Int {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return sessions.filter { $0.startDate >= start }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    detailMetric(
                        TimeInvestmentFormatter.hoursBadge(seconds: viewModel.totalSeconds(for: target)),
                        "time.investment.total".localized()
                    )
                    detailMetric(
                        TimeInvestmentFormatter.compactDuration(seconds: todaySeconds),
                        "time.investment.today".localized()
                    )
                }
                HStack {
                    detailMetric(
                        TimeInvestmentFormatter.compactDuration(seconds: weekSeconds),
                        "time.investment.thisWeek".localized()
                    )
                    detailMetric(
                        "\(viewModel.streak(for: target))",
                        "time.investment.streakDays".localized()
                    )
                }
            }
            Section("time.investment.subprojects".localized()) {
                ForEach(viewModel.subTasks.filter { $0.subjectID == subject.id }) { task in
                    HStack {
                        Text(task.name)
                        Spacer()
                        Text(
                            TimeInvestmentFormatter.compactDuration(
                                seconds: viewModel.totalSeconds(for: .subTask(task.id))
                            )
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
            Section("time.investment.history".localized()) {
                if sessions.isEmpty {
                    Text("time.investment.history.empty".localized())
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { session in
                        Button {
                            onEditSession(session)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                                        .foregroundStyle(.primary)
                                    Text(viewModel.displayName(for: session.investmentTarget ?? target))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(TimeInvestmentFormatter.compactDuration(seconds: session.durationSeconds))
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.deleteSession(session.id)
                            } label: {
                                Label("Delete".localized(), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(subject.name)
    }

    private func detailMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
