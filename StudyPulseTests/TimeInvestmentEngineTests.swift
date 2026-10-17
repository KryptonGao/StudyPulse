import Foundation
import SwiftData
import XCTest
@testable import StudyPulse

final class TimeInvestmentEngineTests: XCTestCase {
    private let subjectID = UUID()
    private let parentID = UUID()
    private let childID = UUID()

    private func session(
        target: InvestmentTarget?,
        start: Date = Date(timeIntervalSince1970: 1_800_000_000),
        seconds: Int,
        completed: Bool = true,
        timeZone: String = "UTC"
    ) -> StudySession {
        StudySession(
            id: UUID(),
            startDate: start,
            durationSeconds: seconds,
            intensity: .steady,
            completed: completed,
            investmentTarget: target,
            timeZoneIdentifier: timeZone
        )
    }

    func testThreeLevelAggregationCountsEachSessionOnce() {
        let subject = TimeInvestmentSubject(id: subjectID, name: "Chemistry")
        let parent = SubTask(id: parentID, subjectID: subjectID, name: "Course")
        let child = SubTask(
            id: childID,
            subjectID: subjectID,
            parentSubTaskID: parentID,
            name: "Round Two"
        )
        let aggregator = TimeInvestmentAggregator(
            subjects: [subject],
            subTasks: [parent, child],
            sessions: [
                session(target: .subject(subjectID), seconds: 600),
                session(target: .subTask(parentID), seconds: 1_200),
                session(target: .subTask(childID), seconds: 1_800),
                session(target: nil, seconds: 9_999),
                session(target: .subTask(childID), seconds: 300, completed: false),
            ]
        )

        XCTAssertEqual(aggregator.directSeconds(for: .subject(subjectID)), 600)
        XCTAssertEqual(aggregator.totalSeconds(for: .subTask(childID)), 1_800)
        XCTAssertEqual(aggregator.totalSeconds(for: .subTask(parentID)), 3_000)
        XCTAssertEqual(aggregator.totalSeconds(for: .subject(subjectID)), 3_600)
        XCTAssertEqual(aggregator.totalAssignedSeconds, 3_600)
        XCTAssertEqual(aggregator.unassignedSessions.count, 1)
    }

    func testStreakKeepsYesterdayGraceAndSplitsMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 12))
        )
        let crossingMidnight = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 23, minute: 59))
        )

        XCTAssertEqual(
            StudyStreakCalculator.currentStreak(
                sessions: [session(target: .subject(subjectID), start: crossingMidnight, seconds: 120)],
                now: now,
                calendar: calendar
            ),
            2
        )
    }

    func testStreakResetsAfterGap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let old = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))
        )
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 12))
        )

        XCTAssertEqual(
            StudyStreakCalculator.currentStreak(
                sessions: [session(target: .subject(subjectID), start: old, seconds: 600)],
                now: now,
                calendar: calendar
            ),
            0
        )
    }

    func testRewardUnlocksExactlyAtThresholdAndNeverRelocks() {
        let subject = TimeInvestmentSubject(id: subjectID, name: "Chemistry")
        let reward = GoalReward(
            title: "Movie",
            target: .subject(subjectID),
            thresholdSeconds: 3_600
        )
        let aggregator = TimeInvestmentAggregator(
            subjects: [subject],
            subTasks: [],
            sessions: [session(target: .subject(subjectID), seconds: 3_600)]
        )
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let unlocked = GoalRewardEvaluator.evaluate(
            rewards: [reward],
            aggregator: aggregator,
            now: now
        )

        XCTAssertEqual(unlocked.newlyUnlocked.count, 1)
        XCTAssertEqual(unlocked.rewards[0].unlockedAt, now)

        let empty = TimeInvestmentAggregator(subjects: [subject], subTasks: [], sessions: [])
        let reevaluated = GoalRewardEvaluator.evaluate(
            rewards: unlocked.rewards,
            aggregator: empty,
            now: now.addingTimeInterval(60)
        )
        XCTAssertTrue(reevaluated.newlyUnlocked.isEmpty)
        XCTAssertEqual(reevaluated.rewards[0].unlockedAt, now)
    }

    func testLegacyStudySessionDecodesAsUnassignedTimer() throws {
        let id = UUID()
        let data = Data(
            """
            {
              "id": "\(id.uuidString)",
              "startDate": 0,
              "durationSeconds": 600,
              "intensity": "steady",
              "completed": true
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(StudySession.self, from: data)

        XCTAssertNil(decoded.investmentTarget)
        XCTAssertEqual(decoded.source, .timer)
        XCTAssertNil(decoded.timeZoneIdentifier)
    }
}

@MainActor
final class TimeInvestmentRepositoryTests: XCTestCase {
    func testRepositoryRejectsCycleAndThirdSubTaskLevel() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let repository = DefaultTimeInvestmentRepository()
        await repository.loadAll(context: container.mainContext)

        let subject = TimeInvestmentSubject(name: "Chemistry")
        try repository.upsertSubject(subject)
        let first = SubTask(subjectID: subject.id, name: "Course")
        try repository.upsertSubTask(first)
        let second = SubTask(
            subjectID: subject.id,
            parentSubTaskID: first.id,
            name: "Round Two"
        )
        try repository.upsertSubTask(second)

        XCTAssertThrowsError(
            try repository.upsertSubTask(
                SubTask(
                    subjectID: subject.id,
                    parentSubTaskID: second.id,
                    name: "Too Deep"
                )
            )
        )

        var cyclic = first
        cyclic.parentSubTaskID = second.id
        XCTAssertThrowsError(try repository.upsertSubTask(cyclic))
    }

    func testNewRewardUnlocksImmediatelyWhenThresholdAlreadyMet() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let repository = DefaultTimeInvestmentRepository()
        await repository.loadAll(context: container.mainContext)
        let subject = TimeInvestmentSubject(name: "Chemistry")
        try repository.upsertSubject(subject)
        try repository.upsertReward(
            GoalReward(
                title: "Coffee",
                target: .subject(subject.id),
                thresholdSeconds: 600
            )
        )

        let unlocked = repository.evaluateRewards(
            sessions: [
                StudySession(
                    id: UUID(),
                    startDate: .now,
                    durationSeconds: 600,
                    intensity: .steady,
                    completed: true,
                    investmentTarget: .subject(subject.id)
                )
            ]
        )

        XCTAssertEqual(unlocked.count, 1)
        XCTAssertNotNil(repository.rewards.first?.unlockedAt)
    }
}

// MARK: - Weekly summary

extension TimeInvestmentEngineTests {
    func testWeeklyInvestmentSplitsThisWeekAndPreviousWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 2   // the engine uses Monday-based weeks
        // Wednesday 2027-01-20 12:00 UTC
        let now = Date(timeIntervalSince1970: 1_800_532_800)
        let weekStart = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: now)).start
        let thisWeek = weekStart.addingTimeInterval(3_600)
        let lastWeek = weekStart.addingTimeInterval(-86_400)

        let a = TimeInvestmentSubject(id: UUID(), name: "A")
        let b = TimeInvestmentSubject(id: UUID(), name: "B")
        let aggregator = TimeInvestmentAggregator(
            subjects: [a, b], subTasks: [],
            sessions: [
                session(target: .subject(a.id), start: thisWeek, seconds: 600),
                session(target: .subject(b.id), start: thisWeek, seconds: 1_200),
                session(target: .subject(a.id), start: lastWeek, seconds: 300),
                session(target: nil, start: thisWeek, seconds: 100)
            ]
        )
        let weekly = aggregator.weekly(now: now, calendar: calendar)
        XCTAssertEqual(weekly.totalSeconds, 1_800)
        XCTAssertEqual(weekly.previousTotalSeconds, 300)
        XCTAssertEqual(weekly.rows.map(\.subject.name), ["B", "A"])
        XCTAssertEqual(weekly.unassignedCount, 1)
    }
}
