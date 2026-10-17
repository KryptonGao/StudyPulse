//
//  MistakeAIActionBar.swift
//  StudyPulse
//
//  错题详情页底部的 AI 动作浮条:解析(主) / 相似题 / 思维导图 / 辩论。
//  Floating AI action bar at the bottom of the mistake detail page.
//

import SwiftUI

struct MistakeAIActionBar: View {
    let onAnalysis: () -> Void
    let onSimilar: () -> Void
    let onMindMap: () -> Void
    let onDebate: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onAnalysis) {
                Label("mistake.v2.ai.analysis".localized(), systemImage: "sparkles")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
            }
            secondary("mistake.v2.ai.similar".localized(), icon: "doc.badge.gearshape", action: onSimilar)
            secondary("mistake.v2.ai.mindmap".localized(), icon: "arrow.triangle.branch", action: onMindMap)
            secondary("mistake.v2.ai.debate".localized(), icon: "person.2.wave.2.fill", action: onDebate)
        }
        .buttonStyle(.plain)
        .padding(5)
        .aiGlass(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func secondary(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if sizeClass == .regular {
                    Label(title, systemImage: icon)
                } else {
                    Image(systemName: icon).accessibilityLabel(title)
                }
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(minWidth: 40, minHeight: 40)
        }
    }
}

#Preview {
    MistakeAIActionBar(onAnalysis: {}, onSimilar: {}, onMindMap: {}, onDebate: {})
        .padding()
}
