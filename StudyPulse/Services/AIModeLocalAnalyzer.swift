//
//  AIModeLocalAnalyzer.swift
//  StudyPulse
//
//  Deterministic Markdown analysis built from the same snapshot that feeds the
//  data pages. Used when no model is configured or a request fails; the UI
//  labels it "local analysis", never as a model reply.
//

import Foundation

nonisolated enum AIModeLocalAnalyzer {

    static func analyze(
        userText: String,
        references: [AIDataReference],
        snapshot: AIStudyDataSnapshot,
        now: Date = Date()
    ) -> (markdown: String, sources: [AISourceLink], followUps: [String]) {
        let domains = AIContextComposer.selectDomains(userText: userText, references: references, mode: .deep)
        var sections: [String] = []
        var sources: [AISourceLink] = []
        for domain in domains {
            let section: (String, [AISourceLink])
            switch domain {
            case .grades: section = grades(snapshot, references: references)
            case .mistakes: section = mistakes(snapshot.mistakes)
            case .exams: section = exams(snapshot.exams)
            case .time: section = time(snapshot.time)
            case .health: section = health(snapshot.health)
            case .diary: section = diary(snapshot.diary)
            }
            sections.append(section.0)
            sources.append(contentsOf: section.1)
        }
        var seen = Set<String>()
        let uniqueSources = sources.filter {
            seen.insert("\($0.kind.rawValue)|\($0.domain?.rawValue ?? "")|\($0.targetID?.uuidString ?? "")|\($0.subjectName ?? "")").inserted
        }
        let followUps = domains.prefix(2).map { "aiMode.local.followUp.\($0.rawValue)".localized() }
        return (sections.joined(separator: "\n\n"), uniqueSources, followUps)
    }

    // MARK: Sections

    private static func title(_ domain: AIDataDomain) -> String {
        "### " + "aiMode.domain.\(domain.rawValue)".localized()
    }

    private static func page(_ domain: AIDataDomain) -> AISourceLink {
        .page(domain, label: "aiMode.domain.\(domain.rawValue)".localized())
    }

    private static func grades(_ s: AIStudyDataSnapshot, references: [AIDataReference]) -> (String, [AISourceLink]) {
        let range = references.first(where: { $0.domain == .grades })
            .map { AIContextComposer.gradeRange(for: $0.scope.kind) } ?? .days30
        let g = s.grades(range)
        var lines = [title(.grades)]
        guard !g.isEmpty else {
            lines.append("aiMode.local.grades.empty".localized())
            return (lines.joined(separator: "\n"), [page(.grades)])
        }
        guard g.hasEnoughForTrend, let average = g.trend.average else {
            lines.append(String(format: "aiMode.local.grades.few".localized(), g.gradeCount))
            return (lines.joined(separator: "\n"), [page(.grades)])
        }
        lines.append(String(format: "aiMode.local.grades.overall".localized(), average, g.gradeCount, g.trend.subjectCount))
        if let delta = g.trend.delta {
            lines.append(String(format: "aiMode.local.grades.delta".localized(), delta))
        }
        var sources = [page(.grades)]
        if let weakest = g.rows.min(by: { $0.averageRate < $1.averageRate }) {
            lines.append(String(format: "aiMode.local.grades.weakest".localized(), weakest.subject, weakest.averageScore, weakest.fullScore, weakest.averageRate))
            sources.append(AISourceLink(kind: .subject, domain: .grades, subjectName: weakest.subject, label: weakest.subject))
        }
        if let dropping = g.rows.filter({ $0.delta < 0 }).min(by: { $0.delta < $1.delta }) {
            lines.append(String(format: "aiMode.local.grades.dropping".localized(), dropping.subject, dropping.delta))
        }
        return (lines.joined(separator: "\n"), sources)
    }

    private static func mistakes(_ m: AIMistakesSnapshot) -> (String, [AISourceLink]) {
        var lines = [title(.mistakes)]
        guard !m.isEmpty else {
            lines.append("aiMode.local.mistakes.empty".localized())
            return (lines.joined(separator: "\n"), [page(.mistakes)])
        }
        lines.append(String(format: "aiMode.local.mistakes.overview".localized(), m.total, m.masteredCount, m.review.total))
        if m.review.overdue > 0 {
            lines.append(String(format: "aiMode.local.mistakes.overdue".localized(), m.review.overdue))
        }
        var sources = [page(.mistakes)]
        if let top = m.priority.first {
            lines.append(String(format: "aiMode.local.mistakes.top".localized(), top.title.isEmpty ? top.subject : top.title, top.mastery * 100))
            sources.append(AISourceLink(kind: .mistake, domain: .mistakes, targetID: top.id, label: top.title.isEmpty ? top.subject : top.title))
        }
        if let pattern = m.patterns.first {
            lines.append(String(format: "aiMode.local.mistakes.pattern".localized(), pattern.pattern.titleKey.localized(), pattern.count))
        }
        return (lines.joined(separator: "\n"), sources)
    }

    private static func exams(_ e: AIExamsSnapshot) -> (String, [AISourceLink]) {
        var lines = [title(.exams)]
        guard let next = e.upcoming.first else {
            lines.append("aiMode.local.exams.empty".localized())
            return (lines.joined(separator: "\n"), [page(.exams)])
        }
        lines.append(String(format: "aiMode.local.exams.next".localized(), next.name, next.daysUntil, next.mastery))
        if e.upcoming.count > 1 {
            lines.append(String(format: "aiMode.local.exams.more".localized(), e.upcoming.count - 1))
        }
        if let done = next.checklistDone, let total = next.checklistTotal, total > 0 {
            lines.append(String(format: "aiMode.local.exams.checklist".localized(), done, total))
        }
        let source = AISourceLink(
            kind: next.isComprehensive ? .comprehensiveExam : .exam, domain: .exams, targetID: next.id, label: next.name
        )
        return (lines.joined(separator: "\n"), [page(.exams), source])
    }

    private static func time(_ t: AITimeSnapshot) -> (String, [AISourceLink]) {
        var lines = [title(.time)]
        guard !t.isEmpty else {
            lines.append("aiMode.local.time.empty".localized())
            return (lines.joined(separator: "\n"), [page(.time)])
        }
        lines.append(String(format: "aiMode.local.time.week".localized(), Double(t.weekSeconds) / 3600, Double(t.previousWeekSeconds) / 3600))
        lines.append(String(format: "aiMode.local.time.streak".localized(), t.streak))
        var sources = [page(.time)]
        if let top = t.projects.first {
            lines.append(String(format: "aiMode.local.time.top".localized(), top.name, Double(top.seconds) / 3600))
            sources.append(AISourceLink(kind: .timeProject, domain: .time, targetID: top.id, label: top.name))
        }
        return (lines.joined(separator: "\n"), sources)
    }

    private static func health(_ h: AIHealthSnapshot) -> (String, [AISourceLink]) {
        var lines = [title(.health)]
        switch h.state {
        case .disabled: lines.append("aiMode.local.health.disabled".localized())
        case .unauthorized: lines.append("aiMode.local.health.unauthorized".localized())
        case .loading: lines.append("aiMode.local.health.loading".localized())
        case .insufficient: lines.append("aiMode.local.health.insufficient".localized())
        case .available:
            lines.append(String(format: "aiMode.local.health.score".localized(), h.recoveryScore ?? 0))
            if let sleep = h.restorativeSleepHours {
                lines.append(String(format: "aiMode.local.health.sleep".localized(), sleep))
            }
        }
        return (lines.joined(separator: "\n"), [page(.health)])
    }

    private static func diary(_ d: AIDiarySnapshot) -> (String, [AISourceLink]) {
        var lines = [title(.diary)]
        guard let latest = d.latest else {
            lines.append("aiMode.local.diary.empty".localized())
            return (lines.joined(separator: "\n"), [page(.diary)])
        }
        lines.append(String(format: "aiMode.local.diary.latest".localized(), latest.moodScore, latest.energyScore))
        lines.append(String(format: "aiMode.local.diary.streak".localized(), d.streak))
        if let average = d.averageMood {
            lines.append(String(format: "aiMode.local.diary.average".localized(), average))
        }
        let source = AISourceLink(kind: .diary, domain: .diary, targetID: latest.id, label: AIContextComposer.ymd(latest.date))
        return (lines.joined(separator: "\n"), [page(.diary), source])
    }
}
