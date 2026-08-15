//
//  StudyPulseMigrationPlan.swift
//  StudyPulse
//

import SwiftData

enum StudyPulseMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            StudyPulseSchemaV1.self,
            StudyPulseSchemaV2.self,
            StudyPulseSchemaV3.self,
            StudyPulseSchemaV4.self,
            StudyPulseSchemaV5.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: StudyPulseSchemaV1.self,
                toVersion: StudyPulseSchemaV2.self
            ),
            .lightweight(
                fromVersion: StudyPulseSchemaV2.self,
                toVersion: StudyPulseSchemaV3.self
            ),
            .lightweight(
                fromVersion: StudyPulseSchemaV3.self,
                toVersion: StudyPulseSchemaV4.self
            ),
            .lightweight(
                fromVersion: StudyPulseSchemaV4.self,
                toVersion: StudyPulseSchemaV5.self
            ),
        ]
    }
}
