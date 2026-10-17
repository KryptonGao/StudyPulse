//
//  AIWaitingView.swift
//  StudyPulse
//
//  Created by Antigravity on 2026/7/13.
//  Copyright © 2026 Chenkai Gao. All rights reserved.
//

import SwiftUI

/// 整页生成类 AI 流程(相似题 / 思维导图 / 考试倒推)的等待页。
/// 与对话界面共用同一套样式:流光背景 + 玻璃卡片 + 呼吸的星芒 + 轮换的状态文案。
///
/// Full-screen waiting view for generation-style AI flows (similar questions,
/// mind map, exam reverse planner). Shares the chat style: flowing background,
/// glass card, breathing sparkle mark and cycling status lines.
struct AIWaitingView: View {
    /// 加载状态标题(如:“AI 正在构思变式题...”)
    /// Loading title.
    let title: String

    /// 可选的取消操作回调
    /// Optional cancellation callback.
    var onCancel: (() -> Void)? = nil

    /// 轮回切换的状态语句列表
    /// List of status messages to cycle through.
    let messages: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentTextIndex = 0
    @State private var start = Date()

    init(title: String, messages: [String], onCancel: (() -> Void)? = nil) {
        self.title = title
        self.messages = messages.isEmpty ? [
            "AI正在结合历史数据...".localized(),
            "AI正在提炼表达...".localized(),
            "AI正在构建逻辑模型...".localized(),
            "AI正在为您生成专属内容...".localized()
        ] : messages
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            AIChatFlowingBackground()
                .ignoresSafeArea()

            VStack(spacing: 22) {
                mark

                VStack(spacing: 10) {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(messages[currentTextIndex % messages.count])
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)))
                        .id(currentTextIndex)
                }
                // 固定高度,避免文案长短不一时布局抖动
                // Fixed height so differing line lengths don't shift the layout.
                .frame(height: 72)

                if let onCancel {
                    Button(action: onCancel) {
                        Text("Cancel".localized())
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 22)
                            .frame(minHeight: 36)
                            .aiGlass(Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 28)
            .aiGlass(RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 36)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { break }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.1)) {
                    currentTextIndex = (currentTextIndex + 1) % messages.count
                }
            }
        }
    }

    /// 与回复头部同款的星芒,放大后在卡片中呼吸并显示已等待秒数。
    /// The same sparkle mark as the reply header, larger, breathing, with elapsed seconds.
    private var mark: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 20 : nil)) { context in
            let time = max(context.date.timeIntervalSince(start), 0)
            let wave = sin(.pi * (time / 2.2).truncatingRemainder(dividingBy: 1))
            let breath = wave * wave
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.primary)
                        .scaleEffect(reduceMotion ? 1 : 1 - 0.14 * breath)
                    Image(systemName: "sparkle")
                        .scaledFont(size: 28, weight: .semibold)
                        .foregroundStyle(Color(.systemBackground))
                        .rotationEffect(.degrees(reduceMotion ? 0 : breath * 45))
                }
                .frame(width: 64, height: 64)
                .opacity(reduceMotion ? 0.55 + 0.45 * breath : 1)

                Text("\(Int(time))s")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    AIWaitingView(
        title: "AI 正在构思变式题...",
        messages: [
            "AI正在结合历史数据...",
            "AI正在提炼表达...",
            "正在为您量身定制变式训练..."
        ],
        onCancel: {}
    )
}
