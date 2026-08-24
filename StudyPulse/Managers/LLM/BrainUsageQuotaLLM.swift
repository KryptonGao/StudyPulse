import Foundation
import os

enum BrainUsageQuotaLLM {
    private struct Response: Decodable { let fiveHour: Int; let sevenDay: Int }

    @MainActor
    static func refreshIfNeeded(container: RepositoryContainer, hrvManager: HealthKitManager) async {
        let prefs = container.envManager.preferences
        guard prefs.brainUsageMode == .dynamic,
              container.envManager.llmConfig.isConfigured else { return }
        if let generated = prefs.brainUsageDynamicQuotaGeneratedAt,
           Date().timeIntervalSince(generated) < 6 * 60 * 60 { return }

        let grades = container.gradeRepo.grades
        let average = grades.isEmpty ? 0 : grades.map { $0.scoreRate() }.reduce(0, +) / Double(grades.count)
        let body = hrvManager.bodyStatus
        let readiness = hrvManager.readiness
        let prompt = LLMPrompt(
            system: "You are a safe study-load planner. Return JSON only with integer fields fiveHour and sevenDay. Values are brain-usage points, not minutes. Keep fiveHour between 20 and 600 and sevenDay between 100 and 3000. Reduce load for poor sleep or low HRV. Never include markdown.",
            messages: [.user("age=\(container.profileRepo.profile.age), averageScoreRate=\(average), readiness=\(readiness.category.rawValue), hrv=\(readiness.todayHRV ?? -1), sleep=\(body.lastNightSleepHours ?? -1), restingHeartRate=\(body.restingHeartRate ?? -1), respiratoryRate=\(body.respiratoryRate ?? -1), exerciseMinutes=\(body.exerciseMinutesToday ?? -1)")],
            sensitivity: .healthSensitive
        )
        do {
            let raw = try await LLMClient.shared.complete(prompt: prompt, config: container.envManager.llmConfig, caller: "BrainUsageQuota")
            guard let data = raw.data(using: .utf8), let response = try? JSONDecoder().decode(Response.self, from: data) else { return }
            let quota = BrainUsageQuota(fiveHour: response.fiveHour, sevenDay: response.sevenDay)
            container.envManager.preferences.brainUsageDynamicFiveHourQuota = quota.fiveHour
            container.envManager.preferences.brainUsageDynamicSevenDayQuota = quota.sevenDay
            container.envManager.preferences.brainUsageDynamicQuotaGeneratedAt = Date()
        } catch {
            Log.llm.error("BrainUsage quota planning fell back to local algorithm: \(error.localizedDescription, privacy: .public)")
        }
    }
}
