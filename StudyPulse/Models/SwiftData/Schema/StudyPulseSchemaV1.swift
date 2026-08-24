//
//  StudyPulseSchemaV1.swift
//  StudyPulse
//
//  The first frozen, explicitly versioned SwiftData schema.
//

import SwiftData

/// The schema shipped before explicit SwiftData migrations were introduced.
///
/// Do not add, remove, rename, or otherwise change a model in this list. A
/// persistent-model change must be introduced by a new `VersionedSchema`.
///
/// The payload-backed history records (coach chats / messages, study sessions,
/// exam simulations) reference their frozen pre-V5 shapes in
/// `StudyPulseSchemaLegacy`; V5 swaps in the current top-level records that
/// add denormalized list/filter columns.
enum StudyPulseSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SubjectRecord.self,
            GradeRecord.self,
            MistakeNoteRecord.self,
            ExamRecord.self,
            ComprehensiveExamRecord.self,
            TaskItemRecord.self,
            UserProfileRecord.self,
            StudyPhaseRecord.self,
            PlantStateRecord.self,
            RoutineRecord.self,
            RoutineInstanceRecord.self,
            DiaryEntryRecord.self,
            CoachGoalRecord.self,
            CoachAnalysisRecord.self,
            CoachProposalRecord.self,
            StudyPulseSchemaLegacy.CoachConversationMessageRecord.self,
            StudyPulseSchemaLegacy.CoachChatRecord.self,
            StudyPulseSchemaLegacy.StudySessionRecord.self,
            ExamAutopsyRecord.self,
            StudyPulseSchemaLegacy.ExamSimulationRecord.self,
        ]
    }
}
