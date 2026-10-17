//
//  AIChatStyle.swift
//  StudyPulse
//
//  所有 AI 对话界面共用的样式积木:
//  - AIChatScaffold:背景 + 内容 + 底部输入框的统一骨架
//  - AIReplyHeader:回复头部的玻璃胶囊(呼吸的星芒 + 名称 + 标签 + 已思考秒数)
//  - AIThinkingBody / AIThinkingState:回复尚未开始时的占位(扫光条 / 跳点 / 状态文案)
//  - AIChatEmptyState:空态 / 未配置态
//  - AIPromptChips:推荐提问
//  - AIChatTrailingAction:导航栏右侧的"停止 / 清空"
//
//  Shared style building blocks for every AI conversation surface:
//  scaffold, reply header pill, thinking placeholder, empty / not-configured
//  state, prompt chips and the trailing toolbar action.
//
//  动效约定:Reduce Motion 下不位移,只做透明度变化;Reduce Transparency 由系统玻璃自行降级。
//  Motion: under Reduce Motion nothing travels, only opacity changes.
//

import SwiftUI

// MARK: - Glass surface / 玻璃表面

extension View {
    /// 在 `shape` 上绘制玻璃:iOS 26 用 Liquid Glass,更早系统回退到 `.regularMaterial` + 细描边。
    /// Draws this view on a glass `shape`: Liquid Glass on iOS 26, material + hairline before that.
    @ViewBuilder
    func aiGlass<S: InsettableShape>(_ shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

// MARK: - Scaffold / 统一骨架

/// 对话页统一骨架:流光背景 + 内容 + 底部输入区。
/// 输入区走 `safeAreaInset`,ScrollView 会自动避让,不再需要手写 96pt 占位。
///
/// Unified chat scaffold: flowing background + content + bottom input.
/// The input goes through `safeAreaInset`, so scroll views avoid it automatically
/// and no hand-written 96pt spacer is needed.
struct AIChatScaffold<Content: View, Input: View>: View {
    private let content: Content
    private let input: Input
    /// 关闭后不画流光背景,让外层(如玻璃 sheet)的背景透出来。
    /// When off, the flowing background is skipped so an outer background (e.g. a glass sheet) shows through.
    private let showsFlowingBackground: Bool

    init(
        showsFlowingBackground: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder input: () -> Input
    ) {
        self.showsFlowingBackground = showsFlowingBackground
        self.content = content()
        self.input = input()
    }

    var body: some View {
        ZStack {
            if showsFlowingBackground {
                AIChatFlowingBackground()
                    .ignoresSafeArea()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { input }
        .containerBackground(.clear, for: .navigation)
    }
}

extension View {
    /// 消息列的统一内边距与进出场动画。
    /// Uniform padding and insert/remove animation for the message column.
    func aiChatMessageColumn<V: Equatable>(animatedBy value: V) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .animation(.spring(duration: 0.4, bounce: 0.15), value: value)
    }
}

// MARK: - Reply header / 回复头部

/// 回复头部:玻璃胶囊,左侧是呼吸的星芒,然后是名称、可选标签、可选的已思考秒数。
/// 工作中星芒会"呼吸"(缩放 + 旋转);Reduce Motion 下只做透明度起伏。
///
/// Reply header: a glass capsule with a breathing sparkle mark, the name, an optional
/// tag and optional elapsed seconds. While working the mark breathes (scale + turn);
/// under Reduce Motion it only fades.
struct AIReplyHeader: View {
    var tag: String? = nil
    var isWorking: Bool = false
    var showsElapsed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private let period: Double = 2.2

    var body: some View {
        Group {
            if isWorking {
                TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 20 : nil)) { context in
                    pill(time: max(context.date.timeIntervalSince(start), 0))
                }
            } else {
                pill(time: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pill(time: Double) -> some View {
        let wave = isWorking ? sin(.pi * (time / period).truncatingRemainder(dividingBy: 1)) : 0
        let breath = wave * wave
        return HStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.primary)
                    .scaleEffect(reduceMotion ? 1 : 1 - 0.22 * breath)
                Image(systemName: "sparkle")
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(Color(.systemBackground))
                    .rotationEffect(.degrees(reduceMotion ? 0 : breath * 90))
            }
            .frame(width: 24, height: 24)
            .background {
                if isWorking && !reduceMotion {
                    Circle()
                        .stroke(Color.primary.opacity(0.35 * (1 - breath)), lineWidth: 2)
                        .scaleEffect(1 + 0.6 * breath)
                }
            }
            .opacity(reduceMotion && isWorking ? 0.55 + 0.45 * breath : 1)

            Text("AI".localized())
                .font(.subheadline.weight(.semibold))

            if let tag, !tag.isEmpty {
                Text(tag)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if showsElapsed {
                Text("· \(Int(time))s")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .frame(minHeight: 32)
        .aiGlass(Capsule())
    }
}

// MARK: - Thinking placeholder / 思考占位

/// 回复尚未开始时的占位内容(不含头部)。
/// - `.sheen`:回复形状的占位条 + 扫光
/// - `.dots`:三个依次跳起的点
/// - `.text`:一行状态文案,带扫光
///
/// Placeholder body for a reply that has not started (no header).
struct AIThinkingBody: View {
    enum Presentation: Equatable {
        case sheen
        case dots
        case text(String)
    }

    var presentation: Presentation = .sheen
    var lineCount: Int = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private let period: Double = 2.2
    /// 跳点颜色:橘、天蓝、淡紫
    /// Dot colours: tangerine, sky, lilac.
    private static let dotColors: [Color] = [
        Color(red: 1.0, green: 0.55, blue: 0.2),
        Color(red: 0.38, green: 0.65, blue: 1.0),
        Color(red: 0.7, green: 0.55, blue: 1.0)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 20 : nil)) { context in
            let time = max(context.date.timeIntervalSince(start), 0)
            Group {
                switch presentation {
                case .sheen:
                    bars.overlay { sheen(time: time).mask(bars) }
                case .dots:
                    dots(time: time)
                case .text(let label):
                    let text = Text(label).font(.body)
                    text
                        .foregroundStyle(.secondary)
                        .overlay { sheen(time: time, color: Color.primary).mask(text) }
                }
            }
        }
        .fontWeight(.semibold)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var accessibilityText: String {
        if case .text(let label) = presentation { return label }
        return "Thinking...".localized()
    }

    private var lineHeight: CGFloat { UIFont.preferredFont(forTextStyle: .body).lineHeight }

    /// 回复形状的占位条:整行、略短、末行更短。
    /// Reply-shaped bars: full, slightly short, and a short trailing bar.
    private var bars: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(0..<max(1, lineCount), id: \.self) { index in
                Capsule()
                    .fill(Color.primary.opacity(0.13))
                    .frame(height: lineHeight * 0.6)
                    .padding(.trailing, index == lineCount - 1 ? 110 : (index.isMultiple(of: 2) ? 0 : 32))
            }
        }
        .frame(minHeight: lineHeight)
    }

    private func dots(time: Double) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                let phase = ((time * 0.9 - Double(index) * 0.16).truncatingRemainder(dividingBy: 1) + 1)
                    .truncatingRemainder(dividingBy: 1)
                let wave = phase < 0.45 ? sin(phase / 0.45 * .pi) : 0
                let lift = wave * wave
                Circle()
                    .fill(Self.dotColors[index % Self.dotColors.count])
                    .frame(width: 9, height: 9)
                    .opacity(reduceMotion ? 0.5 + 0.5 * lift : 1)
                    .scaleEffect(reduceMotion ? 0.8 : 0.8 + 0.2 * lift)
                    .offset(y: reduceMotion ? 0 : -5 * lift)
            }
        }
        .frame(height: lineHeight)
    }

    /// 一道半宽的柔光自左向右扫过;Reduce Motion 下原地明暗起伏。
    /// One soft half-width band crossing leading to trailing; a gentle in-place glow under Reduce Motion.
    private func sheen(time: Double, color: Color = .white) -> some View {
        let progress = (time / period).truncatingRemainder(dividingBy: 1)
        let u = min(progress / 0.8, 1)
        let travel = u * u * (3 - 2 * u)
        let breath = pow(sin(.pi * u), 2)
        let center = -0.25 + travel * 1.5
        let glow = color.opacity(0.5 * breath)
        return LinearGradient(
            colors: reduceMotion ? [glow, glow] : [color.opacity(0), color.opacity(1), color.opacity(0)],
            startPoint: UnitPoint(x: center - 0.25, y: 0.5),
            endPoint: UnitPoint(x: center + 0.25, y: 0.5)
        )
        .allowsHitTesting(false)
    }
}

/// 独立使用的完整思考态(头部 + 占位),用于非气泡场景,如错题 AI 解析加载。
/// Standalone thinking state (header + placeholder) for non-bubble contexts.
struct AIThinkingState: View {
    var presentation: AIThinkingBody.Presentation = .sheen
    var lineCount: Int = 3
    var tag: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AIReplyHeader(tag: tag, isWorking: true, showsElapsed: true)
            AIThinkingBody(presentation: presentation, lineCount: lineCount)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Empty / not configured / 空态

/// 对话页统一空态。`.notConfigured` 带"打开 LLM 设置"入口。
/// Unified chat empty state; `.notConfigured` carries an "Open LLM Settings" link.
struct AIChatEmptyState: View {
    enum Kind {
        case notConfigured(showsSettingsLink: Bool = true)
        case welcome(symbol: String, title: String, message: String?)
    }

    let kind: Kind

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .scaledFont(size: 30, weight: .medium)
                .foregroundStyle(.primary)
                .frame(width: 72, height: 72)
                .aiGlass(Circle())
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if case .notConfigured(let showsLink) = kind, showsLink {
                NavigationLink(destination: LLMSettingsView()) {
                    Label("Open LLM Settings".localized(), systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .padding(.bottom, 24)
    }

    private var symbol: String {
        switch kind {
        case .notConfigured: return "exclamationmark.bubble"
        case .welcome(let symbol, _, _): return symbol
        }
    }

    private var title: String {
        switch kind {
        case .notConfigured: return "LLM Not Configured".localized()
        case .welcome(_, let title, _): return title
        }
    }

    private var message: String? {
        switch kind {
        case .notConfigured: return "Set Base URL, API Key and Model in Settings → LLM.".localized()
        case .welcome(_, _, let message): return message
        }
    }
}

// MARK: - Prompt chips / 推荐提问

/// 推荐提问胶囊,点击后回调所选文本。
/// Suggested-prompt capsules; tapping calls back with the chosen text.
struct AIPromptChips: View {
    let prompts: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(prompts, id: \.self) { prompt in
                Button { onSelect(prompt) } label: {
                    Text(prompt)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .aiGlass(Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Toolbar action / 导航栏动作

/// 导航栏右侧统一动作:流式中显示"停止",否则显示"清空"。
/// Unified trailing toolbar action: "stop" while streaming, otherwise "clear".
struct AIChatTrailingAction: View {
    let isStreaming: Bool
    var canClear: Bool = true
    let onStop: () -> Void
    let onClear: () -> Void

    var body: some View {
        if isStreaming {
            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
            }
            .accessibilityLabel("Cancel".localized())
        } else {
            Button(role: .destructive, action: onClear) {
                Image(systemName: "trash")
            }
            .disabled(!canClear)
            .accessibilityLabel("Clear".localized())
        }
    }
}

#Preview("Thinking") {
    VStack(alignment: .leading, spacing: 28) {
        AIThinkingState(presentation: .sheen)
        AIThinkingState(presentation: .dots)
        AIThinkingState(presentation: .text("正在生成回答…"))
        AIReplyHeader(tag: "身体 · 成绩")
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
}

#Preview("Empty") {
    NavigationStack {
        AIChatEmptyState(kind: .notConfigured())
    }
}
