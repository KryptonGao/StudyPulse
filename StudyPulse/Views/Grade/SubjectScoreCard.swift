//
//  SubjectScoreCard.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/4/25.
//
//  学科成绩卡(详情页列表 / 主页小卡 / 报告卡内复用):
//  - 学科名 + 图标 + 主题色
//  - 模式切换:"score" 显示分数 + 排名;"ranking" 仅显示排名
//  - 右侧 mini chart 仅显示最近 3 个月,默认 100x60
//  - 点击为父级 NavigationLink 提供视觉/反馈
//
//  Subject grade card (used in the detail list, Home mini card, and
//  the report card).
//  - Subject name + icon + theme color
//  - Display mode: "score" → score + rank, "ranking" → rank only
//  - Mini chart on the right shows the last 3 months only, default 100x60
//  - Tap is handled by the parent NavigationLink
//

import SwiftUI
import Charts

// 假设你已有 ChartDataPoint 定义,若没有请取消注释下面这段
// 假设这里 `ChartDataPoint` 已存在;若没有,取消下方注释即可。
// Assumption: `ChartDataPoint` is defined elsewhere; if not, uncomment
// the block below.
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let score: Double
    let scoreRate: Double
    let ranking: Int?
}

/// 单科成绩卡
/// Single-subject grade card.
struct SubjectScoreCard: View {
    /// 一条 series(目前只画单科,保留多 series 留作以后对比)
    /// One chart series (currently only one subject; multi-series left for future comparison).
    struct Series: Identifiable {
        let id = UUID()
        let name: String
        let dataPoints: [ChartDataPoint]
        let color: Color
    }

    let subject: String
    let latestGrade: Grade?
    let history: [Grade]
    /// 新增:接收显示模式
    /// New: receives the display mode from the parent.
    let displayMode: TrendsDisplayMode
    @Environment(RepositoryContainer.self) private var container
    /// 入场动画
    /// Entry animation.
    @State private var animateIn = false

    var fullScore: Double {
        container.fullScore(for: subject)
    }

    /// 学科显示名(优先用 Subject.displayName,否则 fallback 到 subject)
    /// Display name (prefer `Subject.displayName`, fall back to the subject identifier).
    var displayTitle: String {
        if let s = container.subjectRepo.subjects.first(where: { $0.name == subject }) {
            return s.displayName.isEmpty ? subject.localized() : s.displayName
        }
        return subject.localized()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: subjectIcon(subject))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [subjectColor(subject), subjectColor(subject).opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.title3)
                Text(displayTitle) // 使用自定义显示名
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(subjectColor(subject))
                Spacer()
                if let g = latestGrade {
                    HStack(spacing: 6) {
                        Text(g.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(Color(.secondaryLabel))
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                } else {
                    Text("--").foregroundColor(Color(.secondaryLabel))
                }
            }
            
            if let g = latestGrade {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            // 根据模式切换显示内容
                            // Switch display content based on `displayMode`.
                            if displayMode == .score {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.1f", g.score))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(scoreColor(g.score, fullScore: fullScore))
                                    .debugInspectAuto(g.score, label: "score")
                                Text("/ \(Int(fullScore))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let rank = g.ranking {
                                Text(String(format: "Rank: %d".localized(), rank))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .debugInspectAuto(rank, label: "rank")
                            }
                        } else {
                            if let rank = g.ranking, rank > 0 {
                                Text("\(rank)")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(scoreColor(g.score, fullScore: fullScore))
                                    .debugInspectAuto(rank, label: "rank")
                                Text(String(format: "%.1f", g.score))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("N/A".localized())
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.indigo, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                Text(String(format: "%.1f", g.score))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Spacer()
                    //
                    // 只展示最近 3 个月的成绩
                    // Show grades from the last 3 months only.
                    let cutoffDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
                    let recentHistory = history.filter { $0.date >= cutoffDate }
                    miniChartView(
                        series: [
                            Series(
                                name: subject,
                                dataPoints: recentHistory.map {
                                    ChartDataPoint(
                                        date: $0.date,
                                        score: $0.score,
                                        scoreRate: $0.scoreRate(subjectFullScore: fullScore),
                                        ranking: $0.ranking
                                    )
                                },
                                color: displayMode == .score ? .blue : .indigo
                            )
                        ],
                        displayMode: displayMode,
                        fullScore: fullScore
                    )
                    .frame(width: 100, height: 60)
                }
            } else {
                Text("No data available".localized())
                    .font(.caption)
                    .foregroundColor(Color(.secondaryLabel))
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .cardSkin()
        .hoverHighlight()
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                animateIn = true
            }
        }
        .debugLayoutBoundsAuto()
    }
    
    private func subjectIcon(_ subject: String) -> String {
        switch subject {
        case "Chinese": return "character.textbox"
        case "Mathematics", "Mathematics A", "Mathematics B": return "function"
        case "English": return "textformat.abc"
        case "Science": return "atom"
        case "Physics": return "magnet"
        case "Chemistry": return "flask.fill"
        case "Biology": return "leaf.fill"
        case "History": return "hourglass"
        case "Geography": return "globe.europe.africa.fill"
        case "Politics": return "building.columns.fill"
        case "History & Society": return "book.and.wrench"
        case "Information Technology": return "laptopcomputer"
        case "General Technology": return "hammer.fill"
        case "Art": return "paintpalette.fill"
        case "Music": return "music.note.list"
        case "PE & Health": return "figure.run"
        default: return "book.fill"
        }
    }

    /// 每个科目对应一种主题色,用于区分卡片
    /// Per-subject theme color used to distinguish cards.
    private func subjectColor(_ subject: String) -> Color {
        switch subject {
        case "Chinese": return .red
        case "Mathematics", "Mathematics A", "Mathematics B": return .blue
        case "English": return .purple
        case "Science": return .teal
        case "Physics": return .orange
        case "Chemistry": return .green
        case "Biology": return .mint
        case "History": return .brown
        case "Geography": return .indigo
        case "Politics": return .pink
        case "History & Society": return .gray
        case "Information Technology": return .cyan
        case "General Technology": return .secondary
        case "Art": return .pink
        case "Music": return .purple
        case "PE & Health": return .red
        default: return .blue
        }
    }
}

// MARK: - 迷你图表(支持用户自选图表类型)
// MARK: - Mini Chart (respects user's chart type preference)

/// SubjectScoreCard 右侧小图。
/// Right-side mini chart on `SubjectScoreCard`.
struct miniChartView: View {
    var series: [SubjectScoreCard.Series]
    /// 是否把 Y 轴显示为百分比(保留以备扩展,目前未使用)
    /// Whether to render the Y axis as a percentage (kept for future use; currently unused).
    var showYAxisAsPercentage: Bool = false
    /// 接收显示模式:score / ranking
    /// Display mode passed in: score / ranking.
    var displayMode: TrendsDisplayMode
    /// 科目满分(用于按比例显示颜色)
    /// Subject full score (used for proportional color mapping).
    var fullScore: Double = 100
    @Environment(RepositoryContainer.self) private var container

    private var history: [Grade] {
        // 合并所有 series 的成绩(这里通常只有一个 subject)
        // Flatten all series' data points into a single grades list
        // (typically only one subject in practice).
        series.flatMap { s in
            s.dataPoints.map { dp in
                Grade(
                    subject: s.name,
                    score: dp.score,
                    ranking: dp.ranking,
                    date: dp.date
                )
            }
        }
    }

    var body: some View {
        if displayMode == .ranking {
            // 排名仍用折线图(排名只有 1 个维度,不适合饼/直方图/热力)
            // Ranking still uses a line chart (ranking is 1-D, so pie/histogram/heatmap don't apply).
            rankingLineChart
        } else {
            // 分数模式:按设置里选定的图表类型渲染
            // Score mode: render with the chart type from settings.
            let grades = history
            if grades.isEmpty {
                Color.clear
            } else {
                TrendChartView(
                    grades: grades,
                    fullScore: fullScore,
                    chartType: container.envManager.preferences.chartType,
                    compact: true,
                    tintColor: container.envManager.effectiveAccentColor
                )
            }
        }
    }

    private var rankingLineChart: some View {
        Chart {
            ForEach(series) { s in
                ForEach(s.dataPoints.filter { ($0.ranking ?? 0) > 0 }) { p in
                    if let rank = p.ranking, rank > 0 {
                        LineMark(
                            x: .value("Time", p.date),
                            y: .value("Rank", rank),
                            series: .value("Subject", s.name)
                        )
                        .foregroundStyle(s.color)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("Time", p.date),
                            y: .value("Rank", rank)
                        )
                        .symbol {
                            Circle()
                                .fill(Color(.secondarySystemGroupedBackground))
                                .frame(width: 8, height: 8)
                                .overlay {
                                    Circle().stroke(scoreColor(p.score, fullScore: fullScore), lineWidth: 2)
                                }
                        }
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

// MARK: - 预览
// MARK: - Preview
#Preview {
    VStack {
        SubjectScoreCard(
            subject: "Chinese",
            latestGrade: Grade(subject: "Chinese", score: 112.0, ranking: 5, date: Date()),
            history: [
                Grade(subject: "Chinese", score: 98.0, date: Date().addingTimeInterval(-86400 * 10)),
                Grade(subject: "Chinese", score: 105.0, date: Date().addingTimeInterval(-86400 * 5)),
                Grade(subject: "Chinese", score: 112.0, date: Date())
            ],
            displayMode: .score
        )
        .environment(RepositoryContainer())

        SubjectScoreCard(
            subject: "Mathematics",
            latestGrade: Grade(subject: "Mathematics", score: 89.0, ranking: 20, date: Date()),
            history: [
                Grade(subject: "Mathematics", score: 120.0, date: Date().addingTimeInterval(-86400 * 10)),
                Grade(subject: "Mathematics", score: 100.0, date: Date().addingTimeInterval(-86400 * 5)),
                Grade(subject: "Mathematics", score: 89.0, date: Date())
            ],
            displayMode: .ranking
        )
        .environment(RepositoryContainer())
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
