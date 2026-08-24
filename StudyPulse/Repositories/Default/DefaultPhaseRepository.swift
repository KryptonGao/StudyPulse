//
//  DefaultPhaseRepository.swift
//  StudyPulse
//
//  学习阶段 (StudyPhase) Repository 默认实现。
//  Default PhaseRepository implementation backed by SwiftData.
//

import Foundation
import SwiftData
import os

/// 学习阶段 (StudyPhase) Repository 默认实现。
/// Default PhaseRepository implementation backed by SwiftData.
@Observable @MainActor
final class DefaultPhaseRepository: PhaseRepository {
    /// 全部阶段（按 startDate desc 排序）
    /// All phases, sorted by startDate desc.
    var phases: [StudyPhase] = []

    @ObservationIgnored
    private var modelContext: ModelContext?

    /// 用于 background fetch 的容器引用(Sendable)
    /// Container reference for background fetches (Sendable).
    @ObservationIgnored
    private var modelContainer: ModelContainer?

    /// 跨域引用:Phase 操作会读 / 改其它域的 phaseId。
    /// Cross-domain refs: phase ops read/write phaseId in other domains.
    /// 这些 weak 引用由容器在 init 时注入。
    /// These weak refs are injected by the container on init.
    @ObservationIgnored
    weak var gradeRef: (any GradeRepository)?
    @ObservationIgnored
    weak var mistakeRef: (any MistakeRepository)?
    @ObservationIgnored
    weak var examRef: (any ExamRepository)?
    @ObservationIgnored
    weak var taskRef: (any TaskRepository)?

    /// AppEnvironmentManager(由容器注入,用于读/写 activePhaseId)
    /// AppEnvironmentManager (injected by the container; used to read/write `activePhaseId`).
    @ObservationIgnored
    private let envManager: AppEnvironmentManager

    init(envManager: AppEnvironmentManager) {
        self.envManager = envManager
    }

    /// 由容器调用,注入其它 4 个 repo 的 weak 引用以支持跨域 phaseId 操作。
    /// Called by the container; injects weak refs to the other 4 repos
    /// so cross-domain phaseId ops work.
    func setCrossRefs(
        grade: any GradeRepository,
        mistake: any MistakeRepository,
        exam: any ExamRepository,
        task: any TaskRepository
    ) {
        self.gradeRef = grade
        self.mistakeRef = mistake
        self.examRef = exam
        self.taskRef = task
    }

    // MARK: - Lifecycle
    // MARK: - 生命周期 / Lifecycle

    /// 加载所有学习阶段
    /// Load all study phases.
    func loadAll(context: ModelContext) async {
        self.modelContext = context
        self.modelContainer = context.container
        guard let container = modelContainer else { return }
        // detached Task 内创建独立 background ModelContext,fetch + toSnapshot
        // Use an independent background ModelContext inside a detached task.
        let snapshots: [StudyPhase] = await Task.detached(priority: .utility) {
            let ctx = ModelContext(container)
            let entities = (try? ctx.fetch(
                FetchDescriptor<StudyPhaseRecord>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
            )) ?? []
            return entities.map { $0.toSnapshot() }
        }.value
        // 回到 MainActor 赋值
        self.phases = snapshots
    }

    // MARK: - Computed
    // MARK: - 计算属性 / Computed

    /// 当前激活的 phase
    /// Currently active phase.
    var activePhase: StudyPhase? {
        guard let id = envManager.activePhaseId else { return nil }
        return phases.first(where: { $0.id == id })
    }

    /// phase 过滤是否开启（activePhaseId != nil）
    /// Whether phase filtering is on (activePhaseId != nil).
    var phaseFilterEnabled: Bool {
        envManager.activePhaseId != nil
    }

    /// 是否存在 phaseId == nil 的"未归类"数据
    /// Whether any domain has records with phaseId == nil.
    var hasUnassignedData: Bool {
        unassignedRecordCount > 0
    }

    /// 全部域中 phaseId == nil 的记录数（用于未归类提示）
    /// Total unassigned records across all domains (used by the unassigned prompt).
    var unassignedRecordCount: Int {
        let g = gradeRef?.grades.filter { $0.phaseId == nil }.count ?? 0
        let m = mistakeRef?.mistakeSets.filter { $0.phaseId == nil }.count ?? 0
        let e = examRef?.examSets.filter { $0.phaseId == nil }.count ?? 0
        let c = examRef?.comprehensiveExamSets.filter { $0.phaseId == nil }.count ?? 0
        let t = taskRef?.taskItems.filter { $0.phaseId == nil }.count ?? 0
        return g + m + e + c + t
    }

    // MARK: - CRUD
    // MARK: - 增删改查 / CRUD

    /// 新增一个 phase
    /// Add a new phase.
    func add(_ phase: StudyPhase) {
        if let context = modelContext {
            context.insert(StudyPhaseRecord(from: phase))
            guard context.saveOrRollback("PhaseRepository.add") else { return }
        }
        phases.append(phase)
        phases.sort { $0.startDate > $1.startDate }
        Log.data.info("PhaseRepository added: name=\(phase.name, privacy: .public) archived=\(phase.isArchived, privacy: .public)")
        Log.record(.info, category: "Data", message: "PhaseRepository added: \(phase.name)")
    }

    func update(_ phase: StudyPhase) {
        guard let context = modelContext else {
            if let index = phases.firstIndex(where: { $0.id == phase.id }) {
                phases[index] = phase
            }
            return
        }
        do {
            if let entity = try context.fetch(
                FetchDescriptor<StudyPhaseRecord>(predicate: #Predicate { $0.id == phase.id })
            ).first {
                entity.name = phase.name
                entity.startDate = phase.startDate
                entity.endDate = phase.endDate
                entity.isArchived = phase.isArchived
                entity.archivedAt = phase.archivedAt
                entity.goalsData = try? JSONEncoder().encode(phase.goals)
                try context.save()
            } else {
                context.insert(StudyPhaseRecord(from: phase))
                try context.save()
            }
        } catch {
            context.rollback()
            Log.data.error("PhaseRepository update failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        if let index = phases.firstIndex(where: { $0.id == phase.id }) {
            phases[index] = phase
        }
    }

    func delete(_ phase: StudyPhase) {
        // 1. 清空其它域对 phase 的引用
        clearPhaseReferences(phaseId: phase.id)
        // 2. 删 SwiftData
        guard let context = modelContext else {
            phases.removeAll { $0.id == phase.id }
            if envManager.activePhaseId == phase.id { envManager.setActivePhaseId(nil) }
            return
        }
        do {
            if let entity = try context.fetch(
                FetchDescriptor<StudyPhaseRecord>(predicate: #Predicate { $0.id == phase.id })
            ).first {
                context.delete(entity)
                try context.save()
            }
        } catch {
            context.rollback()
            Log.data.error("PhaseRepository delete failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        // 3. 从内存列表中移除
        phases.removeAll { $0.id == phase.id }
        // 4. 如果当前激活的 phase 被删了,清空 activePhaseId
        if envManager.activePhaseId == phase.id {
            envManager.setActivePhaseId(nil)
        }
        Log.data.info("PhaseRepository deleted: name=\(phase.name, privacy: .public)")
    }

    func setArchived(_ phase: StudyPhase, archived: Bool) {
        var updated = phase
        updated.isArchived = archived
        updated.archivedAt = archived ? Date() : nil
        update(updated)
    }

    func activate(_ phase: StudyPhase?) {
        envManager.setActivePhaseId(phase?.id)
    }

    // MARK: - 跨域 phaseId 工具
    // MARK: - 跨域 phaseId 工具 / Cross-domain phaseId helpers

    /// 把全部 phaseId == nil 的记录归到指定 phase
    /// Assign all unassigned records (phaseId == nil) to the given phase.
    @discardableResult
    func assignUnassignedDataToPhase(_ phaseId: UUID) -> (grades: Int, mistakes: Int, exams: Int, comprehensiveExams: Int, tasks: Int) {
        guard let context = modelContext else { return (0, 0, 0, 0, 0) }
        var gCount = 0, mCount = 0, eCount = 0, cCount = 0, tCount = 0
        do {
            // grades
            if let g = gradeRef {
                for i in 0..<g.grades.count where g.grades[i].phaseId == nil {
                    var updated = g.grades[i]
                    updated.phaseId = phaseId
                    g.update(updated)
                    gCount += 1
                }
            }
            // mistakes
            if let m = mistakeRef {
                for i in 0..<m.mistakeSets.count where m.mistakeSets[i].phaseId == nil {
                    var updated = m.mistakeSets[i]
                    updated.phaseId = phaseId
                    m.update(updated)
                    mCount += 1
                }
            }
            // single exams
            if let e = examRef {
                for i in 0..<e.examSets.count where e.examSets[i].phaseId == nil {
                    var updated = e.examSets[i]
                    updated.phaseId = phaseId
                    e.updateExam(updated)
                    eCount += 1
                }
                // comprehensive exams
                for i in 0..<e.comprehensiveExamSets.count where e.comprehensiveExamSets[i].phaseId == nil {
                    var updated = e.comprehensiveExamSets[i]
                    updated.phaseId = phaseId
                    e.updateComprehensiveExam(updated)
                    cCount += 1
                }
            }
            // tasks
            if let t = taskRef {
                for i in 0..<t.taskItems.count where t.taskItems[i].phaseId == nil {
                    var updated = t.taskItems[i]
                    updated.phaseId = phaseId
                    t.update(updated, reminderResult: nil)
                    tCount += 1
                }
            }
            try context.save()
            Log.data.info("PhaseRepository assigned unassigned: g=\(gCount, privacy: .public) m=\(mCount, privacy: .public) e=\(eCount, privacy: .public) c=\(cCount, privacy: .public) t=\(tCount, privacy: .public)")
        } catch {
            Log.data.error("PhaseRepository assignUnassigned failed: \(error.localizedDescription, privacy: .public)")
        }
        return (gCount, mCount, eCount, cCount, tCount)
    }

    /// 清空其它域对指定 phase 的引用（删除 phase 前调用）
    /// Clear all references to the given phase in other domains (called before delete).
    func clearPhaseReferences(phaseId: UUID) {
        guard let context = modelContext else { return }
        do {
            if let g = gradeRef {
                for i in 0..<g.grades.count where g.grades[i].phaseId == phaseId {
                    var updated = g.grades[i]
                    updated.phaseId = nil
                    g.update(updated)
                }
            }
            if let m = mistakeRef {
                for i in 0..<m.mistakeSets.count where m.mistakeSets[i].phaseId == phaseId {
                    var updated = m.mistakeSets[i]
                    updated.phaseId = nil
                    m.update(updated)
                }
            }
            if let e = examRef {
                for i in 0..<e.examSets.count where e.examSets[i].phaseId == phaseId {
                    var updated = e.examSets[i]
                    updated.phaseId = nil
                    e.updateExam(updated)
                }
                for i in 0..<e.comprehensiveExamSets.count where e.comprehensiveExamSets[i].phaseId == phaseId {
                    var updated = e.comprehensiveExamSets[i]
                    updated.phaseId = nil
                    e.updateComprehensiveExam(updated)
                }
            }
            if let t = taskRef {
                for i in 0..<t.taskItems.count where t.taskItems[i].phaseId == phaseId {
                    var updated = t.taskItems[i]
                    updated.phaseId = nil
                    t.update(updated, reminderResult: nil)
                }
            }
            try context.save()
        } catch {
            Log.data.error("PhaseRepository clearPhaseReferences failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
