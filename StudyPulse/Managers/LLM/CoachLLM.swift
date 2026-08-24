import Foundation
import os

/// The explicit, structured recovery context included in every Coach planning request.
/// It is only sent after the user has enabled AI Coach and configured their BYOK LLM.
nonisolated struct CoachLLMHealthContext: Codable, Sendable, Equatable {
    let dataAvailable: Bool
    let readinessCategory: String?
    let hrvZScore: Double?
    let todayHRV: Double?
    let sleepHours: Double?
    let restorativeSleepHours: Double?
    let restingHeartRate: Double?
    let latestHeartRate: Double?
    let respiratoryRate: Double?
    let exerciseMinutes: Double?
    let psychologicalStability: Double?
    let moodScore: Double?
    let energyScore: Double?

    init(signals: CoachHealthSignals, dataAvailable: Bool) {
        self.dataAvailable = dataAvailable
        self.readinessCategory = signals.readinessCategory
        self.hrvZScore = signals.hrvZScore
        self.todayHRV = signals.todayHRV
        self.sleepHours = signals.sleepHours
        self.restorativeSleepHours = signals.restorativeSleepHours
        self.restingHeartRate = signals.restingHeartRate
        self.latestHeartRate = signals.latestHeartRate
        self.respiratoryRate = signals.respiratoryRate
        self.exerciseMinutes = signals.exerciseMinutes
        self.psychologicalStability = signals.psychologicalStability
        self.moodScore = signals.moodScore
        self.energyScore = signals.energyScore
    }
}

nonisolated struct CoachConversationLLMResponse: Codable, Sendable {
    let message: String
    let todoSuggestions: [CoachConversationTodoJSON]

    private enum CodingKeys: String, CodingKey { case message, todoSuggestions }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        todoSuggestions = try container.decodeIfPresent([CoachConversationTodoJSON].self, forKey: .todoSuggestions) ?? []
    }
}

nonisolated struct CoachConversationTodoJSON: Codable, Sendable {
    let title: String
    let subject: String
    let startDate: Date
    let dueDate: Date
    let importance: Int
    let notes: String
    let objective: String
    let stopCondition: CoachStopCondition
    let taskType: TaskType

    private enum CodingKeys: String, CodingKey { case title, subject, startDate, dueDate, importance, notes, objective, stopCondition, taskType, type }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTaskType = try container.decodeIfPresent(TaskType.self, forKey: .taskType)
        let legacyTaskType = try container.decodeIfPresent(TaskType.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        subject = try container.decodeIfPresent(String.self, forKey: .subject) ?? ""
        startDate = try Self.decodeDate(container.decodeIfPresent(String.self, forKey: .startDate))
        dueDate = try Self.decodeDate(container.decodeIfPresent(String.self, forKey: .dueDate), fallback: startDate)
        importance = try container.decodeIfPresent(Int.self, forKey: .importance) ?? 3
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        objective = try container.decodeIfPresent(String.self, forKey: .objective) ?? ""
        taskType = decodedTaskType ?? legacyTaskType ?? .homework
        stopCondition = try container.decode(CoachStopCondition.self, forKey: .stopCondition)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(subject, forKey: .subject)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(importance, forKey: .importance)
        try container.encode(notes, forKey: .notes)
        try container.encode(objective, forKey: .objective)
        try container.encode(stopCondition, forKey: .stopCondition)
        try container.encode(taskType, forKey: .taskType)
    }

    private static func decodeDate(_ value: String?, fallback: Date = Date()) throws -> Date {
        guard let value, !value.isEmpty else { return fallback }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = TimeZone.current
        dateOnly.dateFormat = "yyyy-MM-dd"
        if let date = dateOnly.date(from: value) { return date }
        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid Coach date: \(value)"))
    }
}

enum CoachLLM {
    static let caller = "AICoach"

    static func makePrompt(goal: CoachGoal, analysis: CoachAnalysis, healthContext: CoachLLMHealthContext? = nil,
                           healthChangeReason: String? = nil,
                           languageCode: String? = nil) -> LLMPrompt {
        struct Payload: Codable {
            let goal: CoachGoal?
            let analysis: CoachAnalysis?
            let healthContext: CoachLLMHealthContext?
            let healthChangeReason: String?
        }
        let payload = Payload(goal: goal, analysis: analysis, healthContext: healthContext,
                              healthChangeReason: healthChangeReason)
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return LLMPrompt(system: """
        You are a rigorous long-term study coach. The local app has already calculated every number.
        The payload's healthContext is the current HealthKit-derived recovery snapshot. Use it to adapt
        workload, session length, breaks, and recovery advice; do not invent unavailable health values.
        \(languageInstruction(for: languageCode))
        Never change scores, probabilities, dates, or targets. Return JSON only with keys:
        conclusion, rationale, shouldContinue, items, alternative.
        items contain title, subject, startDate as ISO-8601, objective, stopCondition, importance.
        Never create more work than the user's daily available time. If the target is not feasible,
        say so clearly and provide an alternative instead of pretending it is achievable.
        """, messages: [.user(json)], sensitivity: healthContext == nil ? .ordinary : .healthSensitive)
    }

    static func makeConversationPrompt(goal: CoachGoal?, analysis: CoachAnalysis?,
                                       history: [CoachConversationMessage], context: String,
                                       languageCode: String? = nil) -> LLMPrompt {
        struct Payload: Codable {
            let goal: CoachGoal?
            let analysis: CoachAnalysis?
            let context: String
            let history: [LLMMessage]
        }
        let payload = Payload(goal: goal, analysis: analysis, context: context,
                              history: history.map { LLMMessage(role: $0.role == .user ? .user : .assistant, content: $0.content) })
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return LLMPrompt(system: """
        You are the user's long-term AI Coach. Respond with JSON only using exactly these keys:
        message and todoSuggestions. message is a concise, warm, actionable response in the user's language.
        \(languageInstruction(for: languageCode))
        Always include todoSuggestions, using [] when there are no suggestions. Each suggestion must contain
        title, type (homework or reading), subject, startDate, dueDate as ISO-8601 strings, importance as an integer from 1 to 5,
        notes, objective, and stopCondition with kind, value, label, and targetIDs. Do not include an id field.
        Valid stopCondition.kind values are: mistakeReviewCount, masteryThreshold, questionCount,
        knowledgePoint, studySessionReflection. Example: {"message":"...","todoSuggestions":[]}
        Only suggest a Todo when it is useful. Never schedule before the current date/time, overlap an existing Todo,
        or duplicate an existing Todo. Use the supplied local Todo list as ground truth. Never exceed the goal's daily
        available minutes. Treat the supplied timestamp and recovery-radar health context as authoritative for this
        turn. Do not invent health values, scores, or alter local analysis; if a value is unavailable, say so.
        """, messages: [.user(json)], sensitivity: .healthSensitive)
    }

    private static func languageInstruction(for languageCode: String?) -> String {
        let language: String
        switch languageCode?.lowercased() {
        case "zh-hans", "zh-cn": language = "Simplified Chinese (简体中文)"
        case "zh-hant", "zh-tw", "zh-hk": language = "Traditional Chinese (繁體中文)"
        case "ja", "ja-jp": language = "Japanese (日本語)"
        case "ko", "ko-kr": language = "Korean (한국어)"
        default: language = "English"
        }
        return "Write all human-readable response fields (message, Todo titles, subjects, notes, objectives, and stopCondition labels) in \(language). Keep JSON keys, enum values, and ISO-8601 dates unchanged."
    }

    @MainActor
    static func generate(goal: CoachGoal, analysis: CoachAnalysis, healthContext: CoachLLMHealthContext? = nil,
                         healthChangeReason: String? = nil,
                         config: LLMConfig, languageCode: String? = nil) async throws -> CoachProposal {
        let output = try await LLMClient.shared.complete(prompt: makePrompt(goal: goal, analysis: analysis, healthContext: healthContext, healthChangeReason: healthChangeReason, languageCode: languageCode), config: config, caller: caller)
        return try parse(output: output, goal: goal, analysis: analysis)
    }

    nonisolated static func parseConversation(output: String) throws -> (String, [CoachTodoSuggestion]) {
        let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText = extractJSONObject(from: normalized) ?? normalized
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = (root["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            logConversationParseFailure(output: output, reason: "Missing top-level message")
            throw LLMError.malformedResponse
        }
        let suggestions = (root["todoSuggestions"] as? [[String: Any]] ?? []).compactMap {
            parseTodoSuggestion($0)
        }
        return (message, suggestions)
    }

    /// Backwards-compatible overload for callers that still pass the legacy goal ID.
    nonisolated static func parseConversation(output: String, goalID: UUID) throws -> (String, [CoachTodoSuggestion]) {
        try parseConversation(output: output)
    }

    private nonisolated static func parseTodoSuggestion(_ json: [String: Any]) -> CoachTodoSuggestion? {
        guard let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        let subject = json["subject"] as? String ?? ""
        let startDate = date(from: json["startDate"]) ?? Date()
        let dueDate = date(from: json["dueDate"]) ?? startDate
        let importance = (json["importance"] as? NSNumber)?.intValue ?? 3
        let notes = json["notes"] as? String ?? ""
        let objective = json["objective"] as? String ?? ""
        let taskType = TaskType(rawValue: (json["taskType"] as? String) ?? (json["type"] as? String) ?? "homework") ?? .homework
        let stop = json["stopCondition"] as? [String: Any]
        let kind = CoachStopConditionKind(rawValue: stop?["kind"] as? String ?? "") ?? .knowledgePoint
        let value = (stop?["value"] as? NSNumber)?.doubleValue ?? 1
        let label = stop?["label"] as? String ?? objective
        let targetIDs = (stop?["targetIDs"] as? [String])?.compactMap(UUID.init(uuidString:)) ?? []
        let condition = CoachStopCondition(kind: kind, value: value, label: label, targetIDs: targetIDs)
        return CoachTodoSuggestion(title: title, subject: subject, startDate: startDate, dueDate: dueDate,
                                   importance: importance, notes: notes, objective: objective, taskType: taskType,
                                   stopCondition: condition)
    }

    private nonisolated static func date(from value: Any?) -> Date? {
        if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue) }
        guard let string = value as? String else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    private nonisolated static func logConversationParseFailure(output: String, reason: String) {
        #if DEBUG
        let preview = String(output.prefix(4000))
        Log.llm.error("Coach response parse failed: \(reason, privacy: .public) raw=\(preview, privacy: .private(mask: .hash))")
        #endif
    }

    /// Extract the first balanced JSON object from raw model output. This handles
    /// DeepSeek reasoning blocks, Markdown fences, and a short preamble/postscript.
    private nonisolated static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for index in text.indices[start...] {
            let character = text[index]
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == "\"" { inString.toggle(); continue }
            guard !inString else { continue }
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...index]) }
            }
        }
        return nil
    }

    nonisolated static func parse(output: String, goal: CoachGoal, analysis: CoachAnalysis) throws -> CoachProposal {
        let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText = extractJSONObject(from: normalized) ?? normalized
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let conclusion = root["conclusion"] as? String else {
            #if DEBUG
            let preview = String(output.prefix(4000))
            Log.llm.error("Coach plan parse failed: missing conclusion. raw=\(preview, privacy: .private(mask: .hash))")
            #endif
            throw LLMError.malformedResponse
        }
        let rationale = root["rationale"] as? String ?? ""
        let alternative = root["alternative"] as? String
        let rawItems = root["items"] as? [[String: Any]] ?? []
        let items = rawItems.compactMap { parsePlanItem($0) }
        return CoachProposal(goalID: goal.id, goalVersion: goal.version, analysisID: analysis.id,
                             conclusion: conclusion, rationale: rationale, items: items,
                             alternative: alternative)
    }

    private nonisolated static func parsePlanItem(_ json: [String: Any]) -> CoachPlanItem? {
        guard let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        let subject = json["subject"] as? String ?? ""
        let startDate = date(from: json["startDate"]) ?? Date()
        let objective = json["objective"] as? String ?? ""
        let importance = (json["importance"] as? NSNumber)?.intValue ?? 3
        let stopJSON = json["stopCondition"] as? [String: Any]
        let stopKind = CoachStopConditionKind(rawValue: stopJSON?["kind"] as? String ?? "") ?? .knowledgePoint
        let stopValue = (stopJSON?["value"] as? NSNumber)?.doubleValue ?? 1
        let stopLabel = stopJSON?["label"] as? String ?? objective
        let stopTargetIDs = (stopJSON?["targetIDs"] as? [String])?.compactMap(UUID.init(uuidString:)) ?? []
        let stopCondition = CoachStopCondition(kind: stopKind, value: stopValue, label: stopLabel, targetIDs: stopTargetIDs)
        return CoachPlanItem(title: title, subject: subject, startDate: startDate,
                             objective: objective, stopCondition: stopCondition,
                             importance: min(5, max(1, importance)))
    }
}
