//
//  MasteryCurveView.swift
//  StudyPulse
//
//  错题「掌握度曲线」折线图。
//  Line chart showing a single mistake's mastery score over time.
//
//  数据源：MistakeNote.masteryHistory: [MasteryHistoryEntry]
//  - 起点是题目创建时（分数=0），每次复习追加一个点
//  - 折线连起来就是进步轨迹
//  - 同时显示当前 masteryScore 和 exposureCount
//

import SwiftUI
import Charts

/// 错题详情页顶部的掌握度曲线图。
/// Mastery curve chart at the top of the mistake-detail page.
struct MasteryCurveView: View {
    let history: [MasteryHistoryEntry]
    let currentScore: Double
    let exposureCount: Int
    let createdAt: Date
    /// 自定义主色(默认用全局主色)
    /// Custom tint color (defaults to the global accent color).
    var tintColor: Color = .accentColor
    /// 单卡片下,强制撑满父宽度
    /// Force the chart to fill its parent's width in the single-card case.
    var fillWidth: Bool = true

    @State private var selectedEntry: MasteryHistoryEntry?
    @State private var touchX: CGFloat?

    /// 用于绘图的合并数据：起点 + 所有历史点
    private var plotPoints: [MasteryPlotPoint] {
        var pts: [MasteryPlotPoint] = [MasteryPlotPoint(timestamp: createdAt, score: 0.0, isStart: true)]
        pts.append(contentsOf: history.map {
            MasteryPlotPoint(timestamp: $0.timestamp, score: $0.score, isStart: false)
        })
        return pts
    }

    private var dateRange: (Date, Date) {
        let pts = plotPoints
        guard let first = pts.first?.timestamp, let last = pts.last?.timestamp else {
            let now = Date()
            return (now, now)
        }
        // 单点时给 X 轴留 1 天的窗口，否则 min == max 会让 chart 报错
        if first == last {
            return (first.addingTimeInterval(-3600), last.addingTimeInterval(3600))
        }
        return (first, last)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            chart
            legend
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Header (current score + exposure)
    // MARK: - 头部(当前分 + 复习次数)

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mastery".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f%%", currentScore * 100))
                        .scaledFont(size: 28, weight: .bold, design: .rounded)
                        .foregroundStyle(scoreColor(score: currentScore))
                        .contentTransition(.numericText())
                    Text(scoreTagline(currentScore))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Exposures".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(exposureCount)")
                    .scaledFont(size: 22, weight: .semibold, design: .rounded)
                    .foregroundStyle(tintColor)
                    .contentTransition(.numericText())
            }
        }
    }

    // MARK: - Chart
    // MARK: - 图表

    @ViewBuilder
    private var chart: some View {
        if history.isEmpty {
            emptyState
        } else {
            chartBody
        }
    }

    @ViewBuilder
    private var chartBody: some View {
        let (xStart, xEnd) = dateRange
        let pts = plotPoints
        Chart {
            // 0.20 / 0.50 / 0.80 三条参考虚线
            ForEach([0.2, 0.5, 0.8], id: \.self) { level in
                RuleMark(y: .value("Level", level))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.25))
            }

            ForEach(pts) { p in
                LineMark(
                    x: .value("Time", p.timestamp),
                    y: .value("Score", p.score)
                )
                .foregroundStyle(tintColor)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Time", p.timestamp),
                    y: .value("Score", p.score)
                )
                .foregroundStyle(p.isStart ? Color.secondary : tintColor)
                .symbolSize(p.isStart ? 30 : 40)
            }

            // 选中点的标线 + 标签
            if let s = selectedEntry,
               let xPos = pts.first(where: { $0.timestamp == s.timestamp }) {
                RuleMark(x: .value("Selected", xPos.timestamp))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                PointMark(
                    x: .value("Selected", xPos.timestamp),
                    y: .value("SelectedScore", xPos.score)
                )
                .foregroundStyle(tintColor)
                .symbolSize(120)
            }
        }
        .chartXScale(domain: xStart...xEnd)
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.25, 0.5, 0.75, 1.0]) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text("\(Int(d * 100))%")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: false)
                    .font(.caption2)
            }
        }
        .frame(height: 150)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotFrameAnchor = proxy.plotFrame {
                    let plot = geo[plotFrameAnchor]
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let xInPlot = value.location.x - plot.minX
                                    if let date: Date = proxy.value(atX: xInPlot) {
                                        selectedEntry = nearestEntry(to: date)
                                        touchX = value.location.x
                                    }
                                }
                                .onEnded { _ in
                                    selectedEntry = nil
                                    touchX = nil
                                }
                        )
                }
            }
        }
    }

    // MARK: - Empty / Legend
    // MARK: - 空状态 / 图例

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No reviews yet".localized())
                .font(.subheadline.weight(.medium))
            Text("Review this card to start tracking your mastery progress".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 130)
    }

    @ViewBuilder
    private var legend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle().fill(tintColor).frame(width: 8, height: 8)
                Text("Mastery".localized())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let s = selectedEntry {
                Text(String(format: "%@  %.0f%%".localized(), dateLabel(s.timestamp), s.score * 100))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("\(history.count) " + "reviews".localized())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers
    // MARK: - 辅助函数

    private func nearestEntry(to date: Date) -> MasteryHistoryEntry? {
        history.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(date)) < abs(rhs.timestamp.timeIntervalSince(date))
        }
    }

    private func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// 掌握度分对应的颜色阈值:<0.25 红,<0.5 橙,<0.75 蓝,其余绿
    /// Color thresholds per mastery score: <0.25 red, <0.5 orange, <0.75 blue, otherwise green.
    private func scoreColor(score: Double) -> Color {
        switch score {
        case ..<0.25:  return .red
        case ..<0.5:   return .orange
        case ..<0.75:  return .blue
        default:       return .green
        }
    }

    private func scoreTagline(_ score: Double) -> String {
        // 5 段文本分桶:Struggling / Building / Familiar / Confident / Mastered
        // 5-bucket text labeling: Struggling / Building / Familiar / Confident / Mastered.
        switch score {
        case ..<0.2:  return "Struggling".localized()
        case ..<0.4:  return "Building".localized()
        case ..<0.6:  return "Familiar".localized()
        case ..<0.8:  return "Confident".localized()
        default:      return "Mastered".localized()
        }
    }
}

// MARK: - Plot Point
// MARK: - 绘图点

/// 内部绘图点(起点 + 历次 review)
/// Internal plot point (origin + each review).
private struct MasteryPlotPoint: Identifiable {
    let id: String
    let timestamp: Date
    let score: Double
    let isStart: Bool

    init(timestamp: Date, score: Double, isStart: Bool) {
        // 给一个稳定 id,相同 (timestamp, score, isStart) 视为同一点
        // Stable id so identical (timestamp, score, isStart) are treated as the same point.
        self.id = "\(timestamp.timeIntervalSince1970)-\(score)-\(isStart ? 1 : 0)"
        self.timestamp = timestamp
        self.score = score
        self.isStart = isStart
    }
}

#Preview("Empty") {
    MasteryCurveView(
        history: [],
        currentScore: 0,
        exposureCount: 0,
        createdAt: Date().addingTimeInterval(-86400 * 7)
    )
    .padding()
}

#Preview("With history") {
    let now = Date()
    let entries: [MasteryHistoryEntry] = (0..<6).map { i in
        let q: Int = [4, 4, 3, 4, 5, 4][i]
        let s = [0.21, 0.36, 0.38, 0.55, 0.72, 0.78][i]
        return MasteryHistoryEntry(
            timestamp: now.addingTimeInterval(-Double(6 - i) * 86400),
            score: s,
            quality: q
        )
    }
    return MasteryCurveView(
        history: entries,
        currentScore: 0.78,
        exposureCount: 6,
        createdAt: now.addingTimeInterval(-7 * 86400)
    )
    .padding()
}
