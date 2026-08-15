import Foundation
import SwiftData

@MainActor
protocol CoachRepository: AnyObject, Sendable {
    var goals: [CoachGoal] { get }
    var analyses: [CoachAnalysis] { get }
    var proposals: [CoachProposal] { get }
    var chats: [CoachChat] { get }
    var messages: [CoachConversationMessage] { get }
    func loadAll(context: ModelContext) async
    func addGoal(_ goal: CoachGoal)
    func updateGoal(_ goal: CoachGoal)
    func deleteGoal(_ goal: CoachGoal)
    func chats(for goalID: UUID) -> [CoachChat]
    func standaloneChats() -> [CoachChat]
    func addChat(_ chat: CoachChat)
    func updateChat(_ chat: CoachChat)
    func deleteChat(_ chat: CoachChat)
    func saveAnalysis(_ analysis: CoachAnalysis)
    func saveProposal(_ proposal: CoachProposal)
    func proposal(id: UUID) -> CoachProposal?
    func messages(for goalID: UUID) -> [CoachConversationMessage]
    func messages(forChatID chatID: UUID) -> [CoachConversationMessage]
    func latestMessage(forChatID chatID: UUID) -> CoachConversationMessage?
    func latestMessage(for goalID: UUID) -> CoachConversationMessage?
    /// Explicit full-history read used by backup/export, never startup.
    func allMessages() -> [CoachConversationMessage]
    func addMessage(_ message: CoachConversationMessage)
    func updateMessage(_ message: CoachConversationMessage)
    func deleteMessages(for goalID: UUID)
    func deleteMessages(forChatID chatID: UUID)
}
