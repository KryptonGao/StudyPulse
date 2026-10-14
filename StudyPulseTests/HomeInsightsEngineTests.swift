//
//  HomeInsightsEngineTests.swift
//  StudyPulseTests
//
//  Unit tests for HomeInsightsEngine (Services/HomeInsightsEngine.swift).
//  Pure-function tests: weekly focus, subject snapshots, daily series, week strip.
//

import XCTest
@testable import StudyPulse

@MainActor
final class HomeInsightsEngineTests: XCTestCase {

    private let calendar = Calendar.current
    private let now = Date()

    // MARK: - Helpers

    private func day(_ daysAgo: Int) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
    }

    private func session(
        daysAgo: Int,
        minutes: Int,
        intensity: StudySession.SessionIntensity = .steady,
        completed: Bool = true
    ) -> StudySession {
        StudySession(
            id: UUID(),
            startDate: day(daysAgo).addingTimeInterval(10 * 3600),
            durationSeconds: minutes * 60,
            intensity: intensity,
            completed: completed
        )
    }

    private func grade(_ subject: String, _ score: Double, daysAgo: Int) -> Grade {
        Grade(subject: subject, score: score, importance: 3, date: day(daysAgo), examName: "Exam")
    }

    // MARK: - weeklyFocus

    func test_weeklyFocus_empty_returnsZeroFilledSevenDays() {
        let summary = HomeInsightsEngine.weeklyFocus(sessions: [], now: now)
        XCTAssertEqual(summary.days.count, 7)
        XCTAssertEqual(summary.totalMinutes, 0)
        XCTAssertFalse(summary.hasData)
        XCTAssertTrue(summary.segments.isEmpty)
    }

    func test_weeklyFocus_sumsPerDayAndSplitsByIntensity() {
        let sessions = [
            session(daysAgo: 0, minutes: 30, intensity: .steady),
            session(daysAgo: 0, minutes: 20, intensity: .deepFocus),
            session(daysAgo: 2, minutes: 45, intensity: .steady)
        ]
        let summary = HomeInsightsEngine.weeklyFocus(sessions: sessions, now: now)
        XCTAssertEqual(summary.totalMinutes, 95, accuracy: 0.001)
        XCTAssertEqual(summary.days.last?.minutes ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(summary.segments.filter { $0.date == day(0) }.count, 2)
    }

    func test_weeklyFocus_ignoresIncompleteSessions() {
        let summary = HomeInsightsEngine.weeklyFocus(
            sessions: [session(daysAgo: 0, minutes: 60, completed: false)],
            now: now
        )
        XCTAssertEqual(summary.totalMinutes, 0)
    }

    func test_weeklyFocus_comparesWithPreviousWindow() {
        let sessions = [
            session(daysAgo: 1, minutes: 60),   // current window
            session(daysAgo: 8, minutes: 30),   // previous window
            session(daysAgo: 20, minutes: 90)   // outside both
        ]
        let summary = HomeInsightsEngine.weeklyFocus(sessions: sessions, now: now)
        XCTAssertEqual(summary.totalMinutes, 60, accuracy: 0.001)
        XCTAssertEqual(summary.previousTotalMinutes, 30, accuracy: 0.001)
        XCTAssertEqual(summary.deltaMinutes, 30, accuracy: 0.001)
    }

    // MARK: - subjectSnapshots

    func test_subjectSnapshots_ordersWeakestFirstAndComputesDelta() {
        let grades = [
            grade("Math", 60, daysAgo: 10),
            grade("Math", 80, daysAgo: 5),
            grade("English", 90, daysAgo: 4),
            grade("English", 95, daysAgo: 1)
        ]
        let snapshots = HomeInsightsEngine.subjectSnapshots(grades: grades, fullScoreProvider: { _ in 100 })
        XCTAssertEqual(snapshots.map(\.subject), ["Math", "English"])
        XCTAssertEqual(snapshots[0].averageRate, 0.7, accuracy: 0.001)
        XCTAssertEqual(snapshots[0].deltaPoints ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(snapshots[1].recentRates, [90, 95])
    }

    func test_subjectSnapshots_singleGrade_hasNoDelta() {
        let snapshots = HomeInsightsEngine.subjectSnapshots(
            grades: [grade("Math", 70, daysAgo: 1)],
            fullScoreProvider: { _ in 100 }
        )
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertNil(snapshots[0].deltaPoints)
    }

    func test_subjectSnapshots_respectsLimit() {
        let grades = (0..<8).map { grade("S\($0)", Double(50 + $0), daysAgo: 1) }
        let snapshots = HomeInsightsEngine.subjectSnapshots(grades: grades, fullScoreProvider: { _ in 100 }, limit: 3)
        XCTAssertEqual(snapshots.count, 3)
        XCTAssertEqual(snapshots.first?.subject, "S0")
    }

    // MARK: - Daily series

    func test_sleepSeries_isAscendingAndDropsMissingValues() {
        let history = [
            DailyHealthSnapshot(date: day(0), hrv: nil, restingHeartRate: nil, respiratoryRate: nil,
                                sleepHours: 7.5, deepSleepHours: nil, remSleepHours: nil, exerciseMinutes: nil),
            DailyHealthSnapshot(date: day(2), hrv: nil, restingHeartRate: nil, respiratoryRate: nil,
                                sleepHours: 6, deepSleepHours: nil, remSleepHours: nil, exerciseMinutes: nil),
            DailyHealthSnapshot(date: day(1), hrv: nil, restingHeartRate: nil, respiratoryRate: nil,
                                sleepHours: nil, deepSleepHours: nil, remSleepHours: nil, exerciseMinutes: nil)
        ]
        let series = HomeInsightsEngine.sleepSeries(history: history, now: now)
        XCTAssertEqual(series.map(\.value), [6, 7.5])
        XCTAssertTrue(series[0].date < series[1].date)
    }

    func test_sleepSeries_excludesDaysOutsideWindow() {
        let old = DailyHealthSnapshot(date: day(30), hrv: nil, restingHeartRate: nil, respiratoryRate: nil,
                                      sleepHours: 8, deepSleepHours: nil, remSleepHours: nil, exerciseMinutes: nil)
        XCTAssertTrue(HomeInsightsEngine.sleepSeries(history: [old], now: now, days: 14).isEmpty)
    }

    // MARK: - weekStrip

    func test_weekStrip_returnsSevenAscendingDaysEndingToday() {
        let logs = [DailyActivityLog(date: day(1), mistakeReviews: 3, gradesRecorded: 1, focusMinutes: 10)]
        let strip = HomeInsightsEngine.weekStrip(logs: logs, now: now)
        XCTAssertEqual(strip.count, 7)
        XCTAssertTrue(strip.last?.isToday ?? false)
        XCTAssertEqual(strip.first(where: { $0.date == day(1) })?.points, 18)
        XCTAssertEqual(strip.last?.points, 0)
    }
}
