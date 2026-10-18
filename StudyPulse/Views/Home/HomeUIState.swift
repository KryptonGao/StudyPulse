//
//  HomeUIState.swift
//  StudyPulse
//
//  主页 UI 状态聚合:把 HomeView 之前散落的 8 个 @State
//  (renderPhase / showingFlashcards / 报告导出相关 6 个)打包成单个 struct,
//  减少 HomeView 的 @State 数量并明确这组状态的语义边界(仅主页 UI 临时状态,
//  与 HomeViewModel 的派生数据解耦)。
//
//  Home UI state aggregation: bundles the 8 previously scattered @State on HomeView
//  (renderPhase / showingFlashcards / 6 report-export-related) into a single struct,
//  reducing the @State count on HomeView and clarifying the semantic boundary
//  of this group (Home UI ephemeral state only, decoupled from HomeViewModel derived data).
//
//  - 业务派生数据(SRS / recent grades / upcoming exams / chart 选科)→ HomeViewModel
//  - 临时 UI 状态(模态/分阶段渲染/报告导出)→ HomeUIState
//  - 外部输入(tab 切换)→ @Binding selectedTab
//
//  - Derived business data (SRS / recent grades / upcoming exams / chart subject) → HomeViewModel
//  - Ephemeral UI state (modals / phased render / report export) → HomeUIState
//  - External input (tab switch) → @Binding selectedTab
//
//  Created for HomeView card extraction refactor (2026-07-05).
//

import Foundation
import SwiftUI

/// 主页 UI 状态聚合(纯 struct,放 @State 里使用)。
/// 不放任何派生业务数据,只承载"当前打开什么 modal / 报告导出进行到哪一步"。
/// Home UI state aggregation (plain struct, stored in @State).
/// Holds no derived business data, only "which modal is open / where the report export is".
struct HomeUIState {
    // MARK: - 分阶段渲染
    // MARK: - Phased Rendering

    /// 0 = 仅头部;1 = + 「现在」主卡与快捷坞;2 = 其余区块
    /// 0 = header only; 1 = + Now hero and dock; 2 = remaining zones.
    /// 用于首次进入页面时分 3 帧渲染,避免一次性构建所有复杂子视图。
    /// Used to render in 3 frames on first entry, avoiding building every complex sub-view in a single pass.
    var renderPhase: Int = 0

    // MARK: - 闪卡复习 fullScreenCover
    // MARK: - Flashcard Review fullScreenCover

    /// 是否显示闪卡复习全屏视图
    /// Whether to show the flashcard review full-screen view.
    var showingFlashcards: Bool = false

    /// 是否显示考场人格模拟器。放在 HomeView 根层，避免 LazyVStack 重建卡片时
    /// 一并重建正在答题的 fullScreenCover。
    var showingExamRoleSimulator: Bool = false

    /// 是否显示全屏 AI 模式 / Whether the full-screen AI Mode is presented.
    var showingAIMode: Bool = false

    /// 是否显示考试倒推模拟器。
    var showingExamReversePlanner: Bool = false

    // MARK: - 学习报告导出
    // MARK: - Study Report Export

    /// 是否显示 ReportOptionsSheet
    /// Whether to show the ReportOptionsSheet.
    var showingReportOptions: Bool = false

    /// 整页/单卡报告渲染进行中(用于 ProgressView 蒙层)
    /// Full-page / single-card report render in progress (drives the ProgressView overlay).
    var isRenderingReport: Bool = false

    /// 渲染完成的整页报告图片(走 ReportShareSheet)
    /// Rendered full-page report image (consumed by ReportShareSheet).
    var reportImage: UIImage?

    /// 渲染完成的单卡图片(走 ReportShareSheet,带标题)
    /// Rendered single-card image (consumed by ReportShareSheet, with a title).
    var singleCardImage: UIImage?

    /// 单卡分享时的本地化标题
    /// Localized title used when sharing a single card.
    var singleCardTitle: String = ""

    /// 是否显示分享 sheet
    /// Whether to show the share sheet.
    var showingShareSheet: Bool = false

    /// 报告渲染错误消息(nil = 无错误)
    /// Report render error message (nil = no error).
    var reportErrorMessage: String?
}

extension HomeUIState {
    /// 是否正在导出报告(用于禁用 toolbar 分享按钮)
    /// Whether a report export is in progress (used to disable the toolbar share button).
    var isExporting: Bool { isRenderingReport }

    /// 是否可以打开分享 sheet(必须有一张已渲染的图)
    /// Whether the share sheet can be opened (must have at least one rendered image).
    var canShare: Bool { reportImage != nil || singleCardImage != nil }
}
