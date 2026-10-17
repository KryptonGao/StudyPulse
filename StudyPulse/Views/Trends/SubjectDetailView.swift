//
//  SubjectDetailView.swift
//  StudyPulse
//
//  科目详情:四个关键数字 → 走势 → 掌握度雷达与成绩记录 → AI 解读。
//  Subject detail: four key numbers → trend → mastery radar & grade records → AI reading.
//

import SwiftUI
import Charts

struct SubjectDetailView: View {
    let subject: String
    let viewModel: TrendsViewModel
    @Binding var displayMode: TrendsDisplayMode

    @Environment(RepositoryContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.isInDetailPane) private var isInDetailPane
    @State private var selectedRange: TimeRange = .all
    @State private var showingAddGrade = false

    enum TimeRange: String, CaseIterable, Identifiable {
        case all = "All"
        case last3Months = "3 Months"
        case last6Months = "6 Months"
        case lastYear = "1 Year"
        var id: String { rawValue }
    }

    // MARK: Derived

    private var allGrades: [Grade] {
        container.gradeRepo.filteredGrades.filter { $0.subject == subject }.sorted { $0.date < $1.date }
    }

    private var filteredGrades: [Grade] {
        let months: Int?
        switch selectedRange {
        case .all: months = nil
        case .last3Months: months = 3
        case .last6Months: months = 6
        case .lastYear: months = 12
        }
        guard let months, let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()) else { return allGrades }
        return allGrades.filter { $0.date >= cutoff }
    }

    private var fullScore: Double { container.fullScore(for: subject) }
    private var accent: Color { SubjectPalette.color(for: subject) }
    private var target: Double? {
        container.phaseRepo.activePhase?.goals.first { $0.subject == subject && $0.targetScore > 0 }?.targetScore
    }
    private var snapshot: SubjectRadarSnapshot? { viewModel.radarSnapshots.first { $0.subject == subject } }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                if isInDetailPane {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 4).fill(accent).frame(width: 12, height: 12)
                        Text(container.displayName(for: subject))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    }
                    .accessibilityAddTraits(.isHeader)
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignToken.Spacing.tiny)

                statTiles
                trendCard
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: DesignToken.Spacing.medium) {
                        radarCard.frame(maxWidth: .infinity)
                        recordsCard.frame(maxWidth: .infinity)
                    }
                    .frame(minWidth: 600)
                    VStack(spacing: DesignToken.Spacing.medium) {
                        radarCard
                        recordsCard
                    }
                }
                aiCard
            }
            .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground).opacity(DesignToken.Opacity.rootBackground))
        .navigationTitle(container.displayName(for: subject))
        .navigationBarTitleDisplayMode(.large)
        .adaptiveMaxWidth(960)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("trends.menu.displayMode".localized(), selection: $displayMode) {
                        ForEach(TrendsDisplayMode.allCases) { Label($0.localizedName, systemImage: $0.icon).tag($0) }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddGrade = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add New Grade".localized())
            }
        }
        .sheet(isPresented: $showingAddGrade) {
            AddGradeView(container: container).adaptiveSheet()
        }
    }

    private var subtitle: String {
        var text = String(format: "trends.v2.detail.sub".localized(), allGrades.count, Int(fullScore))
        if let target { text += " · " + String(format: "trends.v2.target".localized(), target) }
        return text
    }

    // MARK: Stat tiles

    private var statTiles: some View {
        let scores = filteredGrades.map(\.score)
        let avg = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        let ranks = filteredGrades.compactMap(\.ranking).filter { $0 > 0 }
        return HStack(spacing: DesignToken.Spacing.small) {
            StatTile(value: avg.map { String(format: "%.1f", $0) } ?? "—", label: "Average Score".localized())
            StatTile(value: scores.max().map { String(format: "%.0f", $0) } ?? "—", label: "trends.v2.detail.best".localized())
            StatTile(
                value: scores.last.map { String(format: "%.0f", $0) } ?? "—",
                label: "Latest".localized(),
                tint: scores.last.map { scoreColor($0, fullScore: fullScore) } ?? .primary
            )
            StatTile(value: ranks.last.map { "#\($0)" } ?? "—", label: "Ranking".localized())
        }
    }

    // MARK: Trend

    private var trendCard: some View {
        PageCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                HStack {
                    Text(displayMode == .score ? "trends.v2.detail.scoreTrend".localized() : "trends.v2.detail.rankTrend".localized())
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Spacer()
                }
                Picker("Time Range".localized(), selection: $selectedRange) {
                    ForEach(TimeRange.allCases) { Text($0.rawValue.localized()).tag($0) }
                }
                .pickerStyle(.segmented)

                if filteredGrades.isEmpty {
                    ContentUnavailableView("No Data".localized(), systemImage: "chart.line.xaxis.dashed")
                        .frame(height: 200)
                } else if displayMode == .score {
                    TrendChartView(
                        grades: filteredGrades,
                        fullScore: fullScore,
                        chartType: container.envManager.preferences.chartType,
                        tintColor: container.envManager.effectiveAccentColor
                    )
                    .frame(height: sizeClass == .regular ? 320 : 240)
                } else {
                    rankChart.frame(height: sizeClass == .regular ? 320 : 240)
                }
            }
        }
    }

    private var rankChart: some View {
        Chart(filteredGrades.filter { ($0.ranking ?? 0) > 0 }) { grade in
            LineMark(x: .value("Date", grade.date), y: .value("Rank", grade.ranking ?? 0))
                .foregroundStyle(.indigo)
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", grade.date), y: .value("Rank", grade.ranking ?? 0))
                .foregroundStyle(scoreColor(grade.score, fullScore: fullScore))
        }
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
    }

    // MARK: Radar

    private var radarCard: some View {
        PageCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                Text("Subject Mastery Radar".localized())
                    .font(.system(.headline, design: .rounded, weight: .bold))
                if let snapshot {
                    Text(String(format: "30-day subject data: %d grades · %d mistakes · %d min study".localized(),
                                snapshot.gradeCount, snapshot.mistakeCount, snapshot.studyMinutes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    BodyRadarChart(
                        normalizedValues: snapshot.values,
                        axisLabels: [
                            "Knowledge Coverage".localized(), "Review Frequency".localized(), "Mistake Rate".localized(),
                            "Average Score".localized(), "Study Time".localized(), "HRV Performance".localized()
                        ]
                    )
                    .frame(height: 230)
                } else {
                    Text("No data available".localized()).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Records

    private var recordsCard: some View {
        PageCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                Text("History".localized())
                    .font(.system(.headline, design: .rounded, weight: .bold))
                if filteredGrades.isEmpty {
                    Text("No grades available".localized()).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    let rows = Array(filteredGrades.reversed().prefix(8))
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, grade in
                        if index > 0 { Divider() }
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(grade.examName.isEmpty ? "Unnamed Exam".localized() : grade.examName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(grade.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if displayMode == .score {
                                Text(String(format: "%.1f", grade.score))
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .foregroundStyle(scoreColor(grade.score, fullScore: fullScore))
                            } else {
                                Text((grade.ranking ?? 0) > 0 ? "#\(grade.ranking ?? 0)" : "N/A".localized())
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .foregroundStyle(.indigo)
                            }
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button(role: .destructive) {
                                container.deleteGrade(grade)
                            } label: { Label("Delete".localized(), systemImage: "trash") }
                        }
                    }
                }
            }
        }
    }

    // MARK: AI

    @ViewBuilder
    private var aiCard: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            Button {
                viewModel.requestRadarAIAnalysis(for: subject)
            } label: {
                Label("AI Interpretation".localized(), systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(viewModel.isRadarAILoading || snapshot == nil)

            if viewModel.isRadarAILoading {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let error = viewModel.radarAIError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            if let analysis = viewModel.radarAIAnalysis, !analysis.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(.purple)
                    Text(analysis).font(.subheadline)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [.purple.opacity(0.12), .blue.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: DesignToken.CornerRadius.large)
                )
            }
        }
    }
}


/// 双栏右栏里的科目详情:自带一份显示模式状态(右栏不与左栏共享绑定)。
/// Subject detail hosted in the right pane; owns its display-mode state.
struct SubjectDetailPaneHost: View {
    let subject: String
    let viewModel: TrendsViewModel
    @State var mode: TrendsDisplayMode

    var body: some View {
        SubjectDetailView(subject: subject, viewModel: viewModel, displayMode: $mode)
    }
}
