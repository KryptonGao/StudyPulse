//
//  ExamCalendarView.swift
//  StudyPulse
//
//  考试月历视图:按日期标点,多日考试跨日高亮,考试 / 综合考试 / 作业 / 阅读四类条目同屏。
//  Exam monthly calendar view: dots per date, multi-day exams highlighted across days.
//
//  v1.x:同时展示考试、作业、阅读材料三类条目。
//  v1.x: shows exams, homework, and reading tasks together.
//
//  Phase 3 拆分 (2026-07-14):原 1008 行单文件 → orchestrator 留本文件,
//  拆出 3 个独立子文件:
//  - ExamCalendarModels.swift      (CalendarItem / CalendarItemKind / CalendarItemKindFilter / Calendar 扩展)
//  - ExamCalendarDayCell.swift     (单日 cell:支持多日 span bar / 单日 dots)
//  - ExamCalendarItemRow.swift     (选中日底部面板的单个事件行)
//
//  本文件只剩:主 View 编排 + 数据聚合 + 玻璃 header / 面板 + 动画状态机 + 点击回调。
//

import SwiftUI

/// 考试 / 任务月历视图
/// Exam / task monthly calendar view.
struct ExamCalendarView: View {
    @Environment(RepositoryContainer.self) private var container

    /// 当前显示月份(动画过程中已提前切为目标月)
    /// Currently displayed month (already swapped to the target month during animation).
    @State private var displayedMonth: Date = Calendar.current.startOfMonth(for: Date())
    /// 正在滑出的旧月份(nil 表示无动画中)
    /// Outgoing month being slid out (nil when no animation is running).
    @State private var outgoingMonth: Date? = nil
    /// 新网格滑入进度(1 → 0,使用弹簧)
    /// Incoming grid slide-in progress (1 → 0, spring).
    @State private var incomingProgress: CGFloat = 0
    /// 旧网格滑出进度(1 → 0,使用 easeOut 防止回弹)
    /// Outgoing grid slide-out progress (1 → 0, easeOut to avoid bounce).
    @State private var outgoingProgress: CGFloat = 0
    /// 滑动方向:1 表示下一个月从底部滑入,-1 表示上一个月从顶部滑入
    /// Slide direction: 1 = next month slides in from the bottom; -1 = previous from the top.
    @State private var slideDirection: Int = 0
    /// 用户当前选中的日期
    /// User-selected date.
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// 点击单科考试行的回调
    /// Callback for tapping a single-subject exam row.
    var onSelectExam: ((Exam) -> Void)?
    /// 点击综合考试行的回调
    /// Callback for tapping a comprehensive exam row.
    var onSelectComprehensive: ((comprehensiveExam) -> Void)?
    /// 点击作业 / 阅读材料行的回调
    /// Callback for tapping a homework / reading row.
    var onSelectTask: ((TaskItem) -> Void)?

    /// 类型过滤(默认全部;考试 / 作业 / 阅读可单独筛选)
    /// Type filter (default: all; can filter by exam / homework / reading).
    var typeFilter: CalendarItemKindFilter = .all

    // MARK: - Data Aggregation / 数据聚合

    /// 当前过滤后所有条目(单科考试 / 综合考试 / 作业 / 阅读)
    /// All items under the current type filter.
    private var allItems: [CalendarItem] {
        var items: [CalendarItem] = []

        if typeFilter == .all || typeFilter == .exam {
            for exam in container.examRepo.examSets {
                let endDate = exam.examEndDate ?? exam.examDate
                items.append(CalendarItem(
                    id: exam.id,
                    kind: .exam,
                    title: exam.name,
                    subject: exam.subject,
                    importance: exam.importance,
                    isCompleted: false,
                    start: Calendar.current.startOfDay(for: exam.examDate),
                    end: Calendar.current.startOfDay(for: endDate),
                    isMultiDay: exam.examEndDate != nil,
                    exam: exam,
                    comprehensiveExam: nil,
                    taskItem: nil
                ))
            }
            for exam in container.examRepo.comprehensiveExamSets {
                let endDate = exam.examEndDate ?? exam.examDate
                items.append(CalendarItem(
                    id: exam.id,
                    kind: .comprehensiveExam,
                    title: exam.name,
                    subject: exam.subject.joined(separator: ", "),
                    importance: exam.importance,
                    isCompleted: false,
                    start: Calendar.current.startOfDay(for: exam.examDate),
                    end: Calendar.current.startOfDay(for: endDate),
                    isMultiDay: exam.examEndDate != nil,
                    exam: nil,
                    comprehensiveExam: exam,
                    taskItem: nil
                ))
            }
        }

        if typeFilter == .all || typeFilter == .homework {
            for task in container.taskRepo.taskItems where task.type == .homework && !task.isCompleted {
                items.append(CalendarItem(
                    id: task.id,
                    kind: .homework,
                    title: task.title,
                    subject: task.subject,
                    importance: task.importance,
                    isCompleted: task.isCompleted,
                    start: Calendar.current.startOfDay(for: task.dueDate),
                    end: Calendar.current.startOfDay(for: task.dueDate),
                    isMultiDay: false,
                    exam: nil,
                    comprehensiveExam: nil,
                    taskItem: task
                ))
            }
        }

        if typeFilter == .all || typeFilter == .reading {
            for task in container.taskRepo.taskItems where task.type == .reading && !task.isCompleted {
                items.append(CalendarItem(
                    id: task.id,
                    kind: .reading,
                    title: task.title,
                    subject: task.subject,
                    importance: task.importance,
                    isCompleted: task.isCompleted,
                    start: Calendar.current.startOfDay(for: task.dueDate),
                    end: Calendar.current.startOfDay(for: task.dueDate),
                    isMultiDay: false,
                    exam: nil,
                    comprehensiveExam: nil,
                    taskItem: task
                ))
            }
        }

        return items
    }

    /// 当天(selectedDate)所在的条目
    /// Items that fall on the selected date.
    private var itemsOnSelectedDate: [CalendarItem] {
        let day = Calendar.current.startOfDay(for: selectedDate)
        return allItems
            .filter { $0.contains(day: day) }
            .sorted { lhs, rhs in
                // 重要度降序,再按开始时间升序
                // Sort: importance DESC, then start time ASC.
                if lhs.importance != rhs.importance { return lhs.importance > rhs.importance }
                return lhs.start < rhs.start
            }
    }

    // MARK: - Body / 主体

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                monthGridContainer
                glassHeaderLayer
            }
            .frame(height: calendarSectionHeight)

            glassBottomPanel
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 月历区域固定高度:顶部 header + 6 行日期格子
    private var calendarSectionHeight: CGFloat {
        headerTotalFixedHeight + 6 * 52 + 8
    }

    // MARK: - Month Grid / 月份网格

    private var monthGridContainer: some View {
        GeometryReader { geo in
            let clampedIncoming = max(0, min(1, incomingProgress))
            let clampedOutgoing = max(0, min(1, outgoingProgress))
            ZStack {
                monthGrid(for: displayedMonth)
                    .offset(y: CGFloat(slideDirection) * clampedIncoming * geo.size.height)

                if let outgoingMonth {
                    monthGrid(for: outgoingMonth)
                        .offset(y: -CGFloat(slideDirection) * (1 - clampedOutgoing) * geo.size.height)
                        .opacity(clampedOutgoing < 0.05 ? 0 : 1)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(monthSwipeGesture)
        }
        .padding(.top, headerTotalFixedHeight)
    }

    private var monthSwipeGesture: some Gesture {
        // 垂直滑动 = 切换月份(向上 = 下个月,向下 = 上个月)
        // Vertical swipe switches month: up = next, down = previous.
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onEnded { value in
                let vertical = value.translation.height
                if vertical < -50 {
                    shiftMonth(by: 1)
                } else if vertical > 50 {
                    shiftMonth(by: -1)
                }
            }
    }

    private func monthGrid(for month: Date) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let days = Calendar.current.monthGridDays(for: month)
        let today = Calendar.current.startOfDay(for: Date())

        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                let day = Calendar.current.startOfDay(for: date)
                let inMonth = Calendar.current.isDate(date, equalTo: month, toGranularity: .month)
                let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                let isToday = Calendar.current.isDate(day, inSameDayAs: today)
                let dayItems = allItems.filter { $0.contains(day: day) }

                ExamCalendarDayCell(
                    date: day,
                    inMonth: inMonth,
                    isSelected: isSelected,
                    isToday: isToday,
                    items: dayItems
                )
                .frame(height: 52)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedDate = day
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Top Glass Header / 顶部玻璃层

    /// 玻璃背景与屏幕左右边缘之间的内缩量
    /// Horizontal inset of the glass background from the screen edges.
    private let glassEdgeInset: CGFloat = 16
    /// 顶部玻璃层固定总高度(与 monthGridContainer 的 .padding(.top) 对齐)
    /// Total fixed height of the top glass layer (aligned with monthGridContainer's top padding).
    private let headerTotalFixedHeight: CGFloat = 88

    private var glassHeaderLayer: some View {
        ZStack(alignment: .top) {
            // Independent glass background layer, sizing & inset controlled separately
            Group {
                if #available(iOS 26, *) {
                    Color.clear.glassEffect(.regular, in: headerGlassShape)
                } else {
                    headerGlassShape.fill(.regularMaterial)
                }
            }
            // Constrain glass height first to prevent vertical overflow into date rows
            .frame(height: headerTotalFixedHeight)
            // Lock horizontal inset on glass itself to avoid full-width stretch
            .padding(.horizontal, glassEdgeInset)
            // Only extend top edge to status bar, no vertical expansion
            .ignoresSafeArea(edges: .top)

            // Foreground header content, matching horizontal inset of glass background
            VStack(spacing: 0) {
                monthHeader
                weekdayHeader
            }
            .padding(.bottom, 8)
            .padding(.horizontal, glassEdgeInset)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var headerGlassShape: some Shape {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    private var monthHeader: some View {
        HStack(spacing: 8) {
            glassCircleButton(systemName: "chevron.left") {
                shiftMonth(by: -1)
            }
            .accessibilityLabel(Text("Previous Month".localized()))

            Spacer()

            Text(displayedMonth, format: .dateTime.year().month(.wide))
                .font(.headline)
                .foregroundColor(Color(.label))

            Spacer()

            glassCircleButton(systemName: "chevron.right") {
                shiftMonth(by: 1)
            }
            .accessibilityLabel(Text("Next Month".localized()))

            glassPillButton(title: "Today".localized()) {
                let today = Date()
                let todayMonth = Calendar.current.startOfMonth(for: today)
                let direction = todayMonth > displayedMonth ? 1 : -1
                animateToMonth(todayMonth, direction: direction)
                selectedDate = Calendar.current.startOfDay(for: today)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func glassCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Color(.label))
                .frame(width: 32, height: 32)
                .background {
                    if #available(iOS 26, *) {
                        Color.clear.glassEffect(.regular, in: Circle())
                    } else {
                        Circle().fill(.regularMaterial)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemName.contains("left") ? "a11y.previous".localized() : "a11y.next".localized())
    }

    @ViewBuilder
    private func glassPillButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(Color(.systemBlue))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if #available(iOS 26, *) {
                        Color.clear.glassEffect(.regular, in: Capsule())
                    } else {
                        Capsule().fill(Color(.systemBlue).opacity(0.12))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var weekdayHeader: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return HStack(spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color(.secondaryLabel))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    // MARK: - Bottom Glass Panel / 底部玻璃详情面板

    private var glassBottomPanel: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 6)

            selectedDayPanel
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background {
                    if #available(iOS 26, *) {
                        Color.clear.glassEffect(.regular, in: bottomGlassShape)
                    } else {
                        bottomGlassShape.fill(.regularMaterial)
                    }
                }
        }
        .padding(.horizontal, glassEdgeInset)
        .padding(.bottom, glassEdgeInset)
    }

    private var bottomGlassShape: some Shape {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    @ViewBuilder
    private var selectedDayPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedDate, format: .dateTime.weekday(.wide).month().day())
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color(.label))
                Spacer()
                if !itemsOnSelectedDate.isEmpty {
                    Text("\(itemsOnSelectedDate.count) " + "items".localized())
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color(.systemBlue).opacity(0.15))
                        )
                        .foregroundColor(Color(.systemBlue))
                }
            }

            if itemsOnSelectedDate.isEmpty {
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.title3)
                            .foregroundColor(Color(.tertiaryLabel))
                        Text("No items on this day".localized())
                            .font(.caption)
                            .foregroundColor(Color(.secondaryLabel))
                    }
                    Spacer()
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(itemsOnSelectedDate) { item in
                            ExamCalendarItemRow(item: item, referenceDate: selectedDate)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let underlying = item.exam {
                                        onSelectExam?(underlying)
                                    } else if let underlying = item.comprehensiveExam {
                                        onSelectComprehensive?(underlying)
                                    } else if let underlying = item.taskItem {
                                        onSelectTask?(underlying)
                                    }
                                }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    // MARK: - Navigation / 跳转

    private func shiftMonth(by offset: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        animateToMonth(Calendar.current.startOfMonth(for: next), direction: offset)
    }

    private func animateToMonth(_ target: Date, direction: Int) {
        guard outgoingMonth == nil else { return }

        outgoingMonth = displayedMonth
        displayedMonth = target
        slideDirection = direction
        incomingProgress = 1
        outgoingProgress = 1

        withAnimation(.interpolatingSpring(stiffness: 140, damping: 24)) {
            incomingProgress = 0
        }
        withAnimation(.easeOut(duration: 0.32)) {
            outgoingProgress = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            outgoingMonth = nil
            slideDirection = 0
            incomingProgress = 0
            outgoingProgress = 0
        }
    }
}

// MARK: - Preview / 独立预览入口

#Preview("With Sample Data") {
    ExamCalendarView()
        .environment(PreviewSupport.makeSampleContainer())
}

#Preview("Empty") {
    ExamCalendarView()
        .environment(RepositoryContainer())
}

#Preview("Dark Mode") {
    ExamCalendarView()
        .environment(PreviewSupport.makeSampleContainer())
        .preferredColorScheme(.dark)
}

@MainActor
private enum PreviewSupport {
    static func makeSampleContainer() -> RepositoryContainer {
        let container = RepositoryContainer()
        container.examRepo.add(single: sampleExams, comprehensive: sampleComprehensiveExams)
        container.taskRepo.add(sampleTasks)
        return container
    }

    private static var sampleExams: [Exam] {
        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.startOfMonth(for: now)
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        func date(day: Int, hour: Int = 9) -> Date {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            return calendar.date(from: components) ?? monthStart
        }

        return [
            Exam(
                name: "Math Quiz",
                date: date(day: 5, hour: 10),
                importance: 3,
                subject: "Mathematics",
                examName: "Chapter 3 Quiz",
                masteryDegree: 60
            ),
            Exam(
                name: "Physics Midterm",
                date: date(day: 12, hour: 8),
                importance: 5,
                subject: "Physics",
                examName: "Midterm",
                masteryDegree: 45
            ),
            Exam(
                name: "Final Week — 3 Day Block",
                date: date(day: 18, hour: 9),
                importance: 5,
                subject: "Chemistry",
                examName: "Final Block",
                masteryDegree: 30
            ).withExamEndDate(date(day: 20, hour: 17)),
            Exam(
                name: "English Oral",
                date: date(day: 22, hour: 14),
                importance: 2,
                subject: "English",
                examName: "Speaking Test",
                masteryDegree: 75
            ),
            Exam(
                name: "History Pop Quiz",
                date: date(day: 26, hour: 11),
                importance: 1,
                subject: "History",
                examName: "Surprise Quiz",
                masteryDegree: 80
            )
        ]
    }

    private static var sampleComprehensiveExams: [comprehensiveExam] {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        func date(day: Int) -> Date {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = 9
            return calendar.date(from: components) ?? now
        }

        return [
            comprehensiveExam(
                name: "Midterm Week",
                date: date(day: 8),
                importance: 4,
                subject: ["Mathematics", "Physics", "Chemistry"],
                examName: "Midterm",
                masteryDegree: 55
            ).withExamEndDate(date(day: 10)),
            comprehensiveExam(
                name: "Liberal Arts Final",
                date: date(day: 28),
                importance: 5,
                subject: ["History", "Politics", "Geography"],
                examName: "Final",
                masteryDegree: 40
            )
        ]
    }

    private static var sampleTasks: [TaskItem] {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        func date(day: Int) -> Date {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = 18
            return calendar.date(from: components) ?? now
        }

        return [
            TaskItem(
                title: "Ch.3 Exercises 1-20",
                type: .homework,
                dueDate: date(day: 6),
                reminderDate: date(day: 5),
                subject: "Mathematics",
                importance: 3,
                notes: "All problems from sections 3.1 - 3.3"
            ),
            TaskItem(
                title: "Read Physics Ch.5",
                type: .reading,
                dueDate: date(day: 9),
                reminderDate: date(day: 8),
                subject: "Physics",
                importance: 2,
                notes: "Read sections 5.1 - 5.4 and take notes"
            ),
            TaskItem(
                title: "Lab Report Draft",
                type: .homework,
                dueDate: date(day: 14),
                reminderDate: date(day: 13),
                subject: "Chemistry",
                importance: 4
            ),
            TaskItem(
                title: "History Reading List",
                type: .reading,
                dueDate: date(day: 24),
                reminderDate: date(day: 23),
                subject: "History",
                importance: 2
            )
        ]
    }
}

private extension Exam {
    func withExamEndDate(_ end: Date) -> Exam {
        var copy = self
        copy.examEndDate = end
        return copy
    }
}

private extension comprehensiveExam {
    func withExamEndDate(_ end: Date) -> comprehensiveExam {
        var copy = self
        copy.examEndDate = end
        return copy
    }
}
