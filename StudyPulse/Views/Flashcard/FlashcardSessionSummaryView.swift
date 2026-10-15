//
//  FlashcardSessionSummaryView.swift
//  StudyPulse
//
//  闪卡复习 session 结束总结页
//  Flashcard session summary page shown when a review session finishes.
//
//  Created by Chenkai Gao on 2026/6/27.
//

import SwiftUI

/// 复习 session 总结页
/// Session summary page.
struct FlashcardSessionSummaryView: View {
    let stats: FlashcardSessionStats
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // 顶部：完成图标
            // Top: completion icon.
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.green.opacity(0.25), .blue.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark.seal.fill")
                    .scaledFont(size: 56)
                    .foregroundStyle(.green)
            }

            Text("Session Summary".localized())
                .font(.title.weight(.bold))

            // 主要统计
            // Headline stats.
            HStack(spacing: 32) {
                StatCircle(value: "\(stats.reviewed)", label: "Reviewed".localized(), color: .purple)
                StatCircle(value: stats.durationString, label: "Duration".localized(), color: .blue)
            }

            // 4 档分布
            // 4-bucket breakdown.
            VStack(alignment: .leading, spacing: 12) {
                Text("Breakdown".localized())
                    .font(.headline)

                if stats.totalRatings > 0 {
                    BreakdownRow(quality: .again, count: stats.again, total: stats.totalRatings)
                    BreakdownRow(quality: .hard, count: stats.hard, total: stats.totalRatings)
                    BreakdownRow(quality: .good, count: stats.good, total: stats.totalRatings)
                    BreakdownRow(quality: .easy, count: stats.easy, total: stats.totalRatings)
                } else {
                    Text("No cards reviewed".localized())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if stats.earlyContrastReviewed > 0 {
                    Divider()
                    Label(
                        String(
                            format: "memory.climate.summary.interleavedCount".localized(),
                            stats.earlyContrastReviewed
                        ),
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
                    if !stats.interleavedPairs.isEmpty {
                        Text(stats.interleavedPairs.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .padding(.horizontal, 24)

            Spacer()

            // 关闭按钮
            // Dismiss button.
            Button {
                onDismiss()
            } label: {
                Text("Done".localized())
                    .font(.headline)
                    .frame(maxWidth: 400)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: 500)
        .onAppear {
            AchievementManager.shared.recordMistakeReviewed(count: stats.reviewed)
        }
    }
}

// MARK: - Stat Circle

private struct StatCircle: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120, height: 120)
        .background(
            Circle()
                .fill(color.opacity(0.12))
        )
    }
}

// MARK: - Breakdown Row

private struct BreakdownRow: View {
    let quality: ReviewQuality
    let count: Int
    let total: Int

    var percentage: Double {
        total > 0 ? Double(count) / Double(total) : 0
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(quality.shortTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(quality.color)
                .frame(width: 56, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(quality.color.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(quality.color)
                        .frame(width: max(4, proxy.size.width * percentage))
                }
            }
            .frame(height: 12)

            Text("\(count)")
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }
}
