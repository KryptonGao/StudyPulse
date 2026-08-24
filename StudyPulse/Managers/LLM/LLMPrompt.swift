//
//  LLMPrompt.swift
//  StudyPulse
//
//  LLM 提示载荷类型 / LLM prompt payload types:
//  - `LLMMessage` / `LLMRole`  — OpenAI Chat Completions 消息结构
//                                OpenAI Chat Completions message envelope
//  - `LLMPrompt`               — 一次完整请求的 system + messages
//                                A full request: system + messages
//
//  纯数据类型,无副作用;由 `LLMRequestBuilder` 按场景构造,`LLMClient` 发送。
//  Pure data types; constructed per-scenario by `LLMRequestBuilder` and
//  sent by `LLMClient`.
//
//  Created for LLM BYOK integration (2026-07-11).
//

import Foundation

// MARK: - LLM Message Role (消息角色)

/// OpenAI Chat Completions 消息角色 / OpenAI Chat Completions role. 模型只接受这 4 种取值。
nonisolated enum LLMRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

// MARK: - LLM Message (单条消息)

/// 单条消息 / Single message. `content` 留空时序列化为 `""`(避免 JSON 缺字段报错)。
/// `content` empty string serializes as `""` (avoids JSON missing-key errors).
nonisolated struct LLMMessage: Codable, Sendable, Equatable {
    var role: LLMRole
    var content: String
    /// Base64 data URLs attached to this message for multimodal providers.
    var imageDataURLs: [String]

    init(role: LLMRole, content: String, imageDataURLs: [String] = []) {
        self.role = role
        self.content = content
        self.imageDataURLs = imageDataURLs
    }

    static func system(_ content: String) -> LLMMessage {
        LLMMessage(role: .system, content: content)
    }
    static func user(_ content: String, imageDataURLs: [String] = []) -> LLMMessage {
        LLMMessage(role: .user, content: content, imageDataURLs: imageDataURLs)
    }
    static func assistant(_ content: String) -> LLMMessage {
        LLMMessage(role: .assistant, content: content)
    }
}

/// Sensitivity classification for data included in an LLM prompt.
/// Health-derived values and recovery/mood summaries require explicit sharing
/// consent before they may be cached or sent to a configured endpoint.
nonisolated enum LLMPromptSensitivity: String, Codable, Sendable, Equatable {
    case ordinary
    case healthSensitive
}

// MARK: - LLM Prompt (单次请求载荷)

/// 一次完整请求 / A full LLM request payload.
/// `messages` 至少含 1 条 system;调用方在 `LLMRequestBuilder` 中按场景构造。
/// `messages` must contain ≥ 1 system message; built per-scenario by
/// `LLMRequestBuilder`.
nonisolated struct LLMPrompt: Sendable {
    /// 系统 prompt(会与 `LLMConfig.systemPromptAppendix` 拼接)
    /// System prompt (will be concatenated with `LLMConfig.systemPromptAppendix`).
    let system: String
    /// 多轮对话或单条 user 消息 / Multi-turn dialog or a single user message.
    let messages: [LLMMessage]

    /// Whether this prompt contains HealthKit-derived or recovery-sensitive data.
    let sensitivity: LLMPromptSensitivity

    init(
        system: String,
        messages: [LLMMessage],
        sensitivity: LLMPromptSensitivity = .ordinary
    ) {
        self.system = system
        self.messages = messages
        self.sensitivity = sensitivity
    }

    /// 拼接 `system + appendix`(若 appendix 非空)。
    /// Concatenate `system + appendix` (if appendix is non-empty).
    /// 在 `LLMClient` 内部调用,不让业务侧操心。
    /// Called inside `LLMClient`; business code never needs to know.
    func effectiveSystem(appendix: String?) -> String {
        guard let appendix, !appendix.isEmpty else { return system }
        return system + "\n\n" + appendix
    }
}
