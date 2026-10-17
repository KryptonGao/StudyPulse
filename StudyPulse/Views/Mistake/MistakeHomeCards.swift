//
//  MistakeHomeCards.swift
//  StudyPulse
//
//  错题首页的四个区块:今日复习主卡 / 工具列 / 弱点并排 / 科目与最近新增列表。
//  Mistakes home blocks: today's review hero, tool row, weak spots, subject & recent lists.
//

import SwiftUI

// MARK: - Review hero

struct MistakeReviewHeroCard: View {
    let breakdown: MistakeReviewBreakdown
    let dueTags: [TagDueEntry]
    let onStart: (FlashcardFilter) -> Void

    @Environment(RepositoryContainer.self) private var container

    private var accent: Color { container.envManager.effectiveAccentColor }

    var body: some View {
        PageCard {
            if breakdown.total == 0 {
                allClear
            } else {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Label("mistake.v2.review.title".localized(), systemImage: "repeat")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(accent)
                        Spacer()
                        Text(String(format: "mistake.v2.review.minutes".localized(), breakdown.estimatedMinutes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(breakdown.total)")
                            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("mistake.v2.review.due".localized())
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }
                    breakdownBar
                    HStack(spacing: DesignToken.Spacing.small) {
                        Button { onStart(.dueQueue) } label: {
                            Label("mistake.v2.review.start".localized(), systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        focusMenu
                    }
                    .buttonBorderShape(.roundedRectangle(radius: DesignToken.CornerRadius.large))
                }
            }
        }
        .background(alignment: .topTrailing) {
            RadialGradient(colors: [accent.opacity(0.16), .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
                .clipShape(RoundedRectangle(cornerRadius: DesignToken.CornerRadius.card))
                .allowsHitTesting(false)
        }
    }

    private var allClear: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("mistake.v2.review.clear".localized())
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(String(format: "mistake.v2.review.upcoming".localized(), breakdown.upcoming))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var breakdownBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(breakdown.bySubject) { item in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(SubjectPalette.color(for: item.subject))
                            .frame(width: max(4, (proxy.size.width - CGFloat(breakdown.bySubject.count - 1) * 2) * CGFloat(item.count) / CGFloat(max(breakdown.total, 1))))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            FlowRow(spacing: 12) {
                ForEach(breakdown.bySubject.prefix(4)) { item in
                    HStack(spacing: 5) {
                        Circle().fill(SubjectPalette.color(for: item.subject)).frame(width: 8, height: 8)
                        Text("\(container.displayName(for: item.subject)) \(item.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if breakdown.overdue > 0 {
                    Text(String(format: "mistake.v2.review.overdue".localized(), breakdown.overdue))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var focusMenu: some View {
        Menu {
            Section("mistake.v2.review.bySubject".localized()) {
                ForEach(breakdown.bySubject.prefix(6)) { item in
                    Button("\(container.displayName(for: item.subject)) · \(item.count)") {
                        onStart(.subject(item.subject))
                    }
                }
            }
            if !dueTags.isEmpty {
                Section("Review by Tag".localized()) {
                    ForEach(dueTags.prefix(6)) { entry in
                        Button("#\(entry.tag) · \(entry.count)") { onStart(.tag(entry.tag)) }
                    }
                }
            }
        } label: {
            Label("mistake.v2.review.focus".localized(), systemImage: "line.3.horizontal.decrease")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .fixedSize()
    }
}

/// 简单的自动换行行布局 / A simple wrapping row layout.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (points, CGSize(width: maxX, height: y + rowHeight))
    }
}

// MARK: - Tools

struct MistakeToolsRow: View {
    struct Tool: Identifiable {
        let id: String
        let title: String
        let icon: String
        let tint: Color
        var enabled = true
        let action: () -> Void
    }

    let tools: [Tool]

    var body: some View {
        HStack(spacing: DesignToken.Spacing.small) {
            ForEach(tools) { tool in
                Button(action: tool.action) {
                    VStack(spacing: 6) {
                        Image(systemName: tool.icon)
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(tool.tint)
                            .frame(width: 34, height: 34)
                            .background(tool.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
                        Text(tool.title)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .cardSkin()
                }
                .buttonStyle(.plain)
                .disabled(!tool.enabled)
                .opacity(tool.enabled ? 1 : 0.45)
            }
        }
    }
}

// MARK: - Weak spots

struct MistakeWeakSpotsRow: View {
    let faultLine: KnowledgeFaultLine?
    let pattern: MistakePatternSummary?
    let patterns: [MistakePatternSummary]
    let container: RepositoryContainer

    var body: some View {
        if faultLine != nil || pattern != nil {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HomeZoneHeader(title: "mistake.v2.zone.weak".localized())
                HStack(alignment: .top, spacing: DesignToken.Spacing.medium) {
                    if let faultLine {
                        NavigationLink {
                            KnowledgeFaultLineView(container: container).environment(container)
                        } label: {
                            weakCard(
                                icon: "bolt.fill", tint: .red,
                                kind: "knowledge.fault.home.title".localized(),
                                title: faultLine.foundationConcept,
                                detail: String(format: "mistake.v2.weak.fault".localized(), Int(faultLine.riskScore * 100), faultLine.impactMistakeCount),
                                progress: faultLine.riskScore
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if let pattern {
                        NavigationLink {
                            MistakePatternGalleryView(summaries: patterns)
                        } label: {
                            weakCard(
                                icon: "repeat", tint: .purple,
                                kind: "mistake.v2.weak.pattern".localized(),
                                title: pattern.pattern.displayName,
                                detail: String(format: "mistake.v2.weak.patternCount".localized(), pattern.recentCount, pattern.subjects.count),
                                progress: pattern.riskScore
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func weakCard(icon: String, tint: Color, kind: String, title: String, detail: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(kind, systemImage: icon)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            ProgressView(value: max(0, min(1, progress))).tint(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .padding(14)
        .cardSkin()
    }
}

// MARK: - Subject list

struct MistakeSubjectList: View {
    let summaries: [MistakeSubjectSummary]
    let mistakesBySubject: [String: [MistakeNote]]
    let onShowTags: (() -> Void)?

    @Environment(RepositoryContainer.self) private var container

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            HomeZoneHeader(title: "Subjects".localized()) {
                if let onShowTags {
                    Button("Tag Graph".localized(), action: onShowTags)
                }
            }
            PageCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(summaries.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 62) }
                        PaneLink(id: item.subject, destination: {
                            SubjectMistakesView(subject: item.subject, mistakes: mistakesBySubject[item.subject] ?? [])
                        }, label: {
                            row(item).paneSelected(item.subject)
                        })
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ item: MistakeSubjectSummary) -> some View {
        HStack(spacing: 12) {
            MiniRing(
                progress: item.mastery,
                color: SubjectPalette.color(for: item.subject),
                lineWidth: 4, size: 34,
                label: String(format: "%.0f", item.mastery * 100)
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(container.displayName(for: item.subject))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                HStack(spacing: 4) {
                    Text(String(format: "mistake.v2.subject.count".localized(), item.count))
                    if item.due > 0 {
                        Text("·")
                        Text(String(format: "mistake.v2.subject.due".localized(), item.due))
                            .foregroundStyle(.orange)
                            .fontWeight(.semibold)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - Mistake rows

struct MistakeRecentList: View {
    let title: String
    let trailing: String?
    let mistakes: [MistakeNote]
    var selection: UUID? = nil

    @Environment(RepositoryContainer.self) private var container

    var body: some View {
        if !mistakes.isEmpty {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HomeZoneHeader(title: title) {
                    if let trailing { Text(trailing).foregroundStyle(.secondary) }
                }
                PageCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(mistakes.enumerated()), id: \.element.id) { index, note in
                            if index > 0 { Divider().padding(.leading, 70) }
                            PaneLink(id: note.id, destination: {
                                MistakeSetDetailView(mistakeSet: note)
                            }, label: {
                                MistakeRow(note: note, isSelected: note.id == selection)
                                    .paneSelected(note.id)
                            })
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct MistakeRow: View {
    let note: MistakeNote
    var isSelected = false

    @Environment(RepositoryContainer.self) private var container

    private var color: Color { SubjectPalette.color(for: note.subject) }

    private var masteryColor: Color {
        note.masteryScore < 0.5 ? .red : (note.masteryScore < 0.7 ? .orange : .green)
    }

    private var dueText: String? {
        guard let days = MistakeHomeEngine.daysUntilReview(note) else { return nil }
        if days < 0 { return "mistake.v2.row.overdue".localized() }
        if days == 0 { return "mistake.v2.row.today".localized() }
        if days == 1 { return "mistake.v2.row.tomorrow".localized() }
        return String(format: "mistake.v2.row.days".localized(), days)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(String(container.displayName(for: note.subject).prefix(2)))
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? note.originalQuestion : note.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if !note.tags.isEmpty {
                        Text(note.tags.prefix(2).map { "#\($0)" }.joined(separator: " "))
                    }
                    if let dueText {
                        if !note.tags.isEmpty { Text("·") }
                        Text(dueText)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            MiniRing(progress: note.masteryScore, color: masteryColor, lineWidth: 3.5, size: 24)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .contentShape(Rectangle())
    }
}
