//
//  FlashcardStudyView.swift
//  StudyPulse
//
//  全屏闪卡复习模式：Anki 风格翻牌 + 4 档自评
//  Full-screen flashcard review mode: Anki-style flip + 4-bucket self-rating.
//
//  Created by Chenkai Gao on 2026/6/27.
//

import SwiftUI
import PencilKit
import os

// MARK: - Session Stats
// MARK: - Session stats

/// 一次复习 session 的统计
/// Per-session review statistics.
struct FlashcardSessionStats: Equatable {
    var reviewed: Int = 0
    var again: Int = 0
    var hard: Int = 0
    var good: Int = 0
    var easy: Int = 0
    var earlyContrastReviewed: Int = 0
    var interleavedPairs: [String] = []
    var startTime: Date = Date()
    var endTime: Date? = nil

    var totalRatings: Int { again + hard + good + easy }

    var durationString: String {
        let end = endTime ?? Date()
        let seconds = Int(end.timeIntervalSince(startTime))
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 {
            return String(format: "%d min %d sec".localized(), m, s)
        }
        return String(format: "%d sec".localized(), s)
    }

    mutating func record(_ quality: ReviewQuality) {
        reviewed += 1
        switch quality {
        case .again: again += 1
        case .hard:  hard += 1
        case .good:  good += 1
        case .easy:  easy += 1
        }
    }

    mutating func recordEarlyContrast(_ pair: ConceptInterference) {
        earlyContrastReviewed += 1
        if !interleavedPairs.contains(pair.displayName) {
            interleavedPairs.append(pair.displayName)
        }
    }
}

// MARK: - Flashcard Filter
// MARK: - Flashcard filter

/// FlashcardStudyView 的过滤模式
/// Filter mode for FlashcardStudyView.
enum FlashcardFilter: Equatable {
    /// 默认：复习所有 due 错题
    case dueQueue
    /// 临时复习单张（不计 SM-2，仅标记）
    case single(MistakeNote)
    /// 仅复习打了某 tag 的 due 错题
    case tag(String)
    /// 15 分钟补救任务：按给定卡片复习，走正常 SM-2
    case remediation([MistakeNote])

    static func == (lhs: FlashcardFilter, rhs: FlashcardFilter) -> Bool {
        switch (lhs, rhs) {
        case (.dueQueue, .dueQueue):
            return true
        case (.single(let a), .single(let b)):
            return a.id == b.id
        case (.tag(let a), .tag(let b)):
            return a == b
        case (.remediation(let a), .remediation(let b)):
            return a.map(\.id) == b.map(\.id)
        default:
            return false
        }
    }

    /// 简短标签（顶部状态条 / Debug 展示用）
    var shortLabel: String {
        switch self {
        case .dueQueue:     return "Due".localized()
        case .single:       return "Single".localized()
        case .tag(let t):   return "#\(t)"
        case .remediation:  return "memory.climate.remediation.short".localized()
        }
    }

    var isSingleMode: Bool {
        if case .single = self { return true }
        return false
    }
}

// MARK: - Flashcard Study View
// MARK: - Flashcard study view

/// 全屏闪卡复习入口
/// Full-screen flashcard study entry.
struct FlashcardStudyView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: FlashcardStudyViewModel

    init(container: RepositoryContainer, filter: FlashcardFilter = .dueQueue, handwritingEnabled: Bool = false) {
        self._viewModel = State(initialValue: FlashcardStudyViewModel(container: container, filter: filter, handwritingEnabled: handwritingEnabled))
    }

    var body: some View {
        ZStack {
            // 背景渐变
            // Background gradient.
            LinearGradient(
                colors: [Color.purple.opacity(0.18), Color.blue.opacity(0.12), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if viewModel.showingSummary {
                FlashcardSessionSummaryView(stats: viewModel.stats) {
                    dismiss()
                }
            } else if viewModel.queue.isEmpty && viewModel.reinsertQueue.isEmpty {
                emptyState
            } else if let mistake = viewModel.currentMistake {
                reviewContent(mistake: mistake)
            } else {
                FlashcardSessionSummaryView(stats: viewModel.stats) {
                    dismiss()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbar }
        .overlay(alignment: .topTrailing) { calculatorFAB }
        .overlay(alignment: .topTrailing) {
            if viewModel.showingCalculator {
                FlashcardCalculatorView {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.showingCalculator = false
                    }
                }
                .padding(.top, 60)
                .padding(.trailing, 12)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.7, anchor: .topTrailing).combined(with: .opacity),
                    removal: .scale(scale: 0.7, anchor: .topTrailing).combined(with: .opacity)
                ))
                .zIndex(10)
            }
        }
        .onAppear { viewModel.loadQueue() }
        .alert("Handwriting Required".localized(), isPresented: $viewModel.showHandwritingRequiredAlert) {
            Button("OK".localized(), role: .cancel) { }
        } message: {
            Text("Please write and submit your answer first".localized())
        }
    }

    /// 浮于右上角的「计算器」开关按钮
    /// Floating top-right calculator toggle.
    private var calculatorFAB: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                viewModel.showingCalculator.toggle()
            }
        } label: {
            Image(systemName: "function")
                .font(.subheadline.weight(.bold))
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(LinearGradient(
                        colors: viewModel.showingCalculator
                            ? [.purple, .blue]
                            : [Color(.tertiarySystemBackground), Color(.secondarySystemBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                )
                .foregroundStyle(viewModel.showingCalculator ? .white : .primary)
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        }
        .accessibilityLabel("Calculator".localized())
        .padding(.top, 8)
        .padding(.trailing, 16)
    }

    // MARK: - Sub-views
    // MARK: - Sub-views

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No Mistakes Due".localized())
                .font(.title2.weight(.semibold))
            Text("Add mistakes to your review queue to start spaced repetition".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                dismiss()
            } label: {
                Text("Close".localized())
                    .frame(maxWidth: 200)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 12)
        }
        .frame(maxWidth: 500)
    }

    @ViewBuilder
    private func reviewContent(mistake: MistakeNote) -> some View {
        VStack(spacing: 0) {
            // 顶部进度条
            VStack(spacing: 8) {
                HStack {
                    Text(String(format: "%d / %d".localized(), viewModel.stats.reviewed, viewModel.totalToReview))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "Time: %@".localized(), viewModel.stats.durationString))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .tint(container.envManager.effectiveAccentColor)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            // 主内容:ScrollView 内,卡片 + (手写时)画布
            ScrollView {
                VStack(spacing: 16) {
                    if let pair = viewModel.currentQueueItem?.interference {
                        Label(
                            String(format: "memory.climate.interleavedBadge".localized(), pair.displayName),
                            systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.purple.opacity(0.12), in: Capsule())
                        .accessibilityHint("memory.climate.earlyDueUnchanged".localized())
                    }

                    // 主卡片
                    FlashcardCardView(mistake: mistake, isFlipped: $viewModel.isFlipped)
                        .frame(maxWidth: 720)
                        .overlay(alignment: .topTrailing) {
                            // 反面时叠加手写笔迹(右上角小图)
                            if viewModel.isFlipped,
                               let png = viewModel.sessionHandwriting[mistake.id],
                               let img = UIImage(data: png) {
                                handwritingOverlay(img: img)
                            }
                        }

                    // 手写画布(仅当启用手写且未翻面时显示)
                    if viewModel.handwritingEnabled && !viewModel.isFlipped {
                        FlashcardHandwritingCanvasView(
                            drawing: $viewModel.currentDrawing,
                            hasContent: { !viewModel.currentDrawing.strokes.isEmpty },
                            onSubmit: { pngData in
                                viewModel.submitHandwriting(pngData: pngData)
                            },
                            onClear: {
                                viewModel.clearHandwriting()
                            }
                        )
                        .frame(maxWidth: 720)
                        .padding(.horizontal, 20)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                    }
                }
                .padding(.vertical, 16)
            }

            // 底部操作区
            if viewModel.isFlipped {
                ReviewActionsRow { quality in
                    viewModel.handleRating(quality)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            } else {
                Button {
                    // 启用手写但未提交:拦截
                    if viewModel.handwritingEnabled && !viewModel.hasSubmittedCurrent {
                        viewModel.showHandwritingRequiredAlert = true
                        return
                    }
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                        viewModel.isFlipped = true
                    }
                } label: {
                    Label(
                        (viewModel.handwritingEnabled && viewModel.hasSubmittedCurrent)
                            ? "Show Answer".localized()
                            : (viewModel.handwritingEnabled
                                ? "Submit & Show Answer".localized()
                                : "Show Answer".localized()),
                        systemImage: "eye.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: 400)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }

    /// 反面叠加的手写笔迹缩略图
    @ViewBuilder
    private func handwritingOverlay(img: UIImage) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "pencil.tip")
                    .font(.caption2)
                Text("Your Handwriting".localized())
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.purple.opacity(0.7))
            )

            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 180, maxHeight: 110)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.purple.opacity(0.5), lineWidth: 1)
                )
                .opacity(0.92)
        }
        .padding(12)
        .allowsHitTesting(false)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                viewModel.finishSession()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("Close".localized())
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.toggleHandwriting()
                }
            } label: {
                Image(systemName: viewModel.handwritingEnabled
                      ? "pencil.tip.crop.circle.badge.minus"
                      : "pencil.tip.crop.circle.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(viewModel.handwritingEnabled ? Color.purple : .secondary)
            }
            .accessibilityLabel(viewModel.handwritingEnabled
                                ? "Handwriting Off".localized()
                                : "Handwriting On".localized())
        }
    }
}

// MARK: - Review Actions Row

/// 底部 4 档自评按钮行
struct ReviewActionsRow: View {
    let onRate: (ReviewQuality) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("How well did you remember?".localized())
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(ReviewQuality.allCases) { quality in
                    Button {
                        onRate(quality)
                    } label: {
                        VStack(spacing: 4) {
                            Text(quality.shortTitle)
                                .font(.subheadline.weight(.bold))
                            Text(quality.description)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(quality.color.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(quality.color.opacity(0.45), lineWidth: 1)
                        )
                        .foregroundStyle(quality.color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 720)
    }
}
