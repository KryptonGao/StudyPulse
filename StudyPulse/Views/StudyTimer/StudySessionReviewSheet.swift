//
//  StudySessionReviewSheet.swift
//  StudyPulse
//
//  会话结束后的心率回顾 sheet:展示心率曲线、峰值高亮、难题标注交互、AI 解读按钮。
//  Post-session heart-rate review sheet: shows HR curve, peak highlights,
//  difficulty annotation interaction, and an AI stress-interpretation button.
//

import SwiftUI
import SwiftStreamingMarkdown
import os

// MARK: - StudySessionReviewSheet

struct StudySessionReviewSheet: View {
    let session: StudySession
    let subjects: [Subject]
    /// 标注更新回调(父视图回写 StudySessionStore)
    /// Annotation update callback (parent persists to StudySessionStore).
    var onAnnotationsChange: ([DifficultyAnnotation]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(RepositoryContainer.self) private var container
    @Environment(HealthKitManager.self) private var hrv: HealthKitManager

    // 标注本地状态(初始化时从 session 读取)
    @State private var annotations: [DifficultyAnnotation] = []
    @State private var editingAnnotation: DifficultyAnnotation?
    @State private var pendingNewAnnotation: (timestamp: Date, heartRate: Double?)?

    // AI 解读状态
    @State private var aiOutput: String = ""
    @State private var aiLoading: Bool = false
    @State private var aiTask: Task<Void, Never>?

    // MARK: - Derived

    private var samples: [HeartRateSample] { session.heartRateSamples ?? [] }
    private var rhr: Double? { hrv.bodyStatus.restingHeartRate }
    private var peaks: [HeartRateSample] {
        HeartRateSample.detectPeaks(samples: samples, rhrBaseline: rhr)
    }

    // MARK: - Body

    private var goalSection: some View {
        Group {
            if let goal = session.goal {
                VStack(alignment: .leading, spacing: 8) {
                    Label(goal.title, systemImage: goal.source.icon)
                        .font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 10) {
                        Text(goal.progressText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        if let rate = goal.completionRate {
                            Text(String(format: "%.0f%%", rate*100))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(rate>=1 ? .green : .accentColor)
                            ProgressView(value: rate).frame(width: 60)
                        }
                    }
                    if let diff = goal.difficulty {
                        Label(diff.displayName, systemImage: diff.icon).font(.caption).foregroundStyle(.secondary)
                    }
                    if let reason = goal.interruptionReason, reason != .none {
                        Label(reason.displayName, systemImage: reason.icon).font(.caption).foregroundColor(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill)))
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    goalSection
                    chartSection
                    annotationListSection
                    aiSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Session Review".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized()) { dismiss() }
                }
            }
            .sheet(item: $editingAnnotation) { anno in
                DifficultyAnnotationEditor(
                    existing: anno,
                    timestamp: anno.timestamp,
                    heartRate: anno.heartRate,
                    subjects: subjects,
                    onSave: { updated in
                        replaceAnnotation(updated)
                    },
                    onDelete: { deleted in
                        deleteAnnotation(deleted)
                    }
                )
            }
            .sheet(isPresented: Binding(
                get: { pendingNewAnnotation != nil },
                set: { if !$0 { pendingNewAnnotation = nil } }
            )) {
                if let pending = pendingNewAnnotation {
                    DifficultyAnnotationEditor(
                        existing: nil,
                        timestamp: pending.timestamp,
                        heartRate: pending.heartRate,
                        subjects: subjects,
                        onSave: { newAnno in
                            addAnnotation(newAnno)
                        }
                    )
                }
            }
            .onAppear {
                if annotations.isEmpty {
                    annotations = session.difficultyAnnotations ?? []
                }
            }
            .onDisappear {
                aiTask?.cancel()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.intensity.displayName)
                        .font(.system(size: 18, weight: .bold))
                    Text(session.startDate, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(session.durationSeconds / 60) min")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: session.intensity.colorHex))
                    Text("\(samples.count) HR samples".localized())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            if samples.count < 5 {
                Label("Apple Watch passive sampling is sparse. Peak detection may be less accurate.".localized(), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.orange.opacity(0.10)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Heart Rate Curve".localized())
                .font(.system(size: 14, weight: .semibold))

            HeartRateChartView(
                samples: samples,
                sessionStart: session.startDate,
                rhrBaseline: rhr,
                annotations: annotations,
                peaks: peaks,
                onTapPeak: { peak in
                    pendingNewAnnotation = (peak.timestamp, peak.bpm)
                },
                onLongPress: { timestamp, bpm in
                    pendingNewAnnotation = (timestamp, bpm)
                }
            )

            if !peaks.isEmpty {
                Text("Tap a red peak to log what you were struggling with. Long-press anywhere to add a manual annotation.".localized())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Annotation list

    private var annotationListSection: some View {
        AnnotationListView(
            annotations: annotations,
            subjects: subjects,
            onEdit: { anno in
                editingAnnotation = anno
            },
            onDelete: { deleted in
                deleteAnnotation(deleted)
            }
        )
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - AI section

    private var aiSection: some View {
        Group {
            if container.envManager.llmConfig.isConfigured {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("AI Stress Interpretation".localized())
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button {
                            runAI()
                        } label: {
                            Label("✨ AI 解读".localized(), systemImage: "sparkles")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.purple.opacity(0.15)))
                                .foregroundColor(.purple)
                        }
                        .disabled(aiLoading)
                    }

                    if aiLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Analyzing…".localized())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if !aiOutput.isEmpty {
                        MarkdownView(text: aiOutput.normalisingSingleDollarMath(), config: .previewConfig)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }

    // MARK: - Annotation mutations

    private func addAnnotation(_ anno: DifficultyAnnotation) {
        annotations.append(anno)
        persistAnnotations()
    }

    private func replaceAnnotation(_ updated: DifficultyAnnotation) {
        if let idx = annotations.firstIndex(where: { $0.id == updated.id }) {
            annotations[idx] = updated
            persistAnnotations()
        }
    }

    private func deleteAnnotation(_ deleted: DifficultyAnnotation) {
        annotations.removeAll { $0.id == deleted.id }
        persistAnnotations()
    }

    private func persistAnnotations() {
        onAnnotationsChange(annotations)
    }

    // MARK: - AI

    private func runAI() {
        aiTask?.cancel()
        aiOutput = ""
        aiLoading = true
        let config = container.envManager.llmConfig
        let prompt = StudySessionStressLLM.makePrompt(
            session: session,
            rhrBaseline: rhr
        )
        aiTask = Task {
            do {
                _ = try await LLMClient.shared.stream(prompt: prompt, config: config, caller: "StudySessionStress") { snapshot in
                    aiOutput = snapshot
                }
                aiLoading = false
            } catch is CancellationError {
                aiLoading = false
            } catch {
                aiLoading = false
                Log.llm.error("StudySessionStressLLM failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Preview

#Preview("Review sheet") {
    let now = Date()
    let samples: [HeartRateSample] = (0..<10).map { i in
        HeartRateSample(
            id: UUID(),
            timestamp: now.addingTimeInterval(Double(i) * 150),
            bpm: [70, 75, 90, 105, 95, 82, 78, 88, 100, 85][i]
        )
    }
    let session = StudySession(
        id: UUID(),
        startDate: now,
        durationSeconds: 25 * 60,
        intensity: .steady,
        completed: true,
        heartRateSamples: samples,
        difficultyAnnotations: []
    )
    return StudySessionReviewSheet(
        session: session,
        subjects: [],
        onAnnotationsChange: { _ in }
    )
    .environment(RepositoryContainer())
}
