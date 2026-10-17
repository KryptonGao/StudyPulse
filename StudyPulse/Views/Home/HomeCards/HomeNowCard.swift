//
//  HomeNowCard.swift
//  StudyPulse
//
//  主页首屏主卡「现在最该做」:一条最紧迫的事 + 一键开始专注 + 今日三环与连续天数。
//  数据来源:`HomeViewModel.planCandidates`(DailyPlanEngine)、`StudyTimerManager`、
//  `AchievementManager.todayLog`。状态不佳触发「最小计划」时,标题区改为轻量说明。
//  Home hero "Do this now": the single most urgent item + one-tap focus + today's three
//  rings and streak. Sources: `HomeViewModel.planCandidates`, `StudyTimerManager`,
//  `AchievementManager.todayLog`. When the minimal plan is active, the copy turns lighter.
//

import SwiftUI

struct HomeNowCard: View {
    let viewModel: HomeViewModel
    /// 当前展示第几个候选;「换一个」按钮循环切换(与「今日」清单共享)。
    /// Which candidate is showing; the "another one" button cycles it (shared with the Today list).
    @Binding var candidateIndex: Int
    /// 是否显示底部「今日三环 + 连续天数」/ Whether to show the bottom rings + streak row.
    var showsRings: Bool = true
    let onOpenItem: (DailyPlanItem) -> Void

    @Environment(RepositoryContainer.self) private var container
    @Environment(AchievementManager.self) private var achievementManager
    @Environment(StudyTimerManager.self) private var timer
    @State private var showingTimer = false

    private var accent: Color { container.envManager.effectiveAccentColor }
    private var candidates: [DailyPlanItem] { viewModel.planCandidates }
    private var current: DailyPlanItem? {
        guard !candidates.isEmpty else { return nil }
        return candidates[candidateIndex % candidates.count]
    }
    private var isTimerActive: Bool { timer.timerState == .running || timer.timerState == .paused }
    private var lightDay: Bool { viewModel.minimalPlan.isActive }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            Label(kicker, systemImage: lightDay ? "leaf.fill" : "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)

            headline
            actions

            if showsRings {
                Divider()
                NavigationLink(value: HomeRoute.achievements) {
                    ringsRow
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) { glow }
        .cardSkin()
        .fullScreenCover(isPresented: $showingTimer) {
            StudyTimerView()
        }
        .debugLayoutBoundsAuto()
    }

    // MARK: - Headline

    private var kicker: String {
        (lightDay ? "home.v2.now.kicker.light" : "home.v2.now.kicker").localized()
    }

    private var headline: some View {
        Button {
            if let current { onOpenItem(current) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(current?.title ?? "All clear".localized())
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(current == nil)
    }

    private var reason: String {
        guard let current else { return "Pick something to study or add a routine.".localized() }
        if lightDay, !viewModel.minimalPlan.reason.isEmpty {
            return viewModel.minimalPlan.reason
        }
        return current.reason
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: DesignToken.Spacing.small) {
            Button(action: startOrContinue) {
                Label(primaryTitle, systemImage: isTimerActive ? "timer" : "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if candidates.count > 1 {
                Button {
                    withAnimation(.snappy) { candidateIndex = (candidateIndex + 1) % candidates.count }
                    Haptics.selection()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .frame(minHeight: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("home.v2.now.another".localized())
            }
        }
    }

    private var primaryTitle: String {
        if isTimerActive { return "home.v2.now.continue".localized() }
        return String(format: "home.v2.now.start".localized(), timer.recommendedDurationSeconds / 60)
    }

    private func startOrContinue() {
        // 未选投入项目时进入计时页让用户先选(与原 StudyTimerCard 行为一致)
        // Without a selected project, open the timer screen first (same as the old StudyTimerCard).
        if !isTimerActive, timer.selectedInvestmentTarget != nil {
            timer.start()
        }
        showingTimer = true
    }

    // MARK: - Rings

    private var ringsRow: some View {
        let log = achievementManager.todayLog
        let config = achievementManager.snapshot.config
        let rings = [
            RingSpec(label: "home.v2.ring.focus".localized(), value: log.focusMinutes,
                     target: config.focusMinutesTarget, unit: "min".localized(), color: accent),
            RingSpec(label: "home.v2.ring.review".localized(), value: log.mistakeReviews,
                     target: config.mistakeReviewTarget, unit: "", color: .orange),
            RingSpec(label: "home.v2.ring.grade".localized(), value: log.gradesRecorded,
                     target: config.gradeRecordTarget, unit: "", color: .green),
        ]
        return HStack(spacing: DesignToken.Spacing.large) {
            ConcentricRings(rings: rings)
                .frame(width: 76, height: 76)
            VStack(spacing: 6) {
                ForEach(rings) { ring in
                    HStack(spacing: 7) {
                        Circle().fill(ring.color).frame(width: 8, height: 8)
                        Text(ring.label)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(ring.valueText)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.footnote)
                }
            }
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text("\(achievementManager.currentStreak)")
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .monospacedDigit()
                Text("home.hero.streak".localized())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 56)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// 右上角主色光晕,裁成与当前卡片皮肤一致的圆角。
    /// Accent glow at the top trailing corner, clipped to the active card skin's corner radius.
    private var glow: some View {
        RadialGradient(
            colors: [accent.opacity(0.16), .clear],
            center: .topTrailing,
            startRadius: 0,
            endRadius: 260
        )
        .clipShape(RoundedRectangle(cornerRadius: container.envManager.effectiveCardSkin.cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }
}

// MARK: - Rings

private struct RingSpec: Identifiable {
    let label: String
    let value: Int
    let target: Int
    let unit: String
    let color: Color
    var id: String { label }

    var progress: Double { target > 0 ? min(Double(value) / Double(target), 1) : 0 }
    var valueText: String {
        let base = target > 0 ? "\(value) / \(target)" : "\(value)"
        return unit.isEmpty ? base : "\(base) \(unit)"
    }
}

/// 同心活动环(Apple 活动环风格),外环在前。
/// Concentric activity rings (Apple-activity style), outermost first.
private struct ConcentricRings: View {
    let rings: [RingSpec]
    private let lineWidth: CGFloat = 8
    private let gap: CGFloat = 2.5

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let inset = lineWidth / 2 + CGFloat(index) * (lineWidth + gap)
                Circle()
                    .stroke(ring.color.opacity(0.18), lineWidth: lineWidth)
                    .padding(inset)
                Circle()
                    .trim(from: 0, to: ring.progress)
                    .stroke(ring.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
                    .animation(.smooth, value: ring.progress)
            }
        }
        .accessibilityHidden(true)
    }
}
