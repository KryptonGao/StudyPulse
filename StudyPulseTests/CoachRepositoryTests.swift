import XCTest
import SwiftData
@testable import StudyPulse

@MainActor
final class CoachRepositoryTests: XCTestCase {
    func testCoachGoalAndProposalPersistInMemoryStore() async throws {
        let model = try TestModelContainerFactory.makeInMemoryContainer()
        let repo = DefaultCoachRepository()
        await repo.loadAll(context: model.mainContext)
        let goal = CoachGoal(title: "Exam", subjects: [CoachGoalSubject(subject: "Math", targetScore: 100)], targetDate: Date().addingTimeInterval(86400))
        repo.addGoal(goal)
        let analysis = CoachAnalysisEngine.analyze(goal: goal, snapshot: CoachDataSnapshot(grades: [], mistakes: [], tasks: [], exams: []))
        repo.saveAnalysis(analysis)
        let proposal = CoachProposal(goalID: goal.id, goalVersion: goal.version, analysisID: analysis.id, conclusion: "Adjust", rationale: "Test", items: [])
        repo.saveProposal(proposal)
        XCTAssertEqual(repo.goals.first?.id, goal.id)
        XCTAssertEqual(repo.analyses.first?.id, analysis.id)
        XCTAssertEqual(repo.proposal(id: proposal.id)?.status, .pending)
    }

    func testExpiredProposalTransitionsToExpired() async throws {
        let model = try TestModelContainerFactory.makeInMemoryContainer()
        let container = RepositoryContainer()
        await container.asyncTestInit(with: model)
        let goal = CoachGoal(title: "Goal", subjects: [CoachGoalSubject(subject: "Math", targetScore: 80)], targetDate: Date().addingTimeInterval(86400))
        container.coachRepo.addGoal(goal)
        let expired = CoachProposal(goalID: goal.id, goalVersion: goal.version, analysisID: UUID(), conclusion: "x", rationale: "x", items: [], expiresAt: Date().addingTimeInterval(-1))
        container.coachRepo.saveProposal(expired)
        CoachCoordinator(container: container).expireStaleProposals()
        XCTAssertEqual(container.coachRepo.proposal(id: expired.id)?.status, .expired)
    }

    func testConversationMessagesPersistAndCanBeUpdated() async throws {
        let model = try TestModelContainerFactory.makeInMemoryContainer()
        let repo = DefaultCoachRepository()
        await repo.loadAll(context: model.mainContext)
        let goalID = UUID()
        var message = CoachConversationMessage(goalID: goalID, role: .assistant, content: "Hello")
        repo.addMessage(message)
        message.content = "Updated"
        repo.updateMessage(message)
        XCTAssertEqual(repo.messages(for: goalID).first?.content, "Updated")
        repo.deleteMessages(for: goalID)
        XCTAssertTrue(repo.messages(for: goalID).isEmpty)
    }

    func testChatsAreIndependentAndCanBeArchivedOrDeleted() async throws {
        let model = try TestModelContainerFactory.makeInMemoryContainer()
        let repo = DefaultCoachRepository()
        await repo.loadAll(context: model.mainContext)
        let goalID = UUID()
        let first = CoachChat(goalID: goalID, title: "Planning")
        let second = CoachChat(goalID: goalID, title: "Reflection")
        repo.addChat(first); repo.addChat(second)
        repo.addMessage(CoachConversationMessage(goalID: goalID, chatID: first.id, role: .user, content: "Plan"))
        repo.addMessage(CoachConversationMessage(goalID: goalID, chatID: second.id, role: .user, content: "Reflect"))

        var archived = second
        archived.isArchived = true
        repo.updateChat(archived)

        XCTAssertEqual(repo.messages(forChatID: first.id).count, 1)
        XCTAssertTrue(repo.chats(for: goalID).first(where: { $0.id == second.id })?.isArchived == true)
        repo.deleteChat(first)
        XCTAssertTrue(repo.messages(forChatID: first.id).isEmpty)
        XCTAssertEqual(repo.messages(forChatID: second.id).count, 1)
    }

    func testLoadAllSkipsCorruptPayloadAndKeepsValidRecords() async throws {
        let model = try TestModelContainerFactory.makeInMemoryContainer()
        let context = model.mainContext
        let good = CoachGoal(
            title: "Keep",
            subjects: [CoachGoalSubject(subject: "Math", targetScore: 90)],
            targetDate: Date().addingTimeInterval(86400)
        )
        let corrupt = CoachGoal(
            title: "Corrupt",
            subjects: [CoachGoalSubject(subject: "Physics", targetScore: 80)],
            targetDate: Date().addingTimeInterval(86400)
        )
        context.insert(try CoachGoalRecord(from: good))
        let corruptRecord = try CoachGoalRecord(from: corrupt)
        corruptRecord.payload = Data()
        context.insert(corruptRecord)
        try context.save()

        let repo = DefaultCoachRepository()
        await repo.loadAll(context: context)
        XCTAssertEqual(repo.goals.map(\.id), [good.id])
        XCTAssertEqual(repo.goals.first?.title, "Keep")
    }
}
