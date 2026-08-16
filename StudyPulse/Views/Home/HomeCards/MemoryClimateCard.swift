//
//  MemoryClimateCard.swift
//  StudyPulse
//

import SwiftUI

struct MemoryClimateCard: View {
    let snapshot: MemoryClimateSnapshot
    let history: [MemoryClimateSnapshot]
    let onStartReview: () -> Void

    @Environment(RepositoryContainer.self) private var container
    @State private var showingDetail = false
    @State private var remediationTask: RemediationTask?
    @State private var showingRemediation = false

    var body: some View {
        if let dominant = snapshot.dominantSubject {
            Button {
                showingDetail = true
            } label: {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("memory.climate.title".localized(), systemImage: "cloud.sun.rain.fill")
                            .font(.headline)
                        Spacer()
                        Text(dominant.weather.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(weatherColor(dominant.weather))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(weatherColor(dominant.weather).opacity(0.12), in: Capsule())
                    }

                    HStack(spacing: 16) {
                        Image(systemName: dominant.weather.symbolName)
                            .font(.system(size: 44))
                            .symbolRenderingMode(.multicolor)
                            .foregroundStyle(weatherColor(dominant.weather))
                            .frame(width: 58)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(dominant.summary)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text("memory.climate.openMap".localized())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(snapshot.subjects.prefix(4)) { climate in
                                HStack(spacing: 4) {
                                    Image(systemName: climate.weather.symbolName)
                                    Text(climate.subject)
                                        .lineLimit(1)
                                }
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(weatherColor(climate.weather))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(weatherColor(climate.weather).opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSkin()
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingDetail) {
                NavigationStack {
                    MemoryClimateDetailView(
                        snapshot: snapshot,
                        history: history,
                        remediationTask: remediationTask,
                        onStartReview: {
                            showingDetail = false
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(250))
                                guard !Task.isCancelled else { return }
                                onStartReview()
                            }
                        },
                        onStartRemediation: {
                            showingDetail = false
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(250))
                                guard !Task.isCancelled else { return }
                                showingRemediation = true
                            }
                        }
                    )
                }
                .presentationDetents([.large])
                .onAppear { generateRemediationTask() }
            }
            .fullScreenCover(isPresented: $showingRemediation) {
                if let task = remediationTask {
                    NavigationStack {
                        FlashcardStudyView(container: container, filter: .remediation(task.mistakes))
                            .environment(container)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button {
                                        showingRemediation = false
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .accessibilityLabel("Close".localized())
                                }
                            }
                    }
                }
            }
        }
    }

    private func generateRemediationTask() {
        remediationTask = RemediationTaskEngine.generate(
            snapshot: snapshot,
            mistakes: container.mistakeRepo.filteredMistakeSets
        )
    }
}

struct MemoryClimateDetailView: View {
    let snapshot: MemoryClimateSnapshot
    let history: [MemoryClimateSnapshot]
    let remediationTask: RemediationTask?
    let onStartReview: () -> Void
    let onStartRemediation: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var historyDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: snapshot.date)
        return (0..<90).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if snapshot.subjects.isEmpty {
                    ContentUnavailableView(
                        "memory.climate.noData.title".localized(),
                        systemImage: "cloud",
                        description: Text("memory.climate.noData.description".localized())
                    )
                } else {
                    todaySection
                    historyMap
                    if remediationTask != nil {
                        remediationSection
                    }
                    evidenceSection
                    reviewButton
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("memory.climate.title".localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done".localized()) { dismiss() }
            }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("memory.climate.today".localized())
                .font(.title2.bold())
            ForEach(snapshot.subjects) { climate in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: climate.weather.symbolName)
                        .font(.title2)
                        .foregroundStyle(weatherColor(climate.weather))
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(climate.subject).font(.headline)
                            Text(climate.weather.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(weatherColor(climate.weather))
                        }
                        Text(climate.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int((climate.confidence * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var historyMap: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("memory.climate.history".localized())
                .font(.headline)
            Text("memory.climate.history.hint".localized())
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(snapshot.subjects) { today in
                        HStack(spacing: 5) {
                            Text(today.subject)
                                .font(.caption)
                                .frame(width: 72, alignment: .leading)
                                .lineLimit(1)
                            ForEach(historyDays, id: \.self) { day in
                                let daily = history.first {
                                    Calendar.current.isDate($0.date, inSameDayAs: day)
                                }
                                let climate = daily?.subjects.first {
                                    $0.subject.caseInsensitiveCompare(today.subject) == .orderedSame
                                }
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(climate.map { weatherColor($0.weather) } ?? Color.secondary.opacity(0.12))
                                    .frame(width: 15, height: 15)
                                    .accessibilityLabel(
                                        climate.map {
                                            "\(today.subject), \($0.weather.title)"
                                        } ?? "\(today.subject), \("memory.climate.noData.title".localized())"
                                    )
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("memory.climate.conceptHotspots".localized())
                .font(.headline)
            ForEach(snapshot.subjects) { climate in
                if !climate.interferences.isEmpty || !climate.primaryConcepts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(climate.subject)
                            .font(.subheadline.weight(.semibold))
                        if let pair = climate.interferences.first {
                            Label(pair.displayName, systemImage: "bolt.horizontal.circle.fill")
                                .foregroundStyle(.orange)
                            Text(
                                String(
                                    format: "memory.climate.negativeRetrievals".localized(),
                                    pair.negativeRetrievalCount
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text(climate.primaryConcepts.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    @ViewBuilder
    private var remediationSection: some View {
        if let task = remediationTask {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("memory.climate.remediation.title".localized(), systemImage: "timer")
                        .font(.headline)
                    Spacer()
                    Text(
                        String(
                            format: "memory.climate.remediation.estimatedMinutes".localized(),
                            task.estimatedMinutes
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Text(strategyDescription(task.strategy))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    onStartRemediation()
                } label: {
                    Label("memory.climate.remediation.button".localized(), systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func strategyDescription(_ strategy: RemediationStrategy) -> String {
        switch strategy {
        case .interference:
            return "memory.climate.remediation.strategy.interference".localized()
        case .overdue:
            return "memory.climate.remediation.strategy.overdue".localized()
        case .weakSpot:
            return "memory.climate.remediation.strategy.weakSpot".localized()
        }
    }

    private var reviewButton: some View {
        Button {
            onStartReview()
        } label: {
            Label("memory.climate.startReview".localized(), systemImage: "rectangle.stack.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
        .disabled(snapshot.subjects.isEmpty)
    }
}

private func weatherColor(_ weather: MemoryWeather) -> Color {
    switch weather {
    case .clear: return .yellow
    case .fog: return .gray
    case .thunderstorm: return .indigo
    case .frozen: return .cyan
    case .southHumid: return .mint
    }
}
