//
//  AIModeDataPage.swift
//  StudyPulse
//
//  Shell of a data page (header, title, scroll body, fixed "chat about my …"
//  button) plus shared row / card pieces. The six domain bodies live in
//  `AIModeDataSections.swift`.
//

import SwiftUI

struct AIModeDataPage: View {
    let domain: AIDataDomain
    var viewModel: AIModeViewModel
    let onDrawer: () -> Void

    @Environment(\.aiTheme) private var theme

    private var data: AIModeDataViewModel { viewModel.dataViewModel }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleBlock
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .aiModeToolbar(
            title: AIModeLabels.domainName(domain),
            trailing: .back,
            onDrawer: onDrawer,
            onTrailing: { viewModel.backToChat() }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) { chatButton }
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("aiMode.data.eyebrow".localized())
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.muted)
            Text(AIModeLabels.domainName(domain))
                .scaledFont(size: 30, weight: .semibold, design: theme.titleDesign)
                .foregroundStyle(theme.ink)
            Text(scopeNote)
                .font(.footnote)
                .foregroundStyle(theme.muted)
        }
    }

    /// States which slice of data the page shows: phase-filtered or not.
    private var scopeNote: String {
        switch domain {
        case .time, .health:
            return "aiMode.data.scope.allTime".localized()
        case .grades, .mistakes, .exams, .diary:
            if let name = viewModel.phaseName, !name.isEmpty {
                return String(format: "aiMode.data.scope.phase".localized(), name)
            }
            return "aiMode.data.scope.noPhase".localized()
        }
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch domain {
        case .grades: AIGradesSection(data: data)
        case .mistakes: AIMistakesSection(snapshot: data.snapshot.mistakes)
        case .exams: AIExamsSection(snapshot: data.snapshot.exams)
        case .time: AITimeSection(snapshot: data.snapshot.time)
        case .health: AIHealthSection(snapshot: data.snapshot.health)
        case .diary: AIDiarySection(snapshot: data.snapshot.diary)
        }
    }

    // MARK: Chat button

    private var chatButton: some View {
        Button {
            let scope = chatScope
            viewModel.askAbout(
                domain,
                scope: scope,
                scopeLabel: AIModeLabels.referenceLabel(domain, scope: scope)
            )
        } label: {
            Text(String(format: "aiMode.data.chatAbout".localized(), AIModeLabels.domainName(domain)))
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(theme.accent)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// Carries the page's current period into the chat reference.
    private var chatScope: AIDateScope {
        domain == .grades ? data.gradeRange.scope : .last30Days
    }
}

// MARK: - Shared pieces

/// Rounded surface used by data sections.
struct AIDataCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.aiTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.soft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct AIMetricLabel: View {
    let value: String
    let caption: String
    @Environment(\.aiTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .scaledFont(size: 28, weight: .semibold, design: theme.titleDesign)
                .foregroundStyle(theme.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(caption)
                .font(.caption)
                .foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct AIEmptyNote: View {
    let text: String
    @Environment(\.aiTheme) private var theme

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(theme.soft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// A tappable row that pushes `route`.
struct AIDataRow: View {
    let title: String
    var subtitle: String?
    var trailing: String?
    var systemImage: String?
    var route: AIModeRoute?
    @Environment(\.aiTheme) private var theme

    var body: some View {
        if let route {
            NavigationLink(value: route) { row(showsChevron: true) }
                .buttonStyle(.plain)
        } else {
            row(showsChevron: false)
        }
    }

    private func row(showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(theme.muted)
                    .frame(width: 30, height: 30)
                    .background(theme.soft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(theme.ink).lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(theme.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.subheadline.weight(.medium)).foregroundStyle(theme.accent)
            }
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(theme.muted)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
    }
}

enum AIFormat {
    static func percent(_ value: Double) -> String { String(format: "%.0f%%", value) }
    static func signed(_ value: Double, digits: Int = 1) -> String {
        String(format: "%+.\(digits)f", value)
    }
    static func hours(_ seconds: Int) -> String { String(format: "%.1f h", Double(seconds) / 3600) }
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month().day())
    }
}
