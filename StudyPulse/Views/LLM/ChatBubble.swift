//
//  ChatBubble.swift
//  StudyPulse
//
//  统一的聊天消息气泡(user / assistant),三个聊天界面共用。
//  三个 chat 界面曾经各自实现气泡,样式 / 宽度 / 动画都各做各的;
//  这里是单一来源,以后再改样式只改这一处。
//
//  Unified chat bubble (user / assistant), shared by three chat UIs.
//  Previously each chat screen rendered its own bubble with its own
//  style / width / animation; this is the single source of truth.
//

import SwiftUI
import SwiftStreamingMarkdown

/// 统一的聊天气泡:user 右对齐小框;assistant 为玻璃胶囊头部 + 平铺内容(上限 600pt),
/// 只读上下文(dimmed)保留轻量卡片。样式积木见 `AIChatStyle.swift`。
/// 三个 chat 界面 (LLMChatView / AIDiscussionSheet / HomeAskSheet / MistakeDebateSheet / CoachConversationView) 都通过本组件渲染。
/// Unified chat bubble: user → right-aligned compact box,
/// assistant → glass-capsule header + flat content (max 600pt), dimmed context keeps a light card. Used by the three
/// chat screens (LLMChatView / AIDiscussionSheet / HomeAskSheet / MistakeDebateSheet / CoachConversationView).
struct ChatBubble: View {
    /// 气泡角色(user / assistant)
    /// Bubble role (user or assistant).
    enum Role {
        case user
        /// `dimmed: true` 用于"上一次的 AI 预测"等只读上下文,
        /// 背景色更弱、加细描边、整体降低不透明度
        /// `dimmed: true` is used for read-only contexts such as the
        /// "previous AI prediction" — weaker background, thin border,
        /// reduced overall opacity.
        case assistant(dimmed: Bool)

        /// 是否为 user 角色
        /// Whether this is a user bubble.
        var isUser: Bool {
            if case .user = self { return true }
            return false
        }
        /// 是否处于 dimmed 模式
        /// Whether this assistant bubble is dimmed.
        var isDimmed: Bool {
            if case .assistant(let d) = self { return d }
            return false
        }
    }

    /// 气泡角色
    /// Bubble role.
    let role: Role
    /// 文本内容
    /// Text content.
    let content: String
    /// 是否正在流式渲染
    /// Whether the content is currently being streamed in.
    let isStreaming: Bool
    /// 错误信息(若有,会覆盖正文显示)
    /// Error text (if set, replaces the body for display).
    let error: String?
    let attachments: [LLMImageAttachment]
    /// assistant 头部"AI"标签右侧的小文字(如 "·  身体 · 成绩" 或 "以下对话基于上一次的 AI 预测")
    /// Caption shown right of the "AI" header label
    /// (e.g. "·  body · grades" or "based on the previous AI prediction").
    let headerTag: String?
    /// 气泡下方的额外内容(HomeAsk 的"数据快照"折叠区)
    /// Optional footer content below the bubble
    /// (e.g. HomeAsk's collapsible "data snapshot" block).
    let footer: AnyView?
    /// 思考阶段的状态文案(如"正在判断需要哪些数据…");为空时显示扫光占位条
    /// Status line shown while thinking (e.g. "Routing…"); nil shows the sheen bars.
    let statusText: String?

    init(
        role: Role,
        content: String,
        isStreaming: Bool = false,
        error: String? = nil,
        attachments: [LLMImageAttachment] = [],
        headerTag: String? = nil,
        footer: AnyView? = nil,
        statusText: String? = nil
    ) {
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.error = error
        self.attachments = attachments
        self.headerTag = headerTag
        self.footer = footer
        self.statusText = statusText
    }

    var body: some View {
        Group {
            if role.isUser {
                userBubble
            } else {
                assistantBubble
            }
        }
        // 用户消息从右下角弹入;助手回复整块淡入并轻微上浮
        // User messages pop in from the bottom-trailing corner; replies fade in and rise slightly.
        .transition(role.isUser
            ? .asymmetric(
                insertion: .scale(scale: 0.8, anchor: .bottomTrailing)
                    .combined(with: .opacity)
                    .combined(with: .move(edge: .bottom)),
                removal: .opacity)
            : .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity))
    }

    // MARK: - User Bubble / 用户气泡

    private var userBubble: some View {
        HStack {
            // 至少 40pt 留白,让 user 气泡始终靠右
            // Reserve at least 40pt of trailing space so the user bubble
            // stays anchored to the right edge.
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 6) {
                Text(content)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.accentColor))
                    .frame(maxWidth: 320, alignment: .trailing)
                    .textSelection(.enabled)
                if !attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(attachments) { attachment in
                            CachedAsyncImage(data: attachment.data, maxDimension: 240)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Assistant Bubble / 助手气泡

    /// 是否处于"尚未收到首字"的思考态
    /// Whether the reply is still waiting for its first token.
    private var isThinking: Bool { error == nil && content.isEmpty && isStreaming }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            AIReplyHeader(
                tag: headerTag,
                isWorking: isStreaming,
                showsElapsed: isStreaming
            )
            if let err = error {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if isThinking {
                AIThinkingBody(
                    presentation: statusText.map { .text($0) } ?? .sheen
                )
            } else {
                MarkdownView(
                    text: content.normalisingSingleDollarMath(),
                    config: .chatConfig(isStreaming: isStreaming)
                )
                .textSelection(.enabled)
                // 流式输出中:正文下方跳点,表示还在继续生成
                // While streaming: bouncing dots under the text show it is still going.
                if isStreaming {
                    AIThinkingBody(presentation: .dots)
                        .transition(.opacity)
                }
            }
            if let footer {
                footer
            }
        }
        // 只读上下文(dimmed)保留轻量卡片;正常回复不加外框,让内容直接铺在背景上
        // Read-only context (dimmed) keeps a light card; normal replies sit flat on the background.
        .padding(role.isDimmed ? 12 : 0)
        .background {
            if role.isDimmed {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.tertiarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            }
        }
        .opacity(role.isDimmed ? 0.85 : 1.0)
        // iPad / 横屏下 600pt 上限,避免内容铺满整个窗口
        // 600pt cap on iPad / landscape so replies don't span the whole window.
        .frame(maxWidth: 600, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
