//
//  TrendsSubjectList.swift
//  StudyPulse
//
//  科目紧凑列表:迷你走势 + 平均 + 变化,退步的排最前(取代 2 栏大卡网格)。
//  Compact subject list: sparkline + average + delta, biggest decline first
//  (replaces the two-column card grid).
//

import SwiftUI

struct TrendsSubjectList: View {
    let rows: [SubjectTrendRow]
    let viewModel: TrendsViewModel
    let mode: TrendsDisplayMode
    var selected: String? = nil

    @Environment(RepositoryContainer.self) private var container

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            HomeZoneHeader(title: "trends.v2.zone.subjects".localized()) {
                Text("trends.v2.sort.change".localized()).foregroundStyle(.secondary)
            }
            PageCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().padding(.leading, 40) }
                        PaneLink(value: row.subject, pane: {
                            SubjectDetailPaneHost(subject: row.subject, viewModel: viewModel, mode: mode)
                        }, label: {
                            SubjectRowView(row: row, viewModel: viewModel, mode: mode, isSelected: row.subject == selected)
                                .paneSelected(row.subject)
                        })
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct SubjectRowView: View {
    let row: SubjectTrendRow
    let viewModel: TrendsViewModel
    let mode: TrendsDisplayMode
    let isSelected: Bool

    @Environment(RepositoryContainer.self) private var container

    private var color: Color { SubjectPalette.color(for: row.subject) }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(container.displayName(for: row.subject))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            MiniSparkline(values: sparkValues, color: color)
            VStack(alignment: .trailing, spacing: 0) {
                Text(primary)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .monospacedDigit()
                if mode == .score {
                    DeltaLabel(value: row.delta)
                }
            }
            .frame(minWidth: 44, alignment: .trailing)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .contentShape(Rectangle())
    }

    private var latestRank: Int? {
        viewModel.gradeHistory(for: row.subject).last(where: { ($0.ranking ?? 0) > 0 })?.ranking
    }

    private var sparkValues: [Double] {
        mode == .score
            ? row.spark
            : viewModel.gradeHistory(for: row.subject).compactMap { $0.ranking.map(Double.init) }.suffix(6).map { -$0 }
    }

    private var primary: String {
        mode == .score ? String(format: "%.0f", row.average) : (latestRank.map { "#\($0)" } ?? "—")
    }

    private var caption: String {
        let name = row.latestExamName.isEmpty ? row.latestDate.formatted(date: .abbreviated, time: .omitted) : row.latestExamName
        return String(format: "trends.v2.row.latest".localized(), row.latest, name)
    }
}
