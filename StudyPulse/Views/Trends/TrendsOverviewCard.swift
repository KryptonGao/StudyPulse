//
//  TrendsOverviewCard.swift
//  StudyPulse
//
//  趋势页首卡:回答「整体在进步吗」。大数字 + 变化 + 走势图(含目标线)+ 时间范围 chip。
//  Trends hero card answering "am I improving overall?": big number, delta,
//  trend chart (with target line) and range chips.
//

import SwiftUI
import Charts

struct TrendsOverviewCard: View {
    let viewModel: TrendsViewModel
    @Binding var mode: TrendsDisplayMode

    @Environment(RepositoryContainer.self) private var container

    private var trend: OverallTrend { mode == .score ? viewModel.overall : viewModel.overallRank }
    private var tint: Color { container.envManager.effectiveAccentColor }

    private func title(for range: TrendsRange) -> String {
        switch range {
        case .days30: return "trends.v2.range.30d".localized()
        case .days90: return "trends.v2.range.90d".localized()
        case .year: return "trends.v2.range.year".localized()
        case .all: return "trends.v2.range.all".localized()
        }
    }

    private var rangeBinding: Binding<TrendsRange> {
        Binding(get: { viewModel.range }, set: { viewModel.setRange($0) })
    }

    var body: some View {
        PageCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                header
                chart
                ChipBar(
                    items: TrendsRange.allCases.map { ChipItem(id: $0, title: title(for: $0)) },
                    selection: rangeBinding
                )
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.medium) {
            VStack(alignment: .leading, spacing: 6) {
                Text(mode == .score ? "trends.v2.overall.score".localized() : "trends.v2.overall.rank".localized())
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bigNumber)
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let delta = trend.delta {
                        // 排名越小越好,所以取反
                        DeltaLabel(value: delta, format: mode == .score ? "%.1f" : "%.0f", higherIsBetter: mode == .score)
                    }
                }
                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Picker("", selection: $mode) {
                ForEach(TrendsDisplayMode.allCases) { Text($0.localizedName).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 140)
            .labelsHidden()
        }
    }

    private var bigNumber: String {
        guard let avg = trend.average else { return "—" }
        return mode == .score ? String(format: "%.1f", avg) : String(format: "%.0f", avg)
    }

    private var summaryLine: String {
        guard trend.gradeCount > 0 else { return "trends.v2.empty.range".localized() }
        return String(format: "trends.v2.summary".localized(), trend.subjectCount, trend.gradeCount)
    }

    // MARK: Chart

    @ViewBuilder
    private var chart: some View {
        if trend.points.count >= 2 {
            let isScore = mode == .score
            let values = trend.points.map(\.value) + [isScore ? trend.targetRate : nil].compactMap { $0 }
            let lo = isScore ? max(0, (values.min() ?? 0) - 6) : max(0, (values.min() ?? 1) - 2)
            let hi = isScore ? min(100, (values.max() ?? 100) + 4) : (values.max() ?? 10) + 2

            Chart {
                ForEach(trend.points) { point in
                    AreaMark(x: .value("Date", point.date), yStart: .value("Base", lo), yEnd: .value("Value", point.value))
                        .foregroundStyle(tint.opacity(0.12))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let last = trend.points.last {
                    PointMark(x: .value("Date", last.date), y: .value("Value", last.value))
                        .foregroundStyle(tint)
                        .symbolSize(70)
                }
                if isScore, let target = trend.targetRate {
                    RuleMark(y: .value("Target", target))
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            Text(String(format: "trends.v2.target".localized(), target))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                        }
                }
            }
            .chartYScale(domain: isScore ? lo...hi : hi...lo)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: false)
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color(.separator).opacity(0.5))
                    AxisValueLabel().font(.caption2)
                }
            }
            .frame(height: 150)
            .accessibilityLabel(Text(summaryLine))
        } else {
            Text("trends.v2.empty.chart".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 90)
        }
    }
}
