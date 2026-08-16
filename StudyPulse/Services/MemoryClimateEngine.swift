//
//  MemoryClimateEngine.swift
//  StudyPulse
//

import Foundation

/// Local-only, deterministic classification of memory state.
nonisolated enum MemoryClimateEngine {
    static let negativeWindowDays = 30
    static let humidWindowHours = 48
    static let frozenDays = 21
    static let overdueGraceDays = 7

    private struct ConceptPair: Hashable {
        let first: String
        let second: String

        init(_ lhs: String, _ rhs: String) {
            if lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending {
                first = lhs
                second = rhs
            } else {
                first = rhs
                second = lhs
            }
        }
    }

    static func generate(
        mistakes: [MistakeNote],
        phaseId: UUID?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MemoryClimateSnapshot {
        let day = calendar.startOfDay(for: now)
        let grouped = Dictionary(grouping: mistakes) {
            let clean = $0.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? "Uncategorized".localized() : clean
        }
        let subjects = grouped.compactMap { subject, notes in
            classify(subject: subject, mistakes: notes, now: now, calendar: calendar)
        }
        .sorted {
            if $0.weather.riskRank != $1.weather.riskRank {
                return $0.weather.riskRank > $1.weather.riskRank
            }
            return $0.subject.localizedCaseInsensitiveCompare($1.subject) == .orderedAscending
        }
        return MemoryClimateSnapshot(date: day, phaseId: phaseId, subjects: subjects)
    }

    static func concepts(for mistake: MistakeNote) -> [String] {
        let tags = unique(mistake.tags)
        if !tags.isEmpty { return tags }
        guard let node = KnowledgeFaultLineEngine.localNodes(for: [mistake]).first else {
            return [mistake.title].filter { !$0.isEmpty }
        }
        return unique([node.targetConcept])
    }

    private static func classify(
        subject: String,
        mistakes: [MistakeNote],
        now: Date,
        calendar: Calendar
    ) -> SubjectMemoryClimate? {
        guard !mistakes.isEmpty else { return nil }

        let allHistory = mistakes.flatMap(\.masteryHistory).sorted { $0.timestamp > $1.timestamp }
        let averageMastery = mistakes.map(\.masteryScore).reduce(0, +) / Double(mistakes.count)
        let enrolled = mistakes.filter { $0.reviewState != nil }
        let overdueCutoff = calendar.date(byAdding: .day, value: -overdueGraceDays, to: now) ?? now
        let overdueCount = enrolled.filter { ($0.reviewState?.nextReviewDate ?? .distantFuture) <= overdueCutoff }.count
        let overdueRatio = enrolled.isEmpty ? 0 : Double(overdueCount) / Double(enrolled.count)
        let daysSinceCalls = mistakes.map { note -> Double in
            let last = note.masteryHistory.max(by: { $0.timestamp < $1.timestamp })?.timestamp
                ?? note.reviewState?.lastReviewDate
                ?? note.date
            return max(0, now.timeIntervalSince(last) / 86_400)
        }.sorted()
        let medianDays = median(daysSinceCalls)
        let isFrozen = medianDays >= Double(frozenDays) || (!enrolled.isEmpty && overdueRatio >= 0.5)

        // Avoid pretending that a brand-new, unreviewed subject has a reliable climate.
        guard allHistory.count >= 2 || isFrozen else { return nil }

        let interferences = detectInterferences(in: mistakes, now: now, calendar: calendar)
        let primaryConcepts = rankedConcepts(in: mistakes)
        let medianRepetitions = median(enrolled.map { Double($0.reviewState?.repetitions ?? 0) }.sorted())
        let humidCutoff = now.addingTimeInterval(-Double(humidWindowHours) * 3_600)
        let latest = allHistory.first
        let recentlySucceeded = latest.map {
            $0.timestamp >= humidCutoff && ($0.quality == ReviewQuality.good.rawValue || $0.quality == ReviewQuality.easy.rawValue)
        } ?? false
        let recentLapseCutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let hadRecentLapse = allHistory.contains {
            $0.timestamp >= recentLapseCutoff && $0.quality == ReviewQuality.again.rawValue
        }

        let weather: MemoryWeather
        let confidence: Double
        if !interferences.isEmpty {
            weather = .thunderstorm
            confidence = interferences[0].confidence
        } else if isFrozen {
            // 冻结优先于湿热：按规格 4.1 的风险序，长期未调用/严重逾期
            // 比「近期答对但欠稳」风险更高，避免刚答对掩盖大面积冻结。
            weather = .frozen
            confidence = min(0.98, 0.65 + min(0.25, medianDays / 100) + overdueRatio * 0.15)
        } else if recentlySucceeded && (averageMastery < 0.7 || medianRepetitions < 2 || hadRecentLapse) {
            weather = .southHumid
            confidence = min(0.95, 0.62 + (0.7 - min(0.7, averageMastery)) * 0.4 + (hadRecentLapse ? 0.1 : 0))
        } else {
            let latestTwoStable = allHistory.prefix(2).count == 2 && allHistory.prefix(2).allSatisfy {
                $0.quality == ReviewQuality.good.rawValue || $0.quality == ReviewQuality.easy.rawValue
            }
            if averageMastery >= 0.7 && latestTwoStable && overdueRatio < 0.2 {
                weather = .clear
                confidence = min(0.98, 0.70 + (averageMastery - 0.7) * 0.6)
            } else {
                weather = .fog
                confidence = min(0.92, 0.58 + abs(0.7 - averageMastery) * 0.25)
            }
        }

        return SubjectMemoryClimate(
            subject: subject,
            weather: weather,
            confidence: confidence,
            averageMastery: averageMastery,
            overdueRatio: overdueRatio,
            primaryConcepts: Array(primaryConcepts.prefix(4)),
            interferences: interferences,
            evidenceMistakeIDs: mistakes.map(\.id)
        )
    }

    private static func detectInterferences(
        in mistakes: [MistakeNote],
        now: Date,
        calendar: Calendar
    ) -> [ConceptInterference] {
        let cutoff = calendar.date(byAdding: .day, value: -negativeWindowDays, to: now) ?? now
        let localNodes = KnowledgeFaultLineEngine.localNodes(for: mistakes)
        var relatedPairs = Set<ConceptPair>()
        var notesByPair: [ConceptPair: Set<UUID>] = [:]

        // Co-tags are direct evidence that two concepts meet in one mistake.
        for note in mistakes {
            let noteConcepts = concepts(for: note)
            for left in noteConcepts.indices {
                for right in noteConcepts.indices where right > left {
                    let pair = ConceptPair(noteConcepts[left], noteConcepts[right])
                    relatedPairs.insert(pair)
                    notesByPair[pair, default: []].insert(note.id)
                }
            }
        }

        // Concepts extracted under the same local foundation are also related.
        let byFoundation = Dictionary(grouping: localNodes) {
            $0.foundationConcept.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for nodes in byFoundation.values {
            // The generic `.other` fallback shares one placeholder foundation
            // across unrelated notes; it is not evidence of concept relation.
            let meaningfulNodes = nodes.filter { $0.category != .other }
            let targets = unique(meaningfulNodes.map(\.targetConcept))
            guard targets.count > 1 else { continue }
            for left in targets.indices {
                for right in targets.indices where right > left {
                    let pair = ConceptPair(targets[left], targets[right])
                    relatedPairs.insert(pair)
                    let ids = meaningfulNodes.filter {
                        $0.targetConcept.caseInsensitiveCompare(pair.first) == .orderedSame ||
                        $0.targetConcept.caseInsensitiveCompare(pair.second) == .orderedSame
                    }.map(\.mistakeID)
                    notesByPair[pair, default: []].formUnion(ids)
                }
            }
        }

        return relatedPairs.compactMap { pair -> ConceptInterference? in
            var firstNegative = 0
            var secondNegative = 0
            var evidence = notesByPair[pair] ?? []

            for note in mistakes {
                let noteConcepts = concepts(for: note)
                let negative = note.masteryHistory.filter {
                    $0.timestamp >= cutoff &&
                    ($0.quality == ReviewQuality.again.rawValue || $0.quality == ReviewQuality.hard.rawValue)
                }.count
                guard negative > 0 else { continue }
                if noteConcepts.contains(where: { $0.caseInsensitiveCompare(pair.first) == .orderedSame }) {
                    firstNegative += negative
                    evidence.insert(note.id)
                }
                if noteConcepts.contains(where: { $0.caseInsensitiveCompare(pair.second) == .orderedSame }) {
                    secondNegative += negative
                    evidence.insert(note.id)
                }
            }
            let total = firstNegative + secondNegative
            guard firstNegative > 0, secondNegative > 0, total >= 3 else { return nil }
            return ConceptInterference(
                firstConcept: pair.first,
                secondConcept: pair.second,
                negativeRetrievalCount: total,
                relatedMistakeIDs: evidence.sorted { $0.uuidString < $1.uuidString },
                confidence: min(0.98, 0.62 + Double(total - 3) * 0.07)
            )
        }
        .sorted {
            if $0.negativeRetrievalCount != $1.negativeRetrievalCount {
                return $0.negativeRetrievalCount > $1.negativeRetrievalCount
            }
            return $0.id < $1.id
        }
    }

    private static func rankedConcepts(in mistakes: [MistakeNote]) -> [String] {
        var counts: [String: (display: String, count: Int)] = [:]
        for note in mistakes {
            for concept in concepts(for: note) {
                let key = concept.lowercased()
                let current = counts[key] ?? (concept, 0)
                counts[key] = (current.display, current.count + 1)
            }
        }
        return counts.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending
        }.map(\.display)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap {
            let clean = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            let key = clean.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return clean
        }
    }
}
