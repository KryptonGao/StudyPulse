//
//  OverviewHeroCard.swift
//  StudyPulse
//
//  主页顶部总览:4 个带趋势的 KPI 磚(平均得分率 / 今日专注 / 连续打卡 / 最近考试)。
//  iPhone 2x2,iPad 单行 4 项。取代只有静态数字的 MainStatsCard。
//  Home top overview: 4 KPI tiles with trends (average rate / today's focus / streak / next exam).
//  2x2 on iPhone, a single row on iPad. Replaces the number-only MainStatsCard.
//

import SwiftUI

struct OverviewHeroCard: View {
    let viewModel: HomeViewModel

    @Environment(RepositoryContainer.self) private var container
    @Environment(AchievementManager.self) private var achievementManager
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isWide: Bool { sizeClass == .regular || isIPad }
    private var accent: Color { container.envManager.effectiveAccentColor }

    var body: some View {
        let tiles = [AnyView(averageTile), AnyView(focusTile), AnyView(streakTile), AnyView(examTile)]
        VStack(spacing: DesignToken.Spacing.medium) {
            if isWide {
                HStack(spacing: DesignToken.Spacing.medium) {
                    ForEach(tiles.indices, id: \.self) { tiles[$0] }
                }
            } else {
                HStack(spacing: DesignToken.Spacing.medium) { tiles[0]; tiles[1] }
                HStack(spacing: DesignToken.Spacing.medium) { tiles[2]; tiles[3] }
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
        .debugLayoutBoundsAuto()
    }

    // MARK: - Tiles

    /// 平均得分率 + 最近 8 次 sparkline + 变化
    private var averageTile: some View {
        let trend = viewModel.averageRateTrend
        return HeroTile(icon: "chart.line.uptrend.xyaxis", tint: .cyan, title: "Average".localized()) {
            if let rate = viewModel.overallAverageRate {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HeroValue(text: String(format: "%.0f", rate), unit: "%")
                    HomeDeltaBadge(delta: Self.trendDelta(trend), format: "%.1f")
                }
            } else {
                HeroValue(text: "—", unit: nil)
            }
        } footer: {
            if trend.count >= 2 {
                HomeSparkline(values: trend, tint: .cyan, height: 26)
            } else {
                HeroCaption(text: "home.hero.noGrades".localized())
            }
        }
    }

    /// 今日专注 + 目标进度环
    private var focusTile: some View {
        let minutes = achievementManager.todayLog.focusMinutes
        let target = achievementManager.snapshot.config.focusMinutesTarget
        let progress = target > 0 ? min(Double(minutes) / Double(target), 1) : 0
        return HeroTile(icon: "timer", tint: .orange, title: "home.hero.focusToday".localized()) {
            HStack(alignment: .center) {
                HeroValue(text: "\(minutes)", unit: "min".localized())
                Spacer(minLength: 4)
                ProgressRing(progress: progress, tint: .orange)
                    .frame(width: 30, height: 30)
            }
        } footer: {
            HeroCaption(text: target > 0
                ? String(format: "home.hero.goalMin".localized(), target)
                : "home.hero.noGoal".localized())
        }
    }

    /// 连续打卡 + 本周活动条(整块跳转成就页)
    private var streakTile: some View {
        let strip = HomeInsightsEngine.weekStrip(logs: achievementManager.snapshot.logs)
        return NavigationLink(destination: AchievementsView()) {
            HeroTile(icon: "flame.fill", tint: .red, title: "home.hero.streak".localized()) {
                HeroValue(text: "\(achievementManager.currentStreak)", unit: "home.unit.days".localized())
            } footer: {
                WeekStripView(days: strip, tint: accent)
            }
        }
        .buttonStyle(.plain)
    }

    /// 最近一场考试倒数
    private var examTile: some View {
        let exam = viewModel.upcomingExams.min { $0.examDate < $1.examDate }
        return HeroTile(icon: "calendar.badge.exclamationmark", tint: .purple, title: "home.hero.nextExam".localized()) {
            if let exam {
                let days = Self.daysUntil(exam.examDate)
                HeroValue(
                    text: days == 0 ? "Today!".localized() : "\(days)",
                    unit: days == 0 ? nil : "home.unit.days".localized(),
                    tint: days <= 3 ? .red : .primary
                )
            } else {
                HeroValue(text: "—", unit: nil)
            }
        } footer: {
            HeroCaption(text: exam?.name ?? "home.hero.noExam".localized())
        }
    }

    // MARK: - Helpers

    /// 后半段均值 − 前半段均值(至少 4 个点)。
    /// Mean of the second half minus the first half (needs ≥ 4 points).
    static func trendDelta(_ values: [Double]) -> Double? {
        guard values.count >= 4 else { return nil }
        let mid = values.count / 2
        let first = values[..<mid]
        let second = values[mid...]
        return second.reduce(0, +) / Double(second.count) - first.reduce(0, +) / Double(first.count)
    }

    static func daysUntil(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let from = calendar.startOfDay(for: now)
        let to = calendar.startOfDay(for: date)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }
}

// MARK: - Building blocks

/// 单个 KPI 磚:小图标标题 + 主体(数值行) + 页脚(趋势 / 说明)。
private struct HeroTile<Value: View, Footer: View>: View {
    let icon: String
    let tint: Color
    let title: String
    @ViewBuilder var value: () -> Value
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            value()
            footer()
                .frame(minHeight: 26, alignment: .bottomLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.CornerRadius.large))
        .accessibilityElement(children: .combine)
    }
}

private struct HeroValue: View {
    let text: String
    let unit: String?
    var tint: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(text)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let unit {
                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct HeroCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// 圆环进度(达成目标时变绿)。
struct ProgressRing: View {
    let progress: Double
    var tint: Color = .accentColor
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progress >= 1 ? Color.green : tint,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// 最近 7 天活动条:圆点透明度 = 活动等级,今天描边。
struct WeekStripView: View {
    let days: [WeekStripDay]
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days) { day in
                let level = HeatmapActivityLevel.from(points: day.points)
                Circle()
                    .fill(level == .none ? Color(.tertiarySystemFill) : tint.opacity(level.opacity))
                    .frame(width: 10, height: 10)
                    .overlay {
                        if day.isToday {
                            Circle().stroke(tint, lineWidth: 1.5).padding(-2)
                        }
                    }
            }
        }
        .accessibilityHidden(true)
    }
}
