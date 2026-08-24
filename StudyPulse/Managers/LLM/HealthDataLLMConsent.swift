//
//  HealthDataLLMConsent.swift
//  StudyPulse
//
//  Central privacy gate and user-facing explanation for health-sensitive AI.
//

import SwiftUI

@MainActor
enum HealthDataLLMConsentManager {
    static func grant(container: RepositoryContainer) {
        container.envManager.preferences.healthDataLLMSharingEnabled = true
    }

    static func revoke(container: RepositoryContainer) {
        container.envManager.preferences.healthDataLLMSharingEnabled = false
        Task { await LLMResponseCache.shared.clear() }
    }
}

/// A single reusable explanation used both at the first health-sensitive AI
/// trigger and from Health settings.
struct HealthDataLLMConsentSheet: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    let onDecision: (Bool) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.teal.gradient)

                Text("Allow health data in AI requests?".localized())
                    .font(.title2.bold())

                Text("StudyPulse can optionally include HealthKit-derived recovery signals and mood or energy summaries in requests to your selected AI endpoint. This is separate from Apple Health permission and is off by default.".localized())
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Local recovery algorithms continue to work if you decline.".localized(), systemImage: "checkmark.circle")
                    Label("You can revoke access at any time; cached AI responses will be cleared.".localized(), systemImage: "arrow.uturn.backward.circle")
                    Label("The selected endpoint processes the data under its own privacy policy.".localized(), systemImage: "network")
                }
                .font(.subheadline)

                Spacer()

                Button {
                    HealthDataLLMConsentManager.grant(container: container)
                    onDecision(true)
                    dismiss()
                } label: {
                    Text("Allow and continue".localized())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    HealthDataLLMConsentManager.revoke(container: container)
                    onDecision(false)
                    dismiss()
                } label: {
                    Text("Not now".localized())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .navigationTitle("AI health privacy".localized())
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
