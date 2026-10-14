import SwiftUI
import os

struct HabitInsightCard: View {
    @Environment(RepositoryContainer.self) private var container
    @State private var localInsights: [HabitInsight] = []
    @State private var aiInsights: [HabitInsight]? = nil
    @State private var aiLoading = false
    @State private var aiErrorMessage: String?
    @State private var aiTask: Task<Void, Never>?
    @State private var todayBestSlot: HabitInsight?
    @State private var slotCells: [WeekdaySlotCell] = []

    private var displayedInsights: [HabitInsight] { aiInsights ?? localInsights }
    private var cooldownSeconds: TimeInterval { TimeInterval(container.envManager.preferences.habitInsightCooldownMinutes * 60) }
    private var cooldownRemaining: Int {
        guard let last = container.envManager.preferences.lastHabitInsightAIRequestTime else { return 0 }
        return max(0, Int((cooldownSeconds - Date().timeIntervalSince(last)).rounded()))
    }

    var body: some View {
        // 数据不足(< 3 次会话)时整卡隐藏,避免空占位 / Hidden entirely until there's enough data.
        Group {
            if !localInsights.isEmpty { cardBody }
        }
        .task { reload() }
        .onDisappear { aiTask?.cancel() }
    }

    private var cardBody: some View {
        HomeCardContainer {
            HomeCardHeader(icon: "waveform.path.ecg", title: "Habit Insight".localized(), tint: .teal) {
                HStack(spacing: 6) {
                    if aiLoading { ProgressView() }
                    if container.envManager.llmConfig.isConfigured {
                        Text("✨ AI").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            if let todayBestSlot { todayWindow(todayBestSlot) }
            if !slotCells.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("home.habit.heatmap".localized())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    WeekdaySlotHeatmap(cells: slotCells, tint: container.envManager.effectiveAccentColor)
                }
            }
            ForEach(displayedInsights) { insight in insightRow(insight) }
            if let aiErrorMessage, container.envManager.preferences.debugModeEnabled { Text(aiErrorMessage).font(.caption).foregroundStyle(.orange) }
            if container.envManager.llmConfig.isConfigured {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(alignment: .center, spacing: 12) {
                        if cooldownRemaining > 0 { Text(String(format: "Cooldown %@".localized(), formatCooldown(cooldownRemaining))).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Analyze Now".localized()) { requestAI(force: true) }
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .disabled(aiLoading || localInsights.isEmpty)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            #if DEBUG
            if container.envManager.preferences.debugModeEnabled { LLMCallIndicator(caller: "HabitInsight") }
            #endif
        }
    }

    private func todayWindow(_ insight: HabitInsight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Today's Best Study Window".localized(), systemImage: "sunrise.fill").font(.subheadline.weight(.semibold))
            Text(insight.title).font(.title3.weight(.bold))
            Text(HabitInsightEngine.notificationBody(for: insight)).font(.caption).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func insightRow(_ insight: HabitInsight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.icon).foregroundStyle(color(for: insight.color)).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title).font(.subheadline.weight(.semibold))
                Text(insight.description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @MainActor private func reload() {
        let sessions = container.studySessionRepo.sessions
        localInsights = HabitInsightEngine.computeInsights(sessions: sessions)
        todayBestSlot = HabitInsightEngine.bestSlotForToday(sessions: sessions)
        slotCells = HomeInsightsEngine.weekdaySlotCells(
            buckets: StudySessionStore.aggregateByWeekdayHourSlot(sessions: sessions)
        )
        guard container.envManager.llmConfig.isConfigured, container.envManager.preferences.habitInsightEnabled, !localInsights.isEmpty else { return }
        requestAI(force: false)
    }

    @MainActor private func requestAI(force: Bool) {
        guard !aiLoading, !localInsights.isEmpty else { return }
        if !force, cooldownRemaining > 0 { return }
        aiTask?.cancel(); aiLoading = true; aiErrorMessage = nil
        let sessions = container.studySessionRepo.sessions
        let fallback = localInsights[0]
        let context = HabitInsightContext(
            insights: localInsights,
            allBuckets: StudySessionStore.aggregateByWeekdayHourSlot(sessions: sessions),
            todayWeekday: Calendar.current.component(.weekday, from: Date()),
            todayBestSlot: todayBestSlot,
            sessionTotal: sessions.count,
            languageCode: container.envManager.preferences.appLanguage ?? "en"
        )
        aiTask = Task { @MainActor in
            var output = ""
            do {
                _ = try await LLMClient.shared.stream(prompt: HabitInsightLLM.makePrompt(context), config: container.envManager.llmConfig, caller: "HabitInsight") { output = $0 }
                if let parsed = HabitInsightLLM.parse(output, fallback: fallback) { aiInsights = [parsed] + localInsights.dropFirst() }
                else { aiErrorMessage = "AI 建议不可用,显示本地版本".localized() }
            } catch is CancellationError {
            } catch {
                aiErrorMessage = "AI 建议不可用,显示本地版本".localized()
                Log.llm.error("HabitInsightLLM stream failed: \(error.localizedDescription, privacy: .public)")
            }
            container.envManager.setLastHabitInsightAIRequestTime(Date())
            aiLoading = false
        }
    }

    private func color(for key: String) -> Color {
        switch key { case "green": return .green; case "orange": return .orange; case "red": return .red; default: return .blue }
    }
    private func formatCooldown(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}
