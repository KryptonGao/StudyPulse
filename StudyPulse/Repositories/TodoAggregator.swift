//
//  TodoAggregator.swift
//  StudyPulse
//
//  跨域 TODO 聚合:把 exams / comprehensiveExams / tasks
//  合并成统一的 `TodoEntry` 列表(供 `TodoView` 用)。
//
//  - phase 过滤:外部显式 phaseId 优先;nil → 从 `AppEnvironmentManager` 取 active phase
//  - 排序:date 升序 → importance 降序
//
//  从原 `RepositoryContainer.todoEntries` 拆出 (Phase 3, 2026-07-14)。
//

import Foundation

/// 跨域 TODO 聚合器
/// Cross-domain TODO aggregator.
///
/// 把 examRepo + taskRepo 的条目合并为统一的 `TodoEntry` 列表。
/// `RepositoryContainer` 通过 `todoAggregator` 字段持有实例,保持调用方式不变。
@MainActor
final class TodoAggregator {
    private let examRepo: any ExamRepository
    private let taskRepo: any TaskRepository
    private let routineRepo: any RoutineRepository
    private let routineInstanceRepo: any RoutineInstanceRepository
    private let envManager: AppEnvironmentManager

    init(
        examRepo: any ExamRepository,
        taskRepo: any TaskRepository,
        routineRepo: any RoutineRepository,
        routineInstanceRepo: any RoutineInstanceRepository,
        envManager: AppEnvironmentManager
    ) {
        self.examRepo = examRepo
        self.taskRepo = taskRepo
        self.routineRepo = routineRepo
        self.routineInstanceRepo = routineInstanceRepo
        self.envManager = envManager
    }

    /// 合并考试 + 待办为统一 TodoEntry(供 TodoView 用)
    /// - Parameters:
    ///   - includeCompleted: 是否包含已完成条目
    ///   - phaseId: 外部显式指定过滤 phase;nil = 按 active phase 自动判定
    func entries(includeCompleted: Bool = false, phaseId: UUID? = nil) -> [TodoEntry] {
        let active = phaseId ?? envManager.activePhaseId
        var entries: [TodoEntry] = []
        // 单科考试
        for e in examRepo.examSets {
            // 统一阶段语义:显式激活时才过滤,`nil phaseId` 旧数据始终纳入(与 Diary 谓词对齐)。
            if active != nil && e.phaseId != nil && e.phaseId != active { continue }
            if !includeCompleted && e.examReview != nil { continue }
            entries.append(TodoEntry(
                id: e.id,
                kind: .exam,
                title: e.name,
                subject: e.subject,
                date: e.examDate,
                endDate: e.examEndDate,
                importance: e.importance,
                isCompleted: e.examReview != nil,
                exam: e,
                comprehensiveExam: nil,
                taskItem: nil,
                routine: nil,
                routineInstance: nil
            ))
        }
        // 综合考试
        for c in examRepo.comprehensiveExamSets {
            if active != nil && c.phaseId != nil && c.phaseId != active { continue }
            entries.append(TodoEntry(
                id: c.id,
                kind: .comprehensiveExam,
                title: c.name,
                subject: "综合",
                date: c.examDate,
                endDate: nil,
                importance: c.importance,
                isCompleted: false,
                exam: nil,
                comprehensiveExam: c,
                taskItem: nil,
                routine: nil,
                routineInstance: nil
            ))
        }
        // 待办
        for t in taskRepo.taskItems {
            if active != nil && t.phaseId != nil && t.phaseId != active { continue }
            if !includeCompleted && t.isCompleted { continue }
            let kind: TodoEntryKind = t.type == .reading ? .reading : .homework
            entries.append(TodoEntry(
                id: t.id,
                kind: kind,
                title: t.title,
                subject: t.subject,
                date: t.dueDate,
                endDate: nil,
                importance: t.importance,
                isCompleted: t.isCompleted,
                exam: nil,
                comprehensiveExam: nil,
                taskItem: t,
                routine: nil,
                routineInstance: nil
            ))
        }
        // 例程:把 routineInstanceRepo 里今天及以后的实例合并进来。
        //   - phase 过滤:用 routineRepo.filteredRoutines(已按 active phase 过滤)做白名单
        //   - includeCompleted=false → 跳过已完成 instance
        //   - 只取今天及以后(由 RoutineSpawner 在 App 启动时物化当天 instance)
        let allowedRoutineIds = Set(routineRepo.filteredRoutines.map { $0.id })
        let todayStart = Calendar.current.startOfDay(for: Date())
        for inst in routineInstanceRepo.allInstances {
            guard allowedRoutineIds.contains(inst.routineId) else { continue }
            guard inst.date >= todayStart else { continue }
            if !includeCompleted && inst.isCompleted { continue }
            let routine = routineRepo.filteredRoutines.first { $0.id == inst.routineId }
            entries.append(TodoEntry(
                id: inst.id,
                kind: .routine,
                title: inst.title,
                subject: inst.subject ?? "",
                date: inst.startTime,
                endDate: inst.endTime,
                importance: 3,
                isCompleted: inst.isCompleted,
                exam: nil,
                comprehensiveExam: nil,
                taskItem: nil,
                routine: routine,
                routineInstance: inst
            ))
        }
        return entries.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.importance > rhs.importance
        }
    }
}
