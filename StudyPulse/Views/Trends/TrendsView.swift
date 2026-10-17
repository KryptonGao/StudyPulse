//
//  TrendsView.swift
//  StudyPulse
//
//  趋势主页:先看「整体在往哪走」,再看「哪一科要管」,最后才是逐科浏览与时间投入。
//  Trends home: overall direction first, then which subject needs work, then per-subject
//  browsing and time investment. iPad shows a list | detail split.
//

import SwiftUI

struct TrendsView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(HealthKitManager.self) private var hrvManager: HealthKitManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var viewModel: TrendsViewModel
    @State private var showingAddGrade = false
    @State private var path = NavigationPath()

    /// 分数 / 排名 / Score vs ranking.
    @State var trendsShowingMode: TrendsDisplayMode = .score

    init(container: RepositoryContainer) {
        _viewModel = State(initialValue: TrendsViewModel.makeDefault(container: container))
    }

    var body: some View {
        TwoPane(placeholderTitle: "trends.v2.pane.placeholder".localized(), placeholderIcon: "chart.xyaxis.line") {
            content
        }
    }

    private var content: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.section) {
                    PhaseBar()

                    if viewModel.activeSubjects.isEmpty {
                        ContentUnavailableView(
                            "No Grades Yet".localized(),
                            systemImage: "chart.xyaxis.line",
                            description: Text("Add grades to see your trends here.".localized())
                        )
                        .padding(.top, 60)
                    } else {
                        TrendsOverviewCard(viewModel: viewModel, mode: $trendsShowingMode)
                        TrendsAttentionCard(insights: viewModel.attention, viewModel: viewModel)
                        TrendsSubjectList(rows: viewModel.subjectRows, viewModel: viewModel, mode: trendsShowingMode)
                    }

                    TimeInvestmentWeekCard()
                }
                .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
                .padding(.vertical)
                .adaptiveMaxWidth(900)
            }
            .background(Color(.systemGroupedBackground).opacity(DesignToken.Opacity.rootBackground))
            .containerBackground(.clear, for: .navigation)
            .debugModeContainer()
            .debugLayoutBoundsAuto()
            .navigationTitle("Trends".localized())
            .navigationBarTitleDisplayMode(.large)
            .frame(maxWidth: .infinity)
            .navigationDestination(for: String.self) { subjectName in
                SubjectDetailView(subject: subjectName, viewModel: viewModel, displayMode: $trendsShowingMode)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { viewOptionsMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddGrade = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add New Grade".localized())
                }
            }
            .sheet(isPresented: $showingAddGrade) {
                AddGradeView(container: container).adaptiveSheet()
            }
            .onAppear { viewModel.recompute() }
            .onChange(of: container.gradeRepo.filteredGrades) { _, _ in viewModel.recompute() }
            .onChange(of: container.mistakeRepo.filteredMistakeSets) { _, _ in viewModel.recompute() }
            .onChange(of: container.examRepo.filteredExamSets) { _, _ in viewModel.recompute() }
            .onChange(of: container.subjectRepo.subjects) { _, _ in viewModel.recompute() }
            .onChange(of: container.envManager.activePhaseId) { _, _ in viewModel.recompute() }
            .onChange(of: hrvManager.readiness) { _, _ in viewModel.recompute() }
        }
    }

    /// 只留图表样式这类「低频」选项;分数 / 排名与时间范围已在首卡内可见。
    /// Only low-frequency options remain here; score/ranking and range are visible in the hero card.
    private var viewOptionsMenu: some View {
        Menu {
            Picker("Chart Type".localized(), selection: Binding(
                get: { container.envManager.preferences.chartType },
                set: { container.envManager.preferences.chartType = $0 }
            )) {
                ForEach(ChartType.allCases) { type in
                    Label(type.localizedDisplayName, systemImage: type.icon).tag(type)
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("trends.menu.title".localized())
    }
}

#Preview {
    TrendsView(container: RepositoryContainer())
        .environment(RepositoryContainer())
        .environment(HealthKitManager.shared)
}

#Preview("Dark Mode") {
    TrendsView(container: RepositoryContainer())
        .environment(RepositoryContainer())
        .environment(HealthKitManager.shared)
        .preferredColorScheme(.dark)
}
