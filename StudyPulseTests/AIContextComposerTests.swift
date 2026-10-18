import XCTest
@testable import StudyPulse

final class AIContextComposerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func snapshot(phaseName: String? = "Spring", phaseId: UUID? = nil) -> AIStudyDataSnapshot {
        var snapshot = AIStudyDataSnapshot()
        snapshot.phaseName = phaseName
        snapshot.phaseId = phaseId
        return snapshot
    }

    // MARK: Routing

    func testRouteMatchesKeywordsInSeveralLanguages() {
        XCTAssertEqual(AIContextComposer.route("我的成绩怎么样"), [.grades])
        XCTAssertEqual(AIContextComposer.route("how is my sleep and my mood"), [.health, .diary])
        XCTAssertEqual(AIContextComposer.route("試験の準備"), [.exams])
        XCTAssertEqual(AIContextComposer.route("오답 복습"), [.mistakes])
        XCTAssertEqual(AIContextComposer.route(""), [])
        XCTAssertEqual(AIContextComposer.route("hello there"), [])
    }

    func testSelectDomainsFallsBackToGradesAndMistakes() {
        XCTAssertEqual(
            AIContextComposer.selectDomains(userText: "hi", references: [], mode: .deep),
            [.grades, .mistakes]
        )
    }

    func testSelectDomainsPutsReferencesFirstAndCapsByMode() {
        let reference = AIDataReference(domain: .time, scopeLabel: "t")
        let text = "成绩 错题 考试 睡眠"
        let deep = AIContextComposer.selectDomains(userText: text, references: [reference], mode: .deep)
        XCTAssertEqual(deep.first, .time)
        XCTAssertEqual(deep.count, 3)
        let quick = AIContextComposer.selectDomains(userText: text, references: [reference], mode: .quick)
        XCTAssertEqual(quick.first, .time)
        XCTAssertEqual(quick.count, 2)
    }

    func testSelectDomainsKeepsEveryReferenceEvenBeyondTheCap() {
        let refs = [AIDataDomain.grades, .mistakes, .exams, .time].map {
            AIDataReference(domain: $0, scopeLabel: $0.rawValue)
        }
        let result = AIContextComposer.selectDomains(userText: "", references: refs, mode: .quick)
        XCTAssertEqual(result.count, 4)
    }

    // MARK: Compose

    func testComposeStatesPhaseScopeAndUnfilteredDomains() {
        let payload = AIContextComposer.compose(
            userText: "成绩", references: [], snapshot: snapshot(phaseName: "Spring"), mode: .deep, now: now
        )
        XCTAssertTrue(payload.text.contains("「Spring」"))
        XCTAssertTrue(payload.text.contains("不受阶段筛选"))
    }

    func testComposeStatesWhenNoPhaseIsSelected() {
        let payload = AIContextComposer.compose(
            userText: "成绩", references: [], snapshot: snapshot(phaseName: nil), mode: .deep, now: now
        )
        XCTAssertTrue(payload.text.contains("未选择学习阶段"))
    }

    func testEmptyGradesAreMarkedInsufficientInsteadOfInvented() {
        let payload = AIContextComposer.compose(
            userText: "我的成绩", references: [], snapshot: snapshot(), mode: .deep, now: now
        )
        XCTAssertTrue(payload.domains.contains(.grades))
        XCTAssertTrue(payload.insufficientDomains.contains(.grades))
        XCTAssertTrue(payload.text.contains("资料不足"))
    }

    func testHealthIsFlaggedOnlyWhenAvailable() {
        var unavailable = snapshot()
        unavailable.health = AIHealthSnapshot(state: .unauthorized)
        let off = AIContextComposer.compose(
            userText: "睡眠", references: [], snapshot: unavailable, mode: .deep, now: now
        )
        XCTAssertFalse(off.containsHealth)
        XCTAssertTrue(off.insufficientDomains.contains(.health))

        var available = snapshot()
        available.health = AIHealthSnapshot(state: .available, recoveryScore: 72, sleepHours: 7)
        let on = AIContextComposer.compose(
            userText: "睡眠", references: [], snapshot: available, mode: .deep, now: now
        )
        XCTAssertTrue(on.containsHealth)
        XCTAssertTrue(on.text.contains("恢复分 72/100"))
    }

    func testDeletedReferencedRecordsAreNotedNotInvented() {
        let missing = UUID()
        let reference = AIDataReference(domain: .mistakes, scopeLabel: "m", recordIDs: [missing])
        let payload = AIContextComposer.compose(
            userText: "", references: [reference], snapshot: snapshot(), mode: .deep,
            existingRecordIDs: [], now: now
        )
        XCTAssertTrue(payload.text.contains("已被删除"))
    }

    func testPhaseMismatchOnReferenceIsNoted() {
        let reference = AIDataReference(domain: .grades, scopeLabel: "g", phaseId: UUID())
        let payload = AIContextComposer.compose(
            userText: "", references: [reference], snapshot: snapshot(phaseId: UUID()), mode: .deep, now: now
        )
        XCTAssertTrue(payload.text.contains("其他学习阶段"))
    }

    func testComposedTextStaysWithinBudget() {
        var big = snapshot()
        big.mistakes = AIMistakesSnapshot(
            total: 500, masteredCount: 1, review: .empty, subjects: [],
            priority: (0..<200).map {
                AIMistakeRow(id: UUID(), title: String(repeating: "长标题", count: 40) + "\($0)",
                             subject: "Math", mastery: 0.3, daysUntilReview: 1)
            },
            patterns: []
        )
        let payload = AIContextComposer.compose(
            userText: "错题", references: [], snapshot: big, mode: .quick, now: now
        )
        XCTAssertLessThanOrEqual(payload.text.count, AIContextComposer.quickBudget + 401)
    }

    func testGradeRangeMapping() {
        XCTAssertEqual(AIContextComposer.gradeRange(for: .last30Days), .days30)
        XCTAssertEqual(AIContextComposer.gradeRange(for: .last90Days), .days90)
        XCTAssertEqual(AIContextComposer.gradeRange(for: .phaseAll), .phase)
    }
}
