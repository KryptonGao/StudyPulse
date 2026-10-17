//
//  TrendsAttentionCard.swift
//  StudyPulse
//
//  「需要关注」行动卡:给出原因 + 三个事实 + 直达动作(复习错题 / 看详情)。
//  "Needs attention" action card: reason, three facts and direct actions.
//

import SwiftUI

struct TrendsAttentionCard: View {
    let insights: [AttentionInsight]
    let viewModel: TrendsViewModel

    @Environment(RepositoryContainer.self) private var container
    @Environment(\.selectAppTab) private var selectAppTab

    var body: some View {
        if let first = insights.first {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HomeZoneHeader(title: "Subjects Needing Attention".localized())
                VStack(spacing: DesignToken.Spacing.medium) {
                    primary(first)
                    if insights.count > 1 {
                        others(Array(insights.dropFirst()))
                    }
                }
            }
        }
    }

    // MARK: Primary

    private func primary(_ insight: AttentionInsight) -> some View {
        let name = container.displayName(for: insight.subject)
        return VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 38, height: 38)
                    .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(.headline, design: .rounded, weight: .bold))
                    Text(reason(for: insight)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.0f", insight.average))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    DeltaLabel(value: insight.delta)
                }
            }

            HStack(spacing: DesignToken.Spacing.small) {
                StatTile(value: "\(insight.dueMistakes)", label: "trends.v2.fact.due".localized(),
                         tint: insight.dueMistakes > 0 ? .orange : .primary)
                StatTile(value: insight.nextExamInDays.map { "D-\($0)" } ?? "—", label: "trends.v2.fact.exam".localized())
                StatTile(value: insight.gapToTarget.map { String(format: "%+.0f", -$0) } ?? "—",
                         label: "trends.v2.fact.target".localized(),
                         tint: (insight.gapToTarget ?? 0) > 0 ? .red : .primary)
            }

            HStack(spacing: DesignToken.Spacing.small) {
                if insight.dueMistakes > 0 {
                    Button {
                        selectAppTab(.mistake)
                    } label: {
                        Label(String(format: "trends.v2.action.review".localized(), insight.dueMistakes), systemImage: "book.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                PaneLink(value: insight.subject, pane: {
                    SubjectDetailPaneHost(subject: insight.subject, viewModel: viewModel, mode: .score)
                }, label: {
                    Label("trends.v2.action.detail".localized(), systemImage: "chart.line.uptrend.xyaxis")
                        .frame(maxWidth: insight.dueMistakes > 0 ? nil : .infinity)
                })
                .buttonStyle(.bordered)
            }
            .controlSize(.regular)
            .buttonBorderShape(.capsule)
        }
        .padding(DesignToken.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DesignToken.CornerRadius.extraLarge - 4, style: .continuous)
                .fill(Color.orange.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.CornerRadius.extraLarge - 4, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private func reason(for insight: AttentionInsight) -> String {
        var parts: [String] = []
        if insight.consecutiveDeclines >= 2 {
            parts.append(String(format: "trends.v2.reason.declines".localized(), insight.consecutiveDeclines))
        }
        if let gap = insight.gapToTarget, gap > 0 {
            parts.append(String(format: "trends.v2.reason.gap".localized(), gap))
        }
        if parts.isEmpty { parts.append("trends.v2.reason.low".localized()) }
        return parts.joined(separator: " · ")
    }

    // MARK: Others

    private func others(_ rest: [AttentionInsight]) -> some View {
        PageCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(rest.enumerated()), id: \.element.id) { index, insight in
                    if index > 0 { Divider().padding(.leading, 16) }
                    PaneLink(value: insight.subject, pane: {
                        SubjectDetailPaneHost(subject: insight.subject, viewModel: viewModel, mode: .score)
                    }, label: {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).imageScale(.small)
                            Text(container.displayName(for: insight.subject)).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(reason(for: insight)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    })
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
