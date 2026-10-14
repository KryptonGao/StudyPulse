//
//  BodyMindTrendCard.swift
//  StudyPulse
//
//  身心趋势:心情 / 睡眠 / HRV 三段切换的 14 天图表。无数据的分段自动隐藏。
//  Body & mind trend: 14-day chart with a mood / sleep / HRV picker. Segments without data are hidden.
//

import SwiftUI
import Charts

struct BodyMindTrendCard: View {
    let mood: [DailyValuePoint]
    let sleep: [DailyValuePoint]
    let hrv: [DailyValuePoint]

    @State private var selected: Metric = .mood

    enum Metric: String, CaseIterable, Identifiable {
        case mood, sleep, hrv
        var id: String { rawValue }

        var title: String {
            switch self {
            case .mood: return "home.bodyMind.mood".localized()
            case .sleep: return "home.bodyMind.sleep".localized()
            case .hrv: return "HRV"
            }
        }
        var tint: Color {
            switch self {
            case .mood: return .pink
            case .sleep: return .indigo
            case .hrv: return .teal
            }
        }
        var unit: String {
            switch self {
            case .mood: return ""
            case .sleep: return "h"
            case .hrv: return "ms"
            }
        }
    }

    private func points(for metric: Metric) -> [DailyValuePoint] {
        switch metric {
        case .mood: return mood
        case .sleep: return sleep
        case .hrv: return hrv
        }
    }

    private var available: [Metric] {
        Metric.allCases.filter { points(for: $0).count >= 2 }
    }

    /// 当前选中项不可用时回退到第一个可用项。
    private var active: Metric {
        available.contains(selected) ? selected : (available.first ?? .mood)
    }

    var body: some View {
        HomeCardContainer {
            HomeCardHeader(
                icon: "waveform.path.ecg",
                title: "home.bodyMind.title".localized(),
                subtitle: "home.bodyMind.subtitle".localized(),
                tint: .pink
            )
            if available.count > 1 {
                Picker("", selection: Binding(get: { active }, set: { selected = $0 })) {
                    ForEach(available) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            let metric = active
            let data = points(for: metric)
            summary(metric: metric, data: data)
            chart(metric: metric, data: data)
        }
        .debugLayoutBoundsAuto()
    }

    // MARK: - Summary

    private func summary(metric: Metric, data: [DailyValuePoint]) -> some View {
        let values = data.map(\.value)
        let average = values.reduce(0, +) / Double(max(values.count, 1))
        let latest = values.last ?? 0
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(format(latest, metric: metric))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(metric.unit)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HomeDeltaBadge(delta: latest - average, format: metric == .hrv ? "%.0f" : "%.1f")
            Spacer(minLength: 0)
            Text(String(format: "home.bodyMind.avg".localized(), format(average, metric: metric) + metric.unit))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func format(_ value: Double, metric: Metric) -> String {
        metric == .hrv ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    // MARK: - Chart

    @ViewBuilder
    private func chart(metric: Metric, data: [DailyValuePoint]) -> some View {
        let average = data.map(\.value).reduce(0, +) / Double(max(data.count, 1))
        Chart {
            switch metric {
            case .sleep:
                ForEach(data) { point in
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("Hours", point.value))
                        .foregroundStyle(point.value >= 7 ? metric.tint.gradient : Color.orange.gradient)
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Target", 7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            case .mood, .hrv:
                ForEach(data) { point in
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("Value", point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(metric.tint)
                    AreaMark(
                        x: .value("Day", point.date, unit: .day),
                        yStart: .value("Base", yDomain(metric: metric, data: data).lowerBound),
                        yEnd: .value("Value", point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(metric.tint.opacity(0.12))
                    PointMark(x: .value("Day", point.date, unit: .day), y: .value("Value", point.value))
                        .symbolSize(22)
                        .foregroundStyle(metric.tint)
                }
                if metric == .hrv {
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
            }
        }
        .chartYScale(domain: yDomain(metric: metric, data: data))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel()
            }
        }
        .frame(height: 130)
    }

    private func yDomain(metric: Metric, data: [DailyValuePoint]) -> ClosedRange<Double> {
        switch metric {
        case .mood:
            return 1...5
        case .sleep:
            return 0...max(10, (data.map(\.value).max() ?? 8) + 1)
        case .hrv:
            let values = data.map(\.value)
            let lo = values.min() ?? 0
            let hi = values.max() ?? 1
            let pad = max((hi - lo) * 0.2, 5)
            return max(lo - pad, 0)...(hi + pad)
        }
    }
}
