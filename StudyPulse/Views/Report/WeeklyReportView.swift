//
//  WeeklyReportView.swift
//  StudyPulse
//
//  Displays weekly/monthly learning report with charts and summary.
//

import SwiftUI
import Charts
import SwiftStreamingMarkdown

struct WeeklyReportView: View {
    let reportData: WeeklyReportManager.ReportData
    let summary: String
    let subjects: [Subject]
    /// 可选 LLM 生成的 AI 总结;非空时渲染在 Summary 之上
    let aiSummary: String?

    init(
        reportData: WeeklyReportManager.ReportData,
        summary: String,
        subjects: [Subject],
        aiSummary: String? = nil
    ) {
        self.reportData = reportData
        self.summary = summary
        self.subjects = subjects
        self.aiSummary = aiSummary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            overviewStats
            studyTimeChart
            intensityChart
            subjectChart
            if let aiSummary, !aiSummary.isEmpty { aiSummarySection(aiSummary) }
            summarySection
            footer
        }
        .padding(24)
        .frame(width: ReportRenderer.defaultWidth, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(.blue)
                Text(reportData.period.displayName)
                    .scaledFont(size: 22, weight: .bold)
            }
            Text(periodDescription)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "Report generated".localized(), formattedTimestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var periodDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let s = formatter.string(from: reportData.startDate)
        let e = formatter.string(from: reportData.endDate)
        return "\(s) → \(e)"
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date())
    }

    // MARK: - Overview Stats

    private var overviewStats: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Overview".localized(), system: "square.grid.2x2.fill")
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                statTile(
                    value: formatStudyTime(reportData.totalStudyMinutes),
                    label: "Study Time".localized(),
                    color: .blue
                )
                statTile(
                    value: "\(reportData.sessionCount)",
                    label: "Sessions".localized(),
                    color: .purple
                )
                statTile(
                    value: "\(reportData.gradeCount)",
                    label: "Grades".localized(),
                    color: .green
                )
                statTile(
                    value: percentString(reportData.averageScoreRate),
                    label: "Avg Score".localized(),
                    color: scoreColor(reportData.averageScoreRate, fullScore: 1)
                )
            }
        }
    }

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .scaledFont(size: 20, weight: .bold, design: .rounded)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.10))
        )
    }

    // MARK: - Study Time Chart

    private var studyTimeChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Daily Study Time".localized(), system: "clock.fill")
            if reportData.dailyStudyMinutes.isEmpty {
                emptyHint
            } else {
                Chart {
                    ForEach(Array(reportData.dailyStudyMinutes.enumerated()), id: \.offset) { _, item in
                        BarMark(
                            x: .value("Date", item.date, unit: .day),
                            y: .value("Minutes", item.minutes)
                        )
                        .foregroundStyle(.blue.gradient)
                        .cornerRadius(3)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, reportData.dailyStudyMinutes.count / 7))) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Int.self) {
                                Text("\(minutes)m")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - Intensity Chart

    private var intensityChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Session Intensity".localized(), system: "bolt.fill")
            if reportData.intensityDistribution.allSatisfy({ $0.count == 0 }) {
                emptyHint
            } else {
                Chart {
                    ForEach(Array(reportData.intensityDistribution.enumerated()), id: \.offset) { _, item in
                        if item.count > 0 {
                            BarMark(
                                x: .value("Intensity", item.intensity.displayName),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(intensityColor(item.intensity))
                            .cornerRadius(3)
                            .annotation(position: .top) {
                                Text("\(item.count)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let count = value.as(Int.self) {
                                Text("\(count)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
    }

    // MARK: - Subject Chart

    private var subjectChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Subject Distribution".localized(), system: "chart.pie.fill")
            if reportData.subjectDistribution.isEmpty {
                emptyHint
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(reportData.subjectDistribution.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.subject)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(item.mistakeCount) (\(Int(item.percentage * 100))%)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.tertiarySystemGroupedBackground))
                        )
                    }
                }
            }
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Summary".localized(), system: "text.alignleft")
            Text(summary)
                .font(.caption)
                .foregroundColor(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
    }

    /// AI 生成的总结段(由 LLM 客户端流式生成)。
    /// 用 `MarkdownView` 渲染。背景使用淡蓝色提示"由 AI 生成"。
    private func aiSummarySection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(.teal)
                Text("AI 总结".localized())
                    .font(.headline)
                Spacer()
                Text("Generated by your LLM".localized())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            MarkdownView(text: text.normalisingSingleDollarMath(), config: .previewConfig)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.teal.opacity(0.08))
                )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .center, spacing: 6) {
            Text(QuoteProvider.dailyQuote())
                .font(.footnote)
                .italic()
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Text("Generated by StudyPulse".localized())
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Building Blocks

    private func sectionTitle(_ text: String, system: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system)
                .foregroundColor(.blue)
            Text(text)
                .font(.headline)
        }
    }

    private var emptyHint: some View {
        Text("No data in this period".localized())
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
    }

    // MARK: - Formatting Helpers

    private func formatStudyTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    private func percentString(_ rate: Double) -> String {
        String(format: "%.0f%%", max(0, min(1, rate)) * 100)
    }

    private func intensityColor(_ intensity: StudySession.SessionIntensity) -> Color {
        switch intensity {
        case .peak: return .green
        case .deepFocus: return .blue
        case .steady: return .indigo
        case .light: return .orange
        case .recovery: return .red
        }
    }
}
