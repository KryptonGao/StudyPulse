//
//  MemoryClimate.swift
//  StudyPulse
//
//  Daily, deterministic memory-climate snapshots derived from mistake-review
//  history. These value types are persisted as versioned JSON.
//

import Foundation

nonisolated enum MemoryWeather: String, CaseIterable, Codable, Hashable, Sendable {
    case clear
    case fog
    case thunderstorm
    case frozen
    case southHumid

    var title: String {
        switch self {
        case .clear: return "memory.climate.weather.clear".localized()
        case .fog: return "memory.climate.weather.fog".localized()
        case .thunderstorm: return "memory.climate.weather.thunderstorm".localized()
        case .frozen: return "memory.climate.weather.frozen".localized()
        case .southHumid: return "memory.climate.weather.southHumid".localized()
        }
    }

    var symbolName: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .fog: return "cloud.fog.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .frozen: return "snowflake"
        case .southHumid: return "humidity.fill"
        }
    }

    /// Higher values are shown first on the home card.
    var riskRank: Int {
        switch self {
        case .thunderstorm: return 5
        case .frozen: return 4
        case .fog: return 3
        case .southHumid: return 2
        case .clear: return 1
        }
    }
}

nonisolated struct ConceptInterference: Identifiable, Codable, Hashable, Sendable {
    let firstConcept: String
    let secondConcept: String
    let negativeRetrievalCount: Int
    let relatedMistakeIDs: [UUID]
    let confidence: Double

    var id: String {
        [firstConcept, secondConcept]
            .map { $0.lowercased() }
            .sorted()
            .joined(separator: "|")
    }

    var displayName: String {
        "\(firstConcept) ↔ \(secondConcept)"
    }
}

nonisolated struct SubjectMemoryClimate: Identifiable, Codable, Hashable, Sendable {
    let subject: String
    let weather: MemoryWeather
    let confidence: Double
    let averageMastery: Double
    let overdueRatio: Double
    let primaryConcepts: [String]
    let interferences: [ConceptInterference]
    let evidenceMistakeIDs: [UUID]

    var id: String { subject }

    var summary: String {
        if weather == .thunderstorm, let pair = interferences.first {
            return String(
                format: "memory.climate.summary.thunderstorm".localized(),
                subject, pair.firstConcept, pair.secondConcept
            )
        }
        let key = "memory.climate.summary.\(weather.rawValue)"
        return String(format: key.localized(), subject)
    }
}

nonisolated struct MemoryClimateSnapshot: Identifiable, Codable, Hashable, Sendable {
    let date: Date
    let phaseId: UUID?
    let subjects: [SubjectMemoryClimate]

    var id: String {
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        return "\(day)|\(phaseId?.uuidString ?? "global")"
    }

    var dominantSubject: SubjectMemoryClimate? {
        subjects.sorted {
            if $0.weather.riskRank != $1.weather.riskRank {
                return $0.weather.riskRank > $1.weather.riskRank
            }
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            return $0.subject.localizedCaseInsensitiveCompare($1.subject) == .orderedAscending
        }.first
    }

    static func empty(date: Date = Date(), phaseId: UUID? = nil) -> MemoryClimateSnapshot {
        MemoryClimateSnapshot(
            date: Calendar.current.startOfDay(for: date),
            phaseId: phaseId,
            subjects: []
        )
    }
}

/// 15 分钟补救任务的策略类型。
/// Strategy behind a 15-minute remediation task.
nonisolated enum RemediationStrategy: String, Codable, Hashable, Sendable {
    /// 雷暴：优先覆盖相关概念对照。
    case interference
    /// 冻结：优先覆盖最早逾期或最长未调用内容。
    case overdue
    /// 雾：优先覆盖最近答错或掌握度最低内容。
    case weakSpot
}

/// 15 分钟最小补救任务。仅内存使用，不持久化。
/// A bounded 15-minute remediation task. In-memory only.
nonisolated struct RemediationTask: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let subject: String
    /// 触发任务的天气（仅 thunderstorm / frozen / fog）。
    let weather: MemoryWeather
    let strategy: RemediationStrategy
    /// 任务卡片，按确定顺序排列；复习时走正常 SRS 流程。
    let mistakes: [MistakeNote]
    /// 预计时长（分钟），不超过 RemediationTaskEngine.maxDurationMinutes。
    let estimatedMinutes: Int
}
