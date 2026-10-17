//
//  HomeAskPanel.swift
//  StudyPulse
//
//  主页 AI 提问面板:平时是悬浮在 tab bar 上方的提问条,点按后从这条输入框「就地向上展开」成
//  液态玻璃小窗(底边不动、不盖住 tab bar),默认半屏高度,拖动顶部把手可拉到接近整屏(原 sheet 高度),
//  下拉则依次回到半屏 / 收起为提问条。取代原 HomeAskBar + sheet。
//  Home "Ask AI" panel: a floating bar above the tab bar that grows *in place, upward* into a Liquid
//  Glass window when tapped (bottom edge stays put, never covers the tab bar). Half-screen by default;
//  drag the handle to pull it to near full height (the old sheet height) or back down to half / the bar.
//  Replaces HomeAskBar + sheet.
//

import SwiftUI

struct HomeAskPanel: View {
    /// 收起态提问条高度(与 `HomeView` 的占位保持一致)/ Collapsed bar height (kept in sync with HomeView's spacer).
    static let collapsedHeight: CGFloat = 46

    private enum Detent {
        case collapsed, half, full
    }

    @Environment(RepositoryContainer.self) private var container
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: HomeAskViewModel
    @State private var detent: Detent = .collapsed
    /// 拖动中的额外高度(向上为正)/ Extra height while dragging (positive = taller).
    @State private var dragExtra: CGFloat = 0
    /// 不受键盘影响的可用高度 / Available height ignoring the keyboard.
    @State private var stableHeight: CGFloat = 0
    /// 受键盘影响的可见高度 / Visible height respecting the keyboard.
    @State private var visibleHeight: CGFloat = 0

    init(container: RepositoryContainer) {
        _viewModel = State(initialValue: HomeAskViewModel(container: container, envManager: container.envManager))
    }

    private var accent: Color { container.envManager.effectiveAccentColor }
    private var isConfigured: Bool { container.envManager.llmConfig.isConfigured }
    private var isExpanded: Bool { detent != .collapsed }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            panel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0 }
        .background {
            // 不跟随键盘收缩,用来算「半屏 / 整屏」,避免弹键盘时面板高度跳变。
            // Ignores the keyboard so half/full heights stay stable while typing.
            Color.clear
                .ignoresSafeArea(.keyboard)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stableHeight = $0 }
        }
    }

    // MARK: - Heights

    private var fullHeight: CGFloat { max(stableHeight > 0 ? stableHeight - 8 : 600, Self.collapsedHeight) }
    private var halfHeight: CGFloat { min(max(stableHeight * 0.5, 280), fullHeight) }

    private func baseHeight(_ detent: Detent) -> CGFloat {
        switch detent {
        case .collapsed: Self.collapsedHeight
        case .half: halfHeight
        case .full: fullHeight
        }
    }

    private var currentHeight: CGFloat {
        let raw = min(max(baseHeight(detent) + dragExtra, Self.collapsedHeight), fullHeight)
        // 键盘弹出时不超过可见区域 / Never taller than the keyboard-aware visible area.
        return visibleHeight > 0 ? min(raw, max(visibleHeight - 8, Self.collapsedHeight)) : raw
    }

    private var cornerRadius: CGFloat { min(28, currentHeight / 2) }

    // MARK: - Panel

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack(alignment: .bottom) {
            if isExpanded {
                expandedContent
                    .transition(.opacity)
            }
            collapsedBar
                .opacity(isExpanded ? 0 : 1)
                .allowsHitTesting(!isExpanded)
        }
        .frame(height: currentHeight)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .aiGlass(shape, interactive: !isExpanded)
        .shadow(color: .black.opacity(isExpanded ? 0.16 : 0.08), radius: isExpanded ? 22 : 12, y: 4)
    }

    // MARK: - Collapsed bar

    private var collapsedBar: some View {
        Button {
            setDetent(.half)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(LinearGradient(colors: [.purple, accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(placeholder)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(accent, in: Circle())
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .frame(height: Self.collapsedHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask AI".localized())
    }

    private var placeholder: String {
        isConfigured ? "home.v2.ask.placeholder".localized() : "未配置 AI · 前往设置".localized()
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            header
            HomeAskChatView(viewModel: viewModel, showsFlowingBackground: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)
            HStack(spacing: 12) {
                Button {
                    setDetent(.collapsed)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Close".localized())
                Spacer(minLength: 0)
                Text("Ask AI".localized())
                    .font(.headline)
                Spacer(minLength: 0)
                if container.envManager.llmConfig.isCloudProvider {
                    LLMThinkingModePicker(
                        mode: Binding(
                            get: { container.envManager.preferences.cloudThinkingMode },
                            set: { container.envManager.setCloudThinkingMode($0) }
                        ),
                        compact: true
                    )
                    .accessibilityLabel("深度思考".localized())
                }
                AIChatTrailingAction(
                    isStreaming: viewModel.phase != .idle,
                    canClear: !viewModel.messages.isEmpty,
                    onStop: { viewModel.cancel() },
                    onClear: { viewModel.reset() }
                )
                .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onTapGesture {
            // 点把手区域:半屏 ↔ 整屏 / Tap the handle area: half ↔ full.
            setDetent(detent == .full ? .half : .full)
        }
    }

    // MARK: - Dragging

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragExtra = -value.translation.height
            }
            .onEnded { value in
                // 用预测落点吸附到最近的档位 / Snap to the nearest detent using the predicted end point.
                let predicted = baseHeight(detent) - value.predictedEndTranslation.height
                let candidates: [Detent] = [.collapsed, .half, .full]
                let target = candidates.min { abs(baseHeight($0) - predicted) < abs(baseHeight($1) - predicted) } ?? .half
                setDetent(target)
            }
    }

    private func setDetent(_ new: Detent) {
        if new == .collapsed {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.42, bounce: 0.12)
        withAnimation(animation) {
            detent = new
            dragExtra = 0
        }
    }
}

#Preview {
    let container = RepositoryContainer()
    return ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        HomeAskPanel(container: container)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
    }
    .environment(container)
}
