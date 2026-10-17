import SwiftUI
import SwiftStreamingMarkdown

struct CoachConversationView: View {
    @State private var viewModel: CoachConversationViewModel
    @State private var input = ""
    @State private var inputAttachments: [LLMImageAttachment] = []
    @State private var emptyPromptKey = CoachConversationPrompts.all.randomElement() ?? "Coach prompt 01"

    /// 从「问教练」预设问题进入时,自动发出的第一句。
    /// First message auto-sent when opened from a "Ask the coach" prompt.
    private let initialPrompt: String?
    @State private var didSendInitialPrompt = false

    init(goal: CoachGoal?, chat: CoachChat, container: RepositoryContainer, initialPrompt: String? = nil) {
        self.initialPrompt = initialPrompt
        _viewModel = State(initialValue: CoachConversationViewModel(goal: goal, chat: chat, container: container))
    }

    var body: some View {
        AIChatScaffold {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if viewModel.messages.isEmpty { emptyState }
                        ForEach(viewModel.messages) { message in
                            ChatBubble(role: message.role == .user ? .user : .assistant(dimmed: false),
                                       content: message.content,
                                       isStreaming: message.isStreaming,
                                       error: message.error,
                                       attachments: message.attachments,
                                       footer: message.todoSuggestions.isEmpty ? nil : AnyView(
                                           VStack(alignment: .leading, spacing: 8) {
                                               ForEach(message.todoSuggestions) { suggestion in
                                                   todoCard(messageID: message.id, suggestion: suggestion)
                                               }
                                           }
                                       ))
                            .id(message.id)
                        }
                    }
                    .aiChatMessageColumn(animatedBy: viewModel.messages.count)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: viewModel.messages.last?.content ?? "") { _, _ in scrollToBottom(proxy) }
            }
        } input: {
            ChatInputBar(text: $input, placeholder: "Message AI Coach...".localized(),
                         isStreaming: viewModel.isStreaming,
                         canSend: (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !inputAttachments.isEmpty)
                            && !viewModel.isStreaming
                            && viewModel.container.envManager.llmConfig.isConfigured,
                         onSend: send,
                         onCancel: viewModel.cancel,
                         multimodalEnabled: viewModel.container.envManager.llmConfig.multimodalEnabled,
                         attachments: $inputAttachments,
                         onSendWithImages: { attachments in send(attachments: attachments) })
        }
        .navigationTitle(viewModel.chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let initialPrompt, !didSendInitialPrompt, viewModel.messages.isEmpty,
                  viewModel.container.envManager.llmConfig.isConfigured else { return }
            didSendInitialPrompt = true
            viewModel.send(initialPrompt)
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Clear conversation".localized(), role: .destructive) { viewModel.clearConversation() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert("AI Coach".localized(), isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK".localized(), role: .cancel) { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.container.envManager.llmConfig.isConfigured {
            AIChatEmptyState(kind: .welcome(
                symbol: "brain.head.profile",
                title: "Your AI Coach is ready".localized(),
                message: emptyPromptKey.localized()
            ))
        } else {
            AIChatEmptyState(kind: .notConfigured())
        }
    }

    private func todoCard(messageID: UUID, suggestion: CoachTodoSuggestion) -> some View {
        let accent: Color = suggestion.taskType == .reading ? .purple : .green
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent)
                    .frame(width: 6)
                    .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(suggestion.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Label(suggestion.startDate.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
                .padding(.leading, 12)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .padding(.trailing, 14)
            .background(accent.opacity(0.34), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.28), lineWidth: 1))

            if suggestion.status == .pending {
                Button { viewModel.addTodoSuggestion(messageID: messageID, suggestionID: suggestion.id) } label: {
                    Label("Create", systemImage: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.green.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                Button("Ignore".localized(), role: .destructive) {
                    viewModel.dismissTodoSuggestion(messageID: messageID, suggestionID: suggestion.id)
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
            } else {
                Label(suggestion.status == .added ? "Created" : "Ignored", systemImage: suggestion.status == .added ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(suggestion.status == .added ? .green : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .scale(scale: 0.94)).combined(with: .opacity), removal: .opacity))
        .animation(.spring(response: 0.46, dampingFraction: 0.8), value: suggestion.status)
    }

    private func send() { send(attachments: inputAttachments) }

    private func send(attachments: [LLMImageAttachment]) {
        let text = input
        input = ""
        viewModel.send(text, attachments: attachments)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let id = viewModel.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .bottom) }
    }
}

private enum CoachConversationPrompts {
    static let all = [
        "Coach prompt 01", "Coach prompt 02", "Coach prompt 03", "Coach prompt 04", "Coach prompt 05",
        "Coach prompt 06", "Coach prompt 07", "Coach prompt 08", "Coach prompt 09", "Coach prompt 10",
        "Coach prompt 11", "Coach prompt 12", "Coach prompt 13", "Coach prompt 14", "Coach prompt 15"
    ]
}

/// Shared visual background for every LLM conversation surface.
/// Keeping this here preserves the AI Coach appearance as the canonical chat UI.
struct AIChatFlowingBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct LightSource {
        let color: Color
        let sizeRatio: CGFloat
        let x: CGFloat
        let y: CGFloat
        let driftX: CGFloat
        let driftY: CGFloat
        let speedX: Double
        let speedY: Double
        let colorSpeed: Double
        let phase: Double
    }

    private let lightSources: [LightSource] = [
        LightSource(color: .blue, sizeRatio: 1.55, x: 0.02, y: 0.04, driftX: 0.24, driftY: 0.08, speedX: 0.23, speedY: 0.17, colorSpeed: 0.31, phase: 0.8),
        LightSource(color: .cyan, sizeRatio: 1.42, x: 0.88, y: 0.10, driftX: 0.25, driftY: 0.11, speedX: 0.19, speedY: 0.13, colorSpeed: 0.27, phase: 2.4),
        LightSource(color: .yellow, sizeRatio: 1.36, x: 0.58, y: 0.20, driftX: 0.22, driftY: 0.12, speedX: 0.16, speedY: 0.21, colorSpeed: 0.29, phase: 4.1),
        LightSource(color: .white, sizeRatio: 1.48, x: 0.24, y: 0.38, driftX: 0.20, driftY: 0.10, speedX: 0.21, speedY: 0.15, colorSpeed: 0.25, phase: 5.7)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            GeometryReader { proxy in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    Color(.systemBackground)

                    ZStack(alignment: .topLeading) {
                        LinearGradient(
                            colors: [Color(red: 0.80, green: 0.90, blue: 1.0), Color(red: 0.94, green: 0.98, blue: 1.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        ForEach(Array(lightSources.enumerated()), id: \.offset) { _, source in
                            let size = proxy.size.width * source.sizeRatio
                            let x = proxy.size.width * (source.x + source.driftX * CGFloat(sin(time * source.speedX + source.phase)))
                            let y = proxy.size.height * (source.y + source.driftY * CGFloat(cos(time * source.speedY + source.phase)))
                            let pulse = 0.88 + 0.16 * sin(time * source.colorSpeed + source.phase)

                            RadialGradient(
                                colors: [
                                    source.color.opacity(0.90),
                                    source.color.opacity(0.48),
                                    source.color.opacity(0.14),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.54
                            )
                            .frame(width: size * 1.18, height: size * 0.82)
                            .scaleEffect(pulse)
                            .blur(radius: 42)
                            .hueRotation(.degrees(sin(time * source.colorSpeed * 0.72 + source.phase) * 22))
                            .rotationEffect(.degrees(sin(time * source.speedX * 0.64 + source.phase) * 10))
                            .offset(x: x - size * 0.59, y: y - size * 0.41)
                            .blendMode(.screen)
                        }
                    }
                    .compositingGroup()
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.42),
                                .init(color: .black.opacity(0.72), location: 0.56),
                                .init(color: .black.opacity(0.20), location: 0.74),
                                .init(color: .clear, location: 0.90)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
