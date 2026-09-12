//
//  CloudAIQuotaView.swift
//  StudyPulse
//
//  Remaining Cloud AI request / token quota from the user dashboard API.
//

import SwiftUI

struct CloudAIQuotaView: View {
    let snapshot: CloudAIQuotaSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            quotaRow(
                title: "Daily requests".localized(),
                remaining: snapshot.remainingDayRequests,
                limit: snapshot.dailyRequestLimit,
                used: snapshot.usedDayRequests,
                progress: snapshot.dayProgress,
                unlimited: snapshot.isDailyUnlimited
            )
            quotaRow(
                title: "Monthly AI Points".localized(),
                remaining: snapshot.remainingMonthPoints,
                limit: snapshot.monthlyPointLimit,
                used: snapshot.usedMonthPoints,
                progress: snapshot.monthProgress,
                unlimited: snapshot.isMonthlyUnlimited
            )
        }
    }

    private func quotaRow(
        title: String,
        remaining: Int?,
        limit: Int?,
        used: Int,
        progress: Double,
        unlimited: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(valueText(remaining: remaining, limit: limit, unlimited: unlimited))
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(unlimited ? Color.secondary : (progress >= 1 ? Color.red : Color.primary))
            }
            if !unlimited {
                ProgressView(value: progress)
                    .tint(progress >= 0.9 ? .orange : .teal)
                Text(String(format: "Used: %@".localized(), formatted(used)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func valueText(remaining: Int?, limit: Int?, unlimited: Bool) -> String {
        if unlimited { return "Unlimited".localized() }
        guard let remaining, let limit else { return "—" }
        return String(
            format: "%@ remaining of %@".localized(),
            formatted(remaining),
            formatted(limit)
        )
    }

    private func formatted(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// Shared remaining-quota section with an explicit refresh action.
struct CloudAIQuotaListSection: View {
    @Environment(RepositoryContainer.self) private var container
    @State private var isRefreshing = false

    var body: some View {
        if container.envManager.isCloudSessionLoggedIn {
            Section {
                if let snapshot = container.envManager.preferences.cloudQuotaSnapshot {
                    CloudAIQuotaView(snapshot: snapshot)
                } else {
                    HStack(spacing: 8) {
                        if isRefreshing { ProgressView().controlSize(.small) }
                        Text("Loading remaining quota…".localized())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task { await refresh() }
                } label: {
                    HStack {
                        Label("Refresh quota".localized(), systemImage: "arrow.clockwise")
                        Spacer()
                        if isRefreshing { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isRefreshing)
            } header: {
                Text("Remaining quota".localized())
            } footer: {
                Text("Daily request quota resets at 00:00 (Asia/Shanghai). Monthly AI Points reset on the 1st.".localized())
            }
        }
    }

    @MainActor
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await container.envManager.refreshCloudQuota()
    }
}

#Preview {
    List {
        Section("Remaining quota".localized()) {
            CloudAIQuotaView(
                snapshot: CloudAIQuotaSnapshot(
                    planName: "FREE",
                    membershipType: "free",
                    membershipStatus: "active",
                    dailyRequestLimit: 5,
                    monthlyPointLimit: 10_000,
                    usedDayRequests: 2,
                    usedMonthPoints: 6_200,
                    fetchedAt: .now
                )
            )
            Button {
            } label: {
                Label("Refresh quota".localized(), systemImage: "arrow.clockwise")
            }
        }
    }
}
