//
//  TodoAgendaViews.swift
//  StudyPulse
//
//  待办页的时间轴组件:周条 / 日标题 / 时间轴行 / 考试大卡。
//  Agenda building blocks of the Todo page: week strip, day header, agenda row, exam card.
//

import SwiftUI

// MARK: - 类型配色 / Kind colours

extension TodoEntry {
    /// 时间轴色条:例程紫 / 作业蓝 / 阅读绿 / 考试按紧迫度。
    /// Agenda accent: routine purple, homework blue, reading green, exams by urgency.
    var agendaColor: Color {
        switch kind {
        case .routine: return .purple
        case .homework: return .blue
        case .reading: return .green
        case .exam, .comprehensiveExam:
            let days = TodoAgendaEngine.daysUntil(date)
            if days <= 3 { return .red }
            if days <= 7 { return .orange }
            return .accentColor
        }
    }

    var isExamLike: Bool { kind == .exam || kind == .comprehensiveExam }
}

extension TodoEntryKind {
    var dotColor: Color {
        switch self {
        case .routine: return .purple
        case .homework: return .blue
        case .reading: return .green
        case .exam, .comprehensiveExam: return .red
        }
    }
}

// MARK: - 周条 / Week strip

struct TodoWeekStrip: View {
    let days: [TodoWeekDay]
    let selected: Date?
    let onSelect: (Date) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                let on = selected.map { Calendar.current.isDate($0, inSameDayAs: day.date) } ?? false
                Button { onSelect(day.date) } label: {
                    VStack(spacing: 4) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(on ? Color.white.opacity(0.85) : .secondary)
                        Text("\(Calendar.current.component(.day, from: day.date))")
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(on ? Color.white : (day.isToday ? Color.accentColor : Color.primary))
                        HStack(spacing: 3) {
                            ForEach(Array(day.kinds.enumerated()), id: \.offset) { _, kind in
                                Circle().fill(on ? Color.white : kind.dotColor).frame(width: 5, height: 5)
                            }
                        }
                        .frame(height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityValue(String(format: "todo.v2.week.count".localized(), day.count))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DesignToken.CornerRadius.large, style: .continuous))
    }
}

// MARK: - 日标题 / Day header

struct TodoDayHeader: View {
    let day: AgendaDay

    private var title: String {
        switch day.kind {
        case .today: return "todo.v2.day.today".localized()
        case .tomorrow: return "todo.v2.day.tomorrow".localized()
        case .day: return day.date.formatted(.dateTime.weekday(.wide))
        case .later: return "todo.v2.day.later".localized()
        }
    }

    private var subtitle: String {
        switch day.kind {
        case .later: return String(format: "todo.v2.day.laterFrom".localized(), day.date.formatted(.dateTime.month().day()))
        default: return day.date.formatted(.dateTime.month().day().weekday(.abbreviated))
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(.title3, design: .rounded, weight: .bold))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            if day.kind == .today || day.kind == .tomorrow {
                Text(String(format: "todo.v2.day.count".localized(), day.entries.count))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 时间轴行 / Agenda row

struct TodoAgendaRow: View {
    let entry: TodoEntry
    var dateStyleTime: Bool = true
    var onTap: () -> Void
    var onToggle: () -> Void

    private var canComplete: Bool { entry.kind == .homework || entry.kind == .reading || entry.kind == .routine }

    private var timeText: String {
        if entry.isExamLike {
            if let slot = entry.exam?.timeSlot { return slot.startTime.formatted(date: .omitted, time: .shortened) }
            return "todo.v2.allDay".localized()
        }
        return entry.date.formatted(date: .omitted, time: .shortened)
    }

    private var timeSub: String {
        switch entry.kind {
        case .homework, .reading: return "todo.v2.due".localized()
        case .routine:
            if let end = entry.endDate {
                let minutes = Int(end.timeIntervalSince(entry.date) / 60)
                if minutes > 0 { return String(format: "todo.v2.minutes".localized(), minutes) }
            }
            return ""
        case .exam, .comprehensiveExam: return ""
        }
    }

    private var meta: String {
        var parts: [String] = [kindLabel]
        if !entry.subject.isEmpty { parts.append(entry.subject.localized()) }
        if entry.isExamLike {
            let d = TodoAgendaEngine.daysUntil(entry.date)
            parts.append(d == 0 ? "todo.v2.today".localized() : String(format: "todo.v2.inDays".localized(), d))
        }
        return parts.joined(separator: " · ")
    }

    private var kindLabel: String {
        switch entry.kind {
        case .exam: return "Exam".localized()
        case .comprehensiveExam: return "Compre.".localized()
        case .homework: return "Homework".localized()
        case .reading: return "Reading".localized()
        case .routine: return "Routine".localized()
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeText).font(.system(.subheadline, design: .rounded, weight: .semibold)).monospacedDigit()
                if !timeSub.isEmpty { Text(timeSub).font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(width: 54, alignment: .trailing)
            .padding(.top, 12)

            HStack(spacing: 10) {
                if canComplete {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { onToggle() }
                    } label: {
                        Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(entry.isCompleted ? Color.green : Color(.tertiaryLabel))
                            .frame(minWidth: 32, minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.isCompleted ? "Pending".localized() : "Done".localized())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .strikethrough(entry.isCompleted)
                        .lineLimit(2)
                    Text(meta).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14, bottomTrailingRadius: 0, topTrailingRadius: 0)
                    .fill(entry.agendaColor)
                    .frame(width: 4)
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(entry.isCompleted ? 0.55 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture(perform: onTap)
        }
    }
}

// MARK: - 考试大卡 / Exam card

struct TodoExamCard: View {
    let entry: TodoEntry
    var onTap: () -> Void
    var onPlan: (() -> Void)?

    private var days: Int { TodoAgendaEngine.daysUntil(entry.date) }
    private var mastery: Int { entry.exam?.masteryDegree ?? entry.comprehensiveExam?.masteryDegree ?? 0 }
    private var checklist: (done: Int, total: Int)? { entry.exam.flatMap(TodoAgendaEngine.checklistProgress) }

    private var place: String {
        guard let e = entry.exam else { return "" }
        var parts: [String] = []
        if !e.locationSchool.isEmpty { parts.append(e.locationSchool) }
        if !e.locationClassroom.isEmpty { parts.append(e.locationClassroom) }
        if !e.locationSeat.isEmpty { parts.append(String(format: "todo.v2.seat".localized(), e.locationSeat)) }
        return parts.joined(separator: " · ")
    }

    private var timeLine: String {
        var parts: [String] = []
        if let slot = entry.exam?.timeSlot {
            parts.append("\(slot.startTime.formatted(date: .omitted, time: .shortened))–\(slot.endTime.formatted(date: .omitted, time: .shortened))")
        } else {
            parts.append("todo.v2.allDay".localized())
        }
        if !place.isEmpty { parts.append(place) }
        return parts.joined(separator: " · ")
    }

    private var masteryTint: Color { mastery <= 20 ? .red : (mastery <= 60 ? .orange : .green) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 0) {
                    Text(days <= 0 ? "0" : "\(days)").font(.system(.title2, design: .rounded, weight: .heavy))
                    Text("todo.v2.daysLater".localized()).font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(entry.agendaColor.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title).font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(2)
                    Text(timeLine).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 16) {
                if let checklist {
                    progress(String(format: "todo.v2.exam.checklist".localized(), checklist.done, checklist.total),
                             value: Double(checklist.done) / Double(max(checklist.total, 1)), tint: .accentColor)
                }
                progress(String(format: "todo.v2.exam.mastery".localized(), mastery), value: Double(mastery) / 100, tint: masteryTint)
            }

            if days <= 7, days >= 0, let onPlan {
                Button(action: onPlan) {
                    Label("todo.v2.exam.plan".localized(), systemImage: "target")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(entry.agendaColor)
            }
        }
        .padding(14)
        .background(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 0, topTrailingRadius: 0)
                .fill(entry.agendaColor)
                .frame(width: 4)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onTap)
    }

    private func progress(_ title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote.weight(.semibold))
            ProgressView(value: min(max(value, 0), 1)).tint(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
