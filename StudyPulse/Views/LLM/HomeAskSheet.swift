//
//  HomeAskSheet.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/7/11.
//
//  主页 AI 提问 sheet。
//  - 头部:会话标题 + 阶段指示器(路由 / 抓取 / 回答) + 关闭/清空按钮
//  - 主体:多轮消息流,每条 assistant 消息可展开看路由 / 数据快照
//  - 底部:共享 ChatInputBar(Liquid Glass 浮动)
//
//  Home screen AI question sheet.
//  - Header: title + phase indicator (routing / fetching / answering) + close/clear buttons
//  - Body: multi-turn message stream, each assistant message can expand to show the route / data snapshot
//  - Bottom: shared ChatInputBar (floating Liquid Glass)
//
//  UI 统一(2026-07-11):使用共享 ChatBubble + ChatInputBar,
//  跟 LLMChatView / AIDiscussionSheet 保持一致。
//  UI unification (2026-07-11): uses the shared ChatBubble + ChatInputBar,
//  keeping style consistent with LLMChatView / AIDiscussionSheet.
//

import SwiftUI
import SwiftStreamingMarkdown

/// 主页 AI 提问 sheet:由 home 上的 "Ask AI" 入口打开。
/// Home-screen AI question sheet: opened from the "Ask AI" entry on Home.
/// LLM 会先做一次"路由"(决定需要哪些数据),再合并上下文给最终回答。
/// The LLM first "routes" the question (decides which data to fetch),
/// then merges the context for the final answer.
struct HomeAskSheet: View {
    @State private var viewModel: HomeAskViewModel
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    /// 输入框焦点状态(用于 example chip 点击后弹出键盘)
    /// Input focus state (used so tapping an example chip pops the keyboard).
    @FocusState private var inputFocused: Bool
    @State private var showingHealthDataConsent = false
    
    /// 预设的初始提问内容
    /// Injected initial question.
    private let initialQuestion: String?

    init(container: RepositoryContainer, envManager: AppEnvironmentManager, initialQuestion: String? = nil) {
        self.initialQuestion = initialQuestion
        _viewModel = State(
            initialValue: HomeAskViewModel(container: container, envManager: envManager)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AIChatFlowingBackground()
                    .ignoresSafeArea()
                if !viewModel.envManager.llmConfig.isConfigured {
                    notConfiguredView
                } else if viewModel.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }
                ChatInputBar(
                    text: $viewModel.inputText,
                    isStreaming: viewModel.phase != .idle,
                    canSend: canSend,
                    onSend: {
                        let text = viewModel.inputText
                        viewModel.send(text)
                    },
                    onCancel: { viewModel.cancel() }
                )
            }
            .containerBackground(.clear, for: .navigation)
            .navigationTitle("Ask AI".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close".localized()) {
                        viewModel.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.phase != .idle {
                        Button {
                            viewModel.cancel()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                        }
                    } else if !viewModel.messages.isEmpty {
                        Button(role: .destructive) {
                            viewModel.reset()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Clear".localized())
                    }
                }
            }
        }
        .llmDebugButton(caller: "HomeAsk-Answer")
        .onDisappear { viewModel.cancel() }
        .onChange(of: viewModel.shouldRequestHealthDataConsent) { _, newValue in
            showingHealthDataConsent = newValue
        }
        .sheet(isPresented: $showingHealthDataConsent) {
            HealthDataLLMConsentSheet { allowed in
                if allowed {
                    viewModel.retryAfterHealthDataConsent()
                } else {
                    viewModel.shouldRequestHealthDataConsent = false
                }
            }
            .environment(container)
        }
        .onAppear {
            // 如果传入了初始问题，且当前无对话记录，则自动触发发送
            // Automatically submit the initial question on appear if present and conversation is empty.
            if let initialQuestion, !initialQuestion.isEmpty, viewModel.messages.isEmpty {
                viewModel.send(initialQuestion)
            }
        }
    }

    // MARK: - Empty / not configured / 空态 / 未配置

    private var notConfiguredView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("未配置大模型".localized())
                .font(.headline)
            Text("前往 设置 → AI 设置,填入 Base URL / API Key 后即可使用".localized())
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 48))
                .foregroundStyle(LinearGradient(
                    colors: [.teal, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text("Ask AI".localized())
                .font(.title2.weight(.semibold))
            Text("问我关于你的身体状态、成绩、趋势、复习建议的问题。\n我会先判断需要哪些数据,再合并上下文给你回答。".localized())
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // 推荐提问样例
            VStack(spacing: 8) {
                exampleChip("今天适合做难题吗?".localized())
                exampleChip("我最近的数学成绩怎么样?".localized())
                exampleChip("本周学习时间够不够?".localized())
                exampleChip("现在应该复习什么?".localized())
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    private func exampleChip(_ text: String) -> some View {
        Button {
            inputFocused = true
            viewModel.inputText = text
        } label: {
            Text(text)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(Color(.tertiarySystemBackground))
                )
                .overlay(
                    Capsule().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message list / 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                    if viewModel.phase != .idle {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text(phaseLabel(viewModel.phase))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                        .id("phase-indicator")
                    }
                    // 96pt 占位 = ChatInputBar 高度 + 一点安全边距
                    // 96pt placeholder = ChatInputBar height + a bit of safe padding.
                    Color.clear.frame(height: 96).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                // 驱动 bubble 进出场 transition
                // Drives bubble enter/exit transitions.
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: viewModel.messages.count)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private func phaseLabel(_ phase: HomeAskViewModel.Phase) -> String {
        switch phase {
        case .idle: return ""
        case .routing: return "正在判断需要哪些数据…".localized()
        case .answering: return "正在生成回答…".localized()
        }
    }

    @ViewBuilder
    private func messageRow(_ message: HomeAskViewModel.Message) -> some View {
        switch message.role {
        case .user:
            ChatBubble(
                role: .user,
                content: message.content
            )
        case .assistant:
            ChatBubble(
                role: .assistant(dimmed: false),
                content: message.content,
                isStreaming: message.isStreaming,
                error: message.error,
                headerTag: message.routingCategories.isEmpty
                    ? nil
                    : message.routingCategories.map(categoryDisplayName).joined(separator: " · "),
                footer: message.dataSnapshot.isEmpty
                    ? nil
                    : AnyView(DataSnapshotBlock(snapshot: message.dataSnapshot))
            )
        case .system:
            VStack(alignment: .leading, spacing: 4) {
                Text(message.content)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                if message.isStreaming {
                    ProgressView()
                        .scaleEffect(0.55)
                        .modifier(PulseModifier())
                }
            }
        case .tool:
            // Tool messages are not surfaced in this UI (LLM is a pure chat flow)
            // Tool 消息不在此 UI 展示(LLM 是纯 chat 流程)
            EmptyView()
        }
    }

    /// 路由分类的本地化展示名
    /// Localized display name for a routing category.
    private func categoryDisplayName(_ c: HomeAskRouterLLM.Category) -> String {
        switch c {
        case .body:   return "身体".localized()
        case .grades: return "成绩".localized()
        case .trends: return "趋势".localized()
        case .review: return "复习".localized()
        }
    }

    /// 发送条件:有内容 + 空闲
    /// Send condition: has content + idle phase.
    private var canSend: Bool {
        let trimmed = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && viewModel.phase == .idle
    }
}

// MARK: - Data Snapshot (可折叠)
// MARK: - Data snapshot (collapsible)

/// 助手消息下方的"数据快照"折叠区。
/// 展示 AI 路由阶段抓取到的真实数据,方便用户审计 AI 的回答。
/// Collapsible "data snapshot" block under each assistant message.
/// Shows the raw data the LLM grabbed during routing, so the user can
/// audit the AI's answer.
private struct DataSnapshotBlock: View {
    let snapshot: String
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.caption2)
                    Text(expanded ? "隐藏数据快照".localized() : "查看数据快照".localized())
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            if expanded {
                Text(snapshot)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
