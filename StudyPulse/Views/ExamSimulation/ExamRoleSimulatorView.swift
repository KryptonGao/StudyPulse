import SwiftUI
import SwiftStreamingMarkdown

struct ExamRoleSimulatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: ExamSimulationViewModel
    @State private var selectedSubject = ""
    @State private var topic = ""
    @State private var showingExitConfirmation = false
    @State private var showingSubmitConfirmation = false

    init(container: RepositoryContainer) {
        _viewModel = State(initialValue: ExamSimulationViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .landing:
                    landingView
                case .generating:
                    processingView(
                        title: "正在生成模拟试卷…".localized(),
                        detail: "AI 正在准备 10 道题，这通常需要 15–30 秒。".localized()
                    )
                case .answering:
                    answeringView
                case .processing:
                    processingView(
                        title: "正在分析答题轨迹…".localized(),
                        detail: "AI 正在阅卷并识别本次可改变的考场模式。".localized()
                    )
                case .result:
                    if let simulation = viewModel.simulation {
                        ExamSimulationResultView(
                            simulation: simulation,
                            validAnalyzedCount: viewModel.validAnalyzedCount,
                            onRetry: { await viewModel.retryAnalysis() },
                            onNew: { viewModel.returnToLanding() }
                        )
                    }
                }
            }
            .navigationTitle("考场人格模拟器".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.state != .generating && viewModel.state != .processing {
                        Button("关闭".localized()) {
                            if viewModel.state == .answering {
                                showingExitConfirmation = true
                            } else {
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if selectedSubject.isEmpty {
                selectedSubject = viewModel.subjects.first?.name ?? ""
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let now = Date()
                if viewModel.tick(now: now) {
                    await viewModel.submit(timedOut: true, now: now)
                }
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active, viewModel.tick() {
                Task { await viewModel.submit(timedOut: true) }
            }
        }
        .alert("退出本次模拟？".localized(), isPresented: $showingExitConfirmation) {
            Button("取消".localized(), role: .cancel) {}
            Button("退出模拟".localized(), role: .destructive) {
                viewModel.abandon()
            }
        } message: {
            Text("本次未完成的模拟会标记为已退出，不会用于稳定模式判断。".localized())
        }
        .alert("提交模拟试卷？".localized(), isPresented: $showingSubmitConfirmation) {
            Button("取消".localized(), role: .cancel) {}
            Button("提交".localized()) {
                Task { await viewModel.submit(timedOut: false) }
            }
        } message: {
            Text("未作答题目将按空白答案参与阅卷。".localized())
        }
        .alert("提示".localized(), isPresented: Binding(
            get: { viewModel.errorMessage != nil && viewModel.state != .result },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("好".localized()) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var landingView: some View {
        ScrollView {
            VStack(spacing: DesignToken.Spacing.large) {
                VStack(spacing: DesignToken.Spacing.medium) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .scaledFont(size: 52)
                        .foregroundStyle(.purple)
                    Text("它观察你如何分配时间、跳题和修改答案，不判断你的性格。".localized())
                        .font(DesignToken.Font.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, DesignToken.Spacing.large)

                VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                    Label("20 分钟 · 10 道题".localized(), systemImage: "timer")
                        .font(DesignToken.Font.titleSmall)
                    Picker("选择学科".localized(), selection: $selectedSubject) {
                        ForEach(viewModel.subjects) { subject in
                            Text(subject.displayName).tag(subject.name)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("可选：指定章节或知识点".localized(), text: $topic, axis: .vertical)
                        .textFieldStyle(.roundedBorder)

                    if viewModel.isLLMConfigured {
                        Button {
                            Task {
                                await viewModel.startNewSimulation(
                                    subject: selectedSubject,
                                    topic: topic
                                )
                            }
                        } label: {
                            Label("开始限时模拟".localized(), systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(selectedSubject.isEmpty)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("开始前需要配置 BYOK 大模型。".localized(), systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            NavigationLink {
                                LLMSettingsView()
                            } label: {
                                Text("前往 LLM 设置".localized())
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(DesignToken.Spacing.cardPadding)
                .cardSkin()

                if !viewModel.history.isEmpty {
                    VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                        Text("历史模拟".localized())
                            .font(DesignToken.Font.titleSmall)
                        ForEach(viewModel.history.prefix(6)) { item in
                            Button {
                                viewModel.showResult(item)
                            } label: {
                                HStack {
                                    Image(systemName: item.analysis?.role.symbol ?? "questionmark.circle")
                                        .foregroundStyle(.purple)
                                    VStack(alignment: .leading) {
                                        Text(item.analysis?.role.displayName ?? "等待分析".localized())
                                            .font(DesignToken.Font.bodyBold)
                                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(DesignToken.Font.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(item.totalScore ?? 0)")
                                        .font(.headline.monospacedDigit())
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            if item.id != viewModel.history.prefix(6).last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(DesignToken.Spacing.cardPadding)
                    .cardSkin()
                }
            }
            .padding(DesignToken.Spacing.secondaryHorizontal)
            .padding(.bottom, DesignToken.Spacing.large)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var answeringView: some View {
        Group {
            if let simulation = viewModel.simulation,
               simulation.questionRecords.indices.contains(viewModel.currentIndex) {
                let record = simulation.questionRecords[viewModel.currentIndex]
                VStack(spacing: 0) {
                    examHeader(simulation: simulation)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Text(String(format: "第 %d 题".localized(), viewModel.currentIndex + 1))
                                    .font(DesignToken.Font.titleSmall)
                                Spacer()
                                Text(record.question.type == "multiple_choice"
                                     ? "选择题".localized()
                                     : "填空题".localized())
                                    .font(DesignToken.Font.caption)
                                    .foregroundStyle(.secondary)
                            }
                            MarkdownPreviewView(text: record.question.question)
                                .frame(minHeight: 80, alignment: .topLeading)
                            answerView(for: record.question)
                        }
                        .padding(DesignToken.Spacing.secondaryHorizontal)
                        .padding(.vertical, DesignToken.Spacing.large)
                    }
                    examFooter(questionCount: simulation.questionRecords.count)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private func examHeader(simulation: ExamSimulation) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(viewModel.currentIndex + 1)/\(simulation.questionRecords.count)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(timeString(viewModel.remainingSeconds), systemImage: "timer")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(viewModel.remainingSeconds <= 120 ? .red : .purple)
                Spacer()
                Button("交卷".localized()) {
                    showingSubmitConfirmation = true
                }
                .font(.subheadline.weight(.semibold))
            }
            ProgressView(
                value: Double(simulation.durationSeconds - viewModel.remainingSeconds),
                total: Double(simulation.durationSeconds)
            )
            .tint(viewModel.remainingSeconds <= 120 ? .red : .purple)
        }
        .padding()
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func answerView(for question: QuizQuestion) -> some View {
        if question.type == "multiple_choice" {
            VStack(spacing: 12) {
                ForEach(question.options ?? [], id: \.self) { option in
                    let letter = String(option.prefix(1))
                    let selected = viewModel.answerBinding(for: question.id) == letter
                    Button {
                        viewModel.selectChoice(letter, for: question.id)
                    } label: {
                        HStack {
                            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selected ? .purple : .secondary)
                            Text(option)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding()
                        .background(
                            selected ? Color.purple.opacity(0.1) : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            MarkdownEditorView(
                text: Binding(
                    get: { viewModel.answerBinding(for: question.id) },
                    set: { viewModel.updateDraft($0, for: question.id) }
                ),
                placeholder: "输入你的答案…".localized()
            )
            .frame(minHeight: 240)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func examFooter(questionCount: Int) -> some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<questionCount, id: \.self) { index in
                        Button("\(index + 1)") {
                            viewModel.move(to: index)
                        }
                        .buttonStyle(.bordered)
                        .tint(index == viewModel.currentIndex ? .purple : .secondary)
                    }
                }
                .padding(.horizontal)
            }
            HStack {
                Button {
                    viewModel.move(to: viewModel.currentIndex - 1)
                } label: {
                    Label("上一题".localized(), systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.currentIndex == 0)

                Button {
                    if viewModel.currentIndex == questionCount - 1 {
                        showingSubmitConfirmation = true
                    } else {
                        viewModel.move(to: viewModel.currentIndex + 1)
                    }
                } label: {
                    Text(viewModel.currentIndex == questionCount - 1
                         ? "交卷".localized()
                         : "下一题".localized())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func processingView(title: String, detail: String) -> some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)
                .tint(.purple)
            Text(title)
                .font(DesignToken.Font.titleSmall)
            Text(detail)
                .font(DesignToken.Font.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ExamSimulationResultView: View {
    let simulation: ExamSimulation
    let validAnalyzedCount: Int
    let onRetry: () async -> Void
    let onNew: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: DesignToken.Spacing.large) {
                if let analysis = simulation.analysis {
                    VStack(spacing: 12) {
                        Image(systemName: analysis.role.symbol)
                            .scaledFont(size: 48)
                            .foregroundStyle(.purple)
                        Text(analysis.isStable && validAnalyzedCount >= 3
                             ? "你的常见考场模式".localized()
                             : "你在本次模拟中呈现出".localized())
                            .font(DesignToken.Font.subheadline)
                            .foregroundStyle(.secondary)
                        Text(analysis.role.displayName)
                            .font(.largeTitle.bold())
                        Text(String(format: "置信度 %d%%".localized(), Int(analysis.confidence * 100)))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.purple)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DesignToken.Spacing.large)
                    .cardSkin()

                    resultCard(title: "行为证据".localized(), symbol: "timeline.selection") {
                        ForEach(analysis.evidence) { evidence in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(evidence.title).font(DesignToken.Font.bodyBold)
                                Text(evidence.detail)
                                    .font(DesignToken.Font.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if evidence.id != analysis.evidence.last?.id { Divider() }
                        }
                    }

                    resultCard(title: "主要风险".localized(), symbol: "exclamationmark.triangle") {
                        Text(analysis.risk)
                            .font(DesignToken.Font.body)
                    }

                    resultCard(title: "下一场可以尝试".localized(), symbol: "scope") {
                        ForEach(Array(analysis.strategies.enumerated()), id: \.offset) { index, strategy in
                            HStack(alignment: .top) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(.purple, in: Circle())
                                Text(strategy).font(DesignToken.Font.body)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark")
                            .scaledFont(size: 44)
                            .foregroundStyle(.orange)
                        Text("分析暂未完成".localized())
                            .font(DesignToken.Font.titleSmall)
                        Text(simulation.lastError ?? "网络或模型响应异常，请稍后重试。".localized())
                            .font(DesignToken.Font.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重新分析".localized()) {
                            Task { await onRetry() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                    .padding(DesignToken.Spacing.large)
                    .frame(maxWidth: .infinity)
                    .cardSkin()
                }

                HStack {
                    Label("\(simulation.totalScore ?? 0)", systemImage: "checkmark.seal")
                    Spacer()
                    Label("\(simulation.answeredCount)/\(simulation.questionRecords.count)", systemImage: "list.number")
                }
                .font(.headline)
                .padding(DesignToken.Spacing.cardPadding)
                .cardSkin()

                Button {
                    onNew()
                } label: {
                    Label("再做一次模拟".localized(), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
            .padding(DesignToken.Spacing.secondaryHorizontal)
            .padding(.vertical, DesignToken.Spacing.large)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func resultCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            Label(title, systemImage: symbol)
                .font(DesignToken.Font.titleSmall)
                .foregroundStyle(.purple)
            content()
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
    }
}
