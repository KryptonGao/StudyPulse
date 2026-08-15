import XCTest
import SwiftData
@testable import StudyPulse

final class ExamSimulationBehaviorRecorderTests: XCTestCase {
    func testRecorderCapturesDwellRevisitSkipAndCommittedAnswerChanges() {
        let start = Date(timeIntervalSince1970: 1_000)
        var recorder = ExamSimulationBehaviorRecorder(
            simulation: ExamSimulation(subject: "Math", questions: makeQuestions())
        )

        recorder.start(at: start, remainingSeconds: 1_200)
        recorder.enterQuestion(index: 0, at: start, remainingSeconds: 1_200)
        recorder.commitAnswer(index: 0, answer: "A", at: start.addingTimeInterval(60), remainingSeconds: 1_140)
        recorder.commitAnswer(index: 0, answer: "B", at: start.addingTimeInterval(150), remainingSeconds: 1_050)
        recorder.leaveQuestion(index: 0, at: start.addingTimeInterval(180), remainingSeconds: 1_020)
        recorder.enterQuestion(index: 0, at: start.addingTimeInterval(240), remainingSeconds: 960)
        recorder.leaveQuestion(index: 0, at: start.addingTimeInterval(270), remainingSeconds: 930)
        recorder.enterQuestion(index: 1, at: start.addingTimeInterval(270), remainingSeconds: 930)
        recorder.markSkipped(index: 1, at: start.addingTimeInterval(280), remainingSeconds: 920)
        recorder.leaveQuestion(index: 1, at: start.addingTimeInterval(280), remainingSeconds: 920)

        let first = recorder.simulation.questionRecords[0]
        XCTAssertEqual(first.visitCount, 2)
        XCTAssertEqual(first.totalViewSeconds, 210, accuracy: 0.001)
        XCTAssertEqual(first.firstAnswer, "A")
        XCTAssertEqual(first.finalAnswer, "B")
        XCTAssertEqual(first.answerChangeCount, 1)
        XCTAssertEqual(recorder.simulation.questionRecords[1].skipCount, 1)
        XCTAssertTrue(recorder.simulation.events.contains { $0.kind == .skipped })
    }

    func testSubmissionAndGradingProduceValidCompletedSimulation() {
        let now = Date()
        var recorder = ExamSimulationBehaviorRecorder(
            simulation: ExamSimulation(subject: "Math", questions: makeQuestions())
        )
        recorder.start(at: now, remainingSeconds: 1_200)
        recorder.enterQuestion(index: 0, at: now, remainingSeconds: 1_200)
        recorder.leaveQuestion(index: 0, at: now.addingTimeInterval(10), remainingSeconds: 1_190)
        recorder.beginSubmission(at: now.addingTimeInterval(10), remainingSeconds: 1_190, timedOut: false)
        recorder.applyGrading(
            QuizGradingResponse(
                totalScore: 70,
                results: [
                    QuizQuestionGradingResult(index: 0, score: 10, isCorrect: true, feedback: "OK")
                ]
            )
        )
        recorder.finish(with: makeAnalysis())

        XCTAssertEqual(recorder.simulation.status, .completed)
        XCTAssertEqual(recorder.simulation.totalScore, 70)
        XCTAssertEqual(recorder.simulation.questionRecords[0].isCorrect, true)
        XCTAssertTrue(recorder.simulation.isValidCompletedSession)
    }

    private func makeQuestions() -> [QuizQuestion] {
        (0..<ExamSimulation.defaultQuestionCount).map {
            QuizQuestion(
                type: "multiple_choice",
                question: "Q\($0)",
                options: ["A. 1", "B. 2", "C. 3", "D. 4"],
                correctAnswer: "A",
                solution: "A"
            )
        }
    }

    private func makeAnalysis() -> ExamRoleAnalysis {
        ExamRoleAnalysis(
            role: .firstQuestionFixation,
            confidence: 0.8,
            evidence: [
                ExamRoleEvidence(title: "Long dwell", detail: "Q1 used 180 seconds", questionIndex: 0),
                ExamRoleEvidence(title: "Revisit", detail: "Q1 was visited twice", questionIndex: 0)
            ],
            risk: "Lost time",
            strategies: ["Set a two-minute cap", "Mark and return"],
            isStable: false
        )
    }
}

final class ExamRoleLLMTests: XCTestCase {
    func testSimulationDecodingBackfillsFieldsMissingFromOlderPayload() throws {
        let data = Data(#"{"subject":"Math"}"#.utf8)
        let simulation = try JSONDecoder().decode(ExamSimulation.self, from: data)

        XCTAssertEqual(simulation.subject, "Math")
        XCTAssertEqual(simulation.durationSeconds, ExamSimulation.defaultDurationSeconds)
        XCTAssertEqual(simulation.status, .preparing)
        XCTAssertTrue(simulation.events.isEmpty)
        XCTAssertTrue(simulation.questionRecords.isEmpty)
    }

    func testParserAcceptsStrictFencedJSONAndBackfillsEvidenceIDs() {
        let raw = """
        ```json
        {
          "role": "overChecking",
          "confidence": 0.73,
          "evidence": [
            {"title": "Repeated visits", "detail": "Four questions were revisited", "questionIndex": 3},
            {"title": "Late changes", "detail": "Two answers changed near submission", "questionIndex": 8}
          ],
          "risk": "Correct answers may be changed",
          "strategies": ["Only change with evidence", "Reserve a fixed review window"],
          "isStable": false
        }
        ```
        """

        let result = ExamRoleLLM.parse(raw)
        XCTAssertEqual(result?.role, .overChecking)
        XCTAssertEqual(result?.evidence.count, 2)
        XCTAssertNotNil(result?.evidence.first?.id)
    }

    func testParserRejectsUnknownRoleAndInsufficientEvidence() {
        let unknown = """
        {"role":"inventedRole","confidence":0.5,"evidence":[
        {"title":"A","detail":"A"},{"title":"B","detail":"B"}],
        "risk":"R","strategies":["S1","S2"],"isStable":false}
        """
        let insufficient = """
        {"role":"pressureDrop","confidence":0.5,"evidence":[
        {"title":"A","detail":"A"}],
        "risk":"R","strategies":["S1","S2"],"isStable":false}
        """

        XCTAssertNil(ExamRoleLLM.parse(unknown))
        XCTAssertNil(ExamRoleLLM.parse(insufficient))
    }
}

@MainActor
final class ExamSimulationRepositoryTests: XCTestCase {
    func testRepositoryPersistsAndReloadsSimulation() async throws {
        let modelContainer = try TestModelContainerFactory.makeInMemoryContainer()
        let repo = DefaultExamSimulationRepository()
        await repo.loadAll(context: modelContainer.mainContext)

        let simulation = ExamSimulation(
            subject: "Physics",
            questions: (0..<10).map {
                QuizQuestion(
                    type: "fill_in_the_blank",
                    question: "Q\($0)",
                    options: nil,
                    correctAnswer: "\($0)",
                    solution: "Solution"
                )
            }
        )
        repo.upsert(simulation)

        let reloaded = DefaultExamSimulationRepository()
        await reloaded.loadAll(context: modelContainer.mainContext)
        XCTAssertEqual(reloaded.simulations.count, 1)
        XCTAssertEqual(reloaded.simulations.first?.id, simulation.id)
        XCTAssertEqual(reloaded.simulations.first?.questionRecords.count, 0)
        XCTAssertEqual(reloaded.simulation(id: simulation.id)?.questionRecords.count, 10)
    }

    func testViewModelRestoresRunningSessionAfterViewRecreation() async throws {
        let container = try await TestRepositoryContainerFactory.makeInMemoryRealContainer()
        let now = Date()
        let questions = (0..<10).map {
            QuizQuestion(
                type: "multiple_choice",
                question: "Q\($0)",
                options: ["A. 1", "B. 2", "C. 3", "D. 4"],
                correctAnswer: "A",
                solution: "A"
            )
        }
        var recorder = ExamSimulationBehaviorRecorder(
            simulation: ExamSimulation(subject: "Math", questions: questions)
        )
        recorder.start(at: now, remainingSeconds: 1_200)
        recorder.enterQuestion(index: 0, at: now, remainingSeconds: 1_200)
        recorder.leaveQuestion(index: 0, at: now.addingTimeInterval(10), remainingSeconds: 1_190)
        recorder.enterQuestion(index: 4, at: now.addingTimeInterval(10), remainingSeconds: 1_190)
        recorder.commitAnswer(index: 4, answer: "B", at: now.addingTimeInterval(12), remainingSeconds: 1_188)
        container.examSimulationRepo.upsert(recorder.simulation)

        let restored = ExamSimulationViewModel(container: container)

        XCTAssertEqual(restored.state, .answering)
        XCTAssertEqual(restored.currentIndex, 4)
        XCTAssertEqual(restored.answerBinding(for: questions[4].id), "B")
        XCTAssertGreaterThan(restored.remainingSeconds, 0)
    }
}
