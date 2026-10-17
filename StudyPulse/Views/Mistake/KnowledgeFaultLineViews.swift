//
//  KnowledgeFaultLineViews.swift
//  StudyPulse
//

import SwiftUI

/// 暂无重复断层时的空态卡 / Empty card shown when no repeated fault line exists.
struct KnowledgeFaultLineEmptyCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("knowledge.fault.home.title".localized())
                    .font(.subheadline.weight(.semibold))
                Text("knowledge.fault.home.empty".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
    }
}

struct KnowledgeFaultLineView: View {
    @Environment(RepositoryContainer.self) private var environmentContainer
    @State private var viewModel: KnowledgeFaultLineViewModel

    private var container: RepositoryContainer { environmentContainer }

    init(container: RepositoryContainer) {
        _viewModel = State(initialValue: KnowledgeFaultLineViewModel.makeDefault(container: container))
    }

    var body: some View {
        Group {
            if container.mistakeRepo.filteredMistakeSets.isEmpty {
                ContentUnavailableView(
                    "knowledge.fault.empty.title".localized(),
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("knowledge.fault.empty.message".localized())
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignToken.Spacing.cardSpacing) {
                        overviewHeader

                        if viewModel.repeatedFaultLines.isEmpty {
                            KnowledgeFaultLineEmptyCard()
                        } else {
                            Text("knowledge.fault.overview.section".localized())
                                .font(.headline)
                            ForEach(viewModel.repeatedFaultLines) { line in
                                NavigationLink {
                                    KnowledgeFaultLineDetailView(
                                        container: container,
                                        focusFaultLineID: line.id,
                                        focusMistakeID: line.relatedMistakeIDs.first
                                    )
                                } label: {
                                    FaultLineRow(line: line)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, DesignToken.Spacing.mainHorizontal)
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("knowledge.fault.navigation.title".localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.manuallyRequestAI()
                } label: {
                    Image(systemName: "sparkles")
                }
                .disabled(viewModel.isLoadingAI)
                .accessibilityLabel("knowledge.fault.ai.manual".localized())
            }
            if viewModel.aiErrorMessage != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("knowledge.fault.retry".localized()) {
                        viewModel.retryAI()
                    }
                    .disabled(viewModel.isLoadingAI)
                }
            }
        }
        .onAppear { viewModel.recompute() }
        .onChange(of: container.mistakeRepo.filteredMistakeSets) { _, _ in
            viewModel.recompute()
        }
        .containerBackground(.clear, for: .navigation)
        .debugModeContainer()
        .debugLayoutBoundsAuto()
    }

    private var overviewHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("knowledge.fault.overview.header".localized(), systemImage: "scope")
                .font(.title3.bold())
            Text("knowledge.fault.overview.description".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if viewModel.isLoadingAI {
                Label("knowledge.fault.ai.loading".localized(), systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.indigo)
            } else if viewModel.scan.usedFallback {
                Label("knowledge.fault.ai.fallback".localized(), systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("knowledge.fault.ai.autoHint".localized())
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let error = viewModel.aiErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
    }
}

struct KnowledgeFaultLineDetailView: View {
    @Environment(RepositoryContainer.self) private var environmentContainer
    @State private var viewModel: KnowledgeFaultLineViewModel
    let focusFaultLineID: String?
    let focusMistakeID: UUID?

    private var container: RepositoryContainer { environmentContainer }

    init(container: RepositoryContainer, focusFaultLineID: String? = nil, focusMistakeID: UUID? = nil) {
        self.focusFaultLineID = focusFaultLineID
        self.focusMistakeID = focusMistakeID
        _viewModel = State(initialValue: KnowledgeFaultLineViewModel.makeDefault(container: container))
    }

    private var node: MistakeKnowledgeNode? {
        if let focusMistakeID { return viewModel.node(for: focusMistakeID) }
        return viewModel.scan.nodes.first
    }

    private var faultLine: KnowledgeFaultLine? {
        if let focusFaultLineID, let line = viewModel.scan.faultLine(id: focusFaultLineID) { return line }
        if let focusMistakeID { return viewModel.faultLine(for: focusMistakeID) }
        return viewModel.scan.faultLines.first
    }

    var body: some View {
        List {
            if let node {
                Section("knowledge.fault.chain.section".localized()) {
                    KnowledgeChainView(node: node)
                }
            } else {
                Section {
                    Text("knowledge.fault.detail.noChain".localized())
                        .foregroundStyle(.secondary)
                }
            }

            if let line = faultLine {
                Section("knowledge.fault.metrics.section".localized()) {
                    KnowledgeFaultMetricsView(line: line)
                }

                Section("knowledge.fault.related.section".localized()) {
                    ForEach(line.relatedMistakes) { mistake in
                        NavigationLink {
                            MistakeSetDetailView(mistakeSet: mistake)
                                .environment(container)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mistake.title)
                                    .font(.body.weight(.semibold))
                                Text(String(format: "knowledge.fault.related.meta".localized(), mistake.subject.isEmpty ? "knowledge.fault.uncategorized".localized() : mistake.subject, Int(mistake.masteryScore * 100)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        viewModel.repairFaultLine = line
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                                .imageScale(.medium)
                            Text("knowledge.fault.repair.action".localized())
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if viewModel.isLoadingAI {
                Section {
                    ProgressView("knowledge.fault.ai.loading".localized())
                }
            } else if viewModel.scan.usedFallback {
                Section {
                    Label("knowledge.fault.ai.fallback".localized(), systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if viewModel.aiErrorMessage != nil {
                        Button("knowledge.fault.retry".localized()) { viewModel.retryAI() }
                    }
                }
            }
        }
        .navigationTitle(faultLine?.foundationConcept ?? "knowledge.fault.detail.title".localized())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $viewModel.repairFaultLine) { line in
            KnowledgeRepairTaskSheet(faultLine: line)
                .environment(container)
                .adaptiveSheet()
        }
        .onAppear { viewModel.recompute() }
        .onChange(of: container.mistakeRepo.filteredMistakeSets) { _, _ in
            viewModel.recompute()
        }
    }
}

private struct FaultLineRow: View {
    let line: KnowledgeFaultLine

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(riskColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(line.foundationConcept)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(String(format: "knowledge.fault.row.summary".localized(), line.impactMistakeCount, line.subjects.joined(separator: "、")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(line.riskScore * 100))%")
                .font(.caption.weight(.bold))
                .foregroundStyle(riskColor)
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
    }

    private var riskColor: Color {
        line.riskScore >= 0.75 ? .red : (line.riskScore >= 0.5 ? .orange : .indigo)
    }
}

private struct KnowledgeFaultMetricsView: View {
    let line: KnowledgeFaultLine

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            metric("knowledge.fault.metric.impact", "\(line.impactMistakeCount)")
            metric("knowledge.fault.metric.subjects", "\(line.subjects.count)")
            metric("knowledge.fault.metric.recurrence", "\(line.recentRecurrenceCount)")
            metric("knowledge.fault.metric.risk", "\(Int(line.riskScore * 100))%")
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.bold())
            Text(title.localized()).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KnowledgeChainView: View {
    let node: MistakeKnowledgeNode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            chainNode(title: node.targetConcept, role: "knowledge.fault.chain.target", color: .blue)
            ForEach(Array(node.prerequisiteConcepts.enumerated()), id: \.offset) { _, prerequisite in
                chainArrow
                chainNode(title: prerequisite, role: "knowledge.fault.chain.prerequisite", color: .orange)
            }
            chainArrow
            chainNode(title: node.foundationConcept, role: "knowledge.fault.chain.foundation", color: .purple)

            if !node.evidence.isEmpty {
                Text(node.evidence.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: "knowledge.fault.chain.accessibility".localized(), node.targetConcept, node.foundationConcept))
    }

    private func chainNode(title: String, role: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(role.localized()).font(.caption).foregroundStyle(.secondary)
                Text(title).font(.body.weight(.semibold))
            }
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private var chainArrow: some View {
        HStack {
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1, height: 14)
                .padding(.leading, 16)
            Image(systemName: "arrow.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(height: 22)
    }
}

struct KnowledgeDepthEntrySection: View {
    let mistakeID: UUID
    let container: RepositoryContainer

    private var node: MistakeKnowledgeNode? {
        KnowledgeFaultLineEngine.localNodes(for: container.mistakeRepo.filteredMistakeSets)
            .first { $0.mistakeID == mistakeID }
    }

    var body: some View {
        Section("knowledge.fault.depth.section".localized()) {
            if let node {
                NavigationLink {
                    KnowledgeFaultLineDetailView(container: container, focusMistakeID: mistakeID)
                        .environment(container)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "scope")
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("knowledge.fault.depth.title".localized())
                                .font(.body.weight(.semibold))
                            Text(String(format: "knowledge.fault.depth.summary".localized(), node.targetConcept, node.foundationConcept))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                }
            } else {
                Text("knowledge.fault.detail.noChain".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
