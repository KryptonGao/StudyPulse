//
//  PhaseManagementView.swift
//  StudyPulse
//
//  学期/假期阶段管理列表:创建、编辑、归档、删除、切换激活。
//  Phase management: create, edit, archive, delete, switch active.
//

import SwiftUI
import os

struct PhaseManagementView: View {
    @Environment(RepositoryContainer.self) private var container

    @State private var showingNewPhase = false
    @State private var editingPhase: StudyPhase? = nil
    @State private var showingFirstPhasePrompt = false
    @State private var pendingNewPhase: StudyPhase? = nil
    @State private var showArchived: Bool = false

    var body: some View {
        List {
            activeSection
            archivedSection
            overviewSection
        }
        .navigationTitle("Study Phases".localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingNewPhase = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add".localized())
            }
        }
        .containerBackground(.clear, for: .navigation)
        .debugModeContainer()
        .debugLayoutBoundsAuto()
        .sheet(isPresented: $showingNewPhase) {
            PhaseEditView(phase: nil) { newPhase, assignExisting in
                handleNewPhase(newPhase, assignExisting: assignExisting)
            }
        }
        .sheet(item: $editingPhase) { phase in
            PhaseEditView(phase: phase)
        }
        .alert("Assign existing data?".localized(), isPresented: $showingFirstPhasePrompt) {
            Button("Assign".localized()) {
                if let p = pendingNewPhase {
                    let result = container.phaseRepo.assignUnassignedDataToPhase(p.id)
                    Log.data.info("弹窗确认归类 / Prompt-confirmed bulk assign: g=\(result.grades) m=\(result.mistakes) e=\(result.exams) c=\(result.comprehensiveExams) t=\(result.tasks)")
                }
                pendingNewPhase = nil
            }
            Button("Keep Unassigned".localized(), role: .cancel) {
                pendingNewPhase = nil
            }
        } message: {
            if let p = pendingNewPhase {
                Text("Move all unassigned grades, mistakes, exams and tasks into \"\(p.name)\"?".localized())
            } else {
                Text("Move unassigned data into the new phase?".localized())
            }
        }
    }

    // MARK: - Active phases

    private var activePhases: [StudyPhase] {
        container.phaseRepo.phases.filter { !$0.isArchived }
    }

    private var archivedPhases: [StudyPhase] {
        container.phaseRepo.phases.filter { $0.isArchived }
    }

    @ViewBuilder
    private var activeSection: some View {
        Section(header: Text("Active".localized())) {
            if activePhases.isEmpty {
                Text("No phases yet. Tap + to create your first semester / break.".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activePhases) { phase in
                    PhaseRow(
                        phase: phase,
                        isActive: container.phaseRepo.activePhase?.id == phase.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if container.phaseRepo.activePhase?.id == phase.id {
                            container.phaseRepo.activate(nil)
                        } else {
                            container.phaseRepo.activate(phase)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            container.phaseRepo.delete(phase)
                        } label: {
                            Label("Delete".localized(), systemImage: "trash")
                        }
                        Button {
                            container.phaseRepo.setArchived(phase, archived: true)
                        } label: {
                            Label("Archive".localized(), systemImage: "archivebox")
                        }
                        .tint(.orange)
                        Button {
                            editingPhase = phase
                        } label: {
                            Label("Edit".localized(), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
    }

    // MARK: - Archived

    @ViewBuilder
    private var archivedSection: some View {
        if !archivedPhases.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $showArchived) {
                    ForEach(archivedPhases) { phase in
                        PhaseRow(phase: phase, isActive: false)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingPhase = phase
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    container.phaseRepo.delete(phase)
                                } label: {
                                    Label("Delete".localized(), systemImage: "trash")
                                }
                                Button {
                                    container.phaseRepo.setArchived(phase, archived: false)
                                } label: {
                                    Label("Unarchive".localized(), systemImage: "tray.and.arrow.up")
                                }
                                .tint(.green)
                            }
                    }
                } label: {
                    Text("Archived (\(archivedPhases.count))".localized())
                }
            }
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        Section(header: Text("Overview".localized())) {
            HStack {
                Text("Total Phases".localized())
                Spacer()
                Text("\(container.phaseRepo.phases.count)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Active".localized())
                Spacer()
                Text("\(activePhases.count)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Archived".localized())
                Spacer()
                Text("\(archivedPhases.count)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Unassigned Records".localized())
                Spacer()
                Text("\(container.phaseRepo.unassignedRecordCount)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - First-phase prompt

    /// 在用户创建第一个 phase 后,如果存在未归类数据,弹窗询问是否归类。
    private func handleNewPhase(_ newPhase: StudyPhase, assignExisting: Bool) {
        if assignExisting && container.phaseRepo.hasUnassignedData {
            let result = container.phaseRepo.assignUnassignedDataToPhase(newPhase.id)
            Log.data.info("弹窗勾选归类 / Toggle-bulk assign: g=\(result.grades) m=\(result.mistakes) e=\(result.exams) c=\(result.comprehensiveExams) t=\(result.tasks)")
        }
    }
}

// MARK: - Row

private struct PhaseRow: View {
    let phase: StudyPhase
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.5))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(phase.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if phase.isArchived {
                        Text("Archived".localized())
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(dateRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !phase.goals.isEmpty {
                    Text("\(phase.goals.count) " + "goal".localized() + (phase.goals.count > 1 ? "s" : ""))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let s = formatter.string(from: phase.startDate)
        let e = formatter.string(from: phase.endDate)
        return "\(s) – \(e)"
    }
}
