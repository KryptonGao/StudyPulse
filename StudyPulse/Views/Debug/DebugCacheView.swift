//
//  DebugCacheView.swift
//  StudyPulse
//
//  Debug → State & Cache：手动触发诊断 / 维护操作。
//  All destructive operations go through confirmation dialogs.
//

import SwiftUI
import SwiftData
import WidgetKit
import UserNotifications
import os

struct DebugCacheView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(HealthKitManager.self) private var hrvManager: HealthKitManager

    // Diagnostics snapshot
    @State private var entityCounts: [(name: String, count: Int)] = []
    @State private var isLoadingCounts: Bool = false
    @State private var lastRefresh: Date? = nil

    // Grade anomaly scan
    @State private var gradeAnomalies: [GradeAnomaly] = []
    @State private var isLoadingAnomalies: Bool = false
    @State private var lastAnomalyRefresh: Date? = nil

    // Pending action feedback
    @State private var statusMessage: String? = nil
    @State private var statusIsError: Bool = false

    // Confirmation dialogs
    @State private var pendingAction: PendingAction? = nil

    enum PendingAction: Identifiable {
        case clearLogs
        case clearImageCache
        case rerunMigration
        case resetPreferences
        case recomputeAchievements

        var id: String {
            switch self {
            case .clearLogs: return "clearLogs"
            case .clearImageCache: return "clearImageCache"
            case .rerunMigration: return "rerunMigration"
            case .resetPreferences: return "resetPreferences"
            case .recomputeAchievements: return "recomputeAchievements"
            }
        }
    }

    var body: some View {
        List {
            diagnosticsSection
            stateSection
            anomalyScanSection
            maintenanceSection
            dangerousSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("debug.stateAndCache".localized())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshEntityCounts()
            await refreshGradeAnomalies()
        }
        .refreshable {
            await refreshEntityCounts()
            await refreshGradeAnomalies()
        }
        .confirmationDialog(
            dialogTitle(for: pendingAction),
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Cancel".localized(), role: .cancel) { pendingAction = nil }
            Button("Confirm".localized(), role: .destructive) {
                if let action = pendingAction {
                    perform(action)
                }
                pendingAction = nil
            }
        } message: {
            Text(dialogMessage(for: pendingAction))
        }
        .alert(
            statusIsError ? "Error".localized() : "Done".localized(),
            isPresented: Binding(
                get: { statusMessage != nil },
                set: { if !$0 { statusMessage = nil } }
            )
        ) {
            Button("OK".localized()) { statusMessage = nil }
        } message: {
            if let msg = statusMessage {
                Text(msg)
            }
        }
    }

    // MARK: - Sections

    private var diagnosticsSection: some View {
        Section {
            if isLoadingCounts {
                HStack {
                    ProgressView()
                    Text("Loading…".localized())
                        .foregroundStyle(.secondary)
                }
            } else if entityCounts.isEmpty {
                Text("No data".localized())
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entityCounts, id: \.name) { item in
                    HStack {
                        Text(item.name)
                            .scaledFont(size: 13, design: .monospaced)
                        Spacer()
                        Text("\(item.count)")
                            .scaledFont(size: 14, weight: .semibold, design: .monospaced)
                            .foregroundStyle(item.count == -1 ? .red : .primary)
                    }
                }

                // 标签统计(从内存中的错题聚合)
                let allTags = container.mistakeRepo.allTags()
                HStack {
                    Text("Tags".localized())
                        .scaledFont(size: 13, design: .monospaced)
                    Spacer()
                    Text("\(allTags.count)")
                        .scaledFont(size: 14, weight: .semibold, design: .monospaced)
                        .foregroundStyle(.primary)
                }
            }

            HStack {
                Text("Active Phase".localized())
                Spacer()
                Text(container.envManager.activePhaseId?.uuidString.prefix(8).description ?? "all")
                    .scaledFont(size: 12, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Glass Effect".localized())
                Spacer()
                Text(container.envManager.glassEffectEnabled ? "ON" : "OFF")
                    .scaledFont(size: 12, design: .monospaced)
                    .foregroundStyle(container.envManager.glassEffectEnabled ? .green : .secondary)
            }
            HStack {
                Text("Accent".localized())
                Spacer()
                Text(container.envManager.effectiveAccent.rawValue)
                    .scaledFont(size: 12, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("debug.entityCounts".localized())
                Spacer()
                Button {
                    Task { await refreshEntityCounts() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }
        } footer: {
            if let last = lastRefresh {
                Text("Updated \(last.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
            }
        }
    }

    private var stateSection: some View {
        Section {
            Button {
                runAction(.recomputeAchievements)
            } label: {
                Label("debug.recomputeAchievements".localized(), systemImage: "arrow.triangle.2.circlepath")
            }
            .foregroundStyle(.blue)

            Button {
                Task { await forceWidgetReload() }
            } label: {
                Label("debug.forceWidgetReload".localized(), systemImage: "rectangle.3.group")
            }
            .foregroundStyle(.blue)

            Button {
                Task { await rescheduleNotifications() }
            } label: {
                Label("debug.rescheduleNotifications".localized(), systemImage: "bell.badge")
            }
            .foregroundStyle(.blue)

            Button {
                Task { await resetHealthKitBootstrap() }
            } label: {
                Label("Reset HealthKit Bootstrap".localized(), systemImage: "heart.text.square")
            }
            .foregroundStyle(.blue)
        } header: {
            Text("Quick Actions".localized())
        } footer: {
            Text("These actions are non-destructive and can be undone by app behavior.".localized())
                .font(.caption2)
        }
    }

    /// 成绩异常扫描:列出明显不在合理范围内的成绩(score 越界 / 重复日期 / 0 分等),
    /// 方便用户清掉脏数据。Debug 专用,不做任何写操作。
    @ViewBuilder
    private var anomalyScanSection: some View {
        Section {
            if isLoadingAnomalies {
                HStack {
                    ProgressView()
                    Text("Scanning…".localized())
                        .foregroundStyle(.secondary)
                }
            } else if gradeAnomalies.isEmpty {
                Label("No anomalies found.".localized(), systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(gradeAnomalies) { anomaly in
                    anomalyRow(anomaly)
                }
            }
        } header: {
            HStack {
                Text("Grade Anomalies".localized())
                Spacer()
                Button {
                    Task { await refreshGradeAnomalies() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }
        } footer: {
            if let last = lastAnomalyRefresh {
                Text("Updated \(last.formatted(date: .omitted, time: .standard)) · 不会自动修复,仅列出供手动清理。")
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder
    private func anomalyRow(_ a: GradeAnomaly) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: a.severity.iconName)
                .foregroundStyle(a.severity.tint)
                .font(.caption)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title)
                    .scaledFont(size: 13, weight: .semibold, design: .rounded)
                Text(a.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var maintenanceSection: some View {
        Section {
            Button {
                pendingAction = .clearLogs
            } label: {
                Label("debug.clearLogs".localized(), systemImage: "trash")
            }
            .foregroundStyle(.orange)

            Button {
                pendingAction = .clearImageCache
            } label: {
                Label("Clear Image Cache".localized(), systemImage: "photo.on.rectangle.angled")
            }
            .foregroundStyle(.orange)

            Button {
                pendingAction = .rerunMigration
            } label: {
                Label("Re-run JSON Migration".localized(), systemImage: "arrow.triangle.merge")
            }
            .foregroundStyle(.orange)
        } header: {
            Text("Cache Maintenance".localized())
        } footer: {
            Text("These actions clear cached data. The app will rebuild the cache on next use.".localized())
                .font(.caption2)
        }
    }

    private var dangerousSection: some View {
        Section {
            Button {
                pendingAction = .resetPreferences
            } label: {
                Label("Reset AppPreferences".localized(), systemImage: "exclamationmark.triangle")
            }
            .foregroundStyle(.red)
        } header: {
            Text("Danger Zone".localized())
        } footer: {
            Text("Resetting preferences will clear all your settings: language, theme, accent, glass effect, active phase, etc.".localized())
                .font(.caption2)
        }
    }

    // MARK: - Actions

    private enum DebugAction {
        case recomputeAchievements
        case forceWidgetReload
        case rescheduleNotifications
        case resetHealthKitBootstrap
        case clearLogs
        case clearImageCache
        case rerunMigration
        case resetPreferences
    }

    private func runAction(_ action: DebugAction) {
        switch action {
        case .recomputeAchievements:
            pendingAction = .recomputeAchievements
        case .forceWidgetReload:
            Task { await forceWidgetReload() }
        case .rescheduleNotifications:
            Task { await rescheduleNotifications() }
        case .resetHealthKitBootstrap:
            Task { await resetHealthKitBootstrap() }
        case .clearLogs:
            pendingAction = .clearLogs
        case .clearImageCache:
            pendingAction = .clearImageCache
        case .rerunMigration:
            pendingAction = .rerunMigration
        case .resetPreferences:
            pendingAction = .resetPreferences
        }
    }

    private func perform(_ action: PendingAction) {
        switch action {
        case .clearLogs:
            Task { await LogStore.shared.clear() }
            statusMessage = "In-memory logs cleared.".localized()
            statusIsError = false
        case .clearImageCache:
            ImageCache.shared.clear()
            statusMessage = "Image cache cleared.".localized()
            statusIsError = false
        case .rerunMigration:
            // Force-rerun migration by clearing flag, then re-running
            UserDefaults.standard.set(false, forKey: ModelContainerFactory.migrationDoneKey)
            if let container = container.modelContainer {
                ModelContainerFactory.migrateFromJSONIfNeeded(context: container.mainContext)
                statusMessage = "Migration re-run complete. Restart the app if needed.".localized()
            } else {
                statusMessage = "ModelContainer not ready.".localized()
                statusIsError = true
            }
            statusIsError = !((statusIsError == false))
        case .resetPreferences:
            container.envManager.preferences = AppPreferences()
            statusMessage = "App preferences have been reset.".localized()
            statusIsError = false
        case .recomputeAchievements:
            AchievementManager.shared.handleDayRolloverIfNeeded()
            statusMessage = "Achievement recompute triggered.".localized()
            statusIsError = false
        }
    }

    // MARK: - Async Actions

    @MainActor
    private func refreshEntityCounts() async {
        isLoadingCounts = true
        defer {
            isLoadingCounts = false
            lastRefresh = Date()
        }
        guard let mc = container.modelContainer else {
            entityCounts = []
            return
        }
        entityCounts = ModelContainerFactory.entityCounts(context: mc.mainContext)
    }

    @MainActor
    private func forceWidgetReload() async {
        WidgetCenter.shared.reloadAllTimelines()
        WidgetDataSyncManager.syncUpcomingExams(
            examSets: container.examRepo.examSets,
            comprehensiveExamSets: container.examRepo.comprehensiveExamSets
        )
        TrendWidgetSyncManager.syncTrend(
            grades: container.gradeRepo.grades,
            subjects: container.subjectRepo.subjects
        )
        HRVWidgetSyncManager.syncHRV(from: hrvManager)
        statusMessage = "Widgets reloaded.".localized()
        statusIsError = false
    }

    @MainActor
    private func rescheduleNotifications() async {
        SRSReviewNotifications.shared.rescheduleAll(mistakes: container.mistakeRepo.mistakeSets)
        DailyGoalReminder.shared.reschedule(
            for: Date(),
            config: AchievementManager.shared.snapshot.config
        )
        for exam in container.examRepo.examSets {
            ExamPrepareNotifications.shared.scheduleNotifications(
                for: exam.examName,
                date: exam.examDate,
                days: exam.countdownNotifyDays
            )
        }
        statusMessage = "All notifications rescheduled.".localized()
        statusIsError = false
    }

    @MainActor
    private func resetHealthKitBootstrap() async {
        await hrvManager.bootstrap()
        statusMessage = "HealthKit bootstrap re-run.".localized()
        statusIsError = false
    }

    /// 扫描所有成绩中的异常条目(score 越界 / 重复日期 / 0 分)。
    /// Debug 专用,只读不写。
    @MainActor
    private func refreshGradeAnomalies() async {
        isLoadingAnomalies = true
        defer {
            isLoadingAnomalies = false
            lastAnomalyRefresh = Date()
        }
        let grades = container.gradeRepo.filteredGrades
        var anomalies: [GradeAnomaly] = []

        // 1) score < 0 或 > fullScore(若 record 自带 fullScore 则用它,否则用科目默认)
        for g in grades {
            let recordFull = g.fullScore
            let subjectFull = container.fullScore(for: g.subject)
            let effectiveFull = recordFull ?? subjectFull
            if g.score < 0 {
                anomalies.append(.init(
                    severity: .error,
                    title: "\(g.subject) · 负分",
                    detail: String(
                        format: "score=%.1f (date=%@, examName=%@)",
                        g.score,
                        g.date.formatted(date: .abbreviated, time: .omitted),
                        g.examName.isEmpty ? "—" : g.examName
                    )
                ))
            } else if g.score > effectiveFull + 0.5 {
                anomalies.append(.init(
                    severity: .error,
                    title: "\(g.subject) · score 超过 fullScore",
                    detail: String(
                        format: "score=%.1f > fullScore=%.1f (date=%@, examName=%@)",
                        g.score, effectiveFull,
                        g.date.formatted(date: .abbreviated, time: .omitted),
                        g.examName.isEmpty ? "—" : g.examName
                    )
                ))
            } else if g.score == 0 {
                anomalies.append(.init(
                    severity: .warning,
                    title: "\(g.subject) · score=0",
                    detail: String(
                        format: "date=%@, examName=%@, ranking=%@",
                        g.date.formatted(date: .abbreviated, time: .omitted),
                        g.examName.isEmpty ? "—" : g.examName,
                        g.ranking.map(String.init) ?? "—"
                    )
                ))
            }
        }

        // 2) 同一科目在同一日期出现 >= 2 条(可能是重复导入 / 手抖录了两次)
        let grouped = Dictionary(grouping: grades) { g -> String in
            "\(g.subject)|\(g.date.formatted(date: .abbreviated, time: .omitted))"
        }
        for (key, items) in grouped where items.count >= 2 {
            let parts = key.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let subject = String(parts[0])
            let dateStr = String(parts[1])
            let scores = items.map { String(format: "%.1f", $0.score) }.joined(separator: ", ")
            anomalies.append(.init(
                severity: .warning,
                title: "\(subject) · 重复日期",
                detail: String(
                    format: "%@ 共有 %d 条记录: %@",
                    dateStr, items.count, scores
                )
            ))
        }

        // 按严重度 + 科目排序
        anomalies.sort { a, b in
            if a.severity != b.severity { return a.severity < b.severity }
            return a.title < b.title
        }

        gradeAnomalies = anomalies
    }

    // MARK: - Dialog Strings

    private func dialogTitle(for action: PendingAction?) -> String {
        guard let action else { return "" }
        switch action {
        case .clearLogs: return "debug.clearLogs".localized()
        case .clearImageCache: return "Clear Image Cache".localized()
        case .rerunMigration: return "Re-run JSON Migration".localized()
        case .resetPreferences: return "Reset AppPreferences".localized()
        case .recomputeAchievements: return "Recompute Achievements".localized()
        }
    }

    private func dialogMessage(for action: PendingAction?) -> String {
        guard let action else { return "" }
        switch action {
        case .clearLogs:
            return "debug.clearLogsConfirm".localized()
        case .clearImageCache:
            return "This drops all in-memory cached images. They will be re-decoded from disk on next use.".localized()
        case .rerunMigration:
            return "This will re-read any legacy JSON files in Documents and insert their content into SwiftData. Already-migrated records will be duplicated.".localized()
        case .resetPreferences:
            return "All your settings (language, theme, accent, glass effect, active phase) will be reset to defaults. This cannot be undone.".localized()
        case .recomputeAchievements:
            return "Force re-derive the streak and achievement snapshot from stored activity logs.".localized()
        }
    }
}

// MARK: - 成绩异常条目(Debug 专用)

/// 一条成绩异常的描述(Debug 视图用)。
/// A single grade anomaly entry shown in the Debug → State & Cache screen.
struct GradeAnomaly: Identifiable {
    enum Severity: Int, Comparable {
        case warning = 0
        case error = 1

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var iconName: String {
            switch self {
            case .warning: return "exclamationmark.triangle.fill"
            case .error:   return "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .warning: return Color(.systemOrange)
            case .error:   return Color(.systemRed)
            }
        }
    }

    let id = UUID()
    let severity: Severity
    let title: String
    let detail: String
}
