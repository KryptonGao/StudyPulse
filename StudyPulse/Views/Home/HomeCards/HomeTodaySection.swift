//
//  HomeTodaySection.swift
//  StudyPulse
//
//  「今日」区块:计划清单(Top-3 其余项 + 闪卡到期一行)+ 待登记成绩横幅 + 考试倒数横滑卡。
//  Today zone: plan list (rest of the Top-3 + a flashcard-due row), a pending-grades banner,
//  and a horizontally scrolling exam countdown carousel.
//

import SwiftUI

/// 「今日」区块各子模块的开关(来自 `HomeLayoutPreference`)。
/// Per-module switches for the Today zone (from `HomeLayoutPreference`).
struct HomeTodayOptions {
    var showsPlan = true
    var showsFlashcards = true
    var showsUnregisteredBanner = true
    var showsExams = true
    var showsSimulator = true
    var showsReversePlanner = true
}

struct HomeTodaySection: View {
    let viewModel: HomeViewModel
    let options: HomeTodayOptions
    let candidateIndex: Int
    let onOpenItem: (DailyPlanItem) -> Void
    let onStartFlashcards: () -> Void
    let onOpenSimulator: () -> Void
    let onOpenReversePlanner: () -> Void

    @Environment(RepositoryContainer.self) private var container
    @Environment(\.selectAppTab) private var selectAppTab
    @State private var showingAddGrade = false

    /// 「现在」主卡占用的候选之外的计划项 / Plan items other than the one the Now hero shows.
    private var listItems: [DailyPlanItem] {
        let all = viewModel.planCandidates
        guard !all.isEmpty else { return [] }
        let skip = candidateIndex % all.count
        return all.enumerated().filter { $0.offset != skip }.map(\.element)
    }

    private var showsFlashcardRow: Bool {
        options.showsFlashcards && viewModel.srsOverview.dueCount > 0
    }
    private var showsBanner: Bool {
        options.showsUnregisteredBanner && !viewModel.unregisteredExams.isEmpty
    }
    private var showsExamCarousel: Bool {
        options.showsExams && !viewModel.upcomingExams.isEmpty
    }
    private var showsList: Bool {
        options.showsPlan && (!listItems.isEmpty || showsFlashcardRow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            HomeZoneHeader(title: "home.v2.zone.today".localized()) {
                Button("home.v2.today.allTodos".localized()) { selectAppTab(.todo) }
            }

            VStack(spacing: DesignToken.Spacing.medium) {
                if showsList { planList }
                if showsBanner { unregisteredBanner }
                if showsExamCarousel { examCarousel }
                if !showsList && !showsBanner && !showsExamCarousel { emptyCard }
            }
        }
        .sheet(isPresented: $showingAddGrade) {
            AddGradeView(container: container)
                .environment(container)
                .adaptiveSheet()
        }
        .debugLayoutBoundsAuto()
    }

    // MARK: - Plan list

    private var planList: some View {
        VStack(spacing: 0) {
            ForEach(Array(listItems.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 44) }
                PlanRow(item: item, onOpen: { onOpenItem(item) }, onComplete: { complete(item) })
            }
            if showsFlashcardRow {
                if !listItems.isEmpty { Divider().padding(.leading, 44) }
                Button(action: onStartFlashcards) {
                    HStack(spacing: DesignToken.Spacing.medium) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.title3)
                            .foregroundStyle(container.envManager.effectiveAccentColor)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Flashcard Review".localized())
                                .font(.subheadline.weight(.semibold))
                            Text(String(format: "%d mistakes due now".localized(), viewModel.srsOverview.dueCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, DesignToken.Spacing.medium)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity)
        .cardSkin()
    }

    /// 任务 / 例程实例可直接在主页打勾;完成后由 ViewModel 重算移出清单。
    /// Tasks and routine instances can be checked off from Home; the VM recompute then removes them.
    private func complete(_ item: DailyPlanItem) {
        switch item.sourceRef {
        case .task(let id):
            container.taskRepo.setCompletion(id, isCompleted: true)
        case .routineInstance(let id):
            container.routineInstanceRepo.setCompletion(id, isCompleted: true)
        default:
            return
        }
        Haptics.success()
    }

    // MARK: - Banner

    private var unregisteredBanner: some View {
        Button {
            showingAddGrade = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(String(format: "home.v2.today.pendingGrades".localized(), viewModel.unregisteredExams.count))
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Text("home.v2.today.register".localized())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Exams

    private var examCarousel: some View {
        let exams = viewModel.upcomingExams.sorted { $0.examDate < $1.examDate }
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: DesignToken.Spacing.medium) {
                ForEach(exams) { exam in
                    ExamCountdownCard(
                        exam: exam,
                        showsSimulator: options.showsSimulator,
                        showsReversePlanner: options.showsReversePlanner,
                        onOpenSimulator: onOpenSimulator,
                        onOpenReversePlanner: onOpenReversePlanner
                    )
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 2)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }

    private var emptyCard: some View {
        HStack(spacing: DesignToken.Spacing.medium) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text("All clear".localized()).font(.subheadline.weight(.semibold))
                Text("Pick something to study or add a routine.".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
    }
}

// MARK: - Plan row

private struct PlanRow: View {
    let item: DailyPlanItem
    let onOpen: () -> Void
    let onComplete: () -> Void

    @State private var checked = false

    private var canCheck: Bool {
        switch item.sourceRef {
        case .task, .routineInstance: return true
        default: return false
        }
    }

    var body: some View {
        HStack(spacing: DesignToken.Spacing.medium) {
            leading
            Button(action: onOpen) {
                HStack(spacing: DesignToken.Spacing.small) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(checked ? .tertiary : .primary)
                            .strikethrough(checked)
                            .lineLimit(1)
                        Text(item.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(tagTitle)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(item.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(item.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, DesignToken.Spacing.medium)
    }

    @ViewBuilder
    private var leading: some View {
        if canCheck {
            Button {
                withAnimation(.snappy) { checked = true }
                onComplete()
            } label: {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(checked ? Color.green : Color.secondary.opacity(0.6))
                    .frame(width: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("home.v2.today.complete".localized())
        } else {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundStyle(item.color)
                .frame(width: 32)
                .accessibilityHidden(true)
        }
    }

    private var tagTitle: String {
        switch item.kind {
        case .urgentExam: return "home.v2.tag.exam".localized()
        case .srsReview: return "home.v2.tag.mistake".localized()
        case .overdueTask, .todayTask: return "home.v2.tag.task".localized()
        case .routineActive, .routineUpcoming: return "home.v2.tag.routine".localized()
        case .recovery: return "home.v2.tag.recovery".localized()
        case .strongSubject, .placeholder: return "home.v2.tag.suggestion".localized()
        }
    }
}

// MARK: - Exam countdown card

private struct ExamCountdownCard: View {
    let exam: Exam
    let showsSimulator: Bool
    let showsReversePlanner: Bool
    let onOpenSimulator: () -> Void
    let onOpenReversePlanner: () -> Void

    private var days: Int { HomeInsightsEngine.daysUntil(exam.examDate) }
    private var countdownColor: Color {
        days <= 3 ? .red : (days <= 10 ? .orange : .primary)
    }
    private var masteryColor: Color { exam.masteryDegree < 70 ? .orange : .green }
    private var showsTools: Bool { days <= 7 && (showsSimulator || showsReversePlanner) }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            NavigationLink(value: HomeRoute.exam(exam.id)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(days == 0 ? "Today!".localized() : "\(days)")
                            .font(.system(.title, design: .rounded, weight: .heavy))
                            .monospacedDigit()
                        if days > 0 {
                            Text("home.unit.days".localized())
                                .font(.footnote.weight(.bold))
                        }
                    }
                    .foregroundStyle(countdownColor)

                    Text(exam.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    ProgressView(value: Double(min(max(exam.masteryDegree, 0), 100)), total: 100)
                        .tint(masteryColor)
                        .padding(.top, 4)
                    Text(String(format: "home.v2.exam.mastery".localized(), exam.masteryDegree))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsTools {
                HStack(spacing: 6) {
                    if showsSimulator {
                        toolPill("home.v2.exam.simulator".localized(), icon: "person.crop.circle.badge.questionmark", action: onOpenSimulator)
                    }
                    if showsReversePlanner {
                        toolPill("home.v2.exam.planner".localized(), icon: "calendar.badge.clock", action: onOpenReversePlanner)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .cardSkin()
    }

    private func toolPill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.mini)
    }

    /// 「10/19 · 08:30 · 302」/ "10/19 · 08:30 · 302".
    private var meta: String {
        var parts = [DateFormatters.monthDay.string(from: exam.examDate)]
        if let slot = exam.timeSlot {
            parts.append(slot.startTime.formatted(date: .omitted, time: .shortened))
        } else {
            parts.append("home.v2.exam.allDay".localized())
        }
        let room = exam.locationClassroom.trimmingCharacters(in: .whitespaces)
        if !room.isEmpty { parts.append(room) }
        return parts.joined(separator: " · ")
    }
}
