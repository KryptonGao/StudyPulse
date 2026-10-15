//
//  RecentGradesCard.swift
//  StudyPulse
//
//  主页"最近成绩"区域:取最近 5 条成绩(按日期倒序)。
//  Home "Recent Grades" region: shows the 5 most recent grades (sorted by date desc).
//
//  Extracted from HomeView.swift during card-extraction refactor (2026-07-05).
//

import SwiftUI

/// 主页"最近成绩"区域。
/// 之前直接读 `container.gradeRepo.grades` 现地 sort + prefix(5)。
/// Home "Recent Grades" region.
/// Previously read `container.gradeRepo.grades` inline and did sort + prefix(5) on the spot.
struct RecentGradesCard: View {
    @Environment(RepositoryContainer.self) private var container

    /// 最近 5 条成绩(按日期倒序,日期相同则维持原顺序)。
    /// The 5 most recent grades (date descending; stable for equal dates).
    var recentGrades: [Grade] {
        Array(container.gradeRepo.grades.sorted { $0.date > $1.date }.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Grades".localized())
                .scaledFont(size: 18, weight: .semibold)
                .foregroundColor(.primary)

            VStack(spacing: 10) {
                ForEach(recentGrades) { grade in
                    CompactGradeRow(grade: grade)
                }
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
        .debugLayoutBoundsAuto()
    }
}

// MARK: - 紧凑成绩行
// MARK: - Compact Grade Row

/// RecentGradesCard 内的行式成绩卡(分数圆 + 科目 + 日期 + 排名)。
///
/// 分数颜色阈值 0.85 / 0.6:≥0.85 绿、≥0.6 橙、其余红。
/// Row-style grade card inside RecentGradesCard (score circle + subject + date + ranking).
///
/// Score color thresholds 0.85 / 0.6: ≥0.85 green, ≥0.6 orange, otherwise red.
struct CompactGradeRow: View {
    let grade: Grade

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(scoreColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Text("\(Int(grade.score))")
                    .scaledFont(size: 14, weight: .bold)
                    .foregroundColor(scoreColor)
                    .debugInspectAuto(grade.score, label: "score")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(grade.subject.localized())
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundColor(.primary)

                Text(grade.date, style: .date)
                    .scaledFont(size: 12)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let ranking = grade.ranking {
                Text("#\(ranking)")
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.6))
        .cornerRadius(12)
        .debugLayoutBoundsAuto()
    }

    private var scoreColor: Color {
        let rate = grade.scoreRate()
        // 颜色阈值:≥0.85 绿、≥0.6 橙、其余红
        // Color thresholds: ≥0.85 green, ≥0.6 orange, otherwise red.
        if rate >= 0.85 { return .green }
        if rate >= 0.6 { return .orange }
        return .red
    }
}
