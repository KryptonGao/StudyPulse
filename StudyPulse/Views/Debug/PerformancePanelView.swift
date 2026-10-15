//
//  PerformancePanelView.swift
//  StudyPulse
//
//  Debug → 性能面板：实时 FPS / 内存 / 卡顿统计。
//  Live FPS / memory / lag statistics for the Debug panel.
//

import SwiftUI
import Charts
import os

struct PerformancePanelView: View {
    @Environment(FPSMonitor.self) private var fpsMonitor: FPSMonitor
    @State private var memoryMB: Double = 0
    @State private var lagCount5min: Int = 0
    @State private var lastLagTimestamp: Date? = nil
    @State private var lastLagDurationMs: Double? = nil

    var body: some View {
        List {
            statsSection
            chartSection
            lastLagSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("debug.performancePanel".localized())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fpsMonitor.start()
            memoryMB = currentMemoryMB()
        }
        .onDisappear {
            // 不停 FPSMonitor — 它是 singleton,别处可能还在用
        }
        .task {
            var iteration = 0
            while !Task.isCancelled {
                await refreshLagStats()
                if iteration.isMultiple(of: 2) {
                    memoryMB = currentMemoryMB()
                }
                iteration += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        Section {
            statRow(
                title: "debug.fps".localized(),
                value: String(format: "%.0f", fpsMonitor.currentFPS),
                unit: "Hz",
                color: fpsColor,
                systemImage: "speedometer"
            )
            statRow(
                title: "debug.memory".localized(),
                value: String(format: "%.0f", memoryMB),
                unit: "MB",
                color: .blue,
                systemImage: "memorychip"
            )
            statRow(
                title: "debug.lagCount5min".localized(),
                value: "\(lagCount5min)",
                unit: "events",
                color: lagCountColor,
                systemImage: "exclamationmark.triangle"
            )
        } header: {
            Text("Live Stats".localized())
        } footer: {
            Text("FPS uses a rolling 60-frame window. Memory uses phys_footprint from task_info.".localized())
                .font(.caption2)
        }
    }

    private var chartSection: some View {
        Section {
            if fpsMonitor.recentFrameIntervalsMs.isEmpty {
                Text("Collecting data…".localized())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                Chart {
                    ForEach(Array(fpsMonitor.recentFrameIntervalsMs.enumerated()), id: \.offset) { idx, value in
                        LineMark(
                            x: .value("Frame", idx),
                            y: .value("ms", value)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    RuleMark(y: .value("60Hz", 16.7))
                        .foregroundStyle(.green.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    RuleMark(y: .value("30Hz", 33.4))
                        .foregroundStyle(.orange.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                .frame(height: 160)
                .chartYScale(domain: 0...max(50, fpsMonitor.recentFrameIntervalsMs.max() ?? 50))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            }
        } header: {
            Text("Frame Intervals (last 120 frames)".localized())
        } footer: {
            Text("Green dashed = 60 FPS (16.7ms). Orange dashed = 30 FPS (33.4ms). Higher bars = laggier frames.".localized())
                .font(.caption2)
        }
    }

    @ViewBuilder
    private var lastLagSection: some View {
        Section {
            if let ts = lastLagTimestamp, let ms = lastLagDurationMs {
                HStack {
                    Text("debug.lastLag".localized())
                    Spacer()
                    Text(String(format: "%.0f ms", ms))
                        .scaledFont(size: 14, weight: .semibold, design: .monospaced)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Text("When".localized())
                    Spacer()
                    Text(ts.formatted(date: .omitted, time: .standard))
                        .scaledFont(size: 12, design: .monospaced)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No lag events recorded.".localized())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Last Main-Thread Lag".localized())
        }
    }

    // MARK: - Helpers

    private func statRow(title: String, value: String, unit: String, color: Color, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .scaledFont(size: 18)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(title)
                .scaledFont(size: 15)
            Spacer()
            Text(value)
                .scaledFont(size: 20, weight: .bold, design: .monospaced)
                .foregroundStyle(color)
            Text(unit)
                .scaledFont(size: 12)
                .foregroundStyle(.secondary)
        }
    }

    private var fpsColor: Color {
        if fpsMonitor.currentFPS >= 55 { return .green }
        if fpsMonitor.currentFPS >= 30 { return .orange }
        return .red
    }

    private var lagCountColor: Color {
        if lagCount5min == 0 { return .green }
        if lagCount5min < 5 { return .orange }
        return .red
    }

    private func refreshLagStats() async {
        let lagCount = await LogStore.shared.recentLagCount(within: 300)
        let lastEvent = await LogStore.shared.lastLagEvent
        lagCount5min = lagCount
        if let event = lastEvent {
            lastLagTimestamp = event.timestamp
            // 尝试从 message 提取毫秒数: "主线程卡顿 / Main thread lag: 45 ms (3 帧)"
            lastLagDurationMs = parseMs(from: event.message)
        } else {
            lastLagTimestamp = nil
            lastLagDurationMs = nil
        }
    }

    private func parseMs(from message: String) -> Double? {
        // 尝试匹配 "NNN ms" 模式
        let pattern = #"(\d+(?:\.\d+)?)\s*ms"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        guard let match = regex.firstMatch(in: message, range: range),
              let r = Range(match.range(at: 1), in: message) else { return nil }
        return Double(message[r])
    }

    /// 读取当前进程 phys_footprint（MB）
    private func currentMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        // phys_footprint 是字节
        let bytes = Double(info.phys_footprint)
        return bytes / 1024.0 / 1024.0
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PerformancePanelView()
            .environment(FPSMonitor.shared)
    }
}
#endif
