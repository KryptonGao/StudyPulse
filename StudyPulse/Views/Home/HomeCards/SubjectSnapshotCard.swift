//
//  SubjectSnapshotCard.swift
//  StudyPulse
//
//  各科一览:每科一行 —— 平均得分率(按等级着色) + 最近成绩 sparkline + 近期变化。最弱科在前。
//  Subject snapshot: one row per subject — average rate (score-coloured), recent sparkline and delta.
//

import SwiftUI

struct SubjectSnapshotCard: View {
    let snapshots: [SubjectSnapshot]

    @Environment(RepositoryContainer.self) private var container

    var body: some View {
        HomeCardContainer {
            HomeCardHeader(
                icon: "square.stack.3d.up.fill",
                title: "home.subjects.title".localized(),
                subtitle: "home.subjects.subtitle".localized(),
                tint: .indigo
            )
            VStack(spacing: DesignToken.Spacing.small) {
                ForEach(snapshots) { snapshot in
                    SubjectSnapshotRow(
                        snapshot: snapshot,
                        displayName: container.displayName(for: snapshot.subject)
                    )
                }
            }
        }
        .debugLayoutBoundsAuto()
    }
}

private struct SubjectSnapshotRow: View {
    let snapshot: SubjectSnapshot
    let displayName: String

    private var color: Color {
        scoreColor(snapshot.averageRate * snapshot.fullScore, fullScore: snapshot.fullScore)
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName.localized())
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(String(format: "home.subjects.count".localized(), snapshot.count))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HomeSparkline(values: snapshot.recentRates, tint: color, height: 26)
                .frame(width: 72)

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f%%", snapshot.averageRate * 100))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                HomeDeltaBadge(delta: snapshot.deltaPoints, format: "%.0f")
            }
            .frame(minWidth: 46, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(.systemBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.CornerRadius.medium))
        .accessibilityElement(children: .combine)
    }
}
