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
    /// 是否显示已完成项 / Show completed items?
    var showCompleted: Bool = false
    var showingNewExam: Bool = false
    var showingNewTask: TaskType? = nil
    var showingNewRoutine: Bool = false
    var selectedExam: Exam? = nil
    var selectedComprehensive: comprehensiveExam? = nil
    var selectedTask: TaskItem? = nil
    var selectedRoutine: Routine? = nil
    var showingPastSheet: Bool = false
    /// 列表 / 日历视图模式(持久化) / List/calendar view mode (persisted).
    var viewMode: ExamViewMode = ExamViewMode.loadFromDefaults()

    // MARK: - 输出状态 / Output states
    /// 全部可见的 todo / All visible todos.
    private(set) var allEntries: [TodoEntry] = []
    /// 未来(≥ 今天 0 点)的 todo / Future todos (≥ today's start-of-day).
    private(set) var upcomingEntries: [TodoEntry] = []
    /// 已过去的 todo / Past todos.
    private(set) var pastEntries: [TodoEntry] = []
    /// 即将到来的 todo,按时间分桶 / Upcoming todos bucketed by time.
    private(set) var groupedUpcoming: [(sectionTitle: String, entries: [TodoEntry])] = []

    // MARK: - 初始化 / Initialization
    init(container: RepositoryContainer) {
        self.container = container
    }

    /// 工厂方法 / Factory.
    static func makeDefault(container: RepositoryContainer) -> TodoViewModel {
        TodoViewModel(container: container)
    }

    // MARK: - 操作 / Actions
    /// 集中重算所有 todo 缓存(过滤 + 拆分过去/未来 + 分桶)
    /// Recompute all todo caches (filter, past/upcoming split, bucketize).
    func recompute() {
        let all = container.todoEntries(includeCompleted: showCompleted)
        let filtered: [TodoEntry]
        if typeFilter == .all {
            filtered = all
        } else {
            filtered = all.filter { entry in
                switch typeFilter {
                case .all:       return true
                // .exam 同时包含单科 + 综合考试
                // .exam covers both single-subject and comprehensive exams.
                case .exam:      return entry.kind == .exam || entry.kind == .comprehensiveExam
                case .homework:  return entry.kind == .homework
                case .reading:   return entry.kind == .reading
                case .routine:   return entry.kind == .routine
                }
            }
        }
        allEntries = filtered

        // 过去 / 未来分桶 / Past / upcoming split.
        let todayStart = Calendar.current.startOfDay(for: Date())
        var upcoming: [TodoEntry] = []
        var past: [TodoEntry] = []
        // 预留容量减少 realloc / Reserve capacity to avoid reallocations.
        upcoming.reserveCapacity(filtered.count)
        for entry in filtered {
            if entry.date >= todayStart {
                upcoming.append(entry)
            } else {
                past.append(entry)
            }
        }
        upcomingEntries = upcoming
        pastEntries = past

        // 按 1 周 / 1 月 / 更远 分桶 / Bucketize: week/month/later.
        let now = Date()
        guard let oneWeekLater = Calendar.current.date(byAdding: .day, value: 7, to: now),
              let oneMonthLater = Calendar.current.date(byAdding: .month, value: 1, to: now) else {
            groupedUpcoming = []
            return
        }
        var weekBucket: [TodoEntry] = []
        var monthBucket: [TodoEntry] = []
        var laterBucket: [TodoEntry] = []
        weekBucket.reserveCapacity(upcoming.count)
        for entry in upcoming {
            if entry.date <= oneWeekLater {
                weekBucket.append(entry)
            } else if entry.date <= oneMonthLater {
                monthBucket.append(entry)
            } else {
                laterBucket.append(entry)
            }
        }
        var result: [(String, [TodoEntry])] = []
        if !weekBucket.isEmpty { result.append(("Within 1 Week".localized(), weekBucket)) }
        if !monthBucket.isEmpty { result.append(("Within 1 Month".localized(), monthBucket)) }
        if !laterBucket.isEmpty { result.append(("Later".localized(), laterBucket)) }
        groupedUpcoming = result
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
