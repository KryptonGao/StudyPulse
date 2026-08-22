import Foundation

/// Pure-function aggregator for goal-oriented focus session stats.
/// No SwiftUI dependencies.
nonisolated enum FocusSessionStatsEngine {

    struct Stats: Equatable, Sendable {
        let totalSessions: Int
        let goalSessions: Int
        let avgCompletionRate: Double? // 0...1, nil if no rated sessions
        let avgInterruptionCount: Double // per session
        let efficiencyBySource: [StudySessionGoalSource: Double] // avg completionRate per source
        let difficultyBreakdown: [StudySessionDifficulty: Int]
        let interruptionBreakdown: [StudySessionInterruptionReason: Int]
    }

    static func compute(sessions: [StudySession]) -> Stats {
        let total = sessions.count
        let goalSessions = sessions.filter { $0.goal != nil }.count

        let rated = sessions.compactMap { $0.goal?.completionRate }
        let avgRate: Double? = rated.isEmpty ? nil : rated.reduce(0, +) / Double(rated.count)

        let interruptedCount = sessions.filter {
            guard let r = $0.goal?.interruptionReason else { return false }
            return r != .none
        }.count
        let avgInterrupt = total == 0 ? 0 : Double(interruptedCount) / Double(total)

        // Group by source for efficiency (avg completionRate per source)
        var bucket: [StudySessionGoalSource: [Double]] = [:]
        for s in sessions {
            guard let g = s.goal, let rate = g.completionRate else { continue }
            bucket[g.source, default: []].append(rate)
        }
        var efficiency: [StudySessionGoalSource: Double] = [:]
        for (k, arr) in bucket {
            efficiency[k] = arr.reduce(0, +) / Double(arr.count)
        }

        var diffCount: [StudySessionDifficulty: Int] = [:]
        var intrCount: [StudySessionInterruptionReason: Int] = [:]
        for s in sessions {
            if let d = s.goal?.difficulty { diffCount[d, default: 0] += 1 }
            if let r = s.goal?.interruptionReason { intrCount[r, default: 0] += 1 }
        }

        return Stats(
            totalSessions: total,
            goalSessions: goalSessions,
            avgCompletionRate: avgRate,
            avgInterruptionCount: avgInterrupt,
            efficiencyBySource: efficiency,
            difficultyBreakdown: diffCount,
            interruptionBreakdown: intrCount
        )
    }

    static func compute(summaries: [StudySessionSummary]) -> Stats {
        // Reuse same logic via lightweight session conversion.
        let sessions = summaries.map { $0.asSession() }
        return compute(sessions: sessions)
    }
}
