//
//  AppEnvironmentManager.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/6/5.
//

import SwiftUI
import Foundation
import os

/// 管理全局应用环境：语言和主题
/// Manages global app environment: language, theme, accent, glass, and phase.
@MainActor
@Observable
final class AppEnvironmentManager {
    static let shared = AppEnvironmentManager()

    // UserDefaults 键名 / UserDefaults key for the preferences blob
    private let defaultsKey = "appPreferences"
    private let keychain = KeychainStore.shared

    var preferences: AppPreferences {
        didSet {
            save()
            // 任何偏好变更都可能影响 debug 子开关 → 同步到 LogStore
            // Any preference change can flip a debug sub-toggle → sync to LogStore.
            applyDebugStateToLogStore()
        }
    }

    /// 当前有效的 SwiftUI ColorScheme（nil = 跟随系统）
    /// Currently effective SwiftUI `ColorScheme` (nil = follow system).
    var effectiveColorScheme: ColorScheme? {
        preferences.colorScheme.toSwiftColorScheme()
    }

    /// 当前有效的语言代码
    /// Currently effective language code.
    var effectiveLanguage: String? {
        preferences.appLanguage
    }

    /// 当前主色（用于 AccentColor / 折线 / 进度条）
    /// Currently active accent (used for AccentColor / charts / progress bars).
    var effectiveAccent: ThemeAccent {
        ThemeAccent.resolve(preferences.accentPaletteId)
    }

    /// 当前主色对应的 `Color`
    /// `Color` representation of the currently active accent.
    var effectiveAccentColor: Color {
        effectiveAccent.color
    }

    // MARK: - Theme Shop (主题 / 皮肤商店)
    // MARK: - 主题商店 / Theme Shop

    /// 当前装备的主色预设（与 `effectiveAccent` 保持一致；后者保留以兼容旧调用点）。
    /// Currently equipped accent palette (matches `effectiveAccent`; the latter is kept for legacy call sites).
    var effectiveAccentPalette: AccentPalette {
        ThemeShopCatalog.accentPalette(forId: preferences.accentPaletteId)
    }

    /// 当前装备的卡片皮肤。
    /// Currently equipped card skin.
    var effectiveCardSkin: CardSkin {
        ThemeShopCatalog.cardSkin(forId: preferences.cardSkinId)
    }

    /// 当前装备的计时器动画。
    /// Currently equipped timer animation.
    var effectiveTimerAnimation: TimerAnimation {
        ThemeShopCatalog.timerAnimation(forId: preferences.timerAnimationId)
    }

    /// 主色对应的 `Color`（直接读 `effectiveAccentPalette.color`）。
    /// `Color` for the accent (reads `effectiveAccentPalette.color` directly).
    var effectiveAccentPaletteColor: Color {
        effectiveAccentPalette.color
    }

    /// 全局是否启用 iOS 26 glassEffect 卡片
    /// Whether iOS 26 glassEffect cards are enabled globally.
    var glassEffectEnabled: Bool {
        preferences.glassEffectEnabled
    }

    /// 学习计时器运行时是否采集 Apple Watch 心率
    /// Whether to stream Apple Watch heart rate during study timer sessions.
    var heartRateStreamingEnabled: Bool {
        preferences.heartRateStreamingEnabled
    }

    /// 当前激活的 study phase id（nil = 全部数据）
    /// Currently active study phase id (nil = all data).
    var activePhaseId: UUID? {
        preferences.activePhaseId
    }

    // MARK: - Debug Mode 透传属性
    // MARK: - Debug 模式透传 / Debug pass-through

    /// Debug 模式总开关
    /// Master debug mode toggle.
    var debugModeEnabled: Bool {
        get { preferences.debugModeEnabled }
        set {
            Log.preferences.info("切换 Debug 总开关 / Debug mode: -> \(newValue, privacy: .public)")
            preferences.debugModeEnabled = newValue
        }
    }

    /// 是否处于 verbose 日志收集模式
    /// Whether verbose log capture is enabled.
    var debugVerboseLogging: Bool {
        preferences.debugVerboseLogging
    }

    /// 是否在主页面右上角显示 FPS / 内存浮窗
    /// Whether to show the FPS / memory overlay in the top-right corner.
    var debugFPSOverlay: Bool {
        preferences.debugFPSOverlay
    }

    /// 是否对 .debugLayoutBounds() 修饰的 view 显示边界
    /// Whether to outline views that have `.debugLayoutBounds()` applied.
    var debugLayoutBounds: Bool {
        preferences.debugLayoutBounds
    }

    /// 是否对 .debugInspect() 修饰的 view 启用长按检视
    /// Whether to enable long-press inspect on views that have `.debugInspect()` applied.
    var debugLongPressInspect: Bool {
        preferences.debugLongPressInspect
    }

    /// 是否启用 Debug 模式（仅看 master 总开关）。banner 出现条件。
    /// Whether Debug mode is on (master toggle only). Drives the banner.
    var isDebugModeActive: Bool {
        debugModeEnabled
    }

    /// 是否启用任意 Debug 子行为（用于决定右上角浮窗 / 修饰符是否生效）
    /// Whether any debug sub-behavior is currently active.
    var anyDebugSubToggleOn: Bool {
        debugVerboseLogging || debugFPSOverlay || debugLayoutBounds || debugLongPressInspect
    }

    /// 切换主色预设
    /// Switch the accent palette.
    func setAccentPalette(_ accent: ThemeAccent) {
        Log.preferences.info("切换 主色 / Accent change: -> \(accent.rawValue, privacy: .public)")
        preferences.accentPaletteId = accent.rawValue
    }

    /// 通过主色预设 id 装备（主题商店入口；与 `setAccentPalette` 行为一致，写同一字段）。
    /// Equip an accent palette by id (theme shop entry; same as `setAccentPalette`).
    func setAccentPaletteId(_ id: String) {
        Log.preferences.info("切换主色 (商店) / Accent change (shop): -> \(id, privacy: .public)")
        preferences.accentPaletteId = id
    }

    /// 装备卡片皮肤。
    /// Equip a card skin.
    func setCardSkinId(_ id: String) {
        Log.preferences.info("切换卡片皮肤 / Card skin change: -> \(id, privacy: .public)")
        preferences.cardSkinId = id
    }

    /// 装备计时器动画。
    /// Equip a timer animation.
    func setTimerAnimationId(_ id: String) {
        Log.preferences.info("切换计时器动画 / Timer animation change: -> \(id, privacy: .public)")
        preferences.timerAnimationId = id
    }

    /// 切换玻璃效果开关
    /// Toggle the glass effect switch.
    func setGlassEffectEnabled(_ enabled: Bool) {
        Log.preferences.info("切换玻璃效果 / Glass effect: -> \(enabled, privacy: .public)")
        preferences.glassEffectEnabled = enabled
    }

    /// Toggle the Apple Watch heart-rate streaming switch.
    func setHeartRateStreamingEnabled(_ enabled: Bool) {
        Log.preferences.info("切换心率采集 / HR streaming: -> \(enabled, privacy: .public)")
        preferences.heartRateStreamingEnabled = enabled
    }

    // MARK: - LLM (BYOK 大模型) 透传属性
    // MARK: - LLM 透传 / LLM pass-through

    /// 当前 LLM 配置快照(只读)。调用方按需构造 `LLMPrompt`。
    /// Current LLM config snapshot (read-only). Callers build `LLMPrompt` as needed.
    var llmConfig: LLMConfig {
        LLMConfig.from(preferences, keychain: keychain)
    }

    /// LLM 总开关
    /// LLM master toggle.
    var llmEnabled: Bool {
        get { preferences.llmEnabled }
        set {
            Log.preferences.info("切换 LLM 总开关 / LLM enabled: -> \(newValue, privacy: .public)")
            preferences.llmEnabled = newValue
        }
    }

    var activeLLMProvider: LLMProvider? {
        preferences.llmProviders.first { $0.id == preferences.activeLLMProviderId }
    }

    func addLLMProvider() {
        let provider = LLMProvider(name: "New Provider")
        preferences.llmProviders.append(provider)
        preferences.activeLLMProviderId = provider.id
    }

    func updateLLMProvider(_ provider: LLMProvider, apiKey: String) throws {
        guard let index = preferences.llmProviders.firstIndex(where: { $0.id == provider.id }) else { return }
        let account = provider.isCloudProvider ? LLMAPIKeyAccount.cloud : LLMAPIKeyAccount.provider(provider.id)
        if apiKey.isEmpty {
            try keychain.delete(account: account)
        } else {
            try keychain.write(apiKey, account: account)
        }
        var metadata = provider
        metadata.legacyAPIKey = nil
        preferences.llmProviders[index] = metadata
    }

    func selectLLMProvider(_ id: UUID) {
        guard preferences.llmProviders.contains(where: { $0.id == id }) else { return }
        preferences.activeLLMProviderId = id
    }

    func deleteLLMProvider(_ id: UUID) {
        let provider = preferences.llmProviders.first { $0.id == id }
        let account = provider?.isCloudProvider == true ? LLMAPIKeyAccount.cloud : LLMAPIKeyAccount.provider(id)
        do {
            try keychain.delete(account: account)
        } catch {
            Log.preferences.error("删除 LLM Keychain 项失败 / Failed to delete LLM Keychain item")
            return
        }
        preferences.llmProviders.removeAll { $0.id == id }
        if preferences.activeLLMProviderId == id {
            preferences.activeLLMProviderId = preferences.llmProviders.first?.id
        }
    }

    /// 设置 LLM baseURL。`nil` / 空字符串视作未配置。
    /// Set the LLM baseURL. `nil` / empty string is treated as unconfigured.
    func setLLMBaseURL(_ url: String?) {
        let normalized: String?
        if let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            normalized = nil
        }
        Log.preferences.info("更新 LLM baseURL / LLM baseURL: -> \(normalized ?? "nil", privacy: .public)")
        updateActiveLLMProvider { $0.baseURL = normalized ?? "" }
    }

    /// 设置 LLM API Key。`nil` / 空字符串视作清空。
    /// Set the LLM API key. `nil` / empty string clears it.
    func setLLMAPIKey(_ key: String?) {
        let normalized: String?
        if let key, !key.isEmpty { normalized = key } else { normalized = nil }
        Log.preferences.info("更新 LLM apiKey / LLM apiKey: -> \(normalized == nil ? "nil" : "<redacted>", privacy: .public)")
        guard let id = preferences.activeLLMProviderId else { return }
        do {
            if let normalized {
                try keychain.write(normalized, account: LLMAPIKeyAccount.provider(id))
            } else {
                try keychain.delete(account: LLMAPIKeyAccount.provider(id))
            }
        } catch {
            Log.preferences.error("更新 LLM Keychain 项失败 / Failed to update LLM Keychain item")
        }
    }

    func llmAPIKey(for providerID: UUID) -> String {
        let provider = preferences.llmProviders.first { $0.id == providerID }
        let account = provider?.isCloudProvider == true ? LLMAPIKeyAccount.cloud : LLMAPIKeyAccount.provider(providerID)
        return (try? keychain.read(account: account)) ?? ""
    }

    func isLLMProviderConfigured(_ provider: LLMProvider) -> Bool {
        let baseURLOk = !provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let apiKeyOk = !llmAPIKey(for: provider.id).isEmpty
        if provider.isCloudProvider {
            return baseURLOk && apiKeyOk
        }
        return baseURLOk && apiKeyOk
            && !provider.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 设置 LLM 模型 id
    /// Set the LLM model id.
    func setLLMModel(_ model: String?) {
        let normalized: String?
        if let model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized = model.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            normalized = nil
        }
        Log.preferences.info("更新 LLM model / LLM model: -> \(normalized ?? "nil", privacy: .public)")
        updateActiveLLMProvider { $0.model = normalized ?? "" }
    }

    private func updateActiveLLMProvider(_ mutate: (inout LLMProvider) -> Void) {
        guard let id = preferences.activeLLMProviderId,
              let index = preferences.llmProviders.firstIndex(where: { $0.id == id }) else { return }
        mutate(&preferences.llmProviders[index])
    }

    // MARK: - Cloud AI Provider

    /// 激活 StudyPulse Cloud AI 内测 provider。
    /// 如果已存在 cloud provider 则直接选中,否则创建新的并写入 API Key。
    func activateCloudProvider(workerURL: String, apiKey: String) throws {
        let trimmedURL = workerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.cloudAIWorkerURL = trimmedURL

        // 先查找已有的 cloud provider
        if let existing = preferences.llmProviders.first(where: { $0.isCloudProvider }) {
            // 更新 workerURL
            if let idx = preferences.llmProviders.firstIndex(where: { $0.id == existing.id }) {
                preferences.llmProviders[idx].baseURL = trimmedURL
            }
            preferences.activeLLMProviderId = existing.id
            try keychain.write(apiKey, account: LLMAPIKeyAccount.cloud)
        } else {
            let provider = LLMProvider.cloudBeta(workerURL: trimmedURL)
            preferences.llmProviders.append(provider)
            preferences.activeLLMProviderId = provider.id
            try keychain.write(apiKey, account: LLMAPIKeyAccount.cloud)
        }
    }

    /// 停用 Cloud AI provider:取消选中(如果当前激活的是 cloud provider)。
    /// 仅 Key 模式下有意义；账号模式下应使用 disconnectKey()。
    func deactivateCloudProvider() {
        if let active = activeLLMProvider, active.isCloudProvider {
            // 取消选中 cloud provider,切换到第一个非 cloud provider(如果有)
            let next = preferences.llmProviders.first { !$0.isCloudProvider }
            preferences.activeLLMProviderId = next?.id
        }
    }

    /// 仅清除 Cloud AI Key（保留 provider 和活跃状态）。账号模式下使用。
    func disconnectCloudKey() {
        try? keychain.delete(account: LLMAPIKeyAccount.cloud)
    }

    /// 删除 Cloud AI provider 及对应 Keychain 条目。
    func deleteCloudProvider() {
        if let cloud = preferences.llmProviders.first(where: { $0.isCloudProvider }) {
            try? keychain.delete(account: LLMAPIKeyAccount.cloud)
            preferences.llmProviders.removeAll { $0.id == cloud.id }
            if preferences.activeLLMProviderId == cloud.id {
                preferences.activeLLMProviderId = preferences.llmProviders.first?.id
            }
        }
    }

    /// Cloud AI API Key(从 Keychain 读取)。
    var cloudAPIKey: String {
        (try? keychain.read(account: LLMAPIKeyAccount.cloud)) ?? ""
    }

    /// Cloud AI Session Token(从 Keychain 读取)。邮箱登录后非空。
    var cloudSessionToken: String? {
        AuthTokenStore.shared.accessToken
            ?? (try? keychain.read(account: LLMAPIKeyAccount.cloudSession))
    }

    var cloudRefreshToken: String? { AuthTokenStore.shared.refreshToken }

    /// 是否已通过邮箱登录 Cloud AI。
    var isCloudSessionLoggedIn: Bool {
        AuthTokenStore.shared.pair != nil || (preferences.cloudSessionEmail != nil && cloudSessionToken != nil)
    }

    func cloudSessionLogin(accessToken: String, refreshToken: String, email: String? = nil,
                           tokenStore: AuthTokenStore = .shared) throws {
        try tokenStore.save(AuthTokenPair(accessToken: accessToken, refreshToken: refreshToken))
        preferences.cloudSessionEmail = email
        preferences.cloudMembershipType = nil
        preferences.cloudMembershipExpiresAt = nil
        preferences.llmEnabled = true
        if let cloud = preferences.llmProviders.first(where: { $0.isCloudProvider }) {
            preferences.activeLLMProviderId = cloud.id
        } else {
            let provider = LLMProvider.cloudBeta(workerURL: preferences.cloudAIWorkerURL ?? "spapi.chenkai.space")
            preferences.llmProviders.append(provider)
            preferences.activeLLMProviderId = provider.id
        }
    }

    /// Applies a profile that was already validated by AuthClient. This method
    /// deliberately does not perform network I/O or persist tokens, so callers
    /// can validate a callback before any credential is written to Keychain.
    func applyCloudProfile(_ profile: ProfileData) {
        if let email = profile.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            preferences.cloudSessionEmail = email
        }
        preferences.cloudMembershipType = profile.membership?.effective_type ?? profile.membership?.type
        preferences.cloudMembershipExpiresAt = profile.membership?.expires_at
        preferences.cloudAvailableModels = profile.plan?.available_models
    }

    /// 保存 Session Token 并记录登录邮箱和会员信息。
    func cloudSessionLogin(email: String, token: String, membershipType: String? = nil, membershipExpiresAt: String? = nil) throws {
        try keychain.write(token, account: LLMAPIKeyAccount.cloudSession)
        preferences.cloudSessionEmail = email
        preferences.cloudMembershipType = membershipType
        preferences.cloudMembershipExpiresAt = membershipExpiresAt
        // 登录即启用 LLM 总开关（用户显然想用 AI 功能）
        preferences.llmEnabled = true
        // 确保 Cloud AI provider 存在并设为活跃（邮箱登录时自动创建，无需 API Key）
        if let cloud = preferences.llmProviders.first(where: { $0.isCloudProvider }) {
            preferences.activeLLMProviderId = cloud.id
        } else {
            let workerURL = preferences.cloudAIWorkerURL ?? "spapi.chenkai.space"
            let provider = LLMProvider.cloudBeta(workerURL: workerURL)
            preferences.llmProviders.append(provider)
            preferences.activeLLMProviderId = provider.id
        }
        Log.preferences.info("Cloud session login: email=\(email, privacy: .private(mask: .hash)) membership=\(membershipType ?? "free", privacy: .public) tokenSaved=\(self.cloudSessionToken != nil)")
    }

    /// 清除 Session Token 和登录邮箱及会员信息。
    func cloudSessionLogout() {
        try? AuthTokenStore.shared.clear()
        try? keychain.delete(account: LLMAPIKeyAccount.cloudSession)
        preferences.cloudSessionEmail = nil
        preferences.cloudMembershipType = nil
        preferences.cloudMembershipExpiresAt = nil
        preferences.cloudAvailableModels = nil
    }

    /// 当前是否有 Cloud AI provider。
    var hasCloudProvider: Bool {
        preferences.llmProviders.contains { $0.isCloudProvider }
    }

    /// 刷新 Cloud AI 用户信息和可用模型列表。
    func refreshCloudProfile() async {
        guard let token = cloudSessionToken,
              let workerURL = preferences.cloudAIWorkerURL,
              !token.isEmpty, !workerURL.isEmpty else { return }
        do {
            let profile = try await AuthClient.shared.getProfile(sessionToken: token, workerURL: workerURL)
            applyCloudProfile(profile)
        } catch {
            Log.preferences.error("刷新 Cloud AI profile 失败: \(error.localizedDescription)")
        }
    }

    /// 当前是否激活 Cloud AI provider。
    var isCloudProviderActive: Bool {
        activeLLMProvider?.isCloudProvider ?? false
    }

    /// 设置 LLM 自定义系统 prompt 追加
    /// Set the LLM system prompt appendix.
    func setLLMSystemPromptAppendix(_ appendix: String?) {
        let normalized: String?
        if let appendix, !appendix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized = appendix
        } else {
            normalized = nil
        }
        preferences.llmSystemPromptAppendix = normalized
    }

    /// 设置 LLM 采样温度(0.0-2.0,内部 clamp)
    /// Set the LLM sampling temperature (0.0–2.0, clamped internally).
    func setLLMTemperature(_ temperature: Double) {
        let clamped = max(0, min(2, temperature))
        preferences.llmTemperature = clamped
    }

    /// 设置恢复雷达 LLM 自动分析冷却时间（5–180 分钟）。
    /// Set the Recovery Radar LLM automatic-analysis cooldown (5–180 minutes).
    func setRadarAICooldownMinutes(_ minutes: Int) {
        let clamped = max(5, min(180, minutes))
        Log.preferences.info("更新恢复雷达 LLM 冷却时间 / Radar LLM cooldown: -> \(clamped, privacy: .public) min")
        preferences.radarAICooldownMinutes = clamped
    }

    func setHabitInsightEnabled(_ value: Bool) { preferences.habitInsightEnabled = value }
    func setHabitInsightNotificationEnabled(_ value: Bool) { preferences.habitInsightNotificationEnabled = value }
    func setHabitInsightNotificationHour(_ value: Int) { preferences.habitInsightNotificationHour = max(0, min(23, value)) }
    func setHabitInsightCooldownMinutes(_ value: Int) { preferences.habitInsightCooldownMinutes = max(5, min(180, value)) }
    func setLastHabitInsightAIRequestTime(_ value: Date?) { preferences.lastHabitInsightAIRequestTime = value }
    func setLastHabitInsightNotificationBody(_ value: String?) { preferences.lastHabitInsightNotificationBody = value }
    func setLastHabitInsightNotificationDate(_ value: Date?) { preferences.lastHabitInsightNotificationDate = value }

    /// 设置 DEBUG 模式专用:全局覆盖 LLM 系统 prompt(仅 DEBUG 模式可见)。
    /// `nil` / 空字符串 → 清空覆盖,回退到默认 + appendix。
    /// DEBUG-only: globally override the LLM system prompt (visible in DEBUG only).
    /// `nil` / empty string clears the override, falling back to default + appendix.
    func setLLMDebugOverrideSystemPrompt(_ override: String?) {
        let normalized: String?
        if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized = override
        } else {
            normalized = nil
        }
        Log.preferences.info("更新 LLM debug override / LLM debug override: -> \(normalized == nil ? "nil" : "<set>")")
        preferences.debugOverrideSystemPrompt = normalized
    }

    /// 设置当前激活的 study phase（nil = 全部数据）
    /// Set the currently active study phase (nil = all data).
    func setActivePhaseId(_ id: UUID?) {
        Log.preferences.info("切换 phase / Active phase change: -> \(id?.uuidString ?? "all", privacy: .public)")
        preferences.activePhaseId = id
        // 通知监听方(PhaseFilterRefresher)刷新 5 个 filtered 缓存。
        // 替代原 0.5s polling,把每分钟 120 次 MainActor 唤醒降到事件驱动 0 次。
        NotificationCenter.default.post(name: .activePhaseDidChange, object: nil)
    }
    
    private init() {
        // 从 UserDefaults 加载 / Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           var prefs = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            let migratedSecrets = LLMAPIKeyMigrator.migrate(
                preferences: &prefs,
                keychain: KeychainStore.shared
            )
            self.preferences = prefs
            // AppPreferences 会把旧版单一 LLM 配置转换为一个 Default provider；
            // 首次读取后立刻回写，确保迁移不是只停留在本次内存中。
            let hasProviderList = (try? JSONSerialization.jsonObject(with: data))
                .flatMap { $0 as? [String: Any] }?["llmProviders"] != nil
            if migratedSecrets || (!hasProviderList && !prefs.llmProviders.isEmpty) {
                save()
            }
            Log.preferences.info("已从 UserDefaults 恢复偏好 / Loaded preferences from UserDefaults: language=\(prefs.appLanguage ?? "auto", privacy: .public) scheme=\(prefs.colorScheme.rawValue, privacy: .public)")
        } else {
            self.preferences = AppPreferences()
            Log.preferences.info("使用默认偏好初始化 / Using default preferences")
        }

        // 同步 verbose 日志开关到 LogStore
        // Sync the verbose logging flag into the in-memory LogStore.
        applyDebugStateToLogStore()
    }

    /// 把 Debug 子开关同步到 LogStore（verbose 日志级别）
    /// Push the current Debug sub-toggles into LogStore.
    private func applyDebugStateToLogStore() {
        let minLevel: LogLevel = preferences.debugVerboseLogging ? .debug : .info
        Task { await LogStore.shared.setMinCaptureLevel(minLevel) }
        Log.preferences.info("LogStore minCaptureLevel = \(minLevel.rawValue, privacy: .public)")
    }

    /// 切换 verbose 日志模式（同时改 preferences 和 LogStore）
    /// Toggle verbose logging (updates both preferences and LogStore).
    func setDebugVerboseLogging(_ enabled: Bool) {
        Log.preferences.info("切换 verbose 日志 / Verbose logging: -> \(enabled, privacy: .public)")
        preferences.debugVerboseLogging = enabled
        applyDebugStateToLogStore()
    }

    /// 保存偏好到 UserDefaults / Save preferences to UserDefaults
    private func save() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
            Log.preferences.debug("已保存偏好到 UserDefaults / Saved preferences: language=\(self.preferences.appLanguage ?? "auto", privacy: .public) scheme=\(self.preferences.colorScheme.rawValue, privacy: .public)")
        } else {
            Log.preferences.error("保存偏好失败 / Failed to encode preferences")
        }
    }

    /// 切换语言 / Switch language
    func setLanguage(_ code: String?) {
        Log.preferences.info("切换语言 / Language change: \(self.preferences.appLanguage ?? "auto", privacy: .public) -> \(code ?? "auto", privacy: .public)")
        preferences.appLanguage = code
        applyLanguage()
    }

    /// 切换主题 / Switch theme
    func setColorScheme(_ scheme: ColorSchemeOption) {
        Log.preferences.info("切换主题 / Color scheme change: \(self.preferences.colorScheme.rawValue, privacy: .public) -> \(scheme.rawValue, privacy: .public)")
        preferences.colorScheme = scheme
    }

    /// 应用语言设置（通过 UserDefaults 覆盖 App 语言）/ Apply language (overrides App language via UserDefaults)
    private func applyLanguage() {
        if let languageCode = preferences.appLanguage {
            UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
            Log.preferences.debug("已写入 AppleLanguages / Wrote AppleLanguages: \(languageCode, privacy: .public)")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            Log.preferences.debug("已清除 AppleLanguages / Cleared AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    /// 启动时应用语言（仅首次加载，不调用 synchronize 避免重启提示）
    /// Apply language at launch (initial load only, skip synchronize to avoid restart prompt)
    func applyLanguageOnLaunch() {
        if let languageCode = preferences.appLanguage {
            UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
            Log.preferences.info("启动时应用语言 / Applied language at launch: \(languageCode, privacy: .public)")
        } else {
            Log.preferences.debug("启动时无偏好语言，使用系统默认 / No preferred language at launch, using system default")
        }
    }
}
