//
//  LLMChatView.swift
//  StudyPulse
//
//  AI 助手对话页:多轮对话 + Markdown 流式渲染。
//  对话历史仅 in-memory,离开页面或按 toolbar 的"清空"按钮释放。
//
//  AI assistant chat screen: multi-turn conversation with streamed
//  Markdown rendering. Conversation history is in-memory only and is
//  released on view disappearance or via the "clear" toolbar button.
//
//  UI 统一(2026-07-11):使用共享 ChatBubble + ChatInputBar,
//  跟 AIDiscussionSheet / HomeAskSheet 保持一致的输入框样式和气泡外观。
//  UI unification (2026-07-11): uses the shared ChatBubble + ChatInputBar,
//  keeping style consistent with AIDiscussionSheet / HomeAskSheet.
//

import SwiftUI
import SwiftStreamingMarkdown

/// AI 助手对话页(单页入口,无上下文绑定)。
/// LLM assistant chat screen (standalone entry, no external context binding).
struct LLMChatView: View {
    @Environment(RepositoryContainer.self) private var container
    @State private var viewModel = LLMChatViewModel()
    /// 输入框文本
    /// Input bar text.
    @State private var inputText: String = ""
    @State private var inputAttachments: [LLMImageAttachment] = []

    var body: some View {
        AIChatScaffold {
            messagesList
        } input: {
            ChatInputBar(
                text: $inputText,
                isStreaming: viewModel.isStreaming,
                canSend: canSend,
                onSend: send,
                onCancel: { viewModel.cancel() },
                multimodalEnabled: container.envManager.llmConfig.multimodalEnabled,
                attachments: $inputAttachments,
                onSendWithImages: { attachments in send(attachments: attachments) }
            )
        }
        .debugModeContainer()
        .debugLayoutBoundsAuto()
        .llmDebugButton(caller: "LLMChat")
        .cloudThinkingToolbar()
        .navigationTitle("AI Assistant".localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                AIChatTrailingAction(
                    isStreaming: viewModel.isStreaming,
                    canClear: !viewModel.messages.isEmpty,
                    onStop: { viewModel.cancel() },
                    onClear: { viewModel.reset() }
                )
            }
        }
    }

    private var canSend: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!trimmed.isEmpty || !inputAttachments.isEmpty) && !viewModel.isStreaming && container.envManager.llmConfig.isConfigured
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
                                role: message.role == .user ? .user : .assistant(dimmed: false),
                                content: message.content,
                                isStreaming: message.isStreaming,
                                error: message.error,
                                attachments: message.attachments
                            )
                            .id(message.id)
                        }
                    }
                    .aiChatMessageColumn(animatedBy: viewModel.messages.count)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.messages.last?.content ?? "") { _, _ in
                scrollToBottom(proxy: proxy)
            }
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
                title: "Start a conversation".localized(),
                message: "Ask about your grades, mistakes, or exams.".localized()
            ))
        }
    }

    // MARK: - Helpers / 辅助方法

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        // 150ms 缓出,让流式追加时不出现硬切
        // 150ms ease-out avoids hard cuts during streaming appends.
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func send() {
        send(attachments: inputAttachments)
    }

    private func send(attachments: [LLMImageAttachment]) {
        let text = inputText
        inputText = ""
        // 清空输入框后立刻把消息交给 viewModel
        // Hand off the message to the view model right after clearing the input.
        viewModel.sendUserMessage(text, attachments: attachments, config: container.envManager.llmConfig, envManager: container.envManager)
    }
}
