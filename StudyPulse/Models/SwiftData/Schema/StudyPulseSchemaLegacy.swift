//
//  StudyPulseSchemaLegacy.swift
//  StudyPulse
//
//  Frozen pre-V5 replicas of the payload-backed history records.
//

import Foundation
import SwiftData

/// Entity shapes exactly as they existed from schema V1 through V4.
///
/// Each `VersionedSchema` must reflect the store that those versions actually
/// created on disk, so the classes referenced by `StudyPulseSchemaV1`...`V4`
/// cannot gain persisted properties in place. SwiftData derives entity names
/// from the bare class name, so these nested replicas map to the same
/// underlying entities as the current top-level records; the V4→V5 lightweight
/// migration therefore resolves to `ALTER TABLE ADD COLUMN` for the new
/// optional columns instead of a destructive entity swap.
///
/// Do not modify these classes. Changed entities must be introduced as new
/// classes referenced by a new `VersionedSchema` (see `StudyPulseSchemaV5`).
enum StudyPulseSchemaLegacy {
    @Model
    final class StudySessionRecord {
        #Index<StudySessionRecord>([\.startDate])
        @Attribute(.unique) var id: UUID
        var startDate: Date
        var payload: Data

        init(from session: StudySession) {
            id = session.id; startDate = session.startDate
            payload = (try? JSONEncoder().encode(session)) ?? Data()
        }

        func toSnapshot() -> StudySession? {
            try? JSONDecoder().decode(StudySession.self, from: payload)
        }
    }

    @Model
    final class CoachChatRecord {
        #Index<CoachChatRecord>([\.goalID], [\.updatedAt])
        @Attribute(.unique) var id: UUID
        var goalID: UUID?
        var payload: Data
        var updatedAt: Date

        init(from chat: CoachChat) {
            id = chat.id; goalID = chat.goalID
            payload = (try? JSONEncoder().encode(chat)) ?? Data(); updatedAt = chat.updatedAt
        }

        func toSnapshot() -> CoachChat? {
            try? JSONDecoder().decode(CoachChat.self, from: payload)
        }
    }

    @Model
    final class CoachConversationMessageRecord {
        #Index<CoachConversationMessageRecord>([\.goalID], [\.createdAt])
        @Attribute(.unique) var id: UUID
        var goalID: UUID?
        var roleRaw: String
        var payload: Data
        var createdAt: Date

        init(from message: CoachConversationMessage) {
            id = message.id; goalID = message.goalID; roleRaw = message.role.rawValue
            payload = (try? JSONEncoder().encode(message)) ?? Data(); createdAt = message.createdAt
        }

        func toSnapshot() -> CoachConversationMessage? {
            try? JSONDecoder().decode(CoachConversationMessage.self, from: payload)
        }
    }

    @Model
    final class ExamSimulationRecord {
        #Index<ExamSimulationRecord>([\.createdAt])
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var payload: Data

        init(from simulation: ExamSimulation) {
            id = simulation.id
            createdAt = simulation.createdAt
            payload = (try? JSONEncoder().encode(simulation)) ?? Data()
        }

        func toSnapshot() -> ExamSimulation? {
            try? JSONDecoder().decode(ExamSimulation.self, from: payload)
        }
    }

    @Model
    final class ExamGoalRecord {
        #Index<ExamGoalRecord>([\.createdAt])
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var payload: Data

        init(from goal: ExamGoal) {
            id = goal.id
            createdAt = goal.createdAt
            payload = (try? JSONEncoder().encode(goal)) ?? Data()
        }

        func toSnapshot() -> ExamGoal? {
            try? JSONDecoder().decode(ExamGoal.self, from: payload)
        }
    }

    @Model
    final class ExamPlanRecord {
        #Index<ExamPlanRecord>([\.examGoalID], [\.createdAt])
        @Attribute(.unique) var id: UUID
        var examGoalID: UUID
        var createdAt: Date
        var payload: Data

        init(from plan: ExamPlan) {
            id = plan.id
            examGoalID = plan.examGoalID
            createdAt = plan.createdAt
            payload = (try? JSONEncoder().encode(plan)) ?? Data()
        }

        func toSnapshot() -> ExamPlan? {
            try? JSONDecoder().decode(ExamPlan.self, from: payload)
        }
    }
}
