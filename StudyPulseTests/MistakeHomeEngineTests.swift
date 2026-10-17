//
//  MistakeHomeEngineTests.swift
//  StudyPulseTests
//
//  Pure-function tests for MistakeHomeEngine (review breakdown, subject summaries, recents).
//

import XCTest
@testable import StudyPulse

final class MistakeHomeEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ subject: String, nextReviewInDays: Int?, mastery: Double = 0, createdDaysAgo: Int = 0) -> MistakeNote {
        var n = TestDataFixtures.makeMistakeNote(
            subject: subject,
            date: calendar.date(byAdding: .day, value: -createdDaysAgo, to: now)!,
            reviewState: nextReviewInDays.map {
                ReviewState(nextReviewDate: calendar.date(byAdding: .day, value: $0, to: now)!)
            }
        )
        n.masteryScore = mastery
        return n
    }

    // MARK: review

    func test_review_noEnrolledNotes_isEmpty() {
        XCTAssertEqual(MistakeHomeEngine.review(mistakes: [note("Math", nextReviewInDays: nil)], now: now, calendar: calendar), .empty)
    }

    func test_review_countsDueOverdueUpcomingAndMinutes() {
        let notes = [
            note("Physics", nextReviewInDays: -3),
            note("Physics", nextReviewInDays: 0),
            note("Math", nextReviewInDays: -1),
            note("Math", nextReviewInDays: 3)          // upcoming, not due
        ]
        let result = MistakeHomeEngine.review(mistakes: notes, now: now, calendar: calendar)
        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.upcoming, 1)
        XCTAssertGreaterThanOrEqual(result.overdue, 2)
        XCTAssertEqual(result.bySubject.first?.subject, "Physics")
        XCTAssertEqual(result.bySubject.first?.count, 2)
        XCTAssertEqual(result.estimatedMinutes, Int((3 * MistakeHomeEngine.minutesPerCard).rounded(.up)))
    }

    // MARK: summaries

    func test_subjectSummaries_sortsByDueThenCount() {
        let notes = [
            note("Math", nextReviewInDays: 5, mastery: 0.5),
            note("Math", nextReviewInDays: 6, mastery: 0.7),
            note("Physics", nextReviewInDays: -1, mastery: 0.2)
        ]
        let result = MistakeHomeEngine.subjectSummaries(mistakes: notes, now: now)
        XCTAssertEqual(result.map(\.subject), ["Physics", "Math"])
        XCTAssertEqual(result.first?.due, 1)
        XCTAssertEqual(result.last?.mastery ?? 0, 0.6, accuracy: 0.0001)
    }

    // MARK: recent

    func test_recent_returnsNewestFirstWithLimit() {
        let notes = [note("A", nextReviewInDays: nil, createdDaysAgo: 5), note("B", nextReviewInDays: nil, createdDaysAgo: 1), note("C", nextReviewInDays: nil, createdDaysAgo: 3)]
        XCTAssertEqual(MistakeHomeEngine.recent(mistakes: notes, limit: 2).map(\.subject), ["B", "C"])
    }

    // MARK: daysUntilReview

    func test_daysUntilReview() {
        XCTAssertNil(MistakeHomeEngine.daysUntilReview(note("Math", nextReviewInDays: nil), now: now, calendar: calendar))
        XCTAssertEqual(MistakeHomeEngine.daysUntilReview(note("Math", nextReviewInDays: -2), now: now, calendar: calendar), -2)
        XCTAssertEqual(MistakeHomeEngine.daysUntilReview(note("Math", nextReviewInDays: 4), now: now, calendar: calendar), 4)
    }
}
