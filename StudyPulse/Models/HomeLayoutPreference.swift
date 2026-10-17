//
//  HomeLayoutPreference.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/6/20.
//

import Foundation

// MARK: - Home Card Type
// MARK: - 主页卡片类型 / Home Card Type

/// 主页可配置的板块卡片类型
/// Home page card types users can configure (order + enabled).
enum HomeCardType: String, CaseIterable, Codable {
    /// 今日 Top-3 计划卡(由 DailyPlanEngine 派生)
    /// Today's Top-3 plan card (derived by DailyPlanEngine).
    case dailyPlan = "dailyPlan"
    /// 状态不佳时自动压缩到三项可完成任务的计划卡。
    case minimalPlan = "minimalPlan"
    case hrvStatus = "hrvStatus"
    case unregisteredExamsReminder = "unregisteredExamsReminder"
    case flashcardReview = "flashcardReview"
    case memoryClimate = "memoryClimate"
    case streakProgress = "streakProgress"
    case quickActions = "quickActions"
    case studySuggestions = "studySuggestions"
    case trendChart = "trendChart"
    case upcomingExams = "upcomingExams"
    /// 考前状态预测卡片（默认关闭，用户可在主页布局设置中开启）。
    case examDayReadiness = "examDayReadiness"
    case studyTimer = "studyTimer"
    case dailyQuote = "dailyQuote"
    case recentGrades = "recentGrades"
    /// 90 天学习热力图（GitHub 风格活动格子图）
    /// 90-day learning heatmap (GitHub-style activity grid).
    case learningHeatmap = "learningHeatmap"
    /// 主页植物卡片（基于 streak / todayLog 的 Canvas 渲染）
    /// Home plant card (Canvas-rendered from streak / todayLog).
    case plant = "plant"
    /// AI 提问入口:点击后弹出"向 AI 提问" sheet,可讨论身体 / 成绩 / 趋势 / 复习
    /// AI Ask entry: opens an "Ask AI" sheet covering body / grades / trends / review.
    case homeAsk = "homeAsk"
    /// 学习日记 + 心情记录入口:点击 emoji cycle moodScore,点击其余区域打开 DiaryView sheet
    /// Study Diary + Mood entry: tap emoji cycles moodScore; tap the rest opens DiaryView sheet.
    case diary = "diary"
    case habitInsight = "habitInsight"
    case brainUsage = "brainUsage"
    /// 限时模拟考试行为分析入口。
    case examRoleSimulator = "examRoleSimulator"
    /// 考试倒推计划入口。
    case examReversePlanner = "examReversePlanner"
    /// 本周专注:7 日堆叠柱状图 + 目标线 + 与上周对比。
    case weeklyFocus = "weeklyFocus"
    /// 各科一览:得分率 + sparkline + 近期变化。
    case subjectSnapshot = "subjectSnapshot"
    /// 身心趋势:心情 / 睡眠 / HRV 14 天图表。
    case bodyMindTrend = "bodyMindTrend"

    /// 本地化显示名称
    var displayName: String {
        switch self {
        case .dailyPlan: return "Today's Top 3".localized()
        case .minimalPlan: return "Minimum Viable Plan".localized()
        case .studyTimer: return "Study Timer".localized()
        case .hrvStatus: return "HRV Readiness".localized()
        case .unregisteredExamsReminder: return "Exam Grade Reminder".localized()
        case .flashcardReview: return "Flashcard Review".localized()
        case .memoryClimate: return "memory.climate.title".localized()
        case .streakProgress: return "Streak Progress".localized()
        case .quickActions: return "Quick Actions".localized()
        case .studySuggestions: return "Study Suggestions".localized()
        case .trendChart: return "Trend Chart".localized()
        case .upcomingExams: return "Upcoming Exams".localized()
        case .examDayReadiness: return "examReadiness.title".localized()
        case .dailyQuote: return "Daily Quote".localized()
        case .recentGrades: return "Recent Grades".localized()
        case .learningHeatmap: return "Learning Heatmap".localized()
        case .plant: return "Plant".localized()
        case .homeAsk: return "Ask AI".localized()
        case .diary: return "Study Diary".localized()
        case .habitInsight: return "Habit Insight".localized()
        case .brainUsage: return "Brain Usage".localized()
        case .examRoleSimulator: return "考场人格模拟器".localized()
        case .examReversePlanner: return "exam.reverse.planner.title".localized()
        case .weeklyFocus: return "home.weeklyFocus.title".localized()
        case .subjectSnapshot: return "home.subjects.title".localized()
        case .bodyMindTrend: return "home.bodyMind.title".localized()
        }
    }

    /// SF Symbol 图标
    var icon: String {
        switch self {
        case .dailyPlan: return "sparkles"
        case .minimalPlan: return "checkmark.circle.fill"
        case .studyTimer: return "timer"
        case .hrvStatus: return "heart.text.square"
        case .unregisteredExamsReminder: return "exclamationmark.bubble.fill"
        case .flashcardReview: return "rectangle.stack.fill"
        case .memoryClimate: return "cloud.sun.rain.fill"
        case .quickActions: return "bolt.fill"
        case .studySuggestions: return "lightbulb.fill"
        case .streakProgress: return "flame.circle.fill"
        case .trendChart: return "chart.line.uptrend.xyaxis"
        case .upcomingExams: return "calendar.badge.exclamationmark"
        case .examDayReadiness: return "chart.line.uptrend.xyaxis.circle.fill"
        case .dailyQuote: return "quote.bubble.fill"
        case .recentGrades: return "list.bullet.rectangle"
        case .learningHeatmap: return "square.grid.4x3.fill"
        case .plant: return "leaf.fill"
        case .homeAsk: return "text.bubble.fill"
        case .diary: return "book.fill"
        case .habitInsight: return "waveform.path.ecg"
        case .brainUsage: return "brain.head.profile"
        case .examRoleSimulator: return "person.crop.circle.badge.questionmark"
        case .examReversePlanner: return "calendar.badge.clock"
        case .weeklyFocus: return "chart.bar.fill"
        case .subjectSnapshot: return "square.stack.3d.up.fill"
        case .bodyMindTrend: return "waveform.path.ecg"
        }
    }

    /// 是否需要全宽渲染（iPad 双列网格中要独占一整行）。
    /// 宽幅可视化卡片（如 90 天热力图、即将考试大卡）应标记为 true。
    var isFullWidth: Bool {
        switch self {
        case .learningHeatmap, .memoryClimate, .examRoleSimulator, .examReversePlanner, .habitInsight: return true
        default: return false
        }
    }
}

// MARK: - Home Card Item
// MARK: - 主页卡片项 / Home Card Item

/// 单个卡片配置项
/// A single card entry (type + enabled flag).
struct HomeCardItem: Identifiable, Codable, Equatable {
    var type: HomeCardType
    var enabled: Bool

    var id: String { type.rawValue }
}

// MARK: - Home Layout Preference
// MARK: - 主页布局偏好 / Home Layout Preference

/// 主页布局偏好：控制卡片的显示顺序和是否显示
/// Home layout preference: card order + enabled flags.
struct HomeLayoutPreference: Codable, Equatable {
    var items: [HomeCardItem]
    /// 动态排布:开启后无信息的卡片自动隐藏,顺序由 `HomeDynamicLayoutEngine` 按紧迫度决定,
    /// 用户手动排序被锁定;关闭后恢复 `items` 的自定义顺序。
    /// Dynamic layout: when on, cards without information are hidden and the order is decided by
    /// `HomeDynamicLayoutEngine` by urgency (manual ordering is locked); off restores `items` order.
    var dynamicLayoutEnabled: Bool = false

    init(items: [HomeCardItem], dynamicLayoutEnabled: Bool = false) {
        self.items = items
        self.dynamicLayoutEnabled = dynamicLayoutEnabled
    }

    enum CodingKeys: String, CodingKey {
        case items, dynamicLayoutEnabled
    }

    // 新字段用 decodeIfPresent 兼容旧 UserDefaults 数据 / decodeIfPresent keeps old stored data decodable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try c.decode([HomeCardItem].self, forKey: .items)
        self.dynamicLayoutEnabled = try c.decodeIfPresent(Bool.self, forKey: .dynamicLayoutEnabled) ?? false
    }

    /// 默认配置:新版主页五区固定排布,这里只决定各区内子模块的开关;
    /// 默认全部启用核心模块,诊断类 / 已收进详情页的卡片保持关闭。
    /// 已保存过布局的老用户不受影响(见 `load()`)。
    /// Default: the redesigned Home has five fixed zones, so this only decides which modules inside
    /// each zone are on. Core modules default to on; cards that moved into detail pages stay off.
    /// Users with a saved layout are unaffected (see `load()`).
    static let `default` = HomeLayoutPreference(items: [
        HomeCardItem(type: .dailyPlan, enabled: true),
        HomeCardItem(type: .minimalPlan, enabled: true),
        HomeCardItem(type: .streakProgress, enabled: true),
        HomeCardItem(type: .quickActions, enabled: true),
        HomeCardItem(type: .dailyQuote, enabled: true),
        HomeCardItem(type: .flashcardReview, enabled: true),
        HomeCardItem(type: .unregisteredExamsReminder, enabled: true),
        HomeCardItem(type: .upcomingExams, enabled: true),
        HomeCardItem(type: .examReversePlanner, enabled: true),
        HomeCardItem(type: .examRoleSimulator, enabled: true),
        HomeCardItem(type: .weeklyFocus, enabled: true),
        HomeCardItem(type: .subjectSnapshot, enabled: true),
        HomeCardItem(type: .recentGrades, enabled: true),
        HomeCardItem(type: .studySuggestions, enabled: true),
        HomeCardItem(type: .hrvStatus, enabled: true),
        HomeCardItem(type: .diary, enabled: true),
        HomeCardItem(type: .habitInsight, enabled: true),
        HomeCardItem(type: .plant, enabled: true),
        HomeCardItem(type: .learningHeatmap, enabled: true),
        HomeCardItem(type: .homeAsk, enabled: true),
        HomeCardItem(type: .trendChart, enabled: false),
        HomeCardItem(type: .bodyMindTrend, enabled: false),
        HomeCardItem(type: .studyTimer, enabled: false),
        HomeCardItem(type: .memoryClimate, enabled: false),
        HomeCardItem(type: .brainUsage, enabled: false),
        HomeCardItem(type: .examDayReadiness, enabled: false),
    ])

    /// 当前启用的卡片类型（按顺序）
    /// Currently enabled card types, in user order.
    var enabledTypes: [HomeCardType] {
        items.filter(\.enabled).map(\.type)
    }

    /// 检查某个卡片类型是否启用
    /// Whether a given card type is enabled.
    func isEnabled(_ type: HomeCardType) -> Bool {
        items.first(where: { $0.type == type })?.enabled ?? true
    }

    // MARK: - Persistence
    // MARK: - 持久化 / Persistence

    private static let userDefaultsKey = "homeLayoutPreference"

    /// 从 UserDefaults 加载
    /// Load from UserDefaults.
    static func load() -> HomeLayoutPreference {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(HomeLayoutPreference.self, from: data)
        else {
            return .default
        }
        // 兼容：已存类型集合与当前 HomeCardType 不一致（新增/删除卡片类型）时合并，
        // 保留用户的顺序与开关，新类型按默认位置插入。
        // Backwards-compat: when the stored type set differs from HomeCardType.allCases,
        // merge while preserving the user's order and toggles; new types are inserted at default positions.
        if Set(decoded.items.map(\.type)) != Set(HomeCardType.allCases) || decoded.items.count != HomeCardType.allCases.count {
            return mergeWithDefault(decoded)
        }
        return decoded
    }

    /// 保存到 UserDefaults
    /// Save to UserDefaults.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    /// 重置为默认配置
    /// Reset to default configuration.
    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    /// 合并已保存配置与默认配置：保留用户已有的顺序与开关，
    /// 新增类型插到默认列表中其前一个已存在类型之后（找不到则放最前）。
    /// Merge saved config with default: keep the user's order and toggles; insert each new type
    /// after its nearest preceding default neighbour that already exists (or at the front).
    static func mergeWithDefault(_ saved: HomeLayoutPreference) -> HomeLayoutPreference {
        var result: [HomeCardItem] = []
        var seen = Set<HomeCardType>()
        for item in saved.items where !seen.contains(item.type) {
            seen.insert(item.type)
            result.append(item)
        }
        let defaults = HomeLayoutPreference.default.items
        for (index, item) in defaults.enumerated() where !seen.contains(item.type) {
            var insertAt = 0
            for prev in defaults[..<index].reversed() {
                if let pos = result.firstIndex(where: { $0.type == prev.type }) {
                    insertAt = pos + 1
                    break
                }
            }
            result.insert(item, at: insertAt)
            seen.insert(item.type)
        }
        return HomeLayoutPreference(items: result, dynamicLayoutEnabled: saved.dynamicLayoutEnabled)
    }
}
