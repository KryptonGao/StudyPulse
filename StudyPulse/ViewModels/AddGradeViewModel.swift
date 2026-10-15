//
//  AddGradeViewModel.swift
//  StudyPulse
//
//  Created by Antigravity on 2026/7/12.
//
//  新增成绩 ViewModel。负责单科/综合考试的成绩录入 + 保存到 Repository。
//  Add-grade ViewModel. Single/comprehensive exam form + persistence.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class AddGradeViewModel {
    // MARK: - 依赖项 / Dependencies
    private let container: RepositoryContainer

    // MARK: - 输入/输出状态 / Input & output state
    /// 考试名称 / Exam name
    var examName: String = ""
    /// 考试日期 / Exam date
    var selectedDate: Date = Date()
    /// 重要性(影响预测权重) / Importance (affects prediction weight)
    var importance: Int = 3
    /// 是否综合考试 / Whether this is a comprehensive exam
    var isComprehensiveExam: Bool = false
    /// 单科考试时选中的科目 / Selected subject (single-subject exam)
    var selectedSingleSubject: String = ""
    /// 综合考试时选中的多个科目 / Selected subjects (comprehensive exam)
    var selectedMultipleSubjects: [String] = []
    /// 各科目的分项成绩 / Per-subject score entries
    var subjectScores: [SubjectScore] = []
    /// 当前关联考试 ID；nil 表示“未归档”（暂不关联考试）
    var selectedExamID: UUID?
    var selectedExamIsComprehensive = false
    var isExamListExpanded = false

    struct ExamOption: Identifiable, Hashable {
        let id: UUID
        let name: String
        let subjectText: String
        let date: Date
        let endedAt: Date
        let isComprehensive: Bool
    }

    /// 单个科目的成绩条目(支持原分 / 排名)
    /// Per-subject score entry (supports raw-score and ranking).
    struct SubjectScore: Identifiable, Equatable {
        let id: UUID
        let subject: String
        var score: Double
        var useRawScore: Bool
        var useRanking: Bool
        var rawScore: Double
        var ranking: Int?

        init(subject: String, score: Double = 85.0, useRawScore: Bool = false, useRanking: Bool = false, rawScore: Double = 85.0, ranking: Int? = 1) {
            self.id = UUID()
            self.subject = subject
            self.score = score
            self.useRawScore = useRawScore
            self.useRanking = useRanking
            self.rawScore = rawScore
            self.ranking = ranking
        }
    }

    // MARK: - 初始化 / Initialization
    init(container: RepositoryContainer) {
        self.container = container
    }

    /// 从 Siri / 外部入口预填科目与分数
    /// Pre-fills subject & score from Siri / external entry.
    func seedPreset(presetSubject: String, presetScore: Double, presetExamName: String?) {
        self.selectedSingleSubject = presetSubject
        self.examName = presetExamName ?? ""
        self.subjectScores = [
            SubjectScore(subject: presetSubject, score: presetScore)
        ]
    }

    // MARK: - 计算属性 / Computed properties
    /// 启用且非 "GROUP:" 聚合的科目列表
    /// Enabled subjects, excluding "GROUP:" aggregate entries.
    var availableSubjects: [String] {
        container.subjectRepo.subjects.filter {
            $0.enabled && !$0.name.starts(with: "GROUP:")
        }.map { $0.name }
    }

    /// 返回内部科目名的显示名(优先 subject.displayName,否则本地化 name)
    /// Display name for a subject (prefers `displayName`, falls back to localized `name`).
    func displayName(forSubject name: String) -> String {
        if let subject = container.subjectRepo.subjects.first(where: { $0.name == name }) {
            return subject.displayName.isEmpty ? name.localized() : subject.displayName
        }
        return name.localized()
    }

    /// 动态列表高度(60pt 每行) / Dynamic list height (60pt per row)
    var dynamicListHeight: CGFloat {
        CGFloat(availableSubjects.count * 60)
    }

    /// 已结束且未归档的考试。默认显示 15 天，展开后显示最近 3 个月。
    var examOptions: [ExamOption] {
        let calendar = Calendar.current
        let now = Date()
        let recentCutoff = calendar.date(byAdding: .day, value: -15, to: now) ?? now
        let expandedCutoff = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        let archivedPhaseIDs = Set(container.phaseRepo.phases.filter(\.isArchived).map(\.id))

        let singles = container.examRepo.filteredExamSets.compactMap { exam -> ExamOption? in
            guard exam.phaseId.map({ !archivedPhaseIDs.contains($0) }) ?? true else { return nil }
            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: exam.examEndDate ?? exam.examDate) ?? exam.examEndDate ?? exam.examDate
            guard end <= now, end >= expandedCutoff else { return nil }
            return ExamOption(id: exam.id, name: exam.name, subjectText: displayName(forSubject: exam.subject), date: exam.examDate, endedAt: end, isComprehensive: false)
        }
        let comprehensives = container.examRepo.filteredComprehensiveExamSets.compactMap { exam -> ExamOption? in
            guard exam.phaseId.map({ !archivedPhaseIDs.contains($0) }) ?? true else { return nil }
            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: exam.examEndDate ?? exam.examDate) ?? exam.examEndDate ?? exam.examDate
            guard end <= now, end >= expandedCutoff else { return nil }
            return ExamOption(id: exam.id, name: exam.name, subjectText: exam.subject.map(displayName(forSubject:)).joined(separator: ", "), date: exam.examDate, endedAt: end, isComprehensive: true)
        }
        let cutoff = isExamListExpanded ? expandedCutoff : recentCutoff
        return (singles + comprehensives).filter { $0.endedAt >= cutoff }.sorted { $0.endedAt > $1.endedAt }
    }

    func selectExam(_ option: ExamOption?) {
        guard let option else {
            selectedExamID = nil
            selectedExamIsComprehensive = false
            return
        }
        selectedExamID = option.id
        selectedExamIsComprehensive = option.isComprehensive
        examName = option.name
        selectedDate = option.date
        if option.isComprehensive, let exam = container.examRepo.comprehensiveExamSets.first(where: { $0.id == option.id }) {
            selectedMultipleSubjects = exam.subject
            isComprehensiveExam = true
        } else if let exam = container.examRepo.examSets.first(where: { $0.id == option.id }) {
            selectedSingleSubject = exam.subject
            isComprehensiveExam = false
        }
        syncSubjectScores()
    }

    /// 由科目与日期自动带出的考试名,例如「数学 2026-10-15」;未选科目时为空。
    /// Auto-suggested exam name built from subject(s) + date, e.g. "Math 2026-10-15"; empty with no subject.
    var suggestedExamName: String {
        let subjects = isComprehensiveExam ? selectedMultipleSubjects : [selectedSingleSubject].filter { !$0.isEmpty }
        guard !subjects.isEmpty else { return "" }
        let dateText = DateFormatters.mediumDate.string(from: selectedDate)
        let subjectText = isComprehensiveExam
            ? "Comprehensive Exam".localized()
            : displayName(forSubject: subjects[0])
        return "\(subjectText) \(dateText)"
    }

    /// 实际使用的考试名:用户填写优先,留空则回退到自动名。
    /// Exam name actually used: the user's input wins, otherwise the suggested name.
    var resolvedExamName: String {
        let trimmed = examName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? suggestedExamName : trimmed
    }

    /// 是否可保存:只要有科目成绩即可(考试名可自动带出)。
    /// Whether saving is allowed: needs at least one subject score (the name can be auto-filled).
    var canSave: Bool {
        !subjectScores.isEmpty && !resolvedExamName.isEmpty
    }

    /// 禁用保存时给用户看的原因提示;可保存时为 nil。
    /// Explains why Save is disabled; nil when saving is allowed.
    var saveBlockerHint: String? {
        if subjectScores.isEmpty {
            return "addGrade.hint.selectSubject".localized()
        }
        return resolvedExamName.isEmpty ? "addGrade.hint.examName".localized() : nil
    }

    /// 某科目的满分 / Full-score for a subject
    func fullScore(for subject: String) -> Double {
        container.fullScore(for: subject)
    }

    // MARK: - 操作 / Actions
    /// 切换综合考试多选列表中某科目的选中状态
    /// Toggles a subject's selection in the comprehensive-exam list.
    func toggleSubject(_ subject: String) {
        if selectedMultipleSubjects.contains(subject) {
            selectedMultipleSubjects.removeAll { $0 == subject }
        } else {
            selectedMultipleSubjects.append(subject)
        }
        syncSubjectScores()
    }

    /// 同步 `subjectScores` 与当前选中科目
    /// Reconciles `subjectScores` with the current subject selection.
    func syncSubjectScores() {
        let selected = isComprehensiveExam ? selectedMultipleSubjects : [selectedSingleSubject]
        let existing = subjectScores.map { $0.subject }

        // 新选中的科目 → 默认分数 85 / Newly selected → default score 85.
        for sub in selected where !existing.contains(sub) {
            subjectScores.append(SubjectScore(subject: sub))
        }

        // 取消选中的科目 → 移除 / Dropped subjects → remove.
        subjectScores.removeAll { !selected.contains($0.subject) }
    }

    /// 把 `subjectScores` 转成 `Grade` 模型,保存到 Repository
    /// Converts `subjectScores` into `Grade` models and persists them.
    func saveGrades() {
        let newGrades: [Grade] = subjectScores.map { subjectScore in
            var grade = Grade(
                subject: subjectScore.subject,
                score: subjectScore.score,
                rawScore: subjectScore.useRawScore ? subjectScore.rawScore : nil,
                ranking: subjectScore.useRanking ? subjectScore.ranking : nil,
                importance: importance,
                date: selectedDate,
                examName: resolvedExamName,
                examId: selectedExamID
            )
            // 记录此次成绩对应的满分
            // Record the full-score for this entry.
            grade.fullScore = container.fullScore(for: subjectScore.subject)
            return grade
        }
        container.addGrades(newGrades)
    }
}
