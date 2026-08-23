//
//  KnowledgeFaultLineEngine.swift
//  StudyPulse
//

import Foundation

nonisolated enum KnowledgeFaultLineEngine {
    static let minimumOccurrences = 2
    static let recentWindowDays = 30

    private struct Rule {
        let category: KnowledgeFaultCategory
        let terms: [String]
        let prerequisite: String
        let foundation: String
    }

    private static let rules: [Rule] = [
        Rule(category: .proportionalReasoning, terms: ["比例", "正比", "反比", "比值", "倍数", "缩放", "proportion", "ratio", "scale"], prerequisite: "比例关系", foundation: "数的关系与比较"),
        Rule(category: .unitConversion, terms: ["单位", "换算", "量纲", "厘米", "米", "千克", "秒", "unit", "convert", "dimension"], prerequisite: "单位制与量纲", foundation: "数量与单位意识"),
        Rule(category: .equationModeling, terms: ["方程", "列式", "建模", "设x", "未知量", "关系式", "model", "equation", "variable"], prerequisite: "变量关系与方程", foundation: "把题意转成关系"),
        Rule(category: .foundationalMemory, terms: ["忘记", "记错", "背错", "记忆", "忘了", "forgot", "memory", "memor"], prerequisite: "定义与结论回忆", foundation: "基础事实记忆"),
        Rule(category: .conceptDefinition, terms: ["概念", "定义", "性质", "定理", "区别", "concept", "definition", "property", "theorem"], prerequisite: "定义与适用条件", foundation: "概念边界"),
        Rule(category: .conditionBoundary, terms: ["条件", "限制", "范围", "前提", "边界", "取值", "constraint", "condition", "boundary"], prerequisite: "条件识别与边界", foundation: "验证问题约束"),
        Rule(category: .methodSelection, terms: ["方法", "思路", "策略", "选错", "公式", "套用", "误用", "method", "approach", "formula"], prerequisite: "问题结构识别", foundation: "选择合适路径"),
        Rule(category: .symbolicCalculation, terms: ["计算", "符号", "移项", "展开", "化简", "运算", "calculation", "symbol", "arithmetic"], prerequisite: "代数运算与符号规则", foundation: "逐步验证中间量"),
        Rule(category: .readingTranslation, terms: ["审题", "读题", "题意", "看漏", "漏读", "信息", "reading", "misread"], prerequisite: "题意拆解", foundation: "从文字提取信息"),
        Rule(category: .other, terms: [], prerequisite: "题目基础概念", foundation: "基础知识连接")
    ]

    static func localNodes(for mistakes: [MistakeNote]) -> [MistakeKnowledgeNode] {
        mistakes.map { makeNode(for: $0, extraction: nil) }
    }

    static func scan(
        mistakes: [MistakeNote],
        extractions: [KnowledgeFaultAIExtraction] = [],
        now: Date = Date()
    ) -> KnowledgeFaultScan {
        let mistakeIDs = Set(mistakes.map(\.id))
        let validExtractions = extractions.filter { mistakeIDs.contains($0.mistakeID) }
        let extractionMap = Dictionary(validExtractions.map { ($0.mistakeID, $0) }, uniquingKeysWith: { first, _ in first })
        let nodes = mistakes.map { makeNode(for: $0, extraction: extractionMap[$0.id]) }
        let lines = aggregate(nodes: nodes, mistakes: mistakes, now: now)
        let aiIDs = Set(validExtractions.map(\.mistakeID))
        return KnowledgeFaultScan(
            nodes: nodes,
            faultLines: lines,
            usedFallback: mistakes.isEmpty || aiIDs.count < mistakes.count,
            aiAppliedCount: aiIDs.count
        )
    }

    static func provisionalLine(
        for node: MistakeKnowledgeNode,
        mistakes: [MistakeNote],
        now: Date = Date()
    ) -> KnowledgeFaultLine? {
        let lines = aggregate(nodes: [node], mistakes: mistakes, now: now)
        return lines.first
    }

    private static func makeNode(
        for mistake: MistakeNote,
        extraction: KnowledgeFaultAIExtraction?
    ) -> MistakeKnowledgeNode {
        if let extraction,
           !extraction.targetConcept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !extraction.foundationConcept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let prerequisites = uniqueNonEmpty(extraction.prerequisiteConcepts).prefix(3).map { $0 }
            return MistakeKnowledgeNode(
                mistakeID: mistake.id,
                subject: displaySubject(mistake.subject),
                targetConcept: trimmed(extraction.targetConcept),
                prerequisiteConcepts: prerequisites.isEmpty ? [fallbackRule(for: mistake).prerequisite] : prerequisites,
                foundationConcept: trimmed(extraction.foundationConcept),
                category: extraction.category,
                evidence: [trimmed(extraction.evidence)].filter { !$0.isEmpty },
                confidence: extraction.confidence,
                source: .ai
            )
        }

        let rule = fallbackRule(for: mistake)
        let target: String
        if let tagged = firstConcept(from: mistake.tags) {
            target = tagged
        } else if !trimmed(mistake.title).isEmpty {
            target = trimmed(mistake.title)
        } else {
            target = displaySubject(mistake.subject) + "知识点"
        }
        let evidence = [mistake.errorReason, mistake.wrongSolution, mistake.correctSolution]
            .map(trimmed)
            .filter { !$0.isEmpty }
            .prefix(2)
        return MistakeKnowledgeNode(
            mistakeID: mistake.id,
            subject: displaySubject(mistake.subject),
            targetConcept: target,
            prerequisiteConcepts: [rule.prerequisite],
            foundationConcept: rule.foundation,
            category: rule.category,
            evidence: Array(evidence),
            confidence: rule.category == .other ? 0.25 : 0.62,
            source: .rules
        )
    }

    private static func aggregate(
        nodes: [MistakeKnowledgeNode],
        mistakes: [MistakeNote],
        now: Date
    ) -> [KnowledgeFaultLine] {
        let notesByID = Dictionary(mistakes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var buckets: [String: (category: KnowledgeFaultCategory, prerequisite: String, foundation: String, ids: Set<UUID>)] = [:]

        for node in nodes {
            let prerequisites = node.prerequisiteConcepts.isEmpty ? [node.foundationConcept] : node.prerequisiteConcepts
            for prerequisite in prerequisites {
                let key = "\(node.category.rawValue)|\(normalize(prerequisite))|\(normalize(node.foundationConcept))"
                var bucket = buckets[key] ?? (node.category, prerequisite, node.foundationConcept, [])
                bucket.ids.insert(node.mistakeID)
                buckets[key] = bucket
            }
        }

        return buckets.compactMap { key, bucket in
            let related = bucket.ids.compactMap { notesByID[$0] }
            guard !related.isEmpty else { return nil }
            let sortedRelated = related.sorted { lhs, rhs in
                let leftScore = notePriority(lhs, now: now)
                let rightScore = notePriority(rhs, now: now)
                if leftScore != rightScore { return leftScore > rightScore }
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            let subjects = Array(Set(related.map { displaySubject($0.subject) })).sorted()
            let recentCutoff = Calendar.current.date(byAdding: .day, value: -recentWindowDays, to: now) ?? now
            let recentRecurrenceCount = related.reduce(0) { partial, note in
                let recentMistake = note.date >= recentCutoff ? 1 : 0
                let recentAgain = note.masteryHistory.filter { $0.timestamp >= recentCutoff && $0.quality == 1 }.count
                return partial + recentMistake + recentAgain
            }
            let averageMastery = related.map(\.masteryScore).reduce(0, +) / Double(related.count)
            let againCount = related.reduce(0) { total, note in
                total + (note.reviewState?.lapses ?? 0) + note.masteryHistory.filter { $0.quality == 1 }.count
            }
            let impact = min(1, Double(related.count) / 6.0)
            let recurrence = min(1, Double(recentRecurrenceCount) / 4.0)
            let mastery = 1 - min(1, max(0, averageMastery))
            let failure = min(1, Double(againCount) / 6.0)
            let breadth = min(1, Double(max(0, subjects.count - 1)) / 3.0)
            let risk = min(1, max(0,
                impact * 0.35 + recurrence * 0.25 + mastery * 0.20 + failure * 0.15 + breadth * 0.05
            ))
            return KnowledgeFaultLine(
                id: key,
                category: bucket.category,
                prerequisiteConcept: trimmed(bucket.prerequisite),
                foundationConcept: trimmed(bucket.foundation),
                impactMistakeCount: related.count,
                subjects: subjects,
                recentRecurrenceCount: recentRecurrenceCount,
                riskScore: risk,
                relatedMistakeIDs: sortedRelated.map(\.id),
                relatedMistakes: sortedRelated
            )
        }
        .sorted {
            if $0.riskScore != $1.riskScore { return $0.riskScore > $1.riskScore }
            if $0.recentRecurrenceCount != $1.recentRecurrenceCount { return $0.recentRecurrenceCount > $1.recentRecurrenceCount }
            if $0.impactMistakeCount != $1.impactMistakeCount { return $0.impactMistakeCount > $1.impactMistakeCount }
            return $0.id < $1.id
        }
    }

    private static func fallbackRule(for mistake: MistakeNote) -> Rule {
        let fields = [mistake.errorReason, mistake.wrongSolution, mistake.correctSolution] + mistake.tags
        let searchable = fields.map(normalize).joined(separator: " ")
        for rule in rules where rule.terms.contains(where: { searchable.contains(normalize($0)) }) {
            return rule
        }
        return Rule(category: .other, terms: [], prerequisite: "题目基础概念", foundation: "基础知识连接")
    }

    private static func firstConcept(from tags: [String]) -> String? {
        tags.map(trimmed).first { !$0.isEmpty }
    }

    private static func notePriority(_ note: MistakeNote, now: Date) -> Double {
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -recentWindowDays, to: now) ?? now
        let recentAgain = note.masteryHistory.filter { $0.timestamp >= recentCutoff && $0.quality == 1 }.count
        return (1 - min(1, max(0, note.masteryScore))) + Double(note.reviewState?.lapses ?? 0) * 0.2 + Double(recentAgain) * 0.1
    }

    private static func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let clean = trimmed(value)
            let key = normalize(clean)
            guard !clean.isEmpty, seen.insert(key).inserted else { return nil }
            return clean
        }
    }

    private static func displaySubject(_ subject: String) -> String {
        let clean = trimmed(subject)
        return clean.isEmpty ? "Uncategorized".localized() : clean
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }
}
