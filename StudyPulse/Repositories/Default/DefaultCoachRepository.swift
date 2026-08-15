import Foundation
import SwiftData
import os

@Observable @MainActor
final class DefaultCoachRepository: CoachRepository, PersistenceExecutorAttachable {
    private(set) var goals: [CoachGoal] = []
    private(set) var analyses: [CoachAnalysis] = []
    private(set) var proposals: [CoachProposal] = []
    private(set) var chats: [CoachChat] = []
    private(set) var messages: [CoachConversationMessage] = []
    private var context: ModelContext?
    @ObservationIgnored private var persistenceExecutor: PersistenceExecutor?

    func attachPersistenceExecutor(_ executor: PersistenceExecutor) {
        persistenceExecutor = executor
    }

    func loadAll(context: ModelContext) async {
        self.context = context
        let executor = persistenceExecutor ?? PersistenceExecutor(modelContainer: context.container)
        persistenceExecutor = executor
        do {
            let snapshots = try await executor.loadCoachSnapshots()
            goals = snapshots.goals
            analyses = snapshots.analyses
            proposals = snapshots.proposals
            chats = snapshots.chats
            messages = snapshots.messages
        } catch is CancellationError {
            Log.data.debug("CoachRepository startup load cancelled")
        } catch {
            goals = []
            analyses = []
            proposals = []
            chats = []
            messages = []
            Log.data.error("CoachRepository load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func addGoal(_ goal: CoachGoal) {
        guard !goals.contains(where: { $0.id == goal.id }) else { return }
        context?.insert(CoachGoalRecord(from: goal)); try? context?.save(); goals.append(goal)
    }

    func updateGoal(_ goal: CoachGoal) {
        if let i = goals.firstIndex(where: { $0.id == goal.id }) { goals[i] = goal }
        if let context, let record = (try? context.fetch(FetchDescriptor<CoachGoalRecord>(
            predicate: #Predicate { $0.id == goal.id }
        )))?.first {
            record.payload = (try? JSONEncoder().encode(goal)) ?? Data(); record.updatedAt = goal.updatedAt
            try? context.save()
        }
    }

    func deleteGoal(_ goal: CoachGoal) {
        chats(for: goal.id).forEach(deleteChat)
        deleteMessages(for: goal.id)
        if let context, let record = (try? context.fetch(FetchDescriptor<CoachGoalRecord>(
            predicate: #Predicate { $0.id == goal.id }
        )))?.first { context.delete(record); try? context.save() }
        goals.removeAll { $0.id == goal.id }
    }

    func chats(for goalID: UUID) -> [CoachChat] {
        chats.filter { $0.goalID == goalID }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func standaloneChats() -> [CoachChat] {
        chats.filter { $0.goalID == nil }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func addChat(_ chat: CoachChat) {
        guard !chats.contains(where: { $0.id == chat.id }) else { return }
        chats.append(chat)
        context?.insert(CoachChatRecord(from: chat)); try? context?.save()
    }

    func updateChat(_ chat: CoachChat) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) { chats[index] = chat }
        if let context, let record = (try? context.fetch(
            FetchDescriptor<CoachChatRecord>(predicate: #Predicate { $0.id == chat.id })
        ))?.first {
            record.goalID = chat.goalID
            record.title = chat.title
            record.isArchived = chat.isArchived
            record.createdAt = chat.createdAt
            record.payload = (try? JSONEncoder().encode(chat)) ?? Data(); record.updatedAt = chat.updatedAt
            try? context.save()
        }
    }

    func deleteChat(_ chat: CoachChat) {
        deleteMessages(forChatID: chat.id)
        if let context, let record = (try? context.fetch(FetchDescriptor<CoachChatRecord>(
            predicate: #Predicate { $0.id == chat.id }
        )))?.first {
            context.delete(record); try? context.save()
        }
        chats.removeAll { $0.id == chat.id }
    }

    func saveAnalysis(_ analysis: CoachAnalysis) {
        // Keep every successful run so Coach history can show a trend.
        if let context, let record = (try? context.fetch(FetchDescriptor<CoachAnalysisRecord>(
            predicate: #Predicate { $0.id == analysis.id }
        )))?.first {
            record.payload = (try? JSONEncoder().encode(analysis)) ?? Data(); record.calculatedAt = analysis.calculatedAt
        } else { context?.insert(CoachAnalysisRecord(from: analysis)) }
        analyses.removeAll { $0.id == analysis.id }
        try? context?.save(); analyses.insert(analysis, at: 0)
    }

    func saveProposal(_ proposal: CoachProposal) {
        if let i = proposals.firstIndex(where: { $0.id == proposal.id }) { proposals[i] = proposal }
        else { proposals.insert(proposal, at: 0) }
        if let context, let record = (try? context.fetch(FetchDescriptor<CoachProposalRecord>(
            predicate: #Predicate { $0.id == proposal.id }
        )))?.first {
            record.payload = (try? JSONEncoder().encode(proposal)) ?? Data(); record.statusRaw = proposal.status.rawValue
        } else { context?.insert(CoachProposalRecord(from: proposal)) }
        try? context?.save()
    }

    func proposal(id: UUID) -> CoachProposal? { proposals.first { $0.id == id } }

    func messages(for goalID: UUID) -> [CoachConversationMessage] {
        guard let context else {
            return messages.filter { $0.goalID == goalID }.sorted { $0.createdAt < $1.createdAt }
        }
        let descriptor = FetchDescriptor<CoachConversationMessageRecord>(
            predicate: #Predicate { $0.goalID == goalID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor))?.compactMap { $0.toSnapshot() } ?? []
    }

    func messages(forChatID chatID: UUID) -> [CoachConversationMessage] {
        guard let context else {
            return messages.filter { $0.chatID == chatID }.sorted { $0.createdAt < $1.createdAt }
        }
        let descriptor = FetchDescriptor<CoachConversationMessageRecord>(
            predicate: #Predicate { $0.chatID == chatID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor))?.compactMap { $0.toSnapshot() } ?? []
    }

    func latestMessage(forChatID chatID: UUID) -> CoachConversationMessage? {
        guard let context else {
            return messages.filter { $0.chatID == chatID }.max { $0.createdAt < $1.createdAt }
        }
        var descriptor = FetchDescriptor<CoachConversationMessageRecord>(
            predicate: #Predicate { $0.chatID == chatID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.toSnapshot()
    }

    func latestMessage(for goalID: UUID) -> CoachConversationMessage? {
        guard let context else {
            return messages.filter { $0.goalID == goalID }.max { $0.createdAt < $1.createdAt }
        }
        var descriptor = FetchDescriptor<CoachConversationMessageRecord>(
            predicate: #Predicate { $0.goalID == goalID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.toSnapshot()
    }

    func allMessages() -> [CoachConversationMessage] {
        guard let context else {
            return messages.sorted { $0.createdAt < $1.createdAt }
        }
        let descriptor = FetchDescriptor<CoachConversationMessageRecord>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor))?.compactMap { $0.toSnapshot() } ?? []
    }

    func addMessage(_ message: CoachConversationMessage) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message); context?.insert(CoachConversationMessageRecord(from: message)); try? context?.save()
    }

    func updateMessage(_ message: CoachConversationMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message }
        if let context, let record = (try? context.fetch(
            FetchDescriptor<CoachConversationMessageRecord>(predicate: #Predicate { $0.id == message.id })
        ))?.first {
            record.goalID = message.goalID
            record.chatID = message.chatID
            record.payload = (try? JSONEncoder().encode(message)) ?? Data(); record.roleRaw = message.role.rawValue
            record.createdAt = message.createdAt; try? context.save()
        }
    }

    func deleteMessages(for goalID: UUID) {
        if let context {
            let records = (try? context.fetch(FetchDescriptor<CoachConversationMessageRecord>(
                predicate: #Predicate { $0.goalID == goalID }
            ))) ?? []
            records.forEach(context.delete); try? context.save()
        }
        messages.removeAll { $0.goalID == goalID }
    }

    func deleteMessages(forChatID chatID: UUID) {
        if let context {
            let records = (try? context.fetch(FetchDescriptor<CoachConversationMessageRecord>(
                predicate: #Predicate { $0.chatID == chatID }
            ))) ?? []
            records.forEach(context.delete); try? context.save()
        }
        messages.removeAll { $0.chatID == chatID }
    }

}
