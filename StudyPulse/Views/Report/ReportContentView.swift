//
//  ReportContentView.swift
//  StudyPulse
//
//  Self-contained SwiftUI view that draws the "Learning Report".
//  Receives an immutable `StudyReport` snapshot, so it has no
//  dependencies on `environment-injected observable` and renders cleanly through
//  `ImageRenderer`.
//

import SwiftUI
import Charts

struct ReportContentView: View {
    let report: StudyReport

    private var pageWidth: CGFloat { ReportRenderer.defaultWidth }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            overviewGrid
            gradesSection
            mistakesSection
            examsSection
            if report.hasHRVSection { hrvSection }
            footer
        }
        .padding(24)
        .frame(width: pageWidth, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(.blue)
                Text("StudyPulse Learning Report".localized())
                    .scaledFont(size: 22, weight: .bold)
            }
            HStack(spacing: 6) {
                if !report.profile.username.isEmpty {
                    Text(report.profile.username)
                        .font(.subheadline.weight(.semibold))
                }
                if !report.profile.schoolName.isEmpty {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(report.profile.schoolName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if !report.profile.grade.isEmpty {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(report.profile.grade)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
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
        let s = formatter.string(from: report.startDate)
        let e = formatter.string(from: report.endDate)
        return "\(s) → \(e)"
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: report.generatedAt)
    }

    // MARK: - Overview

    private var overviewGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Overview".localized(), system: "square.grid.2x2.fill")
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                statTile(
                    value: "\(report.periodGrades.count)",
                    label: "Grades".localized(),
                    color: .blue
                )
                statTile(
                    value: percentString(report.averageScoreRate),
                    label: "Avg Score".localized(),
                    color: scoreColor(report.averageScoreRate, fullScore: 1)
                )
                statTile(
                    value: "\(report.periodMistakes.count)",
                    label: "Mistakes".localized(),
                    color: .orange
                )
                statTile(
                    value: "\(report.upcomingExamCount)",
                    label: "Upcoming".localized(),
                    color: .purple
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

    // MARK: - Grades

    @ViewBuilder
    private var gradesSection: some View {
        if !report.subjectAverages.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Grades".localized(), system: "chart.bar.fill")
                subjectAveragesChart
                if !report.topGrades.isEmpty {
                    Text("Top Grades".localized())
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    VStack(spacing: 6) {
                        ForEach(report.topGrades) { grade in
                            topGradeRow(grade)
                        }
                    }
                }
            }
        } else {
            sectionTitle("Grades".localized(), system: "chart.bar.fill")
            emptyHint
        }
    }

    private var subjectAveragesChart: some View {
        let data = report.subjectAverages
        return Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                BarMark(
                    x: .value("Avg", item.avg * 100),
                    y: .value("Subject", report.displayName(for: item.subject))
                )
                .foregroundStyle(scoreColor(item.avg, fullScore: 1))
                .cornerRadius(3)
                .annotation(position: .trailing) {
                    Text(percentString(item.avg))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
        .chartXScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))%")
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: max(120, CGFloat(data.count) * 28 + 60))
    }

    private func topGradeRow(_ grade: Grade) -> some View {
        let subjectFull = report.fullScore(for: grade.subject)
        let rate = grade.scoreRate(subjectFullScore: subjectFull)
        return HStack(spacing: 10) {
            Circle()
                .fill(scoreColor(rate, fullScore: 1))
                .frame(width: 8, height: 8)
            Text(report.displayName(for: grade.subject))
                .font(.caption.weight(.semibold))
                .frame(width: 80, alignment: .leading)
            Text(grade.examName.isEmpty ? "—" : grade.examName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            Text("\(formatScore(grade.score))/\(formatScore(subjectFull))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundColor(.primary)
            Text(percentString(rate))
                .font(.caption2.weight(.semibold))
                .foregroundColor(scoreColor(rate, fullScore: 1))
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    // MARK: - Mistakes

    @ViewBuilder
    private var mistakesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Mistakes".localized(), system: "pencil.and.list.bullet")
            if report.mistakeBySubject.isEmpty {
                emptyHint
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(report.mistakeBySubject.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(report.displayName(for: item.subject))
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(item.count)")
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
                    if report.dueReviewCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "repeat.circle.fill")
                                .foregroundColor(.pink)
                            Text("\(report.dueReviewCount) " + "due for review".localized())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    // MARK: - Exams

    @ViewBuilder
    private var examsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Exams".localized(), system: "calendar.circle.fill")
            if report.upcomingExams.isEmpty {
                emptyHint
            } else {
                VStack(spacing: 6) {
                    ForEach(report.upcomingExams.prefix(8), id: \.id) { exam in
                        examRow(exam)
                    }
                }
            }
        }
    }

    private func examRow(_ exam: Exam) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.name)
                    .font(.caption.weight(.semibold))
                Text(report.displayName(for: exam.subject))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(exam.examDate, format: .dateTime.month(.abbreviated).day())
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
            Text("\(exam.masteryDegree)%")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundColor(masteryColor(exam.masteryDegree))
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    // MARK: - HRV

    private var hrvSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Recovery Radar".localized(), system: "heart.text.square.fill")
            if let hrv = report.hrv, let body = report.bodyStatus {
                let radar = BodyRadarValues.compute(
                    hrv: hrv,
                    body: body,
                    baselines: report.baselines ?? .empty,
                    age: report.profile.age,
                    mistakes: report.mistakeSets
                )
                BodyRadarChart(values: radar)
                    .frame(height: 220)
                hrvSummaryRow(hrv, body: body)
            } else {
                emptyHint
            }
        }
    }

    private func hrvSummaryRow(_ hrv: HRVReadiness, body: BodyStatus) -> some View {
        HStack(spacing: 10) {
            badge(text: hrvBadgeText(hrv.category), color: hrvBadgeColor(hrv.category))
            if let hr = body.restingHeartRate {
                Text("\(Int(hr.rounded())) bpm")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            if let sleep = body.restorativeSleepHours {
                Text(String(format: "%.1fh sleep".localized(), sleep))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
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

    // MARK: - Building blocks

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

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundColor(color)
    }

    // MARK: - Formatting helpers

    private func percentString(_ rate: Double) -> String {
        String(format: "%.0f%%", max(0, min(1, rate)) * 100)
    }

    private func formatScore(_ value: Double) -> String {
        if value.rounded() == value { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }

    private func masteryColor(_ value: Int) -> Color {
        switch value {
        case ..<40: return .red
        case ..<70: return .orange
        case ..<85: return .blue
        default: return .green
        }
    }

    private func hrvBadgeText(_ category: HRVReadiness.Category) -> String {
        switch category {
        case .excellent: return "Excellent".localized()
        case .normal: return "Normal".localized()
        case .low: return "Low".localized()
        case .loading: return "Loading...".localized()
        case .insufficient: return "Collecting".localized()
        case .noAuthorization: return "-"
        case .queryFailed: return "Error".localized()
        }
    }

    private func hrvBadgeColor(_ category: HRVReadiness.Category) -> Color {
        switch category {
        case .excellent: return .green
        case .normal: return .blue
        case .low: return .orange
        case .loading, .insufficient, .noAuthorization, .queryFailed: return .secondary
        }
    }
}

private struct ReportPreview: View {
    var body: some View {
        var profile = UserProfile()
        profile.username = "陈同学"
        profile.schoolName = "实验中学"
        profile.grade = "高二"
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let report = StudyReport(
            generatedAt: Date(),
            startDate: startDate,
            endDate: Date(),
            profile: profile,
            grades: (0..<12).compactMap { i in
                guard let date = Calendar.current.date(byAdding: .day, value: -i * 2, to: Date()) else { return nil }
                return Grade(
                    subject: ["Math", "English", "Physics"][i % 3],
                    score: 70 + Double.random(in: -10...25),
                    date: date,
                    examName: "Mock \(i)"
                )
            },
            mistakeSets: (0..<6).map { _ in
                MistakeNote(
                    title: "Sample", subject: "Math",
                    originalQuestion: "", source: "", date: Date(),
                    errorReason: "", wrongSolution: "", correctSolution: ""
                )
            },
            examSets: [],
            comprehensiveExamSets: [],
            subjects: [
                Subject(name: "Math", displayName: "数学", fullScore: 100),
                Subject(name: "English", displayName: "英语", fullScore: 100),
                Subject(name: "Physics", displayName: "物理", fullScore: 100)
            ],
            hrvEnabled: false,
            hrvOnboardingCompleted: false,
            hrv: nil,
            bodyStatus: nil,
            baselines: nil
        )
        return ScrollView { ReportContentView(report: report) }
    }
}

#Preview {
    ReportPreview()
}
