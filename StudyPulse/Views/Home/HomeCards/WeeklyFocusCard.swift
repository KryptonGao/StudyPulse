//
//  WeeklyFocusCard.swift
//  StudyPulse
//
//  本周专注:7 日堆叠柱状图(按强度着色) + 每日目标线 + 与上周对比。
//  Weekly focus: 7-day stacked bars by intensity, daily-goal rule line and week-over-week delta.
//

import SwiftUI
import Charts

/// 独立卡片(带标题):用于单卡分享。主页「进展」区块直接嵌入 `WeeklyFocusContent`。
/// Standalone card with a header, used for single-card sharing; the Progress zone embeds `WeeklyFocusContent` directly.
struct WeeklyFocusCard: View {
    let summary: WeeklyFocusSummary

    var body: some View {
        HomeCardContainer {
            HomeCardHeader(
                icon: "chart.bar.fill",
                title: "home.weeklyFocus.title".localized(),
                subtitle: "home.weeklyFocus.subtitle".localized(),
                tint: .blue
            )
            WeeklyFocusContent(summary: summary)
        }
        .debugLayoutBoundsAuto()
    }
}

/// 本周专注内容(汇总行 + 柱状图 + 图例),无外层容器。
/// Weekly focus content (summary row + chart + legend) without a surrounding container.
struct WeeklyFocusContent: View {
    let summary: WeeklyFocusSummary
    /// 为 false 时省略汇总行(主页「进展」卡顶部已有同口径 KPI)。
    /// When false the summary row is omitted (the Progress card already shows the same KPI above).
    var showsSummary: Bool = true

    @Environment(AchievementManager.self) private var achievementManager

    private var dailyTarget: Int { achievementManager.snapshot.config.focusMinutesTarget }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            if showsSummary { summaryRow }
            chart
            legend
        }
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Self.hoursText(summary.totalMinutes))
                    .scaledFont(size: 28, weight: .bold, design: .rounded)
                    .monospacedDigit()
                Text("home.weeklyFocus.hours".localized())
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundStyle(.secondary)
            }
            if summary.previousTotalMinutes > 0 || summary.totalMinutes > 0 {
                HomeDeltaBadge(delta: summary.deltaMinutes / 60, format: "%.1fh")
            }
            Spacer(minLength: 0)
            Text(String(format: "home.weeklyFocus.avg".localized(), Int(summary.dailyAverageMinutes.rounded())))
                .scaledFont(size: 11)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            ForEach(summary.days) { day in
                // 保证每天都有柱位(空白日 0 高度),避免 x 轴缺格
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", 0))
                    .opacity(0)
            }
            ForEach(summary.segments) { segment in
                BarMark(
                    x: .value("Day", segment.date, unit: .day),
                    y: .value("Minutes", segment.minutes)
                )
                .foregroundStyle(by: .value("Intensity", segment.intensity.displayName))
                .cornerRadius(3)
            }
            if dailyTarget > 0 {
                RuleMark(y: .value("Goal", dailyTarget))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
        }
        .chartForegroundStyleScale(domain: intensityDomain, range: intensityColors)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel()
            }
        }
        .frame(height: 150)
        .accessibilityLabel("home.weeklyFocus.title".localized())
    }

    // MARK: - Legend

    /// 只展示本周实际出现过的强度。
    private var usedIntensities: [StudySession.SessionIntensity] {
        StudySession.SessionIntensity.allCases.filter { intensity in
            summary.segments.contains { $0.intensity == intensity }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(usedIntensities, id: \.self) { intensity in
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: intensity.colorHex)).frame(width: 7, height: 7)
                    Text(intensity.displayName)
                        .scaledFont(size: 10)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if dailyTarget > 0 {
                HStack(spacing: 4) {
                    Rectangle()
                        .stroke(Color.secondary.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .frame(width: 14, height: 1)
                    Text(String(format: "home.hero.goalMin".localized(), dailyTarget))
                        .scaledFont(size: 10)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var intensityDomain: [String] {
        StudySession.SessionIntensity.allCases.map(\.displayName)
    }

    private var intensityColors: [Color] {
        StudySession.SessionIntensity.allCases.map { Color(hex: $0.colorHex) }
    }

    static func hoursText(_ minutes: Double) -> String {
        String(format: "%.1f", minutes / 60)
    }
}
