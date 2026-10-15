//
//  DiaryView.swift
//  StudyPulse
//
//  学习日记主视图(sheet 根):今日心情快捷条 + 倒序日记列表 + 日历/趋势/设置入口。
//  Diary main view (sheet root): today mood quick-bar + reverse-chronological
//  entry list + entries to calendar / trend / settings.
//

import SwiftUI

struct DiaryView: View {
    @Environment(RepositoryContainer.self) private var container

    @State private var showingEditor = false
    @State private var editingEntry: DiaryEntry? = nil
    @State private var showingCalendar = false
    @State private var showingTrend = false
    @State private var showingSettings = false

    /// 列表展示用的日记(按 active phase 过滤)
    /// Entries shown in the list (filtered by active phase).
    private var displayEntries: [DiaryEntry] {
        container.diaryRepo.filteredDiaryEntries
    }

    var body: some View {
        // 注意:不要包自己的 NavigationStack!HomeView 外层已经有,
        // 内层 NavigationStack 会与外层冲突:
        // - 第一次 push:inner NS 渲染时 SwiftUI 检测到"已在栈中",
        //   触发自动 pop 回到外层
        // - 之后:NavigationLink path 状态被破坏,无法再触发 push
        // Don't wrap a NavigationStack here! HomeView's outer NavigationStack
        // already exists; nesting causes:
        //   - first push: inner NS detects "already in stack" and auto-pops
        //   - subsequent: path state is corrupted, push no longer fires
        Group {
            if displayEntries.isEmpty {
                emptyState
            } else {
                listView
            }
        }
        .navigationTitle("Study Diary".localized())
        .navigationBarTitleDisplayMode(.large)
        .containerBackground(.clear, for: .navigation)
        .background(Color(.systemGroupedBackground).opacity(0.4).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingCalendar = true
                    } label: {
                        Label("Calendar View".localized(), systemImage: "calendar")
                    }
                    Button {
                        showingTrend = true
                    } label: {
                        Label("Mood Trend".localized(), systemImage: "chart.xyaxis.line")
                    }
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Diary Settings".localized(), systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    editingEntry = nil
                    showingEditor = true
                } label: {
                    Label("New Entry".localized(), systemImage: "plus.circle.fill")
                        .font(.headline)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let entry = editingEntry {
                DiaryEntryEditView(editing: entry)
            } else {
                DiaryEntryEditView()
            }
        }
        .sheet(isPresented: $showingCalendar) {
            DiaryCalendarView()
        }
        .sheet(isPresented: $showingTrend) {
            MoodTrendChartView()
        }
        .sheet(isPresented: $showingSettings) {
            DiarySettingsView()
        }
    }

    // MARK: - 今日心情快捷条 + 列表 / Today Mood Bar + List

    private var listView: some View {
        List {
            // 今日心情快捷条
            // 对齐策略:listRowInsets(EdgeInsets()) 让 card 背景占满 List 内容区,
            // 内部 padding(.horizontal, 16) 给文字/emoji 视觉边距。
            // 日记 row 用同样的 listRowInsets(EdgeInsets()) + DiaryRowView 内部 padding(.horizontal, 16)
            // → 两边"内容起点"都距 List inset 边 16pt,完美对齐。
            // 今日心情 card 用 .listRowBackground(Color.clear) + 自己的 .background()
            // (因为有圆角)。日记 row 让 List 用默认背景(.secondarySystemGroupedBackground)
            // 即可,不需要 clear — iOS 26 List 在 .listRowBackground(Color.clear) 下 row
            // 会完全透明看不见。
            // Alignment strategy: listRowInsets(EdgeInsets()) makes the card
            // background fill the List content area; inner padding(.horizontal, 16)
            // gives visual margin for text/emoji. Diary rows use the same
            // listRowInsets + DiaryRowView's inner padding(.horizontal, 16),
            // so both start 16pt from the List inset edge — perfectly aligned.
            // Today mood card uses .listRowBackground(Color.clear) + its own
            // .background() (because it has rounded corners). Diary rows use
            // the List's default row background — clearing it would make them
            // invisible in iOS 26.
            todayMoodBar
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            // 日记列表(倒序)
            ForEach(displayEntries) { entry in
                DiaryRowView(entry: entry)
                    .listRowInsets(EdgeInsets())
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingEntry = entry
                        showingEditor = true
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            container.diaryRepo.delete(entry)
                        } label: {
                            Label("Delete".localized(), systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    /// 今日心情快捷条:5 个 emoji,点击即记 1 分(无文字也可保存)。
    /// Today mood quick-bar: 5 emoji; tapping one logs a 1-tap mood entry.
    private var todayMoodBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today's Mood".localized())
                    .font(.headline)
                Spacer()
                if let today = container.diaryRepo.todayEntry() {
                    Text(today.moodEmoji)
                        .font(.title2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { score in
                    let emoji = DiaryEntry(moodScore: score).moodEmoji
                    Button {
                        logQuickMood(score: score)
                    } label: {
                        Text(emoji)
                            .scaledFont(size: 32)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.top, 8)
        // 注意:不再加 .padding(.horizontal, 16) — card 背景需要占满 List 内容区,
        // 内部 HStack/VStack 自己有 .padding(.horizontal, 16) 给内容视觉边距。
        // 这样和 DiaryRowView(用 .padding(.horizontal, 16) 内部边距)对齐。
        // Don't add .padding(.horizontal, 16) here — the card background must
        // fill the List content area, and inner HStack/VStack already have
        // .padding(.horizontal, 16) for visual margin. This matches the
        // DiaryRowView's inner .padding(.horizontal, 16) for alignment.
    }

    /// 快速记录心情:若今日已有日记则更新 moodScore,否则新建一条仅含 moodScore 的日记。
    /// Quick mood log: updates today's entry if present, otherwise creates
    /// a new entry containing only the mood score.
    private func logQuickMood(score: Int) {
        if var today = container.diaryRepo.todayEntry() {
            today.moodScore = score
            container.diaryRepo.update(today)
        } else {
            let new = DiaryEntry(date: .now, moodScore: score, energyScore: 3, energyTag: "", content: "")
            container.diaryRepo.add(new)
        }
    }

    // MARK: - 空状态 / Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "book")
                .scaledFont(size: 64)
                .foregroundColor(.secondary.opacity(0.6))

            VStack(spacing: 8) {
                Text("No Diary Entries Yet".localized())
                    .font(.title3.weight(.semibold))
                Text("Track your mood, energy, and reflections to see patterns over time.".localized())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                editingEntry = nil
                showingEditor = true
            } label: {
                Label("Write First Entry".localized(), systemImage: "pencil.line")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(container.envManager.effectiveAccentColor)
                    )
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 日记行视图 / Diary Row

/// 单条日记的行视图:emoji + 精力 tag + 内容预览 + 日期。
/// Single diary row: emoji + energy tag + content preview + date.
struct DiaryRowView: View {
    let entry: DiaryEntry

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.moodEmoji)
                .scaledFont(size: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dateFormatter.string(from: entry.date))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    if !entry.energyTag.isEmpty {
                        Text(entry.energyTag)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                    }
                }
                if !entry.content.isEmpty {
                    Text(entry.content)
                        .font(.callout)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("(No text)".localized())
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        // 与 todayMoodBar 对齐:emoji 起点 = List inset 边 + 16pt
        // Aligns with todayMoodBar: emoji starts at List inset edge + 16pt
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - 预览 / Preview

#Preview("With Entries") {
    let container = RepositoryContainer()
    DiaryView()
        .environment(container)
        .onAppear {
            container.diaryRepo.add(DiaryEntry(date: .now, moodScore: 4, energyScore: 3, energyTag: "专注", content: "# 今天\n完成了数学三章的复习,感觉不错。"))
            container.diaryRepo.add(DiaryEntry(date: .now.addingTimeInterval(-86400), moodScore: 2, energyScore: 2, energyTag: "疲惫", content: "状态一般,需要早睡。"))
        }
}

#Preview("Empty") {
    DiaryView()
        .environment(RepositoryContainer())
}
