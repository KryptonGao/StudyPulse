//
//  TrendsView.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/3/21.
//
//  趋势主页：90 天学习热力图 + 需关注科目横滚卡 + 科目分卡网格 + 添加/切换模式
//  Trends home: 90-day learning heatmap + subjects-needing-attention scroller
//  + subject score card grid + add / mode switch.
//

import SwiftUI
import Charts

/// 趋势主页
/// Trends home view.
struct TrendsView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(HealthKitManager.self) private var hrvManager: HealthKitManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var viewModel: TrendsViewModel
    @State private var showingAddGrade = false

    /// 卡片显示模式：score / ranking
    /// Card display mode: score / ranking.
    @State var trendsShowingMode: TrendsDisplayMode = .score
    @State private var selectedRadarSubject: String?

    init(container: RepositoryContainer) {
        _viewModel = State(initialValue: TrendsViewModel.makeDefault(container: container))
    }

    // 派生数据缓存(已迁移到 TrendsViewModel)
    // Derived data cache — has been moved to TrendsViewModel.

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignToken.Spacing.cardSpacing) {
                    // 90 天学习热力图（顶部全宽；通过 toolbar Menu 开关控制）
                    // 90-day learning heatmap (top, full-width; toolbar Menu toggles it on/off).
                    if container.envManager.preferences.learningHeatmapOnTrends {
                        LearningHeatmapView()
                    }

                    TimeInvestmentSummaryCard()

                    if viewModel.activeSubjects.isEmpty {
                        // 空状态
                        // Empty state — no grades yet.
                        ContentUnavailableView(
                            "No Grades Yet".localized(),
                            systemImage: "chart.xyaxis.line",
                            description: Text("Add grades to see your trends here.".localized())
                        )
                        .padding(.top, 100)
                    } else {
                        if container.envManager.preferences.subjectMasteryRadarOnTrends {
                            subjectMasteryRadar
                        }

                        if !viewModel.subjectsNeedingAttention.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Subjects Needing Attention".localized())
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(viewModel.subjectsNeedingAttention, id: \.self) { subjectName in
                                            NavigationLink(value: subjectName) {
                                                AttentionSubjectCard(subjectName: subjectName, grades: viewModel.gradeHistory(for: subjectName))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        LazyVGrid(columns: AdaptiveGridColumns().columns, spacing: 20) {
                            ForEach(viewModel.activeSubjects, id: \.self) { subjectName in
                                NavigationLink(value: subjectName) {
                                    SubjectScoreCard(
                                        subject: subjectName,
                                        latestGrade: viewModel.latestGrade(for: subjectName),
                                        history: viewModel.gradeHistory(for: subjectName),
                                        displayMode: trendsShowingMode
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, DesignToken.Spacing.mainHorizontal(for: sizeClass))
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground).opacity(DesignToken.Opacity.rootBackground))
            .containerBackground(.clear, for: .navigation)
            .debugModeContainer()
            .debugLayoutBoundsAuto()
            .navigationTitle("Trends".localized())
            .navigationBarTitleDisplayMode(.large)
            // iPad 上撑满 detail 区宽度
            .frame(maxWidth: .infinity)

            //
            .navigationDestination(for: String.self) { subjectName in
                SubjectDetailView(
                    subject: subjectName,
                    displayMode: $trendsShowingMode
                )
            }
            .toolbar {
                // 视图选项:显示模式 / 图表类型 / 热力图,全部就地切换(无需再进设置)
                // View options: display mode / chart type / heatmap, all switchable in place.
                ToolbarItem(placement: .navigationBarTrailing) {
                    viewOptionsMenu
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddGrade = true }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add New Grade".localized())
                }
                ToolbarItem(placement: .principal) {
                    PhaseSelectorView()
                }
            }
            .sheet(isPresented: $showingAddGrade) {
                AddGradeView(container: container)
                    .adaptiveSheet()
            }
            // 派生数据重算:仅在 grades/subjects 变化时触发
            .onAppear { viewModel.recompute() }
            .onChange(of: container.gradeRepo.filteredGrades) { _, _ in viewModel.recompute() }
            .onChange(of: container.mistakeRepo.filteredMistakeSets) { _, _ in viewModel.recompute() }
            .onChange(of: container.subjectRepo.subjects) { _, _ in viewModel.recompute() }
        }
    }

    /// 工具栏「视图选项」菜单:用 Picker 提供选中态与完整的 VoiceOver 文案。
    /// Toolbar view-options menu; Pickers give selection state and full VoiceOver labels.
    private var viewOptionsMenu: some View {
        Menu {
            Picker("trends.menu.displayMode".localized(), selection: $trendsShowingMode) {
                ForEach(TrendsDisplayMode.allCases) { mode in
                    Label(mode.localizedName, systemImage: mode.icon).tag(mode)
                }
            }

            Picker("Chart Type".localized(), selection: Binding(
                get: { container.envManager.preferences.chartType },
                set: { container.envManager.preferences.chartType = $0 }
            )) {
                ForEach(ChartType.allCases) { type in
                    Label(type.localizedDisplayName, systemImage: type.icon).tag(type)
                }
            }

            Divider()

            // 90 天热力图开关（持久化到 AppPreferences）
            Toggle(isOn: Binding(
                get: { container.envManager.preferences.learningHeatmapOnTrends },
                set: { container.envManager.preferences.learningHeatmapOnTrends = $0 }
            )) {
                Label("Show Learning Heatmap".localized(), systemImage: "square.grid.4x3.fill")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("trends.menu.title".localized())
    }

    private var selectedRadarSnapshot: SubjectRadarSnapshot? {
        let subject = selectedRadarSubject ?? viewModel.radarSnapshots.first?.subject
        return viewModel.radarSnapshots.first { $0.subject == subject }
    }

    private var subjectMasteryRadar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Subject Mastery Radar".localized(), systemImage: "hexagon.fill")
                    .font(.headline.weight(.bold))
                Spacer()
                if viewModel.isRadarAILoading {
                    ProgressView().controlSize(.small)
                }
            }

            Picker("Subject".localized(), selection: Binding(
                get: { selectedRadarSubject ?? viewModel.radarSnapshots.first?.subject ?? "" },
                set: { selectedRadarSubject = $0 }
            )) {
                ForEach(viewModel.radarSnapshots) { snapshot in
                    Text(snapshot.subject.localized()).tag(snapshot.subject)
                }
            }
            .pickerStyle(.menu)

            if let snapshot = selectedRadarSnapshot {
                BodyRadarChart(
                    normalizedValues: snapshot.values,
                    axisLabels: [
                        "Knowledge Coverage".localized(),
                        "Review Frequency".localized(),
                        "Mistake Rate".localized(),
                        "Average Score".localized(),
                        "Study Time".localized(),
                        "HRV Performance".localized()
                    ]
                )
                .frame(height: 250)

                Text(String(format: "30-day subject data: %d grades · %d mistakes · %d min study".localized(), snapshot.gradeCount, snapshot.mistakeCount, snapshot.studyMinutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.requestRadarAIAnalysis()
            } label: {
                Label("AI Interpretation".localized(), systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isRadarAILoading)

            if let error = viewModel.radarAIError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let analysis = viewModel.radarAIAnalysis, !analysis.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(analysis)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .cardSkin()
        .onChange(of: viewModel.radarSnapshots) { _, snapshots in
            if selectedRadarSubject == nil || !snapshots.contains(where: { $0.subject == selectedRadarSubject }) {
                selectedRadarSubject = snapshots.first?.subject
            }
        }
        .onChange(of: hrvManager.readiness) { _, _ in viewModel.recompute() }
    }

    // O(1) 字典查表(已在 ViewModel.recompute 排序)
    private func getLatestGrade(for subject: String) -> Grade? {
        viewModel.latestGrade(for: subject)
    }

    private func getGradeHistory(for subject: String) -> [Grade] {
        viewModel.gradeHistory(for: subject)
    }
}

// MARK: - 科目详情页
struct SubjectDetailView: View {
    let subject: String
    @Environment(RepositoryContainer.self) private var container
    @Binding var displayMode: TrendsDisplayMode
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selectedRange: TimeRange = .all
    @State private var showingAddGrade = false

    enum TimeRange: String, CaseIterable {
        case all = "All"
        case last3Months = "3 Months"
        case last6Months = "6 Months"
        case lastYear = "1 Year"
    }

    private var chartHeight: CGFloat {
        sizeClass == .regular ? 380 : 300
    }
    
    // 
    var filteredGrades: [Grade] {
        let base = container.gradeRepo.filteredGrades
            .filter { $0.subject == subject }
            .sorted { $0.date < $1.date }
        
        let now = Date()
        let calendar = Calendar.current

        switch selectedRange {
        case .all:
            return base
        case .last3Months:
            let cutoff = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return base.filter { $0.date >= cutoff }
        case .last6Months:
            let cutoff = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return base.filter { $0.date >= cutoff }
        case .lastYear:
            let cutoff = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return base.filter { $0.date >= cutoff }
        }
    }
    
    // 
    var averageScore: Double {
        guard !filteredGrades.isEmpty else { return 0 }
        return filteredGrades.map{$0.score}.reduce(0,+)/Double(filteredGrades.count)
    }
    
    // 3
    var averageRank: Int {
        let validGrades = filteredGrades.filter { ($0.ranking ?? 0) > 0 }
        guard !validGrades.isEmpty else { return 0 }
        let totalRank = validGrades.compactMap { $0.ranking }.reduce(0, +)
        return totalRank / validGrades.count
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    // 
                    Text(subject.localized())
                        .scaledFont(size: 24, weight: .bold, design: .rounded)
                        .foregroundColor(Color(.label))
                    
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            // 
                            if displayMode == .score {
                                Text("Average Score".localized())
                                    .font(.subheadline)
                                    .foregroundColor(Color(.secondaryLabel))
                                    .tracking(0.5)
                                Text(String(format: "%.1f", averageScore))
                                    .scaledFont(size: 28, weight: .bold, design: .rounded)
                                    .foregroundStyle(scoreColor(averageScore))
                            } else {
                                Text("Average Rank".localized())
                                    .font(.subheadline)
                                    .foregroundColor(Color(.secondaryLabel))
                                    .tracking(0.5)
                                Text(averageRank == 0 ? "N/A".localized() : "\(averageRank)")
                                    .scaledFont(size: 28, weight: .bold, design: .rounded)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.indigo, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(alignment: .trailing, spacing: 8) {
                            Text("Latest".localized())
                                .font(.subheadline)
                                .foregroundColor(Color(.secondaryLabel))
                                .tracking(0.5)
                            
                            if let latest = filteredGrades.last {
                                // 4
                                if displayMode == .score {
                                    Text(String(format: "%.1f", latest.score))
                                        .scaledFont(size: 28, weight: .bold, design: .rounded)
                                        .foregroundStyle(scoreColor(latest.score))
                                } else {
                                    let rank = latest.ranking ?? 0
                                    Text(rank == 0 ? "N/A".localized() : "\(rank)")
                                        .scaledFont(size: 28, weight: .bold, design: .rounded)
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [.indigo, .purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                            } else {
                                Text("N/A".localized())
                                    .foregroundColor(Color(.secondaryLabel))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(DesignToken.Spacing.cardPadding)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignToken.CornerRadius.card)
                            .fill(Color(.secondarySystemGroupedBackground))
                        
                        RoundedRectangle(cornerRadius: DesignToken.CornerRadius.card)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(.systemBlue).opacity(0.3),
                                        Color(.systemBlue).opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    }
                )
                .shadow(
                    color: Color.black.opacity(0.06),
                    radius: 10,
                    x: 0,
                    y: 5
                )
                
                // 
                Picker("Time Range".localized(), selection: $selectedRange) {
                    ForEach(TimeRange.allCases, id:\.self) {
                        Text($0.rawValue.localized())
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                //  displayMode /
                if !filteredGrades.isEmpty {
                    if displayMode == .score {
                        TrendChartView(
                            grades: filteredGrades,
                            fullScore: container.fullScore(for: subject),
                            chartType: container.envManager.preferences.chartType,
                            tintColor: container.envManager.effectiveAccentColor
                        )
                        .frame(height: chartHeight)
                    } else {
                        // 排名仅保留折线图
                        Chart(filteredGrades) { grade in
                            if let rank = grade.ranking, rank > 0 {
                                LineMark(
                                    x: .value("Date", grade.date),
                                    y: .value("Rank", rank)
                                )
                                .foregroundStyle(Color(.indigo))

                                PointMark(
                                    x: .value("Date", grade.date),
                                    y: .value("Rank", rank)
                                )
                                .symbol {
                                    Circle()
                                        .fill(Color(.systemBackground))
                                        .frame(width: 10, height: 10)
                                        .overlay {
                                            Circle().stroke(scoreColor(grade.score), lineWidth: 2)
                                        }
                                }
                            }
                        }
                        .frame(height: chartHeight)
                    }
                } else {
                    ContentUnavailableView("No Data".localized(), systemImage: "chart.line.xaxis.dashed")
                        .frame(height: chartHeight)
                }
                
                // 
                VStack(alignment:.leading, spacing:12) {
                    Text("History".localized())
                        .font(.title2)
                        .bold()
                        .foregroundColor(Color(.label))
                    
                    if filteredGrades.isEmpty {
                        Text("No grades available".localized())
                            .foregroundColor(Color(.secondaryLabel))
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                    } else {
                        ForEach(filteredGrades.reversed()) { grade in
                            HStack {
                                VStack(alignment:.leading) {
                                    Text(grade.examName.isEmpty ? "Unnamed Exam".localized() : grade.examName)
                                        .foregroundColor(Color(.label))
                                    Text(grade.date.formatted(date:.abbreviated, time:.omitted))
                                        .font(.caption)
                                        .foregroundColor(Color(.secondaryLabel))
                                }
                                
                                Spacer()
                                
                                // 6
                                if displayMode == .score {
                                    Text(String(format: "%.1f", grade.score))
                                        .bold()
                                        .foregroundColor(scoreColor(grade.score))
                                } else {
                                    let rank = grade.ranking ?? 0
                                    Text(rank == 0 ? "N/A".localized() : "\(rank)")
                                        .bold()
                                        .foregroundColor(.indigo)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(10)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteGrade(grade)
                                } label: {
                                    Label("Delete".localized(), systemImage:"trash.fill")
                                }
                                .tint(Color(.systemRed))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DesignToken.Spacing.secondaryHorizontal)
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .adaptiveMaxWidth(960)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddGrade = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add New Grade".localized())
            }
        }
        .sheet(isPresented: $showingAddGrade) {
            AddGradeView(container: container)
                .adaptiveSheet()
        }
    }
    
    // 
    private func deleteGrade(_ grade: Grade) {
        container.deleteGrade(grade)
    }
}

// MARK: - 需要引起重视的科目卡片
struct AttentionSubjectCard: View {
    let subjectName: String
    let grades: [Grade]
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var animateIn = false

    var recentGrades: [Grade] {
        Array(grades.sorted { $0.date > $1.date }.prefix(3))
    }

    var averageScore: Double {
        guard !grades.isEmpty else { return 0 }
        return grades.map { $0.score }.reduce(0, +) / Double(grades.count)
    }

    var trend: String {
        guard grades.count >= 2 else { return "N/A".localized() }
        let sorted = grades.sorted { $0.date < $1.date }
        guard let oldScore = sorted.first?.score, let newScore = sorted.last?.score else {
            return "N/A".localized()
        }

        if newScore > oldScore + 5 {
            return "Improving".localized()
        } else if newScore < oldScore - 5 {
            return "Declining".localized()
        } else {
            return "Stable".localized()
        }
    }

    private var cardWidth: CGFloat {
        sizeClass == .regular ? 240 : 200
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(subjectName.localized())
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avg Score".localized())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f", averageScore))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(scoreColor(averageScore))
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trend".localized())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(trend)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            
            if !recentGrades.isEmpty {
                HStack(spacing: 8) {
                    ForEach(recentGrades) { grade in
                        Text(String(format: "%.0f", grade.score))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(scoreColor(grade.score).opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: cardWidth)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .opacity(animateIn ? 1 : 0)
        .offset(x: animateIn ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.1)) {
                animateIn = true
            }
        }
    }
}

#Preview {
    TrendsView(container: RepositoryContainer())
        .environment(HealthKitManager.shared)
}

#Preview("Dark Mode") {
    TrendsView(container: RepositoryContainer())
        .environment(HealthKitManager.shared)
        .preferredColorScheme(.dark)
}
