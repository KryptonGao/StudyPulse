import Foundation
import os

@MainActor
final class CoachCoordinator {
    private let container: RepositoryContainer

    init(container: RepositoryContainer) { self.container = container }

    func snapshot(now: Date = Date()) -> CoachDataSnapshot {
        container.studySessionRepo.refreshFromLegacyJSON()
        let health = HealthKitManager.shared
        let recentMoodEntries = container.diaryRepo.entriesInRange(
            Calendar.current.date(byAdding: .day, value: -7, to: now) ?? .distantPast, now
        )
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        let recentSessions = container.studySessionRepo.sessions(from: cutoff, to: now)
        let recentAnnotations = snapshotAnnotations(from: recentSessions, now: now)
        let psychologicalStability = psychologicalStabilityScore(
            mistakes: container.mistakeRepo.filteredMistakeSets,
            annotations: recentAnnotations,
            moodEntries: recentMoodEntries
        )
        let moodScore = recentMoodEntries.isEmpty ? nil : recentMoodEntries.map { Double($0.moodScore) }.reduce(0, +) / Double(recentMoodEntries.count)
        let energyScore = recentMoodEntries.isEmpty ? nil : recentMoodEntries.map { Double($0.energyScore) }.reduce(0, +) / Double(recentMoodEntries.count)
        let signals = CoachHealthSignals(sleepHours: health.bodyStatus.lastNightSleepHours,
                                         restingHeartRate: health.bodyStatus.restingHeartRate,
                                         respiratoryRate: health.bodyStatus.respiratoryRate,
                                         exerciseMinutes: health.bodyStatus.exerciseMinutesToday,
                                         readinessCategory: health.readiness.category.rawValue,
                                         hrvZScore: health.readiness.zScore,
                                         todayHRV: health.readiness.todayHRV,
                                         latestHeartRate: health.bodyStatus.latestHeartRate,
                                         restorativeSleepHours: health.bodyStatus.restorativeSleepHours,
                                         psychologicalStability: psychologicalStability,
                                         moodScore: moodScore,
                                         energyScore: energyScore)
        return CoachDataSnapshot(
            grades: container.gradeRepo.filteredGrades,
            mistakes: container.mistakeRepo.filteredMistakeSets,
            tasks: container.taskRepo.filteredTaskItems,
            exams: container.examRepo.filteredExamSets,
            sessions: container.studySessionRepo.sessions,
            now: now,
            healthDataAvailable: health.bodyStatus.isUsable || health.readiness.todayHRV != nil,
            healthSignals: signals
        )
    }

    private func snapshotAnnotations(from sessions: [StudySession], now: Date) -> [DifficultyAnnotation] {
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        return sessions.filter { $0.startDate >= cutoff }.flatMap { $0.difficultyAnnotations ?? [] }
    }

    private func psychologicalStabilityScore(mistakes: [MistakeNote], annotations: [DifficultyAnnotation], moodEntries: [DiaryEntry]) -> Double {
        let psychTags: Set<String> = [
            "概念混淆", "计算粗心", "跳步", "审题不清", "思维定势", "逻辑不严密", "考试焦虑", "急躁粗心", "笔误", "遗漏条件",
            "concept confusion", "careless calculation", "skipping steps", "misreading", "fixed thinking", "loose logic", "exam anxiety", "impatience", "slip of pen", "missing condition"
        ]
        let impact = mistakes.reduce(0.0) { total, mistake in
            guard mistake.tags.contains(where: { psychTags.contains($0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) }) else { return total }
            return total + (1 - mistake.masteryScore)
        }
        let mistakeStability = mistakes.isEmpty ? 1 : max(0, min(1, 1 - impact / Double(mistakes.count)))
        let annotationStability = annotations.isEmpty ? 1 : max(0.2, 1 - Double(annotations.count) * 0.15)
        guard !moodEntries.isEmpty else { return mistakeStability * 0.65 + annotationStability * 0.35 }
        let moodStability = max(0, min(1, (moodEntries.map { Double($0.moodScore) }.reduce(0, +) / Double(moodEntries.count) - 1) / 4))
        return moodStability * 0.4 + mistakeStability * 0.4 + annotationStability * 0.2
    }

    @discardableResult
    func analyze(goal: CoachGoal, now: Date = Date()) -> CoachAnalysis {
        let result = CoachAnalysisEngine.analyze(goal: goal, snapshot: snapshot(now: now))
        container.coachRepo.saveAnalysis(result)
        CoachRefreshSignal.clear()
        return result
    }

    /// Creates a proposal only after the locally computed analysis exists and LLM is explicitly enabled.
    func generateProposal(goal: CoachGoal, analysis: CoachAnalysis) async throws -> CoachProposal {
        let prefs = container.envManager.preferences
        guard prefs.coachEnabled, prefs.llmEnabled else { throw LLMError.notConfigured }
        let proposal = try await CoachLLM.generate(goal: goal, analysis: analysis,
                                                   healthContext: currentHealthContext(),
                                                   config: LLMConfig.from(prefs),
                                                   languageCode: prefs.appLanguage)
        container.coachRepo.saveProposal(proposal)
        return proposal
    }

    /// Explicit user action from Settings. This bypasses health-change thresholds and
    /// cooldowns, but still leaves the generated plan pending for user approval.
    func forceRefreshProposal() async throws -> CoachProposal {
        let prefs = container.envManager.preferences
        guard prefs.coachEnabled, prefs.llmEnabled, LLMConfig.from(prefs).isConfigured else {
            throw LLMError.notConfigured
        }
        guard let goal = container.coachRepo.goals.first(where: { $0.status == .active }) else {
            throw CoachCoordinatorError.noActiveGoal
        }
        for proposal in container.coachRepo.proposals where proposal.goalID == goal.id && proposal.status == .pending {
            var superseded = proposal
            superseded.status = .superseded
            superseded.resolvedAt = Date()
            container.coachRepo.saveProposal(superseded)
        }
        let analysis = analyze(goal: goal)
        return try await generateProposal(goal: goal, analysis: analysis)
    }

    /// Keeps the sensitive change decision on device. Only after a material change is
    /// found do we send the normal, already-configured Coach prompt to the user's LLM.
    /// Generated proposals stay pending and never overwrite approved Todo items.
    func refreshPlanForSignificantHealthChange(now: Date = Date()) async {
        let signals = snapshot(now: now).healthSignals
        guard let reason = significantHealthChangeReason(for: signals) else {
            saveHealthBaseline(signals)
            return
        }
        saveHealthBaseline(signals)

        let prefs = container.envManager.preferences
        guard prefs.coachAdaptivePlanEnabled,
              prefs.coachEnabled,
              prefs.llmEnabled,
              LLMConfig.from(prefs).isConfigured,
              let goal = container.coachRepo.goals.first(where: { $0.status == .active }),
              !container.coachRepo.proposals.contains(where: { $0.goalID == goal.id && $0.status == .pending }) else {
            return
        }
        if let last = prefs.lastCoachAdaptivePlanRequestTime,
           now.timeIntervalSince(last) < 6 * 60 * 60 {
            Log.app.debug("Coach adaptive plan skipped by cooldown")
            return
        }

        // Record before awaiting the network so a foreground and background refresh cannot duplicate a request.
        container.envManager.preferences.lastCoachAdaptivePlanRequestTime = now
        let analysis = analyze(goal: goal, now: now)
        do {
            _ = try await generateAdaptiveProposal(goal: goal, analysis: analysis, healthChangeReason: reason)
            if container.envManager.preferences.coachNotificationEnabled {
                CoachNotifications.shared.notifyAdaptivePlanReady(goalID: goal.id)
            }
            Log.app.info("Coach adaptive proposal generated after local health change")
        } catch {
            Log.app.error("Coach adaptive proposal failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func generateAdaptiveProposal(goal: CoachGoal, analysis: CoachAnalysis,
                                          healthChangeReason: String) async throws -> CoachProposal {
        let prefs = container.envManager.preferences
        let proposal = try await CoachLLM.generate(
            goal: goal, analysis: analysis, healthContext: currentHealthContext(),
            healthChangeReason: healthChangeReason,
            config: LLMConfig.from(prefs), languageCode: prefs.appLanguage
        )
        container.coachRepo.saveProposal(proposal)
        return proposal
    }

    private func currentHealthContext() -> CoachLLMHealthContext {
        let data = snapshot()
        return CoachLLMHealthContext(signals: data.healthSignals, dataAvailable: data.healthDataAvailable)
    }

    /// A deliberately conservative, entirely local detector. It only reacts to a recovery
    /// category crossing, or a large HRV / sleep / resting-heart-rate movement.
    private func significantHealthChangeReason(for current: CoachHealthSignals) -> String? {
        let prefs = container.envManager.preferences
        let hasBaseline = prefs.coachHealthBaselineCategory != nil || prefs.coachHealthBaselineZScore != nil ||
            prefs.coachHealthBaselineSleepHours != nil || prefs.coachHealthBaselineRestingHeartRate != nil ||
            prefs.coachHealthBaselineRestorativeSleepHours != nil
        guard hasBaseline else { return nil }

        var changes: [String] = []
        if let previous = prefs.coachHealthBaselineCategory, let category = current.readinessCategory,
           previous != category,
           ["low", "excellent"].contains(previous) || ["low", "excellent"].contains(category) {
            changes.append("readiness changed from \(previous) to \(category)")
        }
        if let previous = prefs.coachHealthBaselineZScore, let value = current.hrvZScore,
           abs(value - previous) >= 1.0 {
            changes.append("HRV baseline deviation changed by \(String(format: "%.1f", abs(value - previous))) z")
        }
        if let previous = prefs.coachHealthBaselineSleepHours, let value = current.sleepHours,
           abs(value - previous) >= 2.0 {
            changes.append("sleep duration changed by \(String(format: "%.1f", abs(value - previous))) hours")
        }
        if let previous = prefs.coachHealthBaselineRestorativeSleepHours, let value = current.restorativeSleepHours,
           abs(value - previous) >= 1.5 {
            changes.append("restorative sleep changed by \(String(format: "%.1f", abs(value - previous))) hours")
        }
        if let previous = prefs.coachHealthBaselineRestingHeartRate, let value = current.restingHeartRate,
           abs(value - previous) >= 15 {
            changes.append("resting heart rate changed by \(Int(abs(value - previous))) bpm")
        }
        return changes.isEmpty ? nil : changes.joined(separator: "; ")
    }

    private func saveHealthBaseline(_ signals: CoachHealthSignals) {
        guard signals.readinessCategory != nil || signals.hrvZScore != nil || signals.sleepHours != nil ||
                signals.restingHeartRate != nil || signals.restorativeSleepHours != nil else { return }
        container.envManager.preferences.coachHealthBaselineCategory = signals.readinessCategory
        container.envManager.preferences.coachHealthBaselineZScore = signals.hrvZScore
        container.envManager.preferences.coachHealthBaselineSleepHours = signals.sleepHours
        container.envManager.preferences.coachHealthBaselineRestingHeartRate = signals.restingHeartRate
        container.envManager.preferences.coachHealthBaselineRestorativeSleepHours = signals.restorativeSleepHours
    }

    /// Approves exactly once. Existing Tasks are never modified.
    func approve(_ proposal: CoachProposal, selectedItemIDs: Set<UUID>? = nil) throws {
        guard let current = container.coachRepo.proposal(id: proposal.id), current.status == .pending else { return }
        guard let goal = container.coachRepo.goals.first(where: { $0.id == proposal.goalID }), goal.version == proposal.goalVersion else {
            throw CoachCoordinatorError.staleProposal
        }
        let selectedItems = proposal.items.filter { selectedItemIDs?.contains($0.id) ?? true }
        guard !selectedItems.isEmpty else { throw CoachCoordinatorError.noItemsSelected }
        let tasks = selectedItems.map { item -> TaskItem in
            let stopData = try? JSONEncoder().encode(CoachTaskSpec(
                startDate: item.startDate, subject: item.subject, objective: item.objective,
                stopCondition: item.stopCondition, goalID: proposal.goalID, proposalID: proposal.id,
                evaluation: CoachTaskEvaluation(status: .pending, progress: 0, evaluatedAt: Date(), detail: "Not evaluated yet.")
            ))
            let due = Calendar.current.date(byAdding: .hour, value: 2, to: item.startDate) ?? item.startDate
            return TaskItem(id: UUID(), title: item.title, type: .homework, dueDate: due,
                            reminderDate: item.startDate, subject: item.subject,
                            importance: item.importance, notes: item.objective,
                            coachExecutionData: stopData, coachGoalId: proposal.goalID,
                            coachProposalId: proposal.id)
        }
        container.addTasks(tasks)
        var resolved = current
        resolved.status = .approved
        resolved.resolvedAt = Date()
        container.coachRepo.saveProposal(resolved)
    }

    func regenerateProposal(for proposal: CoachProposal) async throws -> CoachProposal {
        guard let goal = container.coachRepo.goals.first(where: { $0.id == proposal.goalID }),
              let analysis = container.coachRepo.analyses.first(where: { $0.id == proposal.analysisID }) else {
            throw CoachCoordinatorError.staleProposal
        }
        var old = proposal
        old.status = .superseded; old.resolvedAt = Date()
        container.coachRepo.saveProposal(old)
        return try await generateProposal(goal: goal, analysis: analysis)
    }

    func evaluateCoachTasks(now: Date = Date()) {
        container.studySessionRepo.refreshFromLegacyJSON()
        let taskStart = container.taskRepo.taskItems
            .compactMap { $0.coachExecutionSpec?.startDate }
            .min() ?? now
        let detailedSessions = container.studySessionRepo.sessions(from: taskStart, to: now)
        let input = CoachTaskEvaluationInput(mistakes: container.mistakeRepo.mistakeSets,
                                             sessions: detailedSessions, now: now)
        for task in container.taskRepo.taskItems {
            guard var spec = task.coachExecutionSpec else { continue }
            let evaluation = CoachTaskEvaluator.evaluate(spec: spec, input: input)
            guard spec.evaluation != evaluation else { continue }
            spec.evaluation = evaluation
            var updated = task
            updated.coachExecutionData = try? JSONEncoder().encode(spec)
            if evaluation.status == .completed { updated.isCompleted = true }
            container.taskRepo.update(updated, reminderResult: nil)
        }
    }

    func expireStaleProposals(now: Date = Date()) {
        for proposal in container.coachRepo.proposals where proposal.status == .pending && proposal.expiresAt <= now {
            var expired = proposal
            expired.status = .expired
            expired.resolvedAt = now
            expired.failureReason = "This proposal expired because the learning data changed or it was not confirmed in time."
            container.coachRepo.saveProposal(expired)
        }
    }

    func reject(_ proposal: CoachProposal) {
        guard let current = container.coachRepo.proposal(id: proposal.id), current.status == .pending else { return }
        var resolved = current; resolved.status = .rejected; resolved.resolvedAt = Date()
        container.coachRepo.saveProposal(resolved)
    }
}

enum CoachCoordinatorError: Error, LocalizedError {
    case staleProposal
    case noItemsSelected
    case noActiveGoal
    var errorDescription: String? {
        switch self {
        case .staleProposal: return "This Coach proposal belongs to an older goal version."
        case .noItemsSelected: return "Select at least one plan item."
        case .noActiveGoal: return "Create and activate a Coach goal before refreshing its plan."
        }
    }
}
