//
//  HomeBodyMindSection.swift
//  StudyPulse
//
//  「身心」区块:恢复分仪表 + 三项身体指标 + 一键记录心情 + 今日最佳学习窗口。
//  详情(雷达 / 趋势 / 脑力 / 记忆气候等)收进 `HomeBodyMindDetailView`。未授权 HealthKit 时
//  只显示心情与习惯两行。
//  Body & Mind zone: recovery gauge + three vitals + one-tap mood log + today's best study
//  window. Details (radar / trends / brain usage / memory climate…) live in
//  `HomeBodyMindDetailView`. Without HealthKit authorization only mood and habit rows show.
//

import SwiftUI

/// 「身心」区块各子模块的开关(来自 `HomeLayoutPreference`)。
/// Per-module switches for the Body & Mind zone (from `HomeLayoutPreference`).
struct HomeBodyMindOptions {
    var showsRecovery = true
    var showsDiary = true
    var showsHabit = true
}

struct HomeBodyMindSection: View {
    let viewModel: HomeViewModel
    let options: HomeBodyMindOptions

    @Environment(RepositoryContainer.self) private var container
    @Environment(HealthKitManager.self) private var hrvManager

    private var score: Int? { options.showsRecovery ? viewModel.recoveryScore : nil }
    private var showsMood: Bool { options.showsDiary && container.envManager.preferences.diaryEnabled }
    private var habit: HabitInsight? { options.showsHabit ? viewModel.todayBestSlot : nil }

    var body: some View {
        if score != nil || showsMood || habit != nil {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HomeZoneHeader(title: "home.v2.zone.bodyMind".localized()) {
                    NavigationLink("home.v2.bodyMind.details".localized(), value: HomeRoute.bodyMindDetail)
                }
                card
            }
            .debugLayoutBoundsAuto()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            if let score {
                recovery(score: score)
                vitals
            }
            if showsMood { moodRow }
            if let habit { habitRow(habit) }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
    }

    // MARK: - Recovery

    private func recovery(score: Int) -> some View {
        let level = RecoveryLevel(score: score)
        return HStack(spacing: DesignToken.Spacing.large) {
            Gauge(value: Double(score), in: 0...100) {
                Text("home.v2.bodyMind.recovery".localized())
            } currentValueLabel: {
                Text("\(score)")
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(level.color)
            .scaleEffect(1.15)
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(level.localizedLabel)
                    .font(.headline)
                Text(hrvManager.readiness.suggestion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var vitals: some View {
        let status = hrvManager.bodyStatus
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignToken.Spacing.small) { vitalTiles(status) }
            VStack(spacing: DesignToken.Spacing.small) { vitalTiles(status) }
        }
    }

    @ViewBuilder
    private func vitalTiles(_ status: BodyStatus) -> some View {
        VitalTile(
            value: hrvManager.readiness.todayHRV.map { String(format: "%.0f", $0) },
            unit: "ms",
            caption: "HRV"
        )
        VitalTile(
            value: status.lastNightSleepHours.map { String(format: "%.1f", $0) },
            unit: "h",
            caption: status.restorativeSleepHours.map {
                String(format: "home.v2.bodyMind.sleepDetail".localized(), $0)
            } ?? "home.v2.bodyMind.sleep".localized()
        )
        VitalTile(
            value: status.restingHeartRate.map { String(format: "%.0f", $0) },
            unit: "bpm",
            caption: "home.v2.bodyMind.rhr".localized()
        )
    }

    // MARK: - Mood

    private static let moodEmojis = ["😢", "😕", "🙂", "😊", "🤩"]

    private var moodRow: some View {
        let todayScore = container.diaryRepo.todayEntry()?.moodScore
        return VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            HStack {
                Text("home.v2.bodyMind.moodPrompt".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink("Study Diary".localized(), value: HomeRoute.diary)
                    .font(.caption.weight(.semibold))
            }
            HStack(spacing: 0) {
                ForEach(Array(Self.moodEmojis.enumerated()), id: \.offset) { index, emoji in
                    let value = index + 1
                    Button {
                        logMood(value)
                    } label: {
                        Text(emoji)
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(todayScore == value
                                          ? container.envManager.effectiveAccentColor.opacity(0.2)
                                          : Color(.tertiarySystemFill))
                            )
                            .overlay {
                                if todayScore == value {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(container.envManager.effectiveAccentColor, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(moodLabel(value))
                    .accessibilityAddTraits(todayScore == value ? .isSelected : [])
                    if index < Self.moodEmojis.count - 1 { Spacer(minLength: 4) }
                }
            }
        }
    }

    /// 与 `DiaryView.logQuickMood` 同逻辑:今日已有日记则更新,否则新建仅含心情的日记。
    /// Same logic as `DiaryView.logQuickMood`: update today's entry or create a mood-only one.
    private func logMood(_ score: Int) {
        if var today = container.diaryRepo.todayEntry() {
            today.moodScore = score
            container.diaryRepo.update(today)
        } else {
            container.diaryRepo.add(DiaryEntry(date: .now, moodScore: score, energyScore: 3, energyTag: "", content: ""))
        }
        Haptics.selection()
    }

    private func moodLabel(_ score: Int) -> String {
        switch score {
        case 1: return "Sad".localized()
        case 2: return "Low".localized()
        case 3: return "OK".localized()
        case 4: return "Good".localized()
        default: return "Great".localized()
        }
    }

    // MARK: - Habit

    private func habitRow(_ insight: HabitInsight) -> some View {
        Label {
            Text(HabitInsightEngine.notificationBody(for: insight))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(container.envManager.effectiveAccentColor)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Vital tile

private struct VitalTile: View {
    let value: String?
    let unit: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value ?? "—")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                if value != nil {
                    Text(unit)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

/// 身心详情页:收纳从主页移出的恢复雷达 / 身心趋势 / 脑力 / 记忆气候 / 习惯洞察 / 考前状态预测。
/// Body & Mind detail screen: houses the cards moved off Home — recovery radar, body-mind trend,
/// brain usage, memory climate, habit insight and exam-day readiness.
struct HomeBodyMindDetailView: View {
    let viewModel: HomeViewModel
    let onStartFlashcards: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: DesignToken.Spacing.cardSpacing) {
                HRVStatusCard()
                if viewModel.hasBodyMindData {
                    BodyMindTrendCard(
                        mood: viewModel.moodSeries,
                        sleep: viewModel.sleepSeries,
                        hrv: viewModel.hrvSeries
                    )
                }
                BrainUsageCard()
                if !viewModel.memoryClimate.subjects.isEmpty {
                    MemoryClimateCard(
                        snapshot: viewModel.memoryClimate,
                        history: viewModel.memoryClimateHistory,
                        onStartReview: onStartFlashcards
                    )
                }
                HabitInsightCard()
                ExamDayReadinessCard(viewModel: viewModel)
            }
            .padding(.horizontal, DesignToken.Spacing.secondaryHorizontal)
            .padding(.vertical, DesignToken.Spacing.medium)
            .adaptiveMaxWidth()
        }
        .background(Color(.systemGroupedBackground).opacity(DesignToken.Opacity.rootBackground))
        .containerBackground(.clear, for: .navigation)
        .navigationTitle("home.v2.zone.bodyMind".localized())
        .navigationBarTitleDisplayMode(.inline)
    }
}
