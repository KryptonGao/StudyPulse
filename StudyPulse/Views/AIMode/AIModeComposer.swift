//
//  AIModeComposer.swift
//  StudyPulse
//
//  Bottom input of AI Mode: reference chips, multiline text, a "+" menu that
//  attaches data references, the reasoning gauge and send / stop.
//

import SwiftUI

/// Shared label helpers so every surface names scopes the same way.
enum AIModeLabels {
    static func scopeText(_ kind: AIDateScopeKind) -> String {
        switch kind {
        case .last7Days: return "aiMode.scope.last7".localized()
        case .last30Days: return "aiMode.scope.last30".localized()
        case .last90Days: return "aiMode.scope.last90".localized()
        case .phaseAll: return "aiMode.scope.phase".localized()
        case .custom: return "aiMode.scope.custom".localized()
        }
    }

    static func domainName(_ domain: AIDataDomain) -> String {
        "aiMode.domain.\(domain.rawValue)".localized()
    }

    /// "Grades · Last 30 days"; domains without a time axis use only the name.
    static func referenceLabel(_ domain: AIDataDomain, scope: AIDateScope, subject: String? = nil) -> String {
        var parts = [domainName(domain)]
        if let subject, !subject.isEmpty { parts.append(subject) }
        switch domain {
        case .grades, .time, .health, .diary, .mistakes:
            parts.append(scopeText(scope.kind))
        case .exams:
            break
        }
        return parts.joined(separator: " · ")
    }
}

struct AIModeComposer: View {
    var viewModel: AIModeViewModel
    @Environment(\.aiTheme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var vm = viewModel
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.pendingReferences.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.pendingReferences) { reference in
                            referenceChip(reference)
                        }
                    }
                }
            }
            TextField("aiMode.composer.placeholder".localized(), text: $vm.draft, axis: .vertical)
                .lineLimit(1...5)
                .font(.body)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { viewModel.send() }
                .padding(.horizontal, 4)
            HStack(spacing: 8) {
                plusMenu
                Spacer(minLength: 0)
                AIReasoningGaugeButton(viewModel: viewModel)
                sendButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // The input floats on a Liquid Glass surface (material before iOS 26) so replies scroll behind it.
        .aiGlass(RoundedRectangle(cornerRadius: 28, style: .continuous), interactive: true)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .padding(.top, 4)
        // The reasoning slider floats above the composer, which stays visible underneath. Never disable hit
        // testing here while it is open: that drops the text field's focus and dismisses the keyboard.
    }

    // MARK: Pieces

    private func referenceChip(_ reference: AIDataReference) -> some View {
        HStack(spacing: 4) {
            Image(systemName: reference.domain.systemImage).font(.caption2)
            Text(reference.scopeLabel).font(.caption).lineLimit(1)
            Button {
                viewModel.removeReference(reference.id)
            } label: {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("aiMode.reference.remove".localized())
        }
        .foregroundStyle(theme.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(theme.accentSoft, in: Capsule())
    }

    private var plusMenu: some View {
        Menu {
            Section("aiMode.composer.attach".localized()) {
                ForEach(AIDataDomain.allCases) { domain in
                    Button {
                        let scope = AIDateScope.last30Days
                        viewModel.attach(AIDataReference(
                            domain: domain,
                            scopeLabel: AIModeLabels.referenceLabel(domain, scope: scope),
                            scope: scope,
                            phaseId: viewModel.activePhaseId
                        ))
                    } label: {
                        Label(AIModeLabels.domainName(domain), systemImage: domain.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.medium))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(theme.ink)
        .accessibilityLabel("aiMode.composer.attach".localized())
    }

    @ViewBuilder
    private var sendButton: some View {
        if viewModel.isGenerating {
            Button { viewModel.stop() } label: {
                Image(systemName: "stop.fill")
                    .font(.body.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(theme.ink)
            .accessibilityLabel("aiMode.action.stop".localized())
        } else {
            Button {
                viewModel.send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(theme.accent)
            .disabled(!viewModel.canSend)
            .accessibilityLabel("aiMode.action.send".localized())
        }
    }
}
