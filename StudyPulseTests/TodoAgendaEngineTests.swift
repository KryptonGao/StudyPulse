//
//  TodoAgendaEngineTests.swift
//  StudyPulseTests
//
//  Pure-function tests for TodoAgendaEngine (day grouping, week strip, counts).
//

import XCTest
@testable import StudyPulse

final class TodoAgendaEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// 2026-10-16 (Friday) 10:00 UTC
    private let now = Date(timeIntervalSince1970: 1_792_144_800)

    private func entry(_ kind: TodoEntryKind, dayOffset: Int, hour: Int = 12, completed: Bool = false, title: String = "T") -> TodoEntry {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now))!
        let date = calendar.date(byAdding: .hour, value: hour, to: day)!
        return TodoEntry(id: UUID(), kind: kind, title: title, subject: "", date: date, endDate: nil, importance: 3,
                         isCompleted: completed, exam: nil, comprehensiveExam: nil, taskItem: nil, routine: nil, routineInstance: nil)
    }

    // MARK: agenda

    func test_agenda_groupsByDayWithTodayAndTomorrow() {
        let days = TodoAgendaEngine.agenda(entries: [
            entry(.homework, dayOffset: 0), entry(.reading, dayOffset: 0, hour: 8),
            entry(.exam, dayOffset: 1), entry(.homework, dayOffset: 3)
        ], now: now, calendar: calendar)
        XCTAssertEqual(days.map(\.kind), [.today, .tomorrow, .day])
        XCTAssertEqual(days.first?.entries.count, 2)
        // earlier time first within a day
        XCTAssertEqual(days.first?.entries.first?.kind, .reading)
    }

    func test_agenda_farEntriesCollapseIntoLater() {
        let days = TodoAgendaEngine.agenda(entries: [entry(.homework, dayOffset: 9), entry(.exam, dayOffset: 20)], now: now, calendar: calendar)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.kind, .later)
        XCTAssertEqual(days.first?.entries.count, 2)
    }

    func test_agenda_excludesPastEntries() {
        XCTAssertTrue(TodoAgendaEngine.agenda(entries: [entry(.homework, dayOffset: -1)], now: now, calendar: calendar).isEmpty)
    }

    func test_agendaDay_completedCount() {
        let days = TodoAgendaEngine.agenda(entries: [entry(.homework, dayOffset: 0, completed: true), entry(.reading, dayOffset: 0)], now: now, calendar: calendar)
        XCTAssertEqual(days.first?.completedCount, 1)
    }

    // MARK: week strip

    func test_weekStrip_startsMondayAndMarksToday() {
        let strip = TodoAgendaEngine.weekStrip(entries: [], now: now, calendar: calendar)
        XCTAssertEqual(strip.count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: strip[0].date), 2)       // Monday
        XCTAssertEqual(strip.filter(\.isToday).count, 1)
        XCTAssertEqual(strip.firstIndex(where: \.isToday), 4)                       // Friday
    }

    func test_weekStrip_dotsAreDistinctKindsMaxThreeAndSkipCompleted() {
        let strip = TodoAgendaEngine.weekStrip(entries: [
            entry(.homework, dayOffset: 0), entry(.homework, dayOffset: 0), entry(.exam, dayOffset: 0),
            entry(.reading, dayOffset: 0), entry(.routine, dayOffset: 0), entry(.reading, dayOffset: 1, completed: true)
        ], now: now, calendar: calendar)
        let today = strip.first(where: \.isToday)
        XCTAssertEqual(today?.kinds.count, 3)
        XCTAssertEqual(today?.count, 5)
        XCTAssertEqual(strip[5].count, 0)
    }

    // MARK: counts / helpers

    func test_counts_mergeExamKindsAndSkipCompleted() {
        let c = TodoAgendaEngine.counts(entries: [
            entry(.exam, dayOffset: 1), entry(.comprehensiveExam, dayOffset: 2), entry(.homework, dayOffset: 0),
            entry(.reading, dayOffset: 0, completed: true), entry(.routine, dayOffset: 0)
        ])
        XCTAssertEqual(c, TodoTypeCounts(all: 4, exam: 2, homework: 1, reading: 0, routine: 1))
    }

    func test_daysUntil_usesCalendarDays() {
        let lateTonight = calendar.date(byAdding: .hour, value: 13, to: calendar.startOfDay(for: now))!
        XCTAssertEqual(TodoAgendaEngine.daysUntil(lateTonight, now: now, calendar: calendar), 0)
        let tomorrowMorning = calendar.date(byAdding: .hour, value: 2, to: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!)!
        XCTAssertEqual(TodoAgendaEngine.daysUntil(tomorrowMorning, now: now, calendar: calendar), 1)
    }

    func test_checklistProgress() {
        var exam = TestDataFixtures.makeExam()
        XCTAssertNil(TodoAgendaEngine.checklistProgress(exam))
        exam.checklist = [ExamChecklistItem(title: "a", isChecked: true), ExamChecklistItem(title: "b", isChecked: false)]
        let progress = TodoAgendaEngine.checklistProgress(exam)
        XCTAssertEqual(progress?.done, 1)
        XCTAssertEqual(progress?.total, 2)
    }
}
