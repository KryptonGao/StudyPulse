//
//  AchievementUnlockToast.swift
//  StudyPulse
//
//  成就解锁即时提示 — 顶部滑入 toast。
//  Slide-down toast shown when one or more achievements unlock.
//  Queues multiple badges and displays them one at a time.
//

import SwiftUI

struct AchievementUnlockToast: View, Equatable {
    @Environment(AchievementManager.self) private var achievementManager: AchievementManager
    @State private var currentProgress: AchievementProgress?
    @State private var isVisible = false

    static func == (lhs: AchievementUnlockToast, rhs: AchievementUnlockToast) -> Bool {
        // 仅当 toast 是否可见变化时才需要重渲(Equatable 用法)
        // 通过 onChange 已经局部处理;这里返回 true 表示静态相等,
        // 配合 .equatable() modifier 可以避免 SwiftUI 在父 view diff 时
        // 重建整个 AchievementUnlockToast 实例
        return true
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let progress = currentProgress, isVisible {
                toastView(for: progress)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isVisible)
        .onChange(of: achievementManager.newlyUnlocked) { _, newValue in
            showNextIfNeeded()
        }
        .onAppear {
            showNextIfNeeded()
        }
    }

    // MARK: - Queue management

    private func showNextIfNeeded() {
        guard currentProgress == nil, !achievementManager.newlyUnlocked.isEmpty else { return }
        guard let next = achievementManager.newlyUnlocked.first else { return }
        currentProgress = next
        withAnimation { isVisible = true }

        // Auto-dismiss after 2.5 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2_500))
            guard !Task.isCancelled else { return }
            dismissCurrent()
        }
    }

    private func dismissCurrent() {
        guard let progress = currentProgress else { return }
        withAnimation { isVisible = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            achievementManager.dismissNewlyUnlocked(progress)
            currentProgress = nil
            showNextIfNeeded()
        }
    }

    // MARK: - Toast View

    @ViewBuilder
    private func toastView(for progress: AchievementProgress) -> some View {
        // 老快照中可能有 catalog 已删除的成就 id,definition 可能为 nil。
        // Toast 跳过显示即可,等下一次刷新时自然淘汰。
        if let def = progress.definition {
            Button {
                dismissCurrent()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(tierColor(for: def.tier).opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: def.icon)
                            .scaledFont(size: 18, weight: .semibold)
                            .foregroundColor(tierColor(for: def.tier))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("toast.unlocked".localized())
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text("achievement.\(def.id).title".localized())
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .buttonStyle(.plain)
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
