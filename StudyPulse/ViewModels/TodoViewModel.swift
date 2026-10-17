//
//  TodoViewModel.swift
//  StudyPulse
//
//  Created by Antigravity on 2026/7/12.
//
//  待办列表页 ViewModel。负责把考试 / 作业 / 阅读等"待办"合并、
//  按时间分桶,并处理完成态切换 + 删除。
//  Todo-list page VM. Merges exams/homework/reading into one list,
//  bucketed by time; handles completion toggles + delete.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class TodoViewModel {
    // MARK: - 依赖项 / Dependencies
    private let container: RepositoryContainer

    // MARK: - 输入 & 界面状态 / Input & UI states
    /// 类型筛选(全部 / 考试 / 作业 / 阅读) / Type filter.
    var typeFilter: TodoTypeFilter = .all
    /// 底部「已完成」折叠区是否展开 / Whether the "completed" fold is expanded.
    var showCompleted: Bool = false
    var showingNewExam: Bool = false
    var showingNewTask: TaskType? = nil
    var showingNewRoutine: Bool = false
    var selectedExam: Exam? = nil
    var selectedComprehensive: comprehensiveExam? = nil
    var selectedTask: TaskItem? = nil
    var selectedRoutine: Routine? = nil
    /// 打开倒推计划的考试 / Exam whose reverse plan is open.
    var planningExam: Exam? = nil
    var showingPastSheet: Bool = false
    /// 列表 / 日历视图模式(持久化) / List/calendar view mode (persisted).
    var viewMode: ExamViewMode = ExamViewMode.loadFromDefaults()

    // MARK: - 输出状态 / Output states
    /// 筛选后的全部条目(含已完成)/ All filtered entries, completed included.
    private(set) var allEntries: [TodoEntry] = []
    /// 已过期且未完成(或在显示已完成时含已完成)/ Past entries (incomplete unless showing completed).
    private(set) var pastEntries: [TodoEntry] = []
    /// 按日分组的时间轴(只含未完成)/ Day-grouped agenda of incomplete entries.
    private(set) var agendaDays: [AgendaDay] = []
    /// 未来已完成条目(折叠区)/ Completed upcoming entries (fold).
    private(set) var completedEntries: [TodoEntry] = []
    /// 本周周条(不受类型筛选影响)/ Week strip (ignores the type filter).
    private(set) var weekStrip: [TodoWeekDay] = []
    /// 各类型未完成数量(不受类型筛选影响)/ Incomplete counts per type (ignores the filter).
    private(set) var typeCounts = TodoTypeCounts()
    /// 周条点选的日期;时间轴据此滚动 / Day picked in the week strip; the agenda scrolls to it.
    var selectedDay: Date? = nil

    // MARK: - 初始化 / Initialization
    init(container: RepositoryContainer) {
        self.container = container
    }

    /// 工厂方法 / Factory.
    static func makeDefault(container: RepositoryContainer) -> TodoViewModel {
        TodoViewModel(container: container)
    }

    // MARK: - 操作 / Actions
    /// 集中重算所有 todo 缓存(过滤 + 拆分过去/未来 + 按日分组)
    /// Recompute all todo caches (filter, past/upcoming split, day grouping).
    func recompute() {
        let all = container.todoEntries(includeCompleted: true)
        weekStrip = TodoAgendaEngine.weekStrip(entries: all)
        typeCounts = TodoAgendaEngine.counts(entries: all)

        let filtered: [TodoEntry]
        switch typeFilter {
        case .all:      filtered = all
        // .exam 同时包含单科 + 综合考试 / .exam covers single-subject and comprehensive exams.
        case .exam:     filtered = all.filter { $0.kind == .exam || $0.kind == .comprehensiveExam }
        case .homework: filtered = all.filter { $0.kind == .homework }
        case .reading:  filtered = all.filter { $0.kind == .reading }
        case .routine:  filtered = all.filter { $0.kind == .routine }
        }
        allEntries = filtered

        let todayStart = Calendar.current.startOfDay(for: Date())
        pastEntries = filtered.filter { $0.date < todayStart && !$0.isCompleted }
        let upcoming = filtered.filter { $0.date >= todayStart }
        agendaDays = TodoAgendaEngine.agenda(entries: upcoming.filter { !$0.isCompleted })
        completedEntries = upcoming.filter(\.isCompleted).sorted { $0.date > $1.date }
    }

    /// 切换 TaskItem 的完成态并重算 / Toggle a TaskItem's completion & recompute.
    func toggleCompletion(for task: TaskItem) {
        var updated = task
        updated.isCompleted.toggle()
        container.taskRepo.update(updated, reminderResult: nil)
        Self.completionHaptic(isCompleted: updated.isCompleted)
        recompute()
    }

    /// 完成 → 成功反馈;撤销完成 → 轻点反馈 / Success on complete, light tap on undo.
    private static func completionHaptic(isCompleted: Bool) {
        if isCompleted { Haptics.success() } else { Haptics.impact(.light) }
    }

    /// 切换 Exam 的完成态(目前是 no-op) / Toggle an Exam's completion (no-op).
    func toggleCompletion(for exam: Exam) {
        _ = exam
    }

    /// 切换 RoutineInstance 的完成态并重算 / Toggle a routine instance's completion & recompute.
    func toggleCompletion(for instance: RoutineInstance) {
        container.routineInstanceRepo.setCompletion(instance.id, isCompleted: !instance.isCompleted)
        Self.completionHaptic(isCompleted: !instance.isCompleted)
        recompute()
    }

    /// 删除一条 todo(根据 kind 路由到对应 Repository)
    /// Delete a todo (routed to the matching Repository by `kind`).
    func deleteTodoEntry(_ entry: TodoEntry) {
        switch entry.kind {
        case .homework, .reading:
            if let task = container.taskRepo.taskItems.first(where: { $0.id == entry.id }) {
                container.taskRepo.delete(task)
            }
        case .exam:
            if let exam = container.examRepo.examSets.first(where: { $0.id == entry.id }) {
                container.examRepo.deleteExam(exam)
            }
        case .comprehensiveExam:
            if let exam = container.examRepo.comprehensiveExamSets.first(where: { $0.id == entry.id }) {
                container.examRepo.deleteComprehensiveExam(exam)
            }
        case .routine:
            // 删除例程模板(级联清理关联 instance),与删除 exam/task 语义一致
            if let r = entry.routine {
                container.deleteRoutine(r.id)
            }
        }
        recompute()
    }
}
