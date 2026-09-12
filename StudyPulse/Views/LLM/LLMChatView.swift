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
    /// 输入框焦点状态
    /// Input focus state.
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            AIChatFlowingBackground()
                .ignoresSafeArea()
            messagesList
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
        .containerBackground(.clear, for: .navigation)
        .debugModeContainer()
        .debugLayoutBoundsAuto()
        .llmDebugButton(caller: "LLMChat")
        .cloudThinkingToolbar()
        .navigationTitle("AI Assistant".localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isStreaming {
                    Button {
                        viewModel.cancel()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                    }
                } else {
                    Button {
                        viewModel.reset()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(viewModel.messages.isEmpty)
                }
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
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    LazyVStack(spacing: 12) {
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
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    // 驱动 bubble 进出场的 transition
                    // Drives bubble enter/exit transitions.
                    .animation(.spring(response: 0.35, dampingFraction: 0.78), value: viewModel.messages.count)
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            if !container.envManager.llmConfig.isConfigured {
                Image(systemName: "brain")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                Text("LLM Not Configured".localized())
                    .font(.headline)
                Text("Set Base URL, API Key and Model in Settings → LLM.".localized())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                NavigationLink(destination: LLMSettingsView()) {
                    Label("Open LLM Settings".localized(), systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                Text("Start a conversation".localized())
                    .font(.headline)
                Text("Ask about your grades, mistakes, or exams.".localized())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
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
