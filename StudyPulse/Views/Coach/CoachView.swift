import SwiftUI

struct CoachView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: CoachViewModel
    @State private var showingGoalForm = false
    @State private var editingGoal: CoachGoal?
    @State private var openedGoal: CoachGoal?
    @State private var standaloneChats: [CoachChat] = []
    @State private var openedStandaloneChat: CoachChat?
    @State private var showingArchivedStandaloneChats = false
    @State private var showingHistory = false
    @State private var showingProposalReview = false

    init(container: RepositoryContainer) {
        _viewModel = State(initialValue: CoachViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            Group {
                if !container.envManager.preferences.coachEnabled || !container.envManager.preferences.llmEnabled {
                    ContentUnavailableView("AI Coach is disabled".localized(), systemImage: "brain",
                                           description: Text("Enable Coach and configure your BYOK LLM in Settings → LLM.".localized()))
                } else if viewModel.goals.isEmpty && standaloneChats.isEmpty {
                    emptyView
                } else {
                    goalList
                }
            }
            .navigationTitle("AI Coach".localized())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingGoalForm = true } label: {
                            Label("New Goal".localized(), systemImage: "target")
                        }
                        Button { createStandaloneChat() } label: {
                            Label("New Conversation".localized(), systemImage: "bubble.left.and.bubble.right")
                        }
                        if viewModel.proposal != nil {
                            Button { showingProposalReview = true } label: {
                                Label("Review current proposal".localized(), systemImage: "checklist")
                            }
                        }
                    } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(item: $openedGoal) { goal in
                CoachChatListView(goal: goal, container: container)
            }
            .navigationDestination(item: $openedStandaloneChat) { chat in
                CoachConversationView(goal: nil, chat: chat, container: container)
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
        }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView("Create your first goal".localized(), systemImage: "target",
                               description: Text("AI Coach needs a measurable goal before it can coach you.".localized()))
            .overlay(alignment: .bottom) {
                Button("Create Goal".localized()) { showingGoalForm = true }
                    .buttonStyle(.borderedProminent).padding(.bottom, 32)
            }
    }

    private var goalList: some View {
        List {
            coachSummarySection
            standaloneSection
            goalSection(.active, title: "Active Goals")
            goalSection(.paused, title: "Paused Goals")
            goalSection(.achieved, title: "Completed Goals")
            goalSection(.abandoned, title: "Abandoned Goals")
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private var coachSummarySection: some View {
        if let goal = viewModel.selectedGoal {
            Section("Current analysis".localized()) {
                coachAnalysisCard(goal: goal)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func coachAnalysisCard(goal: CoachGoal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.title).font(.headline)
                    Text(String(format: "Target date: %@".localized(), goal.targetDate.formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    if viewModel.isLoading { ProgressView() }
                    else { Label("Refresh".localized(), systemImage: "arrow.clockwise") }
                }
                .buttonStyle(.borderless).tint(.blue).disabled(viewModel.isLoading)
            }

            Divider().padding(.vertical, 16)

            if let analysis = viewModel.analysis {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: "Weighted prediction: %.1f".localized(), analysis.weightedPredicted))
                        .font(.title3.weight(.medium))
                    Text(String(format: "Success probability: %.0f%%".localized(), analysis.successProbability * 100))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(goal.subjects.enumerated()), id: \.element.id) { index, subject in
                            let share = goal.contribution(of: subject)
                            HStack(spacing: 10) {
                                Text(subject.subject).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(String(format: "%.0f%%".localized(), share * 100))
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 11)
                            if index < goal.subjects.count - 1 { Divider() }
                        }
                    }
                }
                Divider().padding(.top, 4)
                Button("View Coach history".localized()) { showingHistory = true }
                    .font(.body).foregroundStyle(.blue).padding(.top, 14)
            } else {
                Text("Refresh Coach to generate an analysis.".localized())
                    .foregroundStyle(.secondary).padding(.vertical, 8)
            }

            if viewModel.proposal != nil {
                Divider().padding(.vertical, 14)
                HStack {
                    Label("Proposal ready".localized(), systemImage: "sparkles")
                    Spacer()
                    Button("Review".localized()) { showingProposalReview = true }
                }
                Button("Regenerate".localized()) { Task { await viewModel.regenerateProposal() } }
                    .font(.caption).padding(.top, 8)
            }
        }
        .padding(20)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private var standaloneSection: some View {
        let visible = standaloneChats.filter { showingArchivedStandaloneChats ? $0.isArchived : !$0.isArchived }
        Section {
            if visible.isEmpty {
                Button { createStandaloneChat() } label: {
                    Label("New independent conversation".localized(), systemImage: "plus.bubble")
                }
            } else {
                ForEach(visible) { chat in
                    Button { openedStandaloneChat = chat } label: { standaloneChatRow(chat) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleteStandaloneChat(chat) } label: {
                                Label("Delete".localized(), systemImage: "trash")
                            }
                            Button { toggleStandaloneArchive(chat) } label: {
                                Label(chat.isArchived ? "Unarchive".localized() : "Archive".localized(), systemImage: "archivebox")
                            }.tint(.orange)
                        }
                        .contextMenu {
                            Button { toggleStandaloneArchive(chat) } label: {
                                Label(chat.isArchived ? "Unarchive".localized() : "Archive".localized(), systemImage: "archivebox")
                            }
                            Button(role: .destructive) { deleteStandaloneChat(chat) } label: {
                                Label("Delete".localized(), systemImage: "trash")
                            }
                        }
                }
            }
        } header: {
            HStack {
                Text("Independent Conversations".localized())
                Spacer()
                Button { showingArchivedStandaloneChats.toggle() } label: {
                    Image(systemName: showingArchivedStandaloneChats ? "archivebox.fill" : "archivebox")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showingArchivedStandaloneChats ? "Show active conversations".localized() : "Show archived conversations".localized())
            }
        }
    }

    private func standaloneChatRow(_ chat: CoachChat) -> some View {
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

    private func refresh() {
        viewModel.refreshGoals()
        standaloneChats = container.coachRepo.standaloneChats()
    }

    private func createStandaloneChat() {
        let chat = CoachChat(title: "New conversation".localized())
        container.coachRepo.addChat(chat)
        refresh()
        openedStandaloneChat = chat
    }

    private func toggleStandaloneArchive(_ chat: CoachChat) {
        var updated = chat
        updated.isArchived.toggle()
        updated.updatedAt = Date()
        container.coachRepo.updateChat(updated)
        refresh()
    }

    private func deleteStandaloneChat(_ chat: CoachChat) {
        container.coachRepo.deleteChat(chat)
        refresh()
        if openedStandaloneChat?.id == chat.id { openedStandaloneChat = nil }
    }

    @ViewBuilder
    private func goalSection(_ status: CoachGoalStatus, title: String) -> some View {
        let items = viewModel.goals.filter { $0.status == status }
        if !items.isEmpty {
            Section(title.localized()) {
                ForEach(items) { goal in
                    Button { openedGoal = goal } label: { goalRow(goal) }
                        .buttonStyle(.plain)
                        .contextMenu { goalActions(goal) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { viewModel.deleteGoal(goal) } label: { Label("Delete".localized(), systemImage: "trash") }
                        }
                }
            }
        }
    }

    private func goalRow(_ goal: CoachGoal) -> some View {
        HStack(spacing: 12) {
            Image(systemName: goal.status == .active ? "target" : "circle.dashed")
                .font(.title3).foregroundStyle(goal.status == .active ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title).font(.headline).foregroundStyle(.primary)
                Text(String(format: "Target date: %@".localized(), goal.targetDate.formatted(date: .abbreviated, time: .omitted)))
                    .font(.caption).foregroundStyle(.secondary)
                if let last = container.coachRepo.latestMessage(for: goal.id) {
                    Text(last.content).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func goalActions(_ goal: CoachGoal) -> some View {
        Button { editingGoal = goal } label: { Label("Edit goal".localized(), systemImage: "pencil") }
        if goal.status == .active { Button { viewModel.setStatus(.paused, for: goal) } label: { Label("Pause".localized(), systemImage: "pause") } }
        if goal.status == .paused { Button { viewModel.setStatus(.active, for: goal) } label: { Label("Resume".localized(), systemImage: "play") } }
        if goal.status == .active || goal.status == .paused { Button { viewModel.setStatus(.achieved, for: goal) } label: { Label("Mark complete".localized(), systemImage: "checkmark.circle") } }
        if goal.status != .abandoned { Button(role: .destructive) { viewModel.setStatus(.abandoned, for: goal) } label: { Label("Abandon".localized(), systemImage: "xmark.circle") } }
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
