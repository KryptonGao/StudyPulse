//
//  LLMConfig.swift
//  StudyPulse
//
//  LLM BYOK 配置:从 `AppPreferences` 读出 / 写回的桥接层。
//  单一 immutable value type,便于测试与跨线程传递。
//
//  Created for LLM BYOK integration (2026-07-11).
//

import Foundation

// MARK: - LLM Config (LLM 配置)
// MARK: - LLM Config

/// 用户在 `LLMSettingsView` 中配置的 LLM 参数。
/// `enabled == false` 时所有 LLM 调用都应回退到本地实现。
/// LLM parameters configured in `LLMSettingsView`.
/// When `enabled == false`, every LLM call should fall back to the local impl.
nonisolated struct LLMConfig: Sendable, Equatable {
    /// 总开关;关闭时所有 AI 功能回退到本地版本。
    var enabled: Bool
    /// Chat Completions 风格 base URL,例如 https://api.openai.com
    /// (URL 末尾的 `/` 会在 `LLMClient` 内部自动 trim)
    var baseURL: String?
    /// 用户自备的 API Key。仅从本机 Keychain 读取。
    var apiKey: String?
    /// 模型 id,例如 gpt-4o-mini / deepseek-chat
    var model: String?
    /// 用户配置的供应商名称,用于供应商特有的请求参数适配。
    var providerName: String? = nil
    var multimodalEnabled: Bool
    var thinkingEnabled: Bool
    /// `true` 表示使用 StudyPulse Cloud AI 网关（/v1/chat），而非 OpenAI 兼容端点。
    /// When `true`, routes through the StudyPulse Cloud AI gateway (/v1/chat)
    /// instead of an OpenAI-compatible endpoint.
    var isCloudProvider: Bool = false
    /// Cloud AI Session Token（邮箱登录获取）。非空时优先于 apiKey 用于鉴权。
    /// Cloud AI Session Token (from email login). When non-nil, takes precedence
    /// over apiKey for Cloud AI authentication.
    var sessionToken: String? = nil
    /// Explicit user consent to send HealthKit-derived/recovery data to an LLM endpoint.
    /// Defaults to false and is copied from AppPreferences.
    var allowsHealthDataSharing: Bool = false
    /// 自定义系统 prompt 追加(在默认 prompt 之后)
    var systemPromptAppendix: String?
    /// 采样温度 (0.0-2.0)
    var temperature: Double
    /// Debug 专用:完整覆盖 system prompt(非空时,会**完全替换**默认 system + appendix)。
    /// DEBUG-only override: when set, replaces the default system prompt + appendix entirely.
    var overrideSystemPrompt: String?

    /// 是否已配置完整。
    /// Cloud provider: 只需要 baseURL + (apiKey 或 sessionToken)。
    /// BYOK provider: baseURL / apiKey / model 都非空。
    /// `false` 时抛 `LLMError.notConfigured`,调用方按需回退。
    var isConfigured: Bool {
        guard enabled else { return false }
        guard let baseURL, !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if isCloudProvider {
            let hasAPIKey = !(apiKey?.isEmpty ?? true)
            let hasSessionToken = !(sessionToken?.isEmpty ?? true)
            guard hasAPIKey || hasSessionToken else { return false }
            return true
        }
        guard let apiKey, !apiKey.isEmpty else { return false }
        guard let model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }
}

extension LLMConfig {
    /// 默认配置(全部关闭 / 空)。用于首次启动 / 测试 fallback。
    /// Default config (everything off / empty). Used for first launch and tests.
    static let empty = LLMConfig(
        enabled: false,
        baseURL: nil,
        apiKey: nil,
        model: nil,
        providerName: nil,
        multimodalEnabled: false,
        thinkingEnabled: false,
        isCloudProvider: false,
        sessionToken: nil,
        allowsHealthDataSharing: false,
        systemPromptAppendix: nil,
        temperature: 0.7
    )
}

// MARK: - AppPreferences 桥接 / AppPreferences bridge
// MARK: - AppPreferences 桥接

import os

extension LLMConfig {
    /// 从 `AppPreferences` 当前值构造一份 `LLMConfig`。
    /// 这是只读快照;修改配置请走 `AppEnvironmentManager` 提供的 setter。
    /// Build an `LLMConfig` snapshot from the current `AppPreferences`.
    /// Read-only; mutate through the `AppEnvironmentManager` setters.
    @MainActor
    static func from(
        _ prefs: AppPreferences,
        keychain: KeychainStore = .shared
    ) -> LLMConfig {
        let provider = prefs.llmProviders.first { $0.id == prefs.activeLLMProviderId }

        // 始终读取 Session Token（邮箱登录凭据），不依赖 provider 查找
        let sessionToken = AuthTokenStore.shared.accessToken
            ?? (try? keychain.read(account: LLMAPIKeyAccount.cloudSession))
        let hasCloudSession = sessionToken != nil && prefs.cloudSessionEmail != nil

        // Cloud AI 判定：provider 明确是 Cloud，或存在有效的邮箱登录 Session
        let isCloud = (provider?.isCloudProvider ?? false) || hasCloudSession
        let cloudProvider = isCloud ? prefs.llmProviders.first(where: { $0.isCloudProvider }) : nil

        let account: String
        if let provider, provider.isCloudProvider {
            account = LLMAPIKeyAccount.cloud
        } else if let provider {
            account = LLMAPIKeyAccount.provider(provider.id)
        } else {
            account = LLMAPIKeyAccount.legacy
        }
        let apiKey = try? keychain.read(account: account)

        let config = LLMConfig(
            enabled: prefs.llmEnabled,
            baseURL: isCloud ? (prefs.cloudAIWorkerURL ?? "spapi.chenkai.space") : (provider?.baseURL ?? prefs.llmBaseURL),
            apiKey: apiKey ?? nil,
            model: isCloud ? (cloudProvider?.model ?? "MiniMax-M3") : (provider?.model ?? prefs.llmModel),
            providerName: provider?.name,
            multimodalEnabled: provider?.multimodalEnabled ?? false,
            thinkingEnabled: provider?.thinkingEnabled ?? false,
            isCloudProvider: isCloud,
            sessionToken: sessionToken,
            allowsHealthDataSharing: prefs.healthDataLLMSharingEnabled,
            systemPromptAppendix: prefs.llmSystemPromptAppendix,
            temperature: prefs.llmTemperature,
            overrideSystemPrompt: prefs.debugOverrideSystemPrompt
        )
        Log.llm.info("LLMConfig: enabled=\(config.enabled, privacy: .public) isCloud=\(config.isCloudProvider, privacy: .public) baseURL=\(config.baseURL ?? "nil", privacy: .public) hasSessionToken=\(config.sessionToken != nil, privacy: .public) hasAPIKey=\(config.apiKey != nil, privacy: .public) isConfigured=\(config.isConfigured, privacy: .public) model=\(config.model ?? "nil", privacy: .public)")
        return config
    }
}
