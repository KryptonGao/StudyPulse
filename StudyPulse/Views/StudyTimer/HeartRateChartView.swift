//
//  HeartRateChartView.swift
//  StudyPulse
//
//  可复用的学习会话心率曲线图。
//  Reusable heart-rate curve chart for a study session.
//
//  - LineMark + PointMark 平滑曲线(catmullRom)
//  - RHR 基线 RuleMark
//  - 峰值点高亮(超过 rhrBaseline + 30 或最高 N 个)
//  - 难题标注点(带颜色)
//  - 点击峰值 / 长按任意位置回调
//

import SwiftUI
import Charts

// MARK: - HeartRateChartView

struct HeartRateChartView: View {
    let samples: [HeartRateSample]
    let sessionStart: Date
    let rhrBaseline: Double?
    let annotations: [DifficultyAnnotation]
    let peaks: [HeartRateSample]

    /// 点击峰值回调(传入峰值样本)
    /// Tap-on-peak callback.
    var onTapPeak: ((HeartRateSample) -> Void)? = nil
    /// 长按任意位置回调(传入最近的时间戳)
    /// Long-press callback with nearest timestamp.
    var onLongPress: ((Date, Double?) -> Void)? = nil

    @State private var selectedSample: HeartRateSample?
    @State private var touchLocation: CGPoint?

    // MARK: - Derived

    private var bpmValues: [Double] { samples.map(\.bpm) }
    private var minBpm: Double { bpmValues.min() ?? 60 }
    private var maxBpm: Double { bpmValues.max() ?? 100 }
    private var yLower: Double { max(40, minBpm - 10) }
    private var yUpper: Double { min(200, maxBpm + 10) }

    private var peakIds: Set<UUID> { Set(peaks.map(\.id)) }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if samples.isEmpty {
                emptyState
            } else {
                chart
                statsRow
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            // RHR 基线
            if let rhr = rhrBaseline {
                RuleMark(y: .value("RHR", rhr))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.blue.opacity(0.5))
                    .annotation(position: .top, alignment: .leading) {
                        Text("RHR \(Int(rhr))")
                            .font(.caption2)
                            .foregroundColor(.blue.opacity(0.7))
                    }
            }

            // 心率曲线
            ForEach(samples) { s in
                LineMark(
                    x: .value("Time", s.timestamp),
                    y: .value("BPM", s.bpm)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.pink.gradient)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                PointMark(
                    x: .value("Time", s.timestamp),
                    y: .value("BPM", s.bpm)
                )
                .foregroundStyle(peakIds.contains(s.id) ? Color.red : Color.pink)
                .symbolSize(peakIds.contains(s.id) ? 120 : 35)
            }

            // 难题标注点(用不同颜色叠加)
            ForEach(annotations) { a in
                if let hr = a.heartRate {
                    PointMark(
                        x: .value("AnnoTime", a.timestamp),
                        y: .value("AnnoBPM", hr)
                    )
                    .foregroundStyle(Color.orange)
                    .symbolSize(80)
                    .annotation(position: .top, spacing: 4) {
                        Text(a.note.prefix(8))
                            .scaledFont(size: 9, weight: .medium)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                }
            }

            // 选中点标线
            if let sel = selectedSample {
                RuleMark(x: .value("Selected", sel.timestamp))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                PointMark(
                    x: .value("Selected", sel.timestamp),
                    y: .value("SelectedBPM", sel.bpm)
                )
                .foregroundStyle(Color.pink)
                .symbolSize(150)
            }
        }
        .chartXScale(domain: sessionStart...(samples.last?.timestamp ?? sessionStart.addingTimeInterval(60)))
        .chartYScale(domain: yLower...yUpper)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.minute().second(), centered: false)
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text("\(Int(d))")
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 220)
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
                                        selectedSample = nearestSample(to: date)
                                        touchLocation = value.location
                                    }
                                }
                                .onEnded { _ in
                                    selectedSample = nil
                                    touchLocation = nil
                                }
                        )
                        .onLongPressGesture(minimumDuration: 0.4) {
                            // 长按 → 手动标注
                            if let center = touchLocation {
                                let xInPlot = center.x - plot.minX
                                if let date: Date = proxy.value(atX: xInPlot) {
                                    if let nearest = nearestSample(to: date) {
                                        onLongPress?(nearest.timestamp, nearest.bpm)
                                    } else {
                                        onLongPress?(date, nil)
                                    }
                                }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 16) {
            statItem(label: "Avg".localized(), value: String(format: "%.0f", avgBpm))
            statItem(label: "Max".localized(), value: String(format: "%.0f", maxBpm), color: .red)
            statItem(label: "Min".localized(), value: String(format: "%.0f", minBpm), color: .blue)
            Spacer()
            if !peaks.isEmpty {
                Label("\(peaks.count)", systemImage: "arrow.up.heart")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.red)
            }
        }
        .font(.caption)
    }

    private func statItem(label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .scaledFont(size: 10)
                .foregroundColor(.secondary)
            Text(value)
                .scaledFont(size: 14, weight: .semibold, design: .rounded)
                .foregroundColor(color)
        }
    }

    private var avgBpm: Double {
        guard !bpmValues.isEmpty else { return 0 }
        return bpmValues.reduce(0, +) / Double(bpmValues.count)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.text.square")
                .scaledFont(size: 28)
                .foregroundColor(.secondary)
            Text("No heart-rate data".localized())
                .scaledFont(size: 14, weight: .medium)
                .foregroundColor(.secondary)
            Text("Apple Watch may not have been worn or no samples were recorded during this session.".localized())
                .scaledFont(size: 12)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Helpers

    private func nearestSample(to date: Date) -> HeartRateSample? {
        samples.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }
}

// MARK: - Peak detection

extension HeartRateSample {
    /// 检测心率峰值:超过 threshold 的局部极大值。
    /// Detect peaks: local maxima above `threshold`.
    /// - Parameters:
    ///   - threshold: bpm 阈值,低于此值不视为峰值
    ///   - minGapSeconds: 同一峰值簇的最小间隔(避免相邻点重复)
    static func detectPeaks(samples: [HeartRateSample], threshold: Double, minGapSeconds: TimeInterval = 60) -> [HeartRateSample] {
        guard samples.count >= 3 else { return [] }
        var peaks: [HeartRateSample] = []
        for i in 1..<(samples.count - 1) {
            let prev = samples[i - 1]
            let curr = samples[i]
            let next = samples[i + 1]
            if curr.bpm > prev.bpm && curr.bpm >= next.bpm && curr.bpm >= threshold {
                // 检查与上一个峰值的间隔
                if let lastPeak = peaks.last,
                   curr.timestamp.timeIntervalSince(lastPeak.timestamp) < minGapSeconds {
                    // 替换为更高的那个
                    if curr.bpm > lastPeak.bpm {
                        peaks[peaks.count - 1] = curr
                    }
                } else {
                    peaks.append(curr)
                }
            }
        }
        return peaks
    }

    /// 便捷入口:用 RHR + 30 作为阈值,无 RHR 时用中位数 + 30
    /// Convenience entry: threshold = rhr + 30, or median + 30 if rhr is nil.
    static func detectPeaks(samples: [HeartRateSample], rhrBaseline: Double?) -> [HeartRateSample] {
        let sorted = samples.map(\.bpm).sorted()
        let median: Double = sorted.isEmpty ? 80 : sorted[sorted.count / 2]
        let threshold = (rhrBaseline ?? median) + 30
        return detectPeaks(samples: samples, threshold: threshold)
    }
}

// MARK: - Preview

#Preview("Heart rate chart with peaks") {
    let now = Date()
    let samples: [HeartRateSample] = (0..<15).map { i in
        HeartRateSample(
            id: UUID(),
            timestamp: now.addingTimeInterval(Double(i) * 120),
            bpm: [72, 75, 78, 95, 110, 102, 88, 80, 76, 92, 105, 98, 85, 78, 74][i]
        )
    }
    let peaks = HeartRateSample.detectPeaks(samples: samples, rhrBaseline: 65)
    let annotations: [DifficultyAnnotation] = [
        DifficultyAnnotation(id: UUID(), timestamp: samples[4].timestamp, heartRate: 110, note: "几何证明卡住", subjectId: nil)
    ]
    return HeartRateChartView(
        samples: samples,
        sessionStart: now,
        rhrBaseline: 65,
        annotations: annotations,
        peaks: peaks
    )
    .padding()
}

#Preview("Empty state") {
    HeartRateChartView(
        samples: [],
        sessionStart: Date(),
        rhrBaseline: nil,
        annotations: [],
        peaks: []
    )
    .padding()
}
