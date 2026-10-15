//
//  ExamViewMode.swift
//  StudyPulse
//
//  待办 / 考试页的「列表 ⇄ 月历」视图模式(原 ExamView.swift 中唯一仍在使用的部分;
//  ExamView / ExamViewModel / ExamRowView 等已被 TodoView 取代并删除)。
//  List ⇄ calendar view mode for the Todo / Exam pages. This is the only part of the old
//  ExamView.swift still in use; ExamView / ExamViewModel / ExamRowView were superseded by
//  TodoView and removed.
//

import Foundation

// MARK: - 视图模式
// MARK: - View mode

/// 考试页面视图模式：列表 / 月历
/// Exam page view mode: list or calendar.
enum ExamViewMode: String, CaseIterable, Identifiable, Codable {
    case list
    case calendar

    var id: String { rawValue }

    /// 显示名称
    @MainActor var displayName: String {
        switch self {
        case .list: return "List".localized()
        case .calendar: return "Calendar".localized()
        }
    }

    /// 工具栏图标
    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .calendar: return "calendar"
        }
    }

    private static let userDefaultsKey = "examViewMode"

    /// 从 UserDefaults 加载，缺失或非法值时默认 list
    static func loadFromDefaults() -> ExamViewMode {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              let mode = ExamViewMode(rawValue: raw) else {
            return .list
        }
        return mode
    }

    /// 持久化到 UserDefaults
    func saveToDefaults() {
        UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
    }
}
