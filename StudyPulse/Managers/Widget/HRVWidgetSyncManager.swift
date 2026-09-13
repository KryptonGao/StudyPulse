//
//  HRVWidgetSyncManager.swift
//  StudyPulse
//
//  Syncs HRV readiness data to Widget App Group
//

import Foundation
import WidgetKit
import os

@MainActor
enum HRVWidgetSyncManager {
    /// 把 HealthKitManager 的 HRV 准备度数据写入 widget 共享容器并触发刷新。
    /// Write the HealthKitManager's HRV readiness data to the widget shared
    /// container and trigger a widget refresh.
    static func syncHRV(from manager: HealthKitManager) {
        Log.widget.info("开始同步 HRV widget / Syncing HRV widget: enabled=\(manager.hrvEnabled, privacy: .public) onboarded=\(manager.hrvOnboardingCompleted, privacy: .public) category=\(manager.readiness.category.rawValue, privacy: .public)")
        guard manager.hrvEnabled && manager.hrvOnboardingCompleted else {
            // 未启用 / 未完成引导时写入"无授权"占位,widget 走空态
            // If HRV is disabled or onboarding incomplete, write a "noAuthorization"
            // placeholder so the widget can render an empty state.
            HRVWidgetDataStore.save(data: HRVWidgetData(
                todayHRV: nil,
                baselineMean: nil,
                zScore: nil,
                category: "noAuthorization",
                suggestion: "",
                dailyHistory: []
            ))
            Log.widget.debug("HRV widget 写入空数据：未启用或未完成引导 / HRV widget wrote empty payload: not enabled or onboarding incomplete")
            return
        }

        let readiness = manager.readiness
        let history = manager.dailyHRVHistory.map {
            HRVDailyPoint(date: $0.date, value: $0.value)
        }

        let data = HRVWidgetData(
            todayHRV: readiness.todayHRV,
            baselineMean: readiness.baselineMean,
            zScore: readiness.zScore,
            category: readiness.category.rawValue,
            suggestion: readiness.suggestion,
            dailyHistory: history
        )

        HRVWidgetDataStore.save(data: data)
        WidgetCenter.shared.reloadTimelines(ofKind: "HRVWidget")
        Log.widget.info("HRV widget 同步完成 / HRV widget sync done: history=\(history.count, privacy: .public) hasToday=\(readiness.todayHRV != nil, privacy: .public) hasZ=\(readiness.zScore != nil, privacy: .public)")
    }
}
