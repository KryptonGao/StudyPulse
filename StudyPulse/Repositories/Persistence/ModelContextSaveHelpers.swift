//
//  ModelContextSaveHelpers.swift
//  StudyPulse
//
//  SwiftData save helper: 显式错误处理 + 失败回滚,替代静默 try? save。
//

import Foundation
import SwiftData
import os

extension ModelContext {
    /// 持久化待写变更;失败时回滚未提交改动并记录 fault 日志。
    /// 返回 false 表示数据未落盘,调用方不得继续更新内存态。
    ///
    /// Saves pending changes; on failure rolls back uncommitted edits and
    /// logs a fault. A `false` return means nothing reached disk — callers
    /// must not apply their in-memory mutation.
    @discardableResult
    func saveOrRollback(_ label: String) -> Bool {
        do {
            try save()
            return true
        } catch {
            rollback()
            Log.data.fault("SwiftData save 失败已回滚 / Save failed, rolled back [\(label, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
            Log.record(.fault, category: "Data", message: "SwiftData save failed (rolled back) [\(label)]: \(error.localizedDescription)")
            return false
        }
    }
}
