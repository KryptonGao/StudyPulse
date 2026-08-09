# StudyPulse — AI Agent Guide

> 一份面向 AI 代理的完整开发指南。
> 本文件仅使用纯文本和代码块描述架构，不使用任何表格或 ASCII 流程图。

---

## 1. 项目速览

StudyPulse 是一个使用 SwiftUI 构建的 iOS 学业管理应用，帮助学生
追踪成绩、管理错题、规划考试、与 HealthKit 同步 HRV / 多维身体信号
（心率 / 呼吸率 / 深睡+REM / 锻炼）并给出个性化学习建议与趋势分析；
同时提供学习日记 + 心情记录、周计划例程、虚拟植物养成、主题商店、
AI 自测 / 相似题 / 思维导图 / 错题辩论、习惯洞察、长期时间投入（Time Investment）等扩展模块。
支持多种全球教育体系（中国大陆、浙江、上海、台湾、香港、新加坡、UK IGCSE 与 A-Level、IB DP、US AP / SAT / ACT、GRE / GMAT、TOEFL / IELTS 等）。

平台：iOS 18.6+，同时支持 iPhone 与 iPad。
语言：Swift 6.0。
架构：MVVM + Repository 模式。
  - 视图层（`Views/`）只做 SwiftUI 渲染与用户交互。
  - 5 个主页面（Home / Trends / Mistake / Exam / Todo）+ 1 个子页面（`SubjectMistakesViewModel`）各持一个 `@MainActor final class XxxViewModel: ObservableObject`，状态为 `@Published private(set)`，由父 View 通过 `static func makeDefault(container:)` 工厂创建。
  - 数据访问通过 16 个 Repository（`Repositories/Protocols/*Repository.swift` + `Default*Repository` 实现），由 `RepositoryContainer`（`@Observable @MainActor`）聚合。View / ViewModel 通过 `@Environment(RepositoryContainer.self) var container` 注入。
  - 纯函数业务逻辑抽到 `Services/`（DateFormatters / SubjectAggregator / SuggestionEngine / ExamFilter / MistakeFilter / DailyPlanEngine / QuoteProvider / TimeInvestmentEngine），**不依赖 SwiftUI**（仅 `QuoteProvider` 例外，因为 `StudySuggestion.color: Color`）。
并发：Swift 6 Strict Concurrency，默认 Actor 隔离为 MainActor。
构建：Xcode 26.x。
依赖：本地包 `SwiftStreamingMarkdown`（位于 `Packages/`）；Vendored 包 `swift-cmark` / `swift-markdown` / `highlightswift` / `iosMath`（位于 `Packages/Vendored/`）。
存储：SwiftData 实体层（`Models/SwiftData/StudyPulseModels.swift`，@Model 实体）作为持久化后端，采用版本化 schema 迁移（`Models/SwiftData/Schema/` 下 `StudyPulseSchemaV1`–`V4` + `StudyPulseMigrationPlan`，当前生产 schema V4）；进程内单例 `ModelContainerFactory.makeContainer()`，启动时由 `ModelContainerFactory.migrateFromJSONIfNeeded(context:)` 一次性从老 `~/Documents/*.json` 迁移；视图层继续使用 `nonisolated value type` 的 struct；偏好设置、主页顺序、phase 激活、每日目标保存在 UserDefaults；健康历史 `~/Documents/health_history.json`；学习会话由 `StudySessionRepository` 承载到 SwiftData `StudySessionRecord`（整个 `StudySession` 的 JSON 编码进 `payload: Data`，`startDate` 建索引），老 `study_sessions.json` 启动时合并导入；成就 `~/Documents/achievements.json`。
应用组：`group.com.chenkai.gao.studypulse`，用于小组件与 Live Activity 数据同步。
本地化：English、简体中文、繁體中文、日本語、한국（主应用与小组件各自维护五份 Localizable.strings）。
图表：SwiftUI Charts。
OCR：Vision 框架 `VNRecognizeTextRequest`。
日历：EventKit（支持具体时间段或全天事件）。
健康：HealthKit HRV（SDNN）+ BodyStatus（心率 / 呼吸率 / 睡眠 / 锻炼）。
小组件：WidgetKit 三个静态小组件（ExamWidget / TrendWidget / HRVWidget）+ 一个 Live Activity（StudyTimerLiveActivity），已接入 StudyPulse.xcodeproj。
工程文件：StudyPulse.xcodeproj（含 StudyPulse + StudyPulseWidgetExtension 两个目标）。
测试：`StudyPulseTests/` 目标，含 `Infrastructure/`（fixture / TestModelContainer / TestRepositoryContainer 工厂）+ `TestDoubles/`（Mock Repository）+ Services / Algorithm 单元测试。
基础设施：统一日志层（os.Logger + actor 隔离的 LogStore 内存缓冲 + LogDocument 导出）；主线程卡顿监测（LagMonitor）；AppIntents 跨进程桥接（`IntentActionStore`）；全量备份/恢复（`Managers/Backup/`，导出成 `.studypulsebackup` 归档文件，含校验与恢复协调）。

---

## 2. 仓库布局

仓库根目录包含以下核心内容：

- `StudyPulse.xcodeproj`：Xcode 工程，含 StudyPulse 主应用 + StudyPulseWidgetExtension 小组件两个目标。
- `Packages/`：本地 / Vendored 包。
  - `SwiftStreamingMarkdown-0.2.0/`：Markdown 渲染（支持 LaTeX 公式与流式输出）。
  - `Vendored/`：swift-cmark（cmark-gfm 核心）、swift-markdown、highlightswift（代码高亮）、iosMath（LaTeX 数学）。
- `StudyPulse/`：主应用源代码目录。
  - `StudyPulseApp.swift`：`@main` 入口，持有 `RepositoryContainer`（`@Observable @MainActor`）+ 三个 `@StateObject` 单例（`AppEnvironmentManager.shared` / `HealthKitManager.shared` / `StudyTimerManager.shared`），注册通知代理、启动 `LagMonitor.shared`。`.task` 中先 `await container.asyncInit()`（一次性 JSON 迁移 + 16 repo 串行 `loadAll` + 内嵌图片迁移 + SubjectRepo 默认科目 + `RoutineSpawner.runOnce()`），`isReady == true` 后才 `await hrvManager.bootstrap()` 与 `AchievementManager.shared.bootstrap(container:)` 与 `PlantManager.shared.bootstrap(container:)`，并 `timerManager.attach(sessionRepository:timeInvestmentRepository:)`；`scenePhase == .active` 时统一 `WidgetDataSyncManager.syncUpcomingExams(...)` / `TrendWidgetSyncManager.syncTrend(...)` / `HRVWidgetSyncManager.syncHRV(...)` + `SRSReviewNotifications.shared.rescheduleAll(...)` + `ExamReviewNotifications.shared.rescheduleAll(...)` + `DiaryReminderNotifications.shared.reschedule(...)` + `HabitInsightNotifications.shared.reschedule(...)` + `container.taskRepo.refreshCompletionStatesFromReminders()` + `RoutineSpawner.shared.runOnce()`。
  - `StudyPulse.entitlements`：开启 `com.apple.developer.healthkit` / `com.apple.security.application-groups` / `NSSupportsLiveActivities` 权限。
  - `StudyPulseWidgetExtension.entitlements`：小组件目标 entitlements（App Groups + WidgetKit + Live Activity）。
  - `Assets.xcassets`：AccentColor、AppIcon、StudyPulseIcon（含 SVG 源图）。
  - `Models/`：数据模型定义。
    - `DataModels.swift`：`StudyPhase` / `PhaseGoal` / `Subject` / `Grade` / `MistakeNote` / `MasteryHistoryEntry` / `HandwritingAnswerEntry` / `Exam` / `comprehensiveExam` / `UserProfile` / `ExamTimeSlot` / `TaskItem` / `TaskType` / `TodoEntry` / `TodoEntryKind` / `ExamChecklistItem` / `ExamReview` / `RoutineType` / `Routine` / `RoutineInstance` / `DiaryEntry`。
    - `AppPreferences.swift`：应用偏好（语言 + 主题 + 图表类型 + 主色预设 + `glassEffectEnabled` + `learningHeatmapOnTrends` + `activePhaseId` + LLM 配置 + `lastRadarAIRequestTime` / `lastStudySuggestionsAIRequestTime` 冷却时间戳），自定义 `init(from:)` 用 `decodeIfPresent` 给默认值，**向后兼容老 UserDefaults 数据**。
    - `HomeLayoutPreference.swift`：主页卡片顺序与启用标记（17 个 `HomeCardType`）。
    - `HealthHistory.swift`：`DailyHealthSnapshot`。
    - `StudySession.swift`：已完成学习会话记录。
    - `SpacedRepetition.swift`：`ReviewState`（SM-2 算法核心）。
    - `Achievements.swift` + `AchievementCatalog.swift`：成就目录 + 进度。
    - `StudyReport.swift`：学习报告不可变 value type。
    - `MistakePDFSnapshot.swift`：错题 PDF 导出快照。
    - `AIQuizModels.swift`：`QuizQuestion` AI 自测题模型（选择题 / 填空题，含 Markdown + LaTeX）。
    - `HabitInsight.swift`：`HabitInsight` 习惯洞察 + `HabitInsightEngine` 纯函数引擎（90 天学习会话聚合 → 4 类 PatternKind）。
    - `ThemeShop.swift`：`AccentPalette` / `CardSkin` / `TimerAnimation` 三类皮肤目录 + `ThemeShopCatalog` 静态目录；解锁条件绑定 `AchievementDefinition.id`。
    - `PlantState.swift`：`PlantStage`（8 阶段状态机）+ `PlantStageTransition` 历史 + 纯函数 `derive(...)`。
    - `PlantStateRecord.swift`：植物状态 SwiftData 持久化（仅 1 个实体，stage + history JSON）。
    - `SwiftData/StudyPulseModels.swift`：`@Model` 实体层（`SubjectRecord` / `GradeRecord` / `MistakeNoteRecord` / `ExamRecord` / `ComprehensiveExamRecord` / `UserProfileRecord` / `TaskItemRecord` / `ReviewStateRecord` / `StudyPhaseRecord` / `PlantStateRecord` / `RoutineRecord` / `RoutineInstanceRecord` / `DiaryEntryRecord` / `StudySessionRecord` / `TimeInvestmentSubjectRecord` / `SubTaskRecord` / `GoalRewardRecord` / Coach 系列 / ExamGoalRecord / ExamPlanRecord 等），提供 `toSnapshot()` / `init(from:)`，由 `ModelContainerFactory` 启动时自动从 JSON 迁移。`GradeRecord` / `ExamRecord` / `MistakeNoteRecord` / `TaskItemRecord` / `RoutineRecord` 都带 `phaseId: UUID?` 索引字段（`#Index<...>` 注释触发 B-Tree）；`StudySessionRecord` 用 `payload: Data` 存整个 `StudySession` JSON（`startDate` 建索引）。
    - `SwiftData/Schema/`：版本化 schema（`StudyPulseSchemaV1`–`V4` + `StudyPulseMigrationPlan`）。V1 含核心 12 实体 + Coach / StudySession / Exam 复盘 / 模拟 / 计划系列；V2 增加 `StudyPulseSchemaMetadataRecord`；V3 增加 `ExamGoalRecord` / `ExamPlanRecord`；V4 增加 `TimeInvestmentSubjectRecord` / `SubTaskRecord` / `GoalRewardRecord`。`ModelContainerFactory` 用 `Schema(versionedSchema: StudyPulseSchemaV4.self)` + `migrationPlan: StudyPulseMigrationPlan.self`（轻量迁移）。
    - `TimeInvestment.swift`：长期时间投入域模型（`TimeInvestmentSubject` / `SubTask` / `InvestmentTarget` / `GoalReward` + `TimeInvestmentTheme` 5 色主题 + `StudySessionSource`：timer / manual）。独立于学科 `Subject` 模型。
  - `Managers/`：业务逻辑层（按子领域拆分子目录）。
    - `Core/`：
      - `RepositoryContainer.swift`：`@Observable @MainActor` 容器。持有 16 个 Repository + `envManager` + `intentStore` + `modelContainer` + `isReady` + `pendingIntentAction`（桥接 `IntentActionStore`）+ 3 个跨域编排子模块（`bulkOps` / `todoAggregator` / `phaseRefresher`，Phase 3 拆分后由独立文件组合）。`asyncInit()` 执行 JSON 迁移 + 各 repo 串行 `loadAll` + 内嵌图片迁移 + 通知/widget 调度 + `RoutineSpawner.runOnce()`；`observeActivePhaseChanges()` 用 0.5s polling 监测 `AppEnvironmentManager.shared.activePhaseId` 变化触发 `recomputeAllFiltered()`；`recomputeAllFiltered()` 重算 6 个 `filtered*` 缓存（grade / mistake / exam / task / routine / diary）；`todoEntries(includeCompleted:phaseId:)` 跨域聚合 Exam + comprehensiveExam + TaskItem + RoutineInstance 为 `TodoEntry`；`bulkClearData(categories:)` 批量清空；并提供 `addGrade` / `addGrades` / `addMistake` / `addMistakes` / `addExams` / `addTask` / `addTasks` / `addDiary` / `addRoutine` / `deleteXxx` / `activatePhase` 等 facade 方法。
      - `AppEnvironmentManager.swift`：全局 `AppPreferences` 管理 + `effectiveAccentColor`（11 档 `ThemeAccent`） + `activePhaseId`。
      - `AppStyle.swift`：应用设计系统骨架。
      - `CSVDocument.swift`：`FileDocument` 包装 CSV。
      - `DataExportManager.swift`：CSV 导出（`@MainActor` enum）。
      - `ModelContainerFactory.swift`：SwiftData `ModelContainer` 单例工厂 + `migrateFromJSONIfNeeded(context:)` 一次性迁移（UserDefaults flag 避免重复）；`modelTypes` 数组 = `StudyPulseSchemaV4.models`；容器用 `Schema(versionedSchema: StudyPulseSchemaV4.self)` + `migrationPlan: StudyPulseMigrationPlan.self`。
    - `Health/`：
      - `HealthKitManager.swift`：HRV（SDNN）准备度、14 天基线、日级历史、BodyStatus、PersonalBaselines 30 天个人基线。
      - `HealthHistoryStore.swift`：`DailyHealthSnapshot` 30 天滚动持久化（NSLock 线程安全）。
      - `StudyReadinessAlgorithm.swift`：多维学习准备度算法（5 强度 × 5 重点）。详细说明见 `docs/algorithms/AlgorithmIntroduction.md`。
    - `Logging/`：
      - `Log.swift`：`LogLevel` / `LogEntry` / `LogStore`（actor 隔离并发安全，5000 条上限，超出丢最早条目）；`Log.app` / `Log.widget` / `Log.notification` / `Log.ui` / `Log.data` / `Log.study` / `Log.health` 等 subsystem category；`Log.record(_:category:message:)` 同时写 `os.Logger` 与 `LogStore`。
      - `LogDocument.swift`：`FileDocument` 包装内存日志。
      - `LagMonitor.swift`：`CADisplayLink` 主线程卡顿检测器。
    - `PDF/`：
      - `MistakePDFRenderer.swift`：错题 PDF 渲染器（`@MainActor` enum）；Core Text + `NSAttributedString` 渲染多页 A4（595×842 pt）PDF。
      - `MistakePDFDocument.swift`：`FileDocument` 包装 `.pdf` UTType。
    - `Report/`：
      - `ReportRenderer.swift`：`ImageRenderer` + Core Graphics 输出 PNG / JPEG。
      - `ReportImageDocument.swift`：`FileDocument` 包装报告图像。
    - `Study/`：
      - `StudyTimerManager.swift`：`@MainActor` ObservableObject，5 档强度 + Live Activity 协调；**学习会话统一走 `StudySessionRepository`**（`sessions` 数组 + `StudySessionStore` 聚合），`selectInvestmentTarget(_:)` 为当前会话绑定 `InvestmentTarget`（持久化到 UserDefaults 供跨启动恢复），`complete()` 时 `upsert` 到 `container.studySessionRepo`。
      - `DailyGoalReminder.swift`：每日 20:00 晚间提醒。
      - `SRSReviewNotifications.swift`：错题间隔重复复习通知。
      - `ExamReviewNotifications.swift`：考试复盘提醒（按 `countdownNotifyDays` 调度）。
      - `DiaryReminderNotifications.swift`：学习日记晚间提醒（可配置时间，identifier 前缀 `DiaryReminder_`）。
      - `HabitInsightNotifications.swift`：习惯洞察定时推送（在用户历史峰值时段前提示「今日最佳学习窗口」，identifier 前缀 `HabitInsight_`）。
    - `Plan/`：例程（Routine）子系统。
      - `RoutineSpawner.swift`：`@MainActor @Observable` 单例；监听 `enabledRoutines` + 60s 跨日 polling + routine 增删触发；`spawnForToday(now:)` 幂等（按 `routineId|yyyyMMdd` 去重）产生 `RoutineInstance`；`runOnce()` 还会触发 `cleanupStale(olderThanDays: 30)`。
      - `RoutineLiveActivityController.swift`：`ActivityKit` Live Activity 协调器；mistakeReview 类型的 routine spawn 后启动 `RoutineActivityAttributes` Live Activity，完成后 dismiss。
    - `Plant/`：虚拟植物养成子系统。
      - `PlantManager.swift`：`@MainActor @Observable` 单例；订阅 `AchievementManager.shared.snapshot` 变化 → 调用 `PlantStage.derive(...)` 重算 `currentStage`；持 `history` 阶段切换记录；`recordActivity()` 由 `RepositoryContainer.addGrade` / `addMistake` 触发。
      - `PetalColorCatalog.swift`：花瓣配色静态目录（按 stage 提供主色 + 渐变色）。
    - `Utility/`：
      - `CalendarManager.swift`：EventKit（考试 + 任务 Reminders）。
      - `EducationConfig.swift`：全球教育体系静态配置（`nonisolated` enum）。
      - `ImageCache.swift`：`nonisolated` class，`NSCache` 50 条缩略图。
      - `OCRManager.swift`：Vision 文本识别。
      - `StringsLocalized.swift`：`.localized()` 扩展。
      - `SubjectInfo.swift`：展示名称与颜色、满分回退。
    - `Widget/`：
      - `ExamWidgetData.swift` / `WidgetDataSyncManager.swift`。
      - `HRVWidgetData.swift` / `HRVWidgetSyncManager.swift`。
      - `TrendWidgetData.swift` / `TrendWidgetSyncManager.swift`。
    - `Achievement/`：
      - `AchievementManager.swift`：`@MainActor` ObservableObject 单例；`recordGradeRecorded` / `recordMistakeReviewed` / `recordFocusMinutes` 三个事件入口；`updateConfig` 改每日目标；`handleDayRolloverIfNeeded` 跨日滚动；`bootstrap(container:)` 在 `RepositoryContainer.isReady` 之后调用。
      - `AchievementStore.swift`：`AchievementsSnapshot` 的 JSON 持久化（NSLock 线程安全，含首次启动从 `grades.json` / `study_sessions.json` 反推 30 天历史）。
    - `Audio/`：
      - `AudioStorage.swift`：`nonisolated` struct，封装 `~/Documents/audio/` 目录 + 唯一文件名生成（`<uuid>.m4a`）+ 删除。
      - `VoiceMemoManager.swift`：`@MainActor` ObservableObject，封装 `AVAudioRecorder` 录音会话（请求麦克风权限、启动 / 暂停 / 停止 / 删除）。
    - `Backup/`（全量备份 / 恢复子系统）：`BackupExporter`（SwiftData 实体 + UserDefaults + App Group 数据导出为 `.studypulsebackup` 归档）/ `BackupImporter` / `BackupManifest`（格式标识 + schemaVersion = 4 + recordCounts + 媒体文件统计）/ `BackupValidator`（恢复前校验 + 校验和）/ `BackupChecksum` / `BackupRestoreCoordinator` / `BackupArchive` / `BackupDTOs` / `BackupDocument`（`FileDocument` 包装备份文件）/ `BackupError`。入口在 `DataManagementSettingsView` → `BackupRestoreView`（`Views/Settings/`），View 层有 `BackupRestoreViewModel`（`ViewModels/`）。
    - `LLM/`（BYOK 大模型子系统）：
      - `LLMConfig.swift`：`nonisolated` value type，从 `AppPreferences` 桥接 `enabled / baseURL / apiKey / model / systemPromptAppendix / temperature / overrideSystemPrompt`；`isConfigured` 判定三字段全非空。
      - `LLMError.swift`：`notConfigured` / `invalidURL` / `unauthorized`（401）/ `rateLimited`（429）/ `serverError(statusCode:body:)` / `network` / `malformedResponse` / `emptyResponse` / `timeout`；服务端 4xx 错误时 `body` 拼进 `errorDescription` 便于诊断。
      - `LLMPrompt.swift`：`nonisolated` struct，封装 `system` / `[user,assistant]` 消息 + 工具函数 `toMessages()` / `tokensApprox()`。
      - `LLMRequestBuilder.swift`：Phase 3 拆分后基类只保留 `latexFormattingRule` + 通用辅助；按 caller 拆为 6 个独立文件：`MistakeAIAnalysisLLM`（错题 AI 解析，三段输出）/ `BodyRadarLLM`（雷达建议，四段输出）/ `HomeAskLLM`（主页 AI 问答 + Router + Answer）/ `AIQuizLLM`（AI 自测题生成 + 批改）/ `AISimilarQuestionLLM`（相似题生成 + 批改）/ `AIDiscussionLLM`（深入探讨 + 通用聊天）；基类还保留 `StudySuggestionsLLM` / `WeeklyReportLLM` / `ScorePredictionLLM` / `ComprehensiveScorePredictionLLM`。所有 caller **固定输出格式**（`## 错因分析/## 正确思路/## 类似题建议` 或 `## 强度/标题/建议/依据`）便于解析回写本地模型。
      - `LLMResponseParser.swift`：`enum LLMResponseParser` 把 LLM 输出按 `## 段落名` 切分并合并回 `StudySuggestion` / 错因分析 / 周报总结 / 雷达建议，**保留本地 `icon/priority/color`**，只替换 `title/description`。
      - `LLMResponseCache.swift`：`actor` 隔离的 LLM 响应缓存（按 prompt hash + caller 做磁盘/内存缓存，避免短时间重复请求；命中即返回，未配置 LLM 或失败时也能用上次成功的输出兜底）。
      - `LLMClient.swift`：`@MainActor` ObservableObject 单例（`LLMClient.shared`）；`complete(prompt:config:caller:)` 非流式 / `stream(prompt:config:caller:onDelta:)` 流式；自动注入 `Authorization: Bearer` / 构造 Chat Completions 请求体 / 解析 SSE 流 / 拆分 `LLMError`；DEBUG 模式下每次调用写 `LLMCallDebugInfo` 到 `lastCallInfo` + 环形 20 条 `recentCalls` 缓冲。**必须从环境注入 `AppPreferences`**（`@EnvironmentObject`），不要直接 `AppPreferences()` 初始化器。
      - `HomeAskDataProvider.swift`：`enum HomeAskDataProvider` 把用户输入关键词匹配到 4 类上下文（`grade` / `mistake` / `trend` / `readiness`）之一，组合成 HomeAskLLM 的 prompt。
      - `AutoMindMapLLM.swift`：错题思维导图 LLM；输入错题四块内容，输出结构化节点 JSON 给 `AutoMindMapViewModel` 渲染。
  - `Repositories/`：16 域 Repository（`Repositories/Protocols/` 协议 + `Default*Repository` 实现）。
    - `Protocols/`：
      - `GradeRepository.swift`：`@MainActor` protocol；`grades` / `filteredGrades` + CRUD + `migrateInlineImagesIfNeeded()` + `reloadFromSwiftData()`。
      - `MistakeRepository.swift`：`mistakeSets` / `filteredMistakeSets` + CRUD + `recordExposure(_:)`。
      - `ExamRepository.swift`：单科 Exam + 综合 comprehensiveExam + `filtered*` + CRUD + 复盘（`updateExamReview`）+ checklist（`toggleChecklistItem` / `setChecklist`）。
      - `TaskRepository.swift`：作业 / 阅读 + Reminders 同步 + `filteredTaskItems` + `refreshCompletionStatesFromReminders`。
      - `PhaseRepository.swift`：StudyPhase CRUD + `activate(_:)` + `archive` + 跨域清理 `phaseId` 引用（注入 gradeRepo / mistakeRepo / examRepo / taskRepo / routineRepo / diaryRepo 的 weak 引用）。
      - `ProfileRepository.swift`：UserProfile + 头像。
      - `SubjectRepository.swift`：科目 + 满分 + 智能推荐 + 默认科目初始化。
      - `RoutineRepository.swift`：`routines` / `enabledRoutines` / `filteredRoutines` + CRUD + `setEnabled(_;enabled:)`。
      - `RoutineInstanceRepository.swift`：`allInstances` / `todayInstances` / `activeInstances` + 幂等 `spawnIfMissing(_:)` + `setCompletion(_;isCompleted:)` + `cleanupStale(olderThanDays:)`。
      - `DiaryRepository.swift`：`diaryEntries` / `filteredDiaryEntries` + CRUD + `entriesInRange(_:_:)` + `todayEntry()`。
      - `CoachRepository.swift`：AI 学习教练对话（`coachRepo`）。
      - `StudySessionRepository.swift`：学习会话（`sessions` 数组 + `loadAll(context:)` / `upsert(_:)` / `delete(_:)` / `assign(_:to:)` 批量绑定 `InvestmentTarget` / `session(id:)` / `refreshFromLegacyJSON()`）。
      - `TimeInvestmentRepository.swift`：长期时间投入项目（`timeInvestmentRepo`）。
      - `ExamAutopsyRepository.swift`：考试复盘（`examAutopsyRepo`）。
      - `ExamSimulationRepository.swift`：考试模拟（`examSimulationRepo`）。
      - `ExamPlanRepository.swift`：考试计划（`examPlanRepo`）。
    - `RepositoryContainer.swift`：16 个 Repository + `envManager` + `intentStore` 聚合 + 跨域编排（见上 `Managers/Core/`）。
    - `BulkOperationOrchestrator.swift`：Phase 3 拆出；按 category 批量清空各 repo 的数据。
    - `TodoAggregator.swift`：Phase 3 拆出；`aggregate(includeCompleted:phaseId:)` 把 Exam + comprehensiveExam + TaskItem + RoutineInstance 合并为 `TodoEntry`。
    - `PhaseFilterRefresher.swift`：Phase 3 拆出；`recomputeAllFiltered()` 重算 6 个 `filtered*` 缓存（grade / mistake / exam / task / routine / diary）。
    - `ImageStorage.swift`：图片文件 I/O 抽象。
    - `PersistenceExecutor.swift`：SwiftData Predicate-backed fetch 查询执行器，封装 `#Predicate` 条件查询与 SwiftData Context 操作。
    - `IntentActionStore.swift`：AppIntents 跨进程桥接（pendingIntentAction 镜像）。
  - `Services/`：纯函数服务。
    - `DateFormatters.swift`：统一日期格式 + locale 切换。
    - `SubjectAggregator.swift`：`aggregate(grades:subjects:recentDays:referenceDate:includeRecentCount:)` 单次 O(n) 分组聚合，返回 `[String: SubjectAggregate]`（subject / average / count / recentCount / sortedAsc）。
    - `SuggestionEngine.swift`：`generate(from: StudySuggestionsContext, max:)` 学习建议生成。
    - `ExamFilter.swift`：`examsWithinDays(_:exams:)` + `unregisteredExams(startDaysAgo:endDaysAgo:grades:exams:)`。
    - `MistakeFilter.swift`：错题筛选与排序。
    - `DailyPlanEngine.swift`：今日 Top-3 计划生成器；从 exam / mistake SRS / routine / task 中按截止日期与紧迫度排序产生 3 条建议。
    - `QuoteProvider.swift`：每日金句；持有 `Color`，是唯一依赖 SwiftUI 的服务。
    - `TimeInvestmentEngine.swift`：`TimeInvestmentAggregator` 纯函数聚合器；按 `InvestmentTarget`（subject / subTask，含子任务后代汇总）从 `[StudySession]` 聚合直接 / 总投入秒数 + 连续打卡天数。
  - `ViewModels/`：22 个 ViewModel（5 主页面 + 1 子页面 + 独立 sheet / 流程 ViewModel）。
    - `HomeViewModel.swift`：`@MainActor ObservableObject`；SRS 概览 / 近期成绩 / 即将到来考试 / 未登记考试 / 图表选科（5 档 `SubjectSelectionRule`）；`recompute()` / `selectChartSubject(rule:)` / `gradesForSubject(_:)` / `generateSuggestions(limit:)`。
    - `TrendsViewModel.swift`：趋势图数据 + 关注科目聚合。
    - `MistakeViewModel.swift`：错题列表 + 分组 + 搜索。
    - `SubjectMistakesViewModel.swift`：按科目的错题子页。
    - `ExamViewModel.swift`：考试列表 + 倒计时 + 复盘。
    - `TodoViewModel.swift`：统一待办聚合 `container.todoEntries(...)`。
    - `AddGradeViewModel.swift` / `NewExamSetViewModel.swift` / `NewMistakeSetViewModel.swift`：模态表单 ViewModel（封装校验、默认值、关联科目 / phase 处理）。
    - `MistakeDetailEditViewModel.swift`：错题编辑 ViewModel（EditSection 枚举 + OCR + 图片管理 + 语音备忘录 + SRS 入队）。
    - `HomeAskViewModel.swift`：主页 AI 问答 ViewModel（输入关键词 → `HomeAskDataProvider` 选上下文 → 调用 LLM）。
    - `LLMChatViewModel.swift`：通用 AI 聊天 ViewModel（in-memory 历史，离开页面清空）。
    - `AutoMindMapViewModel.swift`：错题思维导图 ViewModel（调 `AutoMindMapLLM` → 节点 JSON → 树渲染）。
    - `FlashcardStudyViewModel.swift`：闪卡复习 ViewModel（SM-2 调度 + 会话状态）。
    - `TimeInvestmentViewModel.swift`：长期时间投入主页 ViewModel（项目汇总 `ProjectSummary` / subTask 树 / 奖励 `GoalReward` / 未分配会话 `unassignedSessions` / 全局连续天数 `globalStreak`；`makeDefault(container:)` 工厂）。
    - `BackupRestoreViewModel.swift`：备份 / 恢复流程 ViewModel。
    - `CoachViewModel.swift` / `CoachConversationViewModel.swift`、`ExamAutopsyViewModel.swift` / `ExamReversePlannerViewModel.swift` / `ExamSimulationViewModel.swift`、`KnowledgeFaultLineViewModel.swift`：AI 教练 / 考试复盘 / 知识断层线等扩展流程 ViewModel。
    - `ViewModelError.swift`：错误类型。
  - `Views/`：SwiftUI 视图（按子领域拆分子目录）。
    - `ContentView.swift`：根视图。iPhone 使用 `TabView`（5 个标签：Home / Trends / Mistakes / Exams / Settings）；iPad 使用自定义 `NavigationSplitView` 侧栏。同时观察 `IntentActionStore` 处理 Siri Shortcuts 跨进程跳转（监听 `pendingIntentAction`，处理后清空）。
    - `Home/`：`HomeView.swift` 主页仪表盘（分帧渲染 + 接收 `HomeViewModel`）；`HomeLayoutSettingsView.swift`；`HomeUIState.swift`；`HomeRecomputeModifier.swift`（phase / language 切换时触发 recompute）；`HomeCards/`（11 张卡片：`WelcomeHeaderCard` / `MainStatsCard` / `QuickActionsCard` / `RecentGradesCard` / `TrendChartCard` / `UpcomingExamsCard` / `StudySuggestionsCard` / `HomeAskCard` / `DailyPlanCard` / `DiaryHomeCard` / `HabitInsightCard`）。
    - `Trends/`：`TrendsView.swift` 趋势分析（顶部可选 `LearningHeatmapView`，受 `AppPreferences.learningHeatmapOnTrends` 控制）。
    - `Exam/`：`ExamView.swift` / `ExamCalendarView.swift`（Phase 3 拆分后 + 3 sub-files：`ExamCalendarModels` / `ExamCalendarDayCell` / `ExamCalendarItemRow`）/ `ExamDetailView.swift`（Phase 3 拆分后 + 4 sub-files：`ChecklistRowView` / `RelatedMistakeCard` / `ReviewSectionRow` / `LinkedMistakesListView`；入口改为 `examId: UUID` 从 `container.examRepo` 实时查 `liveExam`）/ `ComprehensiveExamDetailView.swift`（综合考试详情）/ `ExamDetailEditView.swift` / `NewExamSetView.swift` / `ExamReviewView.swift` / `ScorePredictionEngine.swift` / `ScorePredictionSheet.swift` / `ScorePrediction/`（`SingleSubjectPrediction` / `ComprehensivePrediction` / `PredictionDiscussionEntry`）。
    - `Grade/`：`AddGradeView.swift` / `SubjectScoreCard.swift`。
    - `Mistake/`：
      - `MistakeView.swift`（Phase 3 拆分后 374 行 + 3 sub-files：`MistakeListCellViews` / `DueReviewBanner` / `SubjectMistakesView`；toolbar 含 PDF 导出 + 加入 SRS 队列按钮）。
      - `MistakeSetDetailView.swift`（Phase 3 拆分后 408 行 + 2 sub-files：`MistakeSetHeaderSection` / `MistakeSetContentSection`；详情页 toolbar 含 ✨ AI 解析按钮 + AI 相似题 + AI 思维导图 + 错题辩论 Menu；嵌入 `AudioPlaybackView`）。
      - `MistakeDetailEditView.swift`（编辑页；EditSection 枚举驱动四块编辑；语音备忘录 + OCR + 手写答题 `HandwritingSheet`）。
      - `MistakeToolbar.swift` / `MistakeSearchBar.swift`：错题列表工具栏与搜索栏。
      - `NewMistakeSetView.swift`。
      - `AutoMindMapView.swift`：AI 自动思维导图（基于 `AutoMindMapViewModel` + 节点 JSON 渲染树）。
      - `MistakeDebateSheet.swift`：错题辩论 sheet（LLM 多轮对话，引导学生反思错解）。
      - `TagGraphView.swift` + `TagGraphEdges.swift` + `TagGraphLayout.swift`：标签图谱视图（按 tag 关联错题，用力导向布局）。
      - `HandwritingView.swift` / `HandwritingSheet.swift`：手写答题画布（`PKCanvasView` + `HandwritingAnswerEntry` 持久化）。
      - `PDF/MistakePDFExportSheet.swift` / `PDF/MistakePDFGenerationView.swift`。
      - `Audio/AudioPlaybackView.swift`（详情页内嵌播放）/ `Audio/VoiceMemoRecordingSheet.swift`（编辑页录音 sheet）。
      - `LLM/AISimilarQuestionFlowView.swift`（AI 相似题组卷流程）/ `LLM/AIQuizSetupView.swift` / `LLM/AIQuizView.swift` / `LLM/AIQuizResultView.swift`（AI 自测题生成 + 答题 + 批改三件套）。
    - `Flashcard/`：`FlashcardStudyView.swift` / `FlashcardCardView.swift` / `FlashcardSessionSummaryView.swift` / `FlashcardCalculatorView.swift` / `FlashcardHandwritingCanvasView.swift`（手写答题闪卡）。
    - `Todo/`：`TodoView.swift`（统一待办主页面，类型筛选 + 时间分组 + 列表/日历切换 + 过期 sheet；Phase 3 拆出 `TodoViewSheetsAndDestinations` ViewModifier 避免 body 链式过载）/ `TodoRootView.swift` / `TodoRowView.swift` / `NewTaskView.swift` / `TaskDetailView.swift` / `TaskDetailEditView.swift` / `RoutineEditorSheet.swift`（例程模板编辑 sheet）。
    - `Diary/`：学习日记 + 心情记录子系统。
      - `DiaryView.swift`：日记主页（顶部日历 + 当日编辑区 + 心情 + 精力标签）。
      - `DiaryEntryEditView.swift`：日记编辑页（Markdown 编辑 + 心情 emoji + 精力标签选择）。
      - `DiaryCalendarView.swift` + `DiaryCalendarModels.swift` + `DiaryCalendarDayCell.swift`：日历视图（按日显示心情 emoji + 精力色块）。
      - `MoodTrendChartView.swift`：心情趋势折线图（最近 30 天 moodScore / energyScore）。
    - `Plant/`：虚拟植物养成子系统。
      - `PlantHomeCard.swift`：主页植物卡片（Canvas 渲染当前 `PlantStage`）。
      - `PlantCanvasView.swift`：Canvas 绘制核心（茎 / 叶 / 花瓣 / 光点 / 灰色覆盖）。
      - `PlantAnimator.swift`：阶段切换动画（Spring + sortKey 插值）。
      - `PlantDetailView.swift`：植物详情页（当前阶段 + 历史 timeline + 解锁提示）。
      - `PlantDebugView.swift`：DEBUG 模式下手动切换 stage 调试页。
    - `Profile/`：`EditSubjectsView.swift` / `PreferencesView.swift` / `ProfileEditView.swift`。
    - `StudyTimer/`：`StudyTimerView.swift` + Phase 3 拆分：`StudyTimerActiveCard.swift` / `StudyTimerShared.swift` / `StudyTimerSettingsSheet.swift` / `StudyTimerHistoryList.swift` / `StudySessionDetailView.swift` / `StudySessionReviewSheet.swift` / `AnnotationListView.swift` / `DifficultyAnnotationEditor.swift` / `HeartRateChartView.swift`。
    - `TimeInvestment/`：`TimeInvestmentView.swift`（长期时间投入主页，入口在 `StudyTimerSettingsSheet` 工具栏）/ `TimeInvestmentEditors.swift`（项目 / 子任务 / 奖励编辑）/ `TimeInvestmentSummaryCard.swift`（汇总卡片）。
    - `Report/`：`ReportContentView.swift`（无 `@EnvironmentObject` 依赖，可经 `ImageRenderer` 输出）/ `ReportOptionsSheet.swift` / `ReportShareSheet.swift`。
    - `Settings/`：
      - `SettingsView.swift` 设置根视图，顶部 pinned Profile 行 + 9 段式 `SettingsCategory` 导航。
      - `SettingsCategory.swift` 9 段式导航枚举：`appearance` / `themeShop`（新） / `health` / `reports`（新） / `llm`（新） / `data` / `about` / `faq` / `contribution`（新）。
      - `ProfileSettingsView.swift` 头像卡片 + Edit Subjects + 跳转 `ProfileEditView`。
      - `AppearanceSettingsView.swift` 语言 / 主题 / 主色 / glassEffect / Trends 热力图开关 + 跳转 `HomeLayoutSettingsView` / `ChartTypeSettingsView` / `ContributionSettingsView`。
      - `ThemeShop/`：`ThemeShopView.swift`（主色 / 卡片皮肤 / 计时器动画三档商店，按成就解锁）+ `CardSkinRenderer.swift`（皮肤预览渲染器）。
      - `HealthSettingsView.swift` HRV 开关与详细介绍链接。
      - `WeeklyReportSettingsView.swift` 周报 / 月报自动生成配置。
      - `DataManagementSettingsView.swift` CSV 导出 / 还原示例数据 / Developer Admin / Export Log / 顶部 Phase Management 入口 + **Full Backup & Restore → `BackupRestoreView`**。
      - `AboutSettingsView.swift` 关于 + 版权 + Test Notifications。
      - `QASettingsView.swift` 高频问题。
      - `ContributionSettingsView.swift` 开源贡献指南。
      - `LLMSettingsView.swift`（也放在 `Views/LLM/`，但在 Settings 导航中作为子页）。
      - `DiarySettingsView.swift` 日记提醒时间 + 显示选项。
      - `AchievementsView.swift` 成就 / 连续打卡主页。
      - `DailyGoalsConfigView.swift` 每日目标配置 + 提醒时间。
      - `ChartTypeSettingsView.swift` 图表类型设置（6 档：line / bar / pie / scatter / heatmap / histogram）。
      - `ContributionSettingsView.swift` GitHub 风格活动贡献图配置。
      - `UserAgreementView.swift` 用户协议全文。
      - `PhaseManagementView.swift` 阶段管理主页（active list + archived disclosure + overview）。
      - `PhaseEditView.swift` 新建 / 编辑 phase（含 goals 编辑）。
    - `About/`：`AboutView.swift` / `CopyrightView.swift` / `HRVOnboardingView.swift`（3 页介绍 + 隐私 + 授权）。
    - `Admin/`：`DataAdminView.swift` 开发者工具页。
    - `OnBoarding/`：`OnboardingView.swift`（原生 iOS 26 风格 TabView 分页 + 渐变 + 玻璃质感）/ `OnboardingConfig.swift` / `OnboardingFlowState.swift` / `OnboardingProfileFormView.swift`（6 页基础信息表单）/ `VersionedWelcomeModifier.swift`（版本感知欢迎页）。
    - `Components/`：`GradeChartView` / `HRVStatusCard`（Phase 3 拆分后 + 3 sub-files：`BodyRadarValues` / `BodyRadarChart` / `FitnessRingView`；`HRVStatusSuggestionSection` 备用）/ `LearningHeatmapView`（90 天 GitHub 风格热力图）/ `MasteryCurveView` / `PhaseSelectorView`（全局 phase 切换器 pill，放 5 主页面 toolbar `.principal`）/ `SectionHeader` / `StreakHomeCard` / `StudyTimerCard` / `SubjectPickerView` / `TagChipsView` / `TagEditorView` / `DifficultyPicker` / `TrendChartView` / `Markdown/`（`MarkdownEditorView` / `MarkdownPreviewView` / `MarkdownTextEditor` / `MarkdownCommands` / `MarkdownFormatting` / `MarkdownFocusedValue`）。
    - `LLM/`（BYOK 大模型 UI）：
      - `LLMSettingsView.swift`：总开关 + Base URL + API Key（masked 显示 / 修改）+ Model + Temperature slider + System Prompt 追加 + Test Connection。
      - `LLMChatView.swift` + `LLMChatViewModel.swift`：通用 AI 助手聊天页（in-memory 历史、离开页面自动清空）；复用 `ChatBubble` + `ChatInputBar`。
      - `AIDiscussionSheet.swift`：错题解析 / 成绩预测 / 雷达建议等的「深入探讨」sheet，多轮对话（首条 assistant 消息用 `isInitialContext` 视觉弱化，不放入 conversation history，仅作 system prompt 引用）。
      - `MistakeAIAnalysisSheet.swift`：错题 AI 解析流式 sheet。
      - `HomeAskSheet.swift` + `HomeCards/HomeAskCard.swift` + `HomeAskViewModel.swift`：主页 AI 问答主卡片 + sheet（`HomeAskDataProvider` 根据输入关键词自动选择上下文）。
      - `AIWaitingView.swift`：通用 AI 等待动画（流式调用前展示）。
      - `ChatBubble.swift` + `ChatInputBar.swift`：从原 `LLMMessageBubbleView` 拆出的可复用 chat 组件。
      - `LLMDebugSheet.swift`：DEBUG 模式下面板，按 caller 分组显示 `LLMCallInfo` 环形 20 条历史 + JSON 详情。
    - `Debug/`：DEBUG 模式调试组件 — `DebugBannerView` / `DebugCacheView` / `DebugFPSOverlayView` / `DebugView` / `DebugModifiers`（`.debugModeContainer()` / `.debugLayoutBoundsAuto()`）/ `LogViewerView`（按 category / level 过滤 LogStore）/ `PerformancePanelView`（FPS / 内存 / 卡顿统计）。
    - `Helpers/`：`AvatarView`（异步加载）/ `CachedAsyncImage` / `ImagePicker` / `PhotoCaptureView` / `ScoreColor` / `ZoomableImageView` / `iPadLayout`。
  - `Extensions/`：`AppleIntelligenceGradient.swift` / `ColorExtensions.swift` / `DateExtensions.swift` / `ExportModeEnvironment.swift`（`@Environment(\.exportMode)` 用于 ImageRenderer 渲染时切换 glassEffect → .regularMaterial 兜底）/ `GlassCardModifier.swift`（`.glassCard(enabled:cornerRadius:)` 修饰符）。
  - `Intents/`：`StudyPulseShortcuts.swift`（6 个 AppIntent：AddGrade / RecordMistake / CheckUpcomingExams / CheckBodyStatus / CheckReadiness / CheckSubjectAverage）/ `AddGradeIntent.swift` / `RecordMistakeIntent.swift` / `CheckBodyStatusIntent.swift` / `CheckReadinessIntent.swift` / `CheckSubjectAverageIntent.swift` / `CheckUpcomingExamsIntent.swift` / `IntentAction.swift` / `IntentDataLoader.swift` / `SubjectEntity.swift`。
  - `NotificationsControl/`：`ExamPrepareNotifications.swift`（按 `countdownNotifyDays` 调度；`scheduleNotifications(for:date:days:)` 接受可选 `days` 参数；先 `getPendingNotificationRequests` 取消该 exam 旧通知，再按新 `days` 列表重排）。
- `StudyPulseWidget/`：WidgetKit 小组件源码（scheme：StudyPulseWidgetExtension）。
  - `ExamWidget.swift` / `ExamWidgetEntry.swift` / `ExamWidgetProvider.swift` / `ExamWidgetViews.swift`：考试小组件 S / M / L 三种尺寸。
  - `HRVWidget.swift` / `HRVWidgetData.swift`：HRV 准备度小组件。
  - `TrendWidget.swift` / `TrendWidgetData.swift`：科目成绩趋势折线图小组件。
  - `StudyTimerActivityAttributes.swift` + `StudyTimerLiveActivity.swift`：学习计时器 Live Activity（Lock Screen + Dynamic Island compact leading / compact trailing / minimal / expanded）。
  - `StudyPulseWidgetBundle.swift`：`@main` bundle。
  - `en.lproj` / `zh-Hans.lproj` / `zh-Hant.lproj` / `ja.lproj` / `ko.lproj`：小组件本地化字符串。
- `TestData/`：示例 CSV + `restore_sample_data.py` 还原脚本。
- `StudyPulseTests/`：单元测试目标。
  - `Infrastructure/`：`TestDataFixtures`（共享 fixture）+ `TestModelContainerFactory`（in-memory ModelContainer）+ `TestRepositoryContainerFactory`（注入 mock 的 RepositoryContainer）。
  - `TestDoubles/`：10 个 Mock Repository（`MockDiaryRepository` / `MockExamRepository` / `MockGradeRepository` / `MockMistakeRepository` / `MockPhaseRepository` / `MockProfileRepository` / `MockRoutineInstanceRepository` / `MockRoutineRepository` / `MockSubjectRepository` / `MockTaskRepository`）。
  - 单元测试覆盖：`DailyPlanEngineTests` / `DateFormattersTests` / `DifficultyTagTests` / `ExamFilterTests` / `MistakeFilterTests` / `PlantStageTransitionsTests` / `QuoteProviderTests` / `RecoveryLevelTests` / `RepositoryContainerTests` / `SubjectAggregatorTests` / `SuggestionEngineTests`。
- `en.lproj` / `zh-Hans.lproj` / `zh-Hant.lproj` / `ja.lproj` / `ko.lproj`：主应用各语言 Localizable.strings。
- `AGENTS.md` / `docs/architecture/CODE_WIKI.md` / `docs/architecture/CODE_WIKI_CN.md` / `README.md` / `docs/algorithms/AlgorithmIntroduction.md` / `docs/algorithms/ScorePredictionAlgorithm.md` / `docs/plans/STREAK_ACHIEVEMENT_PLAN.md` / `docs/product/SPEC.md` / `docs/product/DESIGN.md` / `docs/reference/USER_AGREEMENT.md` / `docs/reference/FAQ.json` / `docs/reference/CONTRIBUTING.json` / `LICENSE`：文档、协议与许可。
- `scripts/build.sh`：构建辅助脚本（默认使用 `DerivedDataBuild/` 子目录以隔离）。

---

## 3. 架构说明

应用遵循 MVVM + Repository 模式：

- **视图层**（`Views/`）只做 SwiftUI 渲染与用户交互。
- **ViewModel 层**（`ViewModels/`）每个主页面一个 `@MainActor ObservableObject`；状态为 `@Published private(set)`；通过 `static func makeDefault(container:)` 工厂由父 View 创建。
- **Repository 层**（`Repositories/`）16 个 `@MainActor` class 实现 16 个 protocol；每个域独立可测；`RepositoryContainer` 聚合 + 编排。
- **Service 层**（`Services/`）纯函数 enum/struct，不依赖 SwiftUI，提供可复用业务逻辑。
- **数据层**（`Models/` + `Models/SwiftData/`）`nonisolated value type` 的 struct（视图层使用）+ `@Model` 实体（持久化），双向映射。
- **跨域操作**（widget sync / Achievement 事件 / SRS 通知 / Exam 通知 / Routine spawn / Plant 状态）由 `RepositoryContainer` 的 facade 方法编排，**Repository 之间不互相调用**。

数据流：用户操作触发 ViewModel 业务方法 → ViewModel 调用 `container.xxxRepo.add*` / `container.addXxx(...)` facade → Repository 写入 SwiftData 实体 + 更新自身 `@Published` 数组 → SwiftUI 重新渲染 + 跨域副作用（widget sync / 通知调度 / Achievement 事件 / Plant recordActivity / Routine spawn）。

辅助基础设施：
- 日志：`Log.swift` 提供 `Log.app` / `Log.widget` / `Log.notification` / `Log.ui` / `Log.data` / `Log.study` / `Log.health` / `Log.llm` 等 subsystem + 全局 `LogStore` 内存缓冲（5000 条上限，Swift `actor` 隔离保障并发安全）。所有 Manager / View 生命周期事件调用 `Log.record(_:category:message:)` 写入 `os.Logger` 与 `LogStore`。`LogDocument` 把 `LogStore` 序列化为文本供 `.fileExporter` 导出。`LogViewerView` 在 DEBUG 模式按 category / level 过滤查看。**注意：调用 `Log.xxx.info(...)` 的文件必须 `import os`**，否则编译报 "instance method 'appendInterpolation...' is not available due to missing import of defining module 'os'"。
- 卡顿监控：`LagMonitor.shared` 通过 `CADisplayLink` 监测主线程帧间隔，连续丢帧超过阈值时记录到 `LogStore`。`FPSMonitor` + `PerformancePanelView` 在 DEBUG 模式叠加 FPS / 内存 / 卡顿面板。
- 启动顺序：`StudyPulseApp.init()` 注册通知代理、启动 `LagMonitor.shared`；`.task` 中先 `await container.asyncInit()`（JSON 迁移 + 16 repo loadAll + 图片迁移 + 通知/widget 调度 + `RoutineSpawner.runOnce()`），`isReady == true` 后再 `await hrvManager.bootstrap()` 与 `AchievementManager.shared.bootstrap(container:)` + `PlantManager.shared.bootstrap(container:)`，避免启动期 I/O 竞争；随后 `timerManager.attach(sessionRepository:timeInvestmentRepository:)` 把学习会话与时间投入 repo 注入 `StudyTimerManager`；`scenePhase == .active` 且 `container.isReady == true` 时统一异步加载学习会话 + sync widget + SRS / Exam Review / Diary Reminder / HabitInsight 通知 + Reminders 状态 + `RoutineSpawner.runOnce()`。
- AppIntents 桥接：`IntentActionStore.shared.pendingIntentAction` 镜像到 `RepositoryContainer.pendingIntentAction`；`ContentView` 观察 `IntentActionStore`，处理用户通过 Siri 触发的 6 类 action 后清空。

视图层目录：
- 根视图 `ContentView`：iPhone `TabView` 5 标签（Home / Trends / Mistakes / Exams / Settings）；iPad `NavigationSplitView` 侧栏 + 详情。
- 每个主页面 `XxxView` 在 `init` 中通过 `XxxViewModel.makeDefault(container:)` 创建 ViewModel，并以 `let viewModel: XxxViewModel` 持有；子 View 接收 ViewModel 用 `@ObservedObject`。
- 模态面板：`AddGradeView` / `NewExamSetView` / `NewMistakeSetView` / `MistakeDetailEditView` / `ExamDetailEditView` / `HRVOnboardingView` / `HomeLayoutSettingsView` / `DataAdminView` / `StudyTimerView` / `ReportOptionsSheet` / `ReportShareSheet` / `FlashcardStudyView` / `FlashcardCalculatorView` / `DailyGoalsConfigView` / `UserAgreementView` / `AchievementsView` / `ChartTypeSettingsView` / `ContributionSettingsView` / `PhaseEditView`。
- 全局 `PhaseSelectorView` 胶囊 pill 放在 5 主页面 toolbar `.principal` 位置（Home / Trends / Mistake / Todo / Exam）。
- 主页 `HomeView` 动态卡片由 `HomeLayoutPreference` 的启用顺序渲染（含 `streakProgress` 连续打卡卡 + `learningHeatmap` 热力图）；iPad 两栏 `LazyVGrid`，iPhone 单列 VStack；`HomeCardType.isFullWidth` 标记全宽卡片（`HomeView.iPadDynamicCards` 按"块"渲染：全宽卡片独占整行，普通卡片每 2 个成行）。
- 全局自定义背景图：`BackgroundImageView` 全屏 + 模糊 + 暗化遮罩铺在 `ContentView` 底部；5 个主页面根用 `Color(.systemGroupedBackground).opacity(0.4)`；`List` / `Form` 加 `.scrollContentBackground(.hidden)` 才能让底图穿透；**iOS 26 NavigationStack 有默认不透明 `containerBackground`**，必须在 NavigationStack 内的根内容上加 `.containerBackground(.clear, for: .navigation)`；`TabView` 也需加 `.toolbarBackground(.hidden, for: .tabBar)`。
- Liquid Glass 效果：全局 `AppPreferences.glassEffectEnabled`；卡片 opt-in via `.glassCard(enabled:cornerRadius:)` 修饰符；启用后替换 `Color(.secondarySystemGroupedBackground)` 背景为 iOS 26 `glassEffect`（老系统回退 `.regularMaterial`）；**`glassEffect` 直接套 `Capsule()` 是不透明**，必须用 `Color.clear` + `glassEffect(in: Capsule())` 才有真实透明感。
- 自定义主色：`ThemeAccent` 11 档预设（system / blue / cyan / teal / green / mint / orange / red / pink / purple / indigo）持久化为 `accentPaletteId: String?`；`AppEnvironmentManager.effectiveAccentColor` 是单点消费方；驱动 `ContentView.tint()` / `TrendChartView.tintColor`（line + bar）/ `FlashcardStudyView` 进度条；**状态色（TodoView/ExamView 时间-剩余 / 掌握度 ProgressView）保持按状态着色**，不跟随主色。

业务 / 服务层目录：
- `RepositoryContainer`（`@Observable @MainActor`）聚合 16 个 Repository + ModelContainer 持有 + `isReady` + 3 个跨域编排子模块（`bulkOps` / `todoAggregator` / `phaseRefresher`，Phase 3 拆出独立文件）+ 跨域 facade（`addGrade` / `addGrades` / `addMistake` / `addMistakes` / `addExams` / `addTask` / `addTasks` / `addDiary` / `addRoutine` / `deleteGrade` / `deleteExam` / `deleteTask` / `activatePhase` / `bulkClearData` / `todoEntries`）；**注意：双实例陷阱——`StudyPulseApp` 写 `@State private var container = RepositoryContainer()`，不要写 `DataManager.shared` 之类的双实例**。ViewModel 通过 `DataManager.shared` 调用会拿到空数据（独立实例）；**自检：所有 ViewModel 都用 `container.xxxRepo.xxx` 路径访问，App 入口持有同一个 `RepositoryContainer` 单例**。
- `AppEnvironmentManager`（`@MainActor ObservableObject` 单例）持有 `AppPreferences`（语言 / 主题 / 图表类型 / 主色 / glassEffect / Trends 热力图 / `activePhaseId`），提供 `effectiveColorScheme` / `effectiveAccentColor` / `setLanguage` / `setColorScheme` / `setAccent` / `setGlassEffect` / `setLearningHeatmapOnTrends` / `setActivePhase`。
- `HealthKitManager`（`@MainActor ObservableObject` 单例）持有 `HRVReadiness`（Z-score / 分类 / 建议）、`dailyHRVHistory` / `lastSampleCount` / `hrvDetailLevel` / `BodyStatus` / `PersonalBaselines` 30 天个人基线 / `bodyStatusAuthorized` / `isReady`；`enable()` / `disable()` / `refreshReadiness()` / `refreshBodyStatus()` / `bootstrap()`。`StudyReadinessAlgorithm` 在 HRV 之外把多维身体信号（深睡 + REM、锻炼、心率、呼吸）归一化打分，合成 5 档强度 × 5 类重点建议。详见 `docs/algorithms/AlgorithmIntroduction.md`。
- `AchievementManager`（`@MainActor ObservableObject` 单例）持有 `AchievementsSnapshot`（`config` / `todayLog` / `streak` / `cumulativeProgress` / `unlockedAchievements` / `todayProgress`），对外暴露 `recordGradeRecorded` / `recordMistakeReviewed` / `recordFocusMinutes` 三个事件入口；`updateConfig` 改每日目标；`handleDayRolloverIfNeeded` 在 `scenePhase == .active` 时跨日滚动。`AchievementStore` 负责 `AchievementsSnapshot` 持久化 + 首次启动从 `grades.json` / `study_sessions.json` 反推 30 天历史。详见 `docs/plans/STREAK_ACHIEVEMENT_PLAN.md`。
- `StudyTimerManager`（`@MainActor ObservableObject`）持有当前会话（强度 / 剩余时间 / 状态 idle / running / paused / completed），负责创建 / 更新 / 结束 `StudyTimerActivityAttributes` Live Activity；**完成会话时经 `sessionRepository.upsert(_:)` 持久化为 `StudySession`（绑定 `selectedInvestmentTarget`），老 `~/Documents/study_sessions.json` 由 `StudySessionRepository.refreshFromLegacyJSON()` 一次性合并导入**。`StudyTimerPalette` 提供主应用与 Live Activity 共享的色板。
- `CalendarManager`：EventKit 单例。考试通过 `addExamToCalendar` 写入 `EKEvent`（可选 startTime/endTime，nil 时回退为全天事件）；作业 / 阅读材料通过 `addTaskToReminders` 写入 `EKReminder`（dueDateComponents + EKAlarm）。
- `OCRManager`：Vision 文本识别（`recognitionLanguages = ["zh-Hans", "en"]`）。
- `ImageCache`：`nonisolated` class，单例 `NSCache` 50 项、300px 缩略图。
- `EducationConfig`：`nonisolated` enum。
- `SubjectInfo`：科目显示辅助。
- `WidgetDataSyncManager` / `HRVWidgetSyncManager` / `TrendWidgetSyncManager`：App Group 同步。
- `Log` / `LogStore` / `LogDocument`：统一日志层。
- `LagMonitor`：主线程卡顿检测器。
- `HealthHistoryStore`：`DailyHealthSnapshot` 30 天滚动持久化（NSLock 线程安全）。
- `ReportRenderer`：`SwiftUI ImageRenderer` 把 `ReportContentView` 渲染为 PNG / JPEG。
- `MistakePDFRenderer`：Core Text + `NSAttributedString` 渲染多页 A4 PDF。
- `ModelContainerFactory`：SwiftData `ModelContainer` 单例工厂 + 启动时从 `~/Documents/*.json` 自动迁移（UserDefaults flag 避免重复执行）。
- `SRSReviewNotifications`（identifier 前缀 `SRS_`）+ `DailyGoalReminder`（identifier 前缀 `DailyGoal_`）+ `ExamReviewNotifications`（identifier 前缀 `Exam_<name>_`，按 `countdownNotifyDays` 调度）+ `ExamPrepareNotifications`（legacy，单一 exam 按天数）；共享「先清空前缀再批量重建」调度模式。

数据层目录：
- 模型为 `nonisolated value type`，`Codable` + `Sendable` + `Hashable`，可无 ceremony 跨 actor 传递。`Subject` / `Grade` / `MistakeNote` / `Exam` / `comprehensiveExam` / `ExamTimeSlot` / `UserProfile` / `AppPreferences` / `HomeLayoutPreference` / `HealthHistory`（`DailyHealthSnapshot`）/ `StudySession` / `ReviewState` / `DailyGoalConfig` / `DailyActivityLog` / `StreakState` / `AchievementDefinition` / `AchievementProgress` / `AchievementsSnapshot` / `StudyReport` / `MistakePDFSnapshot` / `TaskItem` / `TaskType` / `TodoEntry` / `TodoEntryKind` / `StudyPhase` / `PhaseGoal` / `ExamChecklistItem` / `ExamReview`。
- **新增非 optional 字段到 Codable struct 必须手写 `init(from:)` + `CodingKeys`，所有新字段用 `decodeIfPresent` 给默认值；否则老 JSON 解码会 fatalError 闪退**。
- SwiftData 实体层：`Models/SwiftData/StudyPulseModels.swift` 定义 `@Model final class` 实体；`@Attribute(.unique) id`；`@Attribute(.externalStorage) Data` 把图片 / Markdown 等大字段外存；嵌套类型（`ExamTimeSlot` / `ReviewState` / `[Data]` / `PhaseGoal`）拍平为基本字段。视图层继续使用 struct（Repository 暴露 `[struct]`），不需要改 view。
- 持久化：业务模型由 SwiftData 实体层承载；图片以 `grade_UUID.jpg` / `avatar_UUID.jpg` 写入 `~/Documents/images/`；健康历史 `~/Documents/health_history.json`；学习会话 `StudySessionRecord`（SwiftData，`payload` JSON），老 `~/Documents/study_sessions.json` 在 `StudySessionRepository.refreshFromLegacyJSON()` 中合并导入；成就 `~/Documents/achievements.json`。UserDefaults 保存 `AppPreferences` / `HomeLayoutPreference` / HRV 相关偏好 / `lastSeenAppVersion` / `DailyGoalConfig` / SwiftData 迁移完成 flag / 上次投资目标（`studyPulse.lastInvestmentTarget*`）。App Group 容器保存 `widgetUpcomingExams` / `HRVWidgetData` / `TrendWidgetData`。

扩展与通知目录：
- `ColorExtensions` / `DateExtensions` / `StringsLocalized` / `GlassCardModifier` 提供跨层使用的辅助。
- `ExamPrepareNotifications` 使用 `UNUserNotificationCenter` 调度本地通知；先 `getPendingNotificationRequests` 取消该 exam 旧通知（按 `identifier.contains("Exam_<name>_")` 过滤），再按新 `days` 列表重排；空数组 = 关闭通知；过期日期自动跳过。

---

## 4. 模块依赖关系

模块依赖顺序为：视图层 → ViewModel 层 → RepositoryContainer → 16 个 Repository → SwiftData 实体层；Service 层被 ViewModel / View 任意调用；模型本身不依赖其它层。

ViewModel 到 RepositoryContainer 的调用示例：
- `HomeViewModel.recompute()` 调 `container.gradeRepo.grades` / `container.mistakeRepo.mistakeSets` / `container.examRepo.filteredExamSets` + `SubjectAggregator.aggregate` + `ExamFilter.examsWithinDays` / `ExamFilter.unregisteredExams`。
- `HomeViewModel.generateSuggestions(limit:)` 调 `StudyReadinessAlgorithm.recommend(...)` + `SuggestionEngine.generate(...)`。
- `TodoViewModel` 调 `container.todoEntries(includeCompleted:phaseId:)`。
- `DailyPlanCard` 调 `DailyPlanEngine.generate(...)`（输入 exam / mistake SRS / routine / task）。
- `HomeAskViewModel` 调 `HomeAskDataProvider.resolve(...)` + `HomeAskLLM.buildPrompt(...)` + `LLMClient.stream(...)`。
- `AutoMindMapViewModel` 调 `AutoMindMapLLM.buildPrompt(...)` + `LLMClient.complete(...)` + JSON 解析为节点树。
- `RepositoryContainer.addGrade` 调 `gradeRepo.add(grade)` + `AchievementManager.shared.recordGradeRecorded()` + `PlantManager.shared.recordActivity()` + `TrendWidgetSyncManager.syncTrend(...)`（跨域副作用）。
- `RepositoryContainer.addMistake` 调 `mistakeRepo.add(mistake)` + `SRSReviewNotifications.shared.rescheduleAll(...)` + `PlantManager.shared.recordActivity()`。
- `RepositoryContainer.addExams` 调 `examRepo.add(...)` + `ExamReviewNotifications.shared.rescheduleAll(...)` + `WidgetDataSyncManager.syncUpcomingExams(...)`。
- `RepositoryContainer.addDiary` 调 `diaryRepo.add(...)` + `DiaryReminderNotifications.shared.reschedule(...)`。
- `RepositoryContainer.addRoutine` 调 `routineRepo.add(...)` + `RoutineSpawner.shared.runOnce()`。
- `RepositoryContainer.activatePhase` 调 `phaseRepo.activate(phase)` + `recomputeAllFiltered()`（6 个 `filtered*` 缓存重算：grade / mistake / exam / task / routine / diary）。

辅助组件不反向调用视图层。
小组件（`StudyPulseWidgetExtension`）通过 App Group 容器读取主应用写入的 `ExamWidgetData` / `HRVWidgetData` / `TrendWidgetData` 数据，自身不依赖 `RepositoryContainer`；Live Activity（`StudyTimerLiveActivity` + `RoutineLiveActivity`）通过 `ActivityAttributes` 与主应用共享会话状态。

---

## 5. 导航流程

应用入口在 `StudyPulseApp`：
- 设置 `NotificationCoordinator` 作为 `UNUserNotificationCenter` delegate，点击通知时清除角标。
- 请求通知授权。
- 启动 `LagMonitor.shared` 监测主线程帧间隔。
- 调用 `AppEnvironmentManager.shared.applyLanguageOnLaunch()` 恢复语言设置。
- 使用 `.task` 先 `await container.asyncInit()`，`isReady = true` 后再 `await hrvManager.bootstrap()` 与 `AchievementManager.shared.bootstrap(container:)`，避免启动期 I/O 竞争。
- `ModelContainerFactory` 在 `container.asyncInit()` 内同步执行一次 SwiftData 迁移（UserDefaults flag 避免重复）。
- 监听 `scenePhase == .active`：当 `container.isReady == true` 时同步 `ExamWidget` / `TrendWidget` / `HRVWidget` + `SRSReviewNotifications` + `ExamReviewNotifications` + `Reminders` 完成态 + `hrvManager.refreshBodyStatus()` + `AchievementManager.handleDayRolloverIfNeeded()` + `DailyGoalReminder.shared.reschedule(...)`。
- 注入 `IntentActionStore` 通过 `EnvironmentObject` 让 `ContentView` 处理 Siri 跨进程跳转。

`ContentView` 根据水平 size class 判定设备：
- iPhone：`TabView` 五个标签（Home / Trends / Mistakes / Exams / Settings）。
- iPad：`NavigationSplitView`，列表项目与 iPhone 五标签一致。

`HomeView`：
- 快速动作按钮打开 `AddGradeView` / `NewExamSetView` / `NewMistakeSetView` / `StudyTimerView` / `ReportOptionsSheet`。
- HRV 状态卡首次出现时启动 `HRVOnboardingView`。
- 未注册考试提醒卡引导到 `AddGradeView`。
- 即将到来的考试引导到 `ExamDetailView`。
- `StreakHomeCard` 跳转到 `AchievementsView`。
- 主页卡片顺序与开关在 `HomeLayoutSettingsView` 配置。
- 顶部 `LearningHeatmapView` 点击格子弹当日详情 sheet。
- 顶部 `PhaseSelectorView` 切换 phase 触发全量 recompute。

`TrendsView`：
- 点击科目进入 per-subject 详情。
- 图表类型在 `ChartTypeSettingsView` 切换（6 档：line / bar / pie / scatter / heatmap / histogram）。
- 顶部 `LearningHeatmapView` 单独受 `AppPreferences.learningHeatmapOnTrends` 控制（在 `TrendsView` toolbar Menu 底部，以 `Divider` 与模式选择分隔）。

`MistakeView`：
- 新建错题进入 `MistakeDetailEditView`。
- 已有错题进入 `MistakeDetailEditView`（编辑模式）。
- 错题入队 SRS 后可在 `FlashcardStudyView` 复习（SM-2 算法调度的会话）；`FlashcardCalculatorView` 调试 SM-2 参数。

`TodoView`（「待办」页，替代原 ExamView）：
- 顶部分类型筛选 chip（All / Exams / Homework / Reading）与「Show Completed」开关。
- 列表模式按时间分组（Within 1 Week / Within 1 Month / Later），左上角 Past Items 按钮打开过期任务 sheet。
- 日历模式仅对考试可见（复用 `ExamCalendarView`）。
- 右上角 + 按钮带菜单：新建考试 / 作业 / 阅读，分别进入 `NewExamSetView` / `NewTaskView`。
- 点击行进入详情：考试 → `ExamDetailView`；作业 / 阅读 → `TaskDetailView`。
- 详情菜单：编辑 / 切换完成态 / 删除；编辑进入 `TaskDetailEditView`，自动处理 Reminder 同步。
- 顶部 `PhaseSelectorView` 切换 phase 过滤。

`ExamView`（保留原视图作为考试日历入口）：
- 列表 / 日历切换（`ExamCalendarView`）。
- 顶部 `PhaseSelectorView` 切换 phase 过滤。
- 点击考试进入 `ExamDetailView`（含考场信息 / 考前清单 / 复盘 / 倒计时通知 / 分享给家人）。

`StudyTimerView`（学习计时器主页面）：
- 由 `StudyTimerManager` 驱动；用户选择 5 档强度之一开始计时（可基于 `StudyReadinessAlgorithm` 的建议预选）。
- 计时开始时同步启动 / 更新 / 结束 `StudyTimerLiveActivity`（Lock Screen + Dynamic Island）。
- 暂停 / 恢复 / 结束操作会同步 Live Activity；完成时把会话落盘为 `StudySession`，并触发 `AchievementManager.recordFocusMinutes()`。

`ReportContentView`（学习报告）：
- 从 `ReportOptionsSheet` 选择报告范围（周期 / 包含模块）后，`ReportRenderer` 用 `ImageRenderer` 渲染为 PNG / JPEG，由 `ReportShareSheet` 分享。

`SettingsView`：
新版采用 9 段式 `NavigationLink` 导航 + 多个聚焦子页，`SettingsCategory` 枚举标识每一段（`appearance` / `themeShop` / `health` / `reports` / `llm` / `data` / `about` / `faq` / `contribution`）；顶部还 pinned 一个 `ProfileSettingsView` 入口：
- Profile（顶部 pinned）：`ProfileSettingsView`（头像卡片 + Edit Subjects + 跳转 `ProfileEditView`）。
1. Appearance & Layout：`AppearanceSettingsView`（语言 / 主题 / 主色 / glassEffect / Trends 热力图开关）+ `HomeLayoutSettingsView`（主页卡片顺序与开关）+ `ChartTypeSettingsView` + `ContributionSettingsView`。
2. Theme Shop：`ThemeShopView`（主色 / 卡片皮肤 / 计时器动画三档商店，按 `AchievementDefinition.id` 解锁）+ `CardSkinRenderer` 预览。
3. Health & Readiness：`HealthSettingsView`（HRV 开关与详细介绍链接）。
4. Learning Reports：`WeeklyReportSettingsView`（周报 / 月报自动生成配置 + AI 总结开关）。
5. LLM：`LLMSettingsView`（BYOK 大模型配置：总开关 + Base URL + API Key + Model + Temperature + System Prompt + Test Connection）。
6. Data Management：`DataManagementSettingsView`（顶部 `Phase Management` 入口 + CSV 导出 / 还原示例数据 / Developer Admin / Export Log）；`AchievementsView`（成就 / 连续打卡主页）+ `DailyGoalsConfigView`（每日目标配置 + 提醒时间）也从这里跳转。
7. About：`AboutSettingsView`（关于 + 版权 + Test Notifications + `UserAgreementView` 全文）。
8. FAQ：`QASettingsView`（高频问题，源数据 `docs/reference/FAQ.json`）。
9. Contribution：`ContributionSettingsView`（开源贡献指南，源数据 `docs/reference/CONTRIBUTING.json`）。

`PhaseManagementView`：
- 顶部 active list（可点击切换 + 跳转 `PhaseEditView`）。
- 中部 archived disclosure。
- 底部 overview（每 phase 关联的 grade / mistake / exam / task 数量）。

---

## 6. 数据层说明

`RepositoryContainer` 为 `@Observable @MainActor` 容器，**作为视图层 / ViewModel 的入口**（替代老的 `DataManager`）。
`@Published` 状态由 16 个 Repository 各自维护：每个 Repository 是 `@MainActor final class` 实现对应 protocol，持有自己的 `@Published var grades: [Grade]` / `@Published var mistakeSets: [MistakeNote]` / 等数组。
每个 Repository 内部维护两个视图：`xxx`（全部数据）+ `filteredXxx`（按 active phase 过滤的派生缓存），底层的 SwiftData 读取通过 `PersistenceExecutor` 配合 `#Predicate<*Record>` 谓词优化直接进行数据库级 fetch，并在 `recomputeFiltered()` 时高效重算（6 个 filtered 缓存：grade / mistake / exam / task / routine / diary）。
`isReady` 标志在 `asyncInit()` 完成后置 true，`scenePhase` 监听者据此避免写入空 widget 数据。

`asyncInit()` 流程：
1. 调 `ModelContainerFactory.makeContainer()` 拿进程内单例 `ModelContainer`（`Schema(versionedSchema: StudyPulseSchemaV4.self)` + `StudyPulseMigrationPlan`）。
2. 调 `ModelContainerFactory.migrateFromJSONIfNeeded(context:)` 一次性把老 `~/Documents/*.json` 导入 SwiftData 实体。
3. 各 Repository 串行 `loadAll(context:)`，每个 repo 内部用 `Task.detached` 做 `toSnapshot` 后回主 Actor 赋值。
4. `GradeRepository.migrateInlineImagesIfNeeded()` 把 `GradeRecord.image` 内嵌 Data 写入 `~/Documents/images/` 并清空字段。
5. `SubjectRepository.initializeDefaultSubjects()` 空库时注入默认科目。
6. `observeActivePhaseChanges()` 启动 0.5s polling Task 监测 `activePhaseId` 变化。
7. `RoutineSpawner.shared.runOnce()` 物化今日例程 + 清理 30 天前的 stale instance。
8. `isReady = true`。
9. 调度通知 + sync widget：`SRSReviewNotifications` / `ExamReviewNotifications` / `DiaryReminderNotifications` / `HabitInsightNotifications` / `WidgetDataSyncManager` / `TrendWidgetSyncManager` / `HRVWidgetSyncManager`。

`ModelContainerFactory.migrateFromJSONIfNeeded(context:)` 流程：
- 检查 UserDefaults `swiftDataMigrated` flag，为 true 直接返回。
- 读 `~/Documents/*.json`（grades / mistakes / exams / comprehensiveExams / tasks / subjects / profile / phases）。
- 全部 `insert` 到 ModelContext。
- 写 `try context.save()`。
- 写 UserDefaults flag。

SwiftData 实体层：
- `Models/SwiftData/StudyPulseModels.swift` 定义 `@Model final class` 实体（核心 12 实体 + `StudySessionRecord` / `TimeInvestmentSubjectRecord` / `SubTaskRecord` / `GoalRewardRecord` / Coach 系列 / `ExamGoalRecord` / `ExamPlanRecord` 等）。
- 每个实体提供 `toSnapshot()` / `init(from:)` 双向映射。
- `@Attribute(.unique) id` 保证实体主键；`@Attribute(.externalStorage) Data` 把图片 / Markdown 等大字段外存。
- `GradeRecord` / `ExamRecord` / `MistakeNoteRecord` / `TaskItemRecord` / `RoutineRecord` 都带 `phaseId: UUID?` + `#Index<...>` 触发 B-Tree 索引；`StudyPhaseRecord` 含 `name` / `startDate` / `endDate` / `isArchived` / `archivedAt` / `goalsData: Data?`（JSON-encoded `[PhaseGoal]`）。
- `StudySessionRecord`：`#Index([\.startDate])` + `@Attribute(.unique) id` + `startDate` + `payload: Data`（整个 `StudySession` 的 JSON，`toSnapshot()` 解码回 value type）。
- `PlantStateRecord`：单例实体（仅 1 行），含 `currentStageRaw` + `historyData: Data?`（JSON-encoded `[PlantStageTransition]`）+ `lastActivityAt`。
- `RoutineRecord`：含 `id` / `title` / `typeRaw` / `subject?` / `weekdays: [Int]` / `startTime` / `endTime` / `enabled` / `phaseId?`。
- `RoutineInstanceRecord`：含 `id` / `routineId` / `title` / `dateKey`（用于幂等去重）/ `date` / `startTime` / `endTime` / `isCompleted` / `completedAt?` / `spawnedMistakeCount`。
- `DiaryEntryRecord`：含 `id` / `date` / `moodScore` / `energyScore` / `energyTag` / `content`（`@Attribute(.externalStorage)`）/ `phaseId?` / `createdAt` / `updatedAt`。
- `TimeInvestmentSubjectRecord` / `SubTaskRecord` / `GoalRewardRecord`：分别带 `#Index`（sortOrder / subjectID / targetID 等）+ `@Attribute(.unique) id`；`GoalRewardRecord.apply(_:)` 保留首次 `unlockedAt`。

图像文件命名：
- 成绩快照：`images/grade_UUID.jpg`。
- 头像：`images/avatar_UUID.jpg`。
- 自定义背景图：`Application Support/Backgrounds/bg_<uuid>.jpg`（中心裁剪为 9:19.5）。
- 语音备忘录：`audio/<uuid>.m4a`（详见 7.6 Audio 子系统）。

持久化数据流：
- 应用启动：`StudyPulseApp` 在 `.task` 中调 `container.asyncInit()`。asyncInit 内部在后台 Task 中读 SwiftData；回到主 Actor 后把结果分配给每个 Repository 的 `@Published`。完成后 `isReady = true`，触发后续 bootstrap（`HealthKitManager` / `AchievementManager` / `PlantManager`）+ `StudyTimerManager.attach(...)`。
- 用户编辑：视图调用 `container.addGrade(...)` / `container.deleteXxx(...)` facade → Repository 调用 SwiftData `context.insert` / `context.delete` + `try context.save()` + 同步更新 `@Published` 触发 SwiftUI 重渲染。跨域副作用（widget sync / Achievement 事件 / SRS 通知 / Plant recordActivity / Routine spawn）由 facade 方法统一处理。

核心模型说明（已用 `nonisolated value type` + 全部 Codable + Sendable + Hashable）：
- `Subject`：id、name、displayName、enabled、fullScore。
- `Grade`：subject、score、rawScore?、ranking?、importance（1..5）、image?（legacy）、imageFileName?、date、examName、fullScore?、**phaseId?**。
- `MistakeNote`：title、subject、originalQuestion、source、date、errorReason、wrongSolution、correctSolution，每区块的文件名数组，reviewState（`ReviewState?`，nil 表示未入队 SRS）、`audioFileName?`、`masteryHistory: [MasteryHistoryEntry]`、`handwritingAnswers: [HandwritingAnswerEntry]`、`tags: [String]`、**phaseId?**。
- `MasteryHistoryEntry`：id、date、mastery（0~1）；用于 `MasteryCurveView` 绘制掌握度曲线。
- `HandwritingAnswerEntry`：id、date、imageFileName、note?；用于手写答题画布持久化。
- `Exam`：name、examDate、examEndDate?、importance、subject、examName、masteryDegree、timeSlot（`ExamTimeSlot?`）、`checklist: [ExamChecklistItem]`（默认 `[]`）、`locationSchool/locationClassroom/locationSeat: String`（默认 `""`）、`countdownNotifyDays: [Int]?`（nil=默认 [1,3,5,10,30] / `[]`=关闭）、`examReview: ExamReview?`、**phaseId?**。
- `comprehensiveExam`：name、examDate、examEndDate?、importance、subject（[String]）、examName、masteryDegree、timeSlot?、**phaseId?**。
- `ExamTimeSlot`：startTime、endTime。
- `TaskItem`：title、kind（homework / reading）、dueDate、reminderDate、notes、completed、reminderIdentifier、subject?、**phaseId?**。
- `TodoEntry` / `TodoEntryKind` / `TaskType`：TodoView 用以把 Exam / comprehensiveExam / TaskItem / RoutineInstance 统一为一条「待办」。
- `ExamChecklistItem`：id、title、isChecked、sortOrder。
- `ExamReview`：考试复盘（评分 / 错题反思 / 改进点等）。
- `UserProfile`：username、realName、age、gender、school / grade / class / studentId、enrollmentYear / examYear、educationStage、regionCode、theme、avatarFileName、selectedSubjects、targetSchool、targetScore。
- `AppPreferences`：appLanguage（可选）、colorScheme、chartType、accentPaletteId、glassEffectEnabled、learningHeatmapOnTrends、activePhaseId、LLM 配置（`llmEnabled` / `llmBaseURL` / `llmModel` / `llmTemperature` / `llmSystemPromptAppendix` / `llmOverrideSystemPrompt`）+ `lastRadarAIRequestTime` / `lastStudySuggestionsAIRequestTime` 冷却时间戳。
- `HomeLayoutPreference`：有序 items（`HomeCardItem` 数组，每块带 enabled flag），持久化到 UserDefaults；17 个 `HomeCardType`；`isFullWidth: Bool` 标记全宽卡片（仅 `learningHeatmap`）。
- `HealthHistory`（`DailyHealthSnapshot`）：date、hrv、restingHeartRate、respiratoryRate、sleepHours、deepSleepHours、remSleepHours、exerciseMinutes。
- `StudySession`：id、startDate、durationSeconds、intensity、completed、heartRateSamples?、difficultyAnnotations?、**investmentTarget?**（`InvestmentTarget`）、**source**（`StudySessionSource`：timer / manual）、timeZoneIdentifier?；自定义 `init(from:)` 用 `decodeIfPresent` 兜底，兼容老 JSON。
- `InvestmentTarget`（在 `Models/TimeInvestment.swift`）：subject / subTask 两类枚举；`GoalReward`：id、title、symbolName、target、thresholdSeconds、createdAt、unlockedAt?。
- `ReviewState`（嵌套在 `MistakeNote` 中）：repetitions、easeFactor、intervalDays、nextReviewDate、lastReviewDate、lapses。
- `DailyGoalConfig`：mistakeReviewTarget、gradeRecordTarget、focusMinutesTarget、reminderEnabled、reminderHour、reminderMinute。
- `DailyActivityLog`：date、mistakeReviews、gradesRecorded、focusMinutes。`totalActivityPoints` = `mistakeReviews + gradesRecorded*5 + focusMinutes`，是热力图强度的数据源。
- `StreakState`：current、longest、lastActiveDate、totalActiveDays。
- `AchievementDefinition` / `AchievementProgress` / `AchievementsSnapshot`：成就目录 + 进度 + 持久化根。
- `StudyReport`：学习报告不可变 value type。
- `MistakePDFSnapshot`：错题 PDF 导出快照。
- `StudyPhase`：id、name、startDate、endDate、isArchived、archivedAt?、goals（[PhaseGoal]）、createdAt。
- `PhaseGoal`：id、subject、targetScore、notes。
- `Routine`：id、title、type（mistakeReview / flashcard / general）、subject?、weekdays、startTime、endTime、enabled、createdAt、**phaseId?**。
- `RoutineInstance`：id、routineId、title、type、subject?、startTime、endTime、date、dateKey（幂等 key）、isCompleted、completedAt?、spawnedMistakeCount。
- `DiaryEntry`：id、date、moodScore（1~5）、energyScore（1~5）、energyTag（专注/平静/兴奋/疲惫/焦虑/烦躁/迷茫）、content（Markdown）、phaseId?、createdAt、updatedAt。自定义 `init(from:)` 用 `decodeIfPresent` 兼容老数据。
- `QuizQuestion`：id、type（multiple_choice / fill_in_the_blank）、question（Markdown + LaTeX）、options?、correctAnswer、solution。
- `HabitInsight`：id、patternKind（peakEfficiency / procrastination / streakDay / weakDay）、weekday、hourSlot、title、description、icon、color、priority、confidence。由 `HabitInsightEngine.computeInsights(sessions:now:)` 纯函数生成。
- `AccentPalette` / `CardSkin` / `TimerAnimation`：三类皮肤条目（id 稳定，绑定 `unlockAchievementId`）；由 `ThemeShopCatalog` 静态目录管理。
- `PlantStage`（enum，8 阶段）+ `PlantStageTransition`（切换历史）。

---

## 7. HRV / HealthKit 子系统

`HealthKitManager` 为 `@MainActor ObservableObject` 单例，统一管理两类 HealthKit 数据：HRV（SDNN）准备度（与个人 14 天基线的 Z-score 对比）和 BodyStatus（多维身体信号快照）。

授权与生命周期：
- `readTypes` 一次请求授权：`heartRateVariabilitySDNN` / `heartRate` / `restingHeartRate` / `respiratoryRate` / `sleepAnalysis` / `appleExerciseTime`。
- `bootstrap()` 由 `StudyPulseApp` 在 `container.asyncInit()` 完成、`isReady = true` 之后调用，避免启动期 I/O 竞争。
- `enable()` / `disable()` 切换 HRV 参与度；`refreshReadiness()` 重算 HRV 准备度；`refreshBodyStatus()` 重算 BodyStatus。

HRV 准备度：
- 采样窗口：14 天 `HKQuantitySample`（`heartRateVariabilitySDNN`）。
- 按日历日聚合：取每个日历日的第一个样本，按日期降序。
- 基线计算：仅统计 ≥ 7 个不同天数的样本，计算过去 14 天均值与标准差。
- Z-score：（当日 SDNN − 均值） / 标准差。
- 分类：excellent（z > 1）、normal（-1 ≤ z ≤ 1）、low（z < -1）、insufficient（少于 7 天）、noAuthorization（无授权）、queryFailed（查询失败）。

BodyStatus 多维身体信号：
- 字段：restingHeartRate、latestHeartRate、respiratoryRate、lastNightSleepHours、deepSleepHours、remSleepHours、exerciseMinutesToday、isUsable。
- 派生量：`restorativeSleepHours = deepSleepHours + remSleepHours`（这是「恢复性睡眠」雷达轴使用的值，反映深睡 + REM，不只是总睡眠时长）。
- SleepQuality 分类：unknown / poor (< 6h) / short (6-7h) / good (7-9h) / excellent (≥ 9h)。

PersonalBaselines 30 天个人基线：
- 由 `HealthHistoryStore` 维护，过去 30 天 `DailyHealthSnapshot` 滚动窗口，存于 `~/Documents/health_history.json`（NSLock 线程安全）。
- `StudyReadinessAlgorithm` 优先用个人 30 天均值 / 标准差对每个信号打分，至少 7 天样本时启用；样本不足时回退到 `AgeReference` 年龄段参考范围。
- 每个信号最终归一化到 0~1，HRV 作为硬覆盖，其余信号合成 5 档学习强度 × 5 类学习重点（最多 25 种组合），未覆盖的组合回退到「steady / balanced」。
- 完整输入 / 评分 / 决策细节见 `docs/algorithms/AlgorithmIntroduction.md`。

对外状态：hrvEnabled、hrvOnboardingCompleted、isAuthorized、isReady、readiness、dailyHRVHistory、lastSampleCount、hrvDetailLevel、bodyStatus、personalBaselines、bodyStatusAuthorized。
`hrvDetailLevel` 决定 `HRVStatusCard` 呈现模式 suggestionOnly / dataAndSuggestion / chartAndData。
首次启用时，`HomeView` 调用 `HRVOnboardingView` 三页介绍 HRV 是什么、隐私保护与授权确认。

---

## 7.5 LLM (BYOK 大模型) 子系统

`LLMClient.shared` 为 `@MainActor` ObservableObject 单例，**OpenAI Chat Completions 协议兼容**（支持 OpenAI / DeepSeek / 月之暗面 / 任何兼容端点）。`LLMConfig` 是 `nonisolated value type` 的不可变配置快照，由 `LLMConfig.from(_: AppPreferences)` 在主线程上按需构造（避免直接持有 `AppPreferences` 引用导致 UI 不能立即更新）。

**核心抽象**：
- `LLMClient.complete(prompt:config:caller:)`：非流式调用，返回最终 `String`。
- `LLMClient.stream(prompt:config:caller:onDelta:)`：流式调用，`onDelta` 接收**到目前为止的完整文本**（不是增量），便于 UI 端存进 `AsyncStream` 给 `SwiftStreamingMarkdown` 的 `MarkdownView` 流式渲染。
- `LLMPrompt`：`nonisolated` struct，封装 `system` / `[user,assistant]` 消息；`LLMRequestBuilder` 基类只保留 `latexFormattingRule` + 通用辅助，按 caller 拆为 **6 个独立文件**（Phase 3 拆分）：`MistakeAIAnalysisLLM`（错题 AI 解析）/ `BodyRadarLLM`（雷达建议）/ `HomeAskLLM`（主页问答 + Router + Answer）/ `AIQuizLLM`（AI 自测题生成 + 批改）/ `AISimilarQuestionLLM`（相似题生成 + 批改）/ `AIDiscussionLLM`（深入探讨 + 通用聊天）；基类还保留 `StudySuggestionsLLM` / `WeeklyReportLLM` / `ScorePredictionLLM` / `ComprehensiveScorePredictionLLM`。所有 caller **固定输出格式**（如 `## 错因分析 / ## 正确思路 / ## 类似题建议` 或 `## 强度/标题/建议/依据`）便于 `LLMResponseParser` 解析回写本地模型。
- `LLMResponseCache`：`actor` 隔离的 LLM 响应缓存（按 prompt hash + caller 做磁盘/内存缓存，避免短时间重复请求；命中即返回，未配置 LLM 或失败时也能用上次成功的输出兜底）。
- `LLMError`：9 类错误（`notConfigured` / `invalidURL` / `unauthorized` 401 / `rateLimited` 429 / `serverError(statusCode:body:)` / `network` / `malformedResponse` / `emptyResponse` / `timeout`），服务端 4xx 错误时把 `body` 拼进 `errorDescription` 便于排查。
- `LLMCallDebugInfo`：DEBUG 面板用，记录 `startTime` / `endTime` / `url` / `model` / `temperature` / `systemPrompt` / `messages` / `response` / `error` / `caller` 标签；`LLMClient.lastCallInfo` 缓存最近一次，`recentCalls` 环形 20 条历史。
- `AutoMindMapLLM`：错题思维导图 LLM；输入错题四块内容，输出结构化节点 JSON 给 `AutoMindMapViewModel` 渲染。
- `HomeAskDataProvider`：`enum HomeAskDataProvider` 把用户输入关键词匹配到 4 类上下文（`grade` / `mistake` / `trend` / `readiness`）之一，组合成 `HomeAskLLM` 的 prompt。

**8 大用户面 AI 功能 + 1 配置入口**：
1. **学习建议卡 `StudySuggestionsCard`**：先展示本地建议，再用 LLM 流式替换为 ✨ AI 建议（带 `✨ AI` 角标），失败回退本地 + 灰字提示；40 分钟冷却（持久化到 `AppPreferences.lastStudySuggestionsAIRequestTime`）。
2. **错题 AI 解析 `MistakeAIAnalysisSheet`**：错题详情 toolbar ✨ 按钮，按三段格式流式渲染；可一键把「正确思路」插入 `editedCorrectSolution`。toolbar Menu 还含 `AI 相似题组卷` → `AISimilarQuestionFlowView` 与 `AI 思维导图` → `AutoMindMapView` 与 `错题辩论` → `MistakeDebateSheet`。
3. **AI 自测题 `AIQuizSetupView` → `AIQuizView` → `AIQuizResultView`**：基于错题或科目由 `AIQuizLLM` 生成选择题 / 填空题（`QuizQuestion`），用户作答后由 `AIQuizLLM.grade(...)` 批改并给出错因。
4. **AI 相似题 `AISimilarQuestionFlowView`**：基于一道错题由 `AISimilarQuestionLLM` 生成 3~5 道相似题，用户作答后批改。
5. **AI 思维导图 `AutoMindMapView`**：基于错题四块内容由 `AutoMindMapLLM` 输出节点 JSON，渲染为可折叠树。
6. **错题辩论 `MistakeDebateSheet`**：多轮对话引导学生反思错解，由 `AIDiscussionLLM` 驱动；首条 AI 输出用 `isInitialContext` 标记 + 视觉弱化，不放入 conversation history。
7. **周 / 月报 AI 总结 `WeeklyReportSettingsView` + `WeeklyReportView`**：周报 / 月报 AI Summary 区块，流式 Markdown + 淡青底色，失败静默跳过。
8. **主页 AI 问答主卡片 `HomeAskCard` + `HomeAskSheet`**：点开 sheet，**`HomeAskDataProvider` 根据用户输入关键词自动选择 4 类上下文**（`grade` / `mistake` / `trend` / `readiness`）之一，与基础问题合并发给 `HomeAskLLM`。
9. **`LLMSettingsView` 配置入口**：总开关 + Base URL + API Key（masked 显示，Change 调用 `setLLMAPIKey(nil)` 清空后才能改）+ Model + Temperature slider + System Prompt 追加 + Test Connection。

**强制规范**：
- **总开关关闭 / 缺字段 / 网络错 / 解析失败都必须静默回退到本地实现**，绝不向用户弹 alert；只写 `Log.llm` category。
- **`LLMClient` 必须从环境注入 `AppPreferences`（`@EnvironmentObject`）**而不是 `AppPreferences()` 初始化器，否则 UI toggle 改了 debug 面板看不到。
- **错题 AI 解析输出固定 3 段**（`## 错因分析 / ## 正确思路 / ## 类似题建议`）；雷达 LLM 输出固定 4 段（`## 强度/标题/建议/依据`），解析后只替换 `title/description`，**保留本地 `icon/priority/color`**。
- **AI 解析 / 预测按钮必须放在用户最直接看到的页面**（如 `MistakeSetDetailView` 错题详情页 toolbar），而不仅仅放在二级编辑页 `MistakeDetailEditView`；否则用户找不到 AI 功能。
- **雷达 LLM 请求有 40 分钟冷却**，仅用户点击「立刻分析」按钮可绕过；持久化到 `AppPreferences.lastRadarAIRequestTime` / `lastStudySuggestionsAIRequestTime`。
- **`LLMChatView` 历史只在内存**，**离开页面自动清空**；不持久化到磁盘。
- **「深入探讨」sheet 把上一次的 AI 输出放在 system prompt**（`===` 分隔符 + "务必主动引用"指示），**不要**作为 conversation history 的第一条 assistant 消息；UI 上用 `isInitialContext` 标记 + 视觉弱化展示。
- DEBUG 模式：`LLMDebugSheet` 按 caller 分组显示 `recentCalls` + JSON 详情；`HomeView` 工具栏 `.llmDebugHomeButton()`（`caller = nil` 显示全部分组）。
- AI 启用卡片底部显示 `LLMCallIndicator`：`🤖 [caller] · <time> ago · <duration>s` + 状态图标。

---

## 7.6 Audio (语音备忘录) 子系统

`AudioStorage`（`nonisolated` struct）封装 `~/Documents/audio/` 目录 + 唯一文件名生成（`<uuid>.m4a`）+ 删除。
`VoiceMemoManager`（`@MainActor` ObservableObject）封装 `AVAudioRecorder` 录音会话：请求 `NSMicrophoneUsageDescription` 权限、`startRecording()` / `pause()` / `resume()` / `stop()` / `delete(filename:)`。

**使用流程**：
- `MistakeDetailEditView` 编辑错题时显示「录音」按钮 → 弹出 `VoiceMemoRecordingSheet`（`AVAudioRecorder` 波形 + 时长 + 暂停 / 继续 / 完成）→ 完成后写 `~/Documents/audio/<uuid>.m4a` 并把 `filename` 写入 `MistakeNote.audioFileName`。
- `MistakeSetDetailView` 详情页若 `MistakeNote.audioFileName != nil` 则嵌入 `AudioPlaybackView`（`AVAudioPlayer` + 进度条 + 播放 / 暂停 / 删除）。

**权限**：`Info.plist` 新增 `NSMicrophoneUsageDescription`（说明录音用于错题语音备忘录）。

---

## 7.7 Diary (学习日记 + 心情记录) 子系统

`DiaryRepository` 为 `@MainActor` Repository，持有 `diaryEntries: [DiaryEntry]` + `filteredDiaryEntries`（按 active phase 过滤）；底层用 SwiftData `DiaryEntryRecord` 持久化，content 字段 `@Attribute(.externalStorage)` 外存。

**模型**（`Models/DataModels.swift`）：`DiaryEntry`（id / date / moodScore 1~5 / energyScore 1~5 / energyTag 专注/平静/兴奋/疲惫/焦虑/烦躁/迷茫 / content Markdown / phaseId? / createdAt / updatedAt）；自定义 `init(from:)` 用 `decodeIfPresent` 兼容老数据。

**视图**（`Views/Diary/`）：
- `DiaryView`：日记主页，顶部日历 + 当日编辑区 + 心情 / 精力标签。
- `DiaryEntryEditView`：Markdown 编辑 + 心情 emoji + 精力标签选择。
- `DiaryCalendarView` + `DiaryCalendarModels` + `DiaryCalendarDayCell`：日历视图，按日显示心情 emoji + 精力色块。
- `MoodTrendChartView`：心情趋势折线图（最近 30 天 moodScore / energyScore）。
- `DiaryHomeCard`（在 `Views/Home/HomeCards/`）：主页快速入口卡片，显示今日心情 + 精力 + 跳转 `DiaryView`。
- `DiarySettingsView`（在 `Views/Settings/`）：日记提醒时间 + 显示选项。

**通知**：`DiaryReminderNotifications`（identifier 前缀 `DiaryReminder_`），可配置时间；由 `RepositoryContainer.addDiary(...)` facade 触发 `reschedule(...)`，`scenePhase == .active` 时统一重排。

---

## 7.8 Routines (周计划例程) 子系统

`RoutineRepository`（模板）+ `RoutineInstanceRepository`（实例）为 `@MainActor` Repository，分别持久化到 SwiftData `RoutineRecord` / `RoutineInstanceRecord`。

**模型**（`Models/DataModels.swift`）：
- `Routine`（id / title / type `RoutineType` mistakeReview/flashcard/general / subject? / weekdays [Int] / startTime / endTime / enabled / createdAt / phaseId?）。
- `RoutineInstance`（id / routineId / title / type / subject? / startTime / endTime / date / dateKey 幂等 key / isCompleted / completedAt? / spawnedMistakeCount）。

**核心组件**（`Managers/Plan/`）：
- `RoutineSpawner`（`@MainActor @Observable` 单例）：监听 `enabledRoutines` + 60s 跨日 polling + routine 增删触发；`spawnForToday(now:)` 幂等（按 `routineId|yyyyMMdd` 去重）产生 `RoutineInstance`；`runOnce()` 还会触发 `cleanupStale(olderThanDays: 30)`。在 `RepositoryContainer.asyncInit()` 第 7 步调用，且在 `scenePhase == .active` 时再次调用。
- `RoutineLiveActivityController`：`ActivityKit` Live Activity 协调器；mistakeReview 类型的 routine spawn 后启动 `RoutineActivityAttributes` Live Activity，完成后 dismiss。

**视图**（`Views/Todo/`）：`RoutineEditorSheet` 例程模板编辑 sheet；TodoView 列表把今日 `RoutineInstance` 跨域聚合为 `TodoEntry`。

**facade**：`RepositoryContainer.addRoutine(...)` 调 `routineRepo.add(...)` + `RoutineSpawner.shared.runOnce()`；`addDiary` / `addGrade` / `addMistake` 等也间接影响 routine 完成度（mistakeReview 类型可spawn 错题 SRS 队列）。

---

## 7.9 Plant (虚拟植物养成) 子系统

`PlantManager`（`Managers/Plant/`，`@MainActor @Observable` 单例）订阅 `AchievementManager.shared.snapshot` 变化（通过 `NotificationCenter` 监听 `achievementsSnapshotDidChange`，替代原 1.5s polling）→ 调用 `PlantStage.derive(...)` 重算 `currentStage`；持 `history` 阶段切换记录（最多 50 条）；`recordActivity(trigger:)` 由 `RepositoryContainer.addGrade` / `addMistake` / `addDiary` 触发（不立即重算，等 AchievementManager sink 触发）。

**模型**（`Models/PlantState.swift`）：
- `PlantStage`（enum，8 阶段）：seed → sprout → seedling → young → mature → flowering → flourishing → withered（枯萎）；reborn 是 withered → seedling 的恢复转换。
- `PlantStageTransition`：fromStage / toStage / date / trigger。
- `PlantStage.derive(streak:totalActiveDays:todayActive:lastActiveDate:previouslyWithered:)`：纯函数，根据连续打卡天数 + 总活跃天数 + 今日是否活跃 + 上次活跃日期 + 之前是否枯萎 决定下一阶段。

**持久化**（`Models/PlantStateRecord.swift`）：单例实体（仅 1 行），含 `currentStageRaw` / `previousStageRaw` / `historyData: Data?`（JSON `[PlantStageTransition]`）/ `lastActivityAt` / `forceOverrideRaw?`（Debug 强制覆盖）/ `simulatedStreakOverride?` / `simulatedLastActiveDate?`。

**视图**（`Views/Plant/`）：
- `PlantHomeCard`：主页植物卡片（在 `Views/Home/HomeCards/`），Canvas 渲染当前 `PlantStage`。
- `PlantCanvasView`：Canvas 绘制核心（茎 / 叶 / 花瓣 / 光点 / 灰色覆盖）。
- `PlantAnimator`：阶段切换动画（Spring + sortKey 插值）。
- `PlantDetailView`：植物详情页（当前阶段 + 历史 timeline + 解锁提示）。
- `PlantDebugView`：DEBUG 模式下手动切换 stage 调试页（forceOverride / 模拟 streak / 模拟 days since last active）。

**配套**：`PetalColorCatalog` 按 stage 提供主色 + 渐变色。

---

## 7.10 ThemeShop (主题商店) 子系统

`Models/ThemeShop.swift` 定义三类皮肤目录 + `ThemeShopCatalog` 静态目录；`Views/Settings/ThemeShop/ThemeShopView.swift` 是商店入口（`SettingsCategory.themeShop`）。

**三类皮肤**：
- `AccentPalette`：主色调色板（id 稳定 / 主色 hex / 渐变色 / unlockAchievementId?）；解锁条件绑定 `AchievementDefinition.id`，未解锁时灰显并提示完成哪个成就解锁。
- `CardSkin`：卡片皮肤（背景纹理 / 边框 / 阴影 / 圆角风格）。
- `TimerAnimation`：学习计时器动画风格（粒子 / 流光 / 极简）。

**消费方**：
- `AccentPalette`：通过 `AppEnvironmentManager.effectiveAccentColor` 驱动 `ContentView.tint()` / `TrendChartView.tintColor` / `FlashcardStudyView` 进度条。
- `CardSkin`：通过 `CardSkinModifier`（`.glassCard(enabled:cornerRadius:)`）修饰符应用到主页面卡片。
- `TimerAnimation`：通过 `StudyTimerView` / `StudyTimerLiveActivity` 的动画分支选择。
- `CardSkinRenderer`：商店内的皮肤预览渲染器。

**解锁流程**：用户达成 `AchievementDefinition` → `AchievementManager` 触发 `unlockAchievementId` → `ThemeShopCatalog.isUnlocked(_:achievements:)` 返回 true → 商店列表项由灰显变为可启用；用户选中后写入 `AppPreferences.accentPaletteId` / `cardSkinId` / `timerAnimationId`。

---

## 7.11 AIQuiz / AutoMindMap / MistakeDebate 子系统

错题详情页（`MistakeSetDetailView`）toolbar Menu 提供三个 AI 学习辅助入口，全部走 BYOK LLM 子系统（详见 7.5）：

**AI 自测题（`AIQuizLLM` + `Views/Mistake/LLM/`）**：
- `AIQuizSetupView`：选择科目 / 题数 / 难度 / 来源（错题 / 科目）。
- `AIQuizView`：作答页面，渲染 `QuizQuestion`（选择题 / 填空题，含 Markdown + LaTeX）；用户提交后调 `AIQuizLLM.grade(...)`。
- `AIQuizResultView`：批改结果，逐题显示对错 + AI 解释错因；可一键把错题加入错题本（`MistakeRepository.add(...)`）。

**AI 思维导图（`AutoMindMapLLM` + `AutoMindMapViewModel` + `Views/Mistake/AutoMindMapView.swift`）**：
- 输入错题四块内容（题目 / 错因 / 错解 / 正解）。
- LLM 输出结构化节点 JSON（根节点 / 子节点 / 关联边）。
- `AutoMindMapViewModel` 解析 JSON 为节点树。
- `AutoMindMapView` 用 Canvas / SwiftUI 渲染可折叠树，支持点击节点展开 / 收起。

**错题辩论（`AIDiscussionLLM` + `Views/Mistake/MistakeDebateSheet.swift`）**：
- 多轮对话引导学生反思错解：AI 先复述错题 → 提问"你当时是怎么想的" → 用户回答 → AI 引导发现矛盾 → 给出改进建议。
- 首条 AI 输出用 `isInitialContext` 标记 + 视觉弱化，**不放入 conversation history**，仅作为 system prompt 引用（`===` 分隔符 + "务必主动引用"指示）。
- 复用 `ChatBubble` + `ChatInputBar` 组件。

**强制规范**：所有三个功能在 LLM 未配置 / 调用失败时**静默回退**（按钮 disabled 或弹出"LLM 未配置"提示，不报错）；DEBUG 模式下 `LLMDebugSheet` 按 caller 分组显示历史调用。

---

## 7.12 Time Investment (长期时间投入) 子系统

独立的长期项目时间投入域：**刻意不复用成绩 / 考试用的学科 `Subject` 模型**，用专属的 `TimeInvestmentSubject`（root project，含 `TimeInvestmentTheme` 5 色主题）+ 最多两级 `SubTask`（形成三层层级）。

**模型**（`Models/TimeInvestment.swift`）：`TimeInvestmentSubject` / `SubTask` / `InvestmentTarget`（subject / subTask 两类，`rawID` 统一） / `GoalReward`（绑定目标的时长成就，`thresholdSeconds`）/ `StudySessionSource`（timer / manual）。全部 `nonisolated value type` + Codable + Hashable + Sendable。

**SwiftData 持久化**：`TimeInvestmentSubjectRecord` / `SubTaskRecord` / `GoalRewardRecord`（`Models/SwiftData/StudyPulseModels.swift`），由 `StudyPulseSchemaV4` 承载。

**会话绑定**：`StudyTimerManager.selectInvestmentTarget(_:)` 让当前 / 新会话可选绑定一个 `InvestmentTarget`；完成后 `StudySession.investmentTarget` 一并持久化。`StudySessionRepository.assign(_:to:)` 批量把一组会话（如 `unassignedSessions`）绑定到目标。`StudyTimerManager` 从 `StudyPulseApp.asyncInit()` 后 `attach(sessionRepository:timeInvestmentRepository:)` 注入两个 repo。

**引擎**（`Services/TimeInvestmentEngine.swift`）：`TimeInvestmentAggregator` 纯函数聚合器，按 target 聚合直接 / 总投入秒数（subTask 会沿 `parentSubTaskID` 把后代秒数汇总到根 subject）+ 项目 / 全局连续天数。

**视图**（`Views/TimeInvestment/`）：`TimeInvestmentView`（项目列表 + 汇总卡片 + 未分配会话），入口在 `StudyTimerSettingsSheet` 工具栏；`TimeInvestmentEditors`（项目 / 子任务 / 奖励编辑）；`TimeInvestmentSummaryCard`。`TimeInvestmentViewModel` 持有 `projects: [ProjectSummary]` / `rewards` / `unassignedSessions` / `globalStreak` 等状态。

**引擎单测**：`StudyPulseTests/TimeInvestmentEngineTests.swift`（聚合 / 后代汇总 / streak）。

---

## 7.13 Backup (全量备份 / 恢复) 子系统

`Managers/Backup/` 提供全量备份与恢复：把 SwiftData 实体 + UserDefaults + App Group 数据导出为 `.studypulsebackup` 归档（`BackupDocument` 为 `FileDocument`）。

**组件**：`BackupExporter`（导出）+ `BackupImporter`（导入）+ `BackupManifest`（`formatIdentifier = com.chenkai.gao.studypulse.backup` + `formatVersion` + `schemaVersion = 4` + `recordCounts` + 媒体统计）+ `BackupValidator`（恢复前校验）+ `BackupChecksum`（校验和）+ `BackupRestoreCoordinator`（恢复编排）+ `BackupArchive` / `BackupDTOs` / `BackupError`。

**入口**：`DataManagementSettingsView` → `BackupRestoreView`（`Views/Settings/`）+ `BackupRestoreViewModel`（`ViewModels/`）。

---

## 8. 可定制主页

`HomeLayoutPreference` 为 Codable struct，持久化到 UserDefaults。`HomeView` 每一次 body 评估时都从 UserDefaults 读取，按启用顺序渲染启用的卡片。iPad 使用两栏 `LazyVGrid`，iPhone 使用单列 VStack。

`HomeCardType` 包括（17 个，按默认顺序）：
- dailyPlan：今日 Top-3 计划卡（由 `DailyPlanEngine` 派生 exam / mistake SRS / routine / task 的最紧迫 3 条）。
- learningHeatmap：90 天学习热力图（`LearningHeatmapView`），`isFullWidth: true` 全宽。
- hrvStatus：HRV 状态（接入 LLM 增强，40 分钟冷却）。
- diary：学习日记 + 心情记录入口（点击 emoji cycle moodScore，点击其余区域打开 `DiaryView` sheet）。
- homeAsk：主页 AI 问答主卡片（`HomeAskCard`），点击弹出 `HomeAskSheet` 与大模型讨论身体 / 成绩 / 趋势 / 复习；自带 Button 弹出 sheet，**不参与长按分享菜单**。
- unregisteredExamsReminder：未注册考试提醒，空时隐藏。
- flashcardReview：闪卡复习入口（基于 SRS 队列，跳转 `FlashcardStudyView`）。
- quickActions：快速动作。
- studyTimer：学习计时器入口（`StudyTimerCard`）。
- streakProgress：连续打卡 / 每日目标进度（`StreakHomeCard`），点按进入 `AchievementsView`。
- plant：植物卡片（`PlantHomeCard`，Canvas 渲染当前 `PlantStage`，详见 7.9）。
- studySuggestions：学习建议（接入 LLM 增强，40 分钟冷却）。
- trendChart：趋势图。
- upcomingExams：即将到来的考试。
- dailyQuote：每日金句。
- recentGrades：近期成绩。
- habitInsight：习惯洞察卡（基于 90 天 `StudySession` 由 `HabitInsightEngine.computeInsights(...)` 派生 4 类 PatternKind：peakEfficiency / procrastination / streakDay / weakDay；默认 enabled = false）。

`HomeLayoutSettingsView` 提供拖动重新排序与每项启用 / 禁用开关，然后保存回 UserDefaults。`HomeLayoutPreference.mergeWithDefault` 当未来版本新增卡片类型时保留用户的选择。

iPad 渲染：`HomeView.iPadDynamicCards` 按"块"渲染：全宽卡片（`isFullWidth: true`）脱离 2 列网格独占整行，普通卡片每 2 个成行。`HomeView` 顶部 `LearningHeatmapView` 是全宽卡片，默认在顶部位置。

---

## 9. 图像、OCR 与 CSV 管线

图像管线：
- 拍摄：`PhotoCaptureView`（相机）或 `ImagePicker`（照片库）。
- 处理：压缩为 JPEG 数据，通过 `Repository.profileRepo.saveAvatar(_:)` 或 `Repository.gradeRepo.add(...)`（grade 内部自动保存图片）写入 `~/Documents/images/`。
- 显示：从 `ImageCache` 读取缩略图（`NSCache` 最多 50 项，最大 300px，nonisolated）。
- 全屏：`ZoomableImageView`（双指缩放与双击缩放）。
- 自定义背景图：`Application Support/Backgrounds/bg_<uuid>.jpg`（9:19.5 中心裁剪），`BackgroundImageView` 全屏 + 模糊 + 暗化遮罩铺在 `ContentView` 底部；5 个主页面根用 `Color(.systemGroupedBackground).opacity(0.4)`；`List` / `Form` 加 `.scrollContentBackground(.hidden)`；NavigationStack 根加 `.containerBackground(.clear, for: .navigation)`；`TabView` 加 `.toolbarBackground(.hidden, for: .tabBar)`。

OCR 管线：
- `OCRManager.shared.recognizeText(in:completion:)` 使用 `VNRecognizeTextRequest`，`recognitionLevel = .accurate`，`recognitionLanguages = ["zh-Hans", "en"]`。

Markdown 管线：
- `Views/Components/Markdown/` 提供 `MarkdownEditorView` / `MarkdownPreviewView` / `MarkdownTextEditor` 三件套：错题四块编辑支持分屏（编辑 + 实时预览），由 `swift-markdown-ui` / `swift-cmark` / `highlightswift` / `iosMath` 共同渲染（代码高亮 + LaTeX 公式）。
- `MistakeSetDetailView` 错题详情页面**只渲染格式化输出**，原始 Markdown 源不显示。

CSV 管线：
- `DataExportManager`（`@MainActor` enum）按年级 / 错题 / 考试 / 综合考试导出 CSV，使用正确的 CSV 转义规则。
- `CSVDocument`（`FileDocument`）把 CSV 字符串包装成可共享文件，通过 `UIActivityViewController` 共享。

学习报告管线：
- `ReportContentView` 接收不可变 `StudyReport`，无 `@EnvironmentObject` 依赖，可经 `ReportRenderer`（`ImageRenderer` + Core Graphics）输出 PNG / JPEG。
- `ReportImageDocument`（`FileDocument`）包装图像供 `.fileExporter` 导出。
- `ReportOptionsSheet` 收集报告周期与模块开关，`ReportShareSheet` 触发分享。

日志导出管线：
- `LogStore` 在内存中累积 `LogEntry`（Swift `actor` 线程隔离保障并发安全，5000 条上限）。
- `LogDocument`（`FileDocument`）把 `LogStore` 序列化为文本行（时间戳 + subsystem + category + level + message），供 `.fileExporter` 导出。
- `DataManagementSettingsView` 提供「Export Log」按钮触发导出。

AppIntents 桥接管线：
- `IntentActionStore.shared.pendingIntentAction` 镜像到 `RepositoryContainer.pendingIntentAction`。
- 6 个 `AppIntent`（AddGrade / RecordMistake / CheckUpcomingExams / CheckBodyStatus / CheckReadiness / CheckSubjectAverage）从 Siri 进程写入 `IntentActionStore`。
- `ContentView` 观察 `IntentActionStore` 变化后路由到对应 View / Sheet，处理完清空 `pendingIntentAction`。

---

## 10. iPad 适配

`ContentView` 在水平 size class 为 regular 时使用 `NavigationSplitView`；iPhone 使用 `TabView`。iPad 侧栏使用 `NavigationLink(value: tab)` 选择标签。

`Views/Helpers/iPadLayout.swift` 提供：
- `adaptiveMaxWidth(_:)` 修饰符（默认 720），在 iPad 上居中内容，iPhone 上全宽。
- `AdaptiveHStack`：iPad 为 `HStack`，iPhone 为 `VStack`。
- `AdaptiveGridColumns(compact:regular:spacing:)`：在 compact 尺寸下 compact 栏数，regular 尺寸下 regular 栏数。
- `adaptiveCardPadding()`：iPhone 加 20pt 外间距，iPad 不加。

各页面的 iPad 最大宽度：PreferencesView 为 640；SettingsView 为 720；ExamView 为 800；TrendsView 为 900；MistakeView 为 900；HomeView 为 1100（使用两栏网格呈现动态卡片）。

适配原则：
- iPhone 布局保持不变；所有 iPad 分支都在 `horizontalSizeClass == .regular` 或 `UIDevice.current.userInterfaceIdiom == .pad` 下判断。
- 内容居中而非拉伸。
- 视图层只调用 `iPadLayout` 辅助组件，不内联写 size class 分支。

---

## 11. 本地化

`Localizable.strings` 放在 `en.lproj` / `zh-Hans.lproj` / `zh-Hant.lproj` / `ja.lproj` / `ko.lproj` 目录。所有用户可见字符串使用 `.localized()` 扩展（定义在 `StringsLocalized.swift`）。**注意：`Text("foo".localized)` 会被推断为闭包 `@Sendable () -> String` 而非 `String`，报 "type '() -> String' cannot conform to 'StringProtocol'"，必须 `Text("foo".localized())` 带括号**。应用在 `AppEnvironmentManager.setLanguage(_:)` 中通过修改 UserDefaults 的 `AppleLanguages` 切换语言，`applyLanguageOnLaunch()` 在应用启动时读取并应用。

热力图本地化：5 份 `Localizable.strings` 同步添加 `heatmap.*` 键；`heatmap.bestDay` 格式串的占位符顺序必须是 `%d` (Int) 在前、`%@` (String) 在后，因为 Swift 端按 `(Int, String)` 顺序传参。

---

## 12. 隐私权限

需要 Info.plist 与 entitlements 声明以下权限键：
- `NSCameraUsageDescription`：用于拍摄错题照片。
- `NSPhotoLibraryUsageDescription`：用于从照片库选择照片。
- `NSCalendarsUsageDescription`：用于添加考试到系统日历。
- `NSRemindersUsageDescription`：用于把作业 / 阅读材料同步到系统提醒事项（Todo 模块）。
- `NSHealthShareUsageDescription`：用于读取 HRV / 心率 / 呼吸率 / 睡眠 / Apple 锻炼时间。
- `NSMicrophoneUsageDescription`：用于在 `MistakeDetailEditView` 中录制错题语音备忘录。
- `NSSupportsLiveActivities`：Info.plist 启用 Live Activity（学习计时器）。
- `com.apple.developer.healthkit`：在 entitlements 文件开启 HealthKit 能力。
- `com.apple.security.application-groups`：App Group `group.com.chenkai.gao.studypulse`，主应用与 `StudyPulseWidgetExtension` 共享小组件与 Live Activity 数据。
注意 `NSHealthUpdateUsageDescription` 未使用，应用不向 HealthKit 写入数据。

---

## 13. WidgetKit 扩展

`StudyPulseWidget/` 目录已作为 `StudyPulseWidgetExtension` 目标接入 `StudyPulse.xcodeproj`，scheme：`StudyPulseWidgetExtension`。Bundle id 为 `Gao.Chenkai.StudyPulse.Widget`，部署目标 iOS 18.6。

提供三个静态小组件 + 一个 Live Activity：
1. `ExamWidget`：即将到来的考试。
2. `TrendWidget`：科目成绩趋势折线图。
3. `HRVWidget`：HRV 准备度（与 `HomeView` 的 `HRVStatusCard` 视觉一致）。
4. `StudyTimerLiveActivity`：学习计时器 Live Activity，Lock Screen 横幅 + Dynamic Island compact leading / compact trailing / minimal / expanded；通过 `StudyTimerActivityAttributes` 与主应用共享会话状态（remainingSeconds / totalSeconds / intensityLabel / intensityIcon / 强度色 hex）。

每个静态小组件都有自己的 `*WidgetData.swift` 与 `*WidgetSyncManager.swift`（位于 `StudyPulse/Managers/Widget/`），主应用在合适时机调用 `sync*()` 写入 App Group。`StudyTimerLiveActivity` 不需要 App Group 同步 —— `ActivityKit` 直接与小组件扩展进程通信。`StudyPulseWidgetBundle` 是 `@main` bundle，组合上述四个 widget。

每个静态小组件与 Live Activity 都完成了 en / zh-Hans / zh-Hant / ja / ko 五种语言本地化，字符串位于 `StudyPulseWidget/{lang}.lproj/Localizable.strings`。小组件扩展内复制了一份 `String.localized()` 扩展用于读取自己的 `Localizable.strings`。

启用步骤（已就绪，无需手工操作）：
1. Xcode 中已存在 `StudyPulseWidgetExtension` 目标，bundle id 为 `Gao.Chenkai.StudyPulse.Widget`，部署目标 iOS 18.6。
2. 主应用与小组件目标都已启用 App Group `group.com.chenkai.gao.studypulse`（`StudyPulse.entitlements` + `StudyPulseWidgetExtension.entitlements`）。
3. 若修改 App Group 名称，更新 `AppGroupConfig.identifier`。
4. 在主应用的 Exam 添加 / 编辑后调用 `WidgetDataSyncManager.syncUpcomingExams(...)`；成绩变化后调用 `TrendWidgetSyncManager.syncTrend(grades:subjects:)`。`StudyPulseApp.scenePhase == .active` 且 `container.isReady == true` 时会统一调用所有 `sync*()`。
5. 使用 `WidgetCenter.shared.reloadAllTimelines()` 触发刷新。
6. Live Activity：`StudyTimerManager` 启动 / 更新 / 结束 Activity，`StudyTimerActivityAttributes` 字段变更时同步更新小组件扩展内对应渲染分支。

`ExamWidgetData` / `HRVWidgetData` / `TrendWidgetData` 为小的 Codable struct，由对应的 `WidgetDataStore` 在各自 `*WidgetData.swift` 中管理读写。

---

## 14. 依赖（SPM）

使用 Swift Package Manager 管理依赖，本地 / Vendored 包统一放在 `Packages/` 目录下：
- `SwiftStreamingMarkdown`（本地，`Packages/SwiftStreamingMarkdown-0.2.0/`）：Markdown 渲染核心，支持 LaTeX 公式与流式输出。**`equatable` 包依赖已移除**以避免构建问题。
- Vendored 包（`Packages/Vendored/`）：`swift-cmark`（cmark-gfm 解析核心）、`swift-markdown`（Apple 官方 Markdown）、`highlightswift`（代码高亮）、`iosMath`（LaTeX 数学）。
- 旧的 `WSOnBoarding` / `NetworkImage` 依赖已移除 —— 引导改用 `Views/OnBoarding/` 原生实现，远程图片改用 `ImageCache` + SwiftUI `AsyncImage`。

解析包的方式：在 Xcode 中 File → Packages → Resolve Package Versions；或在命令行执行 `xcodebuild -resolvePackageDependencies -project StudyPulse.xcodeproj`。**注意 `xcodebuild` 可能因沙箱冲突卡住 SPM 解析；用 `swift package resolve` 替代可能有效**。

Apple 框架：SwiftUI、Charts、Vision、EventKit、UserNotifications、HealthKit、WidgetKit、ActivityKit、SwiftData、AppIntents、UniformTypeIdentifiers。

---

## 15. 构建与运行

构建辅助脚本 `scripts/build.sh` 提供以下选项：
- 默认：调试构建，iPhone 17 模拟器（默认使用 `DerivedDataBuild/` 子目录）。
- `release`：发布构建。
- `clean`：清理构建目录。
- `list`：列出可用模拟器。
- `help`：显示所有选项。

直接使用 xcodebuild 命令：
```bash
xcodebuild -project StudyPulse.xcodeproj -scheme StudyPulse -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build
```

可用 scheme：`StudyPulse`、`MarkdownUI`、`StudyPulseWidgetExtension`。可用配置：`Debug`、`Release`。

构建注意事项：
- **Xcode IDE 和 xcodebuild CLI 不要在同一 DerivedData 目录上并发运行**（会引起 `build.db` 锁）；`scripts/build.sh` 默认使用 `DerivedDataBuild/` 子目录以隔离。
- Xcode 16+ 构建系统使用 `XCBuildData/build.db` SQLite 数据库做模块协调；异常退出或并发访问会导致数据库锁定，**需删除该文件**。构建数据库锁定后可能残留脏缓存导致 "invalid reuse after initialization failure" 错误，**需清空整个 `DerivedData` 目录**。
- Xcode IDE 可能因 SPM 缓存不一致显示 "Missing package product" 错误；重置 package cache 或清空 `DerivedData` / build 目录可解决。
- 不需要运行Test。

---

## 16. 代码规范

架构与编码规范：
- **MVVM + Repository**：视图层通过 `@Environment(RepositoryContainer.self) var container` + ViewModel 访问数据；**不**直接持有 `RepositoryContainer` 单例 / `DataManager` 之类的全局对象。
- ViewModel 规范：`@MainActor final class : ObservableObject` + `@Published private(set)` 状态 + `static func makeDefault(container:)` 工厂 + `import Combine`（`@Published` 需要）。
- 子 View 接收 ViewModel 用 `let viewModel: XxxViewModel` 参数 + `@ObservedObject` 标注（**不是 `@StateObject`**，因为 VM 由父 View 创建并拥有）。
- Service 规范：纯函数 `enum` 或 `struct`，**不 import SwiftUI**（`QuoteProvider` 例外，因为 `StudySuggestion.color: Color`）。
- Repository 规范：`@MainActor class` 实现 protocol；只服务自己的域；**不互相调用**；跨域操作由 `RepositoryContainer` 编排。
- **16 域 Repository**：Grade / Mistake / Exam / Task / Phase / Profile / Subject / Routine / RoutineInstance / Diary / Coach / StudySession / TimeInvestment / ExamAutopsy / ExamSimulation / ExamPlan。
- 模型为 `Codable` + `Sendable` + `Hashable` 的 `nonisolated value type`，可安全地跨 actor 传递。
- 拥有 `@Published` 状态的管理器使用 `@MainActor`；纯辅助（`DataFileIO` / `WidgetDataStore` / `EducationConfig` / `ImageCache` / `SubjectConfig` / `EducationRegion`）为 `nonisolated`。
- SwiftUI 视图放在 `Views/` 目录下；`Components/` / `Helpers/` / `Admin/` / `OnBoarding/` 作为子目录。
- 字符串永远使用 `.localized()` 扩展（必须带括号）。
- 颜色与日期通过 `ColorExtensions` / `DateExtensions` 包装。
- 图像文件保存在 `~/Documents/images/` 目录，不要内联到 JSON（旧的 `Grade.image` 字段已在 `RepositoryContainer.asyncInit` 中迁移为文件）。
- 自定义背景图保存在 `Application Support/Backgrounds/bg_<uuid>.jpg`。
- `MistakeDetailEditView` 使用 `EditSection` 枚举驱动四个编辑块（Question / Reason / Wrong / Correct）。
- `EducationConfig` 为 `nonisolated` enum，提供全球教育系统数据。
- `SubjectConfig` 使用 `required(...)` / `elective(...)` 工厂方法构造。
- 任何用 `Log.xxx.info(...)` 的文件必须 `import os`。
- **任何 `Codable` struct 持久化在 UserDefaults 中、新增非 optional 字段时**：必须手写 `init(from:)` + `CodingKeys`，所有新字段用 `decodeIfPresent` 给默认值；否则老 JSON 解码会 fatalError 闪退。
- **`Section { ... } header: { ... } footer: { ... }` 必须用 trailing closure 语法**（`Section(header: Text(...))` + `} footer: { ... }` 组合会报 "incorrect argument label in call"）。
- **Dictionary 唯一键崩溃防御**：涉及从数据 store 聚合的 dict 用 `var d: [K: V] = [:]` + for 循环手动 `d[key] = ...`，**不要用 `Dictionary(uniqueKeysWithValues:)`**（重复键时 fatalError）。

---

## 17. 性能说明

- 应用启动使用 `container.asyncInit()` 在 `.task` 后台执行（JSON 迁移 + 各 repo loadAll + 图片迁移 + 通知 widget 调度 + `RoutineSpawner.runOnce()`），避免阻塞主线程；`isReady` 在完成后置 true。`HealthKitManager.bootstrap()` / `AchievementManager.bootstrap()` / `PlantManager.shared.bootstrap(container:)` 都在 `isReady` 之后才调用。
- 数据层使用 `PersistenceExecutor` 配合 `#Predicate` 谓词 fetch（Predicate-backed fetch），在大数据量下仅拉取满足筛选条件的模型记录，大幅减轻内存开销与读写延迟。
- `LogStore` 和 `LLMResponseCache` 全面升级为 Swift 6 `actor` 隔离模型，替代过时的 NSLock，避免高并发日志与 LLM 请求响应写入时的锁竞争与潜在死锁。
- 前台激活（`scenePhase == .active`）触发学习会话和 Widget 数据异步加载，避免主线程帧卡顿。
- `ImageCache` 提供 `NSCache` 缓存的缩略图（最多 50 项，最大 300px），完全线程安全（nonisolated）。
- `DataFileIO.imagesDir` 用 `NSLock` 缓存路径，避免每次访问都 stat。
- `ExamRowView` / `ComprehensiveExamRowView` / `UpcomingExamCard` 使用 `daysRemaining` 计算属性替代 `@State + onAppear`，避免不必要的重渲染。
- iPad `HomeView` 使用 `LazyVGrid` 呈现仪表盘，保持内存占用低，即使启用了大量卡片。
- `HomeView` 采用分帧渲染（phased rendering），把动态卡片拆到多个 RunLoop 帧绘制，把首帧 long task 拆成多个小任务，让主线程保持响应。
- `AvatarView` / `WelcomeHeaderView` / `SettingsView` 的头像加载改为异步 Task，不再在主线程同步读文件 / 解码图片。
- `LagMonitor.shared` 持续监测主线程帧间隔，连续丢帧时把详细堆栈 / 时间戳写入 `LogStore`，便于事后通过 Export Log 复盘卡顿。
- `Services/` 是纯函数 enum，5 个 ViewModel 内部对 grade / mistake / exam 的过滤聚合全部走 `SubjectAggregator.aggregate` / `ExamFilter.examsWithinDays` 等共享服务，**避免重复实现**。
- `RepositoryContainer.observeActivePhaseChanges()` 用 0.5s polling 而非 Combine 桥接，避免引入 Combine 依赖；切换 phase 触发 6 个 `filtered*` 缓存重算（grade / mistake / exam / task / routine / diary）。

---

## 18. Agent 工作规则

AI 代理在本仓库工作时遵循以下规则：
- 每次非 trivial 代码修改后，运行构建（Xcode Cmd+B 或 `./scripts/build.sh`）确认通过，留下语法或类型错误。
- 遵循文件布局：
  - 新视图按子领域放在 `Views/{Home,Trends,Exam,Grade,Mistake,Flashcard,Todo,Diary,Plant,Profile,StudyTimer,Report,Settings,About,Admin,OnBoarding,Components,Helpers,Debug,LLM}/`。
  - 可复用组件放在 `Views/Components/`。
  - 视图辅助放在 `Views/Helpers/`。
  - 开发者页面放在 `Views/Admin/`。
  - DEBUG 模式调试组件放在 `Views/Debug/`。
  - 数据结构放在 `Models/`（SwiftData 实体放在 `Models/SwiftData/`）。
  - 业务管理器放在 `Managers/` 按子领域拆分（Core / Health / Logging / PDF / Report / Study / Plan / Plant / Utility / Widget / Achievement / Audio / LLM）。
  - **Repository 协议 + 实现放在 `Repositories/Protocols/` + `Repositories/`，底层依托 `PersistenceExecutor` 提供的 Predicate-backed fetch 查询引擎，由 `RepositoryContainer` 聚合（16 个 Repository + 3 个跨域编排子模块 `BulkOperationOrchestrator` / `TodoAggregator` / `PhaseFilterRefresher`）**。
  - **纯函数服务放在 `Services/`**。
  - **ViewModel 放在 `ViewModels/`**。
  - Settings 相关子页放在 `Views/Settings/`（ThemeShop 子页放在 `Views/Settings/ThemeShop/`）。
  - 小组件相关 `*WidgetData` / `*WidgetSyncManager` 放在 `StudyPulse/Managers/Widget/`。
  - 小组件本体放在 `StudyPulseWidget/`。
  - 本地 / Vendored 包放在 `Packages/` 下。
  - 跨进程 / Siri 桥接放在 `Intents/`（`IntentAction` / `IntentActionStore` / `StudyPulseShortcuts`）。
  - 通知调度放在 `NotificationsControl/` + `Managers/Study/`。
  - **LLM 相关**：`Managers/LLM/` 基类 + 6 caller-specific 文件（`MistakeAIAnalysisLLM` / `BodyRadarLLM` / `HomeAskLLM` / `AIQuizLLM` / `AISimilarQuestionLLM` / `AIDiscussionLLM`）+ `AutoMindMapLLM` + `LLMResponseCache` + `LLMConfig` / `LLMError` / `LLMPrompt` / `LLMRequestBuilder` / `LLMResponseParser` / `LLMClient` / `HomeAskDataProvider`；UI 在 `Views/LLM/`（`LLMSettingsView` / `LLMChatView` / `AIDiscussionSheet` / `MistakeAIAnalysisSheet` / `HomeAskSheet` / `ChatBubble` / `ChatInputBar` / `LLMDebugSheet` / `AIWaitingView`）+ `Views/Mistake/LLM/`（AIQuiz 三件套 + `AISimilarQuestionFlowView`）+ `Views/Mistake/AutoMindMapView.swift` + `Views/Mistake/MistakeDebateSheet.swift`。
  - **Audio 相关**：`Managers/Audio/{AudioStorage, VoiceMemoManager}.swift` + 录音 / 播放 sheet 放在所属业务视图子目录（`Views/Mistake/Audio/`）。
  - **Diary 相关**：`Models/DataModels.swift` 中的 `DiaryEntry` + `Repositories/Protocols/DiaryRepository.swift` + `Views/Diary/` + `Managers/Study/DiaryReminderNotifications.swift` + `Views/Settings/DiarySettingsView.swift` + `Views/Home/HomeCards/DiaryHomeCard.swift`。
  - **Routines 相关**：`Models/DataModels.swift` 中的 `Routine` / `RoutineInstance` / `RoutineType` + `Repositories/Protocols/RoutineRepository.swift` + `Repositories/Protocols/RoutineInstanceRepository.swift` + `Managers/Plan/{RoutineSpawner, RoutineLiveActivityController}.swift` + `Views/Todo/RoutineEditorSheet.swift`。
  - **Plant 相关**：`Models/PlantState.swift` + `Models/PlantStateRecord.swift` + `Managers/Plant/{PlantManager, PetalColorCatalog}.swift` + `Views/Plant/` + `Views/Home/HomeCards/PlantHomeCard.swift`。
  - **ThemeShop 相关**：`Models/ThemeShop.swift` + `Views/Settings/ThemeShop/{ThemeShopView, CardSkinRenderer}.swift`。
  - **Time Investment 相关**：`Models/TimeInvestment.swift` + `Models/SwiftData/` 的 `TimeInvestmentSubjectRecord` / `SubTaskRecord` / `GoalRewardRecord` + `Repositories/Protocols/TimeInvestmentRepository.swift` + `Repositories/Protocols/StudySessionRepository.swift`（会话绑定 `InvestmentTarget`）+ `Services/TimeInvestmentEngine.swift` + `ViewModels/TimeInvestmentViewModel.swift` + `Views/TimeInvestment/`。
  - **Backup 相关**：`Managers/Backup/`（`BackupExporter` / `BackupImporter` / `BackupManifest` / `BackupValidator` / `BackupRestoreCoordinator` 等）+ `ViewModels/BackupRestoreViewModel.swift` + `Views/Settings/BackupRestoreView.swift`。
  - **HabitInsight 相关**：`Models/HabitInsight.swift` + `Managers/Study/HabitInsightNotifications.swift` + `Views/Home/HomeCards/HabitInsightCard.swift`。
  - **测试**：`StudyPulseTests/` 目标，`Infrastructure/`（`TestDataFixtures` + `TestModelContainerFactory` + `TestRepositoryContainerFactory`）+ `TestDoubles/`（Mock Repository）+ Services / Algorithm 单元测试（`DailyPlanEngineTests` / `DateFormattersTests` / `DifficultyTagTests` / `ExamFilterTests` / `MistakeFilterTests` / `PlantStageTransitionsTests` / `QuoteProviderTests` / `RecoveryLevelTests` / `RepositoryContainerTests` / `SubjectAggregatorTests` / `SuggestionEngineTests` / `TimeInvestmentEngineTests` / `SwiftDataMigrationTests`）。新功能涉及纯函数逻辑时应同步加测例。
- 使用 `nonisolated value-type` 模型：新 Codable 模型必须 `nonisolated` + `Sendable` + `Hashable`，以便跨 actor 传递。
- **新增 / 修改 `@Model` 字段必须同步更新 `toSnapshot()` / `init(from:)` + `ModelContainerFactory` 迁移工具 + 版本化 schema（`StudyPulseSchemaV1`–`V4` + `StudyPulseMigrationPlan` stages + `ModelContainerFactory.modelTypes`）**，否则旧数据迁移后会丢字段或新表不可见。
- **新增 / 修改 `StudyPhase` 字段必须同步更新 `StudyPhase` struct 的 `init(from:)`（用 `decodeIfPresent` 给默认值）+ `StudyPhaseRecord.toSnapshot()` / `init(from:)` + `PhaseRepository` 双向映射**。
- **新增非 optional 字段到 `Codable` struct 持久化在 UserDefaults 时，必须手写 `init(from:)` + `CodingKeys`，用 `decodeIfPresent` 给默认值**。
- 本地化所有用户可见字符串：永远不要在源码中直接写英语文本，新文案必须同步添加到 en / zh-Hans / zh-Hant / ja / ko 五份 `Localizable.strings` 文件（主应用与 `StudyPulseWidget` 各一份，共 10 份）。小组件扩展内复制的 `String.localized()` 扩展需同步维护。**必须 `Text("foo".localized())` 带括号**。
- 持久化图像作为文件而非 JSON 内联：使用 `profileRepo.saveAvatar` / `gradeRepo` 内部图片保存。
- 优先使用 `iPadLayout` 辅助而不是在视图里内联写 size class 分支。
- 不要手工修改 `StudyPulse.xcodeproj/project.pbxproj` —— 让 Xcode 管理。**Xcode 16+ 使用 `PBXFileSystemSynchronizedRootGroup` 自动收录 `StudyPulse/` 下的新 `.swift` 文件**。新增 Swift 文件后在 Xcode 中 Add Files to StudyPulse... / 拖入项目即可。
- 涉及新功能 / 新增配置时同步检查 `docs/algorithms/AlgorithmIntroduction.md` / `docs/algorithms/ScorePredictionAlgorithm.md` / `docs/plans/STREAK_ACHIEVEMENT_PLAN.md` / `docs/product/SPEC.md` / `docs/product/DESIGN.md` / `README.md` 是否需要更新：
  - 修改 `StudyReadinessAlgorithm` 评分规则必须同步更新 `docs/algorithms/AlgorithmIntroduction.md`。
  - 修改 `ScorePredictionEngine` / `MistakeGapAnalyzer` / `ScorePredictorFactory` 必须同步更新 `docs/algorithms/ScorePredictionAlgorithm.md`。
  - 修改「每日目标 / 连续天数 / 成就」规则必须同步更新 `docs/plans/STREAK_ACHIEVEMENT_PLAN.md`。
  - 修改 phase / 主色 / glass / 背景图 / 热力图 / 错题 SRS / 考试清单 / Repository 等架构性规则时同步更新 `AGENTS.md` / `docs/product/SPEC.md` / `README.md`。
- 写入 widget 前确认 `container.isReady == true`，避免在主数据加载完成前写入空数据。
- 启动 Live Activity 前检查 `Activity<StudyTimerActivityAttributes>.activities` 避免重复；更新 / 结束 Activity 需在主线程调用 `ActivityKit` API。
- `AchievementManager.record*()` 是事件入口：业务逻辑层不要直接修改 `AchievementsSnapshot`，统一通过 `record*()` 触发。
- 任何用 `Log.xxx.info(...)` 的文件必须 `import os`。
- **双实例陷阱自检**：所有 ViewModel 走 `container.xxxRepo.xxx` 路径访问，App 入口持有同一个 `RepositoryContainer` 单例；如果发现 ViewModel 用 `DataManager.shared` 而 App 用的是 `RepositoryContainer()`，**这就是 bug 信号**。
- **Phase 3 巨型文件拆分原则（2026-07-14 已完成 7 个文件）**：当 orchestrator 文件超过 800 行时按 caller / 子模块拆为独立 subview 文件，每个 subview **必须**带 `#Preview { ... }` 入口，否则就是物理搬运；已拆分的文件：
  - `RepositoryContainer`（577→457 + 3 sub-files：`BulkOperationOrchestrator` / `TodoAggregator` / `PhaseFilterRefresher`）。
  - `LLMRequestBuilder`（1137→233 + 6 sub-files：`MistakeAIAnalysisLLM` / `BodyRadarLLM` / `HomeAskLLM` / `AIQuizLLM` / `AISimilarQuestionLLM` / `AIDiscussionLLM`）。
  - `MistakeView`（930→374 + 3 sub-files：`MistakeListCellViews` / `DueReviewBanner` / `SubjectMistakesView`）。
  - `MistakeSetDetailView`（555→408 + 2 sub-files：`MistakeSetHeaderSection` / `MistakeSetContentSection`）。
  - `HRVStatusCard`（951→590 + 3 sub-files：`BodyRadarValues` / `BodyRadarChart` / `FitnessRingView`）。
  - `ExamCalendarView`（1008→674 + 3 sub-files：`ExamCalendarModels` / `ExamCalendarDayCell` / `ExamCalendarItemRow`）。
  - `ExamDetailView`（885→639 + 4 sub-files：`ChecklistRowView` / `RelatedMistakeCard` / `ReviewSectionRow` / `LinkedMistakesListView`）。
  - 后续再遇到 800+ 行单文件应继续按此模式拆分；拆分时保持 orchestrator facade 方法签名零修改，避免波及调用方。
- **`ExamView.body` / `TodoView.body` 链式修饰器过多**（5+ sheet + 3 destination + toolbar + 5+ onChange）会触发类型推导超时，需抽成独立 `ViewModifier`（`ExamViewSheetsAndDestinations` / `TodoViewSheetsAndDestinations`）。
- git暂存大概率会被沙箱拦截：权限只允许读取 `.git`，无法创建 `index.lock`。需要申请一次 Git 写权限来完成暂存和提交。

## 19. 八荣八耻
以臆猜接口为耻，以查档求证为荣
以模糊开工为耻，以对齐需求为荣
以脑补业务为耻，以请示规则为荣
以新增冗余为耻，以复用存量为荣
以省略校验为耻，以完备测例为荣
以乱改架构为耻，以恪守规范为荣
以不懂装懂为耻，以坦诚存疑为荣
以批量乱改为耻，以分步迭代为荣
