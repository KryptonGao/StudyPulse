//
//  DebugBannerView.swift
//  StudyPulse
//
//  顶部黄色 Debug Mode banner：
//  - 固定 28pt 顶部条显示 "DEBUG MODE ON" + 激活子开关数
//  - WARN / ERROR / FAULT 级别日志实时推送到 banner 下方黄色区域显示
//  - INFO / DEBUG / NOTICE 静默不推（仍可在 LogViewerView 中查看）
//  - Toast 4 秒后自动消失，最多 3 条堆叠
//
//  Top yellow Debug Mode banner:
//  - Fixed 28pt header shows "DEBUG MODE ON" + active sub-toggle count
//  - WARN / ERROR / FAULT entries stream into the yellow zone below the header
//  - INFO / DEBUG / NOTICE are silent on-screen (still visible in LogViewerView)
//  - Toasts auto-dismiss after 4s, max 3 stacked
//

import SwiftUI
import os

struct DebugBannerView: View {
    @Environment(RepositoryContainer.self) private var container
    @State private var toasterStore = LogToasterStore()

    /// 可选点击回调（默认跳转到 Debug Console）
    var onTap: (() -> Void)? = nil

    /// 当前处于激活状态的子开关数（显示在 banner 副标题里）
    private var activeSubToggles: Int {
        var n = 0
        if container.envManager.debugVerboseLogging { n += 1 }
        if container.envManager.debugFPSOverlay { n += 1 }
        if container.envManager.debugLayoutBounds { n += 1 }
        if container.envManager.debugLongPressInspect { n += 1 }
        return n
    }

    var body: some View {
        VStack(spacing: 0) {
            // 固定 28pt 头部
            header
            // WARN / ERROR 实时推送到此（最多 3 条）
            if !toasterStore.toasts.isEmpty {
                toastsColumn
            }
        }
        .background(Color.yellow)
    }

    // MARK: - Header

    private var header: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "ladybug.fill")
                    .scaledFont(size: 13, weight: .semibold)
                Text("DEBUG MODE ON".localized())
                    .scaledFont(size: 12, weight: .bold, design: .monospaced)
                if activeSubToggles > 0 {
                    Text("·")
                        .scaledFont(size: 12, weight: .bold)
                    Text("\(activeSubToggles) " + "active".localized())
                        .scaledFont(size: 11, weight: .medium, design: .monospaced)
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .scaledFont(size: 11, weight: .semibold)
                    .opacity(0.7)
            }
            .foregroundColor(.black.opacity(0.85))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Debug Mode is on. Tap to open console.")
    }

    // MARK: - Toasts column

    private var toastsColumn: some View {
        VStack(spacing: 0) {
            ForEach(toasterStore.toasts) { toast in
                ToastRow(entry: toast.entry)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Toast Row

private struct ToastRow: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: iconName)
                .scaledFont(size: 11, weight: .bold)
                .foregroundColor(badgeColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(Self.timeFormatter.string(from: entry.timestamp))
                        .scaledFont(size: 9, weight: .semibold, design: .monospaced)
                        .foregroundColor(.black.opacity(0.6))
                    Text(entry.category)
                        .scaledFont(size: 9, weight: .bold, design: .monospaced)
                        .foregroundColor(badgeColor)
                    Text(entry.level.rawValue.uppercased())
                        .scaledFont(size: 8, weight: .heavy, design: .monospaced)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(badgeColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    Spacer(minLength: 0)
                }
                Text(entry.message)
                    .scaledFont(size: 10, weight: .medium, design: .monospaced)
                    .foregroundColor(.black.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: 600)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.82))
        )
    }

    private var badgeColor: Color {
        switch entry.level {
        case .warning: return .orange
        case .error: return .red
        case .fault: return .pink
        default: return .gray
        }
    }

    private var iconName: String {
        switch entry.level {
        case .warning: return "exclamationmark.triangle.fill"
        case .error, .fault: return "xmark.octagon.fill"
        default: return "doc.text"
        }
    }
}

// MARK: - LogToasterStore

/// 消费 `LogStore.entriesStream()` 并在内存里维护一个最多 3 条、4 秒自动消失的 toast 队列。
/// 只接收 WARN / ERROR / FAULT 级别，INFO/DEBUG/NOTICE 静默不入队。
@MainActor
@Observable
final class LogToasterStore {
    struct ToastItem: Identifiable {
        let id = UUID()
        let entry: LogEntry
    }

    private(set) var toasts: [ToastItem] = []
    private let maxToasts = 3
    private let displayDuration: TimeInterval = 4.0
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    init() {
        observationTask = Task { [weak self] in
            for await entry in await LogStore.shared.entriesStream() {
                guard !Task.isCancelled else { return }
                self?.handleNewEntry(entry)
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    private func handleNewEntry(_ entry: LogEntry) {
        // 只推送 WARN / ERROR / FAULT
        guard entry.level == .warning || entry.level == .error || entry.level == .fault else {
            return
        }
        let toast = ToastItem(entry: entry)
        toasts.append(toast)
        if toasts.count > maxToasts {
            toasts.removeFirst(toasts.count - maxToasts)
        }
        // 4 秒后自动消失
        let id = toast.id
        let duration = displayDuration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            withAnimation(.easeOut(duration: 0.3)) {
                self?.toasts.removeAll { $0.id == id }
            }
        }
    }
}

#if DEBUG
#Preview {
    DebugBannerView()
        .environment(RepositoryContainer())
}
#endif
