//
//  StudyPulseSchemaV3.swift
//  StudyPulse
//
//  Additive schema for Exam Reverse Planner payload records.
//

import SwiftData

/// Current schema. V1 and V2 remain frozen so existing on-device stores can
/// migrate through the same version history they were created with.
///
/// ExamGoalRecord / ExamPlanRecord reference their frozen pre-V5 shapes in
/// `StudyPulseSchemaLegacy`; V5 swaps in the current top-level records that
/// add denormalized list/filter columns.
enum StudyPulseSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        StudyPulseSchemaV2.models + [
            StudyPulseSchemaLegacy.ExamGoalRecord.self,
            StudyPulseSchemaLegacy.ExamPlanRecord.self,
        ]
    }
}
