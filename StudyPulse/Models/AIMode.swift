//
//  AIMode.swift
//  StudyPulse
//
//  Domain models for the full-screen "AI Mode" conversation space.
//  All types are nonisolated value types so they can cross actors and be
//  JSON-encoded into SwiftData payloads.
//

import Foundation

// MARK: - Preferences

nonisolated enum AIModeAppearance: String, Codable, CaseIterable, Sendable, Hashable {
    case pureBlue
    case warmSerif
}

nonisolated enum AIAnswerMode: String, Codable, CaseIterable, Sendable, Hashable {
    case deep
    case quick
}

// MARK: - Data domains

nonisolated enum AIDataDomain: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case grades, mistakes, exams, time, health, diary

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .grades: return "chart.line.uptrend.xyaxis"
        case .mistakes: return "book.closed"
        case .exams: return "calendar"
        case .time: return "clock"
        case .health: return "heart"
        case .diary: return "book"
        }
    }
}

nonisolated enum AIDateScopeKind: String, Codable, CaseIterable, Sendable, Hashable {
    case last7Days
    case last30Days
    case last90Days
    case phaseAll
    case custom
}

nonisolated struct AIDateScope: Codable, Hashable, Sendable {
    var kind: AIDateScopeKind
    var start: Date?
    var end: Date?

    init(kind: AIDateScopeKind, start: Date? = nil, end: Date? = nil) {
        self.kind = kind
        self.start = start
        self.end = end
    }

    static let last30Days = AIDateScope(kind: .last30Days)
    static let last90Days = AIDateScope(kind: .last90Days)
    static let phaseAll = AIDateScope(kind: .phaseAll)

    /// Resolves the scope to a concrete lower bound (nil = unbounded).
    func lowerBound(now: Date, calendar: Calendar = .current) -> Date? {
        switch kind {
        case .last7Days: return calendar.date(byAdding: .day, value: -7, to: now)
        case .last30Days: return calendar.date(byAdding: .day, value: -30, to: now)
        case .last90Days: return calendar.date(byAdding: .day, value: -90, to: now)
        case .phaseAll: return nil
        case .custom: return start
        }
    }
}

// MARK: - References & sources

nonisolated struct AIDataReference: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var domain: AIDataDomain
    /// Short user-visible label such as "成绩 · 近30天".
    var scopeLabel: String
    var subject: String?
    var scope: AIDateScope
    var recordIDs: [UUID]
    var phaseId: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        domain: AIDataDomain,
        scopeLabel: String,
        subject: String? = nil,
        scope: AIDateScope = .last30Days,
        recordIDs: [UUID] = [],
        phaseId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.domain = domain
        self.scopeLabel = scopeLabel
        self.subject = subject
        self.scope = scope
        self.recordIDs = recordIDs
        self.phaseId = phaseId
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, domain, scopeLabel, subject, scope, recordIDs, phaseId, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        domain = try c.decodeIfPresent(AIDataDomain.self, forKey: .domain) ?? .grades
        scopeLabel = try c.decodeIfPresent(String.self, forKey: .scopeLabel) ?? ""
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
        scope = try c.decodeIfPresent(AIDateScope.self, forKey: .scope) ?? .last30Days
        recordIDs = try c.decodeIfPresent([UUID].self, forKey: .recordIDs) ?? []
        phaseId = try c.decodeIfPresent(UUID.self, forKey: .phaseId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

nonisolated struct AISourceLink: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable, Hashable {
        case domainPage, mistake, exam, comprehensiveExam, diary, subject, timeProject
    }

    var id: UUID
    var kind: Kind
    var domain: AIDataDomain?
    var targetID: UUID?
    var subjectName: String?
    var label: String

    init(
        id: UUID = UUID(),
        kind: Kind,
        domain: AIDataDomain? = nil,
        targetID: UUID? = nil,
        subjectName: String? = nil,
        label: String
    ) {
        self.id = id
        self.kind = kind
        self.domain = domain
        self.targetID = targetID
        self.subjectName = subjectName
        self.label = label
    }

    static func page(_ domain: AIDataDomain, label: String) -> AISourceLink {
        AISourceLink(kind: .domainPage, domain: domain, label: label)
    }

    private enum CodingKeys: String, CodingKey { case id, kind, domain, targetID, subjectName, label }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .domainPage
        domain = try c.decodeIfPresent(AIDataDomain.self, forKey: .domain)
        targetID = try c.decodeIfPresent(UUID.self, forKey: .targetID)
        subjectName = try c.decodeIfPresent(String.self, forKey: .subjectName)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

// MARK: - Conversation & messages

nonisolated struct AIConversation: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var isTitleUserEdited: Bool
    var phaseId: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        isTitleUserEdited: Bool = false,
        phaseId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isTitleUserEdited = isTitleUserEdited
        self.phaseId = phaseId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, isTitleUserEdited, phaseId, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        isTitleUserEdited = try c.decodeIfPresent(Bool.self, forKey: .isTitleUserEdited) ?? false
        phaseId = try c.decodeIfPresent(UUID.self, forKey: .phaseId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

nonisolated enum AIChatRole: String, Codable, Sendable, Hashable {
    case user, assistant
}

nonisolated enum AIMessageStatus: String, Codable, Sendable, Hashable {
    case complete, streaming, stopped, interrupted, failed
}

nonisolated enum AIMessageOrigin: String, Codable, Sendable, Hashable {
    case model
    case localAnalysis
}

nonisolated struct AIChatMessage: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var conversationID: UUID
    var orderIndex: Int
    var role: AIChatRole
    var content: String
    var status: AIMessageStatus
    var origin: AIMessageOrigin
    var answerMode: AIAnswerMode
    /// Reasoning stop the reply was requested with; nil for messages from before per-model levels.
    var reasoningLevel: AIReasoningLevel?
    var references: [AIDataReference]
    var sources: [AISourceLink]
    var followUps: [String]
    /// Write proposals (add grade / add to-do) awaiting the user's confirmation.
    var actions: [AIProposedAction]
    /// nil = no feedback, true = marked helpful.
    var feedbackHelpful: Bool?
    var errorDescription: String?
    var modelName: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        orderIndex: Int,
        role: AIChatRole,
        content: String = "",
        status: AIMessageStatus = .complete,
        origin: AIMessageOrigin = .model,
        answerMode: AIAnswerMode = .deep,
        reasoningLevel: AIReasoningLevel? = nil,
        references: [AIDataReference] = [],
        sources: [AISourceLink] = [],
        followUps: [String] = [],
        actions: [AIProposedAction] = [],
        feedbackHelpful: Bool? = nil,
        errorDescription: String? = nil,
        modelName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.conversationID = conversationID
        self.orderIndex = orderIndex
        self.role = role
        self.content = content
        self.status = status
        self.origin = origin
        self.answerMode = answerMode
        self.reasoningLevel = reasoningLevel
        self.references = references
        self.sources = sources
        self.followUps = followUps
        self.actions = actions
        self.feedbackHelpful = feedbackHelpful
        self.errorDescription = errorDescription
        self.modelName = modelName
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, conversationID, orderIndex, role, content, status, origin, answerMode, reasoningLevel
        case references, sources, followUps, actions, feedbackHelpful, errorDescription, modelName, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        conversationID = try c.decode(UUID.self, forKey: .conversationID)
        orderIndex = try c.decodeIfPresent(Int.self, forKey: .orderIndex) ?? 0
        role = try c.decodeIfPresent(AIChatRole.self, forKey: .role) ?? .assistant
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        status = try c.decodeIfPresent(AIMessageStatus.self, forKey: .status) ?? .complete
        origin = try c.decodeIfPresent(AIMessageOrigin.self, forKey: .origin) ?? .model
        answerMode = try c.decodeIfPresent(AIAnswerMode.self, forKey: .answerMode) ?? .deep
        reasoningLevel = try? c.decodeIfPresent(AIReasoningLevel.self, forKey: .reasoningLevel)
        references = try c.decodeIfPresent([AIDataReference].self, forKey: .references) ?? []
        sources = try c.decodeIfPresent([AISourceLink].self, forKey: .sources) ?? []
        followUps = try c.decodeIfPresent([String].self, forKey: .followUps) ?? []
        actions = try c.decodeIfPresent([AIProposedAction].self, forKey: .actions) ?? []
        feedbackHelpful = try c.decodeIfPresent(Bool.self, forKey: .feedbackHelpful)
        errorDescription = try c.decodeIfPresent(String.self, forKey: .errorDescription)
        modelName = try c.decodeIfPresent(String.self, forKey: .modelName)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    /// Plain text used by the history search index.
    var searchableText: String {
        content.replacingOccurrences(of: "\n", with: " ")
    }
}
