//
//  StudyTimerHistoryList.swift
//  StudyPulse
//
//  Study session history: today's totals and the recent session list.
//  Used by `StudyTimerSetupSheet` (inline summary) and the optional
//  full history sheet presented by `StudyTimerView`.
//

import SwiftUI
import os

// MARK: - StudyTimerHistoryList

/// Full history list: today's totals + last N sessions grouped by day.
struct StudyTimerHistoryList: View {
    @Bindable var timer: StudyTimerManager

    /// Maximum number of recent sessions to display. Defaults to 20.
    var maxSessions: Int = 20

    private var todayMinutes: Int {
        let calendar = Calendar.current
        return timer.sessionSummaries
            .filter { $0.completed && calendar.isDateInToday($0.startDate) }
            .reduce(0) { $0 + $1.durationSeconds / 60 }
    }

    private var completedCount: Int {
        timer.sessionSummaries.filter(\.completed).count
    }

    private var recentSessions: [StudySessionSummary] {
        Array(
            timer.sessionSummaries
                .sorted { $0.startDate > $1.startDate }
                .prefix(maxSessions)
        )
    }

    private var groupedByDay: [(date: Date, sessions: [StudySessionSummary])] {
        let cal = Calendar.current
        var bucket: [Date: [StudySessionSummary]] = [:]
        for session in recentSessions {
            let day = cal.startOfDay(for: session.startDate)
            bucket[day, default: []].append(session)
        }
        return bucket
            .map { (date: $0.key, sessions: $0.value.sorted { $0.startDate > $1.startDate }) }
            .sorted { $0.date > $1.date }
    }

    private var stats: FocusSessionStatsEngine.Stats {
        FocusSessionStatsEngine.compute(summaries: timer.sessionSummaries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryRow
            if stats.totalSessions > 0 {
                FocusStatsCard(stats: stats)
            }

            if recentSessions.isEmpty {
                emptyState
            } else {
                ForEach(groupedByDay, id: \.date) { group in
                    daySection(date: group.date, sessions: group.sessions)
                }
            }
        }
    }

    // MARK: - Subviews

    private var summaryRow: some View {
        HStack {
            Label(
                "\(todayMinutes) min focused today".localized(),
                systemImage: "clock.badge.checkmark"
            )
            .font(.system(size: 13))
            .foregroundColor(.secondary)

            Spacer()

            Label(
                "\(completedCount) sessions total".localized(),
                systemImage: "list.clipboard"
            )
            .font(.system(size: 13))
            .foregroundColor(.secondary)
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No sessions yet".localized())
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            Text("Start your first focus session to see it here.".localized())
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func daySection(date: Date, sessions: [StudySessionSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dayHeader(for: date))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(sessions.reduce(0) { $0 + $1.durationSeconds / 60 }) min")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 6) {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
            }
        }
        .padding(.top, 4)
    }

    private func sessionRow(_ session: StudySessionSummary) -> some View {
        NavigationLink(value: session.id) {
            HStack(spacing: 10) {
                Image(systemName: session.intensity.icon)
                    .font(.system(size: 14))
                    .foregroundColor(intensityColor(session.intensity))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(intensityColor(session.intensity).opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.intensity.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        if let goal = session.goal {
                            Label(goal.title, systemImage: goal.source.icon)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Text(timeLabel(for: session.startDate))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if let goal = session.goal {
                        HStack(spacing: 6) {
                            Text(goal.progressText)
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.secondary)
                            if let rate = goal.completionRate {
                                Text(String(format: "%.0f%%", rate * 100))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(rate >= 1 ? .green : .primary)
                                ProgressView(value: rate)
                                    .frame(width: 40)
                            }
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(session.durationSeconds / 60) min")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(session.completed ? .primary : .secondary)
                    if let diff = session.goal?.difficulty {
                        Text(diff.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if session.heartRateSampleCount > 0 {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.pink)
                }

                if !session.completed {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.7))
                }
                if let reason = session.goal?.interruptionReason, reason != .none {
                    Image(systemName: reason.icon)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func intensityColor(_ intensity: StudySession.SessionIntensity) -> Color {
        switch intensity {
        case .peak: return .green
        case .deepFocus: return .blue
        case .steady: return .indigo
        case .light: return .orange
        case .recovery: return .red
        }
    }

    private func dayHeader(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today".localized() }
        if cal.isDateInYesterday(date) { return "Yesterday".localized() }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func timeLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - HistorySummaryInline

/// Compact one-line summary used at the bottom of the setup sheet so the
/// user can see today's focus and total completed sessions at a glance.
struct HistorySummaryInline: View {
    @Environment(StudyTimerManager.self) private var timer: StudyTimerManager
    @State private var showFullHistory = false

    var body: some View {
        Button {
            showFullHistory = true
        } label: {
            VStack(spacing: 8) {
                Divider()
                HStack {
                    Label(
                        "\(todayMinutes) min focused today".localized(),
                        systemImage: "clock.badge.checkmark"
                    )
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                    Spacer()

                    Label(
                        "\(timer.totalSessionCount) sessions total".localized(),
                        systemImage: "list.clipboard"
                    )
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showFullHistory) {
            NavigationStack {
                StudyTimerHistoryList(timer: timer)
                    .navigationTitle("Study History".localized())
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done".localized()) { showFullHistory = false }
                        }
                    }
                    .navigationDestination(for: UUID.self) { sessionId in
                        StudySessionDetailView(sessionId: sessionId)
                    }
            }
        }
    }

    private var todayMinutes: Int {
        let calendar = Calendar.current
        return timer.sessionSummaries
            .filter { $0.completed && calendar.isDateInToday($0.startDate) }
            .reduce(0) { $0 + $1.durationSeconds / 60 }
    }
}
