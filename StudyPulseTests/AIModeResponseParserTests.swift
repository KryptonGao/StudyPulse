import XCTest
@testable import StudyPulse

final class AIModeResponseParserTests: XCTestCase {
    func testPlainReplyHasNoFollowUps() {
        let parsed = AIModeResponseParser.parse("Just an answer.")
        XCTAssertEqual(parsed.body, "Just an answer.")
        XCTAssertTrue(parsed.followUps.isEmpty)
    }

    func testFollowUpSectionIsSplitOffInEveryLanguage() {
        for heading in ["继续追问", "繼續追問", "Follow-up questions", "続けて質問", "이어서 질문"] {
            let raw = "Body text\n\n## \(heading)\n- First?\n- Second?\n"
            let parsed = AIModeResponseParser.parse(raw)
            XCTAssertEqual(parsed.body, "Body text", heading)
            XCTAssertEqual(parsed.followUps, ["First?", "Second?"], heading)
        }
    }

    func testAtMostThreeFollowUpsAndListMarkersStripped() {
        let raw = "A\n## Follow-up questions\n1. One\n2) Two\n* Three\n- Four\n"
        let parsed = AIModeResponseParser.parse(raw)
        XCTAssertEqual(parsed.followUps, ["One", "Two", "Three"])
    }

    func testThinkBlocksAreRemoved() {
        let parsed = AIModeResponseParser.parse("<think>secret reasoning</think>Visible answer")
        XCTAssertEqual(parsed.body, "Visible answer")
    }

    func testUnterminatedThinkWhileStreamingHidesReasoning() {
        XCTAssertEqual(AIModeResponseParser.stripThinking("Hello <think>still reasoning"), "Hello ")
    }

    func testStrayClosingThinkTagDropsEarlierReasoning() {
        XCTAssertEqual(AIModeResponseParser.stripThinking("reasoning</think>Answer"), "Answer")
    }

    func testPartialStreamingFollowUpHeadingDoesNotCrash() {
        let parsed = AIModeResponseParser.parse("Body\n## Follow-up")
        XCTAssertFalse(parsed.body.isEmpty)
    }

    func testHeadingForLocale() {
        XCTAssertEqual(AIModeResponseParser.heading(forLocale: "zh-Hant-TW"), "繼續追問")
        XCTAssertEqual(AIModeResponseParser.heading(forLocale: "zh-Hans"), "继续追问")
        XCTAssertEqual(AIModeResponseParser.heading(forLocale: "ja"), "続けて質問")
        XCTAssertEqual(AIModeResponseParser.heading(forLocale: "ko-KR"), "이어서 질문")
        XCTAssertEqual(AIModeResponseParser.heading(forLocale: nil), "Follow-up questions")
    }
}
