//
//  DebugFPSOverlayView.swift
//  StudyPulse
//
//  主页面右上角的 mini 浮窗:实时 FPS / 内存(MB) / 日志条数。点击展开为 PerformancePanel。
//  Floating mini panel anchored to the top-right of every main page.
//

import SwiftUI
import os

struct DebugFPSOverlayView: View {
    @Environment(FPSMonitor.self) private var fpsMonitor: FPSMonitor
    @Environment(RepositoryContainer.self) private var container
    @State private var memoryMB: Double = 0
    @State private var logCount: Int = 0
    @State private var expanded: Bool = false

    var body: some View {
        Group {
            if expanded {
                expandedPanel
            } else {
                compactChip
            }
        }
        .onAppear {
            fpsMonitor.start()
            memoryMB = currentMemoryMB()
        }
        .task {
            while !Task.isCancelled {
                memoryMB = currentMemoryMB()
                let entries = await LogStore.shared.allEntries
                logCount = entries.count
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Compact chip

    private var compactChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "speedometer")
                .scaledFont(size: 10, weight: .semibold)
            Text(String(format: "%.0f", fpsMonitor.currentFPS))
                .scaledFont(size: 11, weight: .bold, design: .monospaced)
            Text("·")
                .scaledFont(size: 10)
            Text(String(format: "%.0fM", memoryMB))
                .scaledFont(size: 10, design: .monospaced)
            Image(systemName: "chevron.left")
                .scaledFont(size: 9, weight: .semibold)
                .opacity(0.6)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.black.opacity(0.65))
        )
        .onTapGesture { expanded = true }
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("FPS", value: String(format: "%.0f", fpsMonitor.currentFPS), color: fpsColor)
            row("Memory", value: String(format: "%.0f MB", memoryMB), color: .blue)
            row("Logs", value: "\(logCount) / 5000", color: .gray)
            HStack {
                Spacer()
                Image(systemName: "chevron.up")
                    .scaledFont(size: 10, weight: .semibold)
                    .opacity(0.6)
            }
        }
        .padding(8)
        .frame(width: 130)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.7))
        )
        .onTapGesture { expanded = false }
    }

    private func row(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .scaledFont(size: 10, weight: .semibold, design: .monospaced)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .scaledFont(size: 11, weight: .bold, design: .monospaced)
                .foregroundColor(color)
        }
    }

    private var fpsColor: Color {
        if fpsMonitor.currentFPS >= 55 { return .green }
        if fpsMonitor.currentFPS >= 30 { return .orange }
        return .red
    }

    private func currentMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1024.0 / 1024.0
    }
}
