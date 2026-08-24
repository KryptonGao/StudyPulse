//
//  LearningHeatmapView.swift
//  StudyPulse
//
//  GitHub 风格的 90 天学习热力图。
//  Shows a 90-day activity grid powered by `AchievementManager.snapshot.logs`.
//  - 7 行（周一到周日）× 13 列（13 周 = 91 天）
//  - 5 档颜色强度（基于 DailyActivityLog.totalActivityPoints）
//  - 使用 `effectiveAccentColor` 作为底色，与全局主色联动
//  - 点击格子弹出当日详情
//  - 顶部摘要：90 天活跃天数 / 当前连续天数
//  - 底部色阶图例
//
//  入口：HomeView 顶部 / TrendsView 顶部 / Settings 里可关闭
//

import SwiftUI

// MARK: - Activity Level
// MARK: - 活动强度档位

/// 单日活动强度分档(5 档 + 空),用于颜色映射。
/// 阈值:0 → none;1-2 → light;3-5 → medium;6-10 → strong;11+ → intense
/// Activity intensity bucket used for color mapping.
/// Thresholds: 0 → none; 1-2 → light; 3-5 → medium; 6-10 → strong; 11+ → intense.
enum HeatmapActivityLevel: Int, CaseIterable {
    case none = 0       // 0
    case light = 1      // 1-2
    case medium = 2     // 3-5
    case strong = 3     // 6-10
    case intense = 4    // 11+

    /// 从 totalActivityPoints 计算档位。
    static func from(points: Int) -> HeatmapActivityLevel {
        switch points {
        case ..<1:    return .none
        case 1...2:   return .light
        case 3...5:   return .medium
        case 6...10:  return .strong
        default:      return .intense
        }
    }

    /// 颜色透明度(相对于主色)。0 = 纯灰底。
    /// 档位透明度梯度:0 / 0.22 / 0.45 / 0.72 / 1.0
    /// Opacity relative to the accent color. 0 = pure gray track.
    /// Opacity gradient per level: 0 / 0.22 / 0.45 / 0.72 / 1.0.
    var opacity: Double {
        switch self {
        case .none:    return 0.0
        case .light:   return 0.22
        case .medium:  return 0.45
        case .strong:  return 0.72
        case .intense: return 1.0
        }
    }
}

// MARK: - Heatmap Cell
// MARK: - 热力图格子

/// 单个格子对应的数据:日期 + 活动日志(可能为 nil,代表未记录)。
/// Data for a single heatmap cell: date + activity log (may be `nil` to mean "not recorded").
struct HeatmapCell: Identifiable, Equatable {
    let date: Date
    let log: DailyActivityLog?

    var id: Date { date }
    var points: Int { log?.totalActivityPoints ?? 0 }
    var level: HeatmapActivityLevel { HeatmapActivityLevel.from(points: points) }
}

// MARK: - Learning Heatmap View
// MARK: - 学习热力图视图

/// 90 天学习热力图。GitHub 风格:列 = 周,行 = 周几;今天在最右列。
/// 90-day learning heatmap. GitHub style: columns = weeks, rows = weekdays; today is in the rightmost column.
struct LearningHeatmapView: View {
    @Environment(AchievementManager.self) private var achievementManager: AchievementManager
    @Environment(RepositoryContainer.self) private var container

    /// 90 天滚动窗口(包含今天),共 13 周。
    /// 90-day rolling window (includes today) = 13 weeks.
    static let dayCount: Int = 90
    static let weekCount: Int = 13

    /// 当前选中的格子(用于显示详情 sheet)。
    /// Currently selected cell (used to show the day-detail sheet).
    @State private var selectedCell: HeatmapCell? = nil
    @State private var showingManualActivitySheet = false

    /// 缓存后的 91 格数组,仅在 `snapshot.logs` 变化时重算,避免 body 每帧重算。
    /// Cached 91-cell array; recomputed only when `snapshot.logs` changes so the
    /// body doesn't rebuild it on every render.
    @State private var cells: [HeatmapCell] = []

    private func recomputeCells() { cells = buildCells() }

    private var accent: Color { container.envManager.effectiveAccentColor }
    private var emptyColor: Color { Color(.tertiarySystemFill) }

    /// 把 AchievementManager 的 logs 转换成 91 天(含今天)的格子数组。
    /// 索引顺序:按列优先(先填满一列再下一列),保证 GitHub 风格"今天在最右下方"。
    /// Convert `AchievementManager`'s logs into a 91-cell array (including today).
    /// Iteration order: column-major (fill one column before moving to the next),
    /// which matches the GitHub "today is bottom-right" look.
    private func buildCells() -> [HeatmapCell] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // 把 logs 转成 dict 方便查询（用 merging 保证不会因重复键崩溃）
        var logMap: [Date: DailyActivityLog] = [:]
        for log in achievementManager.snapshot.logs {
            let key = cal.startOfDay(for: log.date)
            // 同日多条记录时合并（理论上不会发生，但 defensive）
            if var existing = logMap[key] {
                existing.mistakeReviews += log.mistakeReviews
                existing.gradesRecorded += log.gradesRecorded
                existing.focusMinutes += log.focusMinutes
                logMap[key] = existing
            } else {
                logMap[key] = log
            }
        }

        // 计算今天所在列的"周开始"（周一为列首）；为简化，统一让"最右一列"就是当前周。
        // GitHub 的列首是周日，这里用周一，更贴近中文/欧洲用户。
        let weekday = cal.component(.weekday, from: today)         // 1 = Sunday
        let mondayBasedWeekday = ((weekday + 5) % 7) + 1            // 1 = Monday ... 7 = Sunday
        let daysToLastColumnStart = mondayBasedWeekday - 1          // 已过的天数
        let lastColumnStart = cal.date(byAdding: .day, value: -daysToLastColumnStart, to: today) ?? today
        // 第一列的开始：lastColumnStart - 12*7 = 84 天前
        let firstColumnStart = cal.date(byAdding: .day, value: -12 * 7, to: lastColumnStart) ?? lastColumnStart

        // 列优先遍历：每列内 7 个格子（周一到周日）
        var result: [HeatmapCell] = []
        result.reserveCapacity(Self.weekCount * 7)
        for col in 0..<Self.weekCount {
            guard let columnStart = cal.date(byAdding: .day, value: col * 7, to: firstColumnStart) else { continue }
            for row in 0..<7 {
                let day = cal.date(byAdding: .day, value: row, to: columnStart) ?? columnStart
                let normalized = cal.startOfDay(for: day)
                let log = logMap[normalized]
                result.append(HeatmapCell(date: normalized, log: log))
            }
        }
        return result
    }

    /// 总活跃天数（past 90 天内，log 存在即算活跃）。
    private var activeDaysIn90: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.dayCount, to: Date()) ?? Date()
        return achievementManager.snapshot.logs
            .filter { $0.date >= Calendar.current.startOfDay(for: cutoff) }
            .count
    }

    /// 最强的一天（用于次要摘要展示）。
    private var bestDay: DailyActivityLog? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.dayCount, to: Date()) ?? Date()
        return achievementManager.snapshot.logs
            .filter { $0.date >= Calendar.current.startOfDay(for: cutoff) }
            .max(by: { $0.totalActivityPoints < $1.totalActivityPoints })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            grid
            legend
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
        .sheet(item: $selectedCell) { cell in
            HeatmapDayDetailSheet(cell: cell, accent: accent)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingManualActivitySheet) {
            ManualActivitySheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: achievementManager.snapshot.logs, initial: true) {
            recomputeCells()
        }
    }

    // MARK: - Header
    // MARK: - 顶部标题

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.4x3.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                    Text("heatmap.title".localized())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
                Text("heatmap.subtitle".localized())
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                showingManualActivitySheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("heatmap.manual.add".localized())
            // 90 天活跃天数
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(activeDaysIn90)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                Text("heatmap.activeDays".localized())
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Grid
    // MARK: - 网格

    private var grid: some View {
        // 13 列 × 7 行;列从左到右(旧→新),行从上到下(周一→周日)。
        // 13 columns × 7 rows; columns L→R (oldest→newest), rows T→B (Monday→Sunday).
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: Self.weekCount)

        return HStack(alignment: .top, spacing: 8) {
            // 周几标签
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(1...7, id: \.self) { row in
                    Text(weekdayShortLabel(for: row))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 22, alignment: .trailing)
                        // 隐藏周三/周五/周日，保持简洁（GitHub 风格）
                        .opacity([1, 3, 5].contains(row) ? 1 : 0)
                }
            }
            .padding(.top, 0)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(cells) { cell in
                    HeatmapCellView(
                        cell: cell,
                        accent: accent,
                        emptyColor: emptyColor,
                        onTap: { selectedCell = cell }
                    )
                }
            }
        }
    }

    // MARK: - Legend
    // MARK: - 色阶图例

    private var legend: some View {
        HStack(spacing: 6) {
            Text("heatmap.less".localized())
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            ForEach(HeatmapActivityLevel.allCases, id: \.rawValue) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color(for: level))
                    .frame(width: 11, height: 11)
            }
            Text("heatmap.more".localized())
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            if let best = bestDay, best.totalActivityPoints > 0 {
                Text(String(format: "heatmap.bestDay".localized(), best.totalActivityPoints, formatDate(best.date)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers
    // MARK: - 辅助函数

    private func color(for level: HeatmapActivityLevel) -> Color {
        if level == .none { return emptyColor }
        return accent.opacity(level.opacity)
    }

    /// 周几短标签(1=周一 ... 7=周日)。
    /// Short weekday label (1 = Monday ... 7 = Sunday).
    private func weekdayShortLabel(for row: Int) -> String {
        // 用 DateFormatter 拿周一/周三/周五/周日的短标签
        let symbols = Calendar.current.shortWeekdaySymbols  // ["Sun", "Mon", ..., "Sat"]
        // shortWeekdaySymbols 顺序：Sun(0) Mon(1) Tue(2) Wed(3) Thu(4) Fri(5) Sat(6)
        // 我们 row 1 = 周一，对应 symbols[1]
        let index = row % 7
        return symbols[index]
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Cell View
// MARK: - 格子视图

/// 单个热力图格子。带点击交互。
/// A single heatmap cell. Tappable.
private struct HeatmapCellView: View {
    let cell: HeatmapCell
    let accent: Color
    let emptyColor: Color
    let onTap: () -> Void

    private var color: Color {
        if cell.level == .none { return emptyColor }
        return accent.opacity(cell.level.opacity)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .onTapGesture(perform: onTap)
            .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let dateString = formatter.string(from: cell.date)
        if cell.log == nil {
            return "\(dateString), no activity"
        }
        return "\(dateString), \(cell.points) activity points"
    }
}

// MARK: - Manual Activity Sheet

private struct ManualActivitySheet: View {
    @Environment(AchievementManager.self) private var achievementManager: AchievementManager
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var kind: ManualActivityKind = .focusMinutes
    @State private var amountText = "25"

    private var amount: Int { Int(amountText) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("heatmap.manual.date".localized(), selection: $date,
                               in: ...Date(), displayedComponents: .date)
                    Picker("heatmap.manual.category".localized(), selection: $kind) {
                        Text("heatmap.detail.reviews".localized()).tag(ManualActivityKind.mistakeReview)
                        Text("heatmap.detail.grades".localized()).tag(ManualActivityKind.gradeRecorded)
                        Text("heatmap.detail.focusMinutes".localized()).tag(ManualActivityKind.focusMinutes)
                    }
                    TextField("heatmap.manual.amount".localized(), text: $amountText)
                        .keyboardType(.numberPad)
                } footer: {
                    Text(String(format: "heatmap.manual.amountHint".localized(),
                                kind == .focusMinutes ? "heatmap.manual.minutesUnit".localized() : "heatmap.manual.countUnit".localized()))
                }
            }
            .navigationTitle("heatmap.manual.title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized()) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save".localized()) {
                        achievementManager.recordManualActivity(kind: kind, count: amount, date: date)
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
    }
}

// MARK: - Day Detail Sheet
// MARK: - 单日详情 sheet

/// 单日详情 sheet:显示当日各项活动数据 + 时间线摘要。
/// Per-day detail sheet: shows all activity data for the day + a timeline summary.
private struct HeatmapDayDetailSheet: View {
    let cell: HeatmapCell
    let accent: Color
    @Environment(\.dismiss) private var dismiss

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: cell.date)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                // 标题区
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent.opacity(cell.level == .none ? 0.12 : cell.level.opacity))
                            .frame(width: 52, height: 52)
                        Image(systemName: cell.level == .none ? "moon.zzz" : "flame.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(cell.level == .none ? Color.secondary : Color.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dateString)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(activitySummary)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 4)

                Divider()

                if let log = cell.log {
                    statRow(icon: "rectangle.stack.fill", color: .purple,
                            title: "heatmap.detail.reviews".localized(),
                            value: "\(log.mistakeReviews)")
                    statRow(icon: "list.bullet.rectangle", color: .blue,
                            title: "heatmap.detail.grades".localized(),
                            value: "\(log.gradesRecorded)")
                    statRow(icon: "timer", color: .orange,
                            title: "heatmap.detail.focusMinutes".localized(),
                            value: String(format: "heatmap.detail.minutesValue".localized(), log.focusMinutes))
                    HStack {
                        Text("heatmap.detail.totalPoints".localized())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(log.totalActivityPoints)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                    }
                    .padding(.top, 6)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("heatmap.detail.noData".localized())
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("heatmap.detail.title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Close".localized())
                }
            }
        }
    }

    private var activitySummary: String {
        if let log = cell.log {
            return String(format: "heatmap.detail.subtitle".localized(), log.totalActivityPoints)
        }
        return "heatmap.detail.emptyDay".localized()
    }

    @ViewBuilder
    private func statRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Preview
// MARK: - 预览

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            LearningHeatmapView()
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
    .environment(RepositoryContainer())
    .environment(AchievementManager.shared)
}
