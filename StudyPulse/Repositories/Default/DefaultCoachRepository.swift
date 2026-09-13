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
            // Keep whatever was already in memory so a transient load failure
            // cannot look like the Coach history vanished.
            Log.data.error(
                "CoachRepository load failed; keeping previously loaded snapshots: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func addGoal(_ goal: CoachGoal) {
        guard !goals.contains(where: { $0.id == goal.id }) else { return }
        if let context {
            do {
                context.insert(try CoachGoalRecord(from: goal))
            } catch {
                Log.data.error("CoachRepository addGoal encode failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard context.saveOrRollback("CoachRepository.addGoal") else { return }
        }
        goals.append(goal)
    }

    func updateGoal(_ goal: CoachGoal) {
        guard let context else {
            if let i = goals.firstIndex(where: { $0.id == goal.id }) { goals[i] = goal }
            return
        }
        do {
            let payload = try encodePayload(goal, operation: "updateGoal")
            if let record = try context.fetch(FetchDescriptor<CoachGoalRecord>(
                predicate: #Predicate { $0.id == goal.id }
            )).first {
                record.payload = payload
                record.updatedAt = goal.updatedAt
                guard context.saveOrRollback("CoachRepository.updateGoal") else { return }
            }
        } catch {
            context.rollback()
            Log.data.error("CoachRepository updateGoal failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        if let i = goals.firstIndex(where: { $0.id == goal.id }) { goals[i] = goal }
    }

    func deleteGoal(_ goal: CoachGoal) {
        chats(for: goal.id).forEach(deleteChat)
        deleteMessages(for: goal.id)
        guard let context else {
            goals.removeAll { $0.id == goal.id }
            return
        }
        do {
            if let record = try context.fetch(FetchDescriptor<CoachGoalRecord>(
                predicate: #Predicate { $0.id == goal.id }
            )).first {
                context.delete(record)
                guard context.saveOrRollback("CoachRepository.deleteGoal") else { return }
            }
        } catch {
            context.rollback()
            Log.data.error("CoachRepository deleteGoal failed: \(error.localizedDescription, privacy: .public)")
            return
        }
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
        if let context {
            do {
                context.insert(try CoachChatRecord(from: chat))
            } catch {
                Log.data.error("CoachRepository addChat encode failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard context.saveOrRollback("CoachRepository.addChat") else { return }
        }
        chats.append(chat)
    }

    func updateChat(_ chat: CoachChat) {
        guard let context else {
            if let index = chats.firstIndex(where: { $0.id == chat.id }) { chats[index] = chat }
            return
        }
        do {
            let payload = try encodePayload(chat, operation: "updateChat")
            if let record = try context.fetch(
                FetchDescriptor<CoachChatRecord>(predicate: #Predicate { $0.id == chat.id })
            ).first {
                record.goalID = chat.goalID
                record.title = chat.title
                record.isArchived = chat.isArchived
                record.createdAt = chat.createdAt
                record.payload = payload
                record.updatedAt = chat.updatedAt
                guard context.saveOrRollback("CoachRepository.updateChat") else { return }
            }
        } catch {
            context.rollback()
            Log.data.error("CoachRepository updateChat failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        if let index = chats.firstIndex(where: { $0.id == chat.id }) { chats[index] = chat }
    }

    func deleteChat(_ chat: CoachChat) {
        deleteMessages(forChatID: chat.id)
        guard let context else {
            chats.removeAll { $0.id == chat.id }
            return
        }
        do {
            if let record = try context.fetch(FetchDescriptor<CoachChatRecord>(
                predicate: #Predicate { $0.id == chat.id }
            )).first {
                context.delete(record)
                guard context.saveOrRollback("CoachRepository.deleteChat") else { return }
            }
        } catch {
            context.rollback()
            Log.data.error("CoachRepository deleteChat failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        chats.removeAll { $0.id == chat.id }
    }

    func saveAnalysis(_ analysis: CoachAnalysis) {
        // Keep every successful run so Coach history can show a trend.
        if let context {
            do {
                let payload = try encodePayload(analysis, operation: "saveAnalysis")
                if let record = try context.fetch(FetchDescriptor<CoachAnalysisRecord>(
                    predicate: #Predicate { $0.id == analysis.id }
                )).first {
                    record.payload = payload
                    record.calculatedAt = analysis.calculatedAt
                } else {
                    context.insert(try CoachAnalysisRecord(from: analysis))
                }
                guard context.saveOrRollback("CoachRepository.saveAnalysis") else { return }
            } catch {
                context.rollback()
                Log.data.error("CoachRepository saveAnalysis failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        analyses.removeAll { $0.id == analysis.id }
        analyses.insert(analysis, at: 0)
    }

    func saveProposal(_ proposal: CoachProposal) {
        if let context {
            do {
                let payload = try encodePayload(proposal, operation: "saveProposal")
                if let record = try context.fetch(FetchDescriptor<CoachProposalRecord>(
                    predicate: #Predicate { $0.id == proposal.id }
                )).first {
                    record.payload = payload
                    record.statusRaw = proposal.status.rawValue
                } else {
                    context.insert(try CoachProposalRecord(from: proposal))
                }
                guard context.saveOrRollback("CoachRepository.saveProposal") else { return }
            } catch {
                context.rollback()
                Log.data.error("CoachRepository saveProposal failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        if let i = proposals.firstIndex(where: { $0.id == proposal.id }) { proposals[i] = proposal }
        else { proposals.insert(proposal, at: 0) }
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
        return fetchMessages(descriptor, fallback: messages.filter { $0.goalID == goalID })
    }

    func messages(forChatID chatID: UUID) -> [CoachConversationMessage] {
        guard let context else {
            return messages.filter { $0.chatID == chatID }.sorted { $0.createdAt < $1.createdAt }
        }
        let descriptor = FetchDescriptor<CoachConversationMessageRecord>(
            predicate: #Predicate { $0.chatID == chatID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return fetchMessages(descriptor, fallback: messages.filter { $0.chatID == chatID })
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
        let fallback = messages.filter { $0.chatID == chatID }
        return fetchLatestMessage(descriptor, fallback: fallback)
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
        let fallback = messages.filter { $0.goalID == goalID }
        return fetchLatestMessage(descriptor, fallback: fallback)
    }

    func allMessages() -> [CoachConversationMessage] {
        guard let context else {
            return messages.sorted { $0.createdAt < $1.createdAt }
        }
        let descriptor = FetchDescriptor<CoachConversationMessageRecord>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return fetchMessages(descriptor, fallback: messages)
    }

    func addMessage(_ message: CoachConversationMessage) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        if let context {
            do {
                context.insert(try CoachConversationMessageRecord(from: message))
            } catch {
                Log.data.error("CoachRepository addMessage encode failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard context.saveOrRollback("CoachRepository.addMessage") else { return }
        }
        messages.append(message)
    }

    func updateMessage(_ message: CoachConversationMessage) {
        guard let context else {
            if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message }
            return
        }
        do {
            let payload = try encodePayload(message, operation: "updateMessage")
            if let record = try context.fetch(
                FetchDescriptor<CoachConversationMessageRecord>(predicate: #Predicate { $0.id == message.id })
            ).first {
                record.goalID = message.goalID
                record.chatID = message.chatID
                record.payload = payload
                record.roleRaw = message.role.rawValue
                record.createdAt = message.createdAt
                guard context.saveOrRollback("CoachRepository.updateMessage") else { return }
            }
        } catch {
            context.rollback()
            Log.data.error("CoachRepository updateMessage failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message }
    }

    func deleteMessages(for goalID: UUID) {
        if let context {
            do {
                let records = try context.fetch(FetchDescriptor<CoachConversationMessageRecord>(
                    predicate: #Predicate { $0.goalID == goalID }
                ))
                records.forEach(context.delete)
                guard context.saveOrRollback("CoachRepository.deleteMessages(for goal)") else { return }
            } catch {
                context.rollback()
                Log.data.error("CoachRepository deleteMessages(for goal) failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        messages.removeAll { $0.goalID == goalID }
    }

    func deleteMessages(forChatID chatID: UUID) {
        if let context {
            do {
                let records = try context.fetch(FetchDescriptor<CoachConversationMessageRecord>(
                    predicate: #Predicate { $0.chatID == chatID }
                ))
                records.forEach(context.delete)
                guard context.saveOrRollback("CoachRepository.deleteMessages(forChat)") else { return }
            } catch {
                context.rollback()
                Log.data.error("CoachRepository deleteMessages(forChat) failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        messages.removeAll { $0.chatID == chatID }
    }

    private func encodePayload<T: Encodable>(_ value: T, operation: String) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            Log.data.error(
                "CoachRepository \(operation, privacy: .public) encode failed: \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    private func fetchMessages(
        _ descriptor: FetchDescriptor<CoachConversationMessageRecord>,
        fallback: [CoachConversationMessage]
    ) -> [CoachConversationMessage] {
        guard let context else {
            return fallback.sorted { $0.createdAt < $1.createdAt }
        }
        do {
            let records = try context.fetch(descriptor)
            var decoded: [CoachConversationMessage] = []
            decoded.reserveCapacity(records.count)
            for record in records {
                if let snapshot = record.toSnapshot() {
                    decoded.append(snapshot)
                } else {
                    Log.data.error(
                        "CoachRepository skipped unreadable message id=\(record.id.uuidString, privacy: .public)"
                    )
                }
            }
            return decoded
        } catch {
            Log.data.error(
                "CoachRepository message fetch failed; using in-memory fallback: \(error.localizedDescription, privacy: .public)"
            )
            return fallback.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private func fetchLatestMessage(
        _ descriptor: FetchDescriptor<CoachConversationMessageRecord>,
        fallback: [CoachConversationMessage]
    ) -> CoachConversationMessage? {
        guard let context else {
            return fallback.max { $0.createdAt < $1.createdAt }
        }
        do {
            if let record = try context.fetch(descriptor).first {
                if let snapshot = record.toSnapshot() {
                    return snapshot
                }
                Log.data.error(
                    "CoachRepository skipped unreadable latest message id=\(record.id.uuidString, privacy: .public)"
                )
            }
            return fallback.max { $0.createdAt < $1.createdAt }
        } catch {
            Log.data.error(
                "CoachRepository latest message fetch failed; using in-memory fallback: \(error.localizedDescription, privacy: .public)"
            )
            return fallback.max { $0.createdAt < $1.createdAt }
        }
    }

}
