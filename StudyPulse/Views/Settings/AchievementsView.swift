//
//  AchievementsView.swift
//  StudyPulse
//
//  成就墙 —— 按 tier 分组展示所有徽章及其解锁进度。
//  Achievement gallery grouped by tier, with unlock progress for each badge.
//

import SwiftUI

struct AchievementsView: View {
    @Environment(AchievementManager.self) private var achievementManager: AchievementManager

    private var progressList: [AchievementProgress] {
        achievementManager.snapshot.achievements
    }

    private var groupedByTier: [(tier: AchievementDefinition.Tier, items: [AchievementProgress])] {
        let tiers: [AchievementDefinition.Tier] = [.onboarding, .volume, .streak, .mastery]
        var result: [(tier: AchievementDefinition.Tier, items: [AchievementProgress])] = []
        for tier in tiers {
            let items = progressList.filter { $0.definition?.tier == tier }
            if !items.isEmpty {
                result.append((tier: tier, items: items))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                streakHeader

                ForEach(groupedByTier, id: \.tier) { group in
                    tierSection(tier: group.tier, items: group.items)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationTitle("Achievements".localized())
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .containerBackground(.clear, for: .navigation)
        .debugModeContainer()
        .debugLayoutBoundsAuto()
    }

    // MARK: - Streak Header

    private var streakHeader: some View {
        HStack(spacing: 24) {
            StreakStat(
                value: "\(achievementManager.snapshot.streak.current)",
                label: "Current Streak".localized(),
                icon: "flame.fill",
                color: .orange
            )
            StreakStat(
                value: "\(achievementManager.snapshot.streak.longest)",
                label: "Longest Streak".localized(),
                icon: "crown.fill",
                color: .yellow
            )
            StreakStat(
                value: "\(achievementManager.snapshot.streak.totalActiveDays)",
                label: "Total Active Days".localized(),
                icon: "calendar.badge.checkmark",
                color: .blue
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Tier Section

    @ViewBuilder
    private func tierSection(tier: AchievementDefinition.Tier, items: [AchievementProgress]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tierTitle(for: tier))
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(items.filter(\.isUnlocked).count)/\(items.count)")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 12)], spacing: 12) {
                ForEach(items) { progress in
                    badgeView(for: progress)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Badge

    @ViewBuilder
    private func badgeView(for progress: AchievementProgress) -> some View {
        // catalog 中找不到定义时(老数据 / 已废弃成就)直接不渲染,避免崩溃
        if let def = progress.definition {
            let isUnlocked = progress.isUnlocked

            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isUnlocked ? tierColor(for: def.tier).opacity(0.18) : Color(.tertiarySystemFill))
                        .frame(width: 56, height: 56)

                    Image(systemName: def.icon)
                        .scaledFont(size: 24)
                        .foregroundColor(isUnlocked ? tierColor(for: def.tier) : .gray.opacity(0.5))
                }

                Text("achievement.\(def.id).title".localized())
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(isUnlocked ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !isUnlocked {
                    Text("\(min(progress.currentValue, def.targetValue))/\(def.targetValue)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                } else if let unlockedDate = progress.unlockedAt {
                    Text(unlockedDate.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        } else {
            // 兜底:占位空 badge 保持网格对齐,避免后续 .frame() 调用歧义
            Color.clear
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Helpers

    private func tierTitle(for tier: AchievementDefinition.Tier) -> String {
        switch tier {
        case .onboarding: return "Getting Started".localized()
        case .streak: return "Streak".localized()
        case .volume: return "Volume".localized()
        case .mastery: return "Mastery".localized()
        case .special: return "Special".localized()
        }
    }

    private func tierColor(for tier: AchievementDefinition.Tier) -> Color {
        switch tier {
        case .onboarding: return .green
        case .streak: return .orange
        case .volume: return .purple
        case .mastery: return .blue
        case .special: return .pink
        }
    }
}

// MARK: - Streak Stat

private struct StreakStat: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
            }
            .foregroundColor(color)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
