//
//  LLMError.swift
//  StudyPulse
//
//  LLM 客户端错误类型。所有调用方(学习建议 / 错题解析 / 周报总结 / AI 助手)
//  应当捕获 `LLMError` 并按需求决定是否回退到本地实现。
//
//  Created for LLM BYOK integration (2026-07-11).
//

import Foundation

// MARK: - LLM Error (LLM 错误类型)
// MARK: - LLM Error

/// LLM 调用过程中可能抛出的错误。
/// 用于上层做"AI 失败 → 回退到本地"的统一入口。
/// Errors that may be thrown by an LLM call. Callers catch this type
/// to implement the "AI failed → fall back to local" pattern.
enum LLMError: Error, LocalizedError, Equatable {
    /// 用户未在 `LLMSettingsView` 配置 baseURL / APIKey / model
    case notConfigured
    /// baseURL 解析失败
    case invalidURL
    /// HTTP 401: API Key 无效 / 鉴权失败
    case unauthorized
    /// HTTP 429: 速率限制
    case rateLimited
    /// HTTP 4xx(非 401/429)/ 5xx。`body` 是服务端返回的 JSON 文本(若有),用于诊断
    case serverError(statusCode: Int, body: String?)
    /// Cloud AI 网关错误。只保存已解析的字段，避免把原始 JSON 传到 UI。
    case cloudServerError(statusCode: Int, code: String?, message: String?)
    /// 网络层错误(URLError / 解码 / 取消 等)
    case network(String)
    /// 响应 JSON 解析失败(数据格式与 OpenAI 协议不符)
    case malformedResponse
    /// 服务端返回了空内容(content 字段为 null/空)
    case emptyResponse
    /// 整个请求超时
    case timeout
    /// The prompt contains health-sensitive data and sharing has not been approved.
    case healthDataConsentRequired

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "LLM not configured. Set Base URL, API Key and Model in Settings → LLM.".localized()
        case .invalidURL:
            return "Invalid Base URL.".localized()
        case .unauthorized:
            return "Authentication failed. Check your API Key.".localized()
        case .rateLimited:
            return "Rate limited. Please try again later.".localized()
        case .serverError(let code, let body):
            // 把服务端返回的真实错误信息拼到提示里(若有)
            // Append the server's actual error body to the message, if any.
            let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                return String(format: "Server error (HTTP %d): %@".localized(), code, trimmed)
            }
            return String(format: "Server error (HTTP %d).".localized(), code)
        case .cloudServerError(let statusCode, let code, let message):
            return Self.cloudUserMessage(statusCode: statusCode, code: code, message: message)
        case .network(let msg):
            return String(format: "Network error: %@".localized(), msg)
        case .malformedResponse:
            return "Failed to parse LLM response.".localized()
        case .emptyResponse:
            return "LLM returned empty content.".localized()
        case .timeout:
            return "LLM request timed out.".localized()
        case .healthDataConsentRequired:
            return "Health data sharing with AI is turned off. You can allow it in Health settings.".localized()
        }
    }

    /// Converts the documented Cloud AI error envelope into a user-facing message.
    /// The raw response is intentionally not retained in this error case.
    nonisolated static func cloudError(statusCode: Int, data: Data, secrets: [String?] = []) -> LLMError {
        var code: String?
        var message: String?

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorObject = object["error"] as? [String: Any] {
                code = errorObject["code"] as? String
                message = errorObject["message"] as? String
            } else if let errorString = object["error"] as? String {
                message = errorString
            }
        }

        let redacted = secrets.compactMap { $0 }.filter { !$0.isEmpty }.reduce(message) { partial, secret in
            partial?.replacingOccurrences(of: secret, with: "<redacted>")
        }
        return .cloudServerError(statusCode: statusCode, code: code, message: redacted)
    }

    private nonisolated static func cloudUserMessage(statusCode: Int, code: String?, message: String?) -> String {
        let searchable = [code, message]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
            .lowercased()

        if searchable.contains("account_banned") || searchable.contains("account banned") || searchable.contains("账号已被暂停") {
            return "Your account has been suspended. Please submit an appeal through Support.".localized()
        }
        if searchable.contains("session_expired") || searchable.contains("invalid or expired session") {
            return "Your login session has expired. Please log in again.".localized()
        }
        if searchable.contains("unauthorized") || searchable.contains("missing api key") || searchable.contains("missing api key or session token") {
            return "Please log in again to continue using Cloud AI.".localized()
        }
        if searchable.contains("invalid api key") || searchable.contains("api key disabled") || searchable.contains("api key expired") {
            return "Your Cloud AI API key is invalid, disabled, or expired. Please check it in Settings → LLM.".localized()
        }
        if searchable.contains("api key not bound to a user") {
            return "Your Cloud AI API key is not linked to an account. Please log in again or contact Support.".localized()
        }
        if searchable.contains("forbidden") || searchable == "forbidden" {
            return "This Cloud AI operation requires an account login. Please log in and try again.".localized()
        }
        if searchable.contains("model") && searchable.contains("not available") {
            return "This model is not available on your current Cloud AI plan. Please choose another model.".localized()
        }
        if searchable.contains("daily request limit") || searchable.contains("monthly token limit") || searchable.contains("monthly point limit") || searchable.contains("api quota exceeded") {
            return "Your Cloud AI quota has been used up. Please try again after the quota resets or upgrade your plan.".localized()
        }
        if searchable.contains("rate_limited") || searchable.contains("rate limit") {
            return "Cloud AI is temporarily rate-limited. Please wait a moment and try again.".localized()
        }
        if searchable.contains("invalid_request") || searchable.contains("invalid json body") {
            return "The Cloud AI request was invalid. Please try again. If the problem continues, contact Support.".localized()
        }
        if searchable.contains("ai request failed") || searchable.contains("server not configured") {
            return "Cloud AI is temporarily unavailable. Please try again later. If the problem continues, contact Support.".localized()
        }
        if statusCode == 401 {
            return "Your Cloud AI login is no longer valid. Please log in again.".localized()
        }
        if statusCode == 403 {
            return "Cloud AI access is currently unavailable for this account. Please check your plan or contact Support.".localized()
        }
        if statusCode == 429 {
            return "Cloud AI is temporarily unavailable due to a usage limit. Please try again later.".localized()
        }
        if statusCode == 500 || statusCode == 502 || statusCode >= 500 {
            return "Cloud AI is temporarily unavailable. Please try again later. If the problem continues, contact Support.".localized()
        }
        if statusCode == 404 {
            return "The Cloud AI service endpoint was not found. Please check the service configuration or contact Support.".localized()
        }
        return "Cloud AI request failed. Please try again. If the problem continues, contact Support.".localized()
    }
}
