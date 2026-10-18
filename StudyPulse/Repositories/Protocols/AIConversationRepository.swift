import Foundation
import SwiftData

/// Persistence for full-screen AI Mode conversations. Deliberately separate
/// from `CoachRepository`: different lifecycle (streaming states, feedback,
/// references, search) and no coupling to Coach goals.
@MainActor
protocol AIConversationRepository: AnyObject {
    /// Newest first (by `updatedAt`).
    var conversations: [AIConversation] { get }
    func loadAll(context: ModelContext) async

    @discardableResult
    func create(_ conversation: AIConversation) -> Bool
    func update(_ conversation: AIConversation)
    func rename(_ id: UUID, title: String)
    /// Deletes the conversation together with all its messages.
    func delete(_ id: UUID)

    func messages(for conversationID: UUID) -> [AIChatMessage]
    func upsertMessage(_ message: AIChatMessage)
    func deleteMessages(_ ids: [UUID])

    /// Matches conversation titles and message text.
    func search(_ query: String) -> [AIConversation]

    /// Full-history reads for backup export.
    func allMessages() -> [AIChatMessage]
    func deleteAll()
}
