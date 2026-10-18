//
//  AIReasoning.swift
//  StudyPulse
//
//  Per-model reasoning intensity for AI Mode. Each model family exposes its
//  own levels (e.g. GPT-5 minimal…high, Cloud off / auto / on, MiniMax
//  off / adaptive); the selection is remembered per model.
//
//  Providers do not publish which efforts a model accepts (OpenAI-compatible
//  `/v1/models` only lists ids), so the levels are detected from the model
//  name. A BYOK provider can override them with its own set
//  (`LLMProvider.reasoningLevels`), chosen from `AIReasoningLevel.customizable`.
//

import Foundation

/// One reasoning stop. Which stops a model offers comes from `AIReasoningProfile`.
nonisolated enum AIReasoningLevel: String, Codable, CaseIterable, Sendable, Hashable {
    case off
    case minimal
    case low
    case auto
    case medium
    case high
    case xhigh
    case max

    /// Stops a user can enable for a provider by hand. `minimal` / `auto` only come from detected presets.
    static let customizable: [AIReasoningLevel] = [.off, .low, .medium, .high, .xhigh, .max]

    /// The lightest stops answer briefly; the rest use the full data budget and reasoning-first prompt.
    var answerMode: AIAnswerMode {
        switch self {
        case .off, .minimal: return .quick
        case .low, .auto, .medium, .high, .xhigh, .max: return .deep
        }
    }

    var titleKey: String { "aiMode.reasoning.level.\(rawValue)" }

    /// Needle position used when a model offers a single fixed stop, and for matching stops across models.
    var intrinsicIntensity: Double {
        switch self {
        case .off: return 0
        case .minimal: return 0.15
        case .low: return 0.3
        case .auto: return 0.45
        case .medium: return 0.55
        case .high: return 0.75
        case .xhigh: return 0.9
        case .max: return 1
        }
    }

    /// Canonical order, so a stored list always reads lightest → heaviest.
    static func ordered(_ levels: some Sequence<AIReasoningLevel>) -> [AIReasoningLevel] {
        let set = Set(levels)
        return allCases.filter(set.contains)
    }

    /// Parses stored raw values, dropping unknown ones.
    static func parse(_ raw: [String]?) -> [AIReasoningLevel]? {
        guard let raw else { return nil }
        let levels = ordered(raw.compactMap(AIReasoningLevel.init(rawValue:)))
        return levels.isEmpty ? nil : levels
    }
}

/// How a model family is told how hard to think.
nonisolated enum AIReasoningFamily: String, Codable, Sendable, Hashable {
    /// StudyPulse Cloud gateway: `studypulse.thinking` off / auto / on.
    case cloud
    /// OpenAI reasoning models and Gemini (OpenAI-compatible): `reasoning_effort`.
    case reasoningEffort
    /// Qwen3 / DashScope: `enable_thinking` + `thinking_budget`.
    case qwen
    /// MiniMax: `thinking.type` disabled / adaptive.
    case miniMax
    /// Models that always reason (DeepSeek Reasoner, R1, *-thinking): nothing to choose.
    case alwaysReasoning
    /// Any other OpenAI-compatible model: off answers briefly; high follows the provider's "Enable Thinking".
    case generic
}

nonisolated struct AIReasoningProfile: Sendable, Hashable {
    let family: AIReasoningFamily
    /// Ordered from lightest to heaviest; never empty.
    let levels: [AIReasoningLevel]
    let defaultLevel: AIReasoningLevel
    /// Key the selection is remembered under, so switching models keeps each model's own choice.
    let key: String
    /// The levels were chosen by the user for this provider rather than detected.
    var isCustom: Bool = false

    var isAdjustable: Bool { levels.count > 1 }

    /// 0…1 needle position of `level` within this model's range.
    func position(of level: AIReasoningLevel) -> Double {
        guard levels.count > 1, let index = levels.firstIndex(of: level) else {
            return level.intrinsicIntensity
        }
        return Double(index) / Double(levels.count - 1)
    }

    /// The stored choice when this model still offers it; otherwise the legacy answer mode
    /// (quick → lightest stop) or the model default.
    func resolve(stored: String?, legacy: AIAnswerMode?) -> AIReasoningLevel {
        if let stored, let level = AIReasoningLevel(rawValue: stored), levels.contains(level) {
            return level
        }
        if legacy == .quick, let lightest = levels.first { return lightest }
        return defaultLevel
    }

    /// Nearest stop this model offers, for a level chosen under another model.
    func clamp(_ level: AIReasoningLevel) -> AIReasoningLevel {
        Self.nearest(to: level, in: levels) ?? defaultLevel
    }

    static func nearest(to level: AIReasoningLevel, in levels: [AIReasoningLevel]) -> AIReasoningLevel? {
        if levels.contains(level) { return level }
        let target = level.intrinsicIntensity
        return levels.min { abs($0.intrinsicIntensity - target) < abs($1.intrinsicIntensity - target) }
    }

    // MARK: Detection

    static func resolve(config: LLMConfig) -> AIReasoningProfile {
        resolve(
            isCloud: config.isCloudProvider,
            providerName: config.providerName,
            baseURL: config.baseURL,
            model: config.model,
            customLevels: config.customReasoningLevels
        )
    }

    /// - Parameter customLevels: Levels the user enabled for the provider; ignored for Cloud, whose server decides.
    static func resolve(
        isCloud: Bool,
        providerName: String?,
        baseURL: String?,
        model: String?,
        customLevels: [AIReasoningLevel]? = nil
    ) -> AIReasoningProfile {
        let detected = detect(isCloud: isCloud, providerName: providerName, baseURL: baseURL, model: model)
        guard !isCloud, let customLevels, !customLevels.isEmpty else { return detected }
        let levels = AIReasoningLevel.ordered(customLevels)
        // Hand-picked levels are sent as `reasoning_effort` unless the family has its own parameter.
        let family: AIReasoningFamily
        switch detected.family {
        case .generic, .alwaysReasoning: family = .reasoningEffort
        case .cloud, .reasoningEffort, .qwen, .miniMax: family = detected.family
        }
        return AIReasoningProfile(
            family: family,
            levels: levels,
            defaultLevel: nearest(to: detected.defaultLevel, in: levels) ?? levels[levels.count - 1],
            key: detected.key,
            isCustom: true
        )
    }

    static func detect(isCloud: Bool, providerName: String?, baseURL: String?, model: String?) -> AIReasoningProfile {
        if isCloud {
            return AIReasoningProfile(family: .cloud, levels: [.off, .auto, .high], defaultLevel: .auto, key: "cloud")
        }
        let fullModel = (model ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let id = modelID(fullModel)
        let host = baseURL.flatMap { URL(string: $0.contains("://") ? $0 : "https://" + $0)?.host?.lowercased() } ?? ""

        func make(_ family: AIReasoningFamily, _ levels: [AIReasoningLevel], _ defaultLevel: AIReasoningLevel) -> AIReasoningProfile {
            AIReasoningProfile(family: family, levels: levels, defaultLevel: defaultLevel, key: "\(family.rawValue)|\(fullModel)")
        }

        let isMiniMax = providerName?.localizedCaseInsensitiveContains("minimax") == true
            || id.contains("minimax")
            || host.contains("minimaxi.com") || host.contains("minimax.io") || host.contains("minimax.chat")
        if isMiniMax { return make(.miniMax, [.off, .auto], .auto) }

        if id.contains("deepseek-reasoner") || id.contains("thinking") || id.hasPrefix("qwq")
            || id.hasSuffix("-r1") || id.contains("-r1-") || id == "r1"
            || id.hasPrefix("o1-mini") || id.hasPrefix("o1-preview") {
            return make(.alwaysReasoning, [.high], .high)
        }

        if id.hasPrefix("gpt-5") {
            if id.contains("chat") { return make(.generic, [.off, .high], .high) }
            // GPT-5.1 and later replace `minimal` with `none`; GPT-5.2 and codex-max add `xhigh`.
            if id.hasPrefix("gpt-5.") {
                let minor = Int(id.dropFirst("gpt-5.".count).prefix { $0.isNumber }) ?? 0
                let xhigh = minor >= 2 || id.contains("codex-max")
                return make(.reasoningEffort, [.off, .low, .medium, .high] + (xhigh ? [.xhigh] : []), .medium)
            }
            return make(.reasoningEffort, [.minimal, .low, .medium, .high], .medium)
        }
        if id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") || id.hasPrefix("gpt-oss") {
            return make(.reasoningEffort, [.low, .medium, .high], .medium)
        }
        if id.hasPrefix("gemini-2.5") || id.hasPrefix("gemini-3") {
            return make(.reasoningEffort, [.low, .medium, .high], .medium)
        }
        if id.hasPrefix("qwen3") || id.hasPrefix("qwen-plus") || id.hasPrefix("qwen-flash") || id.hasPrefix("qwen-turbo") {
            return make(.qwen, [.off, .low, .medium, .high], .medium)
        }
        return make(.generic, [.off, .high], .high)
    }

    /// OpenRouter-style ids ("openai/gpt-5") are matched on the part after the vendor.
    static func modelID(_ model: String) -> String {
        let lowered = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.split(separator: "/").last.map(String.init) ?? lowered
    }

    /// OpenAI reasoning models reject any `temperature` but the default.
    static func isOpenAIReasoningModel(_ model: String?) -> Bool {
        let id = modelID(model ?? "")
        if id.hasPrefix("gpt-5") { return !id.contains("chat") }
        return id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4")
    }
}

extension AIReasoningProfile {
    /// Value for OpenAI-style `reasoning_effort`.
    nonisolated static func reasoningEffort(for level: AIReasoningLevel) -> String {
        switch level {
        case .off: return "none"
        case .auto: return "medium"
        case .minimal, .low, .medium, .high, .xhigh, .max: return level.rawValue
        }
    }

    /// Qwen `thinking_budget` tokens; nil turns thinking off.
    nonisolated static func qwenThinkingBudget(for level: AIReasoningLevel) -> Int? {
        switch level {
        case .off: return nil
        case .minimal, .low: return 1024
        case .auto, .medium: return 4096
        case .high: return 16384
        case .xhigh: return 24576
        case .max: return 32768
        }
    }
}
