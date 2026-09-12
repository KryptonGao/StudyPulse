//
//  TimeInvestmentEngine.swift
//  StudyPulse
//

import Foundation

nonisolated struct TimeInvestmentAggregator: Sendable {
    let subjects: [TimeInvestmentSubject]
    let subTasks: [SubTask]
    let sessions: [StudySession]

    private var subTasksByID: [UUID: SubTask] {
        Dictionary(subTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func directSeconds(for target: InvestmentTarget) -> Int {
        eligibleSessions
            .filter { $0.investmentTarget == target }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    func totalSeconds(for target: InvestmentTarget) -> Int {
        sessions(for: target).reduce(0) { $0 + $1.durationSeconds }
    }

    func sessions(for target: InvestmentTarget) -> [StudySession] {
        switch target {
        case .subject(let subjectID):
            return eligibleSessions.filter { session in
                switch session.investmentTarget {
                case .subject(let id): return id == subjectID
                case .subTask(let id): return subTasksByID[id]?.subjectID == subjectID
                case nil: return false
                }
            }
        case .subTask(let subTaskID):
            let included = Set([subTaskID] + descendantIDs(of: subTaskID))
            return eligibleSessions.filter {
                guard case .subTask(let id) = $0.investmentTarget else { return false }
                return included.contains(id)
            }
        }
    }

    func descendantIDs(of subTaskID: UUID) -> [UUID] {
        var result: [UUID] = []
        var pending = [subTaskID]
        while let parent = pending.popLast() {
            let children = subTasks.filter { $0.parentSubTaskID == parent }.map(\.id)
            result.append(contentsOf: children)
            pending.append(contentsOf: children)
        }
        return result
    }

    var totalAssignedSeconds: Int {
        eligibleSessions
            .filter { $0.investmentTarget != nil }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    var unassignedSessions: [StudySession] {
        eligibleSessions.filter { $0.investmentTarget == nil }
    }

    private var eligibleSessions: [StudySession] {
        sessions.filter { $0.completed && $0.durationSeconds > 0 }
    }
}

nonisolated enum StudyStreakCalculator {
    private struct DayKey: Hashable, Comparable {
        let year: Int
        let month: Int
        let day: Int

        static func < (lhs: DayKey, rhs: DayKey) -> Bool {
            (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
        }
    }

    static func currentStreak(
        sessions: [StudySession],
        now: Date = .now,
        calendar referenceCalendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        let active = activeDays(from: sessions, calendar: referenceCalendar)
        guard !active.isEmpty else { return 0 }

        let calendar = referenceCalendar
        let todayStart = calendar.startOfDay(for: now)
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) else {
            return 0
        }
        let today = key(for: todayStart, calendar: calendar)
        let yesterday = key(for: yesterdayStart, calendar: calendar)

        var cursorDate: Date
        if active.contains(today) {
            cursorDate = todayStart
        } else if active.contains(yesterday) {
            cursorDate = yesterdayStart
        } else {
            return 0
        }

        var count = 0
        while active.contains(key(for: cursorDate, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursorDate) else {
                break
            }
            cursorDate = previous
        }
        return count
    }

    private static func activeDays(from sessions: [StudySession], calendar: Calendar) -> Set<DayKey> {
        var days = Set<DayKey>()
        for session in sessions where session.completed && session.durationSeconds > 0 {
            // 统一用传入的基准日历归一化到"日",与 `currentStreak` 的 today/yesterday
            // 同一基准,避免跨时区后残留的会话日期与当前时区错配导致 streak 断裂(H-12)。
            var day = calendar.startOfDay(for: session.startDate)
            let end = session.startDate
                .addingTimeInterval(TimeInterval(session.durationSeconds))
                .addingTimeInterval(-0.001)
            let finalDay = calendar.startOfDay(for: end)
            while day <= finalDay {
                days.insert(key(for: day, calendar: calendar))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return days
    }

    private static func key(for date: Date, calendar: Calendar) -> DayKey {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return DayKey(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
    }
}

nonisolated enum GoalRewardEvaluator {
    struct Result: Sendable {
        let rewards: [GoalReward]
        let newlyUnlocked: [GoalReward]
    }

    static func evaluate(
        rewards: [GoalReward],
        aggregator: TimeInvestmentAggregator,
        now: Date = .now
    ) -> Result {
        var unlocked: [GoalReward] = []
        let updated = rewards.map { reward -> GoalReward in
            guard reward.unlockedAt == nil,
                  aggregator.totalSeconds(for: reward.target) >= reward.thresholdSeconds else {
                return reward
            }
            var copy = reward
            copy.unlockedAt = now
            unlocked.append(copy)
            return copy
        }
        return Result(rewards: updated, newlyUnlocked: unlocked)
    }
}

nonisolated enum TimeInvestmentFormatter {
    static func hoursBadge(seconds: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let hours = Double(max(0, seconds)) / 3600
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        let value = formatter.string(from: NSNumber(value: hours)) ?? "0"
        return String(format: "time.investment.hours.format".localized(), value)
    }

    static func compactDuration(seconds: Int, locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(Double(max(0, seconds))).formatted(
            .units(
                allowed: [.hours, .minutes],
                width: .abbreviated,
                maximumUnitCount: 2,
                zeroValueUnits: .hide
            )
            .locale(locale)
        )
    }
}
