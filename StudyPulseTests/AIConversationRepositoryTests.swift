import XCTest
import SwiftData
@testable import StudyPulse

@MainActor
final class AIConversationRepositoryTests: XCTestCase {
    /// SwiftData contexts crash if their container is released; keep it for the test's lifetime.
    private var retainedContainer: ModelContainer?

    override func tearDown() {
        retainedContainer = nil
        super.tearDown()
    }

    private func makeRepo() async throws -> (DefaultAIConversationRepository, ModelContainer) {
        let model = try TestModelContainerFactory.makeInMemoryContainer()
        let repo = DefaultAIConversationRepository()
        await repo.loadAll(context: model.mainContext)
        retainedContainer = model
        return (repo, model)
    }

    func testCreateAndOrderNewestFirst() async throws {
        let (repo, _) = try await makeRepo()
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        let older = AIConversation(title: "Older", createdAt: base, updatedAt: base)
        let newer = AIConversation(title: "Newer", createdAt: base, updatedAt: base.addingTimeInterval(60))
        XCTAssertTrue(repo.create(older))
        XCTAssertTrue(repo.create(newer))
        XCTAssertEqual(repo.conversations.map(\.title), ["Newer", "Older"])
        XCTAssertFalse(repo.create(older), "duplicate id must be rejected")
    }

    func testMessagesAreOrderedByOrderIndexAndUpsertUpdatesInPlace() async throws {
        let (repo, _) = try await makeRepo()
        let conversation = AIConversation(title: "Chat")
        repo.create(conversation)
        let second = AIChatMessage(conversationID: conversation.id, orderIndex: 1, role: .assistant, content: "two")
        let first = AIChatMessage(conversationID: conversation.id, orderIndex: 0, role: .user, content: "one")
        repo.upsertMessage(second)
        repo.upsertMessage(first)
        XCTAssertEqual(repo.messages(for: conversation.id).map(\.content), ["one", "two"])

        var edited = second
        edited.content = "two (edited)"
        repo.upsertMessage(edited)
        let messages = repo.messages(for: conversation.id)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.last?.content, "two (edited)")
    }

    func testRenameMarksTitleUserEditedAndIgnoresBlank() async throws {
        let (repo, _) = try await makeRepo()
        let conversation = AIConversation(title: "Auto")
        repo.create(conversation)
        repo.rename(conversation.id, title: "   ")
        XCTAssertEqual(repo.conversations.first?.title, "Auto")
        repo.rename(conversation.id, title: " Mine ")
        XCTAssertEqual(repo.conversations.first?.title, "Mine")
        XCTAssertEqual(repo.conversations.first?.isTitleUserEdited, true)
    }

    func testDeleteRemovesConversationAndItsMessagesOnly() async throws {
        let (repo, _) = try await makeRepo()
        let keep = AIConversation(title: "Keep")
        let drop = AIConversation(title: "Drop")
        repo.create(keep); repo.create(drop)
        repo.upsertMessage(AIChatMessage(conversationID: keep.id, orderIndex: 0, role: .user, content: "k"))
        repo.upsertMessage(AIChatMessage(conversationID: drop.id, orderIndex: 0, role: .user, content: "d"))
        repo.delete(drop.id)
        XCTAssertEqual(repo.conversations.map(\.id), [keep.id])
        XCTAssertTrue(repo.messages(for: drop.id).isEmpty)
        XCTAssertEqual(repo.messages(for: keep.id).count, 1)
        XCTAssertEqual(repo.allMessages().count, 1)
    }

    func testSearchMatchesTitleAndMessageText() async throws {
        let (repo, _) = try await makeRepo()
        let a = AIConversation(title: "Physics review")
        let b = AIConversation(title: "Untitled")
        repo.create(a); repo.create(b)
        repo.upsertMessage(AIChatMessage(conversationID: b.id, orderIndex: 0, role: .user, content: "How do I improve calculus?"))
        XCTAssertEqual(Set(repo.search("physics").map(\.id)), [a.id])
        XCTAssertEqual(Set(repo.search("calculus").map(\.id)), [b.id])
        XCTAssertEqual(repo.search("").count, 2)
        XCTAssertTrue(repo.search("zzz-no-match").isEmpty)
    }

    func testStreamingMessageBecomesInterruptedAfterReload() async throws {
        let (repo, model) = try await makeRepo()
        let conversation = AIConversation(title: "Chat")
        repo.create(conversation)
        let streaming = AIChatMessage(
            conversationID: conversation.id, orderIndex: 0, role: .assistant,
            content: "partial", status: .streaming
        )
        repo.upsertMessage(streaming)

        let reloaded = DefaultAIConversationRepository()
        await reloaded.loadAll(context: model.mainContext)
        let message = try XCTUnwrap(reloaded.messages(for: conversation.id).first)
        XCTAssertEqual(message.status, .interrupted)
        XCTAssertEqual(message.content, "partial")
    }

    func testDeleteAllClearsEverything() async throws {
        let (repo, _) = try await makeRepo()
        let conversation = AIConversation(title: "Chat")
        repo.create(conversation)
        repo.upsertMessage(AIChatMessage(conversationID: conversation.id, orderIndex: 0, role: .user, content: "x"))
        repo.deleteAll()
        XCTAssertTrue(repo.conversations.isEmpty)
        XCTAssertTrue(repo.allMessages().isEmpty)
    }

    func testMessageDecodesFromMinimalLegacyJSON() throws {
        let id = UUID(), conversationID = UUID()
        let json = #"{"id":"\#(id.uuidString)","conversationID":"\#(conversationID.uuidString)"}"#
        let message = try JSONDecoder().decode(AIChatMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.status, .complete)
        XCTAssertEqual(message.origin, .model)
        XCTAssertTrue(message.references.isEmpty)
        XCTAssertNil(message.feedbackHelpful)
    }
}
