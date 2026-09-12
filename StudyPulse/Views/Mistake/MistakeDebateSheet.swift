import SwiftUI

/// 错题“辩论”模式：AI 先发起质疑，学生逐轮为解法辩护。
struct MistakeDebateSheet: View {
    let mistake: MistakeNote
    let onDismiss: () -> Void

    @Environment(RepositoryContainer.self) private var container
    @State private var viewModel = MistakeDebateViewModel()
    @State private var inputText = ""
    @State private var difficulty: MistakeDebateDifficulty = .gentle

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AIChatFlowingBackground()
                    .ignoresSafeArea()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            difficultyPicker
                            if viewModel.messages.isEmpty {
                                emptyState
                            } else {
                                ForEach(viewModel.messages) { message in
                                    ChatBubble(
                                        role: message.role == .user ? .user : .assistant(dimmed: false),
                                        content: message.content,
                                        isStreaming: message.isStreaming,
                                        error: message.error,
                                        headerTag: message.role == .user ? "学生".localized() : "出题老师 · \(difficulty.title)"
                                    )
                                    .id(message.id)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 96)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: viewModel.messages.count) { _, _ in scrollToBottom(proxy) }
                    .onChange(of: viewModel.messages.last?.content ?? "") { _, _ in scrollToBottom(proxy) }
                }

                ChatInputBar(
                    text: $inputText,
                    placeholder: "为你的解法辩护…".localized(),
                    isStreaming: viewModel.isStreaming,
                    canSend: canSend,
                    onSend: send,
                    onCancel: { viewModel.cancel() }
                )
            }
            .containerBackground(.clear, for: .navigation)
            .llmDebugButton(caller: "MistakeDebate")
            .cloudThinkingToolbar()
            .navigationTitle("错题辩论".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close".localized()) {
                        viewModel.cancel()
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.restart(context: makeContext(), difficulty: difficulty, config: container.envManager.llmConfig)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .disabled(viewModel.isStreaming || !container.envManager.llmConfig.isConfigured)
                    .accessibilityLabel("重新开始辩论".localized())
                }
            }
            .onAppear {
                viewModel.startIfNeeded(context: makeContext(), difficulty: difficulty, config: container.envManager.llmConfig)
            }
            .onDisappear { viewModel.cancel() }
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isStreaming
            && container.envManager.llmConfig.isConfigured
    }

    private var difficultyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("选择老师风格".localized(), systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Picker("难度", selection: $difficulty) {
                ForEach(MistakeDebateDifficulty.allCases, id: \.self) { level in
                    Label(level.localizedTitle, systemImage: level.icon).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.hasStarted || viewModel.isStreaming)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: container.envManager.llmConfig.isConfigured ? "person.2.wave.2" : "brain")
                .font(.system(size: 44))
                .foregroundColor(.teal)
            Text(container.envManager.llmConfig.isConfigured
                 ? "老师会先质疑你的第一步。请不要只报答案，要解释为什么。".localized()
                 : "Set Base URL, API Key and Model in Settings → LLM.".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func send() {
        let text = inputText
        inputText = ""
        viewModel.send(text, difficulty: difficulty, config: container.envManager.llmConfig)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let id = viewModel.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .bottom) }
    }

    private func makeContext() -> String {
        var sections = [
            "学科：\(mistake.subject.isEmpty ? "(无)" : mistake.subject)",
            "标题：\(mistake.title)",
            "原题：\(mistake.originalQuestion.isEmpty ? "(无)" : mistake.originalQuestion)",
            "学生错误解法：\(mistake.wrongSolution.isEmpty ? "(无)" : mistake.wrongSolution)"
        ]
        if !mistake.errorReason.isEmpty { sections.append("已记录错因：\(mistake.errorReason)") }
        if !mistake.correctSolution.isEmpty { sections.append("参考正确解法（不要首轮直接公布）：\(mistake.correctSolution)") }
        return sections.joined(separator: "\n")
    }
}

@MainActor
@Observable
final class MistakeDebateViewModel {
    struct Message: Identifiable {
        let id = UUID()
        let role: LLMRole
        var content: String
        var isStreaming = false
        var error: String?
    }

    private(set) var messages: [Message] = []
    private(set) var isStreaming = false
    private(set) var hasStarted = false
    private var history: [LLMMessage] = []
    private var context = ""
    private var task: Task<Void, Never>?

    func startIfNeeded(context: String, difficulty: MistakeDebateDifficulty, config: LLMConfig) {
        guard !hasStarted, config.isConfigured else { return }
        hasStarted = true
        self.context = context
        request("请开始辩论：先针对学生的错误解法提出一个最关键、最值得辩护的问题。不要直接公布答案。", difficulty: difficulty, config: config)
    }

    func restart(context: String, difficulty: MistakeDebateDifficulty, config: LLMConfig) {
        cancel()
        messages.removeAll()
        history.removeAll()
        hasStarted = true
        self.context = context
        request("请重新开始辩论：先针对学生的错误解法提出一个最关键、最值得辩护的问题。不要直接公布答案。", difficulty: difficulty, config: config)
    }

    func send(_ text: String, difficulty: MistakeDebateDifficulty, config: LLMConfig) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming, config.isConfigured else { return }
        request(trimmed, difficulty: difficulty, config: config)
    }

    func cancel() { task?.cancel(); task = nil; isStreaming = false }

    private func request(_ userText: String, difficulty: MistakeDebateDifficulty, config: LLMConfig) {
        let userMessage = Message(role: .user, content: userText)
        messages.append(userMessage)
        history.append(.user(userText))
        let placeholder = Message(role: .assistant, content: "", isStreaming: true)
        messages.append(placeholder)
        isStreaming = true
        let prompt = LLMPrompt(
            system: MistakeDebateLLM.defaultSystem(context: context, difficulty: difficulty),
            messages: history
        )
        task = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await LLMClient.shared.stream(prompt: prompt, config: config, caller: "MistakeDebate") { snapshot in
                    Task { @MainActor in
                        guard let index = self.messages.lastIndex(where: { $0.id == placeholder.id }) else { return }
                        self.messages[index].content = snapshot
                    }
                }
                guard let index = self.messages.lastIndex(where: { $0.id == placeholder.id }) else { return }
                self.messages[index].isStreaming = false
                self.history.append(.assistant(self.messages[index].content))
            } catch is CancellationError {
                if let index = self.messages.lastIndex(where: { $0.id == placeholder.id }) {
                    self.messages[index].isStreaming = false
                    if self.messages[index].content.isEmpty { self.messages[index].content = "已暂停。".localized() }
                }
            } catch {
                if let index = self.messages.lastIndex(where: { $0.id == placeholder.id }) {
                    self.messages[index].isStreaming = false
                    self.messages[index].error = (error as? LLMError)?.errorDescription ?? error.localizedDescription
                }
            }
            self.isStreaming = false
            self.task = nil
        }
    }
}
