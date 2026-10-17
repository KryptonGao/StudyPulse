//
//  MistakeHomeEngine.swift
//  StudyPulse
//
//  错题首页的纯函数聚合:今日复习分解 / 科目汇总 / 最近新增。
//  Pure aggregation for the Mistakes home: today's review breakdown, subject
//  summaries and recent additions.
//

import Foundation

nonisolated struct MistakeReviewBreakdown: Equatable, Sendable {
    struct SubjectDue: Identifiable, Equatable, Sendable {
        let subject: String
        let count: Int
        var id: String { subject }
    }

    /// 已到期(含逾期)总数 / Total due (including overdue).
    var total: Int
    /// 在今天 00:00 之前就到期的数量 / Due before the start of today.
    var overdue: Int
    /// 未来一周内到期 / Due within the upcoming week (not yet due).
    var upcoming: Int
    /// 按到期数降序 / Descending by due count.
    var bySubject: [SubjectDue]
    var estimatedMinutes: Int

    static let empty = MistakeReviewBreakdown(total: 0, overdue: 0, upcoming: 0, bySubject: [], estimatedMinutes: 0)
}

nonisolated struct MistakeSubjectSummary: Identifiable, Equatable, Sendable {
    let subject: String
    let count: Int
    let due: Int
    /// 平均掌握度 0...1 / Mean mastery 0...1.
    let mastery: Double
    var id: String { subject }
}

nonisolated enum MistakeHomeEngine {
    /// 每张闪卡的预估用时(分钟)/ Estimated minutes per flashcard.
    static let minutesPerCard = 1.4

    static func review(
        mistakes: [MistakeNote],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MistakeReviewBreakdown {
        let dueNotes = SRSAlgorithm.dueMistakes(from: mistakes, now: now)
        guard !dueNotes.isEmpty || mistakes.contains(where: { $0.reviewState != nil }) else { return .empty }

        let startOfToday = calendar.startOfDay(for: now)
        let overdue = dueNotes.filter { ($0.reviewState?.nextReviewDate ?? now) < startOfToday }.count

        var counts: [String: Int] = [:]
        for note in dueNotes { counts[note.subject, default: 0] += 1 }
        let bySubject = counts
            .map { MistakeReviewBreakdown.SubjectDue(subject: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.subject < $1.subject }

        let overview = SRSAlgorithm.overview(from: mistakes, now: now)
        return MistakeReviewBreakdown(
            total: dueNotes.count,
            overdue: overdue,
            upcoming: overview.upcomingCount,
            bySubject: bySubject,
            estimatedMinutes: Int((Double(dueNotes.count) * minutesPerCard).rounded(.up))
        )
    }

    /// 科目汇总:到期多的在前,其次错题多的在前。
    /// Subject summaries: more due first, then more mistakes first.
    static func subjectSummaries(
        mistakes: [MistakeNote],
        now: Date = Date()
    ) -> [MistakeSubjectSummary] {
        var grouped: [String: [MistakeNote]] = [:]
        for note in mistakes { grouped[note.subject, default: []].append(note) }

        let summaries = grouped.map { subject, notes -> MistakeSubjectSummary in
            let due = notes.filter { ($0.reviewState?.nextReviewDate).map { $0 <= now } ?? false }.count
            let mastery = notes.map(\.masteryScore).reduce(0, +) / Double(max(notes.count, 1))
            return MistakeSubjectSummary(subject: subject, count: notes.count, due: due, mastery: mastery)
        }
        return summaries.sorted {
            if $0.due != $1.due { return $0.due > $1.due }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.subject < $1.subject
        }
    }

    static func recent(mistakes: [MistakeNote], limit: Int) -> [MistakeNote] {
        Array(mistakes.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// 单条错题的复习状态描述用的天数:负数=已逾期,0=今天,nil=未入队。
    /// Days until review: negative = overdue, 0 = today, nil = not enrolled.
    static func daysUntilReview(_ note: MistakeNote, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let next = note.reviewState?.nextReviewDate else { return nil }
        let from = calendar.startOfDay(for: now)
        let to = calendar.startOfDay(for: next)
        return calendar.dateComponents([.day], from: from, to: to).day
    }
}
