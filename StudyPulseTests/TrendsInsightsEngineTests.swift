//
//  TrendsInsightsEngineTests.swift
//  StudyPulseTests
//
//  Pure-function tests for TrendsInsightsEngine (overall trend, subject rows, attention).
//

import XCTest
@testable import StudyPulse

final class TrendsInsightsEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func grade(_ subject: String, _ score: Double, daysAgo: Int, ranking: Int? = nil) -> Grade {
        TestDataFixtures.makeGrade(
            subject: subject, score: score, ranking: ranking,
            date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!, fullScore: 100
        )
    }

    // MARK: recentDelta

    func test_recentDelta_needsTwoScores() {
        XCTAssertEqual(TrendsInsightsEngine.recentDelta([]), 0)
        XCTAssertEqual(TrendsInsightsEngine.recentDelta([80]), 0)
    }

    func test_recentDelta_twoScores_isLastMinusPrevious() {
        XCTAssertEqual(TrendsInsightsEngine.recentDelta([70, 80]), 10, accuracy: 0.0001)
    }

    func test_recentDelta_comparesLastThreeAgainstPreviousThree() {
        // before = [60,60,60] avg 60, recent = [70,80,90] avg 80
        XCTAssertEqual(TrendsInsightsEngine.recentDelta([60, 60, 60, 70, 80, 90]), 20, accuracy: 0.0001)
    }

    // MARK: overall

    func test_overall_emptyGrades_isEmpty() {
        let result = TrendsInsightsEngine.overall(grades: [], fullScores: [:], range: .days30, now: now, calendar: calendar)
        XCTAssertEqual(result, .empty)
    }

    func test_overall_filtersByRange_andAveragesScoreRate() {
        let grades = [grade("Math", 80, daysAgo: 5), grade("Math", 60, daysAgo: 10), grade("Math", 10, daysAgo: 100)]
        let result = TrendsInsightsEngine.overall(grades: grades, fullScores: ["Math": 100], range: .days30, now: now, calendar: calendar)
        XCTAssertEqual(result.gradeCount, 2)
        XCTAssertEqual(result.average ?? 0, 70, accuracy: 0.0001)
        XCTAssertEqual(result.points.count, 2)
    }

    func test_overall_deltaComparesWithPreviousWindow() {
        // current window (30d): 80 · previous window (30–60d): 60  → +20
        let grades = [grade("Math", 80, daysAgo: 5), grade("Math", 60, daysAgo: 40)]
        let result = TrendsInsightsEngine.overall(grades: grades, fullScores: ["Math": 100], range: .days30, now: now, calendar: calendar)
        XCTAssertEqual(result.delta ?? 0, 20, accuracy: 0.0001)
    }

    func test_overall_allRange_hasNoDelta() {
        let result = TrendsInsightsEngine.overall(
            grades: [grade("Math", 80, daysAgo: 5)], fullScores: ["Math": 100], range: .all, now: now, calendar: calendar
        )
        XCTAssertNil(result.delta)
    }

    func test_overall_targetRateFromPhaseGoals() {
        let goals = [PhaseGoal(subject: "Math", targetScore: 90), PhaseGoal(subject: "English", targetScore: 60)]
        let result = TrendsInsightsEngine.overall(
            grades: [grade("Math", 80, daysAgo: 1)], fullScores: ["Math": 100, "English": 100],
            range: .days30, targets: goals, now: now, calendar: calendar
        )
        XCTAssertEqual(result.targetRate ?? 0, 75, accuracy: 0.0001)
    }

    // MARK: rank

    func test_rank_ignoresGradesWithoutRanking() {
        let grades = [grade("Math", 80, daysAgo: 1, ranking: 10), grade("Math", 80, daysAgo: 2)]
        let result = TrendsInsightsEngine.rank(grades: grades, range: .days30, now: now, calendar: calendar)
        XCTAssertEqual(result.gradeCount, 1)
        XCTAssertEqual(result.average ?? 0, 10, accuracy: 0.0001)
    }

    // MARK: subject rows

    func test_subjectRows_biggestDeclineFirst() {
        let rows = TrendsInsightsEngine.subjectRows(gradesBySubject: [
            "Math": [grade("Math", 90, daysAgo: 20), grade("Math", 70, daysAgo: 1)],
            "English": [grade("English", 70, daysAgo: 20), grade("English", 90, daysAgo: 1)]
        ])
        XCTAssertEqual(rows.map(\.subject), ["Math", "English"])
        XCTAssertEqual(rows.first?.delta ?? 0, -20, accuracy: 0.0001)
        XCTAssertEqual(rows.first?.latest, 70)
    }

    func test_subjectRows_sparkKeepsLastSixAscending() {
        let grades = (0..<8).map { grade("Math", Double(50 + $0), daysAgo: 8 - $0) }
        let row = TrendsInsightsEngine.subjectRows(gradesBySubject: ["Math": grades]).first
        XCTAssertEqual(row?.spark, [52, 53, 54, 55, 56, 57])
    }

    // MARK: attention

    func test_attention_countsTrailingDeclinesAndGap() {
        let grades = [grade("Math", 90, daysAgo: 4), grade("Math", 80, daysAgo: 3), grade("Math", 70, daysAgo: 2), grade("Math", 60, daysAgo: 1)]
        let insight = TrendsInsightsEngine.attention(subject: "Math", grades: grades, target: 85, dueMistakes: 6, nextExamInDays: 3)
        XCTAssertEqual(insight.consecutiveDeclines, 3)
        XCTAssertEqual(insight.gapToTarget ?? 0, 10, accuracy: 0.0001)
        XCTAssertEqual(insight.dueMistakes, 6)
        XCTAssertEqual(insight.nextExamInDays, 3)
    }

    func test_attention_noTarget_hasNoGap() {
        let insight = TrendsInsightsEngine.attention(subject: "Math", grades: [grade("Math", 60, daysAgo: 1)], target: nil, dueMistakes: 0, nextExamInDays: nil)
        XCTAssertNil(insight.gapToTarget)
        XCTAssertEqual(insight.consecutiveDeclines, 0)
    }
}
