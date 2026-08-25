import Foundation

@MainActor
@Observable
final class CoachConversationViewModel {
    private(set) var messages: [CoachConversationMessage] = []
    private(set) var isStreaming = false
    var errorMessage: String?

    let goal: CoachGoal?
    let chat: CoachChat
    let container: RepositoryContainer
    private var currentTask: Task<Void, Never>?
    @ObservationIgnored private lazy var coordinator = CoachCoordinator(container: container)

    init(goal: CoachGoal?, chat: CoachChat, container: RepositoryContainer) {
        self.goal = goal
        self.chat = chat
        self.container = container
        messages = container.coachRepo.messages(forChatID: chat.id).map { message in
            var restored = message
            if restored.isStreaming { restored.isStreaming = false }
            return restored
        }
    }

    func startIfNeeded() {
        // New conversations should wait for the user to decide what they want to ask.
    }

    func send(_ text: String, attachments: [LLMImageAttachment] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || !attachments.isEmpty), !isStreaming else { return }
        guard container.envManager.llmConfig.isConfigured else {
            errorMessage = LLMError.notConfigured.localizedDescription
            return
        }

        let user = CoachConversationMessage(goalID: goal?.id, chatID: chat.id, role: .user, content: trimmed, attachments: attachments)
        messages.append(user); container.coachRepo.addMessage(user)
        let assistant = CoachConversationMessage(goalID: goal?.id, chatID: chat.id, role: .assistant, isStreaming: true)
        messages.append(assistant); container.coachRepo.addMessage(assistant)
        isStreaming = true

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let analysis = goal.map { coordinator.analyze(goal: $0) }
                let basePrompt = CoachLLM.makeConversationPrompt(
                    goal: goal,
                    analysis: analysis,
                    history: Array(messages.dropLast()),
                    context: contextSummary(),
                    languageCode: container.envManager.preferences.appLanguage
                )
                let prompt = LLMPrompt(
                    system: basePrompt.system,
                    messages: basePrompt.messages.enumerated().map { index, message in
                        LLMMessage(
                            role: message.role,
                            content: message.content,
                            imageDataURLs: index == basePrompt.messages.index(before: basePrompt.messages.endIndex)
                                ? attachments.map(\.dataURL)
                                : message.imageDataURLs
                        )
                    },
                    sensitivity: .healthSensitive
                )
                let raw = try await LLMClient.shared.stream(
                    prompt: prompt,
                    config: container.envManager.llmConfig,
                    caller: CoachLLM.caller + "-Conversation"
                ) { [weak self] snapshot in
                    guard let self, let index = self.messages.lastIndex(where: { $0.id == assistant.id }) else { return }
                    self.messages[index].content = snapshot
                    self.container.coachRepo.updateMessage(self.messages[index])
                }

                let parsed = try CoachLLM.parseConversation(output: raw)
                guard let index = messages.firstIndex(where: { $0.id == assistant.id }) else { return }
                messages[index].content = parsed.0
                messages[index].todoSuggestions = parsed.1
                messages[index].isStreaming = false
                container.coachRepo.updateMessage(messages[index])
                touchChat(withTitle: messages.first(where: { $0.role == .user })?.content)
            } catch is CancellationError {
                finishAssistant(assistant.id, content: "[Cancelled]".localized())
            } catch {
                let description = (error as? LLMError)?.errorDescription ?? error.localizedDescription
                if let index = messages.firstIndex(where: { $0.id == assistant.id }) {
                    messages[index].isStreaming = false
                    messages[index].error = description
                    if messages[index].content.isEmpty { messages[index].content = "**Error**: \(description)" }
                    container.coachRepo.updateMessage(messages[index])
                }
            }
            isStreaming = false
            currentTask = nil
        }
    }

    func cancel() { currentTask?.cancel() }

    func clearConversation() {
        currentTask?.cancel(); currentTask = nil; messages.removeAll()
        container.coachRepo.deleteMessages(forChatID: chat.id)
    }

    private func touchChat(withTitle suggestedTitle: String?) {
        var updated = chat
        if chat.title == "New chat", let suggestedTitle, !suggestedTitle.isEmpty {
            updated.title = String(suggestedTitle.prefix(42))
        }
        updated.updatedAt = Date()
        container.coachRepo.updateChat(updated)
    }

    func addTodoSuggestion(messageID: UUID, suggestionID: UUID) {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }),
              let suggestionIndex = messages[messageIndex].todoSuggestions.firstIndex(where: { $0.id == suggestionID }),
              messages[messageIndex].todoSuggestions[suggestionIndex].status == .pending else { return }
        let suggestion = messages[messageIndex].todoSuggestions[suggestionIndex]
        let taskID = UUID()
        let execution = CoachTaskSpec(
            startDate: suggestion.startDate,
            subject: suggestion.subject,
            objective: suggestion.objective,
            stopCondition: suggestion.stopCondition,
            goalID: goal?.id ?? chat.id,
            evaluation: CoachTaskEvaluation(status: .pending, progress: 0, evaluatedAt: Date(), detail: "Not evaluated yet."))
        let data = try? JSONEncoder().encode(execution)
        let task = TaskItem(id: taskID, title: suggestion.title, type: suggestion.taskType,
                            dueDate: suggestion.dueDate, reminderDate: suggestion.startDate,
                            subject: suggestion.subject, importance: suggestion.importance,
                            notes: suggestion.notes, coachExecutionData: data, coachGoalId: goal?.id)
        container.addTask(task)
        messages[messageIndex].todoSuggestions[suggestionIndex].status = .added
        messages[messageIndex].todoSuggestions[suggestionIndex].taskID = taskID
        container.coachRepo.updateMessage(messages[messageIndex])
    }

    func dismissTodoSuggestion(messageID: UUID, suggestionID: UUID) {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }),
              let suggestionIndex = messages[messageIndex].todoSuggestions.firstIndex(where: { $0.id == suggestionID }) else { return }
        messages[messageIndex].todoSuggestions[suggestionIndex].status = .dismissed
        container.coachRepo.updateMessage(messages[messageIndex])
    }

    private func finishAssistant(_ id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content; messages[index].isStreaming = false
        container.coachRepo.updateMessage(messages[index])
    }

    private func contextSummary() -> String {
        let snapshot = coordinator.snapshot()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = snapshot.now
        let preciseTimestamp = String(format: "%.3f", now.timeIntervalSince1970)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.timeZone = .current
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short
        let todos = container.todoEntries(includeCompleted: false)
            .sorted { $0.date < $1.date }
            .prefix(40)
            .map { entry in
                let kind = entry.kind == .reading ? "reading" : entry.kind == .homework ? "homework" : entry.kind.rawValue
                return "- [\(kind)] \(entry.title) | subject=\(entry.subject) | date=\(iso.string(from: entry.date)) | completed=\(entry.isCompleted)"
            }
            .joined(separator: "\n")
        let health = snapshot.healthSignals
        func formatted(_ value: Double?, _ format: String, _ suffix: String = "") -> String {
            guard let value else { return "unavailable" }
            return String(format: format, value) + suffix
        }
        let healthSummary = [
            "HRV today: \(formatted(health.todayHRV, "%.1f", " ms"))",
            "HRV personal-baseline z-score: \(formatted(health.hrvZScore, "%.2f"))",
            "readiness: \(health.readinessCategory ?? "unavailable")",
            "resting heart rate: \(formatted(health.restingHeartRate, "%.1f", " bpm"))",
            "latest heart rate: \(formatted(health.latestHeartRate, "%.1f", " bpm"))",
            "respiratory rate: \(formatted(health.respiratoryRate, "%.1f", " breaths/min"))",
            "restorative sleep (deep + REM): \(formatted(health.restorativeSleepHours, "%.2f", " h"))",
            "total sleep: \(formatted(health.sleepHours, "%.2f", " h"))",
            "exercise today: \(formatted(health.exerciseMinutes, "%.1f", " min"))",
            "psychological stability radar score: \(health.psychologicalStability.map { String(format: "%.0f%%", $0 * 100) } ?? "unavailable" )",
            "recent diary mood average (1-5): \(formatted(health.moodScore, "%.2f"))",
            "recent diary energy average (1-5): \(formatted(health.energyScore, "%.2f"))"
        ].joined(separator: "; ")
        return "Current local date and time at prompt generation: \(dateFormatter.string(from: now)) (\(iso.string(from: now))); timezone=\(TimeZone.current.identifier); Unix timestamp=\(preciseTimestamp). Treat this as the exact current time and do not schedule anything in the past.\n"
            + (goal.map { "Goal target date: \(iso.string(from: $0.targetDate)).\n" } ?? "This is an independent Coach conversation with no linked goal.\n")
            + "Grades: \(snapshot.grades.count); mistakes: \(snapshot.mistakes.count); exams: \(snapshot.exams.count); "
            + "open tasks: \(snapshot.tasks.filter { !$0.isCompleted }.count); study sessions: \(snapshot.sessions.count); "
            + "health data available: \(snapshot.healthDataAvailable).\n"
            + "Recovery radar and health context (local HealthKit/diary data, may be unavailable if not authorized): \(healthSummary).\n"
            + "Known open Todos (do not duplicate or overlap these):\n\(todos.isEmpty ? "(none)" : todos)"
    }
}
