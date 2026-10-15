//
//  TrendChartCard.swift
//  StudyPulse
//
//  主页"单科目趋势"图表卡。菜单选聚焦规则 → 选科目 → TrendChartView。
// 选科 / 科目-成绩查询已迁入 HomeViewModel,本卡只负责 UI。
//  Home "Single-Subject Trend" chart card. Menu selects a focus rule → picks a subject
//  → renders TrendChartView. Subject selection and per-subject grade lookup have
//  been moved into HomeViewModel; this card only handles UI.
//
//  Extracted from HomeView.swift during card-extraction refactor (2026-07-05).
//

import SwiftUI
import Charts

/// 单科目趋势图表卡:用户通过 Menu 选择聚焦规则,
/// VM 根据规则选出一门科目,卡片渲染对应 TrendChartView + 三项统计。
///
/// 由父 View 注入 `HomeViewModel`(VM 拥有选科状态);卡片只读取不写入。
/// Single-subject trend chart card: user picks a focus rule from the Menu,
/// the VM selects a subject per the rule, and the card renders the corresponding
/// TrendChartView + 3 statistics tiles.
///
/// The parent View injects `HomeViewModel` (VM owns the chart subject selection);
/// the card only reads, never writes.
struct TrendChartCard: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.exportMode) private var exportMode
    /// 注入 HomeViewModel(图表选科逻辑已迁入)
    /// Injected HomeViewModel (chart subject selection has been moved here).
    @Bindable var viewModel: HomeViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var animateChart = false

    /// 图表区域高度:iPad/regular 用 260,iPhone 用 180
    /// Chart area height: 260 on iPad / regular, 180 on iPhone.
    private var chartHeight: CGFloat {
        isIPad || sizeClass == .regular ? 260 : 180
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Subject Trend".localized())
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundColor(.primary)

                Spacer()

                // 导出模式(`ImageRenderer`)下用纯文本代替 `Menu`:
                // iOS 26 的 Menu 在 label 自带圆角容器 + 系统"菜单指示器"图标,
                // 这个内部图标在 ImageRenderer 渲染管线里会失败,显示成"黄底红禁止"
                // 的占位符。用纯文本既能保留焦点规则信息,又规避了渲染问题。
                // In export mode (`ImageRenderer`) replace the interactive `Menu` with
                // plain text. iOS 26 Menu adds a system "menu indicator" icon that
                // fails to load in `ImageRenderer`, leaving a yellow placeholder box
                // with a red "prohibited" sign in the exported image.
                if exportMode {
                    Text(viewModel.chartRule.displayName)
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    Menu {
                        Button(action: { viewModel.selectChartSubject(rule: .lowestScore) }) {
                            Label("Focus: Lowest Score".localized(), systemImage: "chart.line.downtrend.xyaxis")
                        }
                        Button(action: { viewModel.selectChartSubject(rule: .mostGrades) }) {
                            Label("Focus: Most Data".localized(), systemImage: "doc.text.fill")
                        }
                        Button(action: { viewModel.selectChartSubject(rule: .recentMost) }) {
                            Label("Focus: Recent Activity".localized(), systemImage: "clock")
                        }
                        Button(action: { viewModel.selectChartSubject(rule: .mostImprovement) }) {
                            Label("Focus: Improvement".localized(), systemImage: "chart.line.uptrend.xyaxis")
                        }
                        Button(action: { viewModel.selectChartSubject(rule: .random) }) {
                            Label("Random Subject".localized(), systemImage: "shuffle")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.chartRule.displayName)
                                .scaledFont(size: 12, weight: .medium)
                            Image(systemName: "chevron.up.chevron.down")
                                .scaledFont(size: 10)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }

            if let subject = viewModel.chartSelectedSubject, let grades = viewModel.gradesForSubject(subject) {
                VStack(spacing: 12) {
                    HStack {
                        Text(subject.localized())
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundColor(.primary)

                        Spacer()

                        Text(String(format: "%d records".localized(), grades.count))
                            .scaledFont(size: 12)
                            .foregroundColor(.secondary)
                    }

                    TrendChartView(
                        grades: grades.sorted(by: { $0.date < $1.date }),
                        fullScore: container.fullScore(for: subject),
                        chartType: container.envManager.preferences.chartType,
                        tintColor: container.envManager.effectiveAccentColor
                    )
                    .frame(height: chartHeight)
                    .opacity(animateChart ? 1 : 0)
                    .offset(y: animateChart ? 0 : 20)

                    HStack(spacing: 20) {
                        ChartStatisticItem(title: "Average".localized(), value: String(format: "%.1f", SubjectAggregator.averageScore(for: grades)), color: .cyan)
                        ChartStatisticItem(title: "Highest".localized(), value: String(format: "%.1f", SubjectAggregator.highestScore(for: grades)), color: .green)
                        ChartStatisticItem(title: "Lowest".localized(), value: String(format: "%.1f", SubjectAggregator.lowestScore(for: grades)), color: .orange)
                    }
                }
                .padding(16)
                .background(Color(.systemBackground).opacity(0.6))
                .cornerRadius(16)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .scaledFont(size: 40)
                        .foregroundColor(.secondary)
                    Text("Select a subject to view trends".localized())
                        .scaledFont(size: 14)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color(.systemBackground).opacity(0.6))
                .cornerRadius(16)
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
        .debugLayoutBoundsAuto()
        .onAppear {
            viewModel.selectChartSubject(rule: viewModel.chartRule)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2)) {
                animateChart = true
            }
        }
    }
}

// MARK: - 统计项视图
// MARK: - Statistics Item View

/// TrendChartCard 底部三段式统计 tile(平均/最高/最低)。
///
/// 注:名字为 `ChartStatisticItem` 是为了避免与 HomeView 之前叫 `StatisticItem`
/// 的全局类型产生歧义;旧名仍保留在 HomeView 删完之前,这里先新名站稳。
/// 3-segment statistics tile at the bottom of TrendChartCard (average / highest / lowest).
///
/// Note: renamed to `ChartStatisticItem` to avoid ambiguity with the old global
/// `StatisticItem` type that previously lived on HomeView; once HomeView is fully
/// cleaned up, the new name is the one to keep.
struct ChartStatisticItem: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .scaledFont(size: 16, weight: .bold)
                .foregroundColor(color)
            Text(title)
                .scaledFont(size: 11)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
