//
//  HomeDynamicLayoutEngineTests.swift
//  StudyPulseTests
//
//  Unit tests for HomeDynamicLayoutEngine and HomeLayoutPreference's dynamicLayoutEnabled field.
//

import XCTest
@testable import StudyPulse

final class HomeDynamicLayoutEngineTests: XCTestCase {

    func test_arrange_hidesCardsWithoutInformation() {
        let result = HomeDynamicLayoutEngine.arrange(
            enabled: [.weeklyFocus, .flashcardReview, .upcomingExams, .quickActions],
            signals: HomeCardSignals()
        )
        XCTAssertEqual(result, [.quickActions])
    }

    func test_arrange_ordersByUrgency() {
        var signals = HomeCardSignals()
        signals.nextExamDays = 2
        signals.dueFlashcards = 5
        signals.weeklyFocusHasData = true
        let result = HomeDynamicLayoutEngine.arrange(
            enabled: [.weeklyFocus, .quickActions, .flashcardReview, .upcomingExams],
            signals: signals
        )
        XCTAssertEqual(result, [.upcomingExams, .flashcardReview, .weeklyFocus, .quickActions])
    }

    func test_arrange_tieKeepsIncomingOrder() {
        var signals = HomeCardSignals()
        signals.nextExamDays = 30
        let a = HomeDynamicLayoutEngine.arrange(enabled: [.studyTimer, .streakProgress], signals: {
            var s = signals; s.currentStreak = 1; return s
        }())
        XCTAssertEqual(a, [.studyTimer, .streakProgress])
    }

    func test_arrange_eveningDiaryWithoutEntryRisesAboveTimer() {
        var signals = HomeCardSignals()
        signals.hour = 21
        let result = HomeDynamicLayoutEngine.arrange(enabled: [.studyTimer, .diary], signals: signals)
        XCTAssertEqual(result, [.diary, .studyTimer])
    }

    func test_arrange_habitInsightNeedsThreeSessions() {
        var signals = HomeCardSignals()
        signals.completedSessionCount = 2
        XCTAssertTrue(HomeDynamicLayoutEngine.arrange(enabled: [.habitInsight], signals: signals).isEmpty)
        signals.completedSessionCount = 3
        XCTAssertEqual(HomeDynamicLayoutEngine.arrange(enabled: [.habitInsight], signals: signals), [.habitInsight])
    }

    func test_everyCardTypeHasPriorityAndInformationRule() {
        let signals = HomeCardSignals()
        for type in HomeCardType.allCases {
            _ = HomeDynamicLayoutEngine.hasInformation(type, signals: signals)
            _ = HomeDynamicLayoutEngine.priority(type, signals: signals)
        }
    }

    func test_layoutPreference_decodesOldDataWithoutDynamicFlag() throws {
        let old = #"{"items":[{"type":"dailyPlan","enabled":true}]}"#
        let decoded = try JSONDecoder().decode(HomeLayoutPreference.self, from: Data(old.utf8))
        XCTAssertFalse(decoded.dynamicLayoutEnabled)
        XCTAssertEqual(decoded.items.count, 1)
    }

    func test_layoutPreference_roundTripsDynamicFlag() throws {
        let pref = HomeLayoutPreference(items: [HomeCardItem(type: .dailyPlan, enabled: true)], dynamicLayoutEnabled: true)
        let data = try JSONEncoder().encode(pref)
        XCTAssertEqual(try JSONDecoder().decode(HomeLayoutPreference.self, from: data), pref)
    }
}
