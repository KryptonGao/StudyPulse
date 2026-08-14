//
//  RepositoryContainer.swift
//  StudyPulse
//
//  聚合 7 个 Repository + 跨域编排(批量清空 / Todo 聚合 / 阶段过滤刷新)。
//  Aggregates 7 domain Repositories + cross-domain orchestration
//  (bulk clear / todo aggregation / phase filter refresh).
//
//  注入方式:`@Environment(RepositoryContainer.self) var container`
//
//  Phase 3 拆分 (2026-07-14):
//  - `BulkOperationOrchestrator`  → BulkOperationOrchestrator.swift
//  - `TodoAggregator`             → TodoAggregator.swift
//  - `PhaseFilterRefresher`       → PhaseFilterRefresher.swift
//  本文件仅保留 7 repo 持有 + ModelContainer + ready 状态 + 高层 facade 薄包装。
//

import Foundation
import SwiftData
import os

/// Repository 容器:7 域 + 3 个跨域子模块 + ModelContainer 持有 + ready 状态。
/// Repository container: 7 domain repos + 3 cross-domain sub-modules +
/// ModelContainer ownership + readiness flag.
@Observable @MainActor
final class RepositoryContainer {
    // 7 个 Repository(由外部注入,默认是 Default 实现)
    // The 7 repositories (injected by caller, default = Default implementations).
    let gradeRepo: any GradeRepository
    let mistakeRepo: any MistakeRepository
    let examRepo: any ExamRepository
    let taskRepo: any TaskRepository
    let phaseRepo: any PhaseRepository
    let profileRepo: any ProfileRepository
    let subjectRepo: any SubjectRepository
    /// 例程模板 Repository(2026-07-09 新增)
    /// Routine template repository (added 2026-07-09).
    let routineRepo: any RoutineRepository
    /// 例程实例 Repository(2026-07-09 新增)
    /// Routine instance repository (added 2026-07-09).
    let routineInstanceRepo: any RoutineInstanceRepository
    /// 学习日记 Repository(2026-07-17 新增)
    /// Diary repository (added 2026-07-17).
    let diaryRepo: any DiaryRepository
    let coachRepo: any CoachRepository
    let studySessionRepo: any StudySessionRepository
    let timeInvestmentRepo: any TimeInvestmentRepository
    let examAutopsyRepo: any ExamAutopsyRepository
    let examSimulationRepo: any ExamSimulationRepository
    let examPlanRepo: any ExamPlanRepository

    // 3 个跨域编排子模块(组合而非继承,避免注入面爆炸)
    // 3 cross-domain orchestration sub-modules (composition over inheritance,
    // to avoid injection surface explosion).
    let bulkOps: BulkOperationOrchestrator
    let todoAggregator: TodoAggregator
    let phaseRefresher: PhaseFilterRefresher

    /// 全局应用环境(主题 / 语言 / phase / LLM 配置等)。由容器持有,Repository 层经构造器注入,
    /// View 层经 `@Environment(RepositoryContainer.self)` 读 `container.envManager`。
    /// Global app environment (theme / language / phase / LLM config). Owned by the
    /// container; repos get it via constructor injection, Views read `container.envManager`.
    let envManager: AppEnvironmentManager

    /// App Intents 跨进程桥接。容器持有引用;App Intents 写入仍走 `IntentActionStore.setPending(_:)` 静态方法。
    /// App Intents cross-process bridge. Container holds the reference; App Intents
    /// writes still go through the `IntentActionStore.setPending(_:)` static method.
    let intentStore: IntentActionStore

    /// SwiftData ModelContainer(由 StudyPulseApp 在 .modelContainer modifier 之后注入)
    /// SwiftData ModelContainer (injected by StudyPulseApp after the
    /// `.modelContainer(...)` modifier).
    @ObservationIgnored
    private(set) var modelContainer: ModelContainer?

    /// Shared SwiftData actor for the high-frequency repositories.
    @ObservationIgnored
    private(set) var persistenceExecutor: PersistenceExecutor?

    @ObservationIgnored
    private static let persistenceSignposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.chenkai.gao.studypulse",
        category: "Persistence"
    )

    /// 是否完成 asyncInit 全部加载。View 用这个 gating loader。
    /// Whether `asyncInit` has finished loading. Views use this to gate a loader.
    private(set) var isReady: Bool = false

    init(
        envManager: AppEnvironmentManager = .shared,
        intentStore: IntentActionStore = .shared,
        gradeRepo: (any GradeRepository)? = nil,
        mistakeRepo: (any MistakeRepository)? = nil,
        examRepo: (any ExamRepository)? = nil,
        taskRepo: (any TaskRepository)? = nil,
        phaseRepo: (any PhaseRepository)? = nil,
        profileRepo: (any ProfileRepository)? = nil,
        subjectRepo: (any SubjectRepository)? = nil,
        routineRepo: (any RoutineRepository)? = nil,
        routineInstanceRepo: (any RoutineInstanceRepository)? = nil,
        diaryRepo: (any DiaryRepository)? = nil,
        coachRepo: (any CoachRepository)? = nil,
        studySessionRepo: (any StudySessionRepository)? = nil,
        timeInvestmentRepo: (any TimeInvestmentRepository)? = nil,
        examAutopsyRepo: (any ExamAutopsyRepository)? = nil,
        examSimulationRepo: (any ExamSimulationRepository)? = nil,
        examPlanRepo: (any ExamPlanRepository)? = nil
    ) {
        self.envManager = envManager
        self.intentStore = intentStore

        // 默认实现按需构造(便于测试注入 mock;默认参数无法引用前序 envManager,故在 body 内构造)
        // Construct default implementations on demand (mocks can be injected; default
        // argument expressions cannot reference a prior parameter, so build in body).
        self.gradeRepo = gradeRepo ?? DefaultGradeRepository(envManager: envManager)
        self.mistakeRepo = mistakeRepo ?? DefaultMistakeRepository(envManager: envManager)
        self.examRepo = examRepo ?? DefaultExamRepository(envManager: envManager)
        self.taskRepo = taskRepo ?? DefaultTaskRepository(envManager: envManager)
        self.phaseRepo = phaseRepo ?? DefaultPhaseRepository(envManager: envManager)
        self.profileRepo = profileRepo ?? DefaultProfileRepository()
        self.subjectRepo = subjectRepo ?? DefaultSubjectRepository()
        self.routineRepo = routineRepo ?? DefaultRoutineRepository(envManager: envManager)
        self.routineInstanceRepo = routineInstanceRepo ?? DefaultRoutineInstanceRepository()
        self.diaryRepo = diaryRepo ?? DefaultDiaryRepository(envManager: envManager)
        self.coachRepo = coachRepo ?? DefaultCoachRepository()
        self.studySessionRepo = studySessionRepo ?? DefaultStudySessionRepository()
        self.timeInvestmentRepo = timeInvestmentRepo ?? DefaultTimeInvestmentRepository()
        self.examAutopsyRepo = examAutopsyRepo ?? DefaultExamAutopsyRepository()
        self.examSimulationRepo = examSimulationRepo ?? DefaultExamSimulationRepository()
        self.examPlanRepo = examPlanRepo ?? DefaultExamPlanRepository()

        if let investmentImpl = self.timeInvestmentRepo as? DefaultTimeInvestmentRepository {
            investmentImpl.setSessionRepository(self.studySessionRepo)
        }

        // 注入跨域 weak 引用
        if let phaseImpl = self.phaseRepo as? DefaultPhaseRepository {
            phaseImpl.setCrossRefs(
                grade: self.gradeRepo,
                mistake: self.mistakeRepo,
                exam: self.examRepo,
                task: self.taskRepo
            )
        }
        if let profileImpl = self.profileRepo as? DefaultProfileRepository,
           let subjectImpl = self.subjectRepo as? DefaultSubjectRepository {
            profileImpl.setSubjectRef(self.subjectRepo)
            subjectImpl.setProfileRef(self.profileRepo)
        }

        // 组合 3 个跨域子模块
        // Compose the 3 cross-domain sub-modules.
        self.bulkOps = BulkOperationOrchestrator(
            gradeRepo: self.gradeRepo,
            mistakeRepo: self.mistakeRepo,
            examRepo: self.examRepo,
            taskRepo: self.taskRepo,
            routineRepo: self.routineRepo,
            routineInstanceRepo: self.routineInstanceRepo,
            profileRepo: self.profileRepo
        )
        self.todoAggregator = TodoAggregator(
            examRepo: self.examRepo,
            taskRepo: self.taskRepo,
            routineRepo: self.routineRepo,
            routineInstanceRepo: self.routineInstanceRepo,
            envManager: envManager
        )
        self.phaseRefresher = PhaseFilterRefresher(
            gradeRepo: self.gradeRepo,
            mistakeRepo: self.mistakeRepo,
            examRepo: self.examRepo,
            taskRepo: self.taskRepo,
            routineRepo: self.routineRepo,
            diaryRepo: self.diaryRepo,
            routineInstanceRepo: self.routineInstanceRepo,
            envManager: envManager
        )
    }

    // MARK: - ModelContainer wiring
    // MARK: - ModelContainer 装配 / ModelContainer wiring

    /// 顶层初始化:JSON 迁移 + 10 个 repo loadAll + 内嵌图片迁移 + 通知 / widget 调度。
    /// Top-level init: JSON migration + 10 repo loadAll + inline image migration + notification / widget scheduling.
    ///
    /// The successfully opened container is supplied by the launch coordinator
    /// and is the same instance injected into SwiftUI.
    func asyncInit(using container: ModelContainer) async {
        let interval = Self.persistenceSignposter.beginInterval("RepositoryContainer.asyncInit")
        defer { Self.persistenceSignposter.endInterval("RepositoryContainer.asyncInit", interval) }
        self.modelContainer = container
        let context = container.mainContext
        attachPersistenceExecutor(to: container)

        // 一次性 SwiftData migration from JSON(老用户数据回填)
        ModelContainerFactory.migrateFromJSONIfNeeded(context: context)

        // Repository protocols are MainActor-isolated. Loading them in a task group
        // would capture actor-isolated state in @Sendable closures and cannot provide
        // real parallelism, so load in actor order instead.
        await loadHighFrequencyRepositories(context: context)
        await phaseRepo.loadAll(context: context)
        await profileRepo.loadAll(context: context)
        await subjectRepo.loadAll(context: context)
        await routineRepo.loadAll(context: context)
        await routineInstanceRepo.loadAll(context: context)
        await diaryRepo.loadAll(context: context)
        await self.coachRepo.loadAll(context: context)
        await self.studySessionRepo.loadAll(context: context)
        await self.timeInvestmentRepo.loadAll(context: context)
        await self.examAutopsyRepo.loadAll(context: context)
        await self.examSimulationRepo.loadAll(context: context)
        await self.examPlanRepo.loadAll(context: context)

        // 内嵌图片迁移(在 waitForAll 后,grades 已加载)
        let migrated = gradeRepo.migrateInlineImagesIfNeeded()
        if migrated > 0, let backed = gradeRepo as? any PersistenceExecutorBacked {
            await backed.flushPendingPersistence()
        }

        // SubjectRepo 默认科目(空库时)
        if subjectRepo.subjects.isEmpty {
            subjectRepo.initializeDefaultSubjects()
        }

        // PlantManager 首次播种 + 注入上下文 + 订阅 AchievementManager
        ModelContainerFactory.migratePlantStateIfNeeded(context: context)
        PlantManager.shared.attach(container: self)

        // 观察 active phase 变化:每次变化触发 5 个 filtered 缓存重算
        phaseRefresher.startObserving()

        isReady = true

        // 调度通知 / widget
        SRSReviewNotifications.shared.rescheduleAll(mistakes: mistakeRepo.mistakeSets)
        ExamReviewNotifications.shared.rescheduleAll(exams: examRepo.examSets)
        WidgetDataSyncManager.syncUpcomingExams(
            examSets: examRepo.examSets,
            comprehensiveExamSets: examRepo.comprehensiveExamSets
        )
        TrendWidgetSyncManager.syncTrend(grades: gradeRepo.grades, subjects: subjectRepo.subjects)

        Log.data.info("RepositoryContainer asyncInit done: g=\(self.gradeRepo.grades.count, privacy: .public) m=\(self.mistakeRepo.mistakeSets.count, privacy: .public) e=\(self.examRepo.examSets.count, privacy: .public) t=\(self.taskRepo.taskItems.count, privacy: .public)")
    }

    /// Reload every repository after an atomic backup restore, then rebuild
    /// phase caches and all external projections.
    func reloadAllAfterBackupRestore() async {
        guard let modelContainer else { return }
        let context = modelContainer.mainContext
        attachPersistenceExecutor(to: modelContainer)
        await loadHighFrequencyRepositories(context: context)
        await phaseRepo.loadAll(context: context)
        await profileRepo.loadAll(context: context)
        await subjectRepo.loadAll(context: context)
        await routineRepo.loadAll(context: context)
        await routineInstanceRepo.loadAll(context: context)
        await diaryRepo.loadAll(context: context)
        await coachRepo.loadAll(context: context)
        await studySessionRepo.loadAll(context: context)
        await timeInvestmentRepo.loadAll(context: context)
        await examAutopsyRepo.loadAll(context: context)
        await examSimulationRepo.loadAll(context: context)
        await phaseRefresher.recomputeAll()
        await examPlanRepo.loadAll(context: context)
        PlantManager.shared.attach(container: self)
        AchievementManager.shared.bootstrap(container: self)
        SRSReviewNotifications.shared.rescheduleAll(mistakes: mistakeRepo.mistakeSets)
        ExamReviewNotifications.shared.rescheduleAll(exams: examRepo.examSets)
        WidgetDataSyncManager.syncUpcomingExams(
            examSets: examRepo.examSets,
            comprehensiveExamSets: examRepo.comprehensiveExamSets
        )
        TrendWidgetSyncManager.syncTrend(grades: gradeRepo.grades, subjects: subjectRepo.subjects)
    }

#if DEBUG
    /// 仅限测试与预览(Unit Tests & Previews):注入纯内存的 ModelContainer 完成全套 Repo 初始化
    /// Tests & previews only: boot the whole repo stack against an in-memory ModelContainer.
    func asyncTestInit(with testContainer: ModelContainer) async {
        self.modelContainer = testContainer
        let context = testContainer.mainContext
        attachPersistenceExecutor(to: testContainer)

        await loadHighFrequencyRepositories(context: context)
        await phaseRepo.loadAll(context: context)
        await profileRepo.loadAll(context: context)
        await subjectRepo.loadAll(context: context)
        await routineRepo.loadAll(context: context)
        await routineInstanceRepo.loadAll(context: context)
        await diaryRepo.loadAll(context: context)
        await self.coachRepo.loadAll(context: context)
        await self.studySessionRepo.loadAll(context: context)
        await self.timeInvestmentRepo.loadAll(context: context)
        await self.examAutopsyRepo.loadAll(context: context)
        await self.examSimulationRepo.loadAll(context: context)
        await self.examPlanRepo.loadAll(context: context)

        if subjectRepo.subjects.isEmpty {
            subjectRepo.initializeDefaultSubjects()
        }

        await phaseRefresher.recomputeAll()
        isReady = true
    }
#endif

    // MARK: - 跨域操作(转发到子模块,保持调用面不变)
    // MARK: - Cross-domain operations (forward to sub-modules; keep call sites unchanged)

    /// 5 个数据域的 filtered 缓存重算(phase 切换时用)。转发到 `phaseRefresher`。
    /// Recompute the 5 filtered caches (called on phase switch). Forwards to `phaseRefresher`.
    func recomputeAllFiltered() {
        Task { await phaseRefresher.recomputeAll() }
    }

    /// 合并考试 + 待办为统一 TodoEntry(供 TodoView 用)。转发到 `todoAggregator`。
    /// Merge exams + tasks into a unified `TodoEntry` list (for `TodoView`).
    func todoEntries(includeCompleted: Bool = false, phaseId: UUID? = nil) -> [TodoEntry] {
        todoAggregator.entries(includeCompleted: includeCompleted, phaseId: phaseId)
    }

    /// 批量清空数据。转发到 `bulkOps`。
    /// Bulk-clear data. Forwards to `bulkOps`.
    @discardableResult
    func bulkClearData(categories: Set<BulkClearCategory>) -> [(category: BulkClearCategory, count: Int)] {
        bulkOps.clear(categories: categories)
    }

    // MARK: - Passthroughs(原 DataManager 调用习惯的兼容)
    // MARK: - Passthroughs(原 DataManager 调用习惯的兼容) / Passthroughs (legacy DataManager compat)

    /// Subject fullScore(原来 DataManager.fullScore)
    /// Subject `fullScore` (legacy `DataManager.fullScore`).
    func fullScore(for subjectName: String) -> Double {
        subjectRepo.fullScore(for: subjectName)
    }

    /// Subject displayName(原来 DataManager.displayName)
    /// Subject `displayName` (legacy `DataManager.displayName`).
    func displayName(for subjectName: String) -> String {
        subjectRepo.displayName(for: subjectName)
    }

    /// 用户头像异步加载(原来 DataManager.loadAvatarAsync)
    /// Async avatar load (legacy `DataManager.loadAvatarAsync`).
    func loadAvatarAsync() async -> Data? {
        await profileRepo.loadAvatarAsync()
    }

    /// 错题 exposure +1(原来 DataManager.recordMistakeExposure)
    /// Mistake exposure +1 (legacy `DataManager.recordMistakeExposure`).
    func recordMistakeExposure(_ mistakeId: UUID) {
        mistakeRepo.recordExposure(mistakeId)
    }

    /// 切换任务完成态(原来 DataManager.setTaskCompletion)
    /// Toggle task completion (legacy `DataManager.setTaskCompletion`).
    func setTaskCompletion(_ taskId: UUID, isCompleted: Bool) {
        taskRepo.setCompletion(taskId, isCompleted: isCompleted)
        CoachRefreshSignal.markDirty()
    }

    /// 刷新系统 Reminders 完成态(原来 DataManager.refreshTaskCompletionStatesFromReminders)
    /// Refresh task completion state from system Reminders.
    func refreshTaskCompletionStatesFromReminders() {
        taskRepo.refreshCompletionStatesFromReminders()
    }

    /// 切换考试 checklist 状态(原来 DataManager.toggleExamChecklistItem)
    /// Toggle one exam checklist item.
    func toggleExamChecklistItem(_ examId: UUID, itemId: UUID) {
        examRepo.toggleChecklistItem(examId, itemId: itemId)
    }

    /// 启用智能科目推荐(原来 DataManager.applySmartSubjectRecommendation)
    /// Apply smart subject recommendation.
    func applySmartSubjectRecommendation(stage: EducationStage, regionCode: String) {
        subjectRepo.applySmartSubjectRecommendation(stage: stage, regionCode: regionCode)
    }

    /// 初始化默认科目(原来 DataManager.initializeDefaultSubjects)
    /// Initialize default subjects.
    func initializeDefaultSubjects() {
        subjectRepo.initializeDefaultSubjects()
    }

    /// 保存头像并更新 profile(原来 DataManager.saveAvatar)
    /// Save avatar and update profile.
    @discardableResult
    func saveAvatar(_ data: Data) -> String? {
        profileRepo.saveAvatar(data)
    }

    /// 删除头像文件(原来 DataManager.deleteAvatar)
    /// Delete an avatar file.
    func deleteAvatar(filename: String) {
        profileRepo.deleteAvatar(filename: filename)
    }

    /// 提交 onboarding 资料(原来 DataManager.commitOnboardingProfile)
    /// Commit the onboarding profile.
    func commitOnboardingProfile(draft: OnboardingProfileDraft, selectedSubjectNames: [String]) {
        profileRepo.commitOnboardingProfile(draft: draft, selectedSubjectNames: selectedSubjectNames)
    }

    // MARK: - 高层 facade(常用 view 调用习惯)
    // MARK: - 高层 facade(常用 view 调用习惯) / High-level facade (common view call patterns)

    /// 添加单条 grade(带 widget sync / Achievement 副作用)
    /// Add a single grade (triggers widget sync + Achievement side effects).
    func addGrade(_ grade: Grade) {
        gradeRepo.add(grade)
        AchievementManager.shared.recordGradeRecorded()
        // Plant subscriber: 主页植物钩子（不影响 derive 逻辑，仅记录活动 + 订阅 1.5s 内 recompute）
        PlantManager.shared.recordActivity(trigger: .grade)
        TrendWidgetSyncManager.syncTrend(grades: gradeRepo.grades, subjects: subjectRepo.subjects)
        CoachRefreshSignal.markDirty()
    }

    /// 批量添加 grade(带 widget sync / Achievement 副作用)
    /// Batch-add grades (triggers widget sync + Achievement side effects).
    func addGrades(_ newGrades: [Grade]) {
        let count = newGrades.count
        gradeRepo.add(newGrades)
        AchievementManager.shared.recordGradeRecorded(count: count)
        PlantManager.shared.recordActivity(trigger: .grade)
        TrendWidgetSyncManager.syncTrend(grades: gradeRepo.grades, subjects: subjectRepo.subjects)
        CoachRefreshSignal.markDirty()
    }

    /// 删除 grade(带 widget sync)
    /// Delete a grade (triggers widget sync).
    func deleteGrade(_ grade: Grade) {
        gradeRepo.delete(grade)
        TrendWidgetSyncManager.syncTrend(grades: gradeRepo.grades, subjects: subjectRepo.subjects)
    }

    /// 添加错题(带 SRS 调度)
    /// Add a mistake (triggers SRS reschedule).
    func addMistake(_ mistake: MistakeNote) {
        mistakeRepo.add(mistake)
        SRSReviewNotifications.shared.rescheduleAll(mistakes: mistakeRepo.mistakeSets)
        CoachRefreshSignal.markDirty()
    }

    /// 批量添加错题
    /// Batch-add mistakes (triggers SRS reschedule).
    func addMistakes(_ mistakes: [MistakeNote]) {
        mistakeRepo.add(mistakes)
        SRSReviewNotifications.shared.rescheduleAll(mistakes: mistakeRepo.mistakeSets)
        CoachRefreshSignal.markDirty()
    }

    /// 删除错题(带 SRS 取消)
    /// Delete a mistake (triggers SRS reschedule).
    func deleteMistake(_ mistake: MistakeNote) {
        mistakeRepo.delete(mistake)
        SRSReviewNotifications.shared.rescheduleAll(mistakes: mistakeRepo.mistakeSets)
    }

    /// 添加考试(带 Review 通知调度)
    /// Add exams (triggers exam review notification reschedule).
    func addExams(single: [Exam], comprehensive: [comprehensiveExam]) {
        examRepo.add(single: single, comprehensive: comprehensive)
        ExamReviewNotifications.shared.rescheduleAll(exams: examRepo.examSets)
        CoachRefreshSignal.markDirty()
    }

    /// 删除单科考试
    /// Delete a single-subject exam.
    func deleteExam(_ exam: Exam) {
        ExamReviewNotifications.shared.cancel(for: exam.id)
        examRepo.deleteExam(exam)
    }

    /// 删除综合考试
    /// Delete a comprehensive exam.
    func deleteComprehensiveExam(_ exam: comprehensiveExam) {
        examRepo.deleteComprehensiveExam(exam)
    }

    /// 添加待办
    /// Add a task.
    func addTask(_ task: TaskItem, syncToReminders: Bool = false, reminderResult: (calendarItemId: String, calendarId: String)? = nil) {
        taskRepo.add(task, syncToReminders: syncToReminders, reminderResult: reminderResult)
        CoachRefreshSignal.markDirty()
    }

    /// 批量添加待办
    /// Batch-add tasks.
    func addTasks(_ newTasks: [TaskItem]) {
        taskRepo.add(newTasks)
        CoachRefreshSignal.markDirty()
    }

    /// 删除待办(带 Reminder 清理)
    /// Delete a task (cleans up its linked Reminder).
    func deleteTask(_ task: TaskItem) {
        taskRepo.delete(task)
    }

    /// 激活 phase(更新 AppEnvironmentManager + 触发 filtered 重算)
    /// Activate a phase (updates `AppEnvironmentManager` + recomputes filtered caches).
    func activatePhase(_ phase: StudyPhase?) {
        phaseRepo.activate(phase)
    }

    /// Await all currently queued high-frequency writes. Used by lifecycle
    /// coordination and deterministic integration tests.
    func flushPendingPersistence() async {
        await (gradeRepo as? any PersistenceExecutorBacked)?.flushPendingPersistence()
        await (mistakeRepo as? any PersistenceExecutorBacked)?.flushPendingPersistence()
        await (examRepo as? any PersistenceExecutorBacked)?.flushPendingPersistence()
        await (taskRepo as? any PersistenceExecutorBacked)?.flushPendingPersistence()
    }

    func cancelPendingPersistence() {
        (gradeRepo as? any PersistenceExecutorBacked)?.cancelPendingPersistence()
        (mistakeRepo as? any PersistenceExecutorBacked)?.cancelPendingPersistence()
        (examRepo as? any PersistenceExecutorBacked)?.cancelPendingPersistence()
        (taskRepo as? any PersistenceExecutorBacked)?.cancelPendingPersistence()
    }

    private func attachPersistenceExecutor(to container: ModelContainer) {
        let executor = PersistenceExecutor(modelContainer: container)
        persistenceExecutor = executor
        (gradeRepo as? any PersistenceExecutorBacked)?.attachPersistenceExecutor(executor)
        (mistakeRepo as? any PersistenceExecutorBacked)?.attachPersistenceExecutor(executor)
        (examRepo as? any PersistenceExecutorBacked)?.attachPersistenceExecutor(executor)
        (taskRepo as? any PersistenceExecutorBacked)?.attachPersistenceExecutor(executor)
        (routineRepo as? any PersistenceExecutorBacked)?.attachPersistenceExecutor(executor)
        (diaryRepo as? any PersistenceExecutorBacked)?.attachPersistenceExecutor(executor)
        (coachRepo as? any PersistenceExecutorAttachable)?.attachPersistenceExecutor(executor)
        (studySessionRepo as? any PersistenceExecutorAttachable)?.attachPersistenceExecutor(executor)
        (timeInvestmentRepo as? any PersistenceExecutorAttachable)?.attachPersistenceExecutor(executor)
    }

    private func loadHighFrequencyRepositories(context: ModelContext) async {
        guard let executor = persistenceExecutor,
              let grades = gradeRepo as? DefaultGradeRepository,
              let mistakes = mistakeRepo as? DefaultMistakeRepository,
              let exams = examRepo as? DefaultExamRepository,
              let tasks = taskRepo as? DefaultTaskRepository else {
            await gradeRepo.loadAll(context: context)
            await mistakeRepo.loadAll(context: context)
            await examRepo.loadAll(context: context)
            await taskRepo.loadAll(context: context)
            return
        }

        do {
            let snapshots = try await executor.loadHighFrequencySnapshots(
                activePhaseID: envManager.activePhaseId
            )
            try Task.checkCancellation()
            grades.publishStartupSnapshots(
                snapshots.grades,
                filtered: snapshots.filteredGrades
            )
            mistakes.publishStartupSnapshots(
                snapshots.mistakes,
                filtered: snapshots.filteredMistakes
            )
            exams.publishStartupSnapshots(
                single: snapshots.exams,
                filteredSingle: snapshots.filteredExams,
                comprehensive: snapshots.comprehensiveExams,
                filteredComprehensive: snapshots.filteredComprehensiveExams
            )
            tasks.publishStartupSnapshots(
                snapshots.tasks,
                filtered: snapshots.filteredTasks
            )
        } catch is CancellationError {
            Log.data.debug("High-frequency repository startup load cancelled")
        } catch {
            Log.data.error("High-frequency repository startup load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 例程 (Routine) 域 facade
    // MARK: - 例程 (Routine) 域 facade / Routine facade

    /// 添加例程模板
    /// Add a routine template.
    func addRoutine(_ routine: Routine) {
        routineRepo.add(routine)
        NotificationCenter.default.post(name: .routineDataChanged, object: nil)
    }

    /// 批量添加例程
    /// Batch-add routine templates.
    func addRoutines(_ newRoutines: [Routine]) {
        routineRepo.add(newRoutines)
        NotificationCenter.default.post(name: .routineDataChanged, object: nil)
    }

    /// 更新例程模板
    /// Update a routine template.
    func updateRoutine(_ routine: Routine) {
        routineRepo.update(routine)
        NotificationCenter.default.post(name: .routineDataChanged, object: nil)
    }

    /// 删除例程模板(同时清理未来未开始的 instance)
    /// Delete a routine template (and any future-not-started instances).
    func deleteRoutine(_ id: UUID) {
        // 先清理关联 instance
        // First clear linked instances.
        let toDelete = routineInstanceRepo.allInstances.filter { $0.routineId == id }
        for inst in toDelete {
            routineInstanceRepo.delete(inst.id)
        }
        routineRepo.delete(id)
        NotificationCenter.default.post(name: .routineDataChanged, object: nil)
    }

    /// 设置例程启用
    /// Enable or disable a routine.
    func setRoutineEnabled(_ id: UUID, enabled: Bool) {
        routineRepo.setEnabled(id, enabled: enabled)
        NotificationCenter.default.post(name: .routineDataChanged, object: nil)
    }
}
