//
//  ExamDetailView.swift
//  StudyPulse
//
//  考试详情页:显示考试的核心字段(Overview)、复盘(checklist / 4 段 Markdown)、
//  关联错题、AI 预测。
//
//  Exam detail page: shows core fields (Overview), review (checklist +
//  4 markdown sections), linked mistakes, and AI prediction.
//
//  Phase 3 拆分 (2026-07-14):原 885 行单文件 → orchestrator 留本文件,
//  拆出 4 个独立子文件:
//  - ChecklistRowView.swift      (考前清单行)
//  - RelatedMistakeCard.swift    (关联错题行卡片)
//  - ReviewSectionRow.swift      (复盘 4 段折叠行)
//  - LinkedMistakesListView.swift (复盘"关联错题"子页面)
//
//  本文件只剩:主 View 编排 + 三大 Section (Overview / Review / Linked Mistakes +
//  AI Prediction) + 状态 / sheets / helpers。
//

import SwiftUI
import UIKit
import os

/// 考试详情页(Overview + 复盘 + 关联错题 + AI 预测 + 关联任务)。
/// Exam detail page (Overview + review + linked mistakes + AI prediction + linked tasks).
struct ExamDetailView: View {
    let examId: UUID
    @Environment(RepositoryContainer.self) private var container
    @Environment(HealthKitManager.self) private var hrvManager
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showingReviewEditor = false
    @State private var showingChecklist = false
    @State private var showingDeleteConfirm = false
    @State private var showingShareSheet = false
    @State private var showAI = false
    @State private var showCalendarAlert = false
    @State private var showNotificationAlert = false
    @State private var showCopyAlert = false
    @State private var copyMessage = ""
    @State private var showHistory = false
    @State private var showingAIForSimilarMistakes = false
    @State private var showAllRelatedMistakes = false
    @State private var animateIn = false
    @State private var showLinkedMistakesView = false
    @State private var showingChecklistEditor = false
    @State private var showingAutopsy = false
    @State private var showingReversePlanner = false
    @State private var readinessAIAdvice: String?
    @State private var readinessAIIsLoading = false
    @State private var readinessAITask: Task<Void, Never>?

    /// 实时从 repo 拿最新版本的考试
    /// Live copy of the exam from the repo.
    private var liveExam: Exam? {
        container.examRepo.examSets.first(where: { $0.id == examId })
    }

    /// 该考试关联的错题(review 中勾选了)
    /// Mistakes linked to the exam (ticked in the review).
    private var linkedMistakes: [MistakeNote] {
        guard let review = liveExam?.examReview else { return [] }
        let allMistakes = container.mistakeRepo.mistakeSets
        return allMistakes.filter { review.linkedMistakeIds.contains($0.id) }
    }

    /// 关联错题 id 列表
    /// List of linked mistake IDs.
    private var linkedMistakeIds: [UUID] {
        liveExam?.examReview?.linkedMistakeIds ?? []
    }

    private var readinessForExam: ExamDayReadiness? {
        guard let exam = liveExam else { return nil }
        return ExamDayReadinessEngine.predict(
            exams: [exam],
            snapshots: hrvManager.dailyHealthHistory,
            sessions: container.studySessionRepo.sessions,
            baselines: hrvManager.personalBaselines,
            age: container.profileRepo.profile.age,
            todayHRVCategory: hrvManager.readiness.category
        ).first
    }

    var body: some View {
        let exam = liveExam
        return Group {
            if let exam = exam {
                content(exam: exam)
            } else {
                missingExamView
            }
        }
    }

    // MARK: - Missing / 找不到考试时的兜底

    @ViewBuilder
    private var missingExamView: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.folder")
                .scaledFont(size: 50)
                .foregroundColor(.secondary)
            Text("Exam not found".localized())
                .font(.headline)
            Text("It may have been deleted.".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Exam".localized())
    }

    // MARK: - Content / 主体

    @ViewBuilder
    private func content(exam: Exam) -> some View {
        List {
            // Section 0:Overview
            Section {
                overviewContent(exam: exam)
                Button { showingAutopsy = true } label: {
                    Label("考试复盘", systemImage: "stethoscope")
                        .font(.headline)
                        .foregroundStyle(.purple)
                }
            } header: {
                Text("Overview".localized())
            }

            // Section 1:Metrics
            Section {
                metricsContent(exam: exam)
            } header: {
                Text("Metrics".localized())
            }

            // Section 2:Checklist
            Section {
                checklistContent(exam: exam)
            } header: {
                HStack {
                    Text("Checklist".localized())
                    Spacer()
                    if !exam.checklist.isEmpty {
                        Text(String(format: "%d/%d".localized(), exam.checklist.filter { $0.isChecked }.count, exam.checklist.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Section 3:Notifications
            Section {
                notificationsContent(exam: exam)
            } header: {
                Text("Notifications & Reminders".localized())
            }

            // Section 4:Calendar
            Section {
                calendarContent(exam: exam)
            } header: {
                Text("Calendar".localized())
            }

            // Section 5:Share
            Section {
                shareContent(exam: exam)
            } header: {
                Text("Share & Export".localized())
            }

            // Section 6:Review
            Section {
                examReadinessContent(exam: exam)
                reviewContent(exam: exam)
            } header: {
                HStack {
                    Text("Review".localized())
                    Spacer()
                    if exam.examReview != nil {
                        Text("✓ Filled".localized())
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else {
                        Text("Pending".localized())
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            // Section 7:Linked Mistakes
            if !linkedMistakes.isEmpty {
                Section {
                    ForEach(linkedMistakes.prefix(3)) { mistake in
                        NavigationLink {
                            MistakeSetDetailView(mistakeSet: mistake)
                        } label: {
                            RelatedMistakeCard(mistake: mistake)
                        }
                    }
                    if linkedMistakes.count > 3 {
                        Button {
                            showLinkedMistakesView = true
                        } label: {
                            HStack {
                                Spacer()
                                Text(String(format: "View all %d mistakes".localized(), linkedMistakes.count))
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "link")
                        Text("Linked Mistakes".localized())
                    }
                } footer: {
                    if let review = exam.examReview,
                       !review.linkedMistakeIds.isEmpty {
                        Text(String(format: "%d mistakes linked from review".localized(), review.linkedMistakeIds.count))
                    }
                }
            }

            // Section 8:AI Prediction
            Section {
                aiPredictionContent(exam: exam)
            } header: {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                    Text("AI Prediction".localized())
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(exam.name)
        .navigationBarTitleDisplayMode(.inline)
        .adaptiveMaxWidth(900)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingReviewEditor = true
                    } label: {
                        Label(exam.examReview == nil ? "Add Review".localized() : "Edit Review".localized(),
                              systemImage: "square.and.pencil")
                    }
                    Button {
                        showingChecklistEditor = true
                    } label: {
                        Label("Edit Checklist".localized(), systemImage: "checklist")
                    }
                    Button { showingAutopsy = true } label: {
                        Label("考试复盘", systemImage: "stethoscope")
                    }
                    Button { showingReversePlanner = true } label: {
                        Label("生成倒推计划", systemImage: "calendar.badge.clock")
                    }
                    if let review = exam.examReview {
                        Button {
                            copyMessage = review.summary
                            UIPasteboard.general.string = review.summary
                            showCopyAlert = true
                        } label: {
                            Label("Copy Summary".localized(), systemImage: "doc.on.doc")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Exam".localized(), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingReviewEditor) {
            ExamReviewEditView(exam: exam)
                .environment(container)
                .adaptiveSheet()
        }
        .sheet(isPresented: $showingChecklistEditor) {
            ExamChecklistEditView(exam: exam)
                .environment(container)
                .adaptiveSheet()
        }
        .sheet(isPresented: $showingAutopsy) {
            NavigationStack {
                ExamAutopsyView(exam: exam, container: container)
                    .environment(container)
            }
        }
        .fullScreenCover(isPresented: $showingReversePlanner) {
            ExamReversePlannerView(container: container, examId: examId)
                .environment(container)
        }
        .alert("Delete Exam".localized(), isPresented: $showingDeleteConfirm) {
            Button("Cancel".localized(), role: .cancel) { }
            Button("Delete".localized(), role: .destructive) {
                container.deleteExam(exam)
            }
        } message: {
            Text("This action cannot be undone.".localized())
        }
        .sheet(isPresented: $showLinkedMistakesView) {
            NavigationStack {
                LinkedMistakesListView(
                    mistakeIds: linkedMistakeIds,
                    subject: exam.subject
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done".localized()) {
                            showLinkedMistakesView = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAllRelatedMistakes) {
            // TODO: 全量错题选择器(可多选,作为"复习任务"写入)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                animateIn = true
            }
        }
        .onDisappear {
            readinessAITask?.cancel()
        }
    }

    // MARK: - Overview / 总览(核心字段)

    @ViewBuilder
    private func overviewContent(exam: Exam) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exam.name)
                        .font(.title3.weight(.semibold))
                    if !exam.subject.isEmpty {
                        Text(exam.subject.localized())
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                importanceBadge(importance: exam.importance)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Date".localized())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(exam.examDate, format: .dateTime.month().day().year())
                        .font(.subheadline.weight(.medium))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time".localized())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(exam.examTimeText)
                        .font(.subheadline.weight(.medium))
                }
                if exam.examEndDate != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Multi-day".localized())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "%d days".localized(), exam.examDurationDays))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.purple)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    private func importanceBadge(importance: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= importance ? "star.fill" : "star")
                    .scaledFont(size: 10)
                    .foregroundColor(i <= importance ? Color.orange : Color.gray.opacity(0.3))
            }
        }
    }

    // MARK: - Metrics / 关键指标

    @ViewBuilder
    private func metricsContent(exam: Exam) -> some View {
        let isCompleted = exam.examReview != nil
        VStack(spacing: 8) {
            HStack {
                Text("Time Left".localized())
                    .foregroundColor(.secondary)
                Spacer()
                Text(timeLeftText(for: exam))
                    .fontWeight(.medium)
                    .foregroundColor(isCompleted ? .green : (exam.isUpcoming ? .blue : .secondary))
            }

            if isCompleted {
                HStack {
                    Text("Status".localized())
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Completed".localized())
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
            } else if exam.isUpcoming {
                HStack {
                    Text("Mastery".localized())
                        .foregroundColor(.secondary)
                    Spacer()
                    masteryRingView(score: exam.masteryDegree)
                }
            }
        }
    }

    private func timeLeftText(for exam: Exam) -> String {
        if exam.examReview != nil {
            return "Finished".localized()
        }
        return exam.timeLeftText
    }

    private func masteryRingView(score: Int) -> some View {
        let color: Color = score >= 75 ? .green : (score >= 50 ? .orange : .red)
        return HStack(spacing: 4) {
            FitnessRingView(progress: Double(score) / 100.0, lineWidth: 3, size: 20)
            Text("\(score)%")
                .font(.caption.weight(.medium))
                .foregroundColor(color)
        }
    }

    // MARK: - Checklist / 考前清单

    @ViewBuilder
    private func checklistContent(exam: Exam) -> some View {
        if exam.checklist.isEmpty {
            Button {
                showingChecklistEditor = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Add Checklist Items".localized())
                }
            }
        } else {
            ForEach(exam.checklist) { item in
                ChecklistRowView(item: item) {
                    container.toggleExamChecklistItem(exam.id, itemId: item.id)
                }
            }
            Button {
                showingChecklistEditor = true
            } label: {
                HStack {
                    Image(systemName: "pencil")
                    Text("Edit Checklist".localized())
                }
            }
            .foregroundColor(.blue)
        }
    }

    // MARK: - Notifications / 通知

    @ViewBuilder
    private func notificationsContent(exam: Exam) -> some View {
        Button {
            Task {
                do {
                    try await exam.scheduleNotifications()
                    showNotificationAlert = true
                } catch {
                    Log.data.error("Failed to schedule notification: \(error.localizedDescription, privacy: .public)")
                }
            }
        } label: {
            HStack {
                Image(systemName: "bell.fill")
                Text("Schedule Notifications".localized())
            }
        }
        .alert("Notifications Scheduled".localized(), isPresented: $showNotificationAlert) {
            Button("OK".localized()) { }
        } message: {
            Text("You will be reminded before this exam.".localized())
        }
    }

    // MARK: - Calendar / 系统日历

    @ViewBuilder
    private func calendarContent(exam: Exam) -> some View {
        Button {
            Task {
                let success = await exam.addToSystemCalendar()
                showCalendarAlert = success
            }
        } label: {
            HStack {
                Image(systemName: "calendar.badge.plus")
                Text("Add to System Calendar".localized())
            }
        }
        .alert("Added to Calendar".localized(), isPresented: $showCalendarAlert) {
            Button("OK".localized()) { }
        } message: {
            Text("The exam has been added to your system calendar.".localized())
        }
    }

    // MARK: - Share / 分享

    @ViewBuilder
    private func shareContent(exam: Exam) -> some View {
        Button {
            showingShareSheet = true
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Share Exam Details".localized())
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivityViewController(activityItems: [exam.shareableText])
        }
    }

    // MARK: - Review / 复盘

    @ViewBuilder
    private func examReadinessContent(exam: Exam) -> some View {
        if let readiness = readinessForExam {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(color(for: readiness.riskCategory))
                VStack(alignment: .leading, spacing: 4) {
                    Text("examReadiness.rowTitle".localized())
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        Text("riskCategory.\(readiness.riskCategory.rawValue)".localized())
                            .font(.caption.weight(.medium))
                            .foregroundStyle(color(for: readiness.riskCategory))
                        if let score = readiness.predictedScore {
                            Text(String(format: "examReadiness.predictedScoreLabel".localized(), score * 100))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(readiness.advice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let readinessAIAdvice {
                        Text(readinessAIAdvice)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if container.envManager.llmConfig.isConfigured {
                        Button {
                            requestReadinessAI(readiness)
                        } label: {
                            Label(
                                readinessAIIsLoading
                                    ? "examReadiness.aiLoading".localized()
                                    : "examReadiness.aiButton".localized(),
                                systemImage: readinessAIIsLoading ? "hourglass" : "sparkles"
                            )
                            .font(.caption.weight(.medium))
                        }
                        .disabled(readinessAIIsLoading)
                    }
                }
            }
        } else {
            Label("examReadiness.emptyHint".localized(), systemImage: "heart.text.square")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func color(for category: RiskCategory) -> Color {
        switch category {
        case .strong: return .green
        case .steady: return .blue
        case .atRisk: return .orange
        case .critical: return .red
        }
    }

    private func requestReadinessAI(_ readiness: ExamDayReadiness) {
        readinessAITask?.cancel()
        readinessAIAdvice = nil
        readinessAIIsLoading = true
        let prompt = ExamReadinessLLM.makePrompt(ExamReadinessLLM.context(from: readiness))
        let config = container.envManager.llmConfig
        readinessAITask = Task { @MainActor in
            defer { readinessAIIsLoading = false }
            do {
                let output = try await LLMClient.shared.complete(
                    prompt: prompt,
                    config: config,
                    caller: "ExamReadiness"
                )
                readinessAIAdvice = ExamReadinessLLM.parse(output)
            } catch is CancellationError {
                // The local result remains visible when the optional request is cancelled.
            } catch {
                // BYOK failures silently fall back to the local algorithm output.
            }
        }
    }

    @ViewBuilder
    private func reviewContent(exam: Exam) -> some View {
        if let review = exam.examReview {
            ReviewSectionRow(
                title: "Summary".localized(),
                icon: "doc.text",
                markdown: review.summary
            )
            ReviewSectionRow(
                title: "What Was Tested".localized(),
                icon: "doc.text.magnifyingglass",
                markdown: review.whatWasTested
            )
            ReviewSectionRow(
                title: "What Went Wrong".localized(),
                icon: "exclamationmark.triangle",
                markdown: review.whatWentWrong
            )
            ReviewSectionRow(
                title: "Insights".localized(),
                icon: "lightbulb",
                markdown: review.whatLearned
            )

            Button {
                showingReviewEditor = true
            } label: {
                HStack {
                    Image(systemName: "pencil")
                    Text("Edit Review".localized())
                }
            }
            .foregroundColor(.blue)
        } else {
            Button {
                showingReviewEditor = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Review".localized())
                }
            }
        }
    }

    // MARK: - AI Prediction / AI 预测

    @ViewBuilder
    private func aiPredictionContent(exam: Exam) -> some View {
        Button {
            showAI = true
        } label: {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Predict Exam Score".localized())
                        .foregroundColor(.primary)
                    Text("AI based on your history, mastery, and recent mistakes".localized())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showAI) {
            ScorePredictionView(exam: exam)
                .environment(container)
                .adaptiveSheet()
        }
    }
}

// MARK: - Preview / 独立预览入口

@MainActor
private enum ExamDetailPreview {
    static func makeContainer() -> RepositoryContainer {
        let container = RepositoryContainer()
        let cal = Calendar.current
        let now = Date()
        var components = DateComponents()
        components.year = cal.component(.year, from: now)
        components.month = cal.component(.month, from: now)
        components.day = cal.component(.day, from: now) + 7
        let examDate = cal.date(from: components) ?? now

        var exam = Exam(
            name: "Math Midterm",
            date: examDate,
            importance: 4,
            subject: "Mathematics",
            examName: "Midterm",
            masteryDegree: 65
        )
        exam.checklist = [
            ExamChecklistItem(title: "身份证", isChecked: true, sortOrder: 0),
            ExamChecklistItem(title: "准考证", sortOrder: 1),
            ExamChecklistItem(title: "2B 铅笔", sortOrder: 2)
        ]
        exam.examReview = ExamReview(
            whatWasTested: "Ch.3-4:二次函数、配方法",
            whatWentWrong: "配方时漏掉 -b/2a 的负号",
            whatLearned: "练习更多顶点形式题目",
            nextStrategy: "整体表现中上,需强化计算细节。",
            linkedMistakeIds: []
        )
        container.examRepo.add(single: [exam], comprehensive: [])
        return container
    }
}

#Preview("With Sample Exam") {
    let container = ExamDetailPreview.makeContainer()
    let examId = container.examRepo.examSets[0].id
    NavigationStack {
        ExamDetailView(examId: examId)
    }
    .environment(container)
}
