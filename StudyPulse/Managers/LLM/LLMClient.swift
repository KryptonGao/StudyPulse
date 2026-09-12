//
//  LLMClient.swift
//  StudyPulse
//
//  LLM BYOK 客户端。实现 OpenAI Chat Completions 协议:
//  - `complete(...)` 单次非流式
//  - `stream(...)`   SSE 流式,逐 delta 调 onDelta
//  - `testConnection(...)` LLMSettingsView 用,极小请求确认可达
//
//  单例 `@MainActor class: observable reference type`,与项目其他 Manager
//  (HealthKitManager / PlantManager) 风格保持一致。
//
//  Created for LLM BYOK integration (2026-07-11).
//

import Foundation
import os

// MARK: - LLM Client

/// 单次 LLM 调用的调试信息(DEBUG 面板用)。包含 URL / prompt / 思考时长 / 响应。
/// Debug info for a single LLM call. Populated by LLMClient.complete / stream.
nonisolated struct LLMCallDebugInfo: Equatable, Sendable {
    /// 调用起始时间
    let startTime: Date
    /// 调用结束时间
    let endTime: Date
    /// 思考/总耗时(秒)
    var elapsedSeconds: TimeInterval { endTime.timeIntervalSince(startTime) }
    /// 端点 URL(完整,含 /v1/chat/completions)
    let url: String
    /// 模型 id
    let model: String
    /// 采样温度
    let temperature: Double
    /// system prompt(完整,含 override / appendix)
    let systemPrompt: String
    /// 消息历史
    let messages: [LLMMessage]
    /// 是否使用 stream
    let streaming: Bool
    /// 响应内容(成功时)
    var response: String?
    /// 错误描述(失败时)
    var error: String?
    /// 调用场景标签(可选,便于多 AI 功能区分),由调用方通过 `caller` 字段填充
    let caller: String

    /// 渲染为可复制的 JSON 字符串(给 LLMDebugSheet 用)
    func asDebugJSON() -> String {
        let allMessages = [LLMMessage.system(systemPrompt)] + messages
        let msgArr = allMessages.map { msg in
            "{\"role\":\"\(msg.role.rawValue)\",\"content\":\(escapeJSON(msg.content))}"
        }.joined(separator: ",")
        return """
        {
          "caller": \(escapeJSON(caller)),
          "url": \(escapeJSON(url)),
          "model": \(escapeJSON(model)),
          "temperature": \(temperature),
          "streaming": \(streaming),
          "elapsedSeconds": \(String(format: "%.3f", elapsedSeconds)),
          "systemPrompt": \(escapeJSON(systemPrompt)),
          "messages": [\(msgArr)],
          "response": \(response.map(escapeJSON) ?? "null"),
          "error": \(error.map(escapeJSON) ?? "null")
        }
        """
    }

    private func escapeJSON(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [])) ?? Data()
        let arr = String(data: data, encoding: .utf8) ?? "[\"\"]"
        // 取首尾的引号(数组形式 = ["..."])
        return String(arr.dropFirst().dropLast())
    }

    func redacting(secret: String?) -> LLMCallDebugInfo {
        redacting(secrets: [secret])
    }

    /// Returns a copy with every supplied credential removed from every debug field.
    /// This covers both BYOK API keys and Cloud session tokens.
    func redacting(secrets: [String?]) -> LLMCallDebugInfo {
        let usableSecrets: [String] = secrets.compactMap { secret -> String? in
            guard let secret, !secret.isEmpty else { return nil }
            return secret
        }
        guard !usableSecrets.isEmpty else { return self }
        func redact(_ value: String) -> String {
            usableSecrets.reduce(value) { partial, secret in
                partial.replacingOccurrences(of: secret, with: "<redacted>")
            }
        }
        return LLMCallDebugInfo(
            startTime: startTime,
            endTime: endTime,
            url: redact(url),
            model: redact(model),
            temperature: temperature,
            systemPrompt: redact(systemPrompt),
            messages: messages.map {
                LLMMessage(
                    role: $0.role,
                    content: redact($0.content),
                    imageDataURLs: $0.imageDataURLs.map(redact)
                )
            },
            streaming: streaming,
            response: response.map(redact),
            error: error.map(redact),
            caller: redact(caller)
        )
    }
}

/// OpenAI Chat Completions 兼容客户端。
/// - `stream(...)` 中 `onDelta` 接收**到目前为止的完整文本**(不是增量),
///   方便 UI 端直接存进 `AsyncStream` 给 `StreamedMarkdownView`。
@MainActor
@Observable
final class LLMClient: @unchecked Sendable {
    // `@unchecked Sendable`:nonisolated 方法(buildBody/effectiveSystem/buildURL)不访问可变状态,
    // 仅 observable 属性(lastCallInfo/recentCalls)需要 MainActor,它们仍在 MainActor 方法中访问。
    // `@unchecked Sendable`: nonisolated methods (buildBody/effectiveSystem/buildURL) access no
    // mutable state; only the observable properties (lastCallInfo/recentCalls) require MainActor,
    // and they are still touched only from MainActor methods (recordCall).
    static let shared = LLMClient()

    /// 整体请求超时(秒);`stream` 与 `complete` 通用。
    /// 多模态请求处理时间较长（图片 base64 编码 + MiniMax 视觉推理），需要更大超时。
    private let timeoutSeconds: TimeInterval = 120

    private let session: URLSession   // 网络会话(可注入以做单测)

    /// 最近一次调用的调试信息(给 LLMDebugSheet 显示)。每次 complete / stream 都会更新。
    /// Most-recent call's debug info. Updated on every complete / stream.
    private(set) var lastCallInfo: LLMCallDebugInfo? = nil
    /// 最近的若干条调用历史(最多保留 20 条,新调用 push 到末尾)。
    /// Recent call history (newest last, capped at 20).
    private(set) var recentCalls: [LLMCallDebugInfo] = []
    private let recentCallsLimit = 20  // 防止 LLM Debug 面板无限增长

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            // 显式声明超时;默认 60s 已经够用,且能被 `stream` 的 task 取消覆盖
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 300
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Public API

    /// 单次非流式调用,返回最终 content。
    /// 失败抛 `LLMError`;调用方按需回退到本地。
    /// - Parameter caller: 调用场景标签(例如 "MistakeAI" / "WeeklyReport");写入 debug info。
    func complete(
        prompt: LLMPrompt,
        config: LLMConfig,
        caller: String = "complete"
    ) async throws -> String {
        try validateConfig(config, prompt: prompt)

        // Cloud AI 网关:使用简化协议,响应格式不同。
        if config.isCloudProvider {
            let context = LLMRequestContext.make(caller: caller, config: config)
            return try await cloudComplete(prompt: prompt, config: config, context: context)
        }

        // BYOK: OpenAI 兼容协议。
        // 缓存命中:直接返回(避免重复走网络)。
        // Cache hit: return immediately (avoids the network round-trip).
        if let cached = await LLMResponseCache.shared.get(caller: caller, prompt: prompt, config: config) {
            return cached
        }
        printPromptToConsole(prompt: prompt, config: config, caller: caller)
        let url = try buildURL(baseURL: config.baseURL)
        // JSON 编解码移到 detached Task,避免阻塞主线程
        // Move JSON encoding off the main actor to keep UI responsive.
        let body = try await Task.detached(priority: .userInitiated) {
            try self.buildBody(prompt: prompt, config: config, stream: false)
        }.value
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey ?? "")", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        Log.llm.info("LLM complete → \(url.absoluteString, privacy: .public) model=\(config.model ?? "?", privacy: .public)")

        let startTime = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "?",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: false,
                response: nil, error: LLMError.timeout.errorDescription,
                caller: caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            throw LLMError.timeout
        } catch {
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "?",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: false,
                response: nil, error: error.localizedDescription,
                caller: caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            throw LLMError.network(error.localizedDescription)
        }
        do {
            try validateHTTP(response: response, data: data, secrets: [config.apiKey, config.sessionToken])
        } catch {
            let desc = (error as? LLMError)?.errorDescription ?? error.localizedDescription
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "?",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: false,
                response: String(data: data, encoding: .utf8),
                error: desc, caller: caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            throw error
        }
        let result = try await Task.detached(priority: .userInitiated) {
            try LLMChatResponse.parseSingleResponse(data)
        }.value
        let info = LLMCallDebugInfo(
            startTime: startTime, endTime: Date(),
            url: url.absoluteString, model: config.model ?? "?",
            temperature: config.temperature,
            systemPrompt: effectiveSystem(prompt: prompt, config: config),
            messages: prompt.messages, streaming: false,
            response: result, error: nil, caller: caller
        )
        recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
        // 写入缓存:相同 prompt 在 TTL 内不重复请求网络。
        // Cache the response so the same prompt doesn't hit the network within TTL.
        await LLMResponseCache.shared.set(caller: caller, prompt: prompt, config: config, response: result)
        return result
    }

    /// Cloud AI 网关专用非流式调用。
    /// Sends a Cloud AI-compatible request and parses the simplified response.
    @MainActor
    private func cloudComplete(
        prompt: LLMPrompt,
        config: LLMConfig,
        context: LLMRequestContext,
        retryingAfterRefresh: Bool = false
    ) async throws -> String {
        // 缓存命中
        if let cached = await LLMResponseCache.shared.get(caller: context.caller, prompt: prompt, config: config) {
            return cached
        }
        printPromptToConsole(prompt: prompt, config: config, caller: context.caller)
        let url = try buildCloudURL(baseURL: config.baseURL)
        let body = try await Task.detached(priority: .userInitiated) {
            try self.buildCloudBody(prompt: prompt, config: config, context: context)
        }.value
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cloudAuthHeader(config: config), forHTTPHeaderField: "Authorization")
        request.httpBody = body
        Log.llm.info("LLM cloud complete → \(url.absoluteString, privacy: .public)")

        let startTime = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "MiniMax-M3",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: false,
                response: nil, error: LLMError.timeout.errorDescription,
                caller: context.caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            throw LLMError.timeout
        } catch {
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "MiniMax-M3",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: false,
                response: nil, error: error.localizedDescription,
                caller: context.caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            throw LLMError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.network("Non-HTTP response")
        }
        if httpResponse.statusCode == 401, !retryingAfterRefresh,
           let refreshToken = AuthTokenStore.shared.refreshToken {
            do {
                let pair = try await AuthClient.shared.refreshAccessToken(refreshToken: refreshToken)
                var refreshedConfig = config
                refreshedConfig.sessionToken = pair.accessToken
                return try await cloudComplete(
                    prompt: prompt,
                    config: refreshedConfig,
                    context: context,
                    retryingAfterRefresh: true
                )
            } catch {
                AuthTokenStore.shared.clearIgnoringErrors()
                throw LLMError.unauthorized
            }
        }
        // Cloud AI 网关上 HTTP 200 但 body 可能包含 {"error":"..."}
        if !(200..<300).contains(httpResponse.statusCode) {
            let cloudError = LLMError.cloudError(statusCode: httpResponse.statusCode, data: data, secrets: [config.apiKey, config.sessionToken])
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "MiniMax-M3",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: false,
                response: nil, error: cloudError.errorDescription, caller: context.caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            throw cloudError
        }

        let result: String
        do {
            result = try await Task.detached(priority: .userInitiated) {
                try self.parseCloudResponse(data, httpResponse: httpResponse, secrets: [config.apiKey, config.sessionToken])
            }.value
        } catch {
            let desc = (error as? LLMError)?.errorDescription ?? error.localizedDescription
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "MiniMax-M3",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: false,
                response: nil,
                error: desc, caller: context.caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            throw error
        }

        let info = LLMCallDebugInfo(
            startTime: startTime, endTime: Date(),
            url: url.absoluteString, model: config.model ?? "MiniMax-M3",
            temperature: config.temperature,
            systemPrompt: effectiveSystem(prompt: prompt, config: config),
            messages: prompt.messages, streaming: false,
            response: result, error: nil, caller: context.caller
        )
        recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
        await LLMResponseCache.shared.set(caller: context.caller, prompt: prompt, config: config, response: result)
        return result
    }

    /// Cloud AI 网关专用 SSE 流式调用。
    /// Cloud AI v0.5-beta+ supports SSE streaming, proxying MiniMax raw OpenAI-compatible chunks.
    /// Uses the Cloud AI endpoint `{workerURL}/v1/chat` with `"stream": true`.
    @MainActor
    private func cloudStream(
        prompt: LLMPrompt,
        config: LLMConfig,
        context: LLMRequestContext,
        onDelta: @MainActor (String) -> Void,
        retryingAfterRefresh: Bool = false
    ) async throws -> String {
        // 缓存命中:把缓存作为单次 onDelta emit,避免重复走网络。
        if let cached = await LLMResponseCache.shared.get(caller: context.caller, prompt: prompt, config: config) {
            onDelta(cached)
            return cached
        }
        printPromptToConsole(prompt: prompt, config: config, caller: context.caller)
        let url = try buildCloudURL(baseURL: config.baseURL)
        let body = try await Task.detached(priority: .userInitiated) {
            try self.buildCloudBody(prompt: prompt, config: config, context: context, stream: true)
        }.value
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cloudAuthHeader(config: config), forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = timeoutSeconds
        Log.llm.info("LLM cloud stream → \(url.absoluteString, privacy: .public)")

        let startTime = Date()
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "MiniMax-M3",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: true,
                response: nil, error: error.localizedDescription,
                caller: context.caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            if let urlErr = error as? URLError, urlErr.code == .timedOut {
                throw LLMError.timeout
            }
            throw LLMError.network(error.localizedDescription)
        }

        // 如果状态非 2xx,先收集 body 再抛(Cloud AI 错误格式: {"error": "..."})。
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var buffer = Data()
            for try await byte in bytes {
                buffer.append(byte)
            }
            if http.statusCode == 401, !retryingAfterRefresh,
               let refreshToken = AuthTokenStore.shared.refreshToken {
                do {
                    let pair = try await AuthClient.shared.refreshAccessToken(refreshToken: refreshToken)
                    var refreshedConfig = config
                    refreshedConfig.sessionToken = pair.accessToken
                    return try await cloudStream(
                        prompt: prompt,
                        config: refreshedConfig,
                        context: context,
                        onDelta: onDelta,
                        retryingAfterRefresh: true
                    )
                } catch {
                    AuthTokenStore.shared.clearIgnoringErrors()
                    throw LLMError.unauthorized
                }
            }
            let cloudError = LLMError.cloudError(statusCode: http.statusCode, data: buffer, secrets: [config.apiKey, config.sessionToken])
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "MiniMax-M3",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: true,
                response: nil, error: cloudError.errorDescription, caller: context.caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            throw cloudError
        }

        // SSE 解析: Cloud AI 透传 MiniMax 的 OpenAI 兼容 chunk 格式，
        // LLMStreamingParser 可直接复用。
        // 注意：不用 break 提前退出，而是 read 到底。
        // AsyncLineSequence 内部有预读缓冲，break 可能导致尚未 yield 的行被丢弃。
        var accumulated = ""
        var pending = ""
        do {
            for try await line in bytes.lines {
                if Task.isCancelled { throw LLMError.network("Cancelled") }
                if LLMStreamingParser.isDoneLine(line) { continue }
                pending = line
                if let piece = LLMStreamingParser.parseLine(pending) {
                    accumulated += piece
                    let snapshot = accumulated
                    onDelta(snapshot)
                }
            }
        } catch {
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "MiniMax-M3",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: true,
                response: accumulated.isEmpty ? nil : accumulated,
                error: error.localizedDescription, caller: context.caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            throw error
        }

        if accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "MiniMax-M3",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: true,
                response: nil, error: LLMError.emptyResponse.errorDescription,
                caller: context.caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            throw LLMError.emptyResponse
        }

        let info = LLMCallDebugInfo(
            startTime: startTime, endTime: Date(),
            url: url.absoluteString, model: config.model ?? "MiniMax-M3",
            temperature: config.temperature,
            systemPrompt: effectiveSystem(prompt: prompt, config: config),
            messages: prompt.messages, streaming: true,
            response: accumulated, error: nil, caller: context.caller
        )
        recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
        await LLMResponseCache.shared.set(caller: context.caller, prompt: prompt, config: config, response: accumulated)
        return accumulated
    }

    /// SSE 流式调用,逐 delta 调 `onDelta`。
    /// 返回**完整文本**;`onDelta` 每次接收到目前为止的全部内容。
    /// 失败抛 `LLMError`。
    /// - Parameter caller: 调用场景标签(例如 "MistakeAI" / "WeeklyReport");写入 debug info。
    func stream(
        prompt: LLMPrompt,
        config: LLMConfig,
        caller: String = "stream",
        onDelta: @MainActor (String) -> Void
    ) async throws -> String {
        try validateConfig(config, prompt: prompt)

        // Cloud AI 网关 v0.5-beta 起支持 SSE 流式传输(透传 MiniMax 原始格式)。
        // Cloud AI gateway supports SSE streaming since v0.5-beta (proxies MiniMax raw format).
        if config.isCloudProvider {
            let context = LLMRequestContext.make(caller: caller, config: config)
            return try await cloudStream(prompt: prompt, config: config, context: context, onDelta: onDelta)
        }

        // BYOK: SSE 流式。
        // 缓存命中:把缓存作为单次 onDelta emit,避免重复走网络。
        // Cache hit: emit the cached response as a single onDelta,avoiding the network round-trip.
        if let cached = await LLMResponseCache.shared.get(caller: caller, prompt: prompt, config: config) {
            onDelta(cached)
            return cached
        }
        printPromptToConsole(prompt: prompt, config: config, caller: caller)
        let url = try buildURL(baseURL: config.baseURL)
        // JSON 编码移到 detached Task,与 complete() 一致
        // Move JSON encoding off the main actor, matching complete().
        let body = try await Task.detached(priority: .userInitiated) {
            try self.buildBody(prompt: prompt, config: config, stream: true)
        }.value
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(config.apiKey ?? "")", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = timeoutSeconds
        Log.llm.info("LLM stream → \(url.absoluteString, privacy: .public) model=\(config.model ?? "?", privacy: .public)")

        let startTime = Date()
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "?",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: true,
                response: nil, error: error.localizedDescription,
                caller: caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            if let urlErr = error as? URLError, urlErr.code == .timedOut {
                throw LLMError.timeout
            }
            throw LLMError.network(error.localizedDescription)
        }
        // 如果状态非 2xx,先把整个 body 收集起来再抛(serverError 才会带 body)
        // If status is not 2xx, drain the whole body before throwing so the error carries it.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var buffer = Data()
            for try await byte in bytes {
                buffer.append(byte)
            }
            do {
                try validateHTTP(response: response, data: buffer, secrets: [config.apiKey, config.sessionToken])
            } catch {
                let desc = (error as? LLMError)?.errorDescription ?? error.localizedDescription
                let info = LLMCallDebugInfo(
                    startTime: startTime, endTime: Date(),
                    url: url.absoluteString, model: config.model ?? "?",
                    temperature: config.temperature,
                    systemPrompt: effectiveSystem(prompt: prompt, config: config),
                    messages: prompt.messages, streaming: true,
                    response: String(data: buffer, encoding: .utf8),
                    error: desc, caller: caller
                )
                recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
                throw error
            }
        }
        try validateHTTP(response: response, data: Data(), secrets: [config.apiKey, config.sessionToken])

        var accumulated = ""
        var pending = ""
        do {
            for try await line in bytes.lines {
                if Task.isCancelled { throw LLMError.network("Cancelled") }
                if LLMStreamingParser.isDoneLine(line) { continue }
                // SSE 事件由空行分隔;单行处理
                pending = line
                if let piece = LLMStreamingParser.parseLine(pending) {
                    accumulated += piece
                    let snapshot = accumulated
                    onDelta(snapshot)
                }
            }
        } catch {
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "?",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: true,
                response: accumulated.isEmpty ? nil : accumulated,
                error: error.localizedDescription, caller: caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            throw error
        }
        if accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let info = LLMCallDebugInfo(
                startTime: startTime, endTime: Date(),
                url: url.absoluteString, model: config.model ?? "?",
                temperature: config.temperature,
                systemPrompt: effectiveSystem(prompt: prompt, config: config),
                messages: prompt.messages, streaming: true,
                response: nil, error: LLMError.emptyResponse.errorDescription,
                caller: caller
            )
            recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
            throw LLMError.emptyResponse
        }
        let info = LLMCallDebugInfo(
            startTime: startTime, endTime: Date(),
            url: url.absoluteString, model: config.model ?? "?",
            temperature: config.temperature,
            systemPrompt: effectiveSystem(prompt: prompt, config: config),
            messages: prompt.messages, streaming: true,
            response: accumulated, error: nil, caller: caller
        )
        recordCall(info, apiKey: config.apiKey, sessionToken: config.sessionToken)
        // 写入缓存:与 complete() 一致,使流式调用的结果也可被后续命中。
        // Cache the response so the same prompt doesn't hit the network within TTL.
        await LLMResponseCache.shared.set(caller: caller, prompt: prompt, config: config, response: accumulated)
        return accumulated
    }

    /// 测试连接。发一条极小请求确认端点可用。
    /// 成功返回;失败抛 `LLMError`。
    /// Cloud 模式下先 GET / 探活,再 POST /v1/chat 验证 sp_ key。
    func testConnection(config: LLMConfig) async throws {
        if config.isCloudProvider {
            try await testCloudConnection(config: config)
            return
        }
        let prompt = LLMPrompt(
            system: "You are a connectivity check endpoint.",
            messages: [.user("ping")]
        )
        _ = try await complete(prompt: prompt, config: config)
    }

    /// Cloud AI 网关连接测试:先 GET / 健康检查,再 POST /v1/chat 验证 API Key。
    @MainActor
    private func testCloudConnection(config: LLMConfig) async throws {
        // 1. 健康检查:直接 GET 根路径,不通过 buildCloudURL(避免 deletingLastPathComponent 只删一层)
        guard let raw = config.baseURL else { throw LLMError.invalidURL }
        let healthURL: URL
        do {
            healthURL = try SecureEndpointURL.make(base: raw)
        } catch {
            throw LLMError.invalidURL
        }
        var healthReq = URLRequest(url: healthURL)
        healthReq.httpMethod = "GET"
        let (healthData, healthResponse) = try await session.data(for: healthReq)
        guard let http = healthResponse as? HTTPURLResponse,
              http.statusCode == 200 else {
            throw LLMError.network("Health check failed")
        }
        guard let json = try? JSONSerialization.jsonObject(with: healthData) as? [String: Any],
              json["status"] as? String == "online" else {
            throw LLMError.network("Cloud AI service unavailable")
        }

        // 2. API Key 验证(发一条极小对话)
        let url = try buildCloudURL(baseURL: config.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cloudAuthHeader(config: config), forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "messages": [["role": "user", "content": "ping"]],
            "studypulse": ["caller": "Legacy", "thinking": "off"],
        ])
        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else {
            throw LLMError.network("Non-HTTP response")
        }
        guard httpResp.statusCode == 200 else {
            throw LLMError.cloudError(statusCode: httpResp.statusCode, data: data, secrets: [config.apiKey, config.sessionToken])
        }
        let reply = try parseCloudResponse(data, httpResponse: httpResp, secrets: [config.apiKey, config.sessionToken])
        guard !reply.isEmpty else {
            throw LLMError.emptyResponse
        }
    }

    // MARK: - Helpers

    /// 返回 Cloud AI 鉴权 Header 值。Session Token 优先于 API Key。
    private func cloudAuthHeader(config: LLMConfig) -> String {
        if let sessionToken = config.sessionToken, !sessionToken.isEmpty {
            Log.llm.info("Cloud AI auth: using Session Token")
            return "Bearer \(sessionToken)"
        }
        Log.llm.info("Cloud AI auth: using API Key")
        return "Bearer \(config.apiKey ?? "")"
    }

    private func validateConfig(_ config: LLMConfig, prompt: LLMPrompt) throws {
        guard config.enabled else { throw LLMError.notConfigured }
        let hasAPIKey = !(config.apiKey?.isEmpty ?? true)
        let hasSessionToken = !(config.sessionToken?.isEmpty ?? true)
        if config.isCloudProvider {
            guard hasAPIKey || hasSessionToken else { throw LLMError.notConfigured }
        } else {
            guard hasAPIKey else { throw LLMError.notConfigured }
        }
        guard let baseURL = config.baseURL, !baseURL.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LLMError.notConfigured
        }
        guard (try? SecureEndpointURL.make(base: baseURL)) != nil else {
            throw LLMError.invalidURL
        }
        if prompt.sensitivity == .healthSensitive, !config.allowsHealthDataSharing {
            throw LLMError.healthDataConsentRequired
        }
        // Cloud provider: model is fixed server-side, skip the model check.
        if !config.isCloudProvider {
            guard let model = config.model, !model.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw LLMError.notConfigured
            }
            // 静默引用 model 避免 unused-warning(Linter 友好)
            _ = model
        }
    }

    private func printPromptToConsole(
        prompt: LLMPrompt,
        config: LLMConfig,
        caller: String
    ) {
        let systemPrompt = effectiveSystem(prompt: prompt, config: config)
        var messageBlocks = ""
        for (index, msg) in prompt.messages.enumerated() {
            messageBlocks += "[\(index + 1)] [\(msg.role.rawValue.uppercased())]:\n\(msg.content)\n"
        }
        let output = """
        ==================== LLM REQUEST PROMPT START [\(caller)] ====================
        Model: \(config.model ?? "nil")
        Temperature: \(config.temperature)
        Base URL: \(config.baseURL ?? "nil")
        -------------------- SYSTEM PROMPT --------------------
        \(systemPrompt)
        ---------------------- MESSAGES ----------------------
        \(messageBlocks)==================== LLM REQUEST PROMPT END ====================
        """
        // 通过 Log.llm(debug 级) 走统一日志系统;Release 默认 minCaptureLevel=.info 不会保留,
        // DEBUG 模式 verbose 开启时才进入 LogStore。
        // Route through the unified Log system at .debug level. Release builds
        // (minCaptureLevel=.info) drop it; DEBUG + verbose captures into LogStore.
        let sanitized = redact(output, secrets: [config.apiKey, config.sessionToken])
        Log.llm.debug("\(sanitized, privacy: .public)")
    }

    nonisolated private func buildURL(baseURL: String?) throws -> URL {
        guard let raw = baseURL else { throw LLMError.invalidURL }
        do {
            return try SecureEndpointURL.make(base: raw, appending: "v1/chat/completions")
        } catch {
            throw LLMError.invalidURL
        }
    }

    /// Cloud AI 网关端点: `{workerURL}/v1/chat`
    /// Cloud AI gateway endpoint.
    nonisolated private func buildCloudURL(baseURL: String?) throws -> URL {
        guard let raw = baseURL else { throw LLMError.invalidURL }
        do {
            return try SecureEndpointURL.make(base: raw, appending: "v1/chat")
        } catch {
            throw LLMError.invalidURL
        }
    }

    nonisolated private func buildBody(prompt: LLMPrompt, config: LLMConfig, stream: Bool) throws -> Data {
        // 手搓 JSON 避免引入外部 SDK
        // DEBUG 覆盖:非空时**完全替换**默认 system + appendix
        // DEBUG override: when non-empty, replace default system + appendix entirely.
        let effective = effectiveSystem(prompt: prompt, config: config)
        let allMessages = [LLMMessage.system(effective)] + prompt.messages
        var payload: [String: Any] = [
            "model": config.model ?? "",
            "temperature": max(0, min(2, config.temperature)),
            "stream": stream,
            "messages": allMessages.map { message in
                var body: [String: Any] = ["role": message.role.rawValue]
                if config.multimodalEnabled {
                    var parts: [[String: Any]] = [["type": "text", "text": message.content]]
                    parts.append(contentsOf: message.imageDataURLs.map {
                        ["type": "image_url", "image_url": ["url": $0]]
                    })
                    body["content"] = parts
                } else {
                    body["content"] = message.content
                }
                return body
            }
        ]
        // MiniMax does not accept the generic `enabled` value. Its OpenAI-
        // compatible endpoint uses `adaptive` / `disabled` instead.
        // Keep the old behavior for other providers for backwards compatibility.
        if isMiniMax(config: config) {
            payload["thinking"] = ["type": config.thinkingEnabled ? "adaptive" : "disabled"]
        } else if config.thinkingEnabled {
            payload["thinking"] = ["type": "enabled"]
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    /// 构建 Cloud AI 网关请求体：完整 messages + studypulse metadata。
    /// Official Cloud AI requests do not send a client-selected model.
    nonisolated private func buildCloudBody(prompt: LLMPrompt, config: LLMConfig, context: LLMRequestContext, stream: Bool = false) throws -> Data {
        let system = effectiveSystem(prompt: prompt, config: config)
        var allMessages: [[String: Any]] = []
        if !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            allMessages.append(["role": "system", "content": system])
        }
        for message in prompt.messages {
            var body: [String: Any] = ["role": message.role.rawValue]
            if config.multimodalEnabled, !message.imageDataURLs.isEmpty {
                var parts: [[String: Any]] = [["type": "text", "text": message.content]]
                parts.append(contentsOf: message.imageDataURLs.map {
                    ["type": "image_url", "image_url": ["url": $0, "detail": "default"]]
                })
                body["content"] = parts
            } else {
                body["content"] = message.content
            }
            allMessages.append(body)
        }
        let payload: [String: Any] = [
            "messages": allMessages,
            "stream": stream,
            "studypulse": cloudMetadata(context: context),
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    nonisolated private func cloudMetadata(context: LLMRequestContext) -> [String: Any] {
        var meta: [String: Any] = [
            "caller": context.caller,
            "thinking": context.thinking.rawValue,
        ]
        if let locale = context.locale?.trimmingCharacters(in: .whitespacesAndNewlines), !locale.isEmpty {
            meta["locale"] = locale
        }
        return meta
    }

    nonisolated private func isMiniMax(config: LLMConfig) -> Bool {
        if config.providerName?.localizedCaseInsensitiveContains("minimax") == true {
            return true
        }
        guard let baseURL = config.baseURL,
              let host = URL(string: baseURL)?.host?.lowercased() else {
            return false
        }
        return host.contains("minimaxi.com") || host.contains("minimax.io") || host.contains("minimax.chat")
    }

    /// 拼接最终 system prompt:`override` 优先,否则 `default + appendix`。
    /// Resolve the final system prompt: override takes precedence over default + appendix.
    nonisolated private func effectiveSystem(prompt: LLMPrompt, config: LLMConfig) -> String {
        if let override = config.overrideSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        return prompt.effectiveSystem(appendix: config.systemPromptAppendix)
    }

    /// 把一次调用写入 `lastCallInfo` + `recentCalls`,并 log 到 `Log.llm`。
    /// Record a call into `lastCallInfo` and `recentCalls`, and emit a Log.llm entry.
    private func recordCall(_ info: LLMCallDebugInfo, apiKey: String?, sessionToken: String?) {
        let sanitized = info.redacting(secrets: [apiKey, sessionToken])
        lastCallInfo = sanitized
        recentCalls.append(sanitized)
        if recentCalls.count > recentCallsLimit {
            recentCalls.removeFirst(recentCalls.count - recentCallsLimit)
        }
        let elapsedStr = String(format: "%.2fs", sanitized.elapsedSeconds)
        let okOrErr = sanitized.error == nil ? "OK" : "ERR: \(sanitized.error ?? "")"
        Log.llm.info("LLM call [\(sanitized.caller, privacy: .public)] \(sanitized.url, privacy: .public) elapsed=\(elapsedStr, privacy: .public) status=\(okOrErr, privacy: .public)")
    }

    private func validateHTTP(response: URLResponse, data: Data, secrets: [String?]) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.network("Non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw LLMError.unauthorized
        case 429: throw LLMError.rateLimited
        default:
            // 把响应体一并抛出,UI 才能看到 "Model not found" / "Invalid API key" 之类
            // Include the response body so the UI can show the server's real error message.
            let body = String(data: data, encoding: .utf8)
                .map { redact($0, secrets: secrets) }
            throw LLMError.serverError(statusCode: http.statusCode, body: body)
        }
    }

    nonisolated private func redact(_ text: String, secrets: [String?]) -> String {
        secrets.compactMap { $0 }.filter { !$0.isEmpty }.reduce(text) { partial, secret in
            partial.replacingOccurrences(of: secret, with: "<redacted>")
        }
    }

    // MARK: - Cloud AI Helpers

    /// 解析 Cloud AI 网关响应: `{"success": true, "data": {"reply": "..."}}`
    /// 或错误: `{"error": "..."}`。
    nonisolated private func parseCloudResponse(_ data: Data, httpResponse: HTTPURLResponse, secrets: [String?] = []) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.malformedResponse
        }
        if let error = json["error"] as? String {
            let data = (try? JSONSerialization.data(withJSONObject: ["error": error])) ?? Data()
            throw LLMError.cloudError(statusCode: httpResponse.statusCode, data: data, secrets: secrets)
        }
        if let errorObject = json["error"] as? [String: Any] {
            let data = (try? JSONSerialization.data(withJSONObject: ["error": errorObject])) ?? Data()
            throw LLMError.cloudError(statusCode: httpResponse.statusCode, data: data, secrets: secrets)
        }
        guard let dataObj = json["data"] as? [String: Any],
              let reply = dataObj["reply"] as? String else {
            throw LLMError.malformedResponse
        }
        return reply
    }
}

// MARK: - Log Category

extension Log {
    /// LLM BYOK 请求/响应/错误日志;不打印 API Key 明文。
    /// LLM BYOK request/response/error logs; never logs the raw API key.
    nonisolated static let llm = Logger(subsystem: subsystem, category: "LLM")
}
