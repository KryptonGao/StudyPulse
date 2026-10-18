import Foundation
import SwiftData
import os

@Observable @MainActor
final class DefaultAIConversationRepository: AIConversationRepository {
    private(set) var conversations: [AIConversation] = []
    @ObservationIgnored private var context: ModelContext?

    func loadAll(context: ModelContext) async {
        self.context = context
        do {
            let records = try context.fetch(FetchDescriptor<AIConversationRecord>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            ))
            conversations = records.compactMap { $0.toSnapshot() }
            recoverInterruptedMessages(context: context)
        } catch {
            Log.data.error("AIConversationRepository load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A message still marked `streaming` at load time belongs to a process
    /// that died mid-generation; surface it as `interrupted`.
    private func recoverInterruptedMessages(context: ModelContext) {
        let streaming = AIMessageStatus.streaming.rawValue
        do {
            let stale = try context.fetch(FetchDescriptor<AIChatMessageRecord>(
                predicate: #Predicate { $0.statusRaw == streaming }
            ))
            guard !stale.isEmpty else { return }
            for record in stale {
                guard var message = record.toSnapshot() else { continue }
                message.status = .interrupted
                record.statusRaw = message.status.rawValue
                if let data = try? JSONEncoder().encode(message) { record.payload = data }
            }
            context.saveOrRollback("AIConversationRepository.recoverInterrupted")
        } catch {
            Log.data.error("AIConversationRepository recover failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Conversations

    @discardableResult
    func create(_ conversation: AIConversation) -> Bool {
        guard !conversations.contains(where: { $0.id == conversation.id }) else { return false }
        if let context {
            do {
                context.insert(try AIConversationRecord(from: conversation))
            } catch {
                Log.data.error("AIConversationRepository create encode failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
            guard context.saveOrRollback("AIConversationRepository.create") else { return false }
        }
        conversations.append(conversation)
        sortConversations()
        return true
    }

    func update(_ conversation: AIConversation) {
        if let context {
            let id = conversation.id
            do {
                guard let record = try context.fetch(FetchDescriptor<AIConversationRecord>(
                    predicate: #Predicate { $0.id == id }
                )).first else { return }
                record.title = conversation.title
                record.createdAt = conversation.createdAt
                record.updatedAt = conversation.updatedAt
                record.payload = try JSONEncoder().encode(conversation)
                guard context.saveOrRollback("AIConversationRepository.update") else { return }
            } catch {
                context.rollback()
                Log.data.error("AIConversationRepository update failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        }
        sortConversations()
    }

    func rename(_ id: UUID, title: String) {
        guard var conversation = conversations.first(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        conversation.title = trimmed
        conversation.isTitleUserEdited = true
        update(conversation)
    }

    func delete(_ id: UUID) {
        if let context {
            do {
                let messageRecords = try context.fetch(FetchDescriptor<AIChatMessageRecord>(
                    predicate: #Predicate { $0.conversationID == id }
                ))
                messageRecords.forEach(context.delete)
                let records = try context.fetch(FetchDescriptor<AIConversationRecord>(
                    predicate: #Predicate { $0.id == id }
                ))
                records.forEach(context.delete)
                guard context.saveOrRollback("AIConversationRepository.delete") else { return }
            } catch {
                context.rollback()
                Log.data.error("AIConversationRepository delete failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        conversations.removeAll { $0.id == id }
    }

    // MARK: Messages

    func messages(for conversationID: UUID) -> [AIChatMessage] {
        guard let context else { return [] }
        do {
            let records = try context.fetch(FetchDescriptor<AIChatMessageRecord>(
                predicate: #Predicate { $0.conversationID == conversationID },
                sortBy: [SortDescriptor(\.orderIndex), SortDescriptor(\.createdAt)]
            ))
            return records.compactMap { record in
                if let snapshot = record.toSnapshot() { return snapshot }
                Log.data.error("AIConversationRepository skipped unreadable message id=\(record.id.uuidString, privacy: .public)")
                return nil
            }
        } catch {
            Log.data.error("AIConversationRepository messages fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func upsertMessage(_ message: AIChatMessage) {
        guard let context else { return }
        let id = message.id
        do {
            let payload = try JSONEncoder().encode(message)
            if let record = try context.fetch(FetchDescriptor<AIChatMessageRecord>(
                predicate: #Predicate { $0.id == id }
            )).first {
                record.conversationID = message.conversationID
                record.orderIndex = message.orderIndex
                record.createdAt = message.createdAt
                record.statusRaw = message.status.rawValue
                record.searchText = message.searchableText
                record.payload = payload
            } else {
                context.insert(try AIChatMessageRecord(from: message))
            }
            context.saveOrRollback("AIConversationRepository.upsertMessage")
        } catch {
            context.rollback()
            Log.data.error("AIConversationRepository upsertMessage failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteMessages(_ ids: [UUID]) {
        guard let context, !ids.isEmpty else { return }
        do {
            let idSet = Set(ids)
            let records = try context.fetch(FetchDescriptor<AIChatMessageRecord>())
            records.filter { idSet.contains($0.id) }.forEach(context.delete)
            context.saveOrRollback("AIConversationRepository.deleteMessages")
        } catch {
            context.rollback()
            Log.data.error("AIConversationRepository deleteMessages failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Search

    func search(_ query: String) -> [AIConversation] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return conversations }
        var matched = Set(conversations.filter { $0.title.localizedStandardContains(trimmed) }.map(\.id))
        if let context {
            do {
                let records = try context.fetch(FetchDescriptor<AIChatMessageRecord>(
                    predicate: #Predicate { $0.searchText.localizedStandardContains(trimmed) }
                ))
                for record in records { matched.insert(record.conversationID) }
            } catch {
                Log.data.error("AIConversationRepository search failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return conversations.filter { matched.contains($0.id) }
    }

    // MARK: Backup / bulk

    func allMessages() -> [AIChatMessage] {
        guard let context else { return [] }
        do {
            let records = try context.fetch(FetchDescriptor<AIChatMessageRecord>(
                sortBy: [SortDescriptor(\.createdAt)]
            ))
            return records.compactMap { $0.toSnapshot() }
        } catch {
            Log.data.error("AIConversationRepository allMessages failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func deleteAll() {
        if let context {
            do {
                try context.fetch(FetchDescriptor<AIChatMessageRecord>()).forEach(context.delete)
                try context.fetch(FetchDescriptor<AIConversationRecord>()).forEach(context.delete)
                guard context.saveOrRollback("AIConversationRepository.deleteAll") else { return }
            } catch {
                context.rollback()
                return
            }
        }
        conversations.removeAll()
    }

    private func sortConversations() {
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }
}
