//
//  AIModeWelcomeView.swift
//  StudyPulse
//
//  Empty-conversation state: time-of-day greeting with the user's name and
//  three starter questions that attach the matching data scope.
//

import SwiftUI

struct AIModeWelcomeView: View {
    var viewModel: AIModeViewModel
    let onOpenAISettings: () -> Void

    @Environment(\.aiTheme) private var theme

    private struct Starter: Identifiable {
        let id: Int
        let textKey: String
        let domain: AIDataDomain
    }

    private let starters: [Starter] = [
        Starter(id: 1, textKey: "aiMode.suggestion.grades", domain: .grades),
        Starter(id: 2, textKey: "aiMode.suggestion.mistakes", domain: .mistakes),
        Starter(id: 3, textKey: "aiMode.suggestion.exams", domain: .exams),
    ]

    private var greetingKey: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "aiMode.greeting.morning"
        case 12..<18: return "aiMode.greeting.afternoon"
        case 18..<23: return "aiMode.greeting.evening"
        default: return "aiMode.greeting.night"
        }
    }

    /// Greeting with the profile name; an empty name drops the dangling separator.
    private var greeting: String {
        let name = viewModel.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = String(format: greetingKey.localized(), name)
        guard name.isEmpty else { return text }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ,，、"))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AISproutMark(size: 34)
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .scaledFont(size: 30, weight: .semibold, design: theme.titleDesign)
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("aiMode.welcome.subtitle".localized())
                        .font(.subheadline)
                        .foregroundStyle(theme.muted)
                }
                if !viewModel.isConfigured {
                    Button(action: onOpenAISettings) {
                        Label("aiMode.welcome.unconfigured".localized(), systemImage: "info.circle")
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(theme.accent)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 0) {
                    ForEach(starters) { starter in
                        Button {
                            ask(starter)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: starter.domain.systemImage)
                                    .font(.subheadline)
                                    .foregroundStyle(theme.muted)
                                    .frame(width: 24)
                                Text(starter.textKey.localized())
                                    .font(.subheadline)
                                    .foregroundStyle(theme.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if starter.id != starters.last?.id {
                            Divider().overlay(theme.line)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 36)
            .padding(.bottom, 24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func ask(_ starter: Starter) {
        let scope = AIDateScope.last30Days
        viewModel.attach(AIDataReference(
            domain: starter.domain,
            scopeLabel: AIModeLabels.referenceLabel(starter.domain, scope: scope),
            scope: scope,
            phaseId: viewModel.activePhaseId
        ))
        viewModel.send(starter.textKey.localized())
    }
}
