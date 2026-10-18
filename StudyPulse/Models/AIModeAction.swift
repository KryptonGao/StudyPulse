//
//  AIModeAction.swift
//  StudyPulse
//
//  Write proposals the model can attach to an AI Mode reply (add a grade / add a
//  to-do). They are only *proposals*: nothing is written until the user applies
//  the card under the message. All types are nonisolated value types and are
//  JSON-encoded inside `AIChatMessage` payloads (`decodeIfPresent` everywhere).
//

import Foundation

nonisolated enum AIActionKind: String, Codable, Sendable, Hashable {
    case addGrade = "add_grade"
    case addTask = "add_task"
}

nonisolated enum AIActionStatus: String, Codable, Sendable, Hashable {
    case pending, applied, dismissed, undone, failed
}

nonisolated struct AIGradeDraft: Codable, Hashable, Sendable {
    /// Internal subject name (`Subject.name`), already validated against the user's subjects.
    var subject: String
    var subjectDisplayName: String
    var score: Double
    var fullScore: Double
    var examName: String
    var date: Date
    var importance: Int
}

nonisolated struct AITaskDraft: Codable, Hashable, Sendable {
    var title: String
    var type: TaskType
    var dueDate: Date
    /// Internal subject name, or "" when none / unmatched.
    var subject: String
    var subjectDisplayName: String
    var notes: String
    var importance: Int
}

nonisolated struct AIProposedAction: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var kind: AIActionKind
    var status: AIActionStatus
    var grade: AIGradeDraft?
    var task: AITaskDraft?
    /// Id of the grade / task created when applied (used by undo).
    var recordID: UUID?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        kind: AIActionKind,
        status: AIActionStatus = .pending,
        grade: AIGradeDraft? = nil,
        task: AITaskDraft? = nil,
        recordID: UUID? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.grade = grade
        self.task = task
        self.recordID = recordID
        self.errorMessage = errorMessage
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, status, grade, task, recordID, errorMessage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(AIActionKind.self, forKey: .kind)
        status = try c.decodeIfPresent(AIActionStatus.self, forKey: .status) ?? .pending
        grade = try c.decodeIfPresent(AIGradeDraft.self, forKey: .grade)
        task = try c.decodeIfPresent(AITaskDraft.self, forKey: .task)
        recordID = try c.decodeIfPresent(UUID.self, forKey: .recordID)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

/// What the prompt builder and the action parser need to validate proposals.
nonisolated struct AIActionContext: Sendable, Equatable {
    var subjects: [Subject]
    var now: Date

    init(subjects: [Subject], now: Date = Date()) {
        // Same filter as the Add Grade screen: enabled, no "GROUP:" aggregate entries.
        self.subjects = subjects.filter { $0.enabled && !$0.name.hasPrefix("GROUP:") }
        self.now = now
    }

    func resolve(_ text: String) -> Subject? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return subjects.first { $0.name.caseInsensitiveCompare(key) == .orderedSame }
            ?? subjects.first { $0.displayName.caseInsensitiveCompare(key) == .orderedSame }
    }
}
