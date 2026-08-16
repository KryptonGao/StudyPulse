//
//  RemediationTaskEngine.swift
//  StudyPulse
//
//  15 分钟最小补救任务生成器：纯函数、无 SwiftUI、无 I/O。
//  Generates a bounded 15-minute remediation task from a memory-climate
//  snapshot. Pure function, no SwiftUI, no I/O.
//

import Foundation

nonisolated enum RemediationTaskEngine {
    /// 任务时长上限（分钟）。
    static let maxDurationMinutes = 15
    /// 每张卡片的预估耗时（分钟）。
    static let estimatedMinutesPerCard = 2.0

    /// 由时长上限推出的卡片数量上限。
    static var maxCards: Int {
        max(1, Int(Double(maxDurationMinutes) / estimatedMinutesPerCard))
    }

    /// 为当前快照生成补救任务；最高风险不在雷暴/冻结/雾中、或没有合适卡片时返回 nil。
    /// Returns nil unless the dominant subject is thunderstorm/frozen/fog
    /// and a non-empty card selection exists.
    static func generate(
        snapshot: MemoryClimateSnapshot,
        mistakes: [MistakeNote],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> RemediationTask? {
        guard let dominant = snapshot.dominantSubject else { return nil }

        let strategy: RemediationStrategy
        switch dominant.weather {
        case .thunderstorm: strategy = .interference
        case .frozen: strategy = .overdue
        case .fog: strategy = .weakSpot
        case .clear, .southHumid: return nil
        }

        let subjectMistakes = mistakes.filter {
            $0.subject.caseInsensitiveCompare(dominant.subject) == .orderedSame
        }
        guard !subjectMistakes.isEmpty else { return nil }

        let selected: [MistakeNote]
        switch strategy {
        case .interference:
            guard let pair = dominant.interferences.first else { return nil }
            selected = interleavedContrastCards(
                for: pair, in: subjectMistakes, now: now, calendar: calendar
            )
        case .overdue:
            selected = overduePriorityCards(in: subjectMistakes, now: now, calendar: calendar)
        case .weakSpot:
            selected = weakSpotCards(in: subjectMistakes, now: now, calendar: calendar)
        }
        guard !selected.isEmpty else { return nil }

        let capped = Array(selected.prefix(maxCards))
        let minutes = min(
            maxDurationMinutes,
            max(1, Int(ceil(Double(capped.count) * estimatedMinutesPerCard)))
        )
        return RemediationTask(
            id: UUID(),
            subject: dominant.subject,
            weather: dominant.weather,
            strategy: strategy,
            mistakes: capped,
            estimatedMinutes: minutes
        )
    }

    // MARK: - 雷暴：相关概念交错 / Thunderstorm: interleaved contrast cards.

    private static func interleavedContrastCards(
        for pair: ConceptInterference,
        in mistakes: [MistakeNote],
        now: Date,
        calendar: Calendar
    ) -> [MistakeNote] {
        let ranked = mistakes.sorted { lhs, rhs in
            let l = negativeCount(lhs, now: now, calendar: calendar)
            let r = negativeCount(rhs, now: now, calendar: calendar)
            if l != r { return l > r }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var aPool = ranked.filter { contains($0, concept: pair.firstConcept) }
        var bPool = ranked.filter { contains($0, concept: pair.secondConcept) }
        var result: [MistakeNote] = []
        var used = Set<UUID>()
        var takeB = false

        while !aPool.isEmpty || !bPool.isEmpty {
            if let next = (takeB ? bPool : aPool).first(where: { !used.contains($0.id) }) {
                result.append(next)
                used.insert(next.id)
                if takeB {
                    bPool.removeAll { used.contains($0.id) }
                } else {
                    aPool.removeAll { used.contains($0.id) }
                }
            }
            takeB.toggle()
        }
        return result
    }

    // MARK: - 冻结：逾期优先，其次最长未调用 / Frozen: overdue first, then longest uncalled.

    private static func overduePriorityCards(
        in mistakes: [MistakeNote],
        now: Date,
        calendar: Calendar
    ) -> [MistakeNote] {
        mistakes.sorted { lhs, rhs in
            let lOverdue = isOverdue(lhs, now: now)
            let rOverdue = isOverdue(rhs, now: now)
            if lOverdue != rOverdue { return lOverdue }
            if lOverdue {
                let lDue = lhs.reviewState?.nextReviewDate ?? .distantFuture
                let rDue = rhs.reviewState?.nextReviewDate ?? .distantFuture
                if lDue != rDue { return lDue < rDue }
            } else {
                let lCall = lastCallDate(lhs)
                let rCall = lastCallDate(rhs)
                if lCall != rCall { return lCall < rCall }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - 雾：最近答错优先，其次最低掌握度 / Fog: recent failures first, then lowest mastery.

    private static func weakSpotCards(
        in mistakes: [MistakeNote],
        now: Date,
        calendar: Calendar
    ) -> [MistakeNote] {
        mistakes.sorted { lhs, rhs in
            let lLast = lastNegativeDate(lhs, now: now, calendar: calendar)
            let rLast = lastNegativeDate(rhs, now: now, calendar: calendar)
            if lLast != rLast { return lLast > rLast }
            if lhs.masteryScore != rhs.masteryScore { return lhs.masteryScore < rhs.masteryScore }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - 辅助 / Helpers.

    private static func contains(_ note: MistakeNote, concept: String) -> Bool {
        MemoryClimateEngine.concepts(for: note).contains {
            $0.caseInsensitiveCompare(concept) == .orderedSame
        }
    }

    private static func negativeCount(
        _ note: MistakeNote,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let cutoff = calendar.date(
            byAdding: .day, value: -MemoryClimateEngine.negativeWindowDays, to: now
        ) ?? now
        return note.masteryHistory.filter {
            $0.timestamp >= cutoff &&
            ($0.quality == ReviewQuality.again.rawValue || $0.quality == ReviewQuality.hard.rawValue)
        }.count
    }

    private static func lastNegativeDate(
        _ note: MistakeNote,
        now: Date,
        calendar: Calendar
    ) -> Date {
        let cutoff = calendar.date(
            byAdding: .day, value: -MemoryClimateEngine.negativeWindowDays, to: now
        ) ?? now
        return note.masteryHistory
            .filter {
                $0.timestamp >= cutoff &&
                ($0.quality == ReviewQuality.again.rawValue || $0.quality == ReviewQuality.hard.rawValue)
            }
            .map(\.timestamp)
            .max() ?? .distantPast
    }

    private static func isOverdue(_ note: MistakeNote, now: Date) -> Bool {
        guard let due = note.reviewState?.nextReviewDate else { return false }
        return due <= now
    }

    private static func lastCallDate(_ note: MistakeNote) -> Date {
        note.masteryHistory.max(by: { $0.timestamp < $1.timestamp })?.timestamp
            ?? note.reviewState?.lastReviewDate
            ?? note.date
    }
}
