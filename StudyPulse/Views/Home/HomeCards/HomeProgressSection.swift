//
//  HomeProgressSection.swift
//  StudyPulse
//
//  「进展」区块:一张卡收进 KPI 三联 + 分段切换(本周专注 / 各科 / 近期成绩)+ 一行学习建议。
//  取代 OverviewHeroCard、WeeklyFocusCard、SubjectSnapshotCard、RecentGradesCard 在主页的平铺。
//  Progress zone: one card combining a three-up KPI row, a segmented switch (weekly focus /
//  subjects / recent grades) and a one-line study insight.
//

import SwiftUI

/// 「进展」区块各子模块的开关(来自 `HomeLayoutPreference`)。
/// Per-module switches for the Progress zone (from `HomeLayoutPreference`).
struct HomeProgressOptions {
    var showsWeeklyFocus = true
    var showsSubjects = true
    var showsRecentGrades = true
    var showsSuggestion = true
}

struct HomeProgressSection: View {
    let viewModel: HomeViewModel
    let options: HomeProgressOptions

    @Environment(RepositoryContainer.self) private var container
    @Environment(\.selectAppTab) private var selectAppTab
    @State private var pane: Pane = .week
    @State private var showingSuggestions = false

    private enum Pane: String, CaseIterable, Identifiable {
        case week, subjects, grades
        var id: String { rawValue }
        var title: String {
            switch self {
            case .week: return "home.v2.progress.week".localized()
            case .subjects: return "home.v2.progress.subjects".localized()
            case .grades: return "Recent Grades".localized()
            }
        }
    }

    private var accent: Color { container.envManager.effectiveAccentColor }

    /// 当前有数据且被启用的面板 / Panes that are enabled and have data.
    private var availablePanes: [Pane] {
        var panes: [Pane] = []
        let weekly = viewModel.weeklyFocus
        if options.showsWeeklyFocus, weekly.totalMinutes + weekly.previousTotalMinutes > 0 { panes.append(.week) }
        if options.showsSubjects, !viewModel.subjectSnapshots.isEmpty { panes.append(.subjects) }
        if options.showsRecentGrades, !viewModel.recentGrades.isEmpty { panes.append(.grades) }
        return panes
    }

    private var hasContent: Bool {
        viewModel.overallAverageRate != nil
            || viewModel.weeklyFocus.hasData
            || viewModel.srsOverview.dueCount > 0
            || !availablePanes.isEmpty
    }

    private var insight: StudySuggestion? {
        options.showsSuggestion ? viewModel.generateSuggestions(limit: 1).first : nil
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HomeZoneHeader(title: "home.v2.zone.progress".localized()) {
                    Button("home.v2.progress.trends".localized()) { selectAppTab(.trends) }
                }
                card
            }
            .sheet(isPresented: $showingSuggestions) { suggestionsSheet }
            .debugLayoutBoundsAuto()
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            kpiRow

            let panes = availablePanes
            if !panes.isEmpty {
                if panes.count > 1 {
                    Picker("home.v2.zone.progress".localized(), selection: activePane(in: panes)) {
                        ForEach(panes) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                paneContent(activePane(in: panes).wrappedValue)
            }

            if let insight { insightRow(insight) }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
    }

    /// 选中面板可能因数据变化失效,回退到第一个可用面板。
    /// The selected pane may become unavailable as data changes; fall back to the first available one.
    private func activePane(in panes: [Pane]) -> Binding<Pane> {
        Binding(
            get: { panes.contains(pane) ? pane : (panes.first ?? .week) },
            set: { pane = $0 }
        )
    }

    @ViewBuilder
    private func paneContent(_ pane: Pane) -> some View {
        switch pane {
        case .week:
            WeeklyFocusContent(summary: viewModel.weeklyFocus, showsSummary: false)
        case .subjects:
            SubjectSnapshotList(snapshots: viewModel.subjectSnapshots)
        case .grades:
            VStack(spacing: DesignToken.Spacing.small) {
                ForEach(viewModel.recentGrades) { CompactGradeRow(grade: $0) }
            }
        }
    }

    // MARK: - KPIs

    private var kpiRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignToken.Spacing.small) { kpis }
            VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) { kpis }
        }
    }

    @ViewBuilder
    private var kpis: some View {
        KPITile(title: "home.v2.kpi.average".localized()) {
            if let rate = viewModel.overallAverageRate {
                KPIValue(text: String(format: "%.0f", rate), unit: "%")
            } else {
                KPIValue(text: "—", unit: nil)
            }
        } delta: {
            HomeDeltaBadge(delta: HomeInsightsEngine.trendDelta(viewModel.averageRateTrend), format: "%.1f")
        }
        KPITile(title: "home.v2.kpi.focus".localized()) {
            KPIValue(text: focusText, unit: nil)
        } delta: {
            let weekly = viewModel.weeklyFocus
            if weekly.previousTotalMinutes > 0 || weekly.totalMinutes > 0 {
                HomeDeltaBadge(delta: weekly.deltaMinutes / 60, format: "%.1fh")
            }
        }
        KPITile(title: "home.v2.kpi.due".localized()) {
            KPIValue(text: "\(viewModel.srsOverview.dueCount)", unit: nil)
        } delta: {
            EmptyView()
        }
    }

    private var focusText: String {
        let minutes = Int(viewModel.weeklyFocus.totalMinutes.rounded())
        return minutes >= 60
            ? String(format: "home.v2.kpi.hm".localized(), minutes / 60, minutes % 60)
            : String(format: "home.v2.kpi.m".localized(), minutes)
    }

    // MARK: - Insight

    private func insightRow(_ suggestion: StudySuggestion) -> some View {
        Button { showingSuggestions = true } label: {
            HStack(alignment: .top, spacing: 10) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(suggestion.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.purple.opacity(0.12), accent.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var badge: some View {
        if container.envManager.llmConfig.isConfigured {
            Label("AI".localized(), systemImage: "sparkles")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    LinearGradient(colors: [.purple, accent], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        } else {
            Image(systemName: "lightbulb.fill")
                .font(.footnote)
                .foregroundStyle(.yellow)
        }
    }

    /// 完整建议(含 LLM 增强)沿用 `StudySuggestionsCard`,放进 sheet。
    /// The full suggestions (with LLM enhancement) reuse `StudySuggestionsCard` inside a sheet.
    private var suggestionsSheet: some View {
        NavigationStack {
            ScrollView {
                StudySuggestionsCard(viewModel: viewModel)
                    .padding(DesignToken.Spacing.large)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Study Suggestions".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized()) { showingSuggestions = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - KPI building blocks

private struct KPITile<Value: View, Delta: View>: View {
    let title: String
    @ViewBuilder var value: () -> Value
    @ViewBuilder var delta: () -> Delta

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                value()
                delta()
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct KPIValue: View {
    let text: String
    let unit: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(text)
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let unit {
                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
