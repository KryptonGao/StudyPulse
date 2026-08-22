import Foundation

// MARK: - Goal Source

/// Where a focus session goal originates.
nonisolated enum StudySessionGoalSource: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case todo
    case knowledgePoint
    case mistakeCluster
    case custom
    case timeInvestment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .todo: return "Todo".localized()
        case .knowledgePoint: return "Knowledge Point".localized()
        case .mistakeCluster: return "Mistake Set".localized()
        case .custom: return "Custom".localized()
        case .timeInvestment: return "Project".localized()
        }
    }

    var icon: String {
        switch self {
        case .todo: return "checklist"
        case .knowledgePoint: return "lightbulb"
        case .mistakeCluster: return "exclamationmark.triangle"
        case .custom: return "pencil"
        case .timeInvestment: return "folder"
        }
    }
}

// MARK: - Goal Unit

nonisolated enum StudySessionGoalUnit: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case count
    case cards
    case chapter
    case minutes
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .count: return "items".localized()
        case .cards: return "cards".localized()
        case .chapter: return "chapters".localized()
        case .minutes: return "minutes".localized()
        case .custom: return "custom".localized()
        }
    }

    var shortLabel: String {
        switch self {
        case .count: return "count".localized()
        case .cards: return "cards".localized()
        case .chapter: return "chapter".localized()
        case .minutes: return "min".localized()
        case .custom: return "custom".localized()
        }
    }
}

// MARK: - Difficulty

nonisolated enum StudySessionDifficulty: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case easy
    case moderate
    case hard
    case veryHard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy: return "Easy".localized()
        case .moderate: return "Moderate".localized()
        case .hard: return "Hard".localized()
        case .veryHard: return "Very Hard".localized()
        }
    }

    var icon: String {
        switch self {
        case .easy: return "face.smiling"
        case .moderate: return "face.dashed"
        case .hard: return "flame"
        case .veryHard: return "exclamationmark.octagon"
        }
    }
}

// MARK: - Interruption Reason

nonisolated enum StudySessionInterruptionReason: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case none
    case notEnoughTime
    case harderThanExpected
    case interrupted
    case switchedTask
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None".localized()
        case .notEnoughTime: return "Not enough time".localized()
        case .harderThanExpected: return "Harder than expected".localized()
        case .interrupted: return "Interrupted".localized()
        case .switchedTask: return "Switched task".localized()
        case .other: return "Other".localized()
        }
    }

    var icon: String {
        switch self {
        case .none: return "checkmark.circle"
        case .notEnoughTime: return "clock.badge.exclamationmark"
        case .harderThanExpected: return "exclamationmark.triangle"
        case .interrupted: return "person.crop.circle.badge.xmark"
        case .switchedTask: return "arrow.triangle.swap"
        case .other: return "ellipsis.circle"
        }
    }
}

// MARK: - StudySessionGoal

/// Per-session learning goal: what to accomplish and how much was completed.
/// Persisted inside `StudySession.goal` (payload JSON), not as a separate SwiftData entity.
nonisolated struct StudySessionGoal: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var source: StudySessionGoalSource
    /// Stable identifier of the linked entity (TodoEntry.id / Mistake tag / InvestmentTarget rawID).
    var sourceID: String?
    /// Snapshot of the linked entity title at creation time.
    var sourceTitle: String?
    var unit: StudySessionGoalUnit
    var customUnitLabel: String?
    var targetValue: Double
    var completedValue: Double?
    var difficulty: StudySessionDifficulty?
    var interruptionReason: StudySessionInterruptionReason?
    var interruptionNote: String?

    // Legacy bridge: when goal originated from TimeInvestment, keep raw target for stats grouping.
    var linkedInvestmentTarget: InvestmentTarget? {
        guard source == .timeInvestment, let sourceID, let uuid = UUID(uuidString: sourceID) else { return nil }
        // Try subject first; consumer can search both tables. Default to subject.
        return InvestmentTarget(kindRawValue: "subject", id: uuid) ?? InvestmentTarget(kindRawValue: "subTask", id: uuid)
    }

    var completionRate: Double? {
        guard targetValue > 0, let completedValue else { return nil }
        return min(completedValue / targetValue, 1.0)
    }

    var isCompleted: Bool {
        guard let rate = completionRate else { return false }
        return rate >= 1.0 - 1e-9
    }

    var unitLabel: String {
        if unit == .custom, let customUnitLabel, !customUnitLabel.isEmpty {
            return customUnitLabel
        }
        return unit.shortLabel
    }

    var progressText: String {
        if let completedValue {
            let t = targetValue.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", targetValue) : String(format: "%.1f", targetValue)
            let c = completedValue.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", completedValue) : String(format: "%.1f", completedValue)
            return "\(c)/\(t) \(unitLabel)"
        } else {
            let t = targetValue.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", targetValue) : String(format: "%.1f", targetValue)
            return "\(t) \(unitLabel)"
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        source: StudySessionGoalSource,
        sourceID: String? = nil,
        sourceTitle: String? = nil,
        unit: StudySessionGoalUnit = .count,
        customUnitLabel: String? = nil,
        targetValue: Double,
        completedValue: Double? = nil,
        difficulty: StudySessionDifficulty? = nil,
        interruptionReason: StudySessionInterruptionReason? = nil,
        interruptionNote: String? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.sourceID = sourceID
        self.sourceTitle = sourceTitle
        self.unit = unit
        self.customUnitLabel = customUnitLabel
        self.targetValue = max(0, targetValue)
        self.completedValue = completedValue.map { max(0, $0) }
        self.difficulty = difficulty
        self.interruptionReason = interruptionReason
        self.interruptionNote = interruptionNote
    }

    // MARK: Codable backward compat

    private enum CodingKeys: String, CodingKey {
        case id, title, source, sourceID, sourceTitle, unit, customUnitLabel, targetValue, completedValue, difficulty, interruptionReason, interruptionNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        source = try c.decodeIfPresent(StudySessionGoalSource.self, forKey: .source) ?? .custom
        sourceID = try c.decodeIfPresent(String.self, forKey: .sourceID)
        sourceTitle = try c.decodeIfPresent(String.self, forKey: .sourceTitle)
        unit = try c.decodeIfPresent(StudySessionGoalUnit.self, forKey: .unit) ?? .count
        customUnitLabel = try c.decodeIfPresent(String.self, forKey: .customUnitLabel)
        targetValue = try c.decodeIfPresent(Double.self, forKey: .targetValue) ?? 0
        completedValue = try c.decodeIfPresent(Double.self, forKey: .completedValue)
        difficulty = try c.decodeIfPresent(StudySessionDifficulty.self, forKey: .difficulty)
        interruptionReason = try c.decodeIfPresent(StudySessionInterruptionReason.self, forKey: .interruptionReason)
        interruptionNote = try c.decodeIfPresent(String.self, forKey: .interruptionNote)
    }
}

extension StudySessionGoal {
    /// Convenience: build a goal from a legacy InvestmentTarget selection.
    nonisolated static func fromInvestmentTarget(_ target: InvestmentTarget, title: String, targetValue: Double = 1, unit: StudySessionGoalUnit = .count) -> StudySessionGoal {
        StudySessionGoal(
            title: title,
            source: .timeInvestment,
            sourceID: target.rawID.uuidString,
            sourceTitle: title,
            unit: unit,
            targetValue: targetValue
        )
    }
}
