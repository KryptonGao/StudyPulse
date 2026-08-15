//
//  StudyPulseSchemaV5.swift
//  StudyPulse
//
//  Denormalized list/filter columns for payload-backed history records.
//

import SwiftData

/// Adds list-facing metadata to payload-backed records. The payload columns
/// remain intact for backwards compatibility and detail-page hydration.
enum StudyPulseSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        StudyPulseSchemaV4.models
    }
}
