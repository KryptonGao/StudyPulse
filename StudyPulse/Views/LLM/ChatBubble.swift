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

/// 统一的聊天气泡:user 右对齐小框,assistant 左对齐宽框(上限 600pt)。
/// 三个 chat 界面 (LLMChatView / AIDiscussionSheet / HomeAskSheet) 都通过本组件渲染。
/// Unified chat bubble: user → right-aligned compact box,
/// assistant → left-aligned wide box (max 600pt). Used by the three
/// chat screens (LLMChatView / AIDiscussionSheet / HomeAskSheet).
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

    init(
        role: Role,
        content: String,
        isStreaming: Bool = false,
        error: String? = nil,
        attachments: [LLMImageAttachment] = [],
        headerTag: String? = nil,
        footer: AnyView? = nil
    ) {
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.error = error
        self.attachments = attachments
        self.headerTag = headerTag
        self.footer = footer
    }

    var body: some View {
        Group {
            if role.isUser {
                userBubble
            } else {
                assistantBubble
            }
        }
        // 新消息:从下方轻微上浮 + 渐入,跟聊天 App 习惯一致
        // New messages: float up slightly from below + fade in, matching
        // the convention of mainstream chat apps.
        .transition(.asymmetric(
            insertion: .scale(
                scale: 0.72,
                anchor: role.isUser ? .bottomTrailing : .bottomLeading
            )
            .combined(with: .opacity)
            .combined(with: .move(edge: .bottom)),
            removal: .opacity
        ))
        .animation(.spring(response: 0.38, dampingFraction: 0.58, blendDuration: 0.12), value: content)
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

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "brain")
                    .font(.caption)
                    .foregroundColor(.teal)
                Text("AI".localized())
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.teal)
                if let headerTag, !headerTag.isEmpty {
                    Text("·  " + headerTag)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if isStreaming {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.leading, 4)
                        .modifier(PulseModifier())
                }
                Spacer()
            }
            if let err = error {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            } else if content.isEmpty && isStreaming {
                HStack(spacing: 6) {
                    Text("Thinking...".localized())
                        .font(.body)
                        .foregroundColor(.secondary)
                    TypingDots()
                }
            } else {
                MarkdownView(
                    text: content.normalisingSingleDollarMath(),
                    config: .previewConfig
                )
                .textSelection(.enabled)
            }
            if let footer {
                footer
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(role.isDimmed
                      ? Color(.tertiarySystemBackground)
                      : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    role.isDimmed ? Color.secondary.opacity(0.25) : Color.clear,
                    lineWidth: 1
                )
        )
        .opacity(role.isDimmed ? 0.85 : 1.0)
        // 关键:iPad / 横屏下 600pt 上限,允许 AI 框随着屏幕变宽
        // KEY: 600pt cap on iPad / landscape so the AI box can still grow
        // with wider screens without spanning the full window.
        .frame(maxWidth: 600, alignment: .leading)
    }
}

// MARK: - 思考中动画(被 ChatBubble 使用,跨文件 internal)
// MARK: - Thinking animation (used by ChatBubble, internal across files)

/// 加载指示器周围的轻微脉动修饰符(0.9 ↔ 1.0)
/// Subtle pulse modifier (0.9 ↔ 1.0) wrapped around the loading indicator.
struct PulseModifier: ViewModifier {
    @State private var pulsing = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.15 : 0.95)
            .opacity(pulsing ? 0.6 : 1.0)
            // 0.9s easeInOut,无限往返,营造"心跳"感
            // 0.9s easeInOut, infinite reverse, gives a "heartbeat" feel.
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}

/// 三个点的打字机动画(··· 依次淡入)
/// Three-dot typing animation (each dot fades in in turn).
struct TypingDots: View {
    @State private var phase: Int = 0
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .opacity(phase == i ? 1.0 : 0.3)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                phase = (phase + 1) % 3
            }
        }
    }
}
