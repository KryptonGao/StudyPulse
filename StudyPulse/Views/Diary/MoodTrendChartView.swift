//
//  MoodTrendChartView.swift
//  StudyPulse
//
//  心情 / 精力 × 学习时长 × HRV 交叉分析图。
//  7/30 天切换;双 Y 轴:左轴 mood/energy 折线(1-5),右轴学习时长柱状(分钟)。
//  HRV 折线为可选第三层(需 HRV 已授权)。
//
//  Mood / energy × study minutes × HRV cross-analysis chart.
//  7/30-day toggle; dual Y-axis: left axis mood/energy lines (1-5),
//  right axis study minutes bars. HRV line is an optional third layer
//  (requires HRV authorization).
//

import SwiftUI
import Charts

struct MoodTrendChartView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(HealthKitManager.self) private var hrvManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss

    @State private var rangeDays: Int = 7

    /// 单日聚合数据点(供 Chart 使用)
    /// Per-day aggregated data point (for Chart).
    struct DailyPoint: Identifiable {
        let id = UUID()
        let date: Date
        let moodScore: Double?       // 当日 mood 均值(1-5),无日记为 nil
        let energyScore: Double?     // 当日 energy 均值(1-5)
        let studyMinutes: Double     // 当日学习总分钟数
        let hrvValue: Double?        // 当日 HRV 均值(若可用)
    }

    /// 折线图专用点(已过滤掉 nil,保证 ForEach 闭包内可直接取 value)
    /// Chart-friendly point with non-optional value, used to keep
    /// `ForEach` closures free of nested `if let` (which broke type inference).
    private struct ChartPoint: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private var moodPoints: [ChartPoint] {
        points.compactMap { p in
            guard let v = p.moodScore else { return nil }
            return ChartPoint(date: p.date, value: v)
        }
    }
    private var energyPoints: [ChartPoint] {
        points.compactMap { p in
            guard let v = p.energyScore else { return nil }
            return ChartPoint(date: p.date, value: v)
        }
    }
    private var hrvPoints: [ChartPoint] {
        points.compactMap { p in
            guard let v = p.hrvValue else { return nil }
            return ChartPoint(date: p.date, value: v)
        }
    }

    private var points: [DailyPoint] {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .day, value: -rangeDays, to: cal.startOfDay(for: now)) ?? now

        let sessions = StudyTimerManager.shared.sessions.filter {
            $0.completed && $0.startDate >= start && $0.startDate <= now
        }
        let diaryEntries = container.diaryRepo.entriesInRange(start, now.addingTimeInterval(86400))

        // 按天分组
        // Group by day.
        var sessionByDay: [Date: Double] = [:]
        for s in sessions {
            let day = cal.startOfDay(for: s.startDate)
            sessionByDay[day, default: 0] += Double(s.durationSeconds) / 60.0
        }

        var diaryByDay: [Date: [DiaryEntry]] = [:]
        for d in diaryEntries {
            let day = cal.startOfDay(for: d.date)
            diaryByDay[day, default: []].append(d)
        }

        var hrvByDay: [Date: Double] = [:]
        for h in hrvManager.dailyHRVHistory {
            let day = cal.startOfDay(for: h.date)
            hrvByDay[day, default: 0] = h.value
        }

        var result: [DailyPoint] = []
        var current = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: now)
        while current <= endDay {
            let diaries = diaryByDay[current] ?? []
            let mood = diaries.isEmpty ? nil : diaries.map { Double($0.moodScore) }.reduce(0, +) / Double(diaries.count)
            let energy = diaries.isEmpty ? nil : diaries.map { Double($0.energyScore) }.reduce(0, +) / Double(diaries.count)
            let study = sessionByDay[current] ?? 0
            let hrv = hrvByDay[current]
            result.append(DailyPoint(date: current, moodScore: mood, energyScore: energy, studyMinutes: study, hrvValue: hrv))
            current = cal.date(byAdding: .day, value: 1, to: current) ?? current
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Range".localized(), selection: $rangeDays) {
                    Text("Last 7 Days".localized()).tag(7)
                    Text("Last 30 Days".localized()).tag(30)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if points.isEmpty || points.allSatisfy({ $0.moodScore == nil && $0.studyMinutes == 0 }) {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            moodEnergyChart
                            studyMinutesChart
                            if hrvManager.hrvEnabled && hrvManager.isAuthorized && points.contains(where: { $0.hrvValue != nil }) {
                                hrvChart
                            }
                            summaryStats
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationTitle("Mood Trend".localized())
            .navigationBarTitleDisplayMode(.inline)
            .containerBackground(.clear, for: .navigation)
            .background(Color(.systemGroupedBackground).opacity(0.4).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized()) { dismiss() }
                }
            }
        }
    }

    // MARK: - 心情 / 精力折线图 / Mood + Energy Line Chart

    private var moodEnergyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mood & Energy".localized())
                .font(.headline)
            Chart {
                ForEach(moodPoints) { p in
                    LineMark(
                        x: .value("Date".localized(), p.date),
                        y: .value("Mood".localized(), p.value)
                    )
                    .foregroundStyle(by: .value("Metric", "Mood"))
                    .symbol(Circle())
                }
                ForEach(energyPoints) { p in
                    LineMark(
                        x: .value("Date".localized(), p.date),
                        y: .value("Energy".localized(), p.value)
                    )
                    .foregroundStyle(by: .value("Metric", "Energy"))
                    .symbol(.square)
                }
            }
            .chartForegroundStyleScale([
                "Mood": Color.orange,
                "Energy": Color.blue
            ])
            .chartLegend(.hidden)
            .chartYScale(domain: 0...5)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.day().month())
                    AxisGridLine()
                }
            }
            .frame(height: 200)

            HStack(spacing: 16) {
                LegendDot(color: .orange, label: "Mood".localized())
                LegendDot(color: .blue, label: "Energy".localized())
            }
            .font(.caption)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 学习时长柱状图 / Study Minutes Bar Chart

    private var studyMinutesChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Study Minutes".localized())
                .font(.headline)
            Chart {
                ForEach(points) { p in
                    BarMark(
                        x: .value("Date".localized(), p.date),
                        y: .value("Minutes".localized(), p.studyMinutes)
                    )
                    .foregroundStyle(container.envManager.effectiveAccentColor.opacity(0.6))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.day().month())
                    AxisGridLine()
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - HRV 折线图 / HRV Line Chart

    private var hrvChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HRV (ms)".localized())
                .font(.headline)
            Chart {
                ForEach(hrvPoints) { p in
                    LineMark(
                        x: .value("Date".localized(), p.date),
                        y: .value("HRV".localized(), p.value)
                    )
                    .foregroundStyle(Color.purple)
                    .symbol(Circle())
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.day().month())
                    AxisGridLine()
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 汇总统计 / Summary Stats

    private var summaryStats: some View {
        let diaryPoints = points.compactMap { $0.moodScore }
        let avgMood = diaryPoints.isEmpty ? nil : diaryPoints.reduce(0, +) / Double(diaryPoints.count)
        let energyPoints = points.compactMap { $0.energyScore }
        let avgEnergy = energyPoints.isEmpty ? nil : energyPoints.reduce(0, +) / Double(energyPoints.count)
        let totalStudy = points.reduce(0) { $0 + $1.studyMinutes }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Summary".localized())
                .font(.headline)
            HStack {
                StatBlock(title: "Average Mood".localized(),
                          value: avgMood.map { String(format: "%.1f", $0) } ?? "—")
                StatBlock(title: "Average Energy".localized(),
                          value: avgEnergy.map { String(format: "%.1f", $0) } ?? "—")
                StatBlock(title: "Total Study".localized(),
                          value: "\(Int(totalStudy))m")
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 空状态 / Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .scaledFont(size: 56)
                .foregroundColor(.secondary.opacity(0.6))
            Text("No data in this period".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 辅助视图 / Helper Views

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }
}

private struct StatBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 预览 / Preview

#Preview {
    let container = RepositoryContainer()
    MoodTrendChartView()
        .environment(container)
        .environment(HealthKitManager.shared)
        .onAppear {
            for i in 0..<7 {
                let date = Date().addingTimeInterval(TimeInterval(-i * 86400))
                container.diaryRepo.add(DiaryEntry(
                    date: date,
                    moodScore: Int.random(in: 2...5),
                    energyScore: Int.random(in: 2...5),
                    energyTag: "",
                    content: ""
                ))
            }
        }
}
