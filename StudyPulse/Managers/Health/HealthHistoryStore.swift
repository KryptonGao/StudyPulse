//
//  HealthHistoryStore.swift
//  StudyPulse
//
//  Persists the past 60 days of `DailyHealthSnapshot` records to
//  ~/Documents/health_history.json. Used by `HealthKitManager` to
//  build the user's 30-day personal baseline for the readiness
//  algorithm.
//  把过去 60 天的 `DailyHealthSnapshot` 持久化到
//  ~/Documents/health_history.json。
//  由 `HealthKitManager` 用来构建 30 天个人基线,作为 readiness 算法的输入。
//

import Foundation
import os

/// 健康历史快照持久化。
/// Persistence for daily health snapshots.
enum HealthHistoryStore {
    nonisolated static let fileName = "health_history.json"
    /// Keep the file small; 60 days is more than enough for a stable
    /// 30-day baseline with room to spare.
    /// 文件保留窗口:60 天足以构建稳定的 30 天基线,且留有冗余。
    nonisolated static let retentionDays = 60

    /// 串行化 `upsert` 的 read-modify-write,避免并发刷新时各自 load 再 save
    /// 互相覆盖当日部分字段(如 restingHeartRate 与 sleepHours 分两次到达)。
    /// `load`/`save` 保持不锁,仅供同步调用方使用(H-12)。
    nonisolated private static let upsertQueue =
        DispatchQueue(label: "com.chenkai.gao.studypulse.health-history")

    // MARK: - File I/O
    // MARK: - 文件读写 / File I/O

    nonisolated static func fileURL() throws -> URL {
        let dir = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return dir.appendingPathComponent(fileName)
    }

    nonisolated static func load() -> [DailyHealthSnapshot] {
        guard let url = try? fileURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            Log.healthHistory.debug("健康历史文件不存在或读取失败 / Health history file missing or unreadable, returning empty")
            return []
        }
        do {
            let decoded = try JSONDecoder().decode(
                [DailyHealthSnapshot].self, from: data)
            Log.healthHistory.info("加载健康历史成功 / Loaded health history: count=\(decoded.count, privacy: .public) bytes=\(data.count, privacy: .public)")
            return decoded
        } catch {
            Log.healthHistory.error("健康历史解码失败 / Health history decode failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    nonisolated static func save(_ snapshots: [DailyHealthSnapshot]) {
        guard let url = try? fileURL() else {
            Log.healthHistory.error("健康历史保存失败：无法解析文件 URL / Health history save failed: cannot resolve file URL")
            return
        }
        // 先按保留窗口裁剪,再写盘;避免日志和实际写盘内容不一致。
        // Trim to the retention window before writing so logs match what hits disk.
        let trimmed = trimToRetention(snapshots)
        let dropped = snapshots.count - trimmed.count
        if dropped > 0 {
            Log.healthHistory.debug("健康历史已截断到保留窗口 / Health history trimmed to retention window: dropped=\(dropped, privacy: .public) kept=\(trimmed.count, privacy: .public)")
        }
        do {
            let data = try JSONEncoder().encode(trimmed)
            try data.write(to: url, options: .atomic)
            // 健康数据敏感:锁屏后不可读(best-effort 加固,失败不影响保存结果)
            // Health data is sensitive: complete protection after unlock only.
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path
            )
            Log.healthHistory.debug("保存健康历史成功 / Saved health history: count=\(trimmed.count, privacy: .public) bytes=\(data.count, privacy: .public)")
        } catch {
            Log.healthHistory.error("健康历史保存失败 / Health history save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Merge today's snapshot into the file (per-field fallback so
    /// partial updates don't clobber earlier readings) and return the
    /// post-write history.
    /// 把今日的快照合并进文件(按字段回退,部分更新不会覆盖早期读数),
    /// 并返回写盘后的完整历史。
    @discardableResult
    nonisolated static func upsert(snapshot: DailyHealthSnapshot) -> [DailyHealthSnapshot] {
        upsertQueue.sync {
            let existing = load()
            let cal = Calendar.current
            let day = cal.startOfDay(for: snapshot.date)
            let prior = existing.first {
                cal.startOfDay(for: $0.date) == day
            }
            let merged = DailyHealthSnapshot(
                date: day,
                hrv:               snapshot.hrv               ?? prior?.hrv,
                restingHeartRate:  snapshot.restingHeartRate  ?? prior?.restingHeartRate,
                respiratoryRate:   snapshot.respiratoryRate   ?? prior?.respiratoryRate,
                sleepHours:        snapshot.sleepHours        ?? prior?.sleepHours,
                deepSleepHours:    snapshot.deepSleepHours    ?? prior?.deepSleepHours,
                remSleepHours:     snapshot.remSleepHours     ?? prior?.remSleepHours,
                exerciseMinutes:   snapshot.exerciseMinutes   ?? prior?.exerciseMinutes
            )
            var updated = existing.filter {
                cal.startOfDay(for: $0.date) != day
            }
            updated.append(merged)
            save(updated)
            let filledFields: [String] = [
                snapshot.hrv.map { _ in "hrv" },
                snapshot.restingHeartRate.map { _ in "rhr" },
                snapshot.respiratoryRate.map { _ in "rr" },
                snapshot.sleepHours.map { _ in "sleep" },
                snapshot.deepSleepHours.map { _ in "deep" },
                snapshot.remSleepHours.map { _ in "rem" },
                snapshot.exerciseMinutes.map { _ in "exercise" }
            ].compactMap { $0 }
            Log.healthHistory.debug("健康历史 upsert 完成 / Health history upsert: date=\(day, privacy: .public) filled=\(filledFields.joined(separator: ","), privacy: .public) total=\(updated.count, privacy: .public)")
            return updated
        }
    }

    /// 按保留窗口裁剪,并按日期降序返回。
    /// Trim to the retention window and return in descending date order.
    nonisolated static func trimToRetention(_ snapshots: [DailyHealthSnapshot]) -> [DailyHealthSnapshot] {
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -retentionDays, to: Date()
        ) ?? Date()
        return snapshots
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }
    }
}
