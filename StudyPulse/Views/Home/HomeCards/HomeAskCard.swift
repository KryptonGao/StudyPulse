//
//  HomeAskCard.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/7/11.
//
//  主页 AI 提问入口卡。
//  - display-only 输入框样式,提示文本随上下文切换
//    ("未配置" / "问点什么..." / 一些推荐问题)
//  - 点击整个卡片或输入框 → 弹出 HomeAskSheet
//  - 不参与长按分享(不能导出"输入框"图片)
//
//  Home AI-Ask entry card.
//  - Display-only input-box style; placeholder text switches with context
//    ("Not configured" / "Ask anything..." / some suggested questions).
//  - Tap on the whole card or the input → presents HomeAskSheet.
//  - Does NOT participate in long-press share (cannot export an "input box" image).
//

import SwiftUI

/// 主页 AI 提问卡片:点击弹出 HomeAskSheet
/// Home AI-Ask card: tap to present HomeAskSheet.
struct HomeAskCard: View {
    @Environment(RepositoryContainer.self) private var container
    /// 是否正在显示 HomeAskSheet
    /// Whether the HomeAskSheet is currently presented.
    @State private var showSheet: Bool = false

    /// 卡片副标题(占位文本):AI 未配置时显示引导文案,否则显示「Ask anything...」
    /// Card subtitle (placeholder text): shows onboarding hint when AI is unconfigured, otherwise "Ask anything...".
    private var placeholder: String {
        if !container.envManager.llmConfig.isConfigured {
            return "未配置 AI · 前往设置".localized()
        }
        return "Ask anything...".localized()
    }

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.teal, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 36, height: 36)
                    Image(systemName: "text.bubble.fill")
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Ask AI".localized())
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        if container.envManager.llmConfig.isConfigured {
                            HStack(spacing: 2) {
                                Image(systemName: "sparkles")
                                    .scaledFont(size: 9, weight: .bold)
                                Text("AI".localized())
                                    .font(.caption2.weight(.bold))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.teal.opacity(0.18)))
                            .foregroundColor(.teal)
                        }
                    }
                    Text(placeholder)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.circle.fill")
                    .scaledFont(size: 22)
                    .foregroundStyle(.tertiary)
            }
            .padding(DesignToken.Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        container.envManager.llmConfig.isConfigured
                            ? Color.teal.opacity(0.25)
                            : Color.secondary.opacity(0.15),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            HomeAskSheet(container: container, envManager: container.envManager)
        }
    }
}
