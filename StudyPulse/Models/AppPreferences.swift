//
//  AppPreferences.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/6/5.
//

import Foundation
import SwiftUI

/// 一个可独立选择的 OpenAI-compatible LLM 供应商配置。
/// API Key 存储在 Keychain；`legacyAPIKey` 仅用于解码并迁移旧偏好。
nonisolated struct LLMProvider: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var baseURL: String
    var legacyAPIKey: String?
    var model: String
    var multimodalEnabled: Bool
    var thinkingEnabled: Bool
    /// `true` 表示该 provider 走 StudyPulse Cloud AI 网关（/v1/chat），而非 OpenAI 兼容端点。
    /// When `true`, the provider uses the StudyPulse Cloud AI gateway (/v1/chat)
    /// instead of an OpenAI-compatible endpoint.
    var isCloudProvider: Bool

    init(id: UUID = UUID(), name: String, baseURL: String = "", legacyAPIKey: String? = nil, model: String = "", multimodalEnabled: Bool = false, thinkingEnabled: Bool = false, isCloudProvider: Bool = false) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.legacyAPIKey = legacyAPIKey
        self.model = model
        self.multimodalEnabled = multimodalEnabled
        self.thinkingEnabled = thinkingEnabled
        self.isCloudProvider = isCloudProvider
    }

    /// StudyPulse Cloud AI 内测 provider 预设。
    /// Pre-configured Cloud AI beta provider.
    static func cloudBeta(workerURL: String) -> LLMProvider {
        LLMProvider(
            name: "StudyPulse Cloud (Beta)",
            baseURL: workerURL,
            model: "MiniMax-M3",
            multimodalEnabled: true,
            thinkingEnabled: false,
            isCloudProvider: true
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, model, multimodalEnabled, thinkingEnabled, isCloudProvider
        case legacyAPIKey = "apiKey"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        legacyAPIKey = try c.decodeIfPresent(String.self, forKey: .legacyAPIKey)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        multimodalEnabled = try c.decodeIfPresent(Bool.self, forKey: .multimodalEnabled) ?? false
        thinkingEnabled = try c.decodeIfPresent(Bool.self, forKey: .thinkingEnabled) ?? false
        isCloudProvider = try c.decodeIfPresent(Bool.self, forKey: .isCloudProvider) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(baseURL, forKey: .baseURL)
        try c.encode(model, forKey: .model)
        try c.encode(multimodalEnabled, forKey: .multimodalEnabled)
        try c.encode(thinkingEnabled, forKey: .thinkingEnabled)
        try c.encode(isCloudProvider, forKey: .isCloudProvider)
    }
}

// MARK: - App Preferences (应用偏好设置)

/// 应用内语言和主题偏好设置模型
/// 数据持久化于 UserDefaults，通过 AppEnvironmentManager 管理
nonisolated struct AppPreferences: Codable {
    /// 语言代码：nil 表示跟随系统
    /// 可选值："en", "zh-Hans", "zh-Hant", "ja", "ko"
    var appLanguage: String?
    /// 颜色主题选项
    var colorScheme: ColorSchemeOption = .system
    /// 成绩趋势图表显示类型（折线/柱状/饼图/散点/热力）
    var chartType: ChartType = .line
    /// 自定义主色预设（影响 AccentColor / 折线 / 进度条）
    /// nil = 跟随系统默认蓝色
    var accentPaletteId: String? = nil
    /// 是否在支持的卡片上启用 iOS 26 glassEffect（默认关闭）
    var glassEffectEnabled: Bool = false
    /// 是否在 Trends 页顶部显示 90 天学习热力图（默认开启）
    var learningHeatmapOnTrends: Bool = true
    /// 是否在 Trends 页显示科目掌握度雷达卡片（默认开启）
    var subjectMasteryRadarOnTrends: Bool = true
    /// 当前选中的 study phase id；nil = 全部数据视图（不过滤）
    /// Current active study phase id. nil = show all data (no filtering).
    var activePhaseId: UUID? = nil

    // MARK: - Theme Shop (主题 / 皮肤商店)

    /// 当前装备的卡片皮肤 id（nil = 使用系统默认 minimal_paper）。
    /// Equipped card skin id; nil = use system default (`minimal_paper`).
    var cardSkinId: String? = nil

    /// 当前装备的计时器动画 id（nil = 使用系统默认 aurora）。
    /// Equipped timer animation id; nil = use system default (`aurora`).
    var timerAnimationId: String? = nil

    // MARK: - Plant Card (主页植物卡片)

    /// 主页植物卡片总开关（默认开启）。关闭后 HomeView 隐藏 PlantHomeCard，
    /// 但 recordActivity 仍会执行（用于 reborn 判定 + Debug 追踪）。
    /// Master toggle for the Home plant card. When off, PlantHomeCard is hidden
    /// in HomeView; recordActivity() still fires so the reborn transition can
    /// trigger once the toggle is re-enabled.
    var plantCardEnabled: Bool = true

    /// 当前选中的花瓣颜色 id（nil = rose）。由 PetalColorCatalog.resolve 解析。
    /// Selected petal color id (nil = rose). Resolved via PetalColorCatalog.
    var plantPetalColorId: String? = nil

    // MARK: - Debug Mode (调试模式)

    /// Debug 模式总开关（默认关闭）。开启后顶部显示黄色 banner，FPS 浮窗、长按检视、Layout Bounds 等子开关才生效。
    /// Master switch for Debug mode. When on, a yellow banner shows at the top of every page,
    /// and the four sub-toggles below become active.
    var debugModeEnabled: Bool = false

    /// 子开关:开启后 LogStore 记录所有 .debug 级别（默认 .info 及以上）。
    /// Sub-toggle: capture .debug level entries in LogStore.
    var debugVerboseLogging: Bool = false

    /// 子开关:在所有主页面右上角显示实时 FPS / 内存 / 日志条数浮窗。
    /// Sub-toggle: show a live FPS / memory / log count overlay on every main page.
    var debugFPSOverlay: Bool = false

    /// 子开关:对应用了 .debugLayoutBounds() 修饰符的 view 显示 1px 随机色边框 + 5% 底色，方便排查布局问题。
    /// Sub-toggle: render a 1px random-color border + 5% tinted background on views marked with .debugLayoutBounds().
    var debugLayoutBounds: Bool = false

    /// 子开关:对应用了 .debugInspect() 修饰符的 view 长按弹 alert 显示原始值与类型。
    /// Sub-toggle: long-press any view marked with .debugInspect() to see its raw value and type.
    var debugLongPressInspect: Bool = false

    // MARK: - LLM (BYOK 大模型)

    /// LLM 总开关;关闭时所有 AI 功能回退到本地版本。
    /// Master switch for the BYOK LLM features. When off, every AI feature
    /// silently falls back to its local implementation.
    var llmEnabled: Bool = false
    /// Explicit opt-in for the long-term AI Coach feature.
    var coachEnabled: Bool = false
    var coachNotificationEnabled: Bool = true
    var coachNotificationHour: Int = 20
    /// When enabled, a material locally-detected recovery change can request a new Coach proposal.
    /// The proposal remains pending until the user approves it.
    var coachAdaptivePlanEnabled: Bool = false
    /// Local health baseline used to detect material changes without sending health data just to decide.
    var coachHealthBaselineCategory: String? = nil
    var coachHealthBaselineZScore: Double? = nil
    var coachHealthBaselineSleepHours: Double? = nil
    var coachHealthBaselineRestingHeartRate: Double? = nil
    var coachHealthBaselineRestorativeSleepHours: Double? = nil
    /// Limits cloud plan generation after a meaningful health change.
    var lastCoachAdaptivePlanRequestTime: Date? = nil
    /// Chat Completions 风格端点 base,例如 https://api.openai.com 或 https://api.deepseek.com
    /// OpenAI-compatible base URL (e.g. https://api.openai.com or https://api.deepseek.com).
    /// `nil` 表示未配置。
    var llmBaseURL: String? = nil
    /// 旧版本 UserDefaults 中的 API Key；只用于启动迁移，保存前必须清空。
    /// Legacy API key decoded only for one-time Keychain migration.
    var llmAPIKey: String? = nil
    /// 模型 id,例如 gpt-4o-mini / deepseek-chat
    /// Model id (e.g. gpt-4o-mini / deepseek-chat).
    var llmModel: String? = nil
    /// 自定义系统 prompt 追加(默认 prompt 之后)
    /// Optional suffix appended to the default system prompt.
    var llmSystemPromptAppendix: String? = nil
    /// 采样温度(0.0-2.0,默认 0.7)
    /// Sampling temperature (0.0-2.0, default 0.7).
    var llmTemperature: Double = 0.7
    /// 可保存多个供应商，并由 `activeLLMProviderId` 指定当前实际发起请求的项。
    var llmProviders: [LLMProvider] = []
    var activeLLMProviderId: UUID? = nil
    /// 主页恢复雷达 LLM 自动分析冷却时间（分钟，默认 40）。
    /// Recovery Radar LLM automatic-analysis cooldown in minutes (default 40).
    var radarAICooldownMinutes: Int = 40
    /// 主页雷达 LLM 增强建议冷却时间戳(用于按设置的时间限流)。
    /// 持久化以便跨 app 重启也生效;`立刻分析` 按钮可绕过此限制。
    /// Last request timestamp of the body-radar LLM-enhanced suggestion.
    /// Used to enforce the configured rate limit; the `Analyze now` button bypasses it.
    var lastRadarAIRequestTime: Date? = nil

    /// StudyPulse Cloud AI Worker 域名。内测 API Key 模式下，客户端不直接持有第三方 AI Key，
    /// 通过此网关统一发起 AI 请求。
    /// StudyPulse Cloud AI Worker base URL. When using a Cloud AI provider,
    /// all requests are routed through this gateway instead of directly to third-party APIs.
    var cloudAIWorkerURL: String? = "spapi.chenkai.space"

    /// Cloud AI 邮箱登录的邮箱地址。非空表示已登录。
    /// The email address used for Cloud AI Session Token login. Non-nil means logged in.
    var cloudSessionEmail: String? = nil

    /// Cloud AI 登录用户的会员类型（free/plus/pro）。登录时从服务端获取。
    /// Cloud AI logged-in user's membership type. Retrieved from server on login.
    var cloudMembershipType: String? = nil

    /// Cloud AI 会员到期时间（ISO 8601）。
    /// Cloud AI membership expiration (ISO 8601).
    var cloudMembershipExpiresAt: String? = nil

    /// Cloud AI 可用模型列表（从 /user/profile 获取）。
    /// Available models for Cloud AI (retrieved from /user/profile).
    var cloudAvailableModels: [String]? = nil

    /// Last Cloud AI quota snapshot from `GET /api/user/dashboard`.
    var cloudQuotaSnapshot: CloudAIQuotaSnapshot? = nil
    /// Cloud AI thinking preference for interactive callers. Background callers use server defaults.
    var cloudThinkingMode: LLMThinkingMode = .auto

    /// Debug 专用:全局覆盖 LLM 系统 prompt(仅 DEBUG 模式可见)。
    /// 非空时 LLMClient.buildBody 会**完全替换**默认 system + appendix,用于排查 prompt 行为。
    /// 空 / nil 时回退到默认 + appendix 的常规逻辑。
    /// DEBUG-only: when set, LLMClient replaces the default system prompt + appendix.
    /// Hidden in LLMSettingsView unless debug mode is on.
    var debugOverrideSystemPrompt: String? = nil

    /// 主页"学习建议"卡片 LLM 增强冷却时间戳(用于 40 分钟最多 1 次的限流)。
    /// 持久化以便跨 app 重启也生效;BodyRadar 同字段已存在,这里镜像实现。
    /// Last LLM request timestamp for the Study Suggestions card; same 40-minute cooldown as BodyRadar.
    var lastStudySuggestionsAIRequestTime: Date? = nil

    /// Whether HealthKit-derived/recovery data may be included in an LLM request.
    /// Default-off privacy gate. Mood and energy summaries are covered as well.
    var healthDataLLMSharingEnabled: Bool = false

    // MARK: - Habit Insight
    var habitInsightEnabled: Bool = false
    var habitInsightNotificationEnabled: Bool = true
    var habitInsightNotificationHour: Int = 7
    var habitInsightCooldownMinutes: Int = 60
    var lastHabitInsightAIRequestTime: Date? = nil
    var lastHabitInsightNotificationBody: String? = nil
    var lastHabitInsightNotificationDate: Date? = nil

    /// 学习计时器运行时是否采集 Apple Watch 心率(需 HealthKit 授权)。
    /// 默认开启;关闭后不挂载 observer、不弹回顾 sheet。
    /// Whether to stream Apple Watch heart rate during study timer sessions.
    /// Requires HealthKit authorization. Default on.
    var heartRateStreamingEnabled: Bool = true

    // MARK: - Diary (学习日记 + 心情记录)

    /// 学习日记功能总开关(默认开启)。关闭后隐藏 DiaryHomeCard + 设置入口。
    /// Master toggle for the study diary feature. When off, DiaryHomeCard
    /// and the settings entry are hidden.
    var diaryEnabled: Bool = true
    /// 每日日记提醒(默认关闭)
    /// Daily diary reminder notification (default off).
    var diaryDailyReminderEnabled: Bool = false
    /// 每日提醒时间(24 小时制,默认 22 点)
    /// Daily reminder hour (24h, default 22 = 22:00).
    var diaryDailyReminderHour: Int = 22
    /// 同步日记记录时刻到 Apple Health Mindful Session(默认开启;iOS 10+ 全球通用)。
    /// Sync each diary entry as an Apple Health Mindful Session sample
    /// (default on; iOS 10+ universal).
    var diarySyncToHealthEnabled: Bool = true
    /// AI 元认知反思段开关(默认开启)。关闭后 WeeklyReportLLM 回退原 3 段输出。
    /// AI metacognition reflection toggle (default on). When off, the weekly
    /// report LLM falls back to the original 3-section output.
    var diaryLLMReflectionEnabled: Bool = true

    // MARK: - Brain Usage
    var brainUsageMode: BrainUsagePreferences.Mode = .manual
    var brainUsageManualFiveHourQuota: Int = BrainUsageQuota.default.fiveHour
    var brainUsageManualSevenDayQuota: Int = BrainUsageQuota.default.sevenDay
    var brainUsageNotifyFiveHour: Bool = true
    var brainUsageNotifySevenDay: Bool = true
    var brainUsageDynamicFiveHourQuota: Int? = nil
    var brainUsageDynamicSevenDayQuota: Int? = nil
    var brainUsageDynamicQuotaGeneratedAt: Date? = nil

    // 自定义解码器：缺字段时使用默认值，兼容老版本 UserDefaults 数据
    // Custom decoder: fall back to defaults for missing fields so older
    // serialized preferences (without accentPaletteId / glassEffectEnabled)
    // continue to decode instead of throwing.
    enum CodingKeys: String, CodingKey {
        case appLanguage, colorScheme, chartType, accentPaletteId, glassEffectEnabled, learningHeatmapOnTrends, subjectMasteryRadarOnTrends, activePhaseId
        case cardSkinId, timerAnimationId
        case plantCardEnabled, plantPetalColorId
        case debugModeEnabled, debugVerboseLogging, debugFPSOverlay, debugLayoutBounds, debugLongPressInspect
        case llmEnabled, coachEnabled, coachNotificationEnabled, coachNotificationHour, coachAdaptivePlanEnabled, coachHealthBaselineCategory, coachHealthBaselineZScore, coachHealthBaselineSleepHours, coachHealthBaselineRestingHeartRate, coachHealthBaselineRestorativeSleepHours, lastCoachAdaptivePlanRequestTime, llmBaseURL, llmAPIKey, llmModel, llmSystemPromptAppendix, llmTemperature, llmProviders, activeLLMProviderId, cloudAIWorkerURL, cloudSessionEmail, cloudMembershipType, cloudMembershipExpiresAt, cloudAvailableModels, cloudQuotaSnapshot, cloudThinkingMode, radarAICooldownMinutes, lastRadarAIRequestTime, debugOverrideSystemPrompt, lastStudySuggestionsAIRequestTime, healthDataLLMSharingEnabled
        case habitInsightEnabled, habitInsightNotificationEnabled, habitInsightNotificationHour, habitInsightCooldownMinutes, lastHabitInsightAIRequestTime, lastHabitInsightNotificationBody, lastHabitInsightNotificationDate
        case heartRateStreamingEnabled
        case diaryEnabled, diaryDailyReminderEnabled, diaryDailyReminderHour, diarySyncToHealthEnabled, diaryLLMReflectionEnabled
        case brainUsageMode, brainUsageManualFiveHourQuota, brainUsageManualSevenDayQuota, brainUsageNotifyFiveHour, brainUsageNotifySevenDay, brainUsageDynamicFiveHourQuota, brainUsageDynamicSevenDayQuota, brainUsageDynamicQuotaGeneratedAt
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.appLanguage = try c.decodeIfPresent(String.self, forKey: .appLanguage)
        self.colorScheme = try c.decodeIfPresent(ColorSchemeOption.self, forKey: .colorScheme) ?? .system
        self.chartType = try c.decodeIfPresent(ChartType.self, forKey: .chartType) ?? .line
        self.accentPaletteId = try c.decodeIfPresent(String.self, forKey: .accentPaletteId)
        self.glassEffectEnabled = try c.decodeIfPresent(Bool.self, forKey: .glassEffectEnabled) ?? false
        self.learningHeatmapOnTrends = try c.decodeIfPresent(Bool.self, forKey: .learningHeatmapOnTrends) ?? true
        self.subjectMasteryRadarOnTrends = try c.decodeIfPresent(Bool.self, forKey: .subjectMasteryRadarOnTrends) ?? true
        self.activePhaseId = try c.decodeIfPresent(UUID.self, forKey: .activePhaseId)
        self.cardSkinId = try c.decodeIfPresent(String.self, forKey: .cardSkinId)
        self.timerAnimationId = try c.decodeIfPresent(String.self, forKey: .timerAnimationId)
        self.plantCardEnabled = try c.decodeIfPresent(Bool.self, forKey: .plantCardEnabled) ?? true
        self.plantPetalColorId = try c.decodeIfPresent(String.self, forKey: .plantPetalColorId)
        self.debugModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .debugModeEnabled) ?? false
        self.debugVerboseLogging = try c.decodeIfPresent(Bool.self, forKey: .debugVerboseLogging) ?? false
        self.debugFPSOverlay = try c.decodeIfPresent(Bool.self, forKey: .debugFPSOverlay) ?? false
        self.debugLayoutBounds = try c.decodeIfPresent(Bool.self, forKey: .debugLayoutBounds) ?? false
        self.debugLongPressInspect = try c.decodeIfPresent(Bool.self, forKey: .debugLongPressInspect) ?? false
        // LLM BYOK 配置 — 缺字段时使用安全默认值,保证旧版 UserDefaults 数据能继续 decode
        self.llmEnabled = try c.decodeIfPresent(Bool.self, forKey: .llmEnabled) ?? false
        self.coachEnabled = try c.decodeIfPresent(Bool.self, forKey: .coachEnabled) ?? false
        self.coachNotificationEnabled = try c.decodeIfPresent(Bool.self, forKey: .coachNotificationEnabled) ?? true
        self.coachNotificationHour = max(0, min(23, try c.decodeIfPresent(Int.self, forKey: .coachNotificationHour) ?? 20))
        self.coachAdaptivePlanEnabled = try c.decodeIfPresent(Bool.self, forKey: .coachAdaptivePlanEnabled) ?? false
        self.coachHealthBaselineCategory = try c.decodeIfPresent(String.self, forKey: .coachHealthBaselineCategory)
        self.coachHealthBaselineZScore = try c.decodeIfPresent(Double.self, forKey: .coachHealthBaselineZScore)
        self.coachHealthBaselineSleepHours = try c.decodeIfPresent(Double.self, forKey: .coachHealthBaselineSleepHours)
        self.coachHealthBaselineRestingHeartRate = try c.decodeIfPresent(Double.self, forKey: .coachHealthBaselineRestingHeartRate)
        self.coachHealthBaselineRestorativeSleepHours = try c.decodeIfPresent(Double.self, forKey: .coachHealthBaselineRestorativeSleepHours)
        self.lastCoachAdaptivePlanRequestTime = try c.decodeIfPresent(Date.self, forKey: .lastCoachAdaptivePlanRequestTime)
        self.llmBaseURL = try c.decodeIfPresent(String.self, forKey: .llmBaseURL)
        self.llmAPIKey = try c.decodeIfPresent(String.self, forKey: .llmAPIKey)
        self.llmModel = try c.decodeIfPresent(String.self, forKey: .llmModel)
        self.llmSystemPromptAppendix = try c.decodeIfPresent(String.self, forKey: .llmSystemPromptAppendix)
        self.llmTemperature = try c.decodeIfPresent(Double.self, forKey: .llmTemperature) ?? 0.7
        self.llmProviders = try c.decodeIfPresent([LLMProvider].self, forKey: .llmProviders) ?? []
        self.activeLLMProviderId = try c.decodeIfPresent(UUID.self, forKey: .activeLLMProviderId)
        self.cloudAIWorkerURL = try c.decodeIfPresent(String.self, forKey: .cloudAIWorkerURL) ?? "spapi.chenkai.space"
        self.cloudSessionEmail = try c.decodeIfPresent(String.self, forKey: .cloudSessionEmail)
        self.cloudMembershipType = try c.decodeIfPresent(String.self, forKey: .cloudMembershipType)
        self.cloudMembershipExpiresAt = try c.decodeIfPresent(String.self, forKey: .cloudMembershipExpiresAt)
        self.cloudAvailableModels = try c.decodeIfPresent([String].self, forKey: .cloudAvailableModels)
        self.cloudQuotaSnapshot = try c.decodeIfPresent(CloudAIQuotaSnapshot.self, forKey: .cloudQuotaSnapshot)
        self.cloudThinkingMode = try c.decodeIfPresent(LLMThinkingMode.self, forKey: .cloudThinkingMode) ?? .auto
        // 从旧版单一配置无损迁移，既有用户升级后可立刻继续使用。
        if self.llmProviders.isEmpty,
           let baseURL = self.llmBaseURL,
           let apiKey = self.llmAPIKey,
           let model = self.llmModel,
           !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !apiKey.isEmpty,
           !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let provider = LLMProvider(name: "Default", baseURL: baseURL, legacyAPIKey: apiKey, model: model)
            self.llmProviders = [provider]
            self.activeLLMProviderId = provider.id
        }
        if let activeLLMProviderId, !self.llmProviders.contains(where: { $0.id == activeLLMProviderId }) {
            self.activeLLMProviderId = self.llmProviders.first?.id
        }
        let radarCooldown = try c.decodeIfPresent(Int.self, forKey: .radarAICooldownMinutes) ?? 40
        self.radarAICooldownMinutes = max(5, min(180, radarCooldown))
        self.lastRadarAIRequestTime = try c.decodeIfPresent(Date.self, forKey: .lastRadarAIRequestTime)
        self.debugOverrideSystemPrompt = try c.decodeIfPresent(String.self, forKey: .debugOverrideSystemPrompt)
        self.lastStudySuggestionsAIRequestTime = try c.decodeIfPresent(Date.self, forKey: .lastStudySuggestionsAIRequestTime)
        self.healthDataLLMSharingEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthDataLLMSharingEnabled) ?? false
        self.habitInsightEnabled = try c.decodeIfPresent(Bool.self, forKey: .habitInsightEnabled) ?? false
        self.habitInsightNotificationEnabled = try c.decodeIfPresent(Bool.self, forKey: .habitInsightNotificationEnabled) ?? true
        let habitHour = try c.decodeIfPresent(Int.self, forKey: .habitInsightNotificationHour) ?? 7
        self.habitInsightNotificationHour = max(0, min(23, habitHour))
        let habitCooldown = try c.decodeIfPresent(Int.self, forKey: .habitInsightCooldownMinutes) ?? 60
        self.habitInsightCooldownMinutes = max(5, min(180, habitCooldown))
        self.lastHabitInsightAIRequestTime = try c.decodeIfPresent(Date.self, forKey: .lastHabitInsightAIRequestTime)
        self.lastHabitInsightNotificationBody = try c.decodeIfPresent(String.self, forKey: .lastHabitInsightNotificationBody)
        self.lastHabitInsightNotificationDate = try c.decodeIfPresent(Date.self, forKey: .lastHabitInsightNotificationDate)
        self.heartRateStreamingEnabled = try c.decodeIfPresent(Bool.self, forKey: .heartRateStreamingEnabled) ?? true
        // Diary 配置 — 缺字段时使用安全默认值,保证旧版 UserDefaults 数据能继续 decode
        self.diaryEnabled = try c.decodeIfPresent(Bool.self, forKey: .diaryEnabled) ?? true
        self.diaryDailyReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .diaryDailyReminderEnabled) ?? false
        let hour = try c.decodeIfPresent(Int.self, forKey: .diaryDailyReminderHour) ?? 22
        self.diaryDailyReminderHour = max(0, min(23, hour))
        self.diarySyncToHealthEnabled = try c.decodeIfPresent(Bool.self, forKey: .diarySyncToHealthEnabled) ?? true
        self.diaryLLMReflectionEnabled = try c.decodeIfPresent(Bool.self, forKey: .diaryLLMReflectionEnabled) ?? true
        self.brainUsageMode = try c.decodeIfPresent(BrainUsagePreferences.Mode.self, forKey: .brainUsageMode) ?? .manual
        self.brainUsageManualFiveHourQuota = try c.decodeIfPresent(Int.self, forKey: .brainUsageManualFiveHourQuota) ?? BrainUsageQuota.default.fiveHour
        self.brainUsageManualSevenDayQuota = try c.decodeIfPresent(Int.self, forKey: .brainUsageManualSevenDayQuota) ?? BrainUsageQuota.default.sevenDay
        self.brainUsageNotifyFiveHour = try c.decodeIfPresent(Bool.self, forKey: .brainUsageNotifyFiveHour) ?? true
        self.brainUsageNotifySevenDay = try c.decodeIfPresent(Bool.self, forKey: .brainUsageNotifySevenDay) ?? true
        self.brainUsageDynamicFiveHourQuota = try c.decodeIfPresent(Int.self, forKey: .brainUsageDynamicFiveHourQuota)
        self.brainUsageDynamicSevenDayQuota = try c.decodeIfPresent(Int.self, forKey: .brainUsageDynamicSevenDayQuota)
        self.brainUsageDynamicQuotaGeneratedAt = try c.decodeIfPresent(Date.self, forKey: .brainUsageDynamicQuotaGeneratedAt)
    }
    
    // MARK: - 语言常量
    
    /// 支持的语言代码常量
    enum Language {
        static let english = "en"
        static let simplifiedChinese = "zh-Hans"
        static let traditionalChinese = "zh-Hant"
        static let japanese = "ja"
        static let korean = "ko"
        
        /// 所有支持的语言列表
        static let all: [(code: String?, displayName: String)] = [
            (nil, "Follow System"),
            (english, "English"),
            (simplifiedChinese, "简体中文"),
            (traditionalChinese, "繁體中文"),
            (japanese, "日本語"),
            (korean, "한국어")
        ]
        
        /// 所有支持的语言列表（已本地化）
        @MainActor static var allLocalized: [(code: String?, displayName: String)] {
            [
                (nil, "Follow System".localized()),
                (english, "English"),
                (simplifiedChinese, "简体中文"),
                (traditionalChinese, "繁體中文"),
                (japanese, "日本語"),
                (korean, "한국어")
            ]
        }
    }
}

// MARK: - Color Scheme Options (颜色主题选项)

/// 应用颜色主题选项
nonisolated enum ColorSchemeOption: String, Codable, CaseIterable {
    case system = "system"   /// 跟随系统
    case light = "light"     /// 浅色模式
    case dark = "dark"       /// 深色模式
    
    /// 主题对应的 SF Symbol 图标
    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
    
    /// 主题的本地化显示名称
    @MainActor var localizedDisplayName: String {
        switch self {
        case .system: "Follow System".localized()
        case .light: "Light".localized()
        case .dark: "Dark".localized()
        }
    }
    
    /// 转换为 SwiftUI ColorScheme（nil = 跟随系统）
    func toSwiftColorScheme() -> ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Chart Type (成绩趋势图表类型)

/// 成绩趋势图表显示类型
/// - line: 折线图（默认）
/// - bar: 柱状图
/// - pie: 饼图（按分数段占比展示）
/// - scatter: 散点图
/// - heatmap: 热力图（按日期-星期分布密度）
/// - histogram: 频数直方图（按 20% 得分率分组统计次数）
nonisolated enum ChartType: String, Codable, CaseIterable, Identifiable {
    case line = "line"
    case bar = "bar"
    case pie = "pie"
    case scatter = "scatter"
    case heatmap = "heatmap"
    case histogram = "histogram"

    var id: String { rawValue }

    /// SF Symbol 图标
    var icon: String {
        switch self {
        case .line: "chart.xyaxis.line"
        case .bar: "chart.bar.fill"
        case .pie: "chart.pie.fill"
        case .scatter: "chart.dots.scatter"
        case .heatmap: "square.grid.4x3.fill"
        case .histogram: "chart.bar.xaxis"
        }
    }

    /// 本地化显示名称
    @MainActor var localizedDisplayName: String {
        switch self {
        case .line: "Line Chart".localized()
        case .bar: "Bar Chart".localized()
        case .pie: "Pie Chart".localized()
        case .scatter: "Scatter Plot".localized()
        case .heatmap: "Heatmap".localized()
        case .histogram: "Frequency Histogram".localized()
        }
    }

    /// 本地化描述
    @MainActor var localizedDescription: String {
        switch self {
        case .line: "Show score trend over time with connected points.".localized()
        case .bar: "Show each grade as a separate bar.".localized()
        case .pie: "Show distribution across score ranges.".localized()
        case .scatter: "Show each grade as an independent dot.".localized()
        case .heatmap: "Show grade density by weekday and week.".localized()
        case .histogram: "Count how often scores fall into each 20% bucket.".localized()
        }
    }
}

// MARK: - Theme Accent (主色预设)

/// 自定义主色预设：影响 AccentColor、趋势折线、进度条、设置项高亮等。
/// 通过 `accentPaletteId` 字符串持久化；新加预设请追加 `id`，不要改老的 id。
nonisolated enum ThemeAccent: String, CaseIterable, Identifiable {
    case system = "system"       // 跟随系统 AccentColor（默认）
    case blue = "blue"
    case cyan = "cyan"
    case teal = "teal"
    case green = "green"
    case mint = "mint"
    case orange = "orange"
    case red = "red"
    case pink = "pink"
    case purple = "purple"
    case indigo = "indigo"

    var id: String { rawValue }

    /// 解析持久化的 id，未知值回退到 `.system`
    static func resolve(_ id: String?) -> ThemeAccent {
        guard let id, let value = ThemeAccent(rawValue: id) else { return .system }
        return value
    }

    /// SF Symbol 图标（用于色板预览）
    var swatchSystemImage: String {
        switch self {
        case .system: "circle.righthalf.fill"
        default: "circle.fill"
        }
    }

    /// 主色（用于 `tint()`、折线、进度条等）
    /// `.system` 走 SwiftUI 系统 AccentColor，遵循系统浅深色
    var color: Color {
        switch self {
        case .system: .accentColor
        case .blue: .blue
        case .cyan: .cyan
        case .teal: .teal
        case .green: .green
        case .mint: .mint
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .purple: .purple
        case .indigo: .indigo
        }
    }

    /// 本地化显示名
    @MainActor var localizedDisplayName: String {
        switch self {
        case .system: "System Default".localized()
        case .blue: "Blue".localized()
        case .cyan: "Cyan".localized()
        case .teal: "Teal".localized()
        case .green: "Green".localized()
        case .mint: "Mint".localized()
        case .orange: "Orange".localized()
        case .red: "Red".localized()
        case .pink: "Pink".localized()
        case .purple: "Purple".localized()
        case .indigo: "Indigo".localized()
        }
    }
}
