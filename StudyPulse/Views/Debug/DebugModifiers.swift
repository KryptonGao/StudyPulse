//
//  DebugModifiers.swift
//  StudyPulse
//
//  Debug 模式专用 View 修饰符：
//  - .debugLayoutBounds()   打开时画 1px 随机色边框 + 5% 底色
//  - .debugInspect(value:)  长按弹 alert 显示原始值与类型
//

import SwiftUI
import os

// MARK: - Layout Bounds

struct DebugLayoutBoundsModifier: ViewModifier {
    let enabled: Bool
    private let seed: UInt64

    init(enabled: Bool) {
        self.enabled = enabled
        // 用 view identity 的 hash 作随机种子,使同一个 view 总是同一颜色
        self.seed = UInt64.random(in: 0...UInt64.max)
    }

    func body(content: Content) -> some View {
        if enabled {
            content
                .overlay(
                    Rectangle()
                        .strokeBorder(borderColor, lineWidth: 0.5)
                )
                .background(borderColor.opacity(0.05))
        } else {
            content
        }
    }

    private var borderColor: Color {
        // 用 seed 生成稳定的 hue
        let hue = Double(seed % 360) / 360.0
        return Color(hue: hue, saturation: 0.8, brightness: 0.9)
    }
}

extension View {
    /// 当 AppEnvironmentManager.debugLayoutBounds 开启时,显示 1px 随机色边框 + 5% 底色。
    /// Marks the view with a 1px debug border + 5% tinted background when Debug → Layout Bounds is on.
    func debugLayoutBounds(_ enabled: Bool) -> some View {
        modifier(DebugLayoutBoundsModifier(enabled: enabled))
    }
}

// MARK: - Long-press Inspect

struct DebugInspectModifier<T>: ViewModifier {
    let value: T
    let label: String
    @State private var showingAlert: Bool = false

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: 0.5) {
                showingAlert = true
            }
            .alert("debug.inspect.title".localized(), isPresented: $showingAlert) {
                Button("Copy".localized()) {
                    UIPasteboard.general.string = String(describing: value)
                }
                Button("OK".localized(), role: .cancel) {}
            } message: {
                Text(inspectMessage)
            }
    }

    private var inspectMessage: String {
        let typeName = String(describing: type(of: value))
        return """
        \(label)
        Type: \(typeName)
        Value: \(String(describing: value))
        """
    }
}

extension View {
    /// 当 AppEnvironmentManager.debugLongPressInspect 开启时,长按该 view 弹 alert 显示原始值与类型。
    /// Long-press to inspect the raw value when Debug → Long-press Inspect is on.
    func debugInspect<T>(_ value: T, label: String) -> some View {
        modifier(DebugInspectModifier(value: value, label: label))
    }
}

// MARK: - Container 修饰符（顶 banner + 右上角浮窗）

struct DebugModeContainerModifier: ViewModifier {
    @Environment(RepositoryContainer.self) private var container
    @State private var showDebugConsole: Bool = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if container.envManager.isDebugModeActive {
                    DebugBannerView {
                        showDebugConsole = true
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                if container.envManager.debugModeEnabled && container.envManager.debugFPSOverlay {
                    DebugFPSOverlayView()
                        .padding(.top, container.envManager.isDebugModeActive ? 36 : 8)
                        .padding(.trailing, 12)
                        .allowsHitTesting(true)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: container.envManager.isDebugModeActive)
            .navigationDestination(isPresented: $showDebugConsole) {
                DebugView()
                    .environment(container)
            }
    }
}

extension View {
    /// 把 Debug 模式的黄色顶部 banner 和右上角 FPS 浮窗挂到当前 view。
    /// Attaches the yellow Debug Mode banner and the FPS overlay to this view.
    /// 应在每个主页面 NavigationStack 内的根 view 上调用一次。
    func debugModeContainer() -> some View {
        modifier(DebugModeContainerModifier())
    }
}

// MARK: - 便捷修饰符

extension View {
    /// 当 Debug 模式开启时,显示 1px 随机色边框 + 5% 底色。
    /// 自动从 EnvironmentObject 读取 `AppEnvironmentManager.debugLayoutBounds`。
    /// Use this on any view to opt in to the layout-bounds overlay.
    /// Reads the toggle automatically from `AppEnvironmentManager`.
    func debugLayoutBoundsAuto() -> some View {
        modifier(DebugLayoutBoundsAutoModifier())
    }

    /// 当 Debug 模式开启时,长按该 view 弹 alert 显示原始值与类型。
    /// 自动从 EnvironmentObject 读取 `AppEnvironmentManager.debugLongPressInspect`。
    /// Use this on any view to opt in to the long-press inspector.
    /// Reads the toggle automatically from `AppEnvironmentManager`.
    func debugInspectAuto<T>(_ value: T, label: String) -> some View {
        modifier(DebugInspectAutoModifier(value: value, label: label))
    }
}

private struct DebugLayoutBoundsAutoModifier: ViewModifier {
    @Environment(RepositoryContainer.self) private var container
    func body(content: Content) -> some View {
        content.debugLayoutBounds(container.envManager.debugLayoutBounds)
    }
}

private struct DebugInspectAutoModifier<T>: ViewModifier {
    @Environment(RepositoryContainer.self) private var container
    let value: T
    let label: String
    func body(content: Content) -> some View {
        if container.envManager.debugLongPressInspect {
            content.debugInspect(value, label: label)
        } else {
            content
        }
    }
}

// MARK: - LLM Debug 入口（仅 DEBUG 模式可见）

/// 任意 AI 视图挂这个修饰符,DEBUG 模式下会出现 🔧 按钮,点击打开 `LLMDebugSheet`。
/// Attach this to any AI view; in DEBUG mode a 🔧 button appears that opens `LLMDebugSheet`.
/// - Parameter caller: 调用方标签,传入后在调试面板里只显示同 caller 的最近一次。
struct LLMDebugButtonModifier: ViewModifier {
    @Environment(RepositoryContainer.self) private var container
    @Environment(LLMClient.self) private var client: LLMClient
    @State private var showDebug: Bool = false
    let caller: String?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if container.envManager.debugModeEnabled {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showDebug = true
                        } label: {
                            // 带红点提示"有最近一次调用"
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "ladybug.fill")
                                    .foregroundColor(.yellow)
                                if client.lastCallInfo != nil {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 4, y: -2)
                                }
                            }
                        }
                        .accessibilityLabel("LLM Debug".localized())
                    }
                }
            }
            .sheet(isPresented: $showDebug) {
                LLMDebugSheet(filterCaller: caller)
                    .environment(container)
            }
    }
}

extension View {
    /// 在 DEBUG 模式下显示 🔧 按钮,点击打开 `LLMDebugSheet`。
    /// 传入 `caller` 可让调试面板只展示同 caller 的最近一次调用(便于多 AI 功能区分)。
    /// Show a 🔧 button in DEBUG mode that opens the LLM debug panel.
    func llmDebugButton(caller: String) -> some View {
        modifier(LLMDebugButtonModifier(caller: caller))
    }

    /// 主页专用:DEBUG 模式按钮,无 caller 过滤(显示所有 caller 的最近一次 + 分组选择器)。
    /// Home-page DEBUG button: no caller filter, so the panel shows the recent-calls picker.
    func llmDebugHomeButton() -> some View {
        modifier(LLMDebugButtonModifier(caller: nil))
    }
}

// MARK: - 卡片上的 LLM 调用指示器(DEBUG 模式显示)

/// DEBUG 模式下在卡片底部显示一行"🤖 BodyRadar · 2m 前 · 1.4s"
/// 让用户能立即看出"刚刚的 LLM 调用来自哪个卡片"。
/// In DEBUG mode, shows a small footer with the most-recent LLM call info for this caller.
struct LLMCallIndicator: View {
    @Environment(LLMClient.self) private var client: LLMClient
    @Environment(RepositoryContainer.self) private var container
    @State private var showDebug: Bool = false
    @State private var refreshDate = Date()
    let caller: String

    private var latestForCaller: LLMCallDebugInfo? {
        client.recentCalls.last(where: { $0.caller == caller })
    }

    var body: some View {
        Group {
            if container.envManager.debugModeEnabled {
                if let info = latestForCaller {
                    Button {
                        showDebug = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: info.error == nil ? "sparkles" : "exclamationmark.triangle.fill")
                                .scaledFont(size: 9)
                            Text(caller)
                                .font(.caption2.weight(.semibold))
                            Text("·")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(relativeTime(info.startTime))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("·")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1fs", info.elapsedSeconds))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(info.error == nil ? .secondary : .red)
                        }
                        .foregroundColor(.teal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.teal.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .scaledFont(size: 9)
                        Text("\(caller) · 未触发")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.08)))
                }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                refreshDate = Date()
            }
        }
        .sheet(isPresented: $showDebug) {
            LLMDebugSheet(filterCaller: caller)
                .environment(container)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = refreshDate.timeIntervalSince(date)
        if interval < 60 { return "\(Int(interval))s 前" }
        if interval < 3600 { return "\(Int(interval / 60))m 前" }
        if interval < 86400 { return "\(Int(interval / 3600))h 前" }
        return "\(Int(interval / 86400))d 前"
    }
}

#if DEBUG
#Preview {
    VStack {
        Text("Tap me long-press")
            .padding()
            .debugLayoutBounds(true)
            .debugInspect("Hello, World!", label: "Greeting")

        Text("Plain text")
            .padding()
            .debugLayoutBounds(true)
    }
}
#endif
