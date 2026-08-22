//
//  StudyTimerSettingsSheet.swift
//  StudyPulse
//
//  Pomodoro setup body (recommendation / presets / custom duration) and
//  the color theme picker sheet.
//

import SwiftUI
import os

// MARK: - StudyTimerSetupSheet

/// Idle / setup body shown before a Pomodoro session starts. Owns the
/// preset selection and custom minute state.
struct StudyTimerSetupSheet: View {
    @Environment(RepositoryContainer.self) private var container
    @Bindable var timer: StudyTimerManager
    @Bindable var hrv: HealthKitManager

    /// Currently selected animation (drives the start button + presets).
    let animation: TimerAnimation

    /// Bindings so that presets and the start button can write into the
    /// parent's state without re-deriving from the recommendation.
    @Binding var customMinutes: Double
    @Binding var selectedPreset: Int?

    /// Called when the user taps "Start Focus" — the parent starts the
    /// timer, animates the progress, and switches to the active body.
    let onStart: () -> Void

    private var themeColor: Color { animation.primaryColor }

    @State private var showGoalSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer().frame(height: 20)

                if timer.timerState == .completed {
                    completedBadge
                }

                recommendationHeader
                SessionGoalPickerRow(timer: timer) { showGoalSheet = true }
                investmentTargetSection
                presetsGrid
                customDurationSection
                startButton

                Spacer().frame(height: 20)

                HistorySummaryInline()
            }
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $showGoalSheet) {
            SessionGoalSheet(timer: timer)
        }
    }

    // MARK: - Subviews

    private var completedBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.green)
            Text("Session Complete!".localized())
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 8)
    }

    private var recommendationHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: StudyIntensityUI.icon)
                .font(.system(size: 36))
                .foregroundColor(themeColor)

            Text(StudyIntensityUI.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)

            Text(String(format: "Recommended: %d min".localized(),
                       timer.recommendedDurationSeconds / 60))
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
    }

    private var presetsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(presetOptions, id: \.minutes) { preset in
                Button {
                    selectedPreset = preset.minutes
                    customMinutes = Double(preset.minutes)
                } label: {
                    VStack(spacing: 6) {
                        Text("\(preset.minutes)")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(selectedPreset == preset.minutes ? .white : .primary)
                        Text("min")
                            .font(.system(size: 12))
                            .foregroundColor(selectedPreset == preset.minutes ? .white.opacity(0.8) : .secondary)
                        if preset.isRecommended {
                            Text("Recommended".localized())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(selectedPreset == preset.minutes ? .white.opacity(0.7) : themeColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(selectedPreset == preset.minutes ? themeColor : Color(.tertiarySystemFill))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                preset.isRecommended && selectedPreset != preset.minutes ? themeColor : .clear,
                                lineWidth: 2
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var investmentTargetSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            Text("time.investment.project".localized())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if selectableTargets.isEmpty {
                NavigationLink {
                    TimeInvestmentView(container: container)
                } label: {
                    Label(
                        "time.investment.createBeforeTimer".localized(),
                        systemImage: "folder.badge.plus"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignToken.Spacing.medium)
                    .background(
                        Color.orange.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: DesignToken.CornerRadius.medium)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(selectableTargets, id: \.target.id) { item in
                        Button {
                            timer.selectInvestmentTarget(item.target)
                        } label: {
                            Label(
                                item.name,
                                systemImage: timer.selectedInvestmentTarget == item.target
                                    ? "checkmark.circle.fill"
                                    : item.symbol
                            )
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: selectedTargetItem?.symbol ?? "folder")
                            .foregroundStyle(themeColor)
                        Text(
                            selectedTargetItem?.name
                                ?? "time.investment.chooseProject".localized()
                        )
                        .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(DesignToken.Spacing.medium)
                    .background(
                        Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: DesignToken.CornerRadius.medium)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customDurationSection: some View {
        VStack(spacing: 8) {
            Text("Custom Duration".localized())
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            HStack {
                Button {
                    customMinutes = max(5, customMinutes - 5)
                    selectedPreset = nil
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text("\(Int(customMinutes)) min")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(minWidth: 80)

                Button {
                    customMinutes = min(120, customMinutes + 5)
                    selectedPreset = nil
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    private var startButton: some View {
        Button {
            onStart()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Start Focus".localized())
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeColor)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private var presetOptions: [(minutes: Int, isRecommended: Bool)] {
        let recommended = timer.recommendedDurationSeconds / 60
        let all = [20, 25, 35, 45, 50]
        return all.sorted { abs($0 - recommended) < abs($1 - recommended) }
                  .map { ($0, $0 == recommended) }
    }

    private struct TargetItem {
        let target: InvestmentTarget
        let name: String
        let symbol: String
    }

    private var selectableTargets: [TargetItem] {
        let subjects = container.timeInvestmentRepo.subjects.filter { !$0.isArchived }
        var result: [TargetItem] = []
        for subject in subjects {
            result.append(
                TargetItem(
                    target: .subject(subject.id),
                    name: subject.name,
                    symbol: subject.symbolName
                )
            )
            let tasks = container.timeInvestmentRepo.subTasks
                .filter { $0.subjectID == subject.id && !$0.isArchived }
                .sorted { $0.sortOrder < $1.sortOrder }
            for task in tasks {
                let prefix = task.parentSubTaskID == nil ? "↳ " : "  ↳ "
                result.append(
                    TargetItem(
                        target: .subTask(task.id),
                        name: prefix + task.name,
                        symbol: "folder"
                    )
                )
            }
        }
        return result
    }

    private var selectedTargetItem: TargetItem? {
        selectableTargets.first { $0.target == timer.selectedInvestmentTarget }
    }
}

// MARK: - Recommendation Refresh

/// Pulls the algorithm suggestion and applies it to the timer manager.
/// Called by `StudyTimerView.onAppear` and whenever HRV signals change.
enum StudyTimerRecommendation {
    @MainActor
    static func refresh(timer: StudyTimerManager, hrv: HealthKitManager, selectedPreset: Int?, customMinutes: inout Double) {
        let suggestion = StudyReadinessAlgorithm.recommend(
            hrvEnabled: hrv.hrvEnabled,
            hrvOnboardingCompleted: hrv.hrvOnboardingCompleted,
            isAuthorized: hrv.isAuthorized,
            hrv: hrv.readiness,
            bodyStatus: hrv.bodyStatus,
            baselines: hrv.personalBaselines,
            age: nil
        )
        if let sug = suggestion {
            timer.recommendedIntensity = intensityFromSuggestion(sug)
        }
        if selectedPreset == nil {
            customMinutes = Double(timer.recommendedDurationSeconds / 60)
        }
    }
}

// MARK: - Quick Theme Sheet (Theme Shop lite)

/// 计时器页内快速切换动效的 sheet。
/// 不承担解锁选择 — 展示当前已装备的 + 已解锁的 + 一个跳主题商店的入口。
/// Debug 模式下放行所有条目。
struct StudyTimerQuickThemeSheet: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var showThemeShop = false

    private var activeAnimation: TimerAnimation {
        container.envManager.effectiveTimerAnimation
    }

    private var unlockedAnimations: [TimerAnimation] {
        let ids = ThemeShopCatalog.timerAnimations
        return ids.filter { anim in
            ThemeShopCatalog.isUnlocked(
                unlockAchievementId: anim.unlockAchievementId,
                achievementIds: achievementSet,
                isDebugMode: container.envManager.debugModeEnabled
            )
        }
    }

    private var achievementSet: Set<String> {
        AchievementManager.shared.snapshot.achievements
            .filter { $0.unlockedAt != nil }
            .map { $0.definitionId }
            .reduce(into: Set<String>()) { $0.insert($1) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                themePreview
                Divider().padding(.vertical, 8)
                themeGrid
                Divider().padding(.vertical, 8)
                shopEntry
            }
            .navigationTitle("Color Theme".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized()) {
                        dismiss()
                    }
                }
            }
            .navigationDestination(isPresented: $showThemeShop) {
                ThemeShopView()
            }
        }
    }

    private var themePreview: some View {
        ZStack {
            LinearGradient(
                colors: activeAnimation.colors.map { $0.opacity(0.15) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .stroke(
                    AngularGradient(
                        colors: activeAnimation.colors + [activeAnimation.colors[0]],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 120, height: 120)
                .shadow(color: activeAnimation.primaryColor.opacity(0.5), radius: 12)
        }
        .frame(height: 180)
    }

    private var themeGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(unlockedAnimations) { anim in
                    Button {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            container.envManager.setTimerAnimationId(anim.id)
                        }
                    } label: {
                        themeTile(anim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private var shopEntry: some View {
        Button {
            showThemeShop = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 18, weight: .medium))
                Text("Browse All Themes".localized())
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func themeTile(_ anim: TimerAnimation) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: anim.colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: anim.primaryColor.opacity(0.4), radius: 8)

                if activeAnimation.id == anim.id {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 56, height: 56)
                }
            }

            Text(anim.localizedName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(activeAnimation.id == anim.id ? anim.primaryColor.opacity(0.12) : Color(.tertiarySystemFill))
        )
    }
}
