//
//  SettingsCategory.swift
//  StudyPulse
//

import SwiftUI

// MARK: - Settings Category

enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case themeShop
    case health
    case reports
    case llm
    case data
    case about
    case faq
    case contribution

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance & Layout".localized()
        case .themeShop: return "Theme Shop".localized()
        case .health: return "Health & Readiness".localized()
        case .reports: return "Learning Reports".localized()
        case .llm: return "LLM".localized()
        case .data: return "Data Management".localized()
        case .about: return "About".localized()
        case .faq: return "FAQ".localized()
        case .contribution: return "Contribution".localized()
        }
    }

    // Compact caption shown in the main list row
    var caption: String {
        switch self {
        case .appearance: return "Language · Theme · Home · Widget".localized()
        case .themeShop: return "Primary · Cards · Timer".localized()
        case .health: return "HRV · Recovery · Focus".localized()
        case .reports: return "Weekly · Monthly · Auto Reports".localized()
        case .llm: return "AI · BYOK · Provider".localized()
        case .data: return "Import · Export · Backup".localized()
        case .about: return "Version · License".localized()
        case .faq: return "Q&A · Help".localized()
        case .contribution: return "Open Source · How to Help".localized()
        }
    }

    // Longer paragraph shown in the detail header
    var detailDescription: String {
        switch self {
        case .appearance: return "Customize the look, language, home dashboard layout and widget data.".localized()
        case .themeShop: return "Unlock primary colors, card skins and timer animations as you hit milestones.".localized()
        case .health: return "Connect Apple Health to read your HRV and get personalized study readiness suggestions.".localized()
        case .reports: return "Configure automatic weekly and monthly learning reports with charts and summaries.".localized()
        case .llm: return "Connect your own OpenAI-compatible LLM endpoint. All requests go directly to the URL you provide.".localized()
        case .data: return "Import, export and manage your grades, mistakes and exams data.".localized()
        case .about: return "App information, version and license details.".localized()
        case .faq: return "Frequently asked questions about using StudyPulse.".localized()
        case .contribution: return "How to contribute to the open source project, code of conduct, and submission process.".localized()
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: return "paintpalette.fill"
        case .themeShop: return "sparkles.rectangle.stack.fill"
        case .health: return "heart.text.square.fill"
        case .reports: return "chart.bar.xaxis"
        case .llm: return "brain"
        case .data: return "externaldrive.fill"
        case .about: return "info.circle.fill"
        case .faq: return "questionmark.circle.fill"
        case .contribution: return "hand.raised.fingers.spread.fill"
        }
    }

    var tint: Color {
        switch self {
        case .appearance: return .blue
        case .themeShop: return .purple
        case .health: return .pink
        case .reports: return .indigo
        case .llm: return .teal
        case .data: return .green
        case .about: return .orange
        case .faq: return .blue
        case .contribution: return .purple
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .appearance: AppearanceSettingsView()
        case .themeShop: ThemeShopView()
        case .health: HealthSettingsView()
        case .reports: WeeklyReportSettingsView()
        case .llm: LLMSettingsView()
        case .data: DataManagementSettingsView()
        case .about: AboutSettingsView()
        case .faq: QASettingsView()
        case .contribution: ContributionSettingsView()
        }
    }
}

// MARK: - Category Row (main list)

struct SettingsCategoryRow: View {
    let category: SettingsCategory

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(category.tint.opacity(0.15))
                Image(systemName: category.systemImage)
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundColor(category.tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .scaledFont(size: 16, weight: .medium)
                    .foregroundColor(.primary)
                Text(category.caption)
                    .scaledFont(size: 12, weight: .regular, design: .default)
                    .textCase(.uppercase)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail Header (inside each sub-page)

struct SettingsDetailHeader: View {
    let category: SettingsCategory

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(category.tint.opacity(0.18))
                Image(systemName: category.systemImage)
                    .scaledFont(size: 56, weight: .regular)
                    .foregroundColor(category.tint)
            }
            .frame(width: 110, height: 110)

            Text(category.title)
                .scaledFont(size: 22, weight: .semibold)
                .foregroundColor(.primary)

            Text(category.detailDescription)
                .scaledFont(size: 14)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
    )
    }
}
