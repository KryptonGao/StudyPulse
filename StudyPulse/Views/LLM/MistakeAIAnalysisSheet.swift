//
//  MistakeAIAnalysisSheet.swift
//  StudyPulse
//
//  错题 AI 解析 sheet:基于错题内容调用 LLM,流式渲染 Markdown 分析结果。
//  - 未配置 LLM 时显示 "请先在设置中配置 LLM"
//  - 失败时显示错误信息 + 关闭按钮
//  - 成功后右下角 "Insert into Correct Solution" 按钮把内容塞回 caller 的绑定
//
//  Mistake AI analysis sheet: streams a Markdown analysis from the LLM
//  based on the mistake content.
//  - When LLM is not configured: shows "Configure LLM in Settings first".
//  - On failure: shows the error and a close button.
//  - On success: an "Insert into Correct Solution" button on the right
//    pushes the analysis back into the caller's binding.
//

import SwiftUI
import SwiftStreamingMarkdown

/// 错题 AI 解析 sheet。
/// 通过 `onInsert` 回调让 caller 决定如何把生成内容写回数据模型。
/// Mistake AI analysis sheet.
/// The `onInsert` callback lets the caller decide how to write the
/// generated content back into the data model.
struct MistakeAIAnalysisSheet: View {
    /// 学科
    /// Subject.
    let subject: String
    /// 错题标题
    /// Mistake title.
    let title: String
    /// 原题内容
    /// Original question content.
    let question: String
    /// 用户的错误解法
    /// User's wrong solution.
    let wrongSolution: String
    /// 标准正确解法
    /// Standard correct solution.
    let correctSolution: String
    /// 错因
    /// Error reason.
    let reason: String
    /// 用户点击"Insert into Correct Solution"时回调,内容是 LLM 生成的"正确思路"段
    /// Called when the user taps "Insert into Correct Solution" with the
    /// LLM-generated "correct approach" text.
    let onInsert: (String) -> Void
    /// 流式分析成功结束后回调,传入完整 LLM 输出(供"深入探讨" sheet 作为初始消息)
    /// Called after a successful stream with the full LLM output
    /// (used as the initial message by the "deep discussion" sheet).
    var onAnalysisComplete: ((String) -> Void)? = nil
    var onPatternDecision: ((MistakePatternUserState) -> Void)? = nil
    /// 用户点击"深入探讨"时回调,传入用于讨论的上下文(含原错题信息) + 上一次的 AI 输出
    /// Called when the user taps "Deep discussion", passing the discussion
    /// context (original mistake info) and the previous AI output.
    var onDiscuss: ((_ context: String, _ lastAnalysis: String) -> Void)? = nil

    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    /// 当前流式任务句柄(用于取消 / 重新生成)
    /// Handle of the in-flight stream task (for cancel / re-generate).
    @State private var streamTask: Task<Void, Never>? = nil
    /// 流式累积的 LLM 输出
    /// Streamed LLM output accumulated so far.
    @State private var streamedText: String = ""
    /// 错误信息(若有)
    /// Error message, if any.
    @State private var errorMessage: String? = nil
    /// 是否处于加载中(首字未到)
    /// Whether we are still loading (first token not yet received).
    @State private var isLoading: Bool = false
    @State private var patternResult: MistakePatternAIResult?
    @State private var selectedPattern: MistakePattern = .other

    var body: some View {
        NavigationStack {
            Group {
                if !container.envManager.llmConfig.isConfigured {
                    notConfiguredView
                } else if let errorMessage {
                    errorView(errorMessage)
                } else if streamedText.isEmpty && isLoading {
                    loadingView
                } else {
                    contentView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .llmDebugButton(caller: "MistakeAI")
            .cloudThinkingToolbar()
            .navigationTitle("AI Analysis".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close".localized()) {
                        streamTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !streamedText.isEmpty && errorMessage == nil {
                        // 深入探讨:在原错题上下文上与 AI 多轮对话
                        Button {
                            streamTask?.cancel()
                            onDiscuss?(buildDiscussionContext(), streamedText)
                        } label: {
                            Label("深入探讨".localized(), systemImage: "bubble.left.and.bubble.right.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold))
                        }
                        .tint(.teal)
                        Button("Insert into Correct".localized()) {
                            streamTask?.cancel()
                            onInsert(streamedText)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .onAppear { startAnalysis() }
            .onDisappear { streamTask?.cancel() }
        }
    }

    // MARK: - Subviews / 子视图

    private var notConfiguredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("LLM Not Configured".localized())
                .font(.headline)
            Text("Set Base URL, API Key and Model in Settings → LLM.".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink(destination: LLMSettingsView()) {
                Label("Open LLM Settings".localized(), systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("AI 解析失败".localized())
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry".localized()) {
                startAnalysis()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        AIWaitingView(
            title: "Analyzing...".localized(),
            messages: [
                "AI正在结合历史数据...".localized(),
                "AI正在提炼表达...".localized(),
                "正在解构错题的考查要点...".localized(),
                "正在诊断您的思维误区...".localized(),
                "正在撰写深度的正确解题思路...".localized(),
                "正在沉淀易错防坑指南...".localized()
            ],
            onCancel: {
                streamTask?.cancel()
                dismiss()
            }
        )
    }

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                summaryHeader
                Divider()
                if streamedText.isEmpty {
                    Text("Waiting for response...".localized())
                        .foregroundColor(.secondary)
                } else {
                    // 流式渲染:每个字符更新都会触发 onDelta,但 SwiftUI 的 .task(id:) 会在 text 变化时重新 parse
                    // 我们用一个内部 AsyncStream 把 streamedText 喂给 StreamedMarkdownView
                    MarkdownStreamedContent(text: streamedText)
                }
                if let patternResult, !patternResult.patternIDs.isEmpty {
                    patternDecisionView(patternResult)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func patternDecisionView(_ result: MistakePatternAIResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("mistake.ai.pattern.title".localized(), systemImage: "scope").font(.headline)
            Text(String(format: "mistake.ai.pattern.evidence".localized(), result.evidence)).font(.caption).foregroundStyle(.secondary)
            Picker("mistake.ai.pattern.picker".localized(), selection: $selectedPattern) {
                ForEach(MistakePattern.allCases, id: \.self) { pattern in
                    Text(pattern.displayName).tag(pattern)
                }
            }
            .pickerStyle(.menu)
            HStack {
                Button("mistake.ai.pattern.accept".localized()) { commit(.accepted(selectedPattern)) }.buttonStyle(.borderedProminent)
                Button("mistake.ai.pattern.ignore".localized()) { commit(.ignoredState) }.buttonStyle(.bordered)
                Button("mistake.ai.pattern.resolved".localized()) { commit(.resolvedState) }.buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func commit(_ state: MistakePatternUserState) {
        onPatternDecision?(state)
        patternResult = nil
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
            }
            HStack(spacing: 6) {
                if !subject.isEmpty {
                    Text(subject)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.blue.opacity(0.15)))
                        .foregroundColor(.blue)
                }
                if !question.isEmpty {
                    Text("\(question.count) chars".localized())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Stream / 流式

    private func startAnalysis() {
        streamTask?.cancel()
        streamedText = ""
        errorMessage = nil
        isLoading = true
        patternResult = nil
        let config = container.envManager.llmConfig
        let prompt = MistakeAnalysisLLM.makePrompt(
            subject: subject,
            title: title,
            question: question,
            wrongSolution: wrongSolution,
            correctSolution: correctSolution,
            reason: reason
        )
        streamTask = Task {
            do {
                _ = try await LLMClient.shared.stream(prompt: prompt, config: config, caller: "MistakeAI") { snapshot in
                    streamedText = snapshot
                }
                isLoading = false
                // 流式结束后,把完整输出交给 caller,便于"深入探讨" sheet 使用
                onAnalysisComplete?(streamedText)
                if let result = MistakeAnalysisLLM.parsePatternResult(from: streamedText), !result.patternIDs.isEmpty {
                    patternResult = result
                    selectedPattern = result.patternIDs[0]
                }
            } catch is CancellationError {
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = (error as? LLMError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// 构造"深入探讨" sheet 用的上下文(含错题元信息 + 上一次的 AI 解析)
    private func buildDiscussionContext() -> String {
        var lines: [String] = []
        if !subject.isEmpty { lines.append("学科:\(subject)") }
        if !title.isEmpty { lines.append("标题:\(title)") }
        if !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("--- 原题 ---")
            lines.append(question)
        }
        if !wrongSolution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("--- 错误解法 ---")
            lines.append(wrongSolution)
        }
        if !correctSolution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("--- 正确解法 ---")
            lines.append(correctSolution)
        }
        if !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("--- 错因 ---")
            lines.append(reason)
        }
        if !streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("--- 上一次 AI 解析(只读) ---")
            lines.append(streamedText)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Streamed Markdown Content

/// `StreamedMarkdownView` 内部已经实现了"流式 Markdown 重新 parse",但要求传入
/// `StreamedMarkdownSource`。这里用一个简单包装,直接用 `MarkdownView` 也能在
/// text 变化时重 parse(`StreamedMarkdownView` 的注释也提示:每个 value 是当前完整快照)。
///
/// 选用 `MarkdownView` + `task(id: text)`:SwiftUI 在 `text` 变化时会重新触发 task,
/// 与 `MarkdownView` 内置的 `task(id: text)` 一致,无需自己实现 `StreamedMarkdownSource`。
private struct MarkdownStreamedContent: View {
    let text: String

    var body: some View {
        // 使用与项目其它位置一致的 previewConfig + 单美元符号 LaTeX 归一化
        MarkdownView(text: text.normalisingSingleDollarMath(), config: .previewConfig)
    }
}
