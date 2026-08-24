//
//  HomeAskViewModel.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/7/11.
//
//  主页 AI 提问 sheet 的 ViewModel。两阶段:路由 → 抓取 → 流式回答。
//  多轮对话:每轮都重跑 1→2→3,确保 LLM 看到最新数据 + 完整历史。
//  Home-page AI question sheet VM. Two-stage: route → fetch → stream.
//  Multi-turn: each turn re-runs 1→2→3 so the LLM always sees fresh data.
//

import Foundation
import SwiftUI
import os

@MainActor
@Observable
final class HomeAskViewModel {
    /// 单条对话消息(支持流式累积 / 错误 / 路由标签)
    /// Single chat message (streaming accumulation, error, routing tag).
    struct Message: Identifiable, Equatable {
        let id: UUID
        let role: LLMRole
        var content: String
        var isStreaming: Bool
        var error: String?
        /// 路由阶段确定的类别(右上角小标签)
        /// Categories from routing (small tag at top-right).
        var routingCategories: [HomeAskRouterLLM.Category] = []
        var routingReasoning: String = ""
        /// 抓取到的数据快照(折叠区展示)
        /// Fetched data snapshot (shown in a collapsible area).
        var dataSnapshot: String = ""

        init(
            id: UUID = UUID(),
            role: LLMRole,
            content: String = "",
            isStreaming: Bool = false,
            error: String? = nil,
            routingCategories: [HomeAskRouterLLM.Category] = [],
            routingReasoning: String = "",
            dataSnapshot: String = ""
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.isStreaming = isStreaming
            self.error = error
            self.routingCategories = routingCategories
            self.routingReasoning = routingReasoning
            self.dataSnapshot = dataSnapshot
        }
    }

    /// 当前阶段(驱动 loading 文案) / Current stage (drives loading text).
    enum Phase: Equatable {
        case idle
        case routing
        case answering
    }

    /// 完整对话历史 / Full conversation history.
    var messages: [Message] = []
    /// 当前阶段 / Current stage.
    var phase: Phase = .idle
    /// 用户正在输入的文本 / In-progress user text.
    var inputText: String = ""
    /// The view presents the shared consent sheet when a body-data answer is blocked.
    var shouldRequestHealthDataConsent: Bool = false
    /// 数据抓取器 / Data fetcher.
    var dataProvider: HomeAskDataProvider
    /// LLM 环境配置管理器 / LLM env config manager.
    let envManager: AppEnvironmentManager
    /// 当前正在运行的 LLM 任务 / Currently running LLM task.
    private var currentTask: Task<Void, Never>? = nil
    private var pendingHealthConsentQuestion: String?

    init(container: RepositoryContainer, envManager: AppEnvironmentManager) {
        self.envManager = envManager
        self.dataProvider = HomeAskDataProvider(
            container: container,
            hrvManager: HealthKitManager.shared,
            profile: container.profileRepo.profile
        )
    }

    // MARK: - 生命周期 / Lifecycle
    /// 取消当前 LLM 任务(保留历史) / Cancel the in-flight LLM task.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    /// 完全重置 / Full reset.
    func reset() {
        cancel()
        messages.removeAll()
        phase = .idle
        shouldRequestHealthDataConsent = false
        pendingHealthConsentQuestion = nil
    }

    // MARK: - 发送 / Sending
    /// 发送问题。两阶段:路由 → 抓取 → 流式回答
    /// Send a user question. Two-stage: route → fetch → stream.
    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 三道闸:非空、当前空闲、LLM 已配置
        // Three guards: non-empty, idle, LLM configured.
        guard !trimmed.isEmpty,
              phase == .idle,
              envManager.llmConfig.isConfigured
        else { return }

        // 1) 把用户消息加入历史
        // 1) Append user message to history.
        messages.append(Message(role: .user, content: trimmed))
        inputText = ""

        // 2) assistant 占位 / Add empty assistant placeholder.
        let placeholder = Message(role: .assistant, content: "", isStreaming: true)
        messages.append(placeholder)

        // 启动 detached 任务执行两阶段管线
        // Kick off the two-stage pipeline in a detached task.
        currentTask = Task { [weak self] in
            await self?.runPipeline(userText: trimmed, placeholderId: placeholder.id)
        }
    }

    /// 两阶段管线执行体 / The two-stage pipeline body.
    private func runPipeline(userText: String, placeholderId: UUID) async {
        let config = envManager.llmConfig
        guard config.isConfigured else {
            updateMessage(id: placeholderId) { $0.error = "请先在设置中配置大模型".localized(); $0.isStreaming = false }
            phase = .idle
            return
        }

        // === 阶段 1: 路由 === / Stage 1: routing
        phase = .routing
        // 兜底:默认拉取全部分类 / Fallback: all categories.
        var routing = HomeAskRouterLLM.Routing(
            categories: HomeAskRouterLLM.Category.allCases,
            reasoning: "兜底:全部分类"
        )
        do {
            let routePrompt = HomeAskRouterLLM.makePrompt(question: userText)
            var routeOutput = ""
            _ = try await LLMClient.shared.stream(prompt: routePrompt, config: config) { snapshot in
                routeOutput = snapshot
            }
            routing = HomeAskRouterLLM.parse(routeOutput)
            Log.llm.info("HomeAsk route: \(routing.categories.map(\.rawValue).joined(separator: ","), privacy: .public)")
        } catch is CancellationError {
            updateMessage(id: placeholderId) { $0.isStreaming = false; $0.error = "已取消".localized() }
            phase = .idle
            return
        } catch {
            Log.llm.error("HomeAsk routing failed: \(error.localizedDescription, privacy: .public)")
            // 路由失败 → 默认全部分类 / Fallback on failure.
        }
        // 把路由结果写到 placeholder(供 UI 显示分类标签)
        // Write the routing decision back to the placeholder.
        updateMessage(id: placeholderId) {
            $0.routingCategories = routing.categories
            $0.routingReasoning = routing.reasoning
        }

        // === 阶段 2: 抓取数据 === / Stage 2: fetch data
        let dataSections = dataProvider.fetch(categories: routing.categories)
        let dataBlock = dataSections.joined(separator: "\n\n")
        updateMessage(id: placeholderId) { $0.dataSnapshot = dataBlock }

        // === 阶段 3: 流式回答 === / Stage 3: stream the answer
        phase = .answering
        let answerPrompt = HomeAskAnswerLLM.makePrompt(
            question: userText,
            activeCategories: routing.categories,
            dataSections: dataSections
        )
        do {
            _ = try await LLMClient.shared.stream(prompt: answerPrompt, config: config, caller: "HomeAsk-Answer") { [weak self] snapshot in
                self?.updateMessage(id: placeholderId) { $0.content = snapshot }
            }
            updateMessage(id: placeholderId) { $0.isStreaming = false }
        } catch is CancellationError {
            updateMessage(id: placeholderId) { $0.isStreaming = false; $0.error = "已取消".localized() }
        } catch let error as LLMError {
            let desc = error.errorDescription ?? error.localizedDescription
            updateMessage(id: placeholderId) { $0.isStreaming = false; $0.error = desc }
            if error == .healthDataConsentRequired {
                pendingHealthConsentQuestion = userText
                shouldRequestHealthDataConsent = true
            }
            Log.llm.error("HomeAsk answer failed: \(error.localizedDescription, privacy: .public)")
        } catch {
            let desc = error.localizedDescription
            updateMessage(id: placeholderId) { $0.isStreaming = false; $0.error = desc }
            Log.llm.error("HomeAsk answer failed: \(desc, privacy: .public)")
        }
        phase = .idle
    }

    /// Re-runs the last blocked answer after the user grants health-data sharing.
    /// The existing user message is retained while its failed assistant bubble is replaced.
    func retryAfterHealthDataConsent() {
        guard let question = pendingHealthConsentQuestion,
              phase == .idle else { return }
        pendingHealthConsentQuestion = nil
        shouldRequestHealthDataConsent = false
        if let index = messages.lastIndex(where: { $0.role == .assistant && $0.error != nil }) {
            messages.remove(at: index)
        }
        let placeholder = Message(role: .assistant, content: "", isStreaming: true)
        messages.append(placeholder)
        currentTask = Task { [weak self] in
            await self?.runPipeline(userText: question, placeholderId: placeholder.id)
        }
    }

    /// 按 id 找到消息并 mutate / Find a message by id and mutate it.
    private func updateMessage(id: UUID, _ mutate: (inout Message) -> Void) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[idx])
    }
}
