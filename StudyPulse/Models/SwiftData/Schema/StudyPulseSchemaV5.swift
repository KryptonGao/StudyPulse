//
//  StudyPulseSchemaV5.swift
//  StudyPulse
//
//  Denormalized list/filter columns for payload-backed history records.
//

import SwiftData

/// Adds list-facing metadata to payload-backed records. The payload columns
/// remain intact for backwards compatibility and detail-page hydration.
///
/// V5 keeps every V1–V4 entity unchanged except the six payload-backed history
/// records, which are swapped from their frozen `StudyPulseSchemaLegacy`
/// shapes to the current top-level records carrying optional denormalized
/// columns. SwiftData matches entities by bare class name, so the V4→V5
/// lightweight stage resolves to in-place `ALTER TABLE ADD COLUMN` and keeps
/// every existing row.
enum StudyPulseSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        StudyPulseSchemaV4.models.map { type in
            switch type {
            case is StudyPulseSchemaLegacy.StudySessionRecord.Type:
                return StudySessionRecord.self
            case is StudyPulseSchemaLegacy.CoachChatRecord.Type:
                return CoachChatRecord.self
            case is StudyPulseSchemaLegacy.CoachConversationMessageRecord.Type:
                return CoachConversationMessageRecord.self
            case is StudyPulseSchemaLegacy.ExamSimulationRecord.Type:
                return ExamSimulationRecord.self
            case is StudyPulseSchemaLegacy.ExamGoalRecord.Type:
                return ExamGoalRecord.self
            case is StudyPulseSchemaLegacy.ExamPlanRecord.Type:
                return ExamPlanRecord.self
            default:
                return type
            }
        }
    }
}
