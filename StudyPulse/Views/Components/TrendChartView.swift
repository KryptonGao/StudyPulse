//
//  TrendChartView.swift
//  StudyPulse
//
//  根据用户在设置中选择的 ChartType(折线/柱状/饼图/散点/热力)渲染成绩趋势。
//  Renders the grade trend according to the user's `ChartType` selection
//  in settings (line / bar / pie / scatter / heatmap / histogram).
//

import SwiftUI
import Charts

/// 统一的成绩趋势图:按 chartType 自动切换渲染方式
/// Unified grade-trend chart that switches rendering style per `chartType`.
struct TrendChartView: View {
    /// 排序后的成绩(按日期升序)
    /// Grades sorted ascending by date.
    let grades: [Grade]
    /// 分数满分(用于饼图/热力图分段与 Y 轴范围)
    /// Full score (used for pie/heatmap bucket thresholds and Y-axis range).
    let fullScore: Double
    /// 当前图表类型
    /// Currently selected chart type.
    let chartType: ChartType
    /// compact 模式:隐藏所有数字标注、简化坐标轴(用于 mini chart 等小尺寸场景)
    /// Compact mode: hides numeric annotations and simplifies axes (for mini charts and similar small layouts).
    var compact: Bool = false
    /// 自定义主色(用于折线 / 柱状图等)
    /// Custom tint color (used for line / bar, etc.).
    var tintColor: Color = .accentColor

    // MARK: - 触屏选中状态(用于"手指放到表上显示数据点"交互)
    // MARK: - Touch selection state (for the "finger on chart shows data point" interaction)
    @State private var selectedGrade: Grade?
    @State private var selectedBucket: HistogramBucket?
    @State private var selectedBucketCount: Int = 0
    /// 触摸 X 坐标(chart 自身坐标系),用于驱动详情卡片横向跟随手指
    /// Touch X coordinate (chart-local), used to drive the detail card to follow the finger horizontally.
    @State private var touchX: CGFloat?

    var body: some View {
        Group {
            switch chartType {
            case .line:
                lineChart
            case .bar:
                barChart
            case .pie:
                pieChart
            case .scatter:
                scatterChart
            case .heatmap:
                heatmapChart
            case .histogram:
                histogramChart
            }
        }
        .chartLegend(compact ? .hidden : .automatic)
        .chartXAxis(compact ? .hidden : .automatic)
        .chartYAxis(compact ? .hidden : .automatic)
    }

    // MARK: - Line Chart
    // MARK: - 折线图

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(grades) { grade in
            LineMark(
                x: .value("Date", grade.date),
                y: .value("Score", grade.score)
            )
            .foregroundStyle(tintColor)
            .interpolationMethod(.linear)

            PointMark(
                x: .value("Date", grade.date),
                y: .value("Score", grade.score)
            )
            .foregroundStyle(scoreColor(grade.score, fullScore: fullScore))
            .symbol {
                let isSelected = selectedGrade?.id == grade.id
                Circle()
                    .fill(isSelected ? scoreColor(grade.score, fullScore: fullScore) : Color(.systemBackground))
                    .frame(width: isSelected ? 14 : 10, height: isSelected ? 14 : 10)
                    .overlay {
                        Circle()
                            .stroke(scoreColor(grade.score, fullScore: fullScore), lineWidth: isSelected ? 3 : 2)
                    }
                    .shadow(color: isSelected ? scoreColor(grade.score, fullScore: fullScore).opacity(0.5) : .clear, radius: 4)
            }
        }
    }

    @ViewBuilder
    private var lineChart: some View {
        let baseChart = Chart {
            lineMarks
        }
        .chartYScale(domain: 0...maxYDomain)

        if compact {
            baseChart
        } else {
            baseChart
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack {
                            // 1. 触摸点高亮 + 垂直引导线 + 数据点标签（不参与 hit test）
                            if let selected = selectedGrade,
                               let plotFrameAnchor = proxy.plotFrame {
                                let plot = geo[plotFrameAnchor]
                                if let xPos = proxy.position(forX: selected.date),
                                   let yPos = proxy.position(forY: selected.score) {
                                    Path { path in
                                        path.move(to: CGPoint(x: xPos, y: plot.minY))
                                        path.addLine(to: CGPoint(x: xPos, y: plot.maxY))
                                    }
                                    .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .allowsHitTesting(false)

                                    Circle()
                                        .stroke(scoreColor(selected.score, fullScore: fullScore), lineWidth: 2)
                                        .background(Circle().fill(Color(.systemBackground)))
                                        .frame(width: 16, height: 16)
                                        .position(x: xPos, y: yPos)
                                        .allowsHitTesting(false)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(Int(selected.score.rounded()))")
                                            .scaledFont(size: 11, weight: .bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule().fill(scoreColor(selected.score, fullScore: fullScore))
                                            )
                                    }
                                    .position(x: xPos, y: max(plot.minY + 14, yPos - 16))
                                    .allowsHitTesting(false)
                                }
                            }

                            // 2. 详情卡片（横向跟随手指 + 液态玻璃，不参与 hit test）
                            if let grade = selectedGrade, let touchX = touchX {
                                let clampedX = max(80, min(geo.size.width - 80, touchX))
                                ChartCalloutCard(grade: grade, fullScore: fullScore)
                                    .position(x: clampedX, y: 36)
                                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                                    .allowsHitTesting(false)
                            }

                            // 3. 全图触屏交互层（顶层，确保整张图都吃 hit test，并把事件透传到手势）
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard let plotFrameAnchor = proxy.plotFrame else { return }
                                            let plot = geo[plotFrameAnchor]
                                            let xInPlot = value.location.x - plot.minX
                                            if let date: Date = proxy.value(atX: xInPlot) {
                                                selectedGrade = nearestGrade(to: date)
                                                touchX = value.location.x
                                            }
                                        }
                                        .onEnded { _ in
                                            selectedGrade = nil
                                            touchX = nil
                                        }
                                )
                        }
                        .animation(.easeInOut(duration: 0.12), value: touchX)
                    }
                }
        }
    }

    // MARK: - Bar Chart
    // 使用 BarMark(x:y:) 让 SwiftUI Charts 按数据密度自动分配柱宽，
    // 既不会过细也不会变成横向短条。少量数据时柱子粗，数据多时柱子变细。

    @ViewBuilder
    private var barChart: some View {
        let baseChart = Chart {
            ForEach(grades) { grade in
                let isSelected = selectedGrade?.id == grade.id
                BarMark(
                    x: .value("Date", grade.date),
                    y: .value("Score", grade.score)
                )
                .foregroundStyle(tintColor.opacity(isSelected ? 1.0 : 0.85))
                .cornerRadius(3)
            }
        }
        .chartYScale(domain: 0...maxYDomain)

        if compact {
            baseChart
        } else {
            baseChart
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack {
                            // 1. 垂直引导线 + 柱顶标签（不参与 hit test）
                            if let selected = selectedGrade,
                               let plotFrameAnchor = proxy.plotFrame {
                                let plot = geo[plotFrameAnchor]
                                if let xPos = proxy.position(forX: selected.date) {
                                    Path { path in
                                        path.move(to: CGPoint(x: xPos, y: plot.minY))
                                        path.addLine(to: CGPoint(x: xPos, y: plot.maxY))
                                    }
                                    .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .allowsHitTesting(false)

                                    VStack(spacing: 0) {
                                        Text("\(Int(selected.score.rounded()))")
                                            .scaledFont(size: 11, weight: .bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule().fill(scoreColor(selected.score, fullScore: fullScore))
                                            )
                                    }
                                    .position(x: xPos, y: max(plot.minY + 14, (proxy.position(forY: selected.score) ?? plot.minY) - 16))
                                    .allowsHitTesting(false)
                                }
                            }

                            // 2. 详情卡片（不参与 hit test）
                            if let grade = selectedGrade, let touchX = touchX {
                                let clampedX = max(80, min(geo.size.width - 80, touchX))
                                ChartCalloutCard(grade: grade, fullScore: fullScore)
                                    .position(x: clampedX, y: 36)
                                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                                    .allowsHitTesting(false)
                            }

                            // 3. 全图触屏交互层（顶层）
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard let plotFrameAnchor = proxy.plotFrame else { return }
                                            let plot = geo[plotFrameAnchor]
                                            let xInPlot = value.location.x - plot.minX
                                            if let date: Date = proxy.value(atX: xInPlot) {
                                                selectedGrade = nearestGrade(to: date)
                                                touchX = value.location.x
                                            }
                                        }
                                        .onEnded { _ in
                                            selectedGrade = nil
                                            touchX = nil
                                        }
                                )
                        }
                        .animation(.easeInOut(duration: 0.12), value: touchX)
                    }
                }
        }
    }

    // MARK: - Pie Chart
    // 按分数段占比统计：≥90, 80-89, 70-79, 60-69, <60

    struct ScoreRange: Identifiable {
        let id = UUID()
        let label: String
        let range: ClosedRange<Double>
        let color: Color
    }

    static let scoreRanges: [ScoreRange] = [
        ScoreRange(label: "A (≥90)", range: 90...1000, color: .green),
        ScoreRange(label: "B (80-89)", range: 80...89.99, color: .blue),
        ScoreRange(label: "C (70-79)", range: 70...79.99, color: .yellow),
        ScoreRange(label: "D (60-69)", range: 60...69.99, color: .orange),
        ScoreRange(label: "F (<60)", range: 0...59.99, color: .red),
    ]

    private var pieBuckets: [(range: ScoreRange, count: Int)] {
        Self.scoreRanges.map { bucket in
            let count = grades.filter { bucket.range.contains($0.score) }.count
            return (bucket, count)
        }
    }

    private var pieChart: some View {
        let visible = pieBuckets.filter { $0.count > 0 }
        let total = max(visible.reduce(0) { $0 + $1.count }, 1)
        return Chart(visible, id: \.range.id) { bucket in
            SectorMark(
                angle: .value("Count", bucket.count),
                innerRadius: .ratio(0.55),
                angularInset: 1.5
            )
            .foregroundStyle(bucket.range.color)
            .annotation(position: .overlay) {
                if !compact, bucket.count > 0 {
                    let percent = Double(bucket.count) / Double(total) * 100
                    // 占比 < 8% 的扇区不显示文字（避免重叠），但保留在最外圈
                    if percent >= 8 {
                        Text("\(Int(percent.rounded()))%")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .chartLegend(compact ? .hidden : .visible)
        .chartLegend(position: .bottom, alignment: .center, spacing: 8) {
            HStack(spacing: 12) {
                ForEach(visible, id: \.range.id) { bucket in
                    let percent = Double(bucket.count) / Double(total) * 100
                    HStack(spacing: 4) {
                        Circle()
                            .fill(bucket.range.color)
                            .frame(width: 8, height: 8)
                        Text("\(bucket.range.label) · \(Int(percent.rounded()))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Scatter Chart

    @ViewBuilder
    private var scatterChart: some View {
        let baseChart = Chart {
            ForEach(grades) { grade in
                let isSelected = selectedGrade?.id == grade.id
                PointMark(
                    x: .value("Date", grade.date),
                    y: .value("Score", grade.score)
                )
                .foregroundStyle(scoreColor(grade.score, fullScore: fullScore))
                .symbolSize(isSelected ? 200 : 80)
            }
        }
        .chartYScale(domain: 0...maxYDomain)

        if compact {
            baseChart
        } else {
            baseChart
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack {
                            // 1. 垂直引导线 + 数据点标签（不参与 hit test）
                            if let selected = selectedGrade,
                               let plotFrameAnchor = proxy.plotFrame {
                                let plot = geo[plotFrameAnchor]
                                if let xPos = proxy.position(forX: selected.date),
                                   let yPos = proxy.position(forY: selected.score) {
                                    Path { path in
                                        path.move(to: CGPoint(x: xPos, y: plot.minY))
                                        path.addLine(to: CGPoint(x: xPos, y: plot.maxY))
                                    }
                                    .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .allowsHitTesting(false)

                                    VStack(spacing: 0) {
                                        Text("\(Int(selected.score.rounded()))")
                                            .scaledFont(size: 11, weight: .bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule().fill(scoreColor(selected.score, fullScore: fullScore))
                                            )
                                    }
                                    .position(x: xPos, y: max(plot.minY + 14, yPos - 16))
                                    .allowsHitTesting(false)
                                }
                            }

                            // 2. 详情卡片（不参与 hit test）
                            if let grade = selectedGrade, let touchX = touchX {
                                let clampedX = max(80, min(geo.size.width - 80, touchX))
                                ChartCalloutCard(grade: grade, fullScore: fullScore)
                                    .position(x: clampedX, y: 36)
                                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                                    .allowsHitTesting(false)
                            }

                            // 3. 全图触屏交互层（顶层）
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard let plotFrameAnchor = proxy.plotFrame else { return }
                                            let plot = geo[plotFrameAnchor]
                                            let xInPlot = value.location.x - plot.minX
                                            if let date: Date = proxy.value(atX: xInPlot) {
                                                selectedGrade = nearestGrade(to: date)
                                                touchX = value.location.x
                                            }
                                        }
                                        .onEnded { _ in
                                            selectedGrade = nil
                                            touchX = nil
                                        }
                                )
                        }
                        .animation(.easeInOut(duration: 0.12), value: touchX)
                    }
                }
        }
    }

    // MARK: - Heatmap
    // 把成绩按 周次(纵轴) x 星期(横轴) 聚合，每个格子的颜色深浅代表当天的「平均分归一化值」

    struct HeatCell: Identifiable {
        let id = UUID()
        let weekIndex: Int
        let weekday: Int
        let intensity: Double   // 0...1，归一化分数
        let label: String       // 显示在该格子上
    }

    private var heatmapCells: [HeatCell] {
        guard !grades.isEmpty else { return [] }
        let calendar = Calendar(identifier: .gregorian)
        let minDate = grades.map(\.date).min() ?? Date()
        let maxDate = grades.map(\.date).max() ?? Date()
        // 周次：相对于最早日期的整周差
        func weekIndex(of date: Date) -> Int {
            let comps = calendar.dateComponents([.day], from: minDate, to: date)
            return max(0, (comps.day ?? 0) / 7)
        }
        // 限制最多展示 12 周，避免单元格过密
        let weekCount = min(12, weekIndex(of: maxDate) + 1)
        var buckets: [String: [Double]] = [:]
        for grade in grades {
            let wd = calendar.component(.weekday, from: grade.date) // 1=Sun ... 7=Sat
            let wi = weekIndex(of: grade.date)
            let key = "\(wi)-\(wd)"
            buckets[key, default: []].append(grade.score)
        }
        let allScores = grades.map(\.score)
        let minScore = allScores.min() ?? 0
        let maxScore = allScores.max() ?? 1
        let span = max(0.0001, maxScore - minScore)
        var cells: [HeatCell] = []
        for wi in 0..<weekCount {
            for wd in 1...7 {
                let key = "\(wi)-\(wd)"
                if let scores = buckets[key], !scores.isEmpty {
                    let avg = scores.reduce(0, +) / Double(scores.count)
                    let intensity = (avg - minScore) / span
                    let label: String
                    if scores.count == 1, let first = scores.first {
                        label = String(format: "%.0f", first)
                    } else {
                        label = String(format: "%.0f×%d", avg, scores.count)
                    }
                    cells.append(HeatCell(weekIndex: wi, weekday: wd, intensity: intensity, label: label))
                }
            }
        }
        return cells
    }

    private var heatmapChart: some View {
        let cells = heatmapCells
        let weekCount = max(1, (cells.map(\.weekIndex).max() ?? 0) + 1)
        return Chart {
            ForEach(cells) { cell in
                RectangleMark(
                    x: .value("Weekday", cell.weekday),
                    y: .value("Week", -cell.weekIndex)
                )
                .foregroundStyle(by: .value("Score", cell.intensity))
            }
        }
        .chartForegroundStyleScale(range: Gradient(colors: [
            Color.red.opacity(0.25),
            Color.orange.opacity(0.5),
            Color.yellow.opacity(0.7),
            Color.green.opacity(0.85)
        ]))
        .chartXScale(domain: 0.5...7.5)
        .chartYScale(domain: Double(-weekCount + 1)...0.5)
        .chartXAxis {
            AxisMarks(values: [1, 2, 3, 4, 5, 6, 7]) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text(weekdayLabel(v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: Array(0..<weekCount).map { Double(-$0) }) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("W\(-Int(v) + 1)")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            if compact {
                EmptyView()
            } else {
                GeometryReader { geo in
                    ForEach(cells) { cell in
                        if let xPos = proxy.position(forX: cell.weekday),
                           let yPos = proxy.position(forY: Double(-cell.weekIndex)) {
                            Text(cell.label)
                                .scaledFont(size: 8, weight: .medium)
                                .foregroundColor(cell.intensity > 0.5 ? .white : .primary)
                                .position(x: xPos, y: yPos)
                        }
                    }
                }
            }
        }
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        let symbols = Calendar(identifier: .gregorian).shortWeekdaySymbols // Sun...Sat
        guard weekday >= 1, weekday <= symbols.count else { return "" }
        return symbols[weekday - 1]
    }

    // MARK: - Frequency Histogram
    // 按 20% 得分率分组统计次数（频数直方图）。
    // 得分率 = score / fullScore，区间：[0,20%) [20,40%) [40,60%) [60,80%) [80,100%]
    // X 轴：分数段（百分比）；Y 轴：落在该段内的成绩次数。

    struct HistogramBucket: Identifiable {
        let id: Int            // 0...4
        let label: String      // "0-20%" 等
        let lower: Double      // 包含
        let upper: Double      // 不包含（最后一档包含）
        let inclusiveUpper: Bool
        let color: Color
    }

    static let histogramBuckets: [HistogramBucket] = [
        HistogramBucket(id: 0, label: "0–20%",   lower: 0.0, upper: 0.2,   inclusiveUpper: false, color: .red),
        HistogramBucket(id: 1, label: "20–40%",  lower: 0.2, upper: 0.4,   inclusiveUpper: false, color: .orange),
        HistogramBucket(id: 2, label: "40–60%",  lower: 0.4, upper: 0.6,   inclusiveUpper: false, color: .yellow),
        HistogramBucket(id: 3, label: "60–80%",  lower: 0.6, upper: 0.8,   inclusiveUpper: false, color: .blue),
        HistogramBucket(id: 4, label: "80–100%", lower: 0.8, upper: 1.001, inclusiveUpper: true,  color: .green),
    ]

    private var histogramData: [(bucket: HistogramBucket, count: Int)] {
        let safeFull = fullScore > 0 ? fullScore : 100
        return Self.histogramBuckets.map { bucket in
            let count = grades.filter { g in
                let rate = g.score / safeFull
                if bucket.inclusiveUpper {
                    return rate >= bucket.lower && rate <= bucket.upper
                } else {
                    return rate >= bucket.lower && rate < bucket.upper
                }
            }.count
            return (bucket, count)
        }
    }

    @ViewBuilder
    private var histogramChart: some View {
        let data = histogramData
        let maxCount = max(data.map(\.count).max() ?? 0, 1)
        let step = max(1, Int(ceil(Double(maxCount) / 4.0)))
        let yValues = stride(from: 0, through: maxCount, by: step).map { $0 }
        // 半透明柱身 + 顶端固定 0.3 数据单位的实色硬边小条。
        // 在数据空间内画，避免 chartOverlay + GeometryReader 的坐标偏移问题。
        let capThickness: Double = 0.3
        let visible = data.filter { $0.count > 0 }
        let baseChart = Chart {
            // 50% 透明的柱身
            ForEach(data, id: \.bucket.id) { item in
                RectangleMark(
                    xStart: .value("Start", Double(item.bucket.id)),
                    xEnd: .value("End", Double(item.bucket.id) + 1),
                    yStart: .value("Zero", 0),
                    yEnd: .value("Count", item.count)
                )
                .foregroundStyle(item.bucket.color.opacity(0.5))
                .cornerRadius(2)
            }
            // 顶端实色硬边小条
            ForEach(visible, id: \.bucket.id) { item in
                RectangleMark(
                    xStart: .value("CapStart", Double(item.bucket.id)),
                    xEnd: .value("CapEnd", Double(item.bucket.id) + 1),
                    yStart: .value("CapLow", max(0, Double(item.count) - capThickness)),
                    yEnd: .value("CapHigh", Double(item.count))
                )
                .foregroundStyle(item.bucket.color)
            }
            // 频数标签（compact 模式隐藏）
            if !compact {
                ForEach(visible, id: \.bucket.id) { item in
                    PointMark(
                        x: .value("LabelX", Double(item.bucket.id) + 0.5),
                        y: .value("LabelY", Double(item.count))
                    )
                    .annotation(position: .top, alignment: .center) {
                        Text("\(item.count)")
                            .font(.caption2.bold())
                            .foregroundColor(.primary)
                    }
                    .opacity(0) // 仅用于承载 annotation，不显示点
                }
            }
        }
        .chartXAxis {
            let n = data.count
            let centers: [Double] = (0..<n).map { Double($0) + 0.5 }
            AxisMarks(position: .bottom, values: centers) { value in
                AxisValueLabel {
                    if let idx = value.as(Double.self).map({ Int($0.rounded()) }),
                       idx >= 0, idx < data.count {
                        Text(data[idx].bucket.label)
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yValues) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXScale(domain: 0...Double(data.count))
        .chartYScale(domain: 0...Double(maxCount) * 1.15)

        if compact {
            baseChart
        } else {
            baseChart
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack {
                            // 1. 垂直引导线 + 频数胶囊（不参与 hit test）
                            if let bucket = selectedBucket,
                               let plotFrameAnchor = proxy.plotFrame {
                                let plot = geo[plotFrameAnchor]
                                let centerX = Double(bucket.id) + 0.5
                                if let xPos = proxy.position(forX: centerX) {
                                    Path { path in
                                        path.move(to: CGPoint(x: xPos, y: plot.minY))
                                        path.addLine(to: CGPoint(x: xPos, y: plot.maxY))
                                    }
                                    .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .allowsHitTesting(false)

                                    VStack(spacing: 0) {
                                        Text("\(selectedBucketCount) 次")
                                            .scaledFont(size: 11, weight: .bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule().fill(bucket.color)
                                            )
                                    }
                                    .position(x: xPos, y: max(plot.minY + 14, (proxy.position(forY: Double(selectedBucketCount)) ?? plot.minY) - 16))
                                    .allowsHitTesting(false)
                                }
                            }

                            // 2. 全图触屏交互层（顶层）
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard let plotFrameAnchor = proxy.plotFrame else { return }
                                            let plot = geo[plotFrameAnchor]
                                            let xInPlot = value.location.x - plot.minX
                                            if let xValue: Double = proxy.value(atX: xInPlot) {
                                                if let nearest = data.min(by: {
                                                    abs(Double($0.bucket.id) + 0.5 - xValue) < abs(Double($1.bucket.id) + 0.5 - xValue)
                                                }) {
                                                    selectedBucket = nearest.bucket
                                                    selectedBucketCount = nearest.count
                                                    touchX = value.location.x
                                                }
                                            }
                                        }
                                        .onEnded { _ in
                                            selectedBucket = nil
                                            selectedBucketCount = 0
                                            touchX = nil
                                        }
                                )
                        }
                        .animation(.easeInOut(duration: 0.12), value: touchX)
                    }
                }
        }
    }

    // MARK: - Helpers

    /// Y 轴最大值：根据满分与最高成绩取较大者，并留 5% 顶部余量
    private var maxYDomain: Double {
        let maxScore = grades.map(\.score).max() ?? fullScore
        return max(maxScore, fullScore) * 1.05
    }

    /// 找到与给定日期最接近的 Grade（按时间距离取最小）
    private func nearestGrade(to date: Date) -> Grade? {
        grades.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }
}

/// Apple Health 风格的数据点提示卡片（iOS 26+ 使用液态玻璃）
private struct ChartCalloutCard: View {
    let grade: Grade
    let fullScore: Double

    private var ratePercent: Int {
        guard fullScore > 0 else { return 0 }
        return Int((grade.score / fullScore * 100).rounded())
    }

    private var dateText: String {
        grade.date.formatted(date: .medium, time: .none)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(grade.subject.uppercased())
                .scaledFont(size: 10, weight: .semibold)
                .tracking(0.5)
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(grade.score.rounded()))")
                    .scaledFont(size: 28, weight: .bold, design: .rounded)
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                Text("/ \(Int(fullScore))")
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundColor(.secondary)
            }
            Text(dateText)
                .scaledFont(size: 12, weight: .medium)
                .foregroundColor(.secondary)
            if !grade.examName.isEmpty {
                Text(grade.examName)
                    .scaledFont(size: 10)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(glassSurface(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    }

    /// iOS 26+ 液态玻璃背景；老版本回退到 .regularMaterial
    @ViewBuilder
    private func glassSurface(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

#Preview {
    let sample: [Grade] = (0..<20).compactMap { i in
        guard let date = Calendar.current.date(byAdding: .day, value: -i * 3, to: Date()) else { return nil }
        return Grade(
            subject: "Math",
            score: 70 + Double.random(in: -15...20),
            rawScore: nil,
            ranking: i % 2 == 0 ? Int.random(in: 1...50) : nil,
            importance: 3,
            image: nil,
            imageFileName: nil,
            date: date,
            examName: "Exam \(i)",
            fullScore: 100
        )
    }
    VStack {
        ForEach(ChartType.allCases) { type in
            VStack(alignment: .leading) {
                Text(type.localizedDisplayName).font(.headline)
                TrendChartView(grades: sample, fullScore: 100, chartType: type)
                    .frame(height: 200)
                    .padding()
            }
        }
    }
}