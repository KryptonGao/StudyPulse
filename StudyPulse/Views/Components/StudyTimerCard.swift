//
//  StudyTimerCard.swift
//  StudyPulse
//
//  Compact HomeView card that shows the current readiness-based
//  Pomodoro recommendation and a Start / Pause / Resume button.
//  主页紧凑卡片:展示基于身体状态(HRV)的番茄钟推荐 + 开始/暂停/继续按钮。
//

import SwiftUI

/// 主页紧凑计时器卡片:基于当前身体状态给出推荐番茄钟时长,提供预设按钮快速开始。
/// Compact home timer card: shows a readiness-based Pomodoro recommendation with preset buttons.
struct StudyTimerCard: View {
    @Environment(StudyTimerManager.self) private var timer: StudyTimerManager
    @Environment(HealthKitManager.self) private var hrv: HealthKitManager
    @Environment(RepositoryContainer.self) private var container
    /// 是否显示全屏 StudyTimerView
    /// Whether the full-screen `StudyTimerView` is presented.
    @State private var showingTimer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Study Timer".localized())
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundColor(.primary)

                Spacer()

                if timer.timerState == .running || timer.timerState == .paused {
                    Image(systemName: "liveactivity")
                        .scaledFont(size: 16)
                        .foregroundColor(.green)
                }

                Image(systemName: intensityIcon)
                    .scaledFont(size: 18)
                    .foregroundColor(intensityColor)
            }

            if timer.timerState == .idle || timer.timerState == .completed {
                // Idle state: show recommendation
                recommendationView
            } else {
                // Active state: show countdown + controls
                activeTimerView
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
        .fullScreenCover(isPresented: $showingTimer) {
            StudyTimerView()
        }
        .onAppear {
            refreshRecommendation()
        }
        .onChange(of: hrv.bodyStatus) { _, _ in
            refreshRecommendation()
        }
        .debugLayoutBoundsAuto()
    }

    // MARK: - Recommendation (idle)
    // MARK: - 推荐(空闲态)

    private var recommendationView: some View {
        VStack(spacing: 12) {
            Button {
                showingTimer = true
            } label: {
                HStack {
                    Image(systemName: "folder.fill")
                    Text(selectedTargetName ?? "time.investment.chooseProject".localized())
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selectedTargetName == nil ? .orange : .secondary)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: intensityIcon)
                    .scaledFont(size: 20)
                    .foregroundColor(intensityColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(intensityTitle)
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundColor(.primary)
                    Text(String(format: "Recommended: %d min session".localized(),
                               timer.recommendedDurationSeconds / 60))
                        .scaledFont(size: 13)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Quick-start preset buttons
            HStack(spacing: 10) {
                ForEach(presetDurations, id: \.seconds) { preset in
                    Button {
                        if timer.selectedInvestmentTarget == nil {
                            showingTimer = true
                        } else {
                            timer.start(seconds: preset.seconds)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(preset.seconds / 60)")
                                .scaledFont(size: 22, weight: .bold)
                                .foregroundColor(preset.isRecommended ? .white : .primary)
                            Text("min")
                                .scaledFont(size: 11)
                                .foregroundColor(preset.isRecommended ? .white.opacity(0.8) : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(preset.isRecommended ? intensityColor : Color(.tertiarySystemFill))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showingTimer = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .scaledFont(size: 20, weight: .bold)
                            .foregroundColor(.secondary)
                        Text("More".localized())
                            .scaledFont(size: 11)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.tertiarySystemFill))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedTargetName: String? {
        guard let target = timer.selectedInvestmentTarget else { return nil }
        switch target {
        case .subject(let id):
            return container.timeInvestmentRepo.subjects.first { $0.id == id }?.name
        case .subTask(let id):
            return container.timeInvestmentRepo.subTasks.first { $0.id == id }?.name
        }
    }

    // MARK: - Active timer
    // MARK: - 计时中视图

    private var activeTimerView: some View {
        VStack(spacing: 12) {
            // Large countdown
            Text(formatTime(timer.remainingSeconds))
                .scaledFont(size: 42, weight: .bold, design: .monospaced)
                .foregroundColor(.primary)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(intensityColor)
                        .frame(width: progressWidth(in: geo.size.width), height: 8)
                }
            }
            .frame(height: 8)

            // Intensity label
            Text(timer.currentIntensity?.displayName ?? "")
                .scaledFont(size: 13, weight: .medium)
                .foregroundColor(intensityColor)

            // Controls
            HStack(spacing: 12) {
                Button {
                    timer.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .scaledFont(size: 18, weight: .semibold)
                        .foregroundColor(.red)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.red.opacity(0.12)))
                }
                .accessibilityLabel("a11y.cancelTimer".localized())
                .buttonStyle(.plain)

                Spacer()

                if timer.timerState == .running {
                    Button {
                        timer.pause()
                    } label: {
                        Image(systemName: "pause.fill")
                            .scaledFont(size: 22)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color.orange))
                    }
                    .accessibilityLabel("a11y.pause".localized())
                    .buttonStyle(.plain)
                } else if timer.timerState == .paused {
                    Button {
                        timer.resume()
                    } label: {
                        Image(systemName: "play.fill")
                            .scaledFont(size: 22)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color.green))
                    }
                    .accessibilityLabel("a11y.resume".localized())
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    showingTimer = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .accessibilityLabel("a11y.openTimer".localized())
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers
    // MARK: - 辅助函数

    private var presetDurations: [(seconds: Int, isRecommended: Bool)] {
        // 番茄钟预设(分钟):20 / 25 / 35 / 45 / 50
        // Pomodoro presets (min): 20 / 25 / 35 / 45 / 50.
        let recommended = timer.recommendedDurationSeconds
        let all: [Int] = [20 * 60, 25 * 60, 35 * 60, 45 * 60, 50 * 60]
        // Show 3 presets: recommended in the middle, flanked by closest others.
        let candidates = all.sorted { abs($0 - recommended) < abs($1 - recommended) }
        let top3 = Array(candidates.prefix(3)).sorted()
        return top3.map { ($0, $0 == recommended) }
    }

    private func progressWidth(in total: CGFloat) -> CGFloat {
        guard timer.totalSeconds > 0 else { return 0 }
        let fraction = CGFloat(timer.remainingSeconds) / CGFloat(timer.totalSeconds)
        return total * (1.0 - fraction)
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func refreshRecommendation() {
        let suggestion = StudyReadinessAlgorithm.recommend(
            hrvEnabled: hrv.hrvEnabled,
            hrvOnboardingCompleted: hrv.hrvOnboardingCompleted,
            isAuthorized: hrv.isAuthorized,
            hrv: hrv.readiness,
            bodyStatus: hrv.bodyStatus,
            baselines: hrv.personalBaselines,
            age: nil // HomeView doesn't have access to profile; use generic adult fallback
        )
        if let sug = suggestion {
            timer.recommendedIntensity = intensityFromSuggestion(sug)
        }
    }

    /// Map a StudySuggestion to its StudyIntensity. Since the suggestion includes
    /// the intensity, we need to reverse-map from the suggestion's title/color.
    /// 把 StudySuggestion 反向映射到 StudyIntensity。
    /// 由于 StudySuggestion 携带了 intensity 字段,这里用 title 反向匹配(中英双字符串)。
    private func intensityFromSuggestion(_ suggestion: StudySuggestion) -> StudyIntensity {
        if suggestion.title == "Peak Performance".localized() || suggestion.title == "巅峰发挥日".localized() { return .peak }
        if suggestion.title == "Deep Focus".localized() || suggestion.title == "深度学习".localized()
            || suggestion.title == "Deep Focus Day".localized() || suggestion.title == "适合深度学习".localized()
            || suggestion.title == "深度学习日".localized() { return .deepFocus }
        if suggestion.title == "Steady Rhythm".localized() || suggestion.title == "稳态学习日".localized() { return .steady }
        if suggestion.title == "Light Review".localized() || suggestion.title == "轻量复习日".localized()
            || suggestion.title == "Back to Mistakes & Basics".localized() || suggestion.title == "回到错题与基础".localized() { return .light }
        if suggestion.title == "Recovery Focus".localized() || suggestion.title == "以恢复为主".localized()
            || suggestion.title == "Rest Today".localized() || suggestion.title == "今天以休息为主".localized() { return .recovery }
        return .steady
    }

    private var intensityIcon: String {
        // 5 个 intensity 各对应一个 SF Symbol
        // One SF Symbol per intensity level.
        switch timer.recommendedIntensity {
        case .peak: return "bolt.heart.fill"
        case .deepFocus: return "brain.head.profile"
        case .steady: return "chart.bar.fill"
        case .light: return "book.closed.fill"
        case .recovery: return "bed.double.fill"
        }
    }

    private var intensityColor: Color {
        // 5 个 intensity 各对应一个色
        // Color per intensity level: peak/deepFocus/steady/light/recovery.
        switch timer.recommendedIntensity {
        case .peak: return .green
        case .deepFocus: return .blue
        case .steady: return .indigo
        case .light: return .orange
        case .recovery: return .red
        }
    }

    private var intensityTitle: String {
        switch timer.recommendedIntensity {
        case .peak: return "Peak Performance".localized()
        case .deepFocus: return "Deep Focus".localized()
        case .steady: return "Steady Rhythm".localized()
        case .light: return "Light Review".localized()
        case .recovery: return "Recovery".localized()
        }
    }
}
