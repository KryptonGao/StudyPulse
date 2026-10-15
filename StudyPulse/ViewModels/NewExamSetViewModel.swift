//
//  NewExamSetViewModel.swift
//  StudyPulse
//
//  Created by Antigravity on 2026/7/12.
//
//  新增考试 ViewModel。负责单科 / 综合考试表单 + 时间段编辑 + 日历同步。
//  New-exam VM. Single/comprehensive exam form, per-subject time slots,
//  Calendar sync.
//

import Foundation
import SwiftUI

/// 综合考试中某科目的时间段(可被多次编辑)
/// Per-subject time slot inside a comprehensive exam (editable).
struct SubjectTimeEntry: Identifiable, Equatable {
    let id: UUID
    let subject: String
    var startTime: Date
    var endTime: Date

    /// 默认 08:00-10:00;可传 startTime / endTime 覆盖
    /// Defaults to 08:00–10:00; pass startTime / endTime to override.
    init(id: UUID = UUID(), subject: String, startTime: Date? = nil, endTime: Date? = nil) {
        self.id = id
        self.subject = subject
        let defaultStart = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        let defaultEnd = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
        self.startTime = startTime ?? defaultStart
        self.endTime = endTime ?? defaultEnd
    }
}

@MainActor
@Observable
final class NewExamSetViewModel {
    // MARK: - 依赖项 / Dependencies
    private let container: RepositoryContainer

    // MARK: - 表单状态 / Form state
    var name = ""
    var selectedSubject = "Mathematics"
    var isComprehensiveExam = false
    /// 考试开始日期(综合考试时作为"考试周"首日)
    /// Exam start date (or first day of an "exam week").
    var examDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    /// 综合考试结束日期(单科时无意义) / End date (unused for single-subject).
    var examEndDate: Date = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    var importance = 3
    var masteryDegree = 50
    var examNote = ""

    // MARK: - 日历 & 弹窗 / Calendar & alert state
    /// 是否同时把这次考试加到系统日历 / Also add to system Calendar?
    var addToCalendarToggle = true
    var showingCalendarAlert = false
    var calendarAlertMessage = ""

    // MARK: - 科目选择 / Subject selection
    var selectedSingleSubject = ""
    var selectedMultipleSubjects: [String] = []
    var subjectTimeEntries: [SubjectTimeEntry] = []

    // MARK: - 初始化 / Initialization
    /// 默认选中第一个可用科目 / Pre-selects the first available subject.
    init(container: RepositoryContainer) {
        self.container = container
        if let first = availableSubjects.first {
            selectedSingleSubject = first
        }
    }

    // MARK: - 计算属性 / Computed properties
    /// 启用的且非 "GROUP:" 聚合的 `Subject` 列表
    /// Enabled, non-`GROUP:` `Subject` records.
    var enabledSubjects: [Subject] {
        container.subjectRepo.subjects.filter {
            $0.enabled && !$0.name.starts(with: "GROUP:")
        }
    }

    /// 动态列表高度(每行 80pt) / Dynamic list height (80pt per row).
    var dynamicListHeight: CGFloat {
        CGFloat(enabledSubjects.count * 80)
    }

    /// 启用的科目名列表(不去重 GROUP) / Enabled subject names.
    var availableSubjectNames: [String] {
        enabledSubjects.map { $0.name }
    }

    /// 启用的科目名列表(包含 GROUP) / Enabled names (includes GROUP).
    var availableSubjects: [String] {
        container.subjectRepo.subjects.filter { $0.enabled }.map { $0.name }
    }

    /// 是否禁用"保存"按钮 / Whether the save button is disabled.
    var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty ||
        (isComprehensiveExam && examDate > examEndDate) ||
        (!isComprehensiveExam && selectedSingleSubject.isEmpty) ||
        (isComprehensiveExam && selectedMultipleSubjects.isEmpty)
    }

    // MARK: - 操作 / Actions
    /// 让 `subjectTimeEntries` 与当前选中的科目集合对齐
    /// Reconcile `subjectTimeEntries` with the current subject selection.
    func syncSubjectTimeEntries() {
        let selected = isComprehensiveExam ? selectedMultipleSubjects : [selectedSingleSubject].filter { !$0.isEmpty }

        // 1. 更新已有条目:把"时分"保持,把"年月日"换成新 examDate
        // 1. Update existing entries: keep "hour:minute", swap "Y-M-D" to new examDate.
        for index in subjectTimeEntries.indices {
            guard selected.contains(subjectTimeEntries[index].subject) else { continue }
            let oldStart = subjectTimeEntries[index].startTime
            let oldEnd   = subjectTimeEntries[index].endTime

            let compsStart = Calendar.current.dateComponents([.hour, .minute], from: oldStart)
            let compsEnd   = Calendar.current.dateComponents([.hour, .minute], from: oldEnd)

            let newStart = Calendar.current.date(bySettingHour: compsStart.hour ?? 8,
                                                  minute: compsStart.minute ?? 0,
                                                  second: 0,
                                                  of: examDate) ?? examDate
            var newEnd   = Calendar.current.date(bySettingHour: compsEnd.hour ?? 10,
                                                  minute: compsEnd.minute ?? 0,
                                                  second: 0,
                                                  of: examDate) ?? examDate
            // 结束 ≤ 开始 → 自动顺延 1 小时 / Auto-extend by 1 hour when invalid.
            if newEnd <= newStart {
                newEnd = Calendar.current.date(byAdding: .hour, value: 1, to: newStart) ?? newStart
            }
            subjectTimeEntries[index].startTime = newStart
            subjectTimeEntries[index].endTime   = newEnd
        }

        // 2. 移除不再选中的条目 / 2. Remove entries no longer selected.
        subjectTimeEntries.removeAll { !selected.contains($0.subject) }

        // 3. 给新选中的科目补默认时间段(08:00-10:00)
        // 3. Add default 08:00–10:00 slots for newly selected subjects.
        let existingSubjects = subjectTimeEntries.map { $0.subject }
        for sub in selected where !existingSubjects.contains(sub) {
            let defaultStart = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: examDate) ?? examDate
            let defaultEnd   = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: examDate) ?? examDate
            subjectTimeEntries.append(SubjectTimeEntry(subject: sub, startTime: defaultStart, endTime: defaultEnd))
        }
    }

    /// 保存考试:创建 Exam / comprehensiveExam,可选择地写入系统日历
    /// Persist the exam; optionally write to system Calendar.
    func saveExam() async -> Bool {
        guard !name.isEmpty else { return false }

        // 安排备考通知 / Schedule exam-prep notifications.
        ExamPrepareNotifications.shared.scheduleNotifications(for: name, date: examDate)

        if isComprehensiveExam {
            var timeSlots: [String: ExamTimeSlot] = [:]
            for entry in subjectTimeEntries {
                timeSlots[entry.subject] = ExamTimeSlot(startTime: entry.startTime, endTime: entry.endTime)
            }

            let newCompExam = comprehensiveExam(
                name: name,
                date: examDate,
                importance: importance,
                subject: selectedMultipleSubjects,
                examName: name,
                masteryDegree: masteryDegree,
                examEndDate: examEndDate,
                subjectTimeSlots: addToCalendarToggle ? timeSlots : nil
            )
            container.addExams(single: [], comprehensive: [newCompExam])
            Haptics.success()

            if addToCalendarToggle {
                do {
                    for entry in subjectTimeEntries {
                        _ = try await CalendarManager.shared.addExamToCalendar(
                            examName: name,
                            subject: entry.subject,
                            examDate: examDate,
                            startTime: entry.startTime,
                            endTime: entry.endTime,
                            note: examNote.isEmpty ? nil : examNote
                        )
                    }
                    calendarAlertMessage = "Successfully added to calendar!".localized()
                    showingCalendarAlert = true
                } catch {
                    calendarAlertMessage = error.localizedDescription
                    showingCalendarAlert = true
                }
            }

        } else {
            guard !selectedSingleSubject.isEmpty else { return false }

            var timeSlot: ExamTimeSlot? = nil
            if addToCalendarToggle, let entry = subjectTimeEntries.first {
                // 单科时把"时分"投影到 examDate 的"年月日"
                // For single-subject, project "hour:minute" onto "Y-M-D" of examDate.
                let combinedStart = Calendar.current.date(
                    bySettingHour: Calendar.current.component(.hour, from: entry.startTime),
                    minute: Calendar.current.component(.minute, from: entry.startTime),
                    second: 0,
                    of: examDate
                ) ?? examDate
                let combinedEnd = Calendar.current.date(
                    bySettingHour: Calendar.current.component(.hour, from: entry.endTime),
                    minute: Calendar.current.component(.minute, from: entry.endTime),
                    second: 0,
                    of: examDate
                ) ?? examDate
                timeSlot = ExamTimeSlot(startTime: combinedStart, endTime: combinedEnd)
            }

            let newExam = Exam(
                name: name,
                date: examDate,
                importance: importance,
                subject: selectedSingleSubject,
                examName: name,
                masteryDegree: masteryDegree,
                timeSlot: timeSlot
            )
            container.addExams(single: [newExam], comprehensive: [])
            Haptics.success()

            if addToCalendarToggle, let slot = timeSlot {
                do {
                    _ = try await CalendarManager.shared.addExamToCalendar(
                        examName: name,
                        subject: selectedSingleSubject,
                        examDate: examDate,
                        startTime: slot.startTime,
                        endTime: slot.endTime,
                        note: examNote.isEmpty ? nil : examNote
                    )
                    calendarAlertMessage = "Successfully added to calendar!".localized()
                    showingCalendarAlert = true
                } catch {
                    calendarAlertMessage = error.localizedDescription
                    showingCalendarAlert = true
                }
            }
        }
        return !showingCalendarAlert
    }
}
