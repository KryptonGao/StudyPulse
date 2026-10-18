import XCTest
@testable import StudyPulse

final class AIStudyDataEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    private var calendar: Calendar { Calendar.current }

    private func daysAgo(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: -n, to: now)!
    }

    // MARK: Grades

    func testGradesEmptyWhenNoRecords() {
        let snapshot = AIStudyDataEngine.grades(grades: [], fullScores: [:], range: .days30, now: now, calendar: calendar)
        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertFalse(snapshot.hasEnoughForTrend)
    }

    func testSingleGradeIsNotEnoughForTrend() {
        let grade = TestDataFixtures.makeGrade(score: 90, date: daysAgo(3), fullScore: 100)
        let snapshot = AIStudyDataEngine.grades(grades: [grade], fullScores: ["Math": 100], range: .days30, now: now, calendar: calendar)
        XCTAssertEqual(snapshot.gradeCount, 1)
        XCTAssertFalse(snapshot.hasEnoughForTrend)
    }

    func testRangeFiltersOlderGradesAndUsesPerGradeFullScore() throws {
        let recent = TestDataFixtures.makeGrade(subject: "Math", score: 90, date: daysAgo(5), fullScore: 150)
        let recent2 = TestDataFixtures.makeGrade(subject: "Math", score: 120, date: daysAgo(2), fullScore: 150)
        let old = TestDataFixtures.makeGrade(subject: "Math", score: 40, date: daysAgo(60), fullScore: 150)
        let grades = [recent, recent2, old]

        let thirty = AIStudyDataEngine.grades(grades: grades, fullScores: ["Math": 150], range: .days30, now: now, calendar: calendar)
        XCTAssertEqual(thirty.gradeCount, 2)
        let row = try XCTUnwrap(thirty.rows.first)
        XCTAssertEqual(row.fullScore, 150)
        XCTAssertEqual(row.averageScore, 105, accuracy: 0.001)
        // 105 / 150 = 70 %
        XCTAssertEqual(row.averageRate, 70, accuracy: 0.001)

        let ninety = AIStudyDataEngine.grades(grades: grades, fullScores: ["Math": 150], range: .days90, now: now, calendar: calendar)
        XCTAssertEqual(ninety.gradeCount, 3)
    }

    func testAllGradesProducesEveryRange() {
        let result = AIStudyDataEngine.allGrades(grades: [], fullScores: [:], now: now, calendar: calendar)
        XCTAssertEqual(Set(result.keys), Set(AIGradeRange.allCases))
    }

    // MARK: Mistakes

    func testMistakesEmpty() {
        XCTAssertTrue(AIStudyDataEngine.mistakes(mistakes: [], now: now, calendar: calendar).isEmpty)
    }

    func testMistakesCountsMasteredByThreshold() {
        var mastered = TestDataFixtures.makeMistakeNote(title: "A")
        mastered.masteryScore = 0.9
        var weak = TestDataFixtures.makeMistakeNote(title: "B")
        weak.masteryScore = 0.2
        let snapshot = AIStudyDataEngine.mistakes(mistakes: [mastered, weak], now: now, calendar: calendar)
        XCTAssertEqual(snapshot.total, 2)
        XCTAssertEqual(snapshot.masteredCount, 1)
    }

    // MARK: Health

    private func healthInput(
        enabled: Bool = true, onboarded: Bool = true, authorized: Bool = true,
        loading: Bool = false, category: String = "normal", score: Int? = 70
    ) -> AIHealthInput {
        AIHealthInput(
            hrvEnabled: enabled, onboardingCompleted: onboarded, isAuthorized: authorized,
            isLoading: loading, readinessCategory: category, hrvZScore: nil, todayHRV: nil,
            bodyUsable: true, restingHeartRate: 60, respiratoryRate: nil, sleepHours: 7,
            restorativeSleepHours: 3, exerciseMinutes: 20, recoveryScore: score
        )
    }

    func testHealthStates() {
        XCTAssertEqual(AIStudyDataEngine.health(healthInput(enabled: false)).state, .disabled)
        XCTAssertEqual(AIStudyDataEngine.health(healthInput(onboarded: false)).state, .disabled)
        XCTAssertEqual(AIStudyDataEngine.health(healthInput(authorized: false)).state, .unauthorized)
        XCTAssertEqual(AIStudyDataEngine.health(healthInput(loading: true)).state, .loading)
        XCTAssertEqual(AIStudyDataEngine.health(healthInput(category: "loading")).state, .loading)
        XCTAssertEqual(AIStudyDataEngine.health(healthInput(score: nil)).state, .insufficient)
        let available = AIStudyDataEngine.health(healthInput())
        XCTAssertEqual(available.state, .available)
        XCTAssertEqual(available.recoveryScore, 70)
    }

    // MARK: Diary

    func testDiaryEmptyAndStreak() {
        XCTAssertTrue(AIStudyDataEngine.diary(entries: [], now: now, calendar: calendar).isEmpty)

        let entries = [0, 1, 2].map {
            DiaryEntry(date: daysAgo($0), moodScore: 4, energyScore: 3, energyTag: "专注", content: "d\($0)")
        }
        XCTAssertEqual(AIStudyDataEngine.diaryStreak(entries: entries, now: now, calendar: calendar), 3)
    }

    func testDiaryStreakSurvivesUnwrittenToday() {
        let entries = [1, 2].map {
            DiaryEntry(date: daysAgo($0), moodScore: 3, energyScore: 3, energyTag: "平静", content: "x")
        }
        XCTAssertEqual(AIStudyDataEngine.diaryStreak(entries: entries, now: now, calendar: calendar), 2)
    }

    func testDiaryStreakBreaksOnGap() {
        let entries = [0, 3].map {
            DiaryEntry(date: daysAgo($0), moodScore: 3, energyScore: 3, energyTag: "平静", content: "x")
        }
        XCTAssertEqual(AIStudyDataEngine.diaryStreak(entries: entries, now: now, calendar: calendar), 1)
    }
}
