//
//  MistakeListCellViews.swift
//  StudyPulse
//
//  错题主页列表中的 5 个 cell 组件:
//  - SubjectCardView     学科行(带最近 7 天新增数)
//  - MistakeCardView     单条错题行(标题 + 学科 + 标签 + 日期 + 图数 + 难度星)
//  - StatItem            Overview 里的统计项(图标 + 数字 + 标题)
//  - OverviewStatsCard   Overview 统计卡(Total + Subjects)
//  - SubjectOverviewCard 学科下错题页顶部的概览(学科 + 本周新增 + 最早记录日期)
//
//  Phase 3 拆分 (2026-07-14):原 `MistakeView.swift` 抽出,本文件每个组件独立可预览。
//

import SwiftUI

// MARK: - Overview Stats Card / 概览统计卡片



// MARK: - Subject Overview Card / 科目概览卡片

/// 学科下错题页顶部的概览(学科名 + 本周新增 + 最早记录日期)
/// Subject overview card on the per-subject drill-down page.
struct SubjectOverviewCard: View {
    let subject: String
    let mistakes: [MistakeNote]

    /// 一周内新增的错题数
    /// Number of mistakes added in the last 7 days.
    var lastWeekCount: Int {
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return mistakes.filter { $0.date > oneWeekAgo }.count
    }

    /// 错题里最早期的一条
    /// The earliest mistake in the list (used to display "tracked since N days").
    var oldestDate: Date? {
        mistakes.min { $0.date < $1.date }?.date
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subject.localized())
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(String(format: "%d mistakes".localized(), mistakes.count))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "folder.fill")
                    .font(.title)
                    .foregroundColor(.purple)
            }

            if lastWeekCount > 0 {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundColor(.green)
                    Text(String(format: "%d added this week".localized(), lastWeekCount))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            if let oldest = oldestDate {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.orange)
                    Text(String(format: "Oldest: %@".localized(), oldest.formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .cardSkin()
    }
}

// MARK: - Stat Item / 统计项组件



// MARK: - Subject Card / 科目卡片组件



// MARK: - Mistake Card / 错题卡片视图

/// 单条错题行(标题 + 学科 + 标签 + 日期 + 图数 + 难度星)
/// Single mistake row. Used by per-subject drill-down and the home page.
struct MistakeCardView: View {
    let mistake: MistakeNote
    @State private var animateIn = false

    /// 四段图片总数(用于右上角的"图"小角标)
    /// Total image count across all four sections (for the "photo" badge).
    var totalImageCount: Int {
        mistake.questionImages.count + mistake.reasonImages.count +
        mistake.wrongSolutionImages.count + mistake.correctSolutionImages.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader
            cardDetails
        }
        .padding(DesignToken.Spacing.cardPadding)
        .cardSkin()
        .hoverHighlight()
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 15)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                animateIn = true
            }
        }
    }

    @ViewBuilder
    private var cardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(mistake.title)
                    .font(.headline)
                    .lineLimit(1)

                if !mistake.subject.isEmpty {
                    Text(mistake.subject.localized())
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(.systemPurple).opacity(0.15))
                        )
                        .foregroundColor(Color(.systemPurple))
                }

                if !mistake.tags.isEmpty {
                    TagChipsView(tags: mistake.tags, compact: true, maxVisible: 3)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(mistake.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if totalImageCount > 0 {
                    Label("\(totalImageCount)", systemImage: "photo.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if mistake.difficulty > 0 {
                    HStack(spacing: 1) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= mistake.difficulty ? "star.fill" : "star")
                                .scaledFont(size: 9)
                                .foregroundStyle(i <= mistake.difficulty ? Color.orange : Color.gray.opacity(0.3))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var cardDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !mistake.originalQuestion.isEmpty {
                Text(mistake.originalQuestion)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
            if !mistake.source.isEmpty {
                Text(String(format: "Source: %@".localized(), mistake.source))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            MistakeShelfLifeView(mistake: mistake)
        }
    }
}

// MARK: - Previews / 独立预览入口

#Preview("MistakeCardView") {
    let m = MistakeNote(
        title: "二次函数顶点公式",
        subject: "Mathematics",
        originalQuestion: "已知 f(x) = x² - 4x + 3,求顶点坐标。",
        source: "数学课本",
        date: Date(),
        errorReason: "忘记配方",
        wrongSolution: "x = -b/2a = 2",
        correctSolution: "顶点 (2, -1)",
        tags: ["跳步", "计算粗心"]
    )
    MistakeCardView(mistake: m)
        .padding()
}

#Preview("SubjectOverviewCard") {
    SubjectOverviewCard(
        subject: "Mathematics",
        mistakes: (0..<10).map { _ in
            MistakeNote(
                title: "Sample",
                subject: "Mathematics",
                originalQuestion: "原题",
                source: "来源",
                date: Date().addingTimeInterval(-Double.random(in: 0...30 * 86400)),
                errorReason: "错因",
                wrongSolution: "错解",
                correctSolution: "正解"
            )
        }
    )
    .padding()
}
