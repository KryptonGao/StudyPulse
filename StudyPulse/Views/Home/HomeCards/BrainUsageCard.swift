import SwiftUI

struct BrainUsageCard: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(HealthKitManager.self) private var hrvManager: HealthKitManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var events: [BrainUsageEvent] = []
    @State private var now = Date()
    @State private var showSettings = false

    private var preferences: BrainUsagePreferences {
        BrainUsagePreferences(
            mode: container.envManager.preferences.brainUsageMode,
            manualQuota: BrainUsageQuota(fiveHour: container.envManager.preferences.brainUsageManualFiveHourQuota, sevenDay: container.envManager.preferences.brainUsageManualSevenDayQuota),
            notifyFiveHour: container.envManager.preferences.brainUsageNotifyFiveHour,
            notifySevenDay: container.envManager.preferences.brainUsageNotifySevenDay,
            dynamicQuota: dynamicQuota,
            dynamicQuotaGeneratedAt: container.envManager.preferences.brainUsageDynamicQuotaGeneratedAt
        )
    }

    private var dynamicQuota: BrainUsageQuota? {
        guard let five = container.envManager.preferences.brainUsageDynamicFiveHourQuota,
              let seven = container.envManager.preferences.brainUsageDynamicSevenDayQuota else { return nil }
        return BrainUsageQuota(fiveHour: five, sevenDay: seven)
    }

    private var quota: BrainUsageQuota {
        if preferences.mode == .dynamic, dynamicQuota == nil {
            let grades = container.gradeRepo.grades
            let rate = grades.isEmpty ? nil : grades.map { $0.scoreRate() }.reduce(0, +) / Double(grades.count)
            return BrainUsageEngine.localQuota(readiness: hrvManager.readiness, bodyStatus: hrvManager.bodyStatus, age: container.profileRepo.profile.age, averageScoreRate: rate)
        }
        return preferences.effectiveQuota
    }

    private var snapshot: BrainUsageSnapshot { BrainUsageEngine.snapshot(events: events, quota: quota, now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Brain Usage".localized(), systemImage: "brain.head.profile").font(.headline)
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Configure Brain Usage".localized())
            }
            usageWindow(title: "Last 5 Hours".localized(), window: snapshot.fiveHour)
            usageWindow(title: "Last 7 Days".localized(), window: snapshot.sevenDay)
            if snapshot.fiveHour.isComplete || snapshot.sevenDay.isComplete {
                Label("Goal reached — you can relax now.".localized(), systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.green)
            }
        }
        .padding(16)
        .glassCard(enabled: container.envManager.glassEffectEnabled, cornerRadius: 16)
        .task {
            reload()
            await BrainUsageQuotaLLM.refreshIfNeeded(container: container, hrvManager: hrvManager)
            reload()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .brainUsageDidChange) {
                guard !Task.isCancelled else { return }
                reload()
            }
        }
        .task {
            while !Task.isCancelled {
                // 仅在 App 活跃时更新时间与评估通知,后台/失焦不做任何主线程工作,避免空转(H-13)。
                if scenePhase == .active {
                    let value = Date()
                    now = value
                    BrainUsageNotifications.shared.evaluate(snapshot: snapshot, preferences: preferences, now: value)
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .sheet(isPresented: $showSettings) { BrainUsageSettingsView().environment(container).environment(hrvManager) }
    }

    private func usageWindow(title: String, window: BrainUsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title).font(.subheadline.weight(.semibold)); Spacer(); Text("\(window.points) / \(window.quota) pts").font(.caption).foregroundStyle(.secondary) }
            if let nextRefreshDate = window.nextRefreshDate {
                Label(refreshText(for: nextRefreshDate), systemImage: "arrow.clockwise")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Label("No pending refresh".localized(), systemImage: "arrow.clockwise")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                let width = max(0, proxy.size.width)
                HStack(spacing: 0) {
                    ForEach(BrainUsageEvent.Kind.allCases, id: \.self) { kind in
                        let value = Double(window.byKind[kind] ?? 0) / Double(max(1, window.quota))
                        Rectangle().fill(color(for: kind)).frame(width: min(width * value, width))
                    }
                }
                .frame(width: width, height: 12, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .clipShape(Capsule())
            }.frame(height: 12)
            HStack(spacing: 10) {
                ForEach(BrainUsageEvent.Kind.allCases, id: \.self) { kind in
                    Label("\(window.byKind[kind] ?? 0)", systemImage: "circle.fill").font(.caption2).foregroundStyle(color(for: kind))
                }
            }
        }
    }

    private func color(for kind: BrainUsageEvent.Kind) -> Color {
        switch kind { case .mistakeReview: return .orange; case .gradeRecorded: return .blue; case .focusMinutes: return .purple }
    }

    private func refreshText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return String(format: "Quota refreshes at %@".localized(), formatter.string(from: date))
    }

    private func reload() {
        BrainUsageStore.migrateLegacyIfNeeded()
        events = BrainUsageStore.load()
        now = Date()
        BrainUsageNotifications.shared.evaluate(snapshot: snapshot, preferences: preferences, now: now)
    }
}
