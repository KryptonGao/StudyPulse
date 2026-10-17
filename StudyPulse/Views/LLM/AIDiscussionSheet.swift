//
//  AIDiscussionSheet.swift
//  StudyPulse
//
//  "深入探讨" 对话 sheet:从 AI 预测/分析结果入口打开,让用户基于
//  给定上下文与 LLM 多轮深入对话。
//  Deep-discussion chat sheet: opened from an AI prediction / analysis
//  result, allowing the user to have a multi-turn conversation with the
//  LLM on top of a given context.
//
//  UI 关键点:
//  - 顶部 header 简要显示当前上下文来源(预测 / 错题 / 周报)
//  - 中部:滚动对话历史,user 右对齐,assistant 左对齐 + MarkdownView 流式
//  - 底部输入框:共享 ChatInputBar(iOS 26 `glassEffect` 浮动胶囊)
//
//  UI 统一(2026-07-11):使用共享 ChatBubble + ChatInputBar,
//  跟 LLMChatView / HomeAskSheet 保持一致。
//  UI unification (2026-07-11): uses the shared ChatBubble + ChatInputBar,
//  keeping style consistent with LLMChatView / HomeAskSheet.
//

import SwiftUI
import SwiftStreamingMarkdown

/// "深入探讨" sheet:在已有 AI 预测/分析的基础上,让用户跟 LLM 多轮追问。
/// Deep-discussion sheet: lets the user follow up on a previous AI
/// prediction / analysis through multi-turn chat.
struct AIDiscussionSheet: View {
    /// 标题(显示在 navigation bar)
    /// Title shown in the navigation bar.
    let title: String
    /// 上下文(喂给 system prompt)
    /// Context block fed into the system prompt.
    let context: String
    /// 初始 assistant 消息(显示在对话历史开头;通常 = 上一步 AI 预测原文)
    /// Initial assistant message shown at the top of the conversation
    /// (typically the previous AI prediction text).
    let initialAssistantMessage: String?
    /// 退出回调
    /// Dismiss callback.
    let onDismiss: () -> Void
    /// Whether the context includes HealthKit/recovery data.
    let containsHealthData: Bool

    @Environment(RepositoryContainer.self) private var container
    @State private var viewModel = AIDiscussionViewModel()
    /// 当前输入框文本
    /// Current input bar text.
    @State private var inputText: String = ""

    init(
        title: String,
        context: String,
        initialAssistantMessage: String?,
        containsHealthData: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.context = context
        self.initialAssistantMessage = initialAssistantMessage
        self.containsHealthData = containsHealthData
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            AIChatScaffold {
                messagesList
            } input: {
                ChatInputBar(
                    text: $inputText,
                    isStreaming: viewModel.isStreaming,
                    canSend: canSend,
                    onSend: send,
                    onCancel: { viewModel.cancel() }
                )
            }
            .llmDebugButton(caller: "AIDiscussion")
            .cloudThinkingToolbar()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close".localized()) {
                        viewModel.cancel()
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    AIChatTrailingAction(
                        isStreaming: viewModel.isStreaming,
                        canClear: !viewModel.messages.isEmpty,
                        onStop: { viewModel.cancel() },
                        onClear: { viewModel.reset() }
                    )
                }
            }
            .onAppear {
                viewModel.bootstrap(
                    context: context,
                    initialAssistantMessage: initialAssistantMessage,
                    containsHealthData: containsHealthData
                )
            }
            .onDisappear { viewModel.cancel() }
        }
    }

    private var canSend: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !viewModel.isStreaming && container.envManager.llmConfig.isConfigured
    }

    // MARK: - Messages List / 消息列表

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(
                                role: message.role == .user
                                    ? .user
                                    : .assistant(dimmed: message.isInitialContext),
                                content: message.content,
                                isStreaming: message.isStreaming,
                                error: message.error,
                                headerTag: message.isInitialContext
                                    ? "以下对话基于上一次的 AI 预测".localized()
                                    : nil
                            )
                            .id(message.id)
                        }
                    }
                    .aiChatMessageColumn(animatedBy: viewModel.messages.count)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in scrollToBottom(proxy: proxy) }
            .onChange(of: viewModel.messages.last?.content ?? "") { _, _ in scrollToBottom(proxy: proxy) }
        }
    }

    // MARK: - Empty State / 空态

    @ViewBuilder
    private var emptyState: some View {
        if !container.envManager.llmConfig.isConfigured {
            AIChatEmptyState(kind: .notConfigured())
        } else {
            AIChatEmptyState(kind: .welcome(
                symbol: "bubble.left.and.bubble.right",
                title: "Ask anything".localized(),
                message: nil
            ))
        }
    }

    // MARK: - Helpers / 辅助方法

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        // 150ms 缓出动画,避免流式追加时的硬切
        // 150ms ease-out to avoid hard cuts during streaming appends.
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func send() {
        let text = inputText
        inputText = ""
        // 清空输入框后立刻把消息交给 viewModel
        // Hand off the text to the view model right after clearing the input.
        viewModel.sendUserMessage(text, config: container.envManager.llmConfig)
    }
}

// MARK: - View Model / 视图模型

@MainActor
@Observable
final class AIDiscussionViewModel {
    struct Message: Identifiable, Equatable {
        let id: UUID
        let role: LLMRole
        var content: String
        var isStreaming: Bool
        var error: String?
        /// 标记这条消息是不是"上一次的 AI 预测"(只用于 UI 显示,不会发给 LLM)
        /// Whether this message is the "previous AI prediction" (UI only, not sent to LLM).
        var isInitialContext: Bool = false

        init(
            id: UUID = UUID(),
            role: LLMRole,
            content: String = "",
            isStreaming: Bool = false,
            error: String? = nil,
            isInitialContext: Bool = false
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.isStreaming = isStreaming
            self.error = error
            self.isInitialContext = isInitialContext
        }
    }

    var messages: [Message] = []
    var isStreaming: Bool = false
    private var context: String = ""
    private var containsHealthData = false
    /// 上一次的 AI 预测原文(只用于拼装 system prompt;不会作为 conversation history 发送,
    /// 因为 `assistant` 角色没有前导 user 消息会让部分 LLM 困惑 / 遗忘)。
    /// Previous AI prediction text (only used to assemble the system prompt;
    /// never sent as part of the conversation history because an `assistant`
    /// message without a leading user message can confuse / make some LLMs forget).
    private var previousAIPrediction: String? = nil
    private var currentTask: Task<Void, Never>? = nil

    /// 初始化对话:把"上一步的 AI 预测"作为初始 assistant 消息(只用于 UI 显示),
    /// 并把同一段内容存到 `previousAIPrediction`,后续每次发请求都会作为 system 上下文喂给 LLM。
    /// Bootstrap the conversation: append the "previous AI prediction" as an
    /// initial assistant message (UI only) and stash the same text in
    /// `previousAIPrediction` so it is fed to the LLM as system context on
    /// every subsequent request.
    func bootstrap(context: String, initialAssistantMessage: String?, containsHealthData: Bool = false) {
        guard messages.isEmpty else { return }
        self.context = context
        self.containsHealthData = containsHealthData
        if let initial = initialAssistantMessage, !initial.isEmpty {
            previousAIPrediction = initial
            messages.append(
                Message(role: .assistant, content: initial, isStreaming: false, isInitialContext: true)
            )
        }
    }

    func reset() {
        currentTask?.cancel()
        currentTask = nil
        messages.removeAll()
        isStreaming = false
        // 注意:reset 会清掉 previousAIPrediction,确保清空后没有遗留上下文
        // NOTE: reset also clears previousAIPrediction to ensure no leftover
        // context leaks after a clean slate.
        previousAIPrediction = nil
    }

    func cancel() {
        currentTask?.cancel()
    }

    func sendUserMessage(_ text: String, config: LLMConfig) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming, config.isConfigured else { return }

        // 1) user message
        messages.append(Message(role: .user, content: trimmed))

        // 2) assistant 占位
        let placeholder = Message(role: .assistant, content: "", isStreaming: true)
        messages.append(placeholder)

        // 3) 构造发给 LLM 的 history
        // 关键:不要把"上一次的 AI 预测"那条 initial assistant 消息放进 history
        // (assistant 没有前导 user 消息,会让 LLM 困惑 / 遗忘);
        // 它已经通过 system prompt 里的"你刚才已经给出的预测"段落显式喂给 LLM。
        // KEY: do NOT include the "previous AI prediction" initial assistant
        // message in the history (assistant without a leading user message
        // confuses some LLMs); the same text is fed via the system prompt
        // under "the prediction you just gave" instead.
        let history: [LLMMessage] = messages
            .filter { $0.id != placeholder.id && !$0.isInitialContext }
            .map { LLMMessage(role: $0.role, content: $0.content) }
        let system = AIDiscussionLLM.defaultSystem(
            context: context,
            previousAIPrediction: previousAIPrediction
        )
        let prompt = LLMPrompt(
            system: system,
            messages: history,
            sensitivity: containsHealthData ? .healthSensitive : .ordinary
        )

        isStreaming = true
        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await LLMClient.shared.stream(prompt: prompt, config: config, caller: "AIDiscussion") { snapshot in
                    Task { @MainActor in
                        if let lastIdx = self.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                            self.messages[lastIdx].content = snapshot
                        }
                    }
                }
                if let lastIdx = self.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                    self.messages[lastIdx].isStreaming = false
                }
            } catch is CancellationError {
                if let lastIdx = self.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                    if self.messages[lastIdx].content.isEmpty {
                        self.messages[lastIdx].content = "[Cancelled]".localized()
                    }
                    self.messages[lastIdx].isStreaming = false
                }
            } catch {
                if let lastIdx = self.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                    let desc = (error as? LLMError)?.errorDescription ?? error.localizedDescription
                    self.messages[lastIdx].error = desc
                    self.messages[lastIdx].isStreaming = false
                    if self.messages[lastIdx].content.isEmpty {
                        self.messages[lastIdx].content = "**Error**: \(desc)"
                    }
                }
            }
            self.isStreaming = false
            self.currentTask = nil
        }
    }
}
