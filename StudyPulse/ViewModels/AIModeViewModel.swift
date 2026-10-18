//
//  AIModeViewModel.swift
//  StudyPulse
//
//  Drives the full-screen AI Mode: scene routing, the active conversation,
//  streaming generation (stop / retry / local-analysis fallback), persisted
//  history and search.
//

import Foundation
import SwiftUI
import UIKit
import os

enum AIModeScene: Hashable {
    case welcome
    case chat
    case data(AIDataDomain)
}

struct AIHistoryGroup: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let conversations: [AIConversation]
}

@MainActor
@Observable
final class AIModeViewModel {

    // MARK: Dependencies

    private let container: RepositoryContainer
    let dataViewModel: AIModeDataViewModel
    private var repo: any AIConversationRepository { container.aiConversationRepo }

    // MARK: UI state

    var scene: AIModeScene = .welcome
    var drawerOpen = false {
        didSet { if drawerOpen { showingReasoningPicker = false } }
    }
    /// Survives switching to a data page or the drawer.
    var draft = ""
    private(set) var pendingReferences: [AIDataReference] = []
    var searchText = ""
    var needsHealthConsent = false

    private(set) var conversation: AIConversation?
    private(set) var messages: [AIChatMessage] = []
    private(set) var isGenerating = false

    /// Whether the reasoning slider is showing over the composer.
    var showingReasoningPicker = false

    /// Reasoning stops the active model offers (Cloud off / auto / on, GPT-5 minimal…high, …).
    var reasoningProfile: AIReasoningProfile { container.envManager.aiModeReasoningProfile }

    /// The active model's remembered stop. Read from preferences, so Settings and AI Mode stay in sync.
    var reasoningLevel: AIReasoningLevel {
        get { container.envManager.aiModeReasoningLevel(for: reasoningProfile) }
        set { container.envManager.setAIModeReasoningLevel(newValue, for: reasoningProfile) }
    }

    /// Prompt strategy / data budget that follows from the reasoning stop.
    var answerMode: AIAnswerMode { reasoningLevel.answerMode }

    // MARK: Generation bookkeeping

    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var generationToken = UUID()
    @ObservationIgnored private var userStopped = false
    @ObservationIgnored private var lastPersist = Date.distantPast
    @ObservationIgnored private var consentRetryMessageID: UUID?

    // Output pacing: the model's text lands in `pacingTarget` as fast as it arrives, and `pacerTask` reveals it
    // into the message at a steady, readable rate so bursts of tokens never make the reply jump.
    @ObservationIgnored private var pacerTask: Task<Void, Never>?
    @ObservationIgnored private var pacingTarget = ""
    @ObservationIgnored private var pacingStreamEnded = false

    private static let persistInterval: TimeInterval = 1.5
    /// Seconds between reveals. Each reveal re-lays the Markdown out, so this is a trade between smoothness and cost.
    private static let pacerTick: Duration = .milliseconds(50)
    /// The slowest reveal, in characters per second, so a trickling stream still reads as writing.
    private static let pacerMinRate = 60.0
    /// The fastest reveal, so a huge burst is spread out instead of dumped.
    private static let pacerMaxRate = 500.0
    /// The backlog is worked off over about this many seconds, so the pace stays near constant instead of
    /// racing through a burst and then crawling.
    private static let pacerCatchUpSeconds = 4.0
    /// Once the model is done, whatever is left is revealed within about this many seconds.
    private static let pacerDrainSeconds = 2.5

    init(container: RepositoryContainer, hrvManager: HealthKitManager) {
        self.container = container
        self.dataViewModel = AIModeDataViewModel.makeDefault(container: container, hrvManager: hrvManager)
    }

    static func makeDefault(container: RepositoryContainer, hrvManager: HealthKitManager) -> AIModeViewModel {
        AIModeViewModel(container: container, hrvManager: hrvManager)
    }

    // MARK: Derived

    var isConfigured: Bool { container.envManager.llmConfig.isConfigured }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    var phaseName: String? { container.phaseRepo.activePhase?.name }

    var activePhaseId: UUID? { container.envManager.activePhaseId }

    var userName: String { container.profileRepo.profile.username }

    /// History grouped by recency: today / yesterday / last 7 days / earlier.
    var historyGroups: [AIHistoryGroup] {
        let items = repo.search(searchText)
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        var buckets: [(String, String, [AIConversation])] = [
            ("today", "aiMode.history.today", []),
            ("yesterday", "aiMode.history.yesterday", []),
            ("week", "aiMode.history.week", []),
            ("earlier", "aiMode.history.earlier", []),
        ]
        for item in items {
            let index: Int
            if item.updatedAt >= today { index = 0 }
            else if item.updatedAt >= yesterday { index = 1 }
            else if item.updatedAt >= weekAgo { index = 2 }
            else { index = 3 }
            buckets[index].2.append(item)
        }
        return buckets.filter { !$0.2.isEmpty }.map { AIHistoryGroup(id: $0.0, titleKey: $0.1, conversations: $0.2) }
    }

    var hasHistory: Bool { !repo.conversations.isEmpty }

    // MARK: Navigation

    func openDrawer() { drawerOpen = true }
    func closeDrawer() { drawerOpen = false }

    func showData(_ domain: AIDataDomain) {
        dataViewModel.recompute()
        scene = .data(domain)
        drawerOpen = false
    }

    func backToChat() {
        scene = conversation == nil ? .welcome : .chat
    }

    func newConversation() {
        stopAndPersist()
        conversation = nil
        messages = []
        pendingReferences = []
        scene = .welcome
        drawerOpen = false
    }

    func open(_ id: UUID) {
        guard let target = repo.conversations.first(where: { $0.id == id }) else { return }
        stopAndPersist()
        conversation = target
        messages = repo.messages(for: id)
        pendingReferences = []
        scene = .chat
        drawerOpen = false
    }

    func rename(_ id: UUID, title: String) {
        repo.rename(id, title: title)
        if conversation?.id == id { conversation = repo.conversations.first { $0.id == id } }
    }

    func delete(_ id: UUID) {
        if conversation?.id == id { newConversation() }
        repo.delete(id)
    }

    // MARK: References

    func attach(_ reference: AIDataReference) {
        let duplicate = pendingReferences.contains {
            $0.domain == reference.domain && $0.scope == reference.scope && $0.subject == reference.subject
        }
        if !duplicate { pendingReferences.append(reference) }
    }

    func removeReference(_ id: UUID) {
        pendingReferences.removeAll { $0.id == id }
    }

    /// "Chat about my …": carries the data page's current scope back into the conversation.
    func askAbout(_ domain: AIDataDomain, scope: AIDateScope = .last30Days, scopeLabel: String, subject: String? = nil) {
        attach(AIDataReference(
            domain: domain,
            scopeLabel: scopeLabel,
            subject: subject,
            scope: scope,
            phaseId: container.envManager.activePhaseId
        ))
        scene = conversation == nil ? .welcome : .chat
    }

    // MARK: Sending

    func send(_ override: String? = nil) {
        let text = (override ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        let now = Date()
        var current = conversation ?? AIConversation(
            title: AIModeLLM.title(from: text),
            phaseId: container.envManager.activePhaseId,
            createdAt: now,
            updatedAt: now
        )
        if conversation == nil {
            repo.create(current)
        } else if current.title.isEmpty, !current.isTitleUserEdited {
            current.title = AIModeLLM.title(from: text)
        }
        current.updatedAt = now
        repo.update(current)
        conversation = current

        let user = AIChatMessage(
            conversationID: current.id,
            orderIndex: messages.count,
            role: .user,
            content: text,
            answerMode: answerMode,
            reasoningLevel: reasoningLevel,
            references: pendingReferences,
            createdAt: now
        )
        let assistant = AIChatMessage(
            conversationID: current.id,
            orderIndex: messages.count + 1,
            role: .assistant,
            content: "",
            status: .streaming,
            answerMode: answerMode,
            reasoningLevel: reasoningLevel,
            createdAt: now.addingTimeInterval(0.001)
        )
        messages.append(user)
        messages.append(assistant)
        repo.upsertMessage(user)
        repo.upsertMessage(assistant)

        draft = ""
        pendingReferences = []
        scene = .chat
        generate(assistantID: assistant.id)
    }

    func stop() {
        guard isGenerating else { return }
        userStopped = true
        generationTask?.cancel()
    }

    func retry(_ messageID: UUID) {
        guard !isGenerating,
              let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].role == .assistant,
              index > 0, messages[index - 1].role == .user else { return }
        var message = messages[index]
        message.content = ""
        message.status = .streaming
        message.origin = .model
        message.errorDescription = nil
        message.followUps = []
        message.actions = []
        message.sources = []
        message.feedbackHelpful = nil
        message.answerMode = answerMode
        message.reasoningLevel = reasoningLevel
        messages[index] = message
        repo.upsertMessage(message)
        generate(assistantID: messageID)
    }

    /// Replaces a failed reply with the deterministic local analysis.
    func useLocalAnalysis(for messageID: UUID) {
        guard !isGenerating,
              let index = messages.firstIndex(where: { $0.id == messageID }),
              index > 0 else { return }
        applyLocalAnalysis(at: index, userMessage: messages[index - 1])
    }

    func retryAfterHealthConsent() {
        needsHealthConsent = false
        if let id = consentRetryMessageID {
            consentRetryMessageID = nil
            retry(id)
        }
    }

    func declineHealthConsent() {
        needsHealthConsent = false
        consentRetryMessageID = nil
    }

    // MARK: Message actions

    func toggleHelpful(_ messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].feedbackHelpful = messages[index].feedbackHelpful == true ? nil : true
        repo.upsertMessage(messages[index])
    }

    func copy(_ messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }) else { return }
        UIPasteboard.general.string = message.content
    }

    // MARK: Write proposals

    /// Writes one proposed grade / to-do through the same facade the manual forms use.
    func applyAction(_ actionID: UUID, in messageID: UUID) {
        mutateAction(actionID, in: messageID) { action in
            guard action.status == .pending || action.status == .failed else { return }
            switch action.kind {
            case .addGrade:
                guard let draft = action.grade else { return fail(&action) }
                let grade = Grade(
                    subject: draft.subject,
                    score: draft.score,
                    importance: draft.importance,
                    date: draft.date,
                    examName: draft.examName,
                    fullScore: draft.fullScore
                )
                container.addGrade(grade)
                action.recordID = grade.id
            case .addTask:
                guard let draft = action.task else { return fail(&action) }
                let task = TaskItem(
                    title: draft.title,
                    type: draft.type,
                    dueDate: draft.dueDate,
                    reminderDate: draft.dueDate,
                    subject: draft.subject,
                    importance: draft.importance,
                    notes: draft.notes
                )
                container.addTask(task, syncToReminders: false)
                action.recordID = task.id
            }
            action.status = .applied
            action.errorMessage = nil
            Haptics.success()
        }
    }

    func applyAllActions(in messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }) else { return }
        for action in message.actions where action.status == .pending {
            applyAction(action.id, in: messageID)
        }
    }

    func dismissAction(_ actionID: UUID, in messageID: UUID) {
        mutateAction(actionID, in: messageID) { action in
            if action.status == .pending || action.status == .failed { action.status = .dismissed }
        }
    }

    /// Removes the record an applied proposal created.
    func undoAction(_ actionID: UUID, in messageID: UUID) {
        mutateAction(actionID, in: messageID) { action in
            guard action.status == .applied, let recordID = action.recordID else { return }
            switch action.kind {
            case .addGrade:
                if let grade = container.gradeRepo.grades.first(where: { $0.id == recordID }) {
                    container.deleteGrade(grade)
                }
            case .addTask:
                if let task = container.taskRepo.taskItems.first(where: { $0.id == recordID }) {
                    container.deleteTask(task)
                }
            }
            action.status = .undone
            Haptics.selection()
        }
    }

    private func fail(_ action: inout AIProposedAction) {
        action.status = .failed
        action.errorMessage = "aiMode.action.error.invalid".localized()
    }

    private func mutateAction(_ actionID: UUID, in messageID: UUID, _ mutate: (inout AIProposedAction) -> Void) {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }),
              let actionIndex = messages[messageIndex].actions.firstIndex(where: { $0.id == actionID })
        else { return }
        var action = messages[messageIndex].actions[actionIndex]
        mutate(&action)
        messages[messageIndex].actions[actionIndex] = action
        repo.upsertMessage(messages[messageIndex])
    }

    // MARK: Generation

    private func generate(assistantID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }), index > 0 else { return }
        let userMessage = messages[index - 1]
        let history = Array(messages[..<index])
        let mode = messages[index].answerMode
        let level = messages[index].reasoningLevel ?? (mode == .quick ? .off : .high)

        dataViewModel.recompute()
        let config = container.envManager.llmConfig
        guard config.isConfigured else {
            applyLocalAnalysis(at: index, userMessage: userMessage)
            return
        }

        let snapshot = dataViewModel.snapshot
        let existing = dataViewModel.existingRecordIDs()
        let context = AIContextComposer.compose(
            userText: userMessage.content,
            references: userMessage.references,
            snapshot: snapshot,
            mode: mode,
            existingRecordIDs: existing
        )
        let locale = config.locale
        let actionContext = AIActionContext(subjects: container.subjectRepo.subjects)
        let prompt = AIModeLLM.makePrompt(
            history: history, context: context, mode: mode, locale: locale, actionContext: actionContext
        )
        let tuned = AIModeLLM.tuned(config, level: level)

        let token = UUID()
        generationToken = token
        userStopped = false
        isGenerating = true
        lastPersist = .distantPast
        pacingTarget = ""
        pacingStreamEnded = false
        startPacer(assistantID: assistantID, token: token)

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let final = try await LLMClient.shared.stream(
                    prompt: prompt, config: tuned, caller: AIModeLLM.caller
                ) { [weak self] accumulated in
                    self?.applyDelta(accumulated, assistantID: assistantID, token: token)
                }
                guard self.generationToken == token else { return }
                let parsed = AIModeResponseParser.parse(final, actionContext: actionContext)
                // Let the pacer finish writing what the model already said before the reply is sealed.
                self.pacingTarget = parsed.body
                self.pacingStreamEnded = true
                await self.pacerTask?.value
                guard self.generationToken == token else { return }
                self.finish(assistantID: assistantID) { message in
                    message.content = parsed.body
                    message.followUps = parsed.followUps
                    message.actions = parsed.actions
                    message.sources = context.sources
                    message.status = parsed.body.isEmpty ? .failed : .complete
                    message.modelName = tuned.isCloudProvider ? nil : tuned.model
                    if parsed.body.isEmpty {
                        message.errorDescription = LLMError.emptyResponse.errorDescription
                    }
                }
            } catch {
                guard self.generationToken == token else { return }
                self.handleFailure(error, assistantID: assistantID, context: context)
            }
        }
    }

    private func applyDelta(_ accumulated: String, assistantID: UUID, token: UUID) {
        guard generationToken == token,
              let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        let parsed = AIModeResponseParser.parse(accumulated)
        pacingTarget = parsed.body
        messages[index].followUps = parsed.followUps
    }

    /// If a reveal would stop inside an unfinished `$…$` / `$$…$$` formula, carries it on to the closing delimiter
    /// (when that is close by), so a formula appears whole instead of as raw source for a moment.
    private static func mathSafeCount(in text: String, revealing count: Int) -> Int {
        let chars = Array(text)
        guard count < chars.count else { return chars.count }
        var open: Int? // 1 inline, 2 display
        var i = 0
        while i < count {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == "$" {
                let double = i + 1 < chars.count && chars[i + 1] == "$"
                let kind = double ? 2 : 1
                if open == nil { open = kind } else if open == kind { open = nil }
                i += double ? 2 : 1
                continue
            }
            i += 1
        }
        guard let kind = open else { return count }
        var j = max(count, i)
        let limit = min(chars.count, count + 160)
        while j < limit {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == "$" {
                if kind == 2 { return j + 1 < chars.count && chars[j + 1] == "$" ? j + 2 : count }
                return j + 1
            }
            j += 1
        }
        return count
    }

    /// Reveals `pacingTarget` into the message a few characters at a time. The rate follows the backlog, so a slow
    /// model is shown as it writes, a fast one is smoothed out, and a burst never leaves the display far behind.
    private func startPacer(assistantID: UUID, token: UUID) {
        pacerTask?.cancel()
        pacerTask = Task { [weak self] in
            var revealed = 0
            var carry = 0.0
            var rate = Self.pacerMinRate
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pacerTick)
                guard let self, !Task.isCancelled, self.generationToken == token,
                      let index = self.messages.firstIndex(where: { $0.id == assistantID }) else { return }
                let now = ContinuousClock.now
                let gap = now - last
                let elapsed = min(max(Double(gap.components.seconds) + Double(gap.components.attoseconds) / 1e18, 0), 0.25)
                last = now

                let target = self.pacingTarget
                let total = target.count
                // Text can shrink when the parser hides a half-written block; never run past the target.
                revealed = min(revealed, total)
                let backlog = total - revealed
                if backlog > 0 {
                    var wanted = Double(backlog) / Self.pacerCatchUpSeconds
                    if self.pacingStreamEnded { wanted = max(wanted, Double(backlog) / Self.pacerDrainSeconds) }
                    wanted = min(max(wanted, Self.pacerMinRate), Self.pacerMaxRate)
                    // Ease toward the wanted rate so the speed never lurches between ticks.
                    rate += (wanted - rate) * min(1, elapsed * 4)
                    carry += rate * elapsed
                    let step = min(Int(carry), backlog)
                    if step > 0 {
                        carry -= Double(step)
                        revealed = Self.mathSafeCount(in: target, revealing: revealed + step)
                        self.messages[index].content = String(target.prefix(revealed))
                        let stamp = Date()
                        if stamp.timeIntervalSince(self.lastPersist) >= Self.persistInterval {
                            self.lastPersist = stamp
                            self.repo.upsertMessage(self.messages[index])
                        }
                    }
                } else {
                    carry = 0
                    if self.pacingStreamEnded { return }
                }
            }
        }
    }

    private func handleFailure(_ error: Error, assistantID: UUID, context: AIContextPayload) {
        if userStopped || error is CancellationError {
            finish(assistantID: assistantID) { message in
                message.status = .stopped
                message.sources = context.sources
            }
            return
        }
        let llmError = error as? LLMError
        if llmError == .healthDataConsentRequired {
            consentRetryMessageID = assistantID
            needsHealthConsent = true
        }
        let description = llmError?.errorDescription ?? error.localizedDescription
        Log.llm.error("AIMode generation failed: \(description, privacy: .public)")
        finish(assistantID: assistantID) { message in
            message.status = .failed
            message.errorDescription = description
        }
    }

    private func finish(assistantID: UUID, _ mutate: (inout AIChatMessage) -> Void) {
        defer {
            pacerTask?.cancel()
            pacerTask = nil
            isGenerating = false
            generationTask = nil
            userStopped = false
        }
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        var message = messages[index]
        mutate(&message)
        messages[index] = message
        repo.upsertMessage(message)
        touchConversation()
    }

    private func applyLocalAnalysis(at index: Int, userMessage: AIChatMessage) {
        dataViewModel.recompute()
        let result = AIModeLocalAnalyzer.analyze(
            userText: userMessage.content,
            references: userMessage.references,
            snapshot: dataViewModel.snapshot
        )
        var message = messages[index]
        message.content = result.markdown
        message.origin = .localAnalysis
        message.status = .complete
        message.sources = result.sources
        message.followUps = result.followUps
        message.actions = []
        message.errorDescription = nil
        message.modelName = nil
        messages[index] = message
        repo.upsertMessage(message)
        touchConversation()
    }

    /// Cancels any in-flight generation and saves what has been received as `stopped`.
    private func stopAndPersist() {
        guard isGenerating else { return }
        generationToken = UUID() // ignore late callbacks
        generationTask?.cancel()
        generationTask = nil
        pacerTask?.cancel()
        pacerTask = nil
        isGenerating = false
        userStopped = false
        for index in messages.indices where messages[index].status == .streaming {
            messages[index].status = .stopped
            repo.upsertMessage(messages[index])
        }
        touchConversation()
    }

    private func touchConversation() {
        guard var current = conversation else { return }
        current.updatedAt = Date()
        repo.update(current)
        conversation = current
    }
}
