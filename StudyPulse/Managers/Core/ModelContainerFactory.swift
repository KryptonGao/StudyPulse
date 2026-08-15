//
//  ModelContainerFactory.swift
//  StudyPulse
//
//  SwiftData ModelContainer 单例工厂。
//  SwiftData ModelContainer factory singleton.
//
//  - 提供一个共享 ModelContainer（在 StudyPulseApp 启动时初始化）
//  - 提供 Migration 工具：从旧版 ~/Documents/*.json 读取并写入 SwiftData
//  - 通过 UserDefaults flag 记录迁移状态，避免重复执行
//

import Foundation
import SwiftData
import os

/// SwiftData 容器配置 + 自动迁移工具
/// SwiftData container configuration + auto-migration helper.
@MainActor
enum ModelContainerFactory {

    /// Models in the current production schema. Kept for debug/test helpers.
    static var modelTypes: [any PersistentModel.Type] {
        StudyPulseSchemaV5.models
    }

    static var currentSchema: Schema {
        Schema(versionedSchema: StudyPulseSchemaV5.self)
    }

    enum StoreError: LocalizedError {
        case applicationSupportUnavailable(String)
        case openFailed(storeURL: URL, reason: String)
        case backupFailed(reason: String)
        case recoveryFailed(backupURL: URL?, reason: String)

        var errorDescription: String? {
            switch self {
            case .applicationSupportUnavailable(let reason):
                return "无法定位应用数据目录：\(reason)"
            case .openFailed(_, let reason):
                return "学习数据库无法打开或迁移：\(reason)"
            case .backupFailed(let reason):
                return "无法安全备份原数据库：\(reason)"
            case .recoveryFailed(_, let reason):
                return "创建恢复数据库失败：\(reason)"
            }
        }

        var storeURL: URL? {
            if case .openFailed(let url, _) = self { return url }
            return nil
        }
    }

    struct DisasterRecoveryResult {
        let container: ModelContainer
        let backupURL: URL?
    }

    /// Opens the current schema with the explicit migration plan.
    ///
    /// A normal launch never moves, deletes, or replaces the existing store.
    /// Failure is surfaced to the launch UI so the user can decide what to do.
    static func makeContainer() throws -> ModelContainer {
        if let cached = _sharedContainer { return cached }

        let storeURL = try persistentStoreURL()
        do {
            let container = try openPersistentContainer(at: storeURL)
            _sharedContainer = container
            Log.data.info("ModelContainer 创建/迁移成功 / ModelContainer opened/migrated: \(storeURL.path, privacy: .public)")
            return container
        } catch {
            Log.data.fault("ModelContainer 打开或迁移失败；原 Store 保持不变 / Open or migration failed; original store preserved: \(error.localizedDescription, privacy: .public)")
            throw StoreError.openFailed(
                storeURL: storeURL,
                reason: error.localizedDescription
            )
        }
    }

    /// Explicit, user-confirmed last-resort recovery.
    ///
    /// The original store bundle is moved into a timestamped backup directory.
    /// If creating the replacement fails, all original files are restored.
    static func performDisasterRecovery() throws -> DisasterRecoveryResult {
        guard _sharedContainer == nil else {
            return DisasterRecoveryResult(container: _sharedContainer!, backupURL: nil)
        }

        let storeURL = try persistentStoreURL()
        let backup = try backupStoreBundle(at: storeURL)

        do {
            let container = try openPersistentContainer(at: storeURL)
            _sharedContainer = container
            Log.data.warning("用户确认灾难恢复；已创建新 Store / User-confirmed disaster recovery created a fresh store")
            return DisasterRecoveryResult(container: container, backupURL: backup?.directory)
        } catch {
            do {
                try restoreStoreBundle(backup, at: storeURL)
            } catch let restoreError {
                Log.data.fault("恢复原 Store 失败 / Failed to restore original store: \(restoreError.localizedDescription, privacy: .public)")
                throw StoreError.recoveryFailed(
                    backupURL: backup?.directory,
                    reason: "\(error.localizedDescription); restore: \(restoreError.localizedDescription)"
                )
            }
            throw StoreError.recoveryFailed(
                backupURL: backup?.directory,
                reason: error.localizedDescription
            )
        }
    }

    private static func persistentStoreURL() throws -> URL {
        do {
            return try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("studypulse.store")
        } catch {
            throw StoreError.applicationSupportUnavailable(error.localizedDescription)
        }
    }

    private static func openPersistentContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = currentSchema
        let config = ModelConfiguration(
            "StudyPulse",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: StudyPulseMigrationPlan.self,
            configurations: [config]
        )
    }

    struct StoreBackup {
        let directory: URL
        let fileNames: [String]
    }

    static func backupStoreBundle(at storeURL: URL) throws -> StoreBackup? {
        let fm = FileManager.default
        let storeDir = storeURL.deletingLastPathComponent()
        let baseName = storeURL.lastPathComponent
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: storeDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw StoreError.backupFailed(reason: error.localizedDescription)
        }

        let activeFiles = contents.filter {
            let name = $0.lastPathComponent
            return name == baseName
                || name.hasPrefix(baseName + "-")
                || name.hasPrefix(baseName + "_")
        }
        guard !activeFiles.isEmpty else { return nil }

        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let backupRoot = storeDir.appendingPathComponent(
            "StudyPulseStoreBackups",
            isDirectory: true
        )
        let backupDirectory = backupRoot.appendingPathComponent(
            "recovery-\(stamp)-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try fm.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw StoreError.backupFailed(reason: error.localizedDescription)
        }

        var movedNames: [String] = []
        do {
            for sourceURL in activeFiles {
                let name = sourceURL.lastPathComponent
                try fm.moveItem(
                    at: sourceURL,
                    to: backupDirectory.appendingPathComponent(name)
                )
                movedNames.append(name)
            }
        } catch {
            for name in movedNames.reversed() {
                try? fm.moveItem(
                    at: backupDirectory.appendingPathComponent(name),
                    to: storeDir.appendingPathComponent(name)
                )
            }
            throw StoreError.backupFailed(reason: error.localizedDescription)
        }

        Log.data.warning("原 Store 已备份用于灾难恢复 / Original store backed up: \(backupDirectory.path, privacy: .public)")
        return StoreBackup(directory: backupDirectory, fileNames: movedNames)
    }

    static func restoreStoreBundle(
        _ backup: StoreBackup?,
        at storeURL: URL
    ) throws {
        guard let backup else { return }

        let fm = FileManager.default
        let storeDir = storeURL.deletingLastPathComponent()
        let baseName = storeURL.lastPathComponent
        let contents = try fm.contentsOfDirectory(
            at: storeDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        // Preserve remnants of the failed replacement instead of deleting them.
        let failedDirectory = backup.directory.appendingPathComponent(
            "failed-replacement",
            isDirectory: true
        )
        try fm.createDirectory(at: failedDirectory, withIntermediateDirectories: true)
        for url in contents {
            let name = url.lastPathComponent
            guard name == baseName
                    || name.hasPrefix(baseName + "-")
                    || name.hasPrefix(baseName + "_")
            else { continue }
            do {
                try fm.moveItem(
                    at: url,
                    to: failedDirectory.appendingPathComponent(name)
                )
            } catch {
                throw StoreError.backupFailed(reason: error.localizedDescription)
            }
        }

        for name in backup.fileNames {
            try fm.moveItem(
                at: backup.directory.appendingPathComponent(name),
                to: storeDir.appendingPathComponent(name)
            )
        }
    }

    nonisolated(unsafe) private static var _sharedContainer: ModelContainer?

    // MARK: - Debug Helpers
    // MARK: - 调试辅助 / Debug helpers

    /// 返回各 @Model 实体的当前记录数（供 Debug → State & Cache 展示）
    /// Record count per registered @Model type, used by Debug → State & Cache.
    @MainActor
    static func entityCounts(context: ModelContext) -> [(name: String, count: Int)] {
        var results: [(name: String, count: Int)] = []
        for type in modelTypes {
            let count: Int
            do {
                count = try entityCount(for: type, in: context)
            } catch {
                Log.data.error("entityCounts 取数失败 / fetchCount failed for \(String(describing: type), privacy: .public): \(error.localizedDescription, privacy: .public)")
                count = -1
            }
            results.append((String(describing: type), count))
        }
        return results
    }

    /// 通用实体计数（通过类型分发到具体 PersistentModel 子类）
    /// Type-erased entity count dispatcher.
    private static func entityCount(for type: any PersistentModel.Type, in context: ModelContext) throws -> Int {
        switch type {
        case is SubjectRecord.Type:
            return try context.fetchCount(FetchDescriptor<SubjectRecord>())
        case is GradeRecord.Type:
            return try context.fetchCount(FetchDescriptor<GradeRecord>())
        case is MistakeNoteRecord.Type:
            return try context.fetchCount(FetchDescriptor<MistakeNoteRecord>())
        case is ExamRecord.Type:
            return try context.fetchCount(FetchDescriptor<ExamRecord>())
        case is ComprehensiveExamRecord.Type:
            return try context.fetchCount(FetchDescriptor<ComprehensiveExamRecord>())
        case is TaskItemRecord.Type:
            return try context.fetchCount(FetchDescriptor<TaskItemRecord>())
        case is UserProfileRecord.Type:
            return try context.fetchCount(FetchDescriptor<UserProfileRecord>())
        case is StudyPhaseRecord.Type:
            return try context.fetchCount(FetchDescriptor<StudyPhaseRecord>())
        case is PlantStateRecord.Type:
            return try context.fetchCount(FetchDescriptor<PlantStateRecord>())
        case is RoutineRecord.Type:
            return try context.fetchCount(FetchDescriptor<RoutineRecord>())
        case is RoutineInstanceRecord.Type:
            return try context.fetchCount(FetchDescriptor<RoutineInstanceRecord>())
        case is DiaryEntryRecord.Type:
            return try context.fetchCount(FetchDescriptor<DiaryEntryRecord>())
        case is CoachGoalRecord.Type:
            return try context.fetchCount(FetchDescriptor<CoachGoalRecord>())
        case is CoachAnalysisRecord.Type:
            return try context.fetchCount(FetchDescriptor<CoachAnalysisRecord>())
        case is CoachProposalRecord.Type:
            return try context.fetchCount(FetchDescriptor<CoachProposalRecord>())
        case is CoachConversationMessageRecord.Type:
            return try context.fetchCount(FetchDescriptor<CoachConversationMessageRecord>())
        case is CoachChatRecord.Type:
            return try context.fetchCount(FetchDescriptor<CoachChatRecord>())
        case is StudySessionRecord.Type:
            return try context.fetchCount(FetchDescriptor<StudySessionRecord>())
        case is TimeInvestmentSubjectRecord.Type:
            return try context.fetchCount(FetchDescriptor<TimeInvestmentSubjectRecord>())
        case is SubTaskRecord.Type:
            return try context.fetchCount(FetchDescriptor<SubTaskRecord>())
        case is GoalRewardRecord.Type:
            return try context.fetchCount(FetchDescriptor<GoalRewardRecord>())
        case is ExamAutopsyRecord.Type:
            return try context.fetchCount(FetchDescriptor<ExamAutopsyRecord>())
        case is ExamSimulationRecord.Type:
            return try context.fetchCount(FetchDescriptor<ExamSimulationRecord>())
        case is ExamGoalRecord.Type:
            return try context.fetchCount(FetchDescriptor<ExamGoalRecord>())
        case is ExamPlanRecord.Type:
            return try context.fetchCount(FetchDescriptor<ExamPlanRecord>())
        case is StudyPulseSchemaMetadataRecord.Type:
            return try context.fetchCount(FetchDescriptor<StudyPulseSchemaMetadataRecord>())
        default:
            // 兜底：返回 -1 提示未实现
            return -1
        }
    }

    // MARK: - Migration
    // MARK: - 数据迁移 / Migration

    /// 是否已经完成 JSON → SwiftData 迁移
    /// Whether the JSON → SwiftData migration has finished.
    static let migrationDoneKey = "didMigrateToSwiftData_v1"

    /// 是否已经为首次启动准备好 PlantStateRecord
    /// Whether an initial PlantStateRecord has been seeded.
    static let plantSeedDoneKey = "didSeedPlantState_v1"

    /// 检查是否需要从 JSON 迁移
    /// Check if migration from JSON is needed.
    static var needsJSONMigration: Bool {
        !UserDefaults.standard.bool(forKey: migrationDoneKey)
    }

    /// 从旧版 ~/Documents/*.json 迁移到 SwiftData。
    /// Migrate legacy ~/Documents/*.json to SwiftData.
    ///
    /// 策略：
    /// - 读取每个 JSON 文件（profile / grades / mistakes / exams / comprehensiveExams / tasks / subjects）
    /// - 全部插入到给定 ModelContext
    /// - 标记迁移完成（写 UserDefaults）
    /// - 旧 JSON 文件保留在原位（不删），避免误操作导致数据丢失
    ///
    /// Strategy:
    /// - Read each JSON file and decode into existing structs
    /// - Insert all as @Model entities
    /// - Mark migration as done (UserDefaults)
    /// - Old JSON files are kept (not deleted) to prevent accidental data loss
    @MainActor
    static func migrateFromJSONIfNeeded(context: ModelContext) {
        guard needsJSONMigration else { return }

        Log.data.info("开始 JSON → SwiftData 迁移 / Starting JSON → SwiftData migration")
        guard let docs = DataFileIO.getDocsDir() else {
            Log.data.error("JSON 迁移跳过(无法解析 Documents 目录) / Migration skipped: no Documents dir")
            return
        }

        var counts: [(String, Int)] = []

        // subjects / 学科
        if let subjects: [Subject] = DataFileIO.load(url: docs.appendingPathComponent("subjects.json")) {
            for s in subjects {
                context.insert(SubjectRecord(from: s))
            }
            counts.append(("subjects", subjects.count))
        }

        // grades / 成绩
        if let grades: [Grade] = DataFileIO.load(url: docs.appendingPathComponent("grades.json")) {
            for g in grades {
                context.insert(GradeRecord(from: g))
            }
            counts.append(("grades", grades.count))
        }

        // mistakes / 错题
        if let mistakes: [MistakeNote] = DataFileIO.load(url: docs.appendingPathComponent("mistakes.json")) {
            for m in mistakes {
                context.insert(MistakeNoteRecord(from: m))
            }
            counts.append(("mistakes", mistakes.count))
        }

        // exams (single subject) / 考试 (单科)
        if let exams: [Exam] = DataFileIO.load(url: docs.appendingPathComponent("exams.json")) {
            for e in exams {
                context.insert(ExamRecord(from: e))
            }
            counts.append(("exams", exams.count))
        }

        // comprehensiveExams / 综合考试
        if let comps: [comprehensiveExam] = DataFileIO.load(url: docs.appendingPathComponent("comprehensiveExams.json")) {
            for e in comps {
                context.insert(ComprehensiveExamRecord(from: e))
            }
            counts.append(("comprehensiveExams", comps.count))
        }

        // tasks (homework / reading material) / 任务 (作业 / 阅读材料)
        if let tasks: [TaskItem] = DataFileIO.load(url: docs.appendingPathComponent("tasks.json")) {
            for t in tasks {
                context.insert(TaskItemRecord(from: t))
            }
            counts.append(("tasks", tasks.count))
        }

        // profile (单例) / profile (singleton)
        if let profile: UserProfile = DataFileIO.load(url: docs.appendingPathComponent("profile.json")) {
            context.insert(UserProfileRecord(from: profile))
            counts.append(("profile", 1))
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: migrationDoneKey)
            let summary = counts.map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
            Log.data.info("JSON → SwiftData 迁移完成 / Migration complete: \(summary, privacy: .public)")
            Log.record(.info, category: "Data", message: "JSON → SwiftData 迁移完成: \(summary)")
        } catch {
            Log.data.error("保存迁移数据失败 / Migration save failed: \(error.localizedDescription, privacy: .public)")
            Log.record(.error, category: "Data", message: "保存迁移数据失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Plant Seed
    // MARK: - Plant 播种 / Plant seed

    /// 首次启动时插入一条 seed PlantStateRecord。
    /// Idempotent: 通过 `plantSeedDoneKey` 跳过；已经存在 record 也跳过。
    /// Seed an initial PlantStateRecord on first launch. Idempotent.
    @MainActor
    static func migratePlantStateIfNeeded(context: ModelContext) {
        // 已经播种过就跳过
        // Already seeded → skip.
        if UserDefaults.standard.bool(forKey: plantSeedDoneKey) { return }

        // 已经存在 record 也跳过（覆盖安装或老 build 升级上来）
        // If a record already exists, skip too (re-install / upgrade from an older build).
        let descriptor = FetchDescriptor<PlantStateRecord>()
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            UserDefaults.standard.set(true, forKey: plantSeedDoneKey)
            return
        }

        let initial = PlantState(currentStage: .seed, lastUpdated: Date())
        let record = PlantStateRecord(from: initial, previousStage: .seed)
        context.insert(record)
        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: plantSeedDoneKey)
            Log.data.info("PlantState 首次播种完成 / Plant state seed complete: stage=seed")
        } catch {
            Log.data.error("PlantState 播种失败 / Plant state seed failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
