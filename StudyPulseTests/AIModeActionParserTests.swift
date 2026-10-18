import XCTest
@testable import StudyPulse

final class AIModeActionParserTests: XCTestCase {
    private let context = AIActionContext(
        subjects: [
            Subject(name: "Mathematics", displayName: "数学", fullScore: 150),
            Subject(name: "Physics", displayName: "物理"),
            Subject(name: "Chemistry", displayName: "化学", enabled: false),
        ],
        now: AIModeActionParserTests.date("2026-10-17 12:00")
    )

    private static func date(_ text: String) -> Date {
        AIModeActionParser.parseDate(text)!
    }

    private func wrap(_ json: String) -> String {
        "好的，我来记录。\n\n```studypulse-actions\n\(json)\n```\n\n## 继续追问\n- 还有吗？"
    }

    func testGradeIsValidatedAndResolvedByDisplayName() {
        let raw = wrap(#"[{"type":"add_grade","subject":"数学","score":132,"examName":"期中","date":"2026-10-10"}]"#)
        let parsed = AIModeResponseParser.parse(raw, actionContext: context)
        XCTAssertEqual(parsed.body, "好的，我来记录。")
        XCTAssertEqual(parsed.followUps, ["还有吗？"])
        XCTAssertEqual(parsed.actions.count, 1)
        let grade = parsed.actions[0].grade
        XCTAssertEqual(grade?.subject, "Mathematics")
        XCTAssertEqual(grade?.fullScore, 150, "falls back to the subject's full score")
        XCTAssertEqual(grade?.score, 132)
        XCTAssertEqual(parsed.actions[0].status, .pending)
    }

    func testInvalidGradesAreDropped() {
        let json = """
        [{"type":"add_grade","subject":"化学","score":80},
         {"type":"add_grade","subject":"Physics","score":120},
         {"type":"add_grade","subject":"Physics","score":-1},
         {"type":"add_grade","subject":"Physics","score":90,"date":"2027-01-01"},
         {"type":"add_grade","subject":"Unknown","score":90},
         {"type":"add_grade","subject":"Physics","score":88}]
        """
        let parsed = AIModeResponseParser.parse(wrap(json), actionContext: context)
        XCTAssertEqual(parsed.actions.count, 1)
        XCTAssertEqual(parsed.actions[0].grade?.score, 88)
    }

    func testTaskParsingAndUnknownSubjectIsCleared() {
        let json = #"[{"type":"add_task","title":" 练习册第3章 ","kind":"reading","dueDate":"2026-10-20 18:30","subject":"???","importance":9}]"#
        let parsed = AIModeResponseParser.parse(wrap(json), actionContext: context)
        let task = parsed.actions.first?.task
        XCTAssertEqual(task?.title, "练习册第3章")
        XCTAssertEqual(task?.type, .reading)
        XCTAssertEqual(task?.subject, "")
        XCTAssertEqual(task?.importance, 5)
        XCTAssertEqual(task?.dueDate, Self.date("2026-10-20 18:30"))
    }

    func testTaskWithoutTitleOrDueDateIsDropped() {
        let json = #"[{"type":"add_task","title":"","dueDate":"2026-10-20"},{"type":"add_task","title":"x"}]"#
        XCTAssertTrue(AIModeResponseParser.parse(wrap(json), actionContext: context).actions.isEmpty)
    }

    func testMalformedJSONYieldsNoActionsButBlockIsStripped() {
        let parsed = AIModeResponseParser.parse(wrap("[{oops"), actionContext: context)
        XCTAssertTrue(parsed.actions.isEmpty)
        XCTAssertEqual(parsed.body, "好的，我来记录。")
    }

    func testUnterminatedBlockWhileStreamingIsHidden() {
        let raw = "Recording it.\n```studypulse-actions\n[{\"type\":\"add_gr"
        let parsed = AIModeResponseParser.parse(raw)
        XCTAssertEqual(parsed.body, "Recording it.")
        XCTAssertTrue(parsed.actions.isEmpty)
    }

    func testWithoutContextNothingIsProposed() {
        let raw = wrap(#"[{"type":"add_grade","subject":"Physics","score":88}]"#)
        XCTAssertTrue(AIModeResponseParser.parse(raw).actions.isEmpty)
    }

    func testAtMostFiveActions() {
        let item = #"{"type":"add_task","title":"t","dueDate":"2026-10-20"}"#
        let json = "[" + Array(repeating: item, count: 8).joined(separator: ",") + "]"
        XCTAssertEqual(AIModeResponseParser.parse(wrap(json), actionContext: context).actions.count, 5)
    }

    func testMessageRoundTripsAndOldPayloadsDecode() throws {
        let action = AIProposedAction(kind: .addTask, task: AITaskDraft(
            title: "t", type: .homework, dueDate: Date(), subject: "", subjectDisplayName: "", notes: "", importance: 3
        ))
        let message = AIChatMessage(conversationID: UUID(), orderIndex: 0, role: .assistant, actions: [action])
        let decoded = try JSONDecoder().decode(AIChatMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.actions, [action])

        let legacy = #"{"id":"\#(UUID().uuidString)","conversationID":"\#(UUID().uuidString)"}"#
        XCTAssertTrue(try JSONDecoder().decode(AIChatMessage.self, from: Data(legacy.utf8)).actions.isEmpty)
    }
}
