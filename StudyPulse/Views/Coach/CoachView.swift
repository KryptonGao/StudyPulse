import SwiftUI

/// 打开的一段对话(可选绑定目标)。
/// An opened conversation (optionally bound to a goal).
private struct OpenedCoachChat: Hashable {
    let goal: CoachGoal?
    let chat: CoachChat
    var initialPrompt: String? = nil
}

/// 「教练室」:当前目标 → 今天的计划 → 随时开口问 → 对话 → 其他目标 → 额度。
/// The coach room: current goal, today's plan, ask anything, conversations, other goals, quota.
struct CoachView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.detailPane) private var pane
    @State private var viewModel: CoachViewModel
    @State private var showingGoalForm = false
    @State private var editingGoal: CoachGoal?
    @State private var openedGoal: CoachGoal?
    @State private var openedChat: OpenedCoachChat?
    @State private var showingArchived = false
    @State private var otherStatus: CoachGoalStatus = .paused
    @State private var showingHistory = false
    @State private var showingProposalReview = false
    /// 触发刷新用的计数(对话 / 目标变更后 +1)/ Bumped to re-read chats after mutations.
    @State private var reloadTick = 0

    init(container: RepositoryContainer) {
        _viewModel = State(initialValue: CoachViewModel(container: container))
    }

    private var isEnabled: Bool {
        container.envManager.preferences.coachEnabled && container.envManager.preferences.llmEnabled
    }

    var body: some View {
        TwoPane(masterWidth: 400, placeholderTitle: "coach.v2.pane.placeholder".localized(), placeholderIcon: "bubble.left.and.bubble.right") {
            content
        }
    }

    private var content: some View {
        NavigationStack {
            Group {
                if !isEnabled {
                    ScrollView {
                        AIChatEmptyState(kind: .notConfigured())
                            .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
                    }
                } else if viewModel.goals.isEmpty && allChats.isEmpty {
                    firstRun
                } else {
                    room
                }
            }
            .background(Color(.systemGroupedBackground).opacity(DesignToken.Opacity.rootBackground))
            .containerBackground(.clear, for: .navigation)
            .navigationTitle("AI Coach".localized())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("View Coach history".localized())
                        .disabled(viewModel.selectedGoal == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingGoalForm = true } label: {
                            Label("New Goal".localized(), systemImage: "target")
                        }
                        Button { openNewChat(goal: nil, prompt: nil) } label: {
                            Label("New Conversation".localized(), systemImage: "bubble.left.and.bubble.right")
                        }
                    } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(item: $openedGoal) { goal in
                CoachChatListView(goal: goal, container: container)
            }
            .navigationDestination(item: $openedChat) { opened in
                CoachConversationView(goal: opened.goal, chat: opened.chat, container: container, initialPrompt: opened.initialPrompt)
            }
            .sheet(isPresented: $showingGoalForm) {
                CoachGoalEditorView { title, subjects, date, minutes, purpose, constraints, _, comprehensiveExamID in
                    openedGoal = viewModel.createGoal(title: title, subjects: subjects, targetDate: date,
                                                       dailyMinutes: minutes, purpose: purpose, constraints: constraints,
                                                       comprehensiveExamID: comprehensiveExamID)
                }
                .environment(container)
            }
            .sheet(item: $editingGoal) { goal in
                CoachGoalEditorView(existing: goal) { title, subjects, date, minutes, purpose, constraints, note, comprehensiveExamID in
                    viewModel.updateGoal(goal, title: title, subjects: subjects, targetDate: date,
                                         dailyMinutes: minutes, purpose: purpose, constraints: constraints,
                                         changeNote: note, comprehensiveExamID: comprehensiveExamID)
                }
                .environment(container)
            }
            .sheet(isPresented: $showingHistory) { CoachHistoryView(viewModel: viewModel) }
            .sheet(isPresented: $showingProposalReview) {
                if let proposal = viewModel.proposal {
                    CoachProposalReviewView(proposal: proposal) { items in viewModel.approveProposal(selectedItems: items) }
                }
            }
            .onAppear {
                refresh()
                Task { await viewModel.refreshIfNeeded() }
                Task { await container.envManager.refreshCloudQuota() }
                if let raw = UserDefaults.standard.string(forKey: "studyPulse.pendingCoachGoalID"),
                   let id = UUID(uuidString: raw), let goal = viewModel.goals.first(where: { $0.id == id }) {
                    viewModel.select(goal)
                    UserDefaults.standard.removeObject(forKey: "studyPulse.pendingCoachGoalID")
                    Task { await viewModel.refreshIfNeeded() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refresh()
                Task { await viewModel.refreshIfNeeded() }
                Task { await container.envManager.refreshCloudQuota() }
            }
        }
    }

    // MARK: - 数据 / Data

    /// 全部对话(目标内 + 独立),按更新时间倒序。`reloadTick` 让它在变更后重新读取。
    /// All conversations (goal-bound + standalone), newest first.
    private var allChats: [CoachChat] {
        _ = reloadTick
        return container.coachRepo.chats.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var visibleChats: [CoachChat] {
        allChats.filter { showingArchived ? $0.isArchived : !$0.isArchived }
    }

    private var archivedCount: Int { allChats.filter(\.isArchived).count }

    /// 今天由教练安排的任务 / Coach-scheduled tasks due today.
    private var todayPlan: [TaskItem] {
        container.taskRepo.taskItems
            .filter { $0.coachGoalId != nil && Calendar.current.isDateInToday($0.dueDate) }
            .filter { viewModel.selectedGoal == nil || $0.coachGoalId == viewModel.selectedGoal?.id }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private func goal(for chat: CoachChat) -> CoachGoal? {
        chat.goalID.flatMap { id in viewModel.goals.first { $0.id == id } }
    }

    // MARK: - 布局 / Layout

    private var firstRun: some View {
        ScrollView {
            VStack(spacing: DesignToken.Spacing.section) {
                ContentUnavailableView(
                    "Create your first goal".localized(),
                    systemImage: "target",
                    description: Text("AI Coach needs a measurable goal before it can coach you.".localized())
                )
                Button("Create Goal".localized()) { showingGoalForm = true }
                    .buttonStyle(.borderedProminent)
                askSection
                quotaRow
            }
            .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
            .padding(.vertical)
            .adaptiveMaxWidth(720)
        }
    }

    private var room: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.section) {
                if let goal = viewModel.selectedGoal { goalHero(goal) }
                if !todayPlan.isEmpty { todaySection }
                askSection
                conversationsSection
                otherGoalsSection
                quotaRow
            }
            .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
            .padding(.vertical)
            .adaptiveMaxWidth(720)
        }
        .refreshable { await container.envManager.refreshCloudQuota() }
    }

    // MARK: - 目标主卡 / Goal hero

    private func goalHero(_ goal: CoachGoal) -> some View {
        let days = TodoAgendaEngine.daysUntil(goal.targetDate)
        let probability = viewModel.analysis?.successProbability
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                MiniRing(progress: probability ?? 0, color: .purple, lineWidth: 7, size: 64,
                         label: probability.map { String(format: "%.0f%%", $0 * 100) })
                VStack(alignment: .leading, spacing: 4) {
                    Label("coach.v2.goal.active".localized(), systemImage: "target")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.purple)
                    Text(goal.title).font(.system(.title3, design: .rounded, weight: .bold)).lineLimit(2)
                    Text(String(format: "coach.v2.goal.meta".localized(),
                                goal.targetDate.formatted(.dateTime.month().day()), max(days, 0), goal.dailyAvailableMinutes))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let analysis = viewModel.analysis {
                Text(String(format: "coach.v2.goal.predicted".localized(), analysis.weightedPredicted))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text("Refresh Coach to generate an analysis.".localized())
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            if let proposal = viewModel.proposal {
                Button { showingProposalReview = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("coach.v2.proposal.title".localized()).font(.subheadline.weight(.semibold))
                            Text(String(format: "coach.v2.proposal.items".localized(), proposal.items.count))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Review".localized()).font(.subheadline.weight(.semibold)).foregroundStyle(.purple)
                        Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(.purple)
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.purple.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Button { continueChat(for: goal) } label: {
                    Label("coach.v2.goal.continue".localized(), systemImage: "bubble.left.and.bubble.right.fill")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                Button { editingGoal = goal } label: {
                    Text("coach.v2.goal.edit".localized()).frame(minHeight: 36)
                }
                .buttonStyle(.bordered)

                Button { Task { await viewModel.refresh() } } label: {
                    Group {
                        if viewModel.isLoading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .frame(minWidth: 24, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Refresh".localized())
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contextMenu { goalActions(goal) }
    }

    // MARK: - 今天的计划 / Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("coach.v2.today".localized())
            VStack(spacing: 0) {
                ForEach(Array(todayPlan.enumerated()), id: \.element.id) { index, task in
                    HStack(spacing: 12) {
                        Button {
                            var updated = task
                            updated.isCompleted.toggle()
                            container.taskRepo.update(updated, reminderResult: nil)
                            if updated.isCompleted { Haptics.success() } else { Haptics.impact(.light) }
                        } label: {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(task.isCompleted ? Color.green : Color(.tertiaryLabel))
                                .frame(minWidth: 32, minHeight: 32)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).font(.system(.body, design: .rounded, weight: .semibold))
                                .strikethrough(task.isCompleted)
                            Text([task.subject.isEmpty ? nil : task.subject.localized(),
                                  task.dueDate.formatted(date: .omitted, time: .shortened)]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .opacity(task.isCompleted ? 0.55 : 1)
                    if index < todayPlan.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: - 问教练 / Ask

    private var askSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("coach.v2.ask".localized())
            AIPromptChips(prompts: [
                "coach.v2.prompt.1".localized(),
                "coach.v2.prompt.2".localized(),
                "coach.v2.prompt.3".localized()
            ]) { prompt in openNewChat(goal: viewModel.selectedGoal, prompt: prompt) }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { openNewChat(goal: viewModel.selectedGoal, prompt: nil) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(.purple)
                    Text("coach.v2.ask.placeholder".localized()).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(.purple)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .aiGlass(Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 对话 / Conversations

    private var conversationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("coach.v2.conversations".localized())
                Spacer()
                if archivedCount > 0 || showingArchived {
                    Button {
                        withAnimation(.snappy) { showingArchived.toggle() }
                    } label: {
                        Text(showingArchived
                             ? "coach.v2.conversations.back".localized()
                             : String(format: "coach.v2.conversations.archived".localized(), archivedCount))
                            .font(.subheadline)
                    }
                }
            }
            if visibleChats.isEmpty {
                Text(showingArchived ? "No archived chats".localized() : "No messages yet".localized())
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleChats.enumerated()), id: \.element.id) { index, chat in
                        chatRow(chat)
                        if index < visibleChats.count - 1 { Divider().padding(.leading, 56) }
                    }
                }
                .padding(.horizontal, 14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func chatRow(_ chat: CoachChat) -> some View {
        let linked = goal(for: chat)
        let last = container.coachRepo.latestMessage(forChatID: chat.id)
        return Button {
            open(OpenedCoachChat(goal: linked, chat: chat))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: linked == nil ? "bubble.left.fill" : "brain.head.profile")
                    .foregroundStyle(chat.isArchived ? Color.secondary : Color.purple)
                    .frame(width: 32, height: 32)
                    .background((chat.isArchived ? Color.secondary : Color.purple).opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(linked.map { chat.title == "New chat" ? $0.title : chat.title } ?? chat.title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary).lineLimit(1)
                    Text(last?.content ?? "No messages yet".localized())
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(chat.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { toggleArchive(chat) } label: {
                Label(chat.isArchived ? "Unarchive".localized() : "Archive".localized(), systemImage: "archivebox")
            }
            Button(role: .destructive) { delete(chat) } label: { Label("Delete".localized(), systemImage: "trash") }
        }
    }

    // MARK: - 其他目标 / Other goals

    private var otherGoalsSection: some View {
        let groups: [(CoachGoalStatus, String)] = [
            (.paused, "coach.v2.other.paused".localized()),
            (.achieved, "coach.v2.other.achieved".localized()),
            (.abandoned, "coach.v2.other.abandoned".localized())
        ]
        let counts = Dictionary(uniqueKeysWithValues: groups.map { status, _ in
            (status, viewModel.goals.filter { $0.status == status }.count)
        })
        let total = counts.values.reduce(0, +)
        let extraActive = viewModel.goals.filter { $0.status == .active && $0.id != viewModel.selectedGoal?.id }
        return Group {
            if total + extraActive.count > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("coach.v2.other".localized())
                    if !extraActive.isEmpty {
                        goalRows(extraActive)
                    }
                    if total > 0 {
                        Picker("coach.v2.other".localized(), selection: $otherStatus) {
                            ForEach(groups, id: \.0) { status, title in
                                Text("\(title) \(counts[status] ?? 0)").tag(status)
                            }
                        }
                        .pickerStyle(.segmented)
                        let items = viewModel.goals.filter { $0.status == otherStatus }
                        if items.isEmpty {
                            Text("coach.v2.other.empty".localized())
                                .font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                        } else {
                            goalRows(items)
                        }
                    }
                }
            }
        }
    }

    private func goalRows(_ items: [CoachGoal]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, goal in
                Button { openedGoal = goal } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "target")
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.title).font(.system(.body, design: .rounded, weight: .semibold)).foregroundStyle(.primary)
                            Text(String(format: "Target date: %@".localized(), goal.targetDate.formatted(date: .abbreviated, time: .omitted)))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { goalActions(goal) }
                if index < items.count - 1 { Divider().padding(.leading, 44) }
            }
        }
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - 额度 / Quota

    @ViewBuilder
    private var quotaRow: some View {
        if container.envManager.isCloudSessionLoggedIn, let snapshot = container.envManager.preferences.cloudQuotaSnapshot {
            let unlimited = snapshot.isMonthlyUnlimited
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                Text("coach.v2.quota".localized()).font(.subheadline)
                if unlimited {
                    Spacer()
                    Text("Unlimited".localized()).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                } else {
                    ProgressView(value: snapshot.monthProgress).tint(snapshot.monthProgress >= 0.9 ? .orange : .purple)
                    Text("\(Int((snapshot.monthProgress * 100).rounded()))%")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - 小件 / Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func goalActions(_ goal: CoachGoal) -> some View {
        Button { editingGoal = goal } label: { Label("Edit goal".localized(), systemImage: "pencil") }
        if goal.status == .active { Button { viewModel.setStatus(.paused, for: goal) } label: { Label("Pause".localized(), systemImage: "pause") } }
        if goal.status == .paused { Button { viewModel.setStatus(.active, for: goal) } label: { Label("Resume".localized(), systemImage: "play") } }
        if goal.status == .active || goal.status == .paused { Button { viewModel.setStatus(.achieved, for: goal) } label: { Label("Mark complete".localized(), systemImage: "checkmark.circle") } }
        if goal.status != .abandoned { Button(role: .destructive) { viewModel.setStatus(.abandoned, for: goal) } label: { Label("Abandon".localized(), systemImage: "xmark.circle") } }
        Button(role: .destructive) { viewModel.deleteGoal(goal) } label: { Label("Delete".localized(), systemImage: "trash") }
    }

    // MARK: - 行为 / Actions

    private func refresh() {
        viewModel.refreshGoals()
        reloadTick += 1
    }

    /// 继续该目标最近的未封存对话;没有就新建。
    /// Continue the goal's latest active chat, or start a new one.
    private func continueChat(for goal: CoachGoal) {
        if let latest = container.coachRepo.chats(for: goal.id)
            .filter({ !$0.isArchived }).max(by: { $0.updatedAt < $1.updatedAt }) {
            open(OpenedCoachChat(goal: goal, chat: latest))
        } else {
            openNewChat(goal: goal, prompt: nil)
        }
    }

    /// 双栏时在右栏显示对话,否则 push。
    /// Show the conversation in the right pane in a two-pane, otherwise push it.
    private func open(_ opened: OpenedCoachChat) {
        if let pane {
            pane.show(id: opened.chat.id, content: AnyView(
                CoachConversationView(goal: opened.goal, chat: opened.chat, container: container, initialPrompt: opened.initialPrompt)
            ))
        } else {
            openedChat = opened
        }
    }

    private func openNewChat(goal: CoachGoal?, prompt: String?) {
        let chat = goal.map { CoachChat(goalID: $0.id) } ?? CoachChat(title: "New conversation".localized())
        container.coachRepo.addChat(chat)
        reloadTick += 1
        open(OpenedCoachChat(goal: goal, chat: chat, initialPrompt: prompt))
    }

    private func toggleArchive(_ chat: CoachChat) {
        var updated = chat
        updated.isArchived.toggle()
        updated.updatedAt = Date()
        container.coachRepo.updateChat(updated)
        reloadTick += 1
    }

    private func delete(_ chat: CoachChat) {
        container.coachRepo.deleteChat(chat)
        reloadTick += 1
        if openedChat?.chat.id == chat.id { openedChat = nil }
        if pane?.selectedID == AnyHashable(chat.id) { pane?.clear() }
    }
}

private struct CoachChatListView: View {
    @Environment(RepositoryContainer.self) private var container
    let goal: CoachGoal
    @State private var chats: [CoachChat] = []
    @State private var openedChat: CoachChat?
    @State private var showingArchived = false

    init(goal: CoachGoal, container: RepositoryContainer) {
        self.goal = goal
        _chats = State(initialValue: container.coachRepo.chats(for: goal.id))
    }

    var body: some View {
        List {
            let visible = chats.filter { showingArchived ? $0.isArchived : !$0.isArchived }
            if visible.isEmpty {
                ContentUnavailableView(showingArchived ? "No archived chats".localized() : "Start a new chat".localized(),
                                       systemImage: showingArchived ? "archivebox" : "bubble.left.and.bubble.right",
                                       description: Text("Create separate chats to explore different questions about this goal.".localized()))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(visible) { chat in
                    Button { openedChat = chat } label: { chatRow(chat) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { delete(chat) } label: { Label("Delete".localized(), systemImage: "trash") }
                            Button { toggleArchive(chat) } label: {
                                Label(chat.isArchived ? "Unarchive".localized() : "Archive".localized(), systemImage: "archivebox")
                            }.tint(.orange)
                        }
                        .contextMenu { chatActions(chat) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(goal.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingArchived.toggle() } label: {
                    Image(systemName: showingArchived ? "archivebox.fill" : "archivebox")
                }
                .accessibilityLabel(showingArchived ? "Show active chats".localized() : "Show archived chats".localized())
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { createChat() } label: { Image(systemName: "plus") }
            }
        }
        .navigationDestination(item: $openedChat) { chat in
            CoachConversationView(goal: goal, chat: chat, container: container)
        }
        .task { refresh() }
    }

    private func chatRow(_ chat: CoachChat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: chat.isArchived ? "archivebox" : "bubble.left.and.bubble.right.fill")
                .foregroundStyle(chat.isArchived ? Color.secondary : Color.teal)
            VStack(alignment: .leading, spacing: 4) {
                Text(chat.title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                if let last = container.coachRepo.latestMessage(forChatID: chat.id) {
                    Text(last.content).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("No messages yet".localized()).font(.caption).foregroundStyle(.secondary)
                }
                Text(chat.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func chatActions(_ chat: CoachChat) -> some View {
        Button { toggleArchive(chat) } label: {
            Label(chat.isArchived ? "Unarchive".localized() : "Archive".localized(), systemImage: "archivebox")
        }
        Button(role: .destructive) { delete(chat) } label: { Label("Delete".localized(), systemImage: "trash") }
    }

    private func refresh() { chats = container.coachRepo.chats(for: goal.id) }

    private func createChat() {
        let chat = CoachChat(goalID: goal.id)
        container.coachRepo.addChat(chat)
        refresh()
        openedChat = chat
    }

    private func toggleArchive(_ chat: CoachChat) {
        var updated = chat; updated.isArchived.toggle(); updated.updatedAt = Date()
        container.coachRepo.updateChat(updated); refresh()
    }

    private func delete(_ chat: CoachChat) {
        container.coachRepo.deleteChat(chat); refresh()
        if openedChat?.id == chat.id { openedChat = nil }
    }
}
