//
//  AIModeActionParser.swift
//  StudyPulse
//
//  Pulls the machine-readable ```studypulse-actions block out of a model reply,
//  validates each proposal against the user's subjects, and returns the reply
//  text with the block removed. Pure function.
//

import Foundation

nonisolated enum AIModeActionParser {

    static let fenceTag = "studypulse-actions"
    static let maxActions = 5

    struct Result: Equatable, Sendable {
        var text: String
        var actions: [AIProposedAction]
    }

    /// Removes every action block (including an unterminated trailing one while
    /// streaming) and returns the validated proposals.
    static func extract(from raw: String, context: AIActionContext?) -> Result {
        var text = raw
        var payloads: [String] = []
        let opener = "```" + fenceTag

        while let open = text.range(of: opener, options: .caseInsensitive) {
            let bodyStart = open.upperBound
            if let close = text.range(of: "```", range: bodyStart..<text.endIndex) {
                payloads.append(String(text[bodyStart..<close.lowerBound]))
                text.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                text.removeSubrange(open.lowerBound..<text.endIndex)
            }
        }

        guard let context else { return Result(text: text, actions: []) }
        var actions: [AIProposedAction] = []
        for payload in payloads {
            actions.append(contentsOf: decode(payload, context: context))
        }
        return Result(text: text, actions: Array(actions.prefix(maxActions)))
    }

    // MARK: Decoding

    private struct RawAction: Decodable {
        var type: String?
        // add_grade
        var subject: String?
        var score: Double?
        var fullScore: Double?
        var examName: String?
        var date: String?
        var importance: Int?
        // add_task
        var title: String?
        var kind: String?
        var dueDate: String?
        var notes: String?
    }

    private static func decode(_ payload: String, context: AIActionContext) -> [AIProposedAction] {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        let items: [RawAction]
        if let array = try? decoder.decode([RawAction].self, from: data) {
            items = array
        } else if let single = try? decoder.decode(RawAction.self, from: data) {
            items = [single]
        } else {
            return []
        }
        return items.compactMap { validate($0, context: context) }
    }

    private static func validate(_ raw: RawAction, context: AIActionContext) -> AIProposedAction? {
        switch raw.type?.lowercased() {
        case AIActionKind.addGrade.rawValue:
            guard let subject = context.resolve(raw.subject ?? ""),
                  let score = raw.score, score.isFinite, score >= 0 else { return nil }
            let full = (raw.fullScore.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }) ?? subject.fullScore
            guard score <= full else { return nil }
            let date = raw.date.flatMap { parseDate($0) } ?? context.now
            guard date <= context.now.addingTimeInterval(24 * 3600) else { return nil }
            let draft = AIGradeDraft(
                subject: subject.name,
                subjectDisplayName: subject.displayName,
                score: score,
                fullScore: full,
                examName: (raw.examName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                date: date,
                importance: clampImportance(raw.importance)
            )
            return AIProposedAction(kind: .addGrade, grade: draft)

        case AIActionKind.addTask.rawValue:
            let title = (raw.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let dueText = raw.dueDate, let due = parseDate(dueText) else { return nil }
            let subject = context.resolve(raw.subject ?? "")
            let draft = AITaskDraft(
                title: title,
                type: raw.kind?.lowercased() == TaskType.reading.rawValue ? .reading : .homework,
                dueDate: due,
                subject: subject?.name ?? "",
                subjectDisplayName: subject?.displayName ?? "",
                notes: (raw.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                importance: clampImportance(raw.importance)
            )
            return AIProposedAction(kind: .addTask, task: draft)

        default:
            return nil
        }
    }

    private static func clampImportance(_ value: Int?) -> Int { min(max(value ?? 3, 1), 5) }

    /// Accepts `yyyy-MM-dd` (end of that day for tasks is the caller's concern — we use 09:00
    /// only for date-only input) and `yyyy-MM-dd HH:mm` / ISO-8601.
    static func parseDate(_ text: String, calendar: Calendar = .current) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                if format == "yyyy-MM-dd" {
                    return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
                }
                return date
            }
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
