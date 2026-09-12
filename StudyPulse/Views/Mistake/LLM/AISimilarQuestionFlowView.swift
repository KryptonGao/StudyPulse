//
//  AISimilarQuestionFlowView.swift
//  StudyPulse
//
//  AI 变式题 flow:出同类题 → 选手写/打字作答 → 判分 → 错题入库。
//  AI "similar question" flow: generate a similar problem → accept a
//  hand-written / typed answer → grade → optionally save the failed
//  answer as a new mistake.
//

import SwiftUI
import PencilKit
import SwiftStreamingMarkdown

/// LLM 一次返回的变式题 + 标准解法对。
/// One "similar question + standard solution" pair returned by the LLM.
struct SimilarQuestionResult: Codable {
    /// 题目文本
    /// Question text.
    let question: String
    /// 标准解法
    /// Standard solution.
    let correctSolution: String
}

/// 答题方式:手写(PencilKit)或打字(Markdown)。
/// Answer mode: hand-written (PencilKit) or typed (Markdown).
private enum AnswerMode: String, CaseIterable, Identifiable {
    case typing = "Typing"
    case handwriting = "Handwriting"

    var id: String { rawValue }

    /// 本地化标题
    /// Localized title.
    var title: String {
        switch self {
        case .typing: return "Markdown 作答".localized()
        case .handwriting: return "Handwriting".localized()
        }
    }

    /// SF Symbol 图标
    /// SF Symbol for the mode.
    var systemImage: String {
        switch self {
        case .typing: return "keyboard"
        case .handwriting: return "pencil.tip"
        }
    }
}

/// AI 变式题 flow(从错题详情 → "同类题" 入口打开)。
/// "Generate a similar problem" flow (opened from a mistake's
/// "similar question" entry).
struct AISimilarQuestionFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RepositoryContainer.self) private var container

    /// 用作 generation 种子的原错题
    /// Original mistake used as the generation seed.
    let originalMistake: MistakeNote

    /// 是否正在等待 LLM 返回首字
    /// Whether we are still waiting for the first LLM token.
    @State private var isLoading = true
    /// LLM 错误信息
    /// LLM error message.
    @State private var errorMessage: String? = nil

    /// LLM 生成的同类题文本
    /// LLM-generated similar-question text.
    @State private var generatedQuestion: String = ""
    /// LLM 给出的标准解法
    /// LLM-provided standard solution.
    @State private var generatedSolution: String = ""

    // 模式选择 / Mode selection
    /// 当前作答模式
    /// Current answer mode.
    @State private var answerMode: AnswerMode = .typing
    /// 打字模式的作答文本
    /// Typed answer text.
    @State private var typedAnswer: String = ""
    /// 是否显示正解/解析区
    /// Whether the "correct solution" panel is shown.
    @State private var showingSolution = false
    /// 手写模式的 PencilKit 画板数据
    /// PencilKit drawing data in hand-written mode.
    @State private var drawing = PKDrawing()

    // AI 判分状态 / AI grading state
    /// 是否正在判分
    /// Whether grading is in flight.
    @State private var isGrading = false
    /// 判分错误
    /// Grading error message.
    @State private var gradingError: String? = nil
    /// 判分结构化结果
    /// Grading structured result.
    @State private var gradingResult: SimilarQuestionGradingLLM.GradingResult? = nil
    /// 流式判分累积的原始文本
    /// Streamed raw grading text accumulated so far.
    @State private var gradingStreamedText: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    AIWaitingView(
                        title: "AI 正在构思变式题...".localized(),
                        messages: [
                            "AI正在结合历史数据...".localized(),
                            "AI正在提炼表达...".localized(),
                            "正在分析您的薄弱考点...".localized(),
                            "正在为您量身定制变式训练...".localized(),
                            "正在构建学术难度模型...".localized()
                        ],
                        onCancel: { dismiss() }
                    )
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Retry".localized()) {
                            generate()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    quizContent
                }
            }
            .navigationTitle("AI 变式题".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized()) { dismiss() }
                }
            }
            .cloudThinkingToolbar()
        }
        .onAppear {
            if generatedQuestion.isEmpty {
                generate()
            }
        }
    }

    @ViewBuilder
    private var quizContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 题目区
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "q.circle.fill")
                            .foregroundColor(.blue)
                        Text("Question".localized())
                            .font(.headline)
                    }
                    MarkdownView(text: generatedQuestion.normalisingSingleDollarMath(), config: .previewConfig)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                // 答题/草稿区
                VStack(alignment: .leading, spacing: 12) {
                // 头部:图标 + 标题 + 作答模式分段控件
                // Header: icon + title + answer-mode segmented control.
                HStack {
                    Image(systemName: answerMode.systemImage)
                        .foregroundColor(.orange)
                    Text("Draft / Answer".localized())
                        .font(.headline)
                    Spacer()
                    // 作答方式切换
                    // Answer-mode switcher.
                    Picker("Mode", selection: $answerMode) {
                        ForEach(AnswerMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                // 根据模式渲染手写 / 打字
                // Render handwriting / typing based on the mode.
                switch answerMode {
                case .handwriting:
                    handwritingCanvas
                case .typing:
                    typingEditor
                }
            }
            .padding(.horizontal)

            // 判分结果区(只在打字模式下展示;手写模式走"自评分"逻辑)
            // Grading result region (only in typing mode; handwriting uses
            // a self-grade flow instead).
            if answerMode == .typing, let result = gradingResult {
                gradingResultSection(result)
                    .padding(.horizontal)
            } else if answerMode == .typing, isGrading {
                gradingLoadingSection
                    .padding(.horizontal)
            } else if answerMode == .typing, let gradingError = gradingError {
                gradingErrorSection(gradingError)
                    .padding(.horizontal)
            }

            // 解析区:用户主动展开时,显示正解 + "Done / Save to Mistakes" 按钮
            // Solution region: when expanded by the user, shows the
            // correct solution plus "Done" / "Save to Mistakes" buttons.
            if showingSolution {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            Text("Correct Solution".localized())
                                .font(.headline)
                        }
                        MarkdownView(text: generatedSolution.normalisingSingleDollarMath(), config: .previewConfig)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)

                        // 底部操作
                        HStack(spacing: 16) {
                            Button {
                                updateOriginalMastery()
                                dismiss()
                            } label: {
                                Text("Done".localized())
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                saveAsNewMistake()
                                updateOriginalMastery()
                                dismiss()
                            } label: {
                                Text("Save to Mistakes".localized())
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 16)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Answer Input / 作答输入

    @ViewBuilder
    private var handwritingCanvas: some View {
        FlashcardHandwritingCanvasView(
            drawing: $drawing,
            hasContent: { !drawing.bounds.isEmpty },
            onSubmit: { _ in showingSolution = true },
            onClear: { drawing = PKDrawing() },
            minHeight: 300,
            labels: FlashcardHandwritingCanvasView.Labels(
                header: "草稿区".localized(),
                hint: "双指滑动/缩放".localized(),
                clear: "Clear".localized(),
                submit: "Check Solution".localized()
            )
        )
    }

    @ViewBuilder
    private var typingEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkdownEditorView(
                text: $typedAnswer,
                placeholder: "Supports Markdown, math $...$ and chemistry $\\ce{...}$"
            )
            .frame(minHeight: 360)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            HStack(spacing: 12) {
                Button {
                    typedAnswer = ""
                    gradingResult = nil
                    gradingError = nil
                    gradingStreamedText = ""
                } label: {
                    Label("Clear".localized(), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && gradingResult == nil)

                Button {
                    if container.envManager.llmConfig.isConfigured {
                        startGrading()
                    } else {
                        // 未配置 LLM → 退化为"查看正解"
                        showingSolution = true
                    }
                } label: {
                    if container.envManager.llmConfig.isConfigured {
                        Label("AI 判分".localized(), systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Check Solution".localized(), systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(container.envManager.llmConfig.isConfigured ? .teal : .blue)
                .disabled(typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGrading)
            }
        }
    }

    // MARK: - Grading UI / 判分 UI

    @ViewBuilder
    private func gradingResultSection(_ result: SimilarQuestionGradingLLM.GradingResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: result.isCorrect ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(result.isCorrect ? .green : .orange)
                Text("AI 判分".localized())
                    .font(.headline)
                Spacer()
                Text("\(result.score) / 100")
                    .font(.title3.weight(.bold))
                    .foregroundColor(result.isCorrect ? .green : .orange)
            }

            // 详细 Markdown 反馈
            if !result.detail.isEmpty {
                MarkdownView(text: result.detail.normalisingSingleDollarMath(), config: .previewConfig)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            }

            HStack(spacing: 12) {
                Button {
                    gradingResult = nil
                    gradingStreamedText = ""
                } label: {
                    Label("Retry".localized(), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showingSolution = true
                } label: {
                    Label("View Solution".localized(), systemImage: "lightbulb")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var gradingLoadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.teal)
                Text("AI 判分中...".localized())
                    .font(.headline)
                Spacer()
                ProgressView()
            }
            if !gradingStreamedText.isEmpty {
                MarkdownView(text: gradingStreamedText.normalisingSingleDollarMath(), config: .previewConfig)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            }
        }
    }

    @ViewBuilder
    private func gradingErrorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("判分失败".localized())
                    .font(.headline)
            }
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                Button {
                    gradingError = nil
                    startGrading()
                } label: {
                    Label("Retry".localized(), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showingSolution = true
                } label: {
                    Label("View Solution".localized(), systemImage: "lightbulb")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Generate / 出题

    /// 调 LLM 出同类题,响应可能是 JSON `[{question, correctSolution}]`
    /// 或纯文本,这里统一做一次规范化解析
    /// Call the LLM to generate a similar question. The response may be
    /// JSON (`[{question, correctSolution}]`) or plain text; both are
    /// handled by the normalizer below.
    private func generate() {
        isLoading = true
        errorMessage = nil

        Task {
            let prompt = SimilarQuestionLLM.makePrompt(
                subject: originalMistake.subject,
                title: originalMistake.title,
                originalQuestion: originalMistake.originalQuestion,
                correctSolution: originalMistake.correctSolution,
                errorReason: originalMistake.errorReason
            )

            do {
                let jsonString = try await LLMClient.shared.complete(
                    prompt: prompt,
                    config: container.envManager.llmConfig,
                    caller: "AISimilarQuestion"
                )

                if let data = jsonString.data(using: .utf8),
                   let result = try? JSONDecoder().decode(SimilarQuestionResult.self, from: data) {
                    self.generatedQuestion = result.question
                    self.generatedSolution = result.correctSolution
                } else {
                    // Fallback string matching if JSON parsing fails
                    self.generatedQuestion = jsonString
                    self.generatedSolution = ""
                }
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Grading / 判分

    private func startGrading() {
        gradingResult = nil
        gradingError = nil
        gradingStreamedText = ""
        isGrading = true
        let prompt = SimilarQuestionGradingLLM.makePrompt(
            subject: originalMistake.subject,
            question: generatedQuestion,
            correctSolution: generatedSolution,
            userAnswer: typedAnswer
        )
        let config = container.envManager.llmConfig
        Task { @MainActor in
            do {
                let streamed = try await LLMClient.shared.stream(
                    prompt: prompt,
                    config: config,
                    caller: "AISimilarGrading"
                ) { snapshot in
                    gradingStreamedText = snapshot
                }
                isGrading = false
                if let parsed = SimilarQuestionGradingLLM.parse(streamed) {
                    gradingResult = parsed
                } else {
                    // 解析失败:把流式原样作为 detail 给出,让用户至少能看到反馈
                    gradingError = "无法解析评分,请重试".localized()
                }
            } catch is CancellationError {
                isGrading = false
            } catch {
                isGrading = false
                gradingError = (error as? LLMError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Persist / 持久化

    /// 把这次变式题的结果保存为新的错题(仅在用户主动 "Save to Mistakes" 时调用)
    /// Save the current similar-question result as a new mistake (only
    /// when the user explicitly taps "Save to Mistakes").
    private func saveAsNewMistake() {
        let newMistake = MistakeNote(
            title: "【AI变式】" + originalMistake.title,
            subject: originalMistake.subject,
            originalQuestion: generatedQuestion,
            source: "AI Generated",
            date: Date(),
            errorReason: "",
            wrongSolution: "",
            correctSolution: generatedSolution,
            reviewState: .initial(),
            phaseId: originalMistake.phaseId,
            tags: ["AI变式题"]
        )
        container.addMistake(newMistake)
    }

    private func updateOriginalMastery() {
        // 轻微增加原题掌握度作为复习奖励
        var updated = originalMistake
        let newEntry = MasteryHistoryEntry(score: min(1.0, updated.masteryScore + 0.1), quality: 4)
        updated.masteryHistory.append(newEntry)
        updated.masteryScore = newEntry.score
        updated.exposureCount += 1
        container.mistakeRepo.update(updated)
    }
}
