//
//  SingleSubjectPrediction.swift
//  StudyPulse
//
//  Created for the Exam "预测" button feature.
//  Exam "Predict" button feature — single-subject score prediction view.
//

import SwiftUI
import Charts

/// 单科预测内容视图(离群点警告 + CI 柱图 + 关键统计 + AI 入口 + 详情按钮)
/// Single-subject prediction content view
/// (outlier warning + CI bar chart + key stats + AI entry + detail button).
struct SingleSubjectPredictionContent: View {
    let exam: Exam
    let history: [Grade]
    let result: ScorePredictionResult
    let fullScore: Double
    let subjectMistakes: [MistakeNote]
    @Binding var showingDetail: Bool

    @Environment(RepositoryContainer.self) private var container

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 离群点警告(若最近一次考试残差 > 3σ)
            // Outlier warning (only when the most recent exam's residual exceeds 3σ).
            if let warning = result.outlierWarning {
                outlierWarningCard(warning: warning)
            }

            // v1.5:数据不足横幅(n<3 / yHat 撞边界 / CI 撑满)
            // v1.5: low-confidence banner (n<3 / yHat clamped / CI hits full range).
            if result.isLowConfidence {
                lowConfidenceCard(result: result)
            }

            // 95% CI 柱状图
            // 95% CI bar chart.
            ciBarChartCard(result: result)

            // 关键统计
            // Key stats.
            statsCard(result: result)

            // 历史样本
            // History samples used for the prediction.
            historyCard(result: result)

            // AI 预测按钮 + 折叠结果
            // AI prediction button + collapsible result.
            PredictionDiscussionEntryView(context: .singleSubject(
                exam: exam,
                history: history,
                defaultResult: result,
                fullScore: fullScore,
                subjectMistakes: subjectMistakes
            ))

            // 详情入口
            // Detail entry button.
            detailButton
        }
    }

    // MARK: - 子卡片
    // MARK: - Sub-cards

    /// 95% 置信区间柱状图
    /// 95% confidence interval bar chart.
    @ViewBuilder
    private func ciBarChartCard(result: ScorePredictionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("95% Confidence Interval".localized())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(
                    format: "±%.1f %@".localized(),
                    result.halfWidth,
                    "pts".localized()
                ))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(container.envManager.effectiveAccentColor)
            }

            // 主柱状图
            // Main bar mark (the CI rectangle).
            Chart {
                RectangleMark(
                    xStart: .value("Side", "CI"),
                    xEnd: .value("Side", "CI"),
                    yStart: .value("Lower", result.lowerBound),
                    yEnd: .value("Upper", result.upperBound)
                )
                .foregroundStyle(container.envManager.effectiveAccentColor.opacity(0.18))
                .cornerRadius(6)

                // 预测点水平线
                // Predicted-score horizontal rule.
                RuleMark(y: .value("Predicted", result.predicted))
                    .foregroundStyle(container.envManager.effectiveAccentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .annotation(position: .top, alignment: .leading) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(container.envManager.effectiveAccentColor)
                                .frame(width: 7, height: 7)
                            Text("\(Int(result.predicted.rounded()))")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.primary)
                        }
                    }

                // 最近一次实际分数参考线
                // Last-actual-score reference line.
                if let last = result.lastActual {
                    RuleMark(y: .value("Last", last))
                        .foregroundStyle(Color(.systemGray))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .bottom, alignment: .leading) {
                            Text(String(format: "Last %d".localized(), Int(last.rounded())))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                }
            }
            .chartXAxis(.hidden)
            .chartYScale(domain: 0...max(result.fullScore, result.upperBound * 1.05))
            .frame(height: 220)
            .padding(.top, 4)

            // 区间文本
            // Interval text (lower → predicted → upper).
            HStack(spacing: 6) {
                Text("\(Int(result.lowerBound.rounded()))")
                    .font(.title3.weight(.bold))
                    .foregroundColor(container.envManager.effectiveAccentColor.opacity(0.45))
                Text("→")
                    .font(.title3)
                    .foregroundColor(container.envManager.effectiveAccentColor.opacity(0.45))
                Text("\(Int(result.predicted.rounded()))")
                    .font(.title3.weight(.heavy))
                    .foregroundColor(container.envManager.effectiveAccentColor)
                Text("→")
                    .font(.title3)
                    .foregroundColor(container.envManager.effectiveAccentColor.opacity(0.45))
                Text("\(Int(result.upperBound.rounded()))")
                    .font(.title3.weight(.bold))
                    .foregroundColor(container.envManager.effectiveAccentColor.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text("Predicted score range with 95% confidence.".localized())
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    /// 关键统计
    /// Key statistics card.
    @ViewBuilder
    private func statsCard(result: ScorePredictionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Key Stats".localized())
                .font(.subheadline)
                .fontWeight(.semibold)

            statsRow(
                title: "Prediction Range".localized(),
                value: String(
                    format: "Based on %d exams, ±%.1f pts".localized(),
                    result.usedSampleSize,
                    result.halfWidth
                )
            )

            if result.shouldShowMistakeEffects, let gamma = result.exposureLift {
                let perTenReviews = gamma * 10
                let formattedPerTen = String(format: "%+0.1f", perTenReviews)
                statsRow(
                    title: "Exposure Lift".localized(),
                    value: String(
                        format: "每 10 次复习 → %@ %@".localized(),
                        formattedPerTen,
                        "pts".localized()
                    ),
                    valueColor: gamma >= 0 ? Color(.systemGreen) : Color(.systemRed)
                )
            }

            if result.shouldShowMistakeEffects, result.avgMastery > 0 {
                let shrunkPct = Int((1.0 - result.masteryCIMultiplier) * 100)
                statsRow(
                    title: "Avg Mastery".localized(),
                    value: String(
                        format: "%d%% (CI −%d%%)".localized(),
                        Int(result.avgMastery * 100),
                        shrunkPct
                    ),
                    valueColor: Color(.systemBlue)
                )
            } else if !result.shouldShowMistakeEffects {
                statsRow(
                    title: "Mistake Review".localized(),
                    value: "复习过少,未纳入计算".localized(),
                    valueColor: Color(.systemGray)
                )
            }

            statsRow(
                title: "Window".localized(),
                value: String(
                    format: "%dd / EWMA %dd".localized(),
                    Int(result.windowDays),
                    Int(result.halfLifeDays)
                )
            )

            if let slope = result.slope {
                let perWeek = slope * 7
                let trendKey: String = (abs(perWeek) < 0.05) ? "Flat" : (perWeek > 0 ? "Rising" : "Falling")
                let trend = trendKey.localized()
                let formatted = String(format: "%+.2f", perWeek)
                statsRow(
                    title: "Trend (per week)".localized(),
                    value: String(format: "%@ pts (%@)".localized(), formatted, trend)
                )
            }
            if let delta = result.delta {
                let formatted = String(format: "%+.1f", delta)
                let color: Color = delta >= 0 ? Color(.systemGreen) : Color(.systemRed)
                statsRow(
                    title: "Change vs. Last".localized(),
                    value: String(format: "%@ %@".localized(), formatted, "pts".localized()),
                    valueColor: color
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    /// 离群点警告卡
    /// Outlier warning card.
    @ViewBuilder
    private func outlierWarningCard(warning: OutlierWarning) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(.systemOrange))
                Text("Outlier Detected".localized())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "z = %+.1fσ".localized(), warning.zScore))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color(.systemOrange))
            }
            Text("Last exam may have been affected by special factors (illness, bad day, etc.). Treat the prediction with extra caution.".localized())
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(String(format: "%@ %@".localized(), warning.date.formatted(date: .abbreviated, time: .omitted), "·"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "Score %@, fitted %@, |residual| %@".localized(),
                            String(format: "%.1f", warning.score),
                            String(format: "%.1f", warning.fittedValue),
                            String(format: "%.1f", abs(warning.residual))))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemOrange).opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(.systemOrange).opacity(0.35), lineWidth: 1)
        )
    }

    /// 数据不足横幅
    /// Low-confidence banner shown when the prediction isn't reliable.
    @ViewBuilder
    private func lowConfidenceCard(result: ScorePredictionResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(.systemOrange))
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Data Insufficient for Reliable Prediction".localized())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(String(
                    format: "仅基于 %d 条成绩,置信区间过宽,以下数字仅作参考。".localized(),
                    result.usedSampleSize
                ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemOrange).opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(.systemOrange).opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statsRow(title: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(valueColor)
        }
    }

    /// 历史样本列表
    /// List of historical samples used in the prediction.
    @ViewBuilder
    private func historyCard(result: ScorePredictionResult) -> some View {
        let recent = result.dataRange.map { range in
            history.filter { range.contains($0.date) }
        } ?? []
        let sorted = recent.sorted(by: { $0.date > $1.date })
        if !sorted.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Grades Used".localized())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    if let range = result.dataRange {
                        Text(String(
                            format: "%@ – %@".localized(),
                            range.lowerBound.formatted(date: .abbreviated, time: .omitted),
                            range.upperBound.formatted(date: .abbreviated, time: .omitted)
                        ))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                ForEach(sorted, id: \.id) { g in
                    HStack {
                        Text(g.date, format: .dateTime.month().day())
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .leading)
                        if !g.examName.isEmpty {
                            Text(g.examName)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("(no name)".localized())
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("\(Int(g.score.rounded()))")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    /// 详情按钮
    /// Detail entry button (opens ScorePredictionDetailView).
    @ViewBuilder
    private var detailButton: some View {
        Button {
            showingDetail = true
        } label: {
            HStack {
                Image(systemName: "target")
                Text("How to Reach Your Target".localized())
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(container.envManager.effectiveAccentColor.opacity(0.12))
            )
            .foregroundColor(container.envManager.effectiveAccentColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 预测详情页
// MARK: - Prediction detail page

/// 预测详情:输入目标分 → 计算 gap → 推荐错题
/// Prediction detail: input a target score, compute the gap, recommend mistakes to review.
struct ScorePredictionDetailView: View {
    let exam: Exam
    let history: [Grade]
    let result: ScorePredictionResult
    let fullScore: Double

    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var targetScoreText: String = ""
    @State private var didInitTarget = false
    @FocusState private var targetFocused: Bool

    private var candidateMistakes: [MistakeNote] {
        container.mistakeRepo.filteredMistakeSets
            .filter { $0.subject == exam.subject && !$0.title.isEmpty }
            .sorted { $0.date > $1.date }
    }

    private var targetScore: Double {
        let parsed = Double(targetScoreText.trimmingCharacters(in: .whitespaces)) ?? result.upperBound
        return max(0, min(parsed, fullScore))
    }

    private var gap: Double {
        MistakeGapAnalyzer.scoreGap(target: targetScore, result: result)
    }

    private var recommendations: [MistakeRecommendation] {
        guard gap > 0 else { return [] }
        return MistakeGapAnalyzer.recommendations(
            mistakes: candidateMistakes,
            targetScore: targetScore,
            maxCount: 5
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    targetInputCard
                    gapSummaryCard
                    if gap > 0 {
                        recommendationCard
                    } else {
                        onTrackCard
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Target Plan".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized()) { dismiss() }
                }
            }
            .onAppear {
                guard !didInitTarget else { return }
                didInitTarget = true
                let defaultTarget = min(fullScore, max(result.upperBound, (result.predicted + 5).rounded(.up)))
                let roundedToFive = (defaultTarget / 5.0).rounded() * 5.0
                let safe = max(1, min(fullScore, roundedToFive))
                targetScoreText = String(Int(safe))
            }
        }
    }

    @ViewBuilder
    private var targetInputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Target Score".localized())
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 10) {
                TextField("e.g. 130", text: $targetScoreText)
                    .keyboardType(.numberPad)
                    .focused($targetFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
                    .frame(maxWidth: 120)
                Text("/ \(Int(fullScore))")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Stepper("", value: Binding(
                    get: { Int(targetScoreText) ?? 0 },
                    set: { targetScoreText = String(max(0, min($0, Int(fullScore)))) }
                ))
                .labelsHidden()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var gapSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Score Gap".localized())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "To %d".localized(), Int(targetScore)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("+ \(String(format: "%.1f", gap))")
                    .scaledFont(size: 36, weight: .heavy, design: .rounded)
                    .foregroundColor(gap > 0 ? Color(.systemOrange) : Color(.systemGreen))
                Text("pts".localized())
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            Text(String(
                format: "To safely reach %d (with 95%% confidence), you need to close the gap above your lower bound (%d).".localized(),
                Int(targetScore),
                Int(result.lowerBound)
            ))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recommended Mistakes".localized())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "%d / %d".localized(),
                            recommendations.count,
                            candidateMistakes.count))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if recommendations.isEmpty {
                Text("No mistakes found for this subject yet. Add some to get targeted recommendations.".localized())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(recommendations) { rec in
                    recommendationRow(rec)
                    if rec.id != recommendations.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private func recommendationRow(_ rec: MistakeRecommendation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.bubble.fill")
                .foregroundColor(.orange)
                .font(.callout)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(rec.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Label(rec.date.formatted(date: .abbreviated, time: .omitted),
                          systemImage: "calendar")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Label(String(format: "Mastery %d%%".localized(),
                                 Int((rec.masteryScore * 100).rounded())),
                          systemImage: "gauge.with.dots.needle.67percent")
                        .font(.caption2)
                        .foregroundColor(rec.masteryScore < 0.4 ? Color(.systemRed) : Color(.systemOrange))
                    if rec.exposureCount > 0 {
                        Label(String(format: "× %d".localized(), rec.exposureCount),
                               systemImage: "eye")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var onTrackCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("On Track".localized(), systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundColor(Color(.systemGreen))
            Text(String(
                format: "Your predicted lower bound (%d) already meets or exceeds the target (%d). No extra review needed based on current trend.".localized(),
                Int(result.lowerBound),
                Int(targetScore)
            ))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGreen).opacity(0.10))
        )
    }
}
