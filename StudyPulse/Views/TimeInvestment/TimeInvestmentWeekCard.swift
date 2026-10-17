//
//  TimeInvestmentWeekCard.swift
//  StudyPulse
//
//  趋势页底部的「时间投入」:本周总时长 + 各项目横条 + 未归属计时提示。
//  Trends footer card: this week's total, per-project bars and an unassigned hint.
//

import SwiftUI

struct TimeInvestmentWeekCard: View {
    @Environment(RepositoryContainer.self) private var container

    private var weekly: WeeklyInvestment {
        TimeInvestmentAggregator(
            subjects: container.timeInvestmentRepo.subjects,
            subTasks: container.timeInvestmentRepo.subTasks,
            sessions: container.studySessionRepo.sessions
        ).weekly()
    }

    var body: some View {
        let weekly = weekly
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            HomeZoneHeader(title: "time.investment.title".localized()) {
                NavigationLink {
                    TimeInvestmentView(container: container)
                } label: {
                    Text("trends.v2.invest.manage".localized())
                }
            }
            PageCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(TimeInvestmentFormatter.compactDuration(seconds: weekly.totalSeconds))
                            .font(.system(.title2, design: .rounded, weight: .heavy))
                            .monospacedDigit()
                        Text(weekCaption(weekly))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if weekly.rows.isEmpty {
                        Text("trends.v2.invest.empty".localized())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        let maxSeconds = max(weekly.rows.first?.seconds ?? 1, 1)
                        VStack(spacing: 8) {
                            ForEach(weekly.rows.prefix(4)) { row in
                                HStack(spacing: 10) {
                                    Text(row.subject.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .frame(width: 84, alignment: .leading)
                                    ProgressView(value: Double(row.seconds), total: Double(maxSeconds))
                                        .tint(Color(hex: row.subject.theme.colorHex))
                                    Text(TimeInvestmentFormatter.compactDuration(seconds: row.seconds))
                                        .font(.footnote.weight(.semibold))
                                        .monospacedDigit()
                                        .frame(minWidth: 52, alignment: .trailing)
                                }
                            }
                        }
                    }

                    if weekly.unassignedCount > 0 {
                        NavigationLink {
                            TimeInvestmentView(container: container)
                        } label: {
                            Label(String(format: "trends.v2.invest.unassigned".localized(), weekly.unassignedCount),
                                  systemImage: "tray.full.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private func weekCaption(_ weekly: WeeklyInvestment) -> String {
        let diff = weekly.totalSeconds - weekly.previousTotalSeconds
        guard weekly.previousTotalSeconds > 0 else { return "trends.v2.invest.thisWeek".localized() }
        let sign = diff >= 0 ? "+" : "−"
        return String(
            format: "trends.v2.invest.vsLast".localized(),
            sign + TimeInvestmentFormatter.compactDuration(seconds: abs(diff))
        )
    }
}
