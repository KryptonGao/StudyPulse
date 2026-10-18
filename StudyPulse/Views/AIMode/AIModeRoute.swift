//
//  AIModeRoute.swift
//  StudyPulse
//
//  Typed navigation destinations pushed from AI Mode data rows and source chips.
//

import Foundation

enum AIModeRoute: Hashable {
    case mistake(UUID)
    case exam(UUID)
    case comprehensiveExam(UUID)
    case diary
    case timeInvestment
    case subject(String)
    case aiSettings
    case healthSettings

    /// Maps a model-cited source to a push destination; `nil` means "switch to a data page".
    init?(source: AISourceLink) {
        switch source.kind {
        case .mistake:
            guard let id = source.targetID else { return nil }
            self = .mistake(id)
        case .exam:
            guard let id = source.targetID else { return nil }
            self = .exam(id)
        case .comprehensiveExam:
            guard let id = source.targetID else { return nil }
            self = .comprehensiveExam(id)
        case .diary: self = .diary
        case .timeProject: self = .timeInvestment
        case .subject:
            guard let name = source.subjectName, !name.isEmpty else { return nil }
            self = .subject(name)
        case .domainPage: return nil
        }
    }
}
