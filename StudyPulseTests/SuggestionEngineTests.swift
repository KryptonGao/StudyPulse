//
//  SuggestionEngineTests.swift
//  StudyPulseTests
//
//  Unit tests for SuggestionEngine (Services/SuggestionEngine.swift).
//  Tests the 7 find* helpers + the orchestration `generate(from:)` method.
//

import XCTest
import SwiftUI
@testable import StudyPulse

@MainActor
final class SuggestionEngineTests: XCTestCase {

    // Fixed reference: 2026-06-15 12:00:00 UTC
    private let now: Date = {
        var c = DateComponents()
        c.year = 2026
        c.month = 6
        c.day = 15
        c.hour = 12
        c.minute = 0
        c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }()

    private let emptyProfile = UserProfile()

    // MARK: - Helpers

    private func makeGrade(subject: String, score: Double, daysAgo: Int) -> Grade {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return Grade(subject: subject, score: score, date: date, examName: "Exam")
    }

    private func makeMistake(subject: String, daysAgo: Int = 0) -> MistakeNote {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return MistakeNote(
            title: "Q",
            subject: subject,
            originalQuestion: "?",
            source: "Book",
            date: date,
            errorReason: "calc",
            wrongSolution: "?",
            correctSolution: "!"
        )
    }

    private func makeExam(subject: String, daysFromNow: Int) -> Exam {
        let date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: now) ?? now
        return Exam(
            name: "Exam",
            date: date,
            importance: 3,
            subject: subject,
            examName: "Exam",
            masteryDegree: 0
        )
    }

    // MARK: - findWeakSubject

    func test_findWeakSubject_returnsLowestAverageWithMin2Samples() {
        let aggregates: [String: SubjectAggregate] = [
            "Math": SubjectAggregate(subject: "Math", average: 90, count: 3, recentCount: 3, sortedAsc: []),
            "English": SubjectAggregate(subject: "English", average: 70, count: 3, recentCount: 3, sortedAsc: []),
            "Physics": SubjectAggregate(subject: "Physics", average: 80, count: 1, recentCount: 1, sortedAsc: [])
        ]
        // Physics has only 1 sample → excluded; English (70) is weakest
        XCTAssertEqual(SuggestionEngine.findWeakSubject(aggregates: aggregates), "English")
    }

    // MARK: - findStrongSubject

    func test_findStrongSubject_returnsHighestAverageWithMin2Samples() {
        let aggregates: [String: SubjectAggregate] = [
            "Math": SubjectAggregate(subject: "Math", average: 95, count: 4, recentCount: 4, sortedAsc: []),
            "English": SubjectAggregate(subject: "English", average: 75, count: 3, recentCount: 3, sortedAsc: [])
        ]
        XCTAssertEqual(SuggestionEngine.findStrongSubject(aggregates: aggregates), "Math")
    }

    // MARK: - findDecliningTrend

    func test_findDecliningTrend_returnsSubjectWithDescendingScores() {
        // Math: 90 → 80 → 65 (drops 25 over 3 samples)
        let sorted: [Grade] = [
            makeGrade(subject: "Math", score: 90, daysAgo: 30),
            makeGrade(subject: "Math", score: 80, daysAgo: 15),
            makeGrade(subject: "Math", score: 65, daysAgo: 1)
        ]
        let aggregates: [String: SubjectAggregate] = [
            "Math": SubjectAggregate(subject: "Math", average: 78, count: 3, recentCount: 1, sortedAsc: sorted)
        ]
        XCTAssertEqual(SuggestionEngine.findDecliningTrend(aggregates: aggregates), "Math")
    }

    // MARK: - findImprovingTrend

    func test_findImprovingTrend_returnsSubjectWithAscendingScores() {
        // English: 60 → 75 → 88 (rises 28)
        let sorted: [Grade] = [
            makeGrade(subject: "English", score: 60, daysAgo: 30),
            makeGrade(subject: "English", score: 75, daysAgo: 15),
            makeGrade(subject: "English", score: 88, daysAgo: 1)
        ]
        let aggregates: [String: SubjectAggregate] = [
            "English": SubjectAggregate(subject: "English", average: 74, count: 3, recentCount: 1, sortedAsc: sorted)
        ]
        XCTAssertEqual(SuggestionEngine.findImprovingTrend(aggregates: aggregates), "English")
    }

    // MARK: - findMistakeHeavySubject

    func test_findMistakeHeavySubject_returnsSubjectWithManyMistakes() {
        let aggregates: [String: SubjectAggregate] = [
            "Math": SubjectAggregate(subject: "Math", average: 80, count: 2, recentCount: 2, sortedAsc: [])
        ]
        // 6 mistakes > 2 grades * 2 = 4 ✓
        XCTAssertEqual(
            SuggestionEngine.findMistakeHeavySubject(aggregates: aggregates, mistakeCounts: ["Math": 6]),
            "Math"
        )
    }

    // MARK: - findImbalancedStudy

    func test_findImbalancedStudy_returnsSubjectWith3xMoreGrades() {
        // Math:10, English:2, Physics:2 → Math >> avg(2)
        let aggregates: [String: SubjectAggregate] = [
            "Math": SubjectAggregate(subject: "Math", average: 80, count: 10, recentCount: 10, sortedAsc: []),
            "English": SubjectAggregate(subject: "English", average: 80, count: 2, recentCount: 2, sortedAsc: []),
            "Physics": SubjectAggregate(subject: "Physics", average: 80, count: 2, recentCount: 2, sortedAsc: [])
        ]
        XCTAssertEqual(SuggestionEngine.findImbalancedStudy(aggregates: aggregates), "Math")
    }

    // MARK: - Determinism (M-06): tie-breaks must be stable

    func test_findWeakAndStrongSubject_tieBreaksByName() {
        // 同平均分:weak/strong 均应返回科目名字典序较小者
        // Equal averages: both helpers must pick the lexicographically
        // smaller subject name.
        let aggregates: [String: SubjectAggregate] = [
            "Math": SubjectAggregate(subject: "Math", average: 70, count: 3, recentCount: 3, sortedAsc: []),
            "English": SubjectAggregate(subject: "English", average: 70, count: 3, recentCount: 3, sortedAsc: []),
            "Art": SubjectAggregate(subject: "Art", average: 90, count: 3, recentCount: 3, sortedAsc: []),
            "Band": SubjectAggregate(subject: "Band", average: 90, count: 3, recentCount: 3, sortedAsc: [])
        ]
        XCTAssertEqual(SuggestionEngine.findWeakSubject(aggregates: aggregates), "English")
        XCTAssertEqual(SuggestionEngine.findStrongSubject(aggregates: aggregates), "Art")
    }

    func test_findDecliningTrend_picksLargestDrop_andTieBreaksByName() {
        // Math 降 25,Chemistry 降 9 → 取降幅更大的 Math;
        // Math/Physics 同降 20 → 取字典序更小的 Math。
        // Math drops 25 vs Chemistry 9 → Math; equal drops (20) → name order.
        let mathDrop25: [Grade] = [
            makeGrade(subject: "Math", score: 90, daysAgo: 30),
            makeGrade(subject: "Math", score: 80, daysAgo: 15),
            makeGrade(subject: "Math", score: 65, daysAgo: 1)
        ]
        let chemistryDrop9: [Grade] = [
            makeGrade(subject: "Chemistry", score: 80, daysAgo: 30),
            makeGrade(subject: "Chemistry", score: 76, daysAgo: 15),
            makeGrade(subject: "Chemistry", score: 71, daysAgo: 1)
        ]
        var aggregates: [String: SubjectAggregate] = [
            "Math": SubjectAggregate(subject: "Math", average: 78, count: 3, recentCount: 3, sortedAsc: mathDrop25),
            "Chemistry": SubjectAggregate(subject: "Chemistry", average: 75, count: 3, recentCount: 3, sortedAsc: chemistryDrop9)
        ]
        XCTAssertEqual(SuggestionEngine.findDecliningTrend(aggregates: aggregates), "Math")

        let physicsDrop25: [Grade] = [
            makeGrade(subject: "Physics", score: 95, daysAgo: 30),
            makeGrade(subject: "Physics", score: 85, daysAgo: 15),
            makeGrade(subject: "Physics", score: 70, daysAgo: 1)
        ]
        aggregates["Physics"] = SubjectAggregate(
            subject: "Physics", average: 83, count: 3, recentCount: 3, sortedAsc: physicsDrop25
        )
        // Math 与 Physics 均降 25 → 字典序取 Math
        // Equal drops (25) → Math by name order.
        XCTAssertEqual(SuggestionEngine.findDecliningTrend(aggregates: aggregates), "Math")
    }

    func test_findImprovingTrend_picksLargestGain_andTieBreaksByName() {
        let englishGain28: [Grade] = [
            makeGrade(subject: "English", score: 60, daysAgo: 30),
            makeGrade(subject: "English", score: 75, daysAgo: 15),
            makeGrade(subject: "English", score: 88, daysAgo: 1)
        ]
        let germanGain28: [Grade] = [
            makeGrade(subject: "German", score: 55, daysAgo: 30),
            makeGrade(subject: "German", score: 70, daysAgo: 15),
            makeGrade(subject: "German", score: 83, daysAgo: 1)
        ]
        let artGain6: [Grade] = [
            makeGrade(subject: "Art", score: 80, daysAgo: 30),
            makeGrade(subject: "Art", score: 82, daysAgo: 15),
            makeGrade(subject: "Art", score: 86, daysAgo: 1)
        ]
        let aggregates: [String: SubjectAggregate] = [
            "English": SubjectAggregate(subject: "English", average: 74, count: 3, recentCount: 3, sortedAsc: englishGain28),
            "German": SubjectAggregate(subject: "German", average: 69, count: 3, recentCount: 3, sortedAsc: germanGain28),
            "Art": SubjectAggregate(subject: "Art", average: 82, count: 3, recentCount: 3, sortedAsc: artGain6)
        ]
        // English/German 均涨 28 → 字典序取 English;Art 涨 6 落选
        // Equal gains (28) → English by name order; Art (6) loses.
        XCTAssertEqual(SuggestionEngine.findImprovingTrend(aggregates: aggregates), "English")
    }

    func test_findMistakeHeavySubject_tieBreaksByName() {
        // Math/Physics 均满足 mc>=5 && mc>gc*2 → 字典序取 Math
        // Both qualify → Math by name order.
        let aggregates: [String: SubjectAggregate] = [:]
        XCTAssertEqual(
            SuggestionEngine.findMistakeHeavySubject(
                aggregates: aggregates,
                mistakeCounts: ["Physics": 6, "Math": 6]
            ),
            "Math"
        )
    }

    func test_findUnreviewedMistakeSubjects_returnsSortedPrefix() {
        // 错题 ≥ 3 且无成绩:返回字典序前 2 个
        // >= 3 mistakes, no grades: first 2 by name order.
        let subjects = SuggestionEngine.findUnreviewedMistakeSubjects(
            aggregates: [:],
            mistakeCounts: ["Physics": 4, "Art": 3, "Math": 5]
        )
        XCTAssertEqual(subjects, ["Art", "Math"])
    }

    // MARK: - upcomingExamsCount

    func test_upcomingExamsCount_countsWithinWindow() {
        let in5 = makeExam(subject: "Math", daysFromNow: 5)
        let in10 = makeExam(subject: "Math", daysFromNow: 10)
        let in20 = makeExam(subject: "Math", daysFromNow: 20) // outside 14
        let past = makeExam(subject: "Math", daysFromNow: -1)
        let count = SuggestionEngine.upcomingExamsCount(
            examSets: [in5, in10, in20, past],
            now: now,
            windowDays: 14
        )
        XCTAssertEqual(count, 2)
    }

    // MARK: - urgentExamsCount

    func test_urgentExamsCount_includesTodayAndTomorrow() {
        let today = makeExam(subject: "Math", daysFromNow: 0)
        let tomorrow = makeExam(subject: "Math", daysFromNow: 1)
        let count = SuggestionEngine.urgentExamsCount(
            examSets: [today, tomorrow],
            now: now,
            windowDays: 1
        )
        XCTAssertEqual(count, 2)
    }

    // MARK: - generate()

    func test_generate_withNoData_returnsAtLeastLowPrioritySuggestion() {
        let ctx = StudySuggestionsContext(
            grades: [],
            mistakeSets: [],
            examSets: [],
            profile: emptyProfile,
            bodyStatusSuggestion: nil,
            now: now
        )
        let result = SuggestionEngine.generate(from: ctx, max: 3)
        XCTAssertFalse(result.isEmpty)
    }

    func test_generate_bodyStatusSuggestion_takesPriority() {
        let body = StudySuggestion(
            icon: "heart.fill",
            title: "Body says rest",
            description: "Take it easy today",
            priority: .high,
            color: .blue
        )
        let ctx = StudySuggestionsContext(
            grades: [],
            mistakeSets: [],
            examSets: [],
            profile: emptyProfile,
            bodyStatusSuggestion: body,
            now: now
        )
        let result = SuggestionEngine.generate(from: ctx, max: 5)
        XCTAssertEqual(result.first?.title, "Body says rest")
    }
}
