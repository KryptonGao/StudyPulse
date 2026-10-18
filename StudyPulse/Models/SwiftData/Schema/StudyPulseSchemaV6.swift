//
//  StudyPulseSchemaV6.swift
//  StudyPulse
//
//  Adds the full-screen AI Mode conversation entities.
//

import SwiftData

/// V6 keeps every V5 entity unchanged and adds `AIConversationRecord` and
/// `AIChatMessageRecord`. New tables only, so the V5→V6 stage is lightweight.
enum StudyPulseSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        StudyPulseSchemaV5.models + [
            AIConversationRecord.self,
            AIChatMessageRecord.self,
        ]
    }
}
