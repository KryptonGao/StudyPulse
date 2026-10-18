//
//  AIModeDataSections.swift
//  StudyPulse
//
//  Bodies of the six AI Mode data pages. Every figure comes from the same
//  `AIStudyDataSnapshot` that is sent to the model as context.
//

import SwiftUI
import Charts

// MARK: - Grades

struct AIGradesSection: View {
    var data: AIModeDataViewModel
    @Environment(\.aiTheme) private var theme

    var body: some View {
        @Bindable var vm = data
        let grades = data.currentGrades
        VStack(alignment: .leading, spacing: 18) {
            Picker("aiMode.data.period".localized(), selection: $vm.gradeRange) {
                Text("aiMode.scope.last30".localized()).tag(AIGradeRange.days30)
                Text("aiMode.scope.last90".localized()).tag(AIGradeRange.days90)
                Text("aiMode.scope.phase".localized()).tag(AIGradeRange.phase)
            }
            .pickerStyle(.segmented)

            if grades.isEmpty {
                AIEmptyNote(text: "aiMode.data.empty.grades".localized())
            } else {
                summary(grades)
                if grades.hasEnoughForTrend, grades.trend.points.count >= 2 {
                    chart(grades.trend.points)
                } else {
                    AIEmptyNote(text: "aiMode.data.grades.fewRecords".localized())
                }
                VStack(spacing: 0) {
                    ForEach(grades.rows) { row in
                        AIDataRow(
                            title: row.subject,
                            subtitle: String(format: "aiMode.data.grades.latest".localized(),
                                             row.latestScore, row.fullScore, row.latestExamName),
                            trailing: String(format: "%.1f", row.averageScore) + (row.delta == 0 ? "" : "  " + AIFormat.signed(row.delta)),
                            route: .subject(row.subject)
                        )
                    }
                }
            }
        }
    }

    private func summary(_ grades: AIGradesSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AIMetricLabel(
                value: grades.trend.average.map(AIFormat.percent) ?? "—",
                caption: "aiMode.data.grades.average".localized()
            )
            if let delta = grades.trend.delta {
                AIMetricLabel(
                    value: AIFormat.signed(delta) + "%",
                    caption: "aiMode.data.grades.delta".localized()
                )
            }
            AIMetricLabel(
                value: "\(grades.gradeCount)",
                caption: "aiMode.data.grades.count".localized()
            )
        }
    }

    private func chart(_ points: [OverallTrendPoint]) -> some View {
        Chart(points) { point in
            AreaMark(x: .value("date", point.date), y: .value("rate", point.value))
                .foregroundStyle(LinearGradient(
                    colors: [theme.accent.opacity(0.25), theme.accent.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.monotone)
            LineMark(x: .value("date", point.date), y: .value("rate", point.value))
                .foregroundStyle(theme.accent)
                .interpolationMethod(.monotone)
            PointMark(x: .value("date", point.date), y: .value("rate", point.value))
                .foregroundStyle(theme.accent)
                .symbolSize(24)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 170)
        .accessibilityLabel("aiMode.data.grades.chart".localized())
    }
}

// MARK: - Mistakes

struct AIMistakesSection: View {
    let snapshot: AIMistakesSnapshot
    @Environment(\.aiTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if snapshot.isEmpty {
                AIEmptyNote(text: "aiMode.data.empty.mistakes".localized())
            } else {
                HStack(alignment: .top, spacing: 12) {
                    AIMetricLabel(value: "\(snapshot.total)", caption: "aiMode.data.mistakes.total".localized())
                    AIMetricLabel(value: "\(snapshot.masteredCount)", caption: "aiMode.data.mistakes.mastered".localized())
                    AIMetricLabel(value: "\(snapshot.review.total)", caption: "aiMode.data.mistakes.due".localized())
                }
                if snapshot.review.overdue > 0 {
                    AIEmptyNote(text: String(format: "aiMode.data.mistakes.overdue".localized(), snapshot.review.overdue))
                }
                if !snapshot.priority.isEmpty {
                    sectionTitle("aiMode.data.mistakes.priority".localized())
                    VStack(spacing: 0) {
                        ForEach(snapshot.priority) { row in
                            AIDataRow(
                                title: row.title.isEmpty ? row.subject : row.title,
                                subtitle: reviewText(row),
                                trailing: String(format: "%.0f%%", row.mastery * 100),
                                route: .mistake(row.id)
                            )
                        }
                    }
                }
                if !snapshot.patterns.isEmpty {
                    sectionTitle("aiMode.data.mistakes.patterns".localized())
                    VStack(spacing: 0) {
                        ForEach(snapshot.patterns) { pattern in
                            AIDataRow(
                                title: pattern.pattern.titleKey.localized(),
                                subtitle: pattern.subjects.joined(separator: " · "),
                                trailing: "×\(pattern.count)"
                            )
                        }
                    }
                }
                if !snapshot.subjects.isEmpty {
                    sectionTitle("aiMode.data.mistakes.subjects".localized())
                    VStack(spacing: 0) {
                        ForEach(snapshot.subjects) { subject in
                            AIDataRow(
                                title: subject.subject,
                                subtitle: String(format: "aiMode.data.mistakes.subjectLine".localized(), subject.count, subject.due),
                                trailing: String(format: "%.0f%%", subject.mastery * 100)
                            )
                        }
                    }
                }
            }
        }
    }

    private func reviewText(_ row: AIMistakeRow) -> String {
        guard let days = row.daysUntilReview else { return row.subject }
        if days <= 0 { return row.subject + " · " + "aiMode.data.mistakes.dueNow".localized() }
        return row.subject + " · " + String(format: "aiMode.data.mistakes.dueIn".localized(), days)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(theme.ink)
    }
}

// MARK: - Exams

struct AIExamsSection: View {
    let snapshot: AIExamsSnapshot
    @Environment(\.aiTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if snapshot.upcoming.isEmpty {
                AIEmptyNote(text: "aiMode.data.empty.exams".localized())
            } else {
                VStack(spacing: 0) {
                    ForEach(snapshot.upcoming) { exam in
                        AIDataRow(
                            title: exam.name,
                            subtitle: subtitle(exam),
                            trailing: exam.daysUntil <= 0
                                ? "aiMode.data.exams.today".localized()
                                : String(format: "aiMode.data.exams.days".localized(), exam.daysUntil),
                            route: exam.isComprehensive ? .comprehensiveExam(exam.id) : .exam(exam.id)
                        )
                    }
                }
            }
            if let plan = snapshot.plan {
                AIDataCard {
                    Text("aiMode.data.exams.plan".localized())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.ink)
                    Text(plan.examName + " · " + plan.subject)
                        .font(.footnote)
                        .foregroundStyle(theme.muted)
                    Text(plan.summary)
                        .font(.footnote)
                        .foregroundStyle(theme.ink)
                }
            }
        }
    }

    private func subtitle(_ exam: AIExamRow) -> String {
        var parts = [AIFormat.shortDate(exam.date)]
        parts.append(String(format: "aiMode.data.exams.mastery".localized(), exam.mastery))
        if let done = exam.checklistDone, let total = exam.checklistTotal, total > 0 {
            parts.append(String(format: "aiMode.data.exams.checklist".localized(), done, total))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Time

struct AITimeSection: View {
    let snapshot: AITimeSnapshot
    @Environment(\.aiTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if snapshot.isEmpty {
                AIEmptyNote(text: "aiMode.data.empty.time".localized())
            } else {
                HStack(alignment: .top, spacing: 12) {
                    AIMetricLabel(value: AIFormat.hours(snapshot.weekSeconds), caption: "aiMode.data.time.week".localized())
                    AIMetricLabel(value: AIFormat.hours(snapshot.previousWeekSeconds), caption: "aiMode.data.time.lastWeek".localized())
                    AIMetricLabel(value: "\(snapshot.streak)", caption: "aiMode.data.time.streak".localized())
                }
                if !snapshot.days.isEmpty {
                    Chart(snapshot.days) { day in
                        BarMark(x: .value("day", day.date, unit: .day), y: .value("min", day.minutes))
                            .foregroundStyle(theme.accent.opacity(0.85))
                            .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }
                    }
                    .frame(height: 150)
                    .accessibilityLabel("aiMode.data.time.chart".localized())
                }
                if !snapshot.projects.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(snapshot.projects) { project in
                            AIDataRow(
                                title: project.name,
                                trailing: AIFormat.hours(project.seconds),
                                systemImage: "clock",
                                route: .timeInvestment
                            )
                        }
                    }
                }
                if snapshot.unassignedCount > 0 {
                    AIEmptyNote(text: String(format: "aiMode.data.time.unassigned".localized(), snapshot.unassignedCount))
                }
            }
        }
    }
}

// MARK: - Health

struct AIHealthSection: View {
    let snapshot: AIHealthSnapshot
    @Environment(\.aiTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch snapshot.state {
            case .available:
                grid
            case .disabled:
                notice("aiMode.data.health.disabled".localized())
            case .unauthorized:
                notice("aiMode.data.health.unauthorized".localized())
            case .loading:
                notice("aiMode.data.health.loading".localized())
            case .insufficient:
                notice("aiMode.data.health.insufficient".localized())
            }
        }
    }

    private func notice(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AIEmptyNote(text: text)
            if snapshot.state == .disabled || snapshot.state == .unauthorized {
                NavigationLink(value: AIModeRoute.healthSettings) {
                    Label("aiMode.data.health.openSettings".localized(), systemImage: "heart.text.square")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }

    private var grid: some View {
        let cells: [(String, String)] = [
            ("aiMode.data.health.recovery".localized(), snapshot.recoveryScore.map { "\($0)" } ?? "—"),
            ("aiMode.data.health.sleep".localized(), snapshot.restorativeSleepHours.map { String(format: "%.1f h", $0) } ?? "—"),
            ("aiMode.data.health.restingHR".localized(), snapshot.restingHeartRate.map { String(format: "%.0f", $0) } ?? "—"),
            ("aiMode.data.health.exercise".localized(), snapshot.exerciseMinutes.map { String(format: "%.0f min", $0) } ?? "—"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            ForEach(cells.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    Text(cells[index].0).font(.caption).foregroundStyle(theme.muted)
                    Text(cells[index].1)
                        .scaledFont(size: 26, weight: .semibold, design: theme.titleDesign)
                        .foregroundStyle(theme.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.soft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Diary

struct AIDiarySection: View {
    let snapshot: AIDiarySnapshot
    @Environment(\.aiTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let latest = snapshot.latest {
                HStack(alignment: .top, spacing: 12) {
                    AIMetricLabel(value: "\(snapshot.streak)", caption: "aiMode.data.diary.streak".localized())
                    AIMetricLabel(
                        value: snapshot.averageMood.map { String(format: "%.1f", $0) } ?? "—",
                        caption: "aiMode.data.diary.averageMood".localized()
                    )
                    AIMetricLabel(value: "\(snapshot.entryCount30)", caption: "aiMode.data.diary.entries".localized())
                }
                if snapshot.moodSeries.count >= 2 {
                    Chart(snapshot.moodSeries) { point in
                        LineMark(x: .value("date", point.date), y: .value("mood", point.value))
                            .foregroundStyle(theme.accent)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("date", point.date), y: .value("mood", point.value))
                            .foregroundStyle(theme.accent)
                            .symbolSize(20)
                    }
                    .chartYScale(domain: 1...5)
                    .frame(height: 120)
                    .accessibilityLabel("aiMode.data.diary.chart".localized())
                }
                NavigationLink(value: AIModeRoute.diary) {
                    AIDataCard {
                        Text(AIFormat.shortDate(latest.date) + " · " + latest.energyTag)
                            .font(.caption)
                            .foregroundStyle(theme.muted)
                        if !latest.excerpt.isEmpty {
                            Text(latest.excerpt)
                                .font(.subheadline)
                                .foregroundStyle(theme.ink)
                                .lineLimit(5)
                                .multilineTextAlignment(.leading)
                        }
                        Text(String(format: "aiMode.data.diary.moodEnergy".localized(), latest.moodScore, latest.energyScore))
                            .font(.footnote)
                            .foregroundStyle(theme.muted)
                    }
                }
                .buttonStyle(.plain)
            } else {
                AIEmptyNote(text: "aiMode.data.empty.diary".localized())
            }
        }
    }
}
