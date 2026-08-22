//
//  StudyTimerActiveCard.swift
//  StudyPulse
//
//  Full-screen Pomodoro timer card: animated ring, control buttons,
//  ambient particles, and immersive landscape layout.
//

import SwiftUI
import os

// MARK: - StudyTimerActiveCard

struct StudyTimerActiveCard: View {
    @Bindable var timer: StudyTimerManager

    /// Whether the immersive landscape (rotated) layout is active. The
    /// card uses this to switch between the standard vertical body and
    /// the landscape "ring + side controls" body.
    @Binding var immersiveLandscapeMode: Bool

    /// Currently selected animation (drives ring / glow / orb palette and
    /// background flow). Source of truth lives in `envManager.effectiveTimerAnimation`.
    let animation: TimerAnimation

    /// Notifies the parent that the user wants to toggle immersive mode
    /// so the parent can lock / unlock device orientation.
    let onImmersiveToggle: () -> Void

    /// Notifies the parent that the user has interacted with the screen
    /// while the controls were idle (so the parent can reset its idle
    /// timer and reveal the controls).
    let onUserInteraction: () -> Void

    // MARK: - Animation State

    @State private var animatedProgress: Double = 1.0
    @State private var breatheScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.3
    @State private var ringRotation: Double = 0
    @State private var orbs: [FloatingOrb] = []
    @State private var showPausedPulse = false
    @State private var controlButtonScale: [Bool] = [false, false, false]
    @State private var isIdle: Bool = false

    // Idle detection
    @State private var idleTimer: Timer?
    @State private var idleCount: Int = 0
    private let idleThreshold: TimeInterval = 15.0

    // MARK: - Derived

    private var isRunning: Bool { timer.timerState == .running }

    private var themeColor: Color { animation.primaryColor }
    private var flowColors: [Color] { animation.colors }

    private var activePrimaryTextColor: Color {
        immersiveLandscapeMode ? .white : .primary
    }
    private var activeSecondaryTextColor: Color {
        immersiveLandscapeMode ? Color.white.opacity(0.72) : .secondary
    }
    private var activeSurfaceFillColor: Color {
        immersiveLandscapeMode ? Color.white.opacity(0.08) : Color(.tertiarySystemFill)
    }
    private var activeSurfaceStrokeColor: Color {
        immersiveLandscapeMode ? Color.white.opacity(0.14) : Color(.secondarySystemFill)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                backgroundLayer(size: proxy.size)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onUserInteraction()
                    }
                    .onHover { hovering in
                        if hovering { onUserInteraction() }
                    }

                if immersiveLandscapeMode && proxy.size.width > proxy.size.height {
                    immersiveLandscapeBody(in: proxy.size)
                } else {
                    standardActiveTimerBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            startAmbientAnimations()
            generateOrbs()
            startIdleTimer()
        }
        .onDisappear {
            stopAmbientAnimations()
            stopIdleTimer()
        }
        .onChange(of: animation.id) { _, _ in
            // 切换动画风格时重新生成粒子,匹配新的 particleCount / style
            generateOrbs()
        }
        .onChange(of: timer.remainingSeconds) { _, newValue in
            guard timer.totalSeconds > 0 else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedProgress = Double(newValue) / Double(timer.totalSeconds)
            }
        }
        .onChange(of: timer.timerState) { _, newState in
            if newState == .running {
                startAmbientAnimations()
            } else {
                stopAmbientAnimations()
            }
        }
    }

    // MARK: - Background Layer

    private func backgroundLayer(size proxySize: CGSize) -> some View {
        ZStack {
            if immersiveLandscapeMode {
                Color.black

                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    landscapeFlowLayer(size: proxySize, time: t)
                }
            } else {
                // Flowing gradient background (default) or starfield / forest
                TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    backgroundFlowLayer(time: t)
                }
            }

            // Radial glow behind timer
            RadialGradient(
                colors: [animation.glowColor.opacity(glowOpacity), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .blendMode(.plusLighter)

            // Floating orbs
            if isRunning && animation.particleStyle != .none {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(orbs) { orb in
                            let cycle = time.truncatingRemainder(dividingBy: orb.speed) / orb.speed
                            let progress = (cycle + orb.phase).truncatingRemainder(dividingBy: 1.0)
                            let y = proxySize.height * (1.0 - progress)
                            let x = orb.xRatio * proxySize.width + sin(time * 0.5 + orb.phase * 10) * 20
                            let colorIndex = Int((time * 0.1 + orb.phase * 3).truncatingRemainder(dividingBy: Double(flowColors.count)))
                            let orbColor = flowColors[colorIndex]
                            particleView(orb: orb, color: orbColor, progress: progress)
                                .frame(width: orb.size, height: orb.size)
                                .position(x: x, y: y)
                                .opacity(orb.opacity * (1.0 - progress))
                        }
                    }
                }
            }
        }
    }

    /// 单个粒子的形状（按 `animation.particleStyle` 分支）。
    @ViewBuilder
    private func particleView(orb: FloatingOrb, color: Color, progress: Double) -> some View {
        switch animation.particleStyle {
        case .snowfall:
            Image(systemName: "snowflake")
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
                .rotationEffect(.degrees(progress * 360))
        case .petals:
            Image(systemName: "leaf.fill")
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
                .rotationEffect(.degrees(orb.phase * 360 + progress * 90))
        case .stars:
            Image(systemName: "star.fill")
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
        case .fireflies:
            Circle()
                .fill(color)
                .blur(radius: 1.0)
        case .bubbles:
            Circle()
                .stroke(color, lineWidth: 1.0)
        case .rain:
            Capsule()
                .fill(color)
                .frame(width: orb.size * 0.3, height: orb.size * 2.5)
        case .orbs:
            Circle()
                .fill(color)
                .blur(radius: 1.5)
        case .none:
            EmptyView()
        }
    }

    private func landscapeFlowLayer(size: CGSize, time: TimeInterval) -> some View {
        ZStack {
            ForEach(Array(flowColors.enumerated()), id: \.offset) { index, color in
                let phase = Double(index) * 1.7
                let x = size.width * (0.15 + 0.7 * (0.5 + 0.5 * sin(time * (0.10 + Double(index) * 0.015) + phase)))
                let y = size.height * (0.18 + 0.64 * (0.5 + 0.5 * cos(time * (0.13 + Double(index) * 0.02) + phase * 0.8)))
                let width = min(size.width, size.height) * (0.22 + CGFloat(index) * 0.04)
                let height = width * (1.2 + CGFloat(index) * 0.12)

                Ellipse()
                    .fill(color.opacity(0.16))
                    .frame(width: width, height: height)
                    .blur(radius: 48)
                    .position(x: x, y: y)
                    .blendMode(.screen)
            }
        }
        .compositingGroup()
    }

    /// 竖屏背景层：按 `animation.backgroundStyle` 分支。
    @ViewBuilder
    private func backgroundFlowLayer(time: TimeInterval) -> some View {
        switch animation.backgroundStyle {
        case .flowGradient:
            LinearGradient(
                colors: [
                    flowColors[0].opacity(0.08 + 0.02 * sin(time * 0.3)),
                    Color(.systemBackground),
                    flowColors[1].opacity(0.04 + 0.02 * cos(time * 0.2))
                ],
                startPoint: UnitPoint(
                    x: 0.5 + 0.3 * sin(time * 0.15),
                    y: 0.5 + 0.3 * cos(time * 0.15)
                ),
                endPoint: UnitPoint(
                    x: 0.5 - 0.3 * sin(time * 0.15),
                    y: 0.5 - 0.3 * cos(time * 0.15)
                )
            )

        case .starfield:
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.12)
                ForEach(0..<20, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.3 + 0.5 * sin(time * 0.5 + Double(i) * 0.7)))
                        .frame(width: 2, height: 2)
                        .offset(
                            x: CGFloat((i * 37) % 360) - 180,
                            y: CGFloat((i * 53) % 600) - 300
                        )
                }
                // 颜色光晕
                RadialGradient(
                    colors: [flowColors[0].opacity(0.12), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 350
                )
                .blendMode(.plusLighter)
            }

        case .forest:
            ZStack {
                Color(red: 0.05, green: 0.12, blue: 0.06)
                LinearGradient(
                    colors: [
                        flowColors[0].opacity(0.18 + 0.04 * sin(time * 0.3)),
                        flowColors[1].opacity(0.10 + 0.03 * cos(time * 0.2))
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

        case .none:
            Color(.systemBackground)
        }
    }

    // MARK: - Layouts

    private var standardActiveTimerBody: some View {
        VStack(spacing: 0) {
            Spacer()

            timerRingView(outerGlowSize: 310, outerRingSize: 290, trackSize: 240, innerSize: 220, timeFontSize: 52)

            Spacer()

            controlButtons

            Spacer().frame(height: isIdle ? 20 : 40)
        }
    }

    private func immersiveLandscapeBody(in size: CGSize) -> some View {
        let ringWidth = min(size.height * 0.76, size.width * 0.42, 470)

        return ZStack {
            timerRingView(
                outerGlowSize: ringWidth,
                outerRingSize: ringWidth - 16,
                trackSize: ringWidth - 58,
                innerSize: ringWidth - 118,
                timeFontSize: ringWidth * 0.22
            )
            .frame(width: ringWidth, height: ringWidth)

            HStack {
                Spacer()

                controlButtons
                    .frame(width: 120)
                    .padding(.trailing, 56)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        Group {
            if !isIdle {
                let controlsLayout = immersiveLandscapeMode
                    ? AnyLayout(VStackLayout(spacing: 28))
                    : AnyLayout(HStackLayout(spacing: 48))

                controlsLayout {
                    // End button
                    controlButton(index: 0, accent: .red) {
                        timer.cancel()
                    } icon: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.red)
                    } label: {
                        Text("End".localized())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                    } background: {
                        Circle()
                            .fill(Color.red.opacity(0.1))
                            .frame(width: 60, height: 60)
                        Circle()
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                            .frame(width: 60, height: 60)
                    }

                    // Play/Pause button (primary)
                    controlButton(index: 1, accent: timer.timerState == .paused ? .green : themeColor) {
                        if timer.timerState == .running {
                            timer.pause()
                        } else if timer.timerState == .paused {
                            timer.resume()
                        }
                    } icon: {
                        Image(systemName: timer.timerState == .paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                    } label: {
                        Text(timer.timerState == .paused ? "Resume".localized() : "Pause".localized())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(activeSecondaryTextColor)
                    } background: {
                        let base = timer.timerState == .paused ? Color.green : themeColor
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [base, base.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 76, height: 76)
                            .shadow(color: base.opacity(0.4), radius: 12, x: 0, y: 4)
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.2), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(width: 76, height: 76)
                    }

                    // Full-screen button
                    controlButton(index: 2, accent: themeColor) {
                        onImmersiveToggle()
                    } icon: {
                        Image(systemName: immersiveLandscapeMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(themeColor)
                    } label: {
                        Text(immersiveLandscapeMode ? "Exit Full Screen".localized() : "Full Screen".localized())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(activeSecondaryTextColor)
                    } background: {
                        Circle()
                            .fill(activeSurfaceFillColor)
                            .frame(width: 60, height: 60)
                        Circle()
                            .stroke(immersiveLandscapeMode ? activeSurfaceStrokeColor : themeColor.opacity(0.2), lineWidth: 1)
                            .frame(width: 60, height: 60)
                    }
                }
                .frame(maxWidth: immersiveLandscapeMode ? 120 : .infinity)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isIdle)
    }

    @ViewBuilder
    private func controlButton<Icon: View, Label: View, Background: View>(
        index: Int,
        accent: Color,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder label: () -> Label,
        @ViewBuilder background: () -> Background
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                controlButtonScale[index] = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    controlButtonScale[index] = false
                }
            }
            action()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    background()
                    icon()
                }
                .scaleEffect(controlButtonScale[index] ? 0.9 : 1.0)

                label()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Idle Detection

    private func startIdleTimer() {
        stopIdleTimer()
        idleCount = 0
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                idleCount += 1
                if !isIdle && isRunning && idleCount >= Int(idleThreshold) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        isIdle = true
                    }
                }
            }
        }
    }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func wakeFromIdle() {
        guard isIdle else { return }
        isIdle = false
        stopIdleTimer()
        startIdleTimer()
    }

    private func resetIdleTimer() {
        if isIdle {
            wakeFromIdle()
        } else {
            stopIdleTimer()
            startIdleTimer()
        }
    }

    /// Called from the parent when the user taps or hovers the screen.
    func handleUserInteraction() {
        if isIdle {
            withAnimation(.easeOut(duration: 0.22)) {
                isIdle = false
            }
        }
        stopIdleTimer()
        startIdleTimer()
    }

    // MARK: - Ambient Animations

    private func generateOrbs() {
        let count = max(0, min(animation.particleCount, 32))
        let (sizeRange, speedRange, opacityRange) = animation.particleStyle.ranges
        orbs = (0..<count).map { _ in
            FloatingOrb(
                xRatio: CGFloat.random(in: 0.05...0.95),
                size: CGFloat.random(in: sizeRange),
                speed: Double.random(in: speedRange),
                phase: Double.random(in: 0...1),
                opacity: Double.random(in: opacityRange)
            )
        }
    }

    private func startAmbientAnimations() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            breatheScale = 1.04
        }
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            glowOpacity = 0.45
        }
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            showPausedPulse = true
        }
    }

    private func stopAmbientAnimations() {
        withAnimation(.easeOut(duration: 0.5)) {
            breatheScale = 1.0
            glowOpacity = 0.15
        }
    }

    // MARK: - Timer Ring

    @ViewBuilder
    private func timerRingView(
        outerGlowSize: CGFloat,
        outerRingSize: CGFloat,
        trackSize: CGFloat,
        innerSize: CGFloat,
        timeFontSize: CGFloat
    ) -> some View {
        let safeTimeFontSize = immersiveLandscapeMode ? min(timeFontSize, innerSize * 0.32) : timeFontSize
        let timeTextWidth = immersiveLandscapeMode ? innerSize * 0.74 : innerSize * 0.82

        ZStack {
            // Outer glow ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: flowColors.flatMap { [$0.opacity(0.0), $0.opacity(0.4), $0.opacity(0.0)] } + [flowColors[0].opacity(0.0)],
                        center: .center,
                        startAngle: .degrees(ringRotation - 60),
                        endAngle: .degrees(ringRotation + 60)
                    ),
                    style: StrokeStyle(lineWidth: immersiveLandscapeMode ? 12 : 24, lineCap: .round)
                )
                .frame(width: outerGlowSize, height: outerGlowSize)
                .blur(radius: 12)
                .opacity(immersiveLandscapeMode ? (isRunning ? 0.26 : 0.10) : (isRunning ? 0.6 : 0.2))

            // Outer thin ring
            if immersiveLandscapeMode {
                Circle()
                    .stroke(Color.white.opacity(isRunning ? 0.18 : 0.10), lineWidth: 2)
                    .frame(width: outerRingSize, height: outerRingSize)
                    .scaleEffect(breatheScale)
                    .blur(radius: 0.4)
            } else {
                Circle()
                    .stroke(themeColor.opacity(0.15), lineWidth: 2)
                    .frame(width: outerRingSize, height: outerRingSize)
                    .scaleEffect(breatheScale)
                    .opacity(isRunning ? 0.5 : 0.15)
            }

            // Track ring
            if immersiveLandscapeMode {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 8)
                    .frame(width: trackSize, height: trackSize)
            } else {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 10)
                    .frame(width: trackSize, height: trackSize)
            }

            // Progress arc
            Circle()
                .trim(from: 0, to: 1.0 - animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: flowColors + [flowColors[0]],
                        center: .center,
                        startAngle: .degrees(ringRotation - 90),
                        endAngle: .degrees(ringRotation + 270)
                    ),
                    style: StrokeStyle(lineWidth: immersiveLandscapeMode ? 8 : 10, lineCap: .round)
                )
                .frame(width: trackSize, height: trackSize)
                .rotationEffect(.degrees(-90))
                .shadow(color: themeColor.opacity(0.5), radius: 8, x: 0, y: 0)
                .animation(.easeInOut(duration: 0.5), value: animatedProgress)

            // Center
            if immersiveLandscapeMode {
                nativeGlassCircle(diameter: innerSize, opacity: 0.56)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    )
            } else {
                Circle()
                    .stroke(themeColor.opacity(0.08), lineWidth: 1)
                    .frame(width: innerSize, height: innerSize)
            }

            // Center labels
            VStack(spacing: 8) {
                Text(formatTime(timer.remainingSeconds))
                    .font(.system(size: safeTimeFontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [immersiveLandscapeMode ? .white : .primary, themeColor.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: timer.remainingSeconds)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .frame(maxWidth: timeTextWidth)

                Text(timer.currentIntensity?.displayName ?? "")
                    .font(.system(size: max(15, safeTimeFontSize * 0.28), weight: .medium))
                    .foregroundColor(themeColor)
                    .opacity(0.9)

                if let goal = timer.activeGoal ?? timer.draftGoal {
                    Label(goal.title, systemImage: goal.source.icon)
                        .font(.system(size: max(11, safeTimeFontSize * 0.20), weight: .medium))
                        .foregroundColor(immersiveLandscapeMode ? Color.white.opacity(0.82) : .secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(immersiveLandscapeMode ? Color.white.opacity(0.10) : Color(.tertiarySystemFill)))
                }

                if timer.timerState == .paused {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .scaleEffect(showPausedPulse ? 1.4 : 1.0)
                            .opacity(showPausedPulse ? 0.5 : 1.0)
                        Text("Paused".localized())
                            .font(.system(size: max(13, timeFontSize * 0.22), weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
                    .overlay(
                        Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                }

                // 实时心率徽标(Apple Watch 通过 HealthKit 写入)
                // Live heart-rate badge (Apple Watch via HealthKit).
                if let hr = timer.currentHeartRate {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .symbolEffect(.bounce, value: hr)
                        Text("\(Int(hr)) bpm")
                            .font(.system(size: max(12, timeFontSize * 0.2), weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.pink)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.pink.opacity(0.12)))
                    .overlay(Capsule().stroke(Color.pink.opacity(0.25), lineWidth: 1))
                } else if timer.timerState == .running {
                    // 会话运行中但尚未收到心率样本。区分采集是否已启动:
                    // Session running but no HR sample yet. Distinguish whether
                    // streaming is actually active vs skipped/disabled.
                    if timer.hrStreamingActive {
                        // 采集已启动,但 Apple Watch 被动采样间隔 5-10 分钟,需等待
                        Text("Waiting for Apple Watch HR (passive sampling ~5-10 min)…".localized())
                            .font(.system(size: max(10, timeFontSize * 0.16), weight: .medium))
                            .foregroundColor(activeSecondaryTextColor)
                    } else {
                        // 采集未启动:功能关闭或 HealthKit 未授权
                        Text("HR streaming off — enable in Settings / Health".localized())
                            .font(.system(size: max(10, timeFontSize * 0.16), weight: .medium))
                            .foregroundColor(activeSecondaryTextColor.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: innerSize * 0.82)
        }
    }

    // MARK: - Format

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
