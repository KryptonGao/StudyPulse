//
//  AIContextComposer.swift
//  StudyPulse
//
//  Builds the compact, explicit text context sent to the model in AI Mode.
//  Priority for choosing data: user references > keyword routing > default
//  (grades + mistakes). Every block states its time range, units, full
//  score and whether it is limited by the active study phase, so the model
//  never has to guess. Pure function; no SwiftUI.
//

import Foundation

nonisolated struct AIContextPayload: Equatable, Sendable {
    var text: String
    var sources: [AISourceLink]
    var domains: [AIDataDomain]
    /// True when HealthKit-derived values are present in `text`.
    var containsHealth: Bool
    /// Domains that were requested but had too little data to analyse.
    var insufficientDomains: [AIDataDomain]
}

nonisolated enum AIContextComposer {

    static let deepBudget = 6000
    static let quickBudget = 2500

    // MARK: Routing

    private static let keywords: [AIDataDomain: [String]] = [
        .grades: [
            "成绩", "成績", "分数", "分數", "考试成绩", "平均分", "排名", "趋势", "趨勢", "进步", "進步", "退步",
            "grade", "grades", "score", "scores", "marks", "average", "trend", "ranking",
            "成績", "点数", "点数", "平均点", "偏差値",
            "성적", "점수", "평균", "추세", "등수",
        ],
        .mistakes: [
            "错题", "錯題", "错因", "錯因", "复习", "複習", "薄弱", "易错", "易錯", "掌握",
            "mistake", "mistakes", "wrong", "review", "weak", "weakness", "flashcard",
            "間違い", "ミス", "復習", "弱点",
            "오답", "복습", "약점",
        ],
        .exams: [
            "考试", "考試", "倒计时", "倒數", "备考", "備考", "复习计划", "複習計畫", "考前",
            "exam", "exams", "test", "deadline", "countdown", "prepare", "study plan",
            "試験", "テスト", "試験勉強", "受験",
            "시험", "수능", "준비",
        ],
        .time: [
            "时间", "時間", "专注", "專注", "学习时长", "學習時長", "投入", "计时", "計時", "打卡", "连续", "連續",
            "time", "focus", "hours", "streak", "timer", "study time", "spent",
            "勉強時間", "集中", "連続",
            "시간", "집중", "연속",
        ],
        .health: [
            "身体", "身體", "睡眠", "心率", "hrv", "恢复", "恢復", "疲劳", "疲勞", "状态", "狀態", "精力", "身心",
            "sleep", "heart", "recovery", "fatigue", "tired", "energy", "health", "body",
            "睡眠", "疲れ", "回復", "体調",
            "수면", "피로", "회복", "컨디션",
        ],
        .diary: [
            "日记", "日記", "心情", "情绪", "情緒", "感受", "压力", "壓力", "焦虑", "焦慮",
            "diary", "journal", "mood", "feeling", "emotion", "stress", "anxious",
            "日記", "気分", "感情", "ストレス",
            "일기", "기분", "감정", "스트레스",
        ],
    ]

    /// Domains whose keywords appear in `text`, in the fixed domain order.
    static func route(_ text: String) -> [AIDataDomain] {
        let lowered = text.lowercased()
        guard !lowered.isEmpty else { return [] }
        return AIDataDomain.allCases.filter { domain in
            (keywords[domain] ?? []).contains { lowered.contains($0.lowercased()) }
        }
    }

    /// User references first, then keyword routing, then the grades+mistakes default.
    static func selectDomains(
        userText: String,
        references: [AIDataReference],
        mode: AIAnswerMode
    ) -> [AIDataDomain] {
        let maxDomains = mode == .deep ? 3 : 2
        var ordered: [AIDataDomain] = []
        func add(_ domain: AIDataDomain) {
            if !ordered.contains(domain) { ordered.append(domain) }
        }
        references.forEach { add($0.domain) }
        route(userText).forEach(add)
        if ordered.isEmpty { add(.grades); add(.mistakes) }
        return Array(ordered.prefix(max(maxDomains, references.count)))
    }

    // MARK: Compose

    static func compose(
        userText: String,
        references: [AIDataReference],
        snapshot: AIStudyDataSnapshot,
        mode: AIAnswerMode,
        existingRecordIDs: Set<UUID> = [],
        now: Date = Date()
    ) -> AIContextPayload {
        let domains = selectDomains(userText: userText, references: references, mode: mode)

        let budget = mode == .deep ? deepBudget : quickBudget
        let perDomain = max(600, budget / max(domains.count, 1))
        let listLimit = mode == .deep ? 5 : 3

        var blocks: [String] = []
        var sources: [AISourceLink] = []
        var insufficient: [AIDataDomain] = []
        var containsHealth = false

        var header = ["【数据范围说明】"]
        header.append("当前日期：\(ymd(now))。")
        if let phase = snapshot.phaseName {
            header.append("成绩、错题、考试、日记按目前学习阶段「\(phase)」筛选；学习时间与身心数据不受阶段筛选，为全部历史。")
        } else {
            header.append("当前未选择学习阶段，所有数据均为全部历史。")
        }
        blocks.append(header.joined(separator: "\n"))

        for domain in domains {
            let refs = references.filter { $0.domain == domain }
            let block: (lines: [String], sources: [AISourceLink], insufficient: Bool)
            switch domain {
            case .grades:
                block = gradesBlock(snapshot, refs: refs, limit: listLimit)
            case .mistakes:
                block = mistakesBlock(snapshot.mistakes, limit: listLimit, now: now)
            case .exams:
                block = examsBlock(snapshot.exams, limit: listLimit, now: now)
            case .time:
                block = timeBlock(snapshot.time, limit: listLimit)
            case .health:
                block = healthBlock(snapshot.health)
                if snapshot.health.state == .available { containsHealth = true }
            case .diary:
                block = diaryBlock(snapshot.diary, phaseName: snapshot.phaseName)
            }
            var lines = block.lines
            let domainSources = block.sources
            let isInsufficient = block.insufficient

            // Phase mismatch / deleted records noted per reference.
            for ref in refs {
                if let refPhase = ref.phaseId, refPhase != snapshot.phaseId, domain != .time, domain != .health {
                    lines.append("注：该引用创建于其他学习阶段，已改以目前阶段的数据重新统计。")
                }
                let missing = ref.recordIDs.filter { !existingRecordIDs.contains($0) }
                if !missing.isEmpty {
                    lines.append("注：引用的 \(missing.count) 条记录已被删除，无法提供其内容。")
                }
            }

            blocks.append(cap(lines, maxChars: perDomain))
            sources.append(contentsOf: domainSources)
            if isInsufficient { insufficient.append(domain) }
        }

        var text = blocks.joined(separator: "\n\n")
        if text.count > budget + 400 {
            text = String(text.prefix(budget + 400)) + "…"
        }
        return AIContextPayload(
            text: text,
            sources: dedupe(sources),
            domains: domains,
            containsHealth: containsHealth,
            insufficientDomains: insufficient
        )
    }

    // MARK: Domain blocks

    private static func gradesBlock(
        _ snapshot: AIStudyDataSnapshot,
        refs: [AIDataReference],
        limit: Int
    ) -> (lines: [String], sources: [AISourceLink], insufficient: Bool) {
        let range = refs.first.map { gradeRange(for: $0.scope.kind) } ?? .days30
        let subjectFilter = refs.compactMap(\.subject).first
        let grades = snapshot.grades(range)
        var lines = ["【成绩】时间范围：\(rangeLabel(range))；分数为原始分，括号内为该科满分；得分率=得分/满分。"]
        guard !grades.isEmpty else {
            lines.append("资料不足：该范围内没有成绩记录。")
            return (lines, [.page(.grades, label: sourceLabel(.grades))], true)
        }
        var rows = grades.rows
        if let subjectFilter {
            rows = rows.filter { $0.subject == subjectFilter }
            lines.append("聚焦科目：\(subjectFilter)")
        }
        if grades.hasEnoughForTrend, let average = grades.trend.average {
            var line = "整体平均得分率 \(num(average))%"
            if let delta = grades.trend.delta { line += "（较上一等长区间 \(signed(delta)) 个百分点）" }
            line += "；共 \(grades.gradeCount) 次成绩、\(grades.trend.subjectCount) 科"
            if let target = grades.trend.targetRate { line += "；阶段目标折算得分率 \(num(target))%" }
            lines.append(line)
        } else {
            lines.append("资料不足：成绩记录少于 2 条，不足以判断趋势（仅 \(grades.gradeCount) 条）。")
        }
        for row in rows.prefix(limit) {
            lines.append(
                "- \(row.subject)：平均 \(num(row.averageScore))/\(num(row.fullScore, 0))（得分率 \(num(row.averageRate))%），"
                + "最近一次 \(num(row.latestScore))/\(num(row.fullScore, 0))（\(row.latestExamName.isEmpty ? "未命名考试" : row.latestExamName)，\(ymd(row.latestDate))），"
                + "近期变化 \(signed(row.delta)) 分，共 \(row.count) 次"
            )
        }
        var sources: [AISourceLink] = [.page(.grades, label: sourceLabel(.grades))]
        if let weakest = grades.rows.min(by: { $0.averageRate < $1.averageRate }) {
            sources.append(AISourceLink(kind: .subject, domain: .grades, subjectName: weakest.subject, label: weakest.subject))
        }
        return (lines, sources, !grades.hasEnoughForTrend)
    }

    private static func mistakesBlock(
        _ m: AIMistakesSnapshot,
        limit: Int,
        now: Date
    ) -> (lines: [String], sources: [AISourceLink], insufficient: Bool) {
        var lines = ["【错题】统计全部错题（已按阶段筛选）；掌握度 0–100%，≥\(Int(AIMistakesSnapshot.masteredThreshold * 100))% 视为已掌握。"]
        guard !m.isEmpty else {
            lines.append("资料不足：没有错题记录。")
            return (lines, [.page(.mistakes, label: sourceLabel(.mistakes))], true)
        }
        lines.append("共 \(m.total) 题，已掌握 \(m.masteredCount) 题；今日待复习 \(m.review.total) 题（其中逾期 \(m.review.overdue) 题），未来一周内到期 \(m.review.upcoming) 题。")
        for subject in m.subjects.prefix(limit) {
            lines.append("- \(subject.subject)：\(subject.count) 题，待复习 \(subject.due)，平均掌握度 \(num(subject.mastery * 100))%")
        }
        if !m.priority.isEmpty {
            lines.append("优先复习：")
            for row in m.priority.prefix(limit) {
                lines.append("- 《\(row.title.isEmpty ? "未命名" : row.title)》（\(row.subject)，掌握度 \(num(row.mastery * 100))%，\(reviewText(row.daysUntilReview))）")
            }
        }
        for pattern in m.patterns {
            lines.append("反复出现的错误类型：\(pattern.pattern.titleKey.localized())，\(pattern.count) 题，涉及 \(pattern.subjects.joined(separator: "、"))")
        }
        var sources: [AISourceLink] = [.page(.mistakes, label: sourceLabel(.mistakes))]
        for row in m.priority.prefix(2) {
            sources.append(AISourceLink(kind: .mistake, domain: .mistakes, targetID: row.id, label: row.title.isEmpty ? row.subject : row.title))
        }
        return (lines, sources, false)
    }

    private static func examsBlock(
        _ e: AIExamsSnapshot,
        limit: Int,
        now: Date
    ) -> (lines: [String], sources: [AISourceLink], insufficient: Bool) {
        var lines = ["【考试与计划】仅列出尚未开始的考试（已按阶段筛选）；掌握程度 0–100。"]
        guard !e.upcoming.isEmpty else {
            lines.append("资料不足：没有即将到来的考试。")
            if let plan = e.plan { lines.append("最近的备考计划（\(plan.examName)，\(ymd(plan.createdAt))）：\(String(plan.summary.prefix(300)))") }
            return (lines, [.page(.exams, label: sourceLabel(.exams))], true)
        }
        for row in e.upcoming.prefix(limit) {
            var line = "- \(row.name)（\(row.subjects.joined(separator: "、"))）：\(ymd(row.date))，\(row.daysUntil == 0 ? "今天" : "还有 \(row.daysUntil) 天")，重要度 \(row.importance)/5，掌握程度 \(row.mastery)"
            if let done = row.checklistDone, let total = row.checklistTotal { line += "，考前清单 \(done)/\(total)" }
            lines.append(line)
        }
        if let plan = e.plan {
            lines.append("最近的备考计划（\(plan.examName)，\(ymd(plan.createdAt))）：\(String(plan.summary.prefix(300)))")
        }
        var sources: [AISourceLink] = [.page(.exams, label: sourceLabel(.exams))]
        for row in e.upcoming.prefix(2) {
            sources.append(AISourceLink(
                kind: row.isComprehensive ? .comprehensiveExam : .exam, domain: .exams, targetID: row.id, label: row.name
            ))
        }
        return (lines, sources, false)
    }

    private static func timeBlock(
        _ t: AITimeSnapshot,
        limit: Int
    ) -> (lines: [String], sources: [AISourceLink], insufficient: Bool) {
        var lines = ["【学习时间】不受阶段筛选，为全部历史；本周从周一起算；仅统计已完成的计时会话。"]
        guard !t.isEmpty else {
            lines.append("资料不足：没有已完成的学习计时记录。")
            return (lines, [.page(.time, label: sourceLabel(.time))], true)
        }
        let delta = t.weekSeconds - t.previousWeekSeconds
        lines.append("本周累计 \(hours(t.weekSeconds))，上周 \(hours(t.previousWeekSeconds))（\(delta >= 0 ? "+" : "-")\(hours(abs(delta)))）；当前连续学习 \(t.streak) 天；有 \(t.unassignedCount) 个会话未归入任何项目。")
        if !t.days.isEmpty {
            let perDay = t.days.map { "\(Int($0.minutes.rounded()))分" }.joined(separator: "、")
            lines.append("最近 7 天每日专注（旧→新）：\(perDay)")
        }
        for project in t.projects.prefix(limit) {
            lines.append("- \(project.name)：本周 \(hours(project.seconds))")
        }
        var sources: [AISourceLink] = [.page(.time, label: sourceLabel(.time))]
        if let top = t.projects.first {
            sources.append(AISourceLink(kind: .timeProject, domain: .time, targetID: top.id, label: top.name))
        }
        return (lines, sources, false)
    }

    private static func healthBlock(
        _ h: AIHealthSnapshot
    ) -> (lines: [String], sources: [AISourceLink], insufficient: Bool) {
        var lines = ["【身心状态】不受阶段筛选；来自用户授权的 Apple 健康数据，恢复分 0–100。"]
        let source = [AISourceLink.page(.health, label: sourceLabel(.health))]
        switch h.state {
        case .disabled:
            lines.append("资料不足：用户尚未启用身心状态功能。")
            return (lines, source, true)
        case .unauthorized:
            lines.append("资料不足：用户尚未授权读取健康数据。")
            return (lines, source, true)
        case .loading:
            lines.append("资料不足：健康数据仍在加载。")
            return (lines, source, true)
        case .insufficient:
            lines.append("资料不足：健康数据样本不足以计算恢复分。")
            return (lines, source, true)
        case .available:
            break
        }
        if let score = h.recoveryScore { lines.append("恢复分 \(score)/100") }
        if let category = h.readinessCategory { lines.append("HRV 准备度分类：\(category)") }
        if let z = h.hrvZScore { lines.append("HRV 相对个人基线 Z 值 \(num(z, 2))") }
        if let hrv = h.todayHRV { lines.append("今日 HRV(SDNN) \(num(hrv, 0)) ms") }
        if let value = h.restingHeartRate { lines.append("静息心率 \(num(value, 0)) 次/分") }
        if let value = h.respiratoryRate { lines.append("呼吸率 \(num(value)) 次/分") }
        if let value = h.sleepHours { lines.append("昨夜睡眠 \(num(value)) 小时") }
        if let value = h.restorativeSleepHours { lines.append("恢复性睡眠（深睡+REM）\(num(value)) 小时") }
        if let value = h.exerciseMinutes { lines.append("今日锻炼 \(num(value, 0)) 分钟") }
        return (lines, source, false)
    }

    private static func diaryBlock(
        _ d: AIDiarySnapshot,
        phaseName: String?
    ) -> (lines: [String], sources: [AISourceLink], insufficient: Bool) {
        var lines = ["【学习日记】已按阶段筛选；心情与精力均为 1–5 分（5 最好）。"]
        guard let latest = d.latest else {
            lines.append("资料不足：没有日记记录。")
            return (lines, [.page(.diary, label: sourceLabel(.diary))], true)
        }
        lines.append("近 30 天共 \(d.entryCount30) 篇日记；连续记录 \(d.streak) 天" + (d.averageMood.map { "；平均心情 \(num($0))/5" } ?? ""))
        lines.append("最新一篇（\(ymd(latest.date))）：心情 \(latest.moodScore)/5，精力 \(latest.energyScore)/5" + (latest.energyTag.isEmpty ? "" : "，标签「\(latest.energyTag)」"))
        if !latest.excerpt.isEmpty { lines.append("摘录：\(latest.excerpt)") }
        let sources = [
            AISourceLink.page(.diary, label: sourceLabel(.diary)),
            AISourceLink(kind: .diary, domain: .diary, targetID: latest.id, label: ymd(latest.date)),
        ]
        return (lines, sources, d.streak == 0 && d.entryCount30 < 2)
    }

    // MARK: Helpers

    static func gradeRange(for kind: AIDateScopeKind) -> AIGradeRange {
        switch kind {
        case .last7Days, .last30Days, .custom: return .days30
        case .last90Days: return .days90
        case .phaseAll: return .phase
        }
    }

    private static func rangeLabel(_ range: AIGradeRange) -> String {
        switch range {
        case .days30: return "近 30 天"
        case .days90: return "近 90 天"
        case .phase: return "目前阶段全部"
        }
    }

    private static func sourceLabel(_ domain: AIDataDomain) -> String {
        "aiMode.domain.\(domain.rawValue)".localized()
    }

    private static func reviewText(_ days: Int?) -> String {
        guard let days else { return "未加入复习队列" }
        if days < 0 { return "已逾期 \(-days) 天" }
        if days == 0 { return "今天复习" }
        return "\(days) 天后复习"
    }

    private static func cap(_ lines: [String], maxChars: Int) -> String {
        var result: [String] = []
        var used = 0
        for line in lines {
            if used + line.count + 1 > maxChars, !result.isEmpty {
                result.append("…（其余内容已省略）")
                break
            }
            result.append(line)
            used += line.count + 1
        }
        return result.joined(separator: "\n")
    }

    private static func dedupe(_ sources: [AISourceLink]) -> [AISourceLink] {
        var seen = Set<String>()
        var result: [AISourceLink] = []
        for source in sources {
            let key = "\(source.kind.rawValue)|\(source.domain?.rawValue ?? "")|\(source.targetID?.uuidString ?? "")|\(source.subjectName ?? "")"
            if seen.insert(key).inserted { result.append(source) }
        }
        return result
    }

    static func ymd(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func num(_ value: Double, _ digits: Int = 1) -> String {
        let text = String(format: "%.\(digits)f", value)
        guard digits > 0, text.contains(".") else { return text }
        var trimmed = text
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    private static func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + num(value)
    }

    private static func hours(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟" }
        return "\(num(Double(seconds) / 3600)) 小时"
    }
}
