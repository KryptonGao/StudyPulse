//
//  DiaryCalendarView.swift
//  StudyPulse
//
//  学习日记月历视图:参照 ExamCalendarView 的成熟模式
//  (动画 / 7×6 网格 / 玻璃 header / 玻璃底部 panel),
//  数据层改用 `container.diaryRepo.diaryEntries`。
//
//  旧实现的 bug:cell 是正方形 + VStack(数字 + emoji),垂直空间被 emoji
//  挤压时数字被截断显示 "..."。新实现固定 cell 高度 52pt,数字 26pt 圆
//  始终居中,emoji 在圆下方单独占 13pt,互不挤压。
//
//  Diary monthly calendar view: mirrors the mature pattern of
//  ExamCalendarView (animation / 7×6 grid / glass header / glass bottom
//  panel), with the data layer swapped to `container.diaryRepo`.
//

import SwiftUI

struct DiaryCalendarView: View {
    @Environment(RepositoryContainer.self) private var container

    // MARK: - 状态 / State

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

    /// 点击某日条目时,通知 caller 打开日记编辑器
    /// Callback to open the editor for the given entry (set by the parent view).
    var onSelectEntry: ((DiaryEntry) -> Void)?

    // MARK: - 数据聚合 / Data Aggregation

    private let calendar = Calendar.current

    /// 所有日记按日历日分组
    /// All diary entries grouped by calendar day.
    private var entriesByDay: [Date: [DiaryEntry]] {
        var bucket: [Date: [DiaryEntry]] = [:]
        for entry in container.diaryRepo.diaryEntries {
            let day = calendar.startOfDay(for: entry.date)
            bucket[day, default: []].append(entry)
        }
        return bucket
    }

    /// 选中日当天所有日记(按时间升序)
    /// Entries that fall on the selected date (sorted ascending by time).
    private var entriesOnSelectedDate: [DiaryEntry] {
        let day = calendar.startOfDay(for: selectedDate)
        return (entriesByDay[day] ?? []).sorted { $0.date < $1.date }
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
    /// Fixed height: top glass header + 6 rows of day cells.
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
        let days = calendar.monthGridDays(for: month)
        let today = calendar.startOfDay(for: Date())
        let bucket = entriesByDay

        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                let day = calendar.startOfDay(for: date)
                let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
                let isToday = calendar.isDate(day, inSameDayAs: today)
                let dayEntry = bucket[day]?.first

                DiaryCalendarDayCell(
                    date: day,
                    inMonth: inMonth,
                    isSelected: isSelected,
                    isToday: isToday,
                    entry: dayEntry
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
            Group {
                if #available(iOS 26, *) {
                    Color.clear.glassEffect(.regular, in: headerGlassShape)
                } else {
                    headerGlassShape.fill(.regularMaterial)
                }
            }
            .frame(height: headerTotalFixedHeight)
            .padding(.horizontal, glassEdgeInset)
            .ignoresSafeArea(edges: .top)

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
                let todayMonth = calendar.startOfMonth(for: today)
                let direction = todayMonth > displayedMonth ? 1 : -1
                animateToMonth(todayMonth, direction: direction)
                selectedDate = calendar.startOfDay(for: today)
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
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
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
                if !entriesOnSelectedDate.isEmpty {
                    Text("\(entriesOnSelectedDate.count) " + "items".localized())
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color(.systemBlue).opacity(0.15))
                        )
                        .foregroundColor(Color(.systemBlue))
                }
            }

            if entriesOnSelectedDate.isEmpty {
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "book.closed")
                            .font(.title3)
                            .foregroundColor(Color(.tertiaryLabel))
                        Text("No Diary Entries Yet".localized())
                            .font(.caption)
                            .foregroundColor(Color(.secondaryLabel))
                    }
                    Spacer()
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(entriesOnSelectedDate) { entry in
                            diaryRow(for: entry)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelectEntry?(entry)
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

    /// 选中日面板内单条日记 row
    /// Single diary row inside the selected-day panel.
    private func diaryRow(for entry: DiaryEntry) -> some View {
        HStack(spacing: 10) {
            // 类型条 / kind bar.
            RoundedRectangle(cornerRadius: 3)
                .fill(DiaryCalendarPalette.color(forMood: entry.moodScore))
                .frame(width: 4, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.moodEmoji)
                        .font(.title3)
                    Text(moodLabel(for: entry.moodScore))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Color(.label))
                    if !entry.energyTag.isEmpty {
                        Text(entry.energyTag)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color(.tertiarySystemFill))
                            )
                            .foregroundColor(Color(.secondaryLabel))
                    }
                }
                if !entry.content.isEmpty {
                    Text(entry.content)
                        .font(.caption)
                        .foregroundColor(Color(.secondaryLabel))
                        .lineLimit(2)
                } else {
                    Text("(No text)".localized())
                        .font(.caption)
                        .foregroundColor(Color(.tertiaryLabel))
                        .italic()
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background {
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.tertiarySystemGroupedBackground))
            }
        }
    }

    private func moodLabel(for score: Int) -> String {
        switch score {
        case 1: return "Sad".localized()
        case 2: return "Low".localized()
        case 3: return "OK".localized()
        case 4: return "Good".localized()
        case 5: return "Great".localized()
        default: return ""
        }
    }

    // MARK: - Navigation / 跳转

    private func shiftMonth(by offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        animateToMonth(calendar.startOfMonth(for: next), direction: offset)
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

#Preview("Empty") {
    DiaryCalendarView()
        .environment(RepositoryContainer())
}

#Preview("With Entries") {
    let container = RepositoryContainer()
    let cal = Calendar.current
    let today = Date()
    func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: today))!
    }
    container.diaryRepo.add(DiaryEntry(date: day(0), moodScore: 4, energyScore: 4, energyTag: "专注", content: "完成数学三章复习。"))
    container.diaryRepo.add(DiaryEntry(date: day(-3), moodScore: 5, energyScore: 5, energyTag: "兴奋", content: "今天效率很高,刷了 30 道题。"))
    container.diaryRepo.add(DiaryEntry(date: day(-7), moodScore: 2, energyScore: 2, energyTag: "疲惫", content: ""))
    return DiaryCalendarView()
        .environment(container)
}

#Preview("Dark Mode") {
    let container = RepositoryContainer()
    let today = Calendar.current.startOfDay(for: Date())
    container.diaryRepo.add(DiaryEntry(date: today, moodScore: 3, energyScore: 3, energyTag: "平静", content: "今天中等状态。"))
    return DiaryCalendarView()
        .environment(container)
        .preferredColorScheme(.dark)
}
