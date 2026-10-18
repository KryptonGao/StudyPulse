//
//  AIReasoningPicker.swift
//  StudyPulse
//
//  Reasoning intensity in AI Mode: a small dashboard gauge beside the send
//  button shows the active model's stop; tapping it replaces the composer
//  with a Liquid Glass slider wrapped in a blur that fades outward. The
//  slider lives in its own non-key window so opening it keeps the text
//  field focused and the keyboard up (the system keyboard itself stays on
//  top and is not blurred).
//

import SwiftUI
import UIKit

// MARK: - Gauge

/// A simplified speedometer: a 270° dial, the filled part and a needle at `value` (0…1).
struct AIReasoningGauge: View {
    var value: Double
    var tint: Color
    var track: Color
    var size: CGFloat = 22

    var body: some View {
        let lineWidth = max(1.6, size * 0.1)
        let clamped = min(max(value, 0), 1)
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            Capsule()
                .fill(tint)
                .frame(width: lineWidth, height: size * 0.38)
                .offset(y: -size * 0.17)
                .rotationEffect(.degrees(-135 + 270 * clamped))
            Circle()
                .fill(tint)
                .frame(width: lineWidth * 2.2, height: lineWidth * 2.2)
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
    }
}

/// The composer button that shows the gauge and opens the slider.
struct AIReasoningGaugeButton: View {
    var viewModel: AIModeViewModel
    @Environment(\.aiTheme) private var theme

    var body: some View {
        let profile = viewModel.reasoningProfile
        let level = viewModel.reasoningLevel
        Button {
            Haptics.selection()
            withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                viewModel.showingReasoningPicker = true
            }
        } label: {
            AIReasoningGauge(
                value: profile.position(of: level),
                tint: theme.accent,
                track: theme.muted.opacity(0.35),
                size: 22
            )
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.35, bounce: 0.2), value: level)
        .accessibilityLabel("aiMode.reasoning.title".localized())
        .accessibilityValue(level.titleKey.localized())
        .accessibilityHint("aiMode.reasoning.hint".localized())
    }
}

// MARK: - Overlay

/// Covers the app's screen; the slider floats just above the composer, which stays visible and sharp.
/// Tapping anywhere outside closes it. Hosted by `AIReasoningOverlayPresenter` in its own window so the keyboard stays up.
struct AIReasoningPickerOverlay: View {
    var viewModel: AIModeViewModel
    /// The composer's glass surface in screen coordinates.
    var anchor: CGRect

    @Environment(\.aiTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Stop under the finger while dragging; nil when settled.
    @State private var previewIndex: Int?
    @State private var appeared = false

    private static let pillHeight: CGFloat = 76
    /// Space between the slider and the top of the composer.
    private static let composerGap: CGFloat = 12
    private static let composerCornerRadius: CGFloat = 28

    var body: some View {
        let profile = viewModel.reasoningProfile
        let committed = profile.levels.firstIndex(of: viewModel.reasoningLevel) ?? 0
        let shownIndex = previewIndex ?? committed
        let shownLevel = profile.levels[min(shownIndex, profile.levels.count - 1)]
        let pillWidth = max(anchor.width - 24, 160)
        // The slider floats just above the composer, which stays visible.
        let sliderY = anchor.minY - Self.composerGap - Self.pillHeight / 2

        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)

            // Strongest right behind the slider, fading out toward the screen edges; the composer is cut out
            // so it stays sharp under the slider.
            AIRadialProgressiveBlur()
                .frame(width: anchor.width + 200, height: 440)
                .position(x: anchor.midX, y: sliderY)
                .mask {
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                        RoundedRectangle(cornerRadius: Self.composerCornerRadius, style: .continuous)
                            .frame(width: anchor.width, height: anchor.height)
                            .position(x: anchor.midX, y: anchor.midY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                .opacity(appeared ? 1 : 0)
                .allowsHitTesting(false)

            Group {
                Text(shownLevel.titleKey.localized())
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.ink)
                    .contentTransition(reduceMotion ? .opacity : .interpolate)
                    .animation(.snappy(duration: 0.2), value: shownLevel)
                    .fixedSize()
                    // A fixed-level caption sits between the title and the slider.
                    .position(x: anchor.midX, y: sliderY - Self.pillHeight / 2 - (profile.isAdjustable ? 30 : 56))
                    .accessibilityHidden(true)

                AIReasoningSlider(
                    stops: profile.levels.count,
                    selected: committed,
                    previewIndex: $previewIndex,
                    tint: theme.accent,
                    idleTrack: theme.soft,
                    onCommit: { index in
                        guard profile.levels.indices.contains(index) else { return }
                        viewModel.reasoningLevel = profile.levels[index]
                    }
                )
                .frame(width: pillWidth, height: Self.pillHeight)
                .accessibilityElement()
                .accessibilityLabel("aiMode.reasoning.title".localized())
                .accessibilityValue(shownLevel.titleKey.localized())
                .accessibilityAdjustableAction { direction in
                    let next: Int
                    switch direction {
                    case .increment: next = min(committed + 1, profile.levels.count - 1)
                    case .decrement: next = max(committed - 1, 0)
                    @unknown default: return
                    }
                    viewModel.reasoningLevel = profile.levels[next]
                }
                .accessibilityAction(named: "aiMode.reasoning.done".localized(), dismiss)
                .position(x: anchor.midX, y: sliderY)

                if !profile.isAdjustable {
                    Text("aiMode.reasoning.fixed".localized())
                        .font(.footnote)
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                        .frame(width: pillWidth)
                        .position(x: anchor.midX, y: sliderY - Self.pillHeight / 2 - 20)
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 10)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.35, bounce: 0.15)) {
                appeared = true
            }
        }
    }

    private func dismiss() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.05)) {
            appeared = false
        } completion: {
            viewModel.showingReasoningPicker = false
        }
    }
}

// MARK: - Overlay window

/// Never becomes key, so the composer's text field keeps focus and the keyboard stays up.
private final class AIReasoningOverlayWindow: UIWindow {
    override var canBecomeKey: Bool { false }
}

/// Owns the window that shows the slider while the keyboard stays up.
@MainActor
final class AIReasoningOverlayPresenter {
    private var window: UIWindow?
    private var host: UIHostingController<AnyView>?

    var isShowing: Bool { window != nil }

    func show(over source: UIWindow, content: AnyView) {
        guard let scene = source.windowScene else { return }
        if let host {
            host.rootView = content
            return
        }
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        let window = AIReasoningOverlayWindow(windowScene: scene)
        window.backgroundColor = .clear
        window.rootViewController = host
        window.overrideUserInterfaceStyle = source.traitCollection.userInterfaceStyle
        // Above the app's windows. The system keyboard is drawn above any app window and stays visible.
        let top = scene.windows.map(\.windowLevel.rawValue).max() ?? UIWindow.Level.normal.rawValue
        window.windowLevel = UIWindow.Level(rawValue: max(top, UIWindow.Level.alert.rawValue) + 1)
        window.isHidden = false
        self.window = window
        self.host = host
    }

    func update(_ content: AnyView) {
        host?.rootView = content
    }

    func hide() {
        window?.isHidden = true
        window = nil
        host = nil
    }
}

/// Reports the UIKit window a SwiftUI view lives in.
struct AIWindowReader: UIViewRepresentable {
    var onWindow: (UIWindow?) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindow = onWindow
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ReaderView, context: Context) {
        uiView.onWindow = onWindow
    }

    final class ReaderView: UIView {
        var onWindow: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindow?(window)
        }
    }
}

/// Presents the reasoning slider in its own window while `showingReasoningPicker` is on.
struct AIReasoningOverlayHost: ViewModifier {
    var viewModel: AIModeViewModel
    /// The composer's glass surface in screen coordinates.
    var anchor: CGRect

    @Environment(\.aiTheme) private var theme
    @State private var presenter = AIReasoningOverlayPresenter()
    @State private var sourceWindow = WeakWindow()

    final class WeakWindow {
        weak var window: UIWindow?
    }

    func body(content: Content) -> some View {
        content
            .background(AIWindowReader { sourceWindow.window = $0 }.allowsHitTesting(false))
            .onChange(of: viewModel.showingReasoningPicker) { _, showing in
                if showing, let window = sourceWindow.window {
                    presenter.show(over: window, content: overlay)
                } else {
                    presenter.hide()
                }
            }
            // The keyboard or a rotation can move the composer while the slider is open.
            .onChange(of: anchor) { _, _ in
                if presenter.isShowing { presenter.update(overlay) }
            }
            .onChange(of: theme) { _, _ in
                if presenter.isShowing { presenter.update(overlay) }
            }
            .onDisappear {
                presenter.hide()
                viewModel.showingReasoningPicker = false
            }
    }

    private var overlay: AnyView {
        AnyView(
            AIReasoningPickerOverlay(viewModel: viewModel, anchor: anchor)
                .environment(\.aiTheme, theme)
                .tint(theme.accent)
        )
    }
}

extension View {
    /// Shows the reasoning slider above `anchor` (the composer, screen coordinates) without dismissing the keyboard.
    func aiReasoningOverlay(viewModel: AIModeViewModel, anchor: CGRect) -> some View {
        modifier(AIReasoningOverlayHost(viewModel: viewModel, anchor: anchor))
    }
}

// MARK: - Slider

/// Discrete slider on a Liquid Glass capsule: an accent fill up to a white knob, with a dot at every stop.
struct AIReasoningSlider: View {
    let stops: Int
    let selected: Int
    @Binding var previewIndex: Int?
    var tint: Color
    var idleTrack: Color
    var onCommit: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Knob center while the finger is down; nil when resting on a stop.
    @State private var dragX: CGFloat?
    /// The finger has moved far enough to count as a drag; before that a touch is a tap on a stop.
    @State private var isDragging = false
    /// Stop committed on release; the knob holds there until `selected` catches up
    /// (the overlay window receives the new selection a frame later).
    @State private var pendingCommit: Int?

    private static let dragThreshold: CGFloat = 6

    private static let inset: CGFloat = 8
    private static let knobGap: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let trackHeight = geo.size.height - Self.inset * 2
            let trackWidth = geo.size.width - Self.inset * 2
            let knob = trackHeight - Self.knobGap * 2
            let minX = Self.knobGap + knob / 2
            let maxX = trackWidth - Self.knobGap - knob / 2
            let restX = stopX(selected, minX: minX, maxX: maxX)
            let knobX = dragX ?? restX

            ZStack(alignment: .leading) {
                Capsule().fill(idleTrack)
                Capsule()
                    .fill(tint)
                    .frame(width: knobX + knob / 2 + Self.knobGap)
                ForEach(0..<stops, id: \.self) { index in
                    let x = stopX(index, minX: minX, maxX: maxX)
                    Circle()
                        .fill(x <= knobX ? Color.white.opacity(0.45) : tint.opacity(0.35))
                        .frame(width: 10, height: 10)
                        .position(x: x, y: trackHeight / 2)
                        .opacity(abs(x - knobX) < knob / 2 ? 0 : 1)
                }
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                    .frame(width: knob, height: knob)
                    .scaleEffect(dragX == nil || reduceMotion ? 1 : 1.06)
                    .position(x: knobX, y: trackHeight / 2)
            }
            .frame(width: trackWidth, height: trackHeight)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard stops > 1 else { return }
                        let x = min(max(value.location.x, minX), maxX)
                        let nearest = nearestStop(x, minX: minX, maxX: maxX)
                        if !isDragging && abs(value.translation.width) < Self.dragThreshold {
                            // A tap: glide the knob to the touched stop instead of teleporting under the finger.
                            if dragX == nil || nearest != previewIndex {
                                withAnimation(settleAnimation) {
                                    dragX = stopX(nearest, minX: minX, maxX: maxX)
                                }
                            }
                        } else if !isDragging {
                            // Drag begins: catch up to the finger quickly, then track it 1:1.
                            isDragging = true
                            withAnimation(reduceMotion ? nil : .interactiveSpring(duration: 0.18)) { dragX = x }
                        } else {
                            dragX = x
                        }
                        if nearest != (previewIndex ?? selected) { Haptics.selection() }
                        previewIndex = nearest
                    }
                    .onEnded { value in
                        guard stops > 1 else { return }
                        let x = min(max(value.location.x, minX), maxX)
                        let nearest = isDragging ? nearestStop(x, minX: minX, maxX: maxX) : (previewIndex ?? selected)
                        isDragging = false
                        guard nearest != selected else {
                            withAnimation(settleAnimation) {
                                dragX = nil
                                previewIndex = nil
                            }
                            return
                        }
                        withAnimation(settleAnimation) { dragX = stopX(nearest, minX: minX, maxX: maxX) }
                        pendingCommit = nearest
                        onCommit(nearest)
                    }
            )
            .padding(Self.inset)
            .frame(width: geo.size.width, height: geo.size.height)
            .aiGlass(Capsule(), interactive: true)
            .animation(dragX == nil && !reduceMotion ? .spring(duration: 0.3, bounce: 0.25) : nil, value: selected)
        }
        .onChange(of: selected) { _, newValue in
            guard pendingCommit == newValue else { return }
            pendingCommit = nil
            // Same target as the knob is already heading to, so the spring just continues.
            withAnimation(settleAnimation) {
                dragX = nil
                previewIndex = nil
            }
        }
    }

    private var settleAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.3, bounce: 0.25)
    }

    private func stopX(_ index: Int, minX: CGFloat, maxX: CGFloat) -> CGFloat {
        guard stops > 1 else { return maxX }
        return minX + (maxX - minX) * CGFloat(index) / CGFloat(stops - 1)
    }

    private func nearestStop(_ x: CGFloat, minX: CGFloat, maxX: CGFloat) -> Int {
        guard stops > 1, maxX > minX else { return 0 }
        let fraction = (x - minX) / (maxX - minX)
        return min(max(Int((fraction * CGFloat(stops - 1)).rounded()), 0), stops - 1)
    }
}

// MARK: - Progressive blur

/// Layers of material masked by shrinking radial gradients: the blur is heaviest at the center
/// and thins out toward the edges, so the surroundings dissolve gradually instead of at a hard line.
struct AIRadialProgressiveBlur: View {
    var body: some View {
        ZStack {
            layer(.ultraThinMaterial, radius: 0.5)
            layer(.thinMaterial, radius: 0.36)
            layer(.regularMaterial, radius: 0.24)
        }
    }

    private func layer(_ material: Material, radius: CGFloat) -> some View {
        Rectangle()
            .fill(material)
            .mask(
                EllipticalGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.6), location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    center: .center,
                    startRadiusFraction: 0,
                    endRadiusFraction: radius
                )
            )
    }
}

#Preview("Reasoning slider") {
    @Previewable @State var preview: Int?
    VStack(spacing: 40) {
        HStack(spacing: 16) {
            ForEach([0, 0.33, 0.66, 1.0], id: \.self) { value in
                AIReasoningGauge(value: value, tint: .blue, track: .gray.opacity(0.35), size: 28)
            }
        }
        AIReasoningSlider(stops: 3, selected: 2, previewIndex: $preview, tint: .blue, idleTrack: Color(.systemGray5)) { _ in }
            .frame(height: 76)
            .padding(.horizontal, 24)
    }
    .padding(.vertical, 40)
    .background { AIRadialProgressiveBlur() }
}
