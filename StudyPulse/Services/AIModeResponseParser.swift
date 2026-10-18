//
//  AIModeResponseParser.swift
//  StudyPulse
//
//  Splits a model reply into body text and the trailing "follow-up
//  questions" section, and removes <think> blocks. Pure function.
//

import Foundation

nonisolated struct AIParsedReply: Equatable, Sendable {
    var body: String
    var followUps: [String]
    /// Validated write proposals (empty unless an `AIActionContext` was supplied).
    var actions: [AIProposedAction] = []
}

nonisolated enum AIModeResponseParser {

    /// Headings accepted for the follow-up section (all supported languages).
    static let followUpHeadings: [String] = [
        "继续追问", "繼續追問", "Follow-up questions", "Follow-up Questions", "続けて質問", "이어서 질문",
    ]

    /// Heading the prompt asks the model to use for the given UI locale.
    static func heading(forLocale identifier: String?) -> String {
        let id = (identifier ?? "").lowercased()
        if id.hasPrefix("zh-hant") || id.hasPrefix("zh-tw") || id.hasPrefix("zh-hk") || id.hasPrefix("zh_tw") {
            return "繼續追問"
        }
        if id.hasPrefix("zh") { return "继续追问" }
        if id.hasPrefix("ja") { return "続けて質問" }
        if id.hasPrefix("ko") { return "이어서 질문" }
        return "Follow-up questions"
    }

    static let maxFollowUps = 3

    static func parse(_ raw: String, actionContext: AIActionContext? = nil) -> AIParsedReply {
        let extracted = AIModeActionParser.extract(from: stripThinking(raw), context: actionContext)
        let cleaned = extracted.text
        let lines = cleaned.components(separatedBy: "\n")
        var headingIndex: Int?
        for (index, line) in lines.enumerated().reversed() {
            if isFollowUpHeading(line) { headingIndex = index; break }
        }
        guard let headingIndex else {
            return AIParsedReply(body: cleaned.trimmingCharacters(in: .whitespacesAndNewlines), followUps: [], actions: extracted.actions)
        }
        let body = lines[..<headingIndex].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var followUps: [String] = []
        for line in lines[(headingIndex + 1)...] {
            let item = stripListMarker(line)
            if !item.isEmpty { followUps.append(item) }
            if followUps.count >= maxFollowUps { break }
        }
        return AIParsedReply(body: body, followUps: followUps, actions: extracted.actions)
    }

    /// Removes `<think>…</think>` blocks, and an unterminated trailing `<think>…`
    /// (the model is still reasoning while streaming).
    static func stripThinking(_ text: String) -> String {
        var result = text
        while let open = result.range(of: "<think>") {
            if let close = result.range(of: "</think>", range: open.upperBound..<result.endIndex) {
                result.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                result.removeSubrange(open.lowerBound..<result.endIndex)
            }
        }
        // A stray closing tag (reasoning started before the first chunk).
        if let close = result.range(of: "</think>") {
            result.removeSubrange(result.startIndex..<close.upperBound)
        }
        return result
    }

    private static func isFollowUpHeading(_ line: String) -> Bool {
        var text = line.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("#") else { return false }
        text = String(text.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ":：*"))
        return followUpHeadings.contains { text.caseInsensitiveCompare($0) == .orderedSame }
    }

    private static func stripListMarker(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "• ", "· "] where text.hasPrefix(marker) {
            text = String(text.dropFirst(marker.count))
            break
        }
        // "1. " / "1) " / "1、"
        if let first = text.firstIndex(where: { !$0.isNumber }), first != text.startIndex {
            let rest = text[first...]
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") || rest.hasPrefix("、") {
                text = String(rest.dropFirst(rest.hasPrefix("、") ? 1 : 2))
            }
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"“”「」")).trimmingCharacters(in: .whitespaces)
    }
}
