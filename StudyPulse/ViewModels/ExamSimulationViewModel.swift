import Foundation

@MainActor
@Observable
final class ExamSimulationViewModel {
    enum FlowState: Equatable {
        case landing
        case generating
        case answering
        case processing
        case result
    }

    private(set) var state: FlowState = .landing
    private(set) var simulation: ExamSimulation?
    private(set) var currentIndex = 0
    private(set) var remainingSeconds = ExamSimulation.defaultDurationSeconds
    var draftAnswers: [UUID: String] = [:]
    var errorMessage: String?

    private let container: RepositoryContainer
    private var recorder: ExamSimulationBehaviorRecorder?
    private var submissionInFlight = false

    init(container: RepositoryContainer) {
        self.container = container
        restoreRunningSimulationIfNeeded()
    }

    var isLLMConfigured: Bool { container.envManager.llmConfig.isConfigured }
    var subjects: [Subject] { container.subjectRepo.subjects.filter(\.enabled) }
    var analyzedHistory: [ExamSimulation] { container.examSimulationRepo.recentAnalyzed(limit: 20) }
    var history: [ExamSimulation] {
        container.examSimulationRepo.recentCompleted(limit: 6)
    }
    var validAnalyzedCount: Int { analyzedHistory.count }

    func startNewSimulation(subject: String, topic: String = "") async {
        guard isLLMConfigured else {
            errorMessage = "请先配置 LLM，才能开始考场模拟。".localized()
            return
        }
        guard state != .generating && state != .processing else { return }

        state = .generating
        errorMessage = nil
        let mistakes = container.mistakeRepo.mistakeSets
            .filter { $0.subject == subject }
            .sorted { $0.date > $1.date }
        let useMistakes = !mistakes.isEmpty && topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let prompt = QuizGenerationLLM.makePrompt(
            subject: subject,
            scope: useMistakes ? "mistakes" : "chapter",
            referenceMistakes: Array(mistakes.prefix(10)),
            chapterTopic: topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "本科目综合核心知识，难度由基础到中等递进"
                : topic,
            count: ExamSimulation.defaultQuestionCount
        )

        do {
            let raw = try await LLMClient.shared.complete(
                prompt: prompt,
                config: container.envManager.llmConfig,
                caller: "ExamSimulationGeneration"
            )
            guard let questions = ExamRoleLLM.parseQuestions(raw) else {
                throw LLMError.malformedResponse
            }
            var newSimulation = ExamSimulation(subject: subject, questions: questions)
            var newRecorder = ExamSimulationBehaviorRecorder(simulation: newSimulation)
            let now = Date()
            newRecorder.start(at: now, remainingSeconds: newSimulation.durationSeconds)
            newRecorder.enterQuestion(index: 0, at: now, remainingSeconds: newSimulation.durationSeconds)
            newSimulation = newRecorder.simulation

            recorder = newRecorder
            simulation = newSimulation
            currentIndex = 0
            remainingSeconds = newSimulation.durationSeconds
            draftAnswers = [:]
            container.examSimulationRepo.upsert(newSimulation)
            state = .answering
        } catch {
            errorMessage = error.localizedDescription
            state = .landing
        }
    }

    /// Returns true when the caller should trigger automatic submission.
    func tick(now: Date = Date()) -> Bool {
        guard state == .answering, let startedAt = simulation?.startedAt,
              let duration = simulation?.durationSeconds else { return false }
        remainingSeconds = max(0, duration - Int(now.timeIntervalSince(startedAt)))
        return remainingSeconds == 0 && !submissionInFlight
    }

    func answerBinding(for questionId: UUID) -> String {
        draftAnswers[questionId] ?? ""
    }

    func updateDraft(_ answer: String, for questionId: UUID) {
        draftAnswers[questionId] = answer
    }

    /// Multiple-choice taps are committed immediately so changing A → B on the
    /// same visit is captured as a real answer revision.
    func selectChoice(_ answer: String, for questionId: UUID, now: Date = Date()) {
        draftAnswers[questionId] = answer
        guard state == .answering,
              let simulation,
              simulation.questionRecords.indices.contains(currentIndex),
              simulation.questionRecords[currentIndex].question.id == questionId else { return }
        recorder?.commitAnswer(
            index: currentIndex,
            answer: answer,
            at: now,
            remainingSeconds: remainingSeconds
        )
        syncAndPersist()
    }

    func move(to index: Int, now: Date = Date()) {
        guard state == .answering, let simulation,
              simulation.questionRecords.indices.contains(index),
              index != currentIndex else { return }
        commitAndLeaveCurrent(at: now)
        currentIndex = index
        recorder?.enterQuestion(index: index, at: now, remainingSeconds: remainingSeconds)
        syncAndPersist()
    }

    func submit(timedOut: Bool, now: Date = Date()) async {
        guard state == .answering, !submissionInFlight else { return }
        submissionInFlight = true
        commitAndLeaveCurrent(at: now)
        recorder?.beginSubmission(at: now, remainingSeconds: remainingSeconds, timedOut: timedOut)
        syncAndPersist()
        state = .processing
        await gradeAndAnalyze()
        submissionInFlight = false
    }

    func retryAnalysis() async {
        guard let simulation, simulation.status == .analysisFailed, isLLMConfigured else { return }
        recorder = ExamSimulationBehaviorRecorder(simulation: simulation)
        state = .processing
        await gradeAndAnalyze()
    }

    func showResult(_ item: ExamSimulation) {
        guard let full = container.examSimulationRepo.simulation(id: item.id) else { return }
        simulation = full
        recorder = ExamSimulationBehaviorRecorder(simulation: full)
        state = .result
    }

    func returnToLanding() {
        simulation = nil
        recorder = nil
        draftAnswers = [:]
        currentIndex = 0
        remainingSeconds = ExamSimulation.defaultDurationSeconds
        errorMessage = nil
        state = .landing
    }

    func abandon(now: Date = Date()) {
        guard state == .answering else {
            returnToLanding()
            return
        }
        commitAndLeaveCurrent(at: now)
        recorder?.abandon(at: now, remainingSeconds: remainingSeconds)
        syncAndPersist()
        returnToLanding()
    }

    private func commitAndLeaveCurrent(at now: Date) {
        guard let simulation,
              simulation.questionRecords.indices.contains(currentIndex) else { return }
        let questionId = simulation.questionRecords[currentIndex].question.id
        let answer = draftAnswers[questionId] ?? ""
        recorder?.commitAnswer(
            index: currentIndex,
            answer: answer,
            at: now,
            remainingSeconds: remainingSeconds
        )
        if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recorder?.markSkipped(index: currentIndex, at: now, remainingSeconds: remainingSeconds)
        }
        recorder?.leaveQuestion(index: currentIndex, at: now, remainingSeconds: remainingSeconds)
        syncAndPersist()
    }

    private func gradeAndAnalyze() async {
        guard var current = recorder?.simulation else { return }
        do {
            if current.totalScore == nil {
                let answers = Dictionary(
                    uniqueKeysWithValues: current.questionRecords.map {
                        ($0.question.id, $0.finalAnswer ?? "")
                    }
                )
                let gradingPrompt = QuizGradingLLM.makePrompt(
                    subject: current.subject,
                    questions: current.questionRecords.map(\.question),
                    userAnswers: answers
                )
                let gradingRaw = try await LLMClient.shared.complete(
                    prompt: gradingPrompt,
                    config: container.envManager.llmConfig,
                    caller: "ExamSimulationGrading"
                )
                guard let grading = ExamRoleLLM.parseGrading(gradingRaw) else {
                    throw LLMError.malformedResponse
                }
                recorder?.applyGrading(grading)
                syncAndPersist()
                current = recorder?.simulation ?? current
            }

            let previous = container.examSimulationRepo.analyzedSimulations
                .filter { $0.id != current.id }
            let prompt = ExamRoleLLM.makePrompt(simulation: current, previous: previous)
            let analysisRaw = try await LLMClient.shared.complete(
                prompt: prompt,
                config: container.envManager.llmConfig,
                caller: "ExamRoleAnalysis"
            )
            guard var analysis = ExamRoleLLM.parse(analysisRaw) else {
                throw LLMError.malformedResponse
            }
            if previous.count + 1 < 3 {
                analysis.isStable = false
            }
            recorder?.finish(with: analysis)
            syncAndPersist()
            state = .result
        } catch {
            recorder?.fail(error.localizedDescription)
            syncAndPersist()
            errorMessage = error.localizedDescription
            state = .result
        }
    }

    private func syncAndPersist() {
        guard let value = recorder?.simulation else { return }
        simulation = value
        container.examSimulationRepo.upsert(value)
    }

    private func restoreRunningSimulationIfNeeded(now: Date = Date()) {
        guard let active = container.examSimulationRepo.latestRunningSimulation() else { return }

        simulation = active
        recorder = ExamSimulationBehaviorRecorder(simulation: active)
        draftAnswers = Dictionary(
            uniqueKeysWithValues: active.questionRecords.compactMap { record in
                guard let answer = record.finalAnswer else { return nil }
                return (record.question.id, answer)
            }
        )
        currentIndex = active.events.reversed()
            .first(where: { $0.kind == .questionEntered })?
            .questionIndex ?? 0
        if let startedAt = active.startedAt {
            remainingSeconds = max(0, active.durationSeconds - Int(now.timeIntervalSince(startedAt)))
        } else {
            remainingSeconds = active.durationSeconds
        }
        state = .answering
    }
}
