import SwiftUI

/// 1–2 step goal configuration before starting a focus session.
struct SessionGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RepositoryContainer.self) private var container
    @Bindable var timer: StudyTimerManager

    // Draft state - initialized from timer.draftGoal or defaults.
    @State private var selectedSource: StudySessionGoalSource = .custom
    @State private var selectedSourceID: String?
    @State private var selectedSourceTitle: String?
    @State private var title: String = ""
    @State private var targetValue: Double = 20
    @State private var unit: StudySessionGoalUnit = .count
    @State private var customUnitLabel: String = ""
    @State private var searchText: String = ""

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && targetValue > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sourcePicker
                    linkedEntitySection
                    titleSection
                    targetSection
                    unitSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Set Goal".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized()) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save".localized()) { saveAndDismiss() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .safeAreaInset(edge: .bottom) {
                footerActions
            }
        }
        .onAppear { hydrate() }
    }

    // MARK: - Source picker

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Source".localized())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach([StudySessionGoalSource.todo, .mistakeCluster, .knowledgePoint, .timeInvestment, .custom], id: \.self) { src in
                        sourceChip(src)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func sourceChip(_ src: StudySessionGoalSource) -> some View {
        let selected = selectedSource == src
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedSource = src
                // reset linkage when switching away from entity-bound sources; keep title if custom
                if src == .custom {
                    selectedSourceID = nil
                    selectedSourceTitle = nil
                } else {
                    // keep existing link but ensure title reflects source if empty
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: src.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(selected ? .white : .primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(selected ? Color.accentColor : Color(.tertiarySystemFill)))
                Text(src.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundColor(selected ? .accentColor : .primary)
            }
            .frame(width: 72)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Linked entity

    @ViewBuilder
    private var linkedEntitySection: some View {
        if selectedSource != .custom {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(linkedSectionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if selectedSourceID != nil {
                        Button("Clear".localized()) {
                            selectedSourceID = nil
                            selectedSourceTitle = nil
                        }
                        .font(.caption)
                    }
                }
                // quick search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search".localized(), text: $searchText)
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))

                let items = filteredLinkedItems
                if items.isEmpty {
                    Text("No matches".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(items.prefix(8), id: \.id) { item in
                            Button {
                                selectedSourceID = item.id
                                selectedSourceTitle = item.title
                                if title.trimmingCharacters(in: .whitespaces).isEmpty {
                                    title = item.title
                                }
                                // sensible default target by source
                                if targetValue == 20 || targetValue == 1 {
                                    switch selectedSource {
                                    case .todo: targetValue = 1
                                    case .mistakeCluster: targetValue = 10
                                    case .knowledgePoint: targetValue = 5
                                    case .timeInvestment: targetValue = 1
                                    default: break
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: item.icon)
                                        .foregroundColor(.secondary)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(Color(.tertiarySystemFill)))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                                            Text(subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if selectedSourceID == item.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selectedSourceID == item.id ? Color.accentColor.opacity(0.10) : Color(.tertiarySystemFill))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    private var linkedSectionTitle: String {
        switch selectedSource {
        case .todo: return "Todo".localized()
        case .mistakeCluster: return "Mistake Cluster".localized()
        case .knowledgePoint: return "Knowledge Point".localized()
        case .timeInvestment: return "Project".localized()
        case .custom: return ""
        }
    }

    private struct LinkedItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let icon: String
    }

    private var filteredLinkedItems: [LinkedItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let all: [LinkedItem]
        switch selectedSource {
        case .todo:
            all = todoItems
        case .mistakeCluster:
            all = mistakeClusterItems
        case .knowledgePoint:
            all = knowledgePointItems
        case .timeInvestment:
            all = projectItems
        case .custom:
            all = []
        }
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(q) || ($0.subtitle?.lowercased().contains(q) ?? false) }
    }

    private var todoItems: [LinkedItem] {
        let entries = container.todoEntries(includeCompleted: false)
            .sorted { $0.date < $1.date }
            .prefix(20)
        return entries.map {
            LinkedItem(id: $0.id.uuidString, title: $0.title, subtitle: $0.subject, icon: kindIcon($0.kind))
        }
    }

    private func kindIcon(_ kind: TodoEntryKind) -> String {
        switch kind {
        case .exam: return "calendar"
        case .comprehensiveExam: return "square.stack.3d.up"
        case .homework: return "pencil.and.list.clipboard"
        case .reading: return "book"
        case .routine: return "repeat"
        }
    }

    private var mistakeClusterItems: [LinkedItem] {
        // Group mistakes by subject.
        var map: [String: Int] = [:]
        for m in container.mistakeRepo.mistakeSets {
            map[m.subject, default: 0] += 1
        }
        return map.map { (subject, count) in
            LinkedItem(id: "mistakeCluster:\(subject)", title: subject.isEmpty ? "Mistakes".localized() : subject, subtitle: "\(count) mistakes".localized(), icon: "exclamationmark.triangle")
        }.sorted { $0.title < $1.title }
    }

    private var knowledgePointItems: [LinkedItem] {
        var tagCount: [String: Int] = [:]
        for m in container.mistakeRepo.mistakeSets {
            for t in m.tags where !t.trimmingCharacters(in: .whitespaces).isEmpty {
                tagCount[t, default: 0] += 1
            }
        }
        if tagCount.isEmpty {
            // fallback: use subjects as knowledge points
            return mistakeClusterItems.map { LinkedItem(id: "kp:\($0.title)", title: $0.title, subtitle: $0.subtitle, icon: "lightbulb") }
        }
        return tagCount.map { (tag, count) in
            LinkedItem(id: "kp:\(tag)", title: tag, subtitle: "\(count) mistakes".localized(), icon: "lightbulb")
        }.sorted { $0.title < $1.title }
    }

    private var projectItems: [LinkedItem] {
        var items: [LinkedItem] = []
        for s in container.timeInvestmentRepo.subjects.filter({ !$0.isArchived }) {
            items.append(LinkedItem(id: s.id.uuidString, title: s.name, subtitle: s.symbolName, icon: s.symbolName))
            for t in container.timeInvestmentRepo.subTasks.filter({ $0.subjectID == s.id && !$0.isArchived }) {
                items.append(LinkedItem(id: t.id.uuidString, title: "↳ \(t.name)", subtitle: s.name, icon: "folder"))
            }
        }
        return items
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Goal Title".localized())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("e.g. 20 problems · Review functions".localized(), text: $title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Target

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Target Value".localized())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Stepper(value: $targetValue, in: 1...999, step: 1) {
                    Text("\(Int(targetValue)) \(unitLabel)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .labelsHidden()
                Text("\(Int(targetValue)) \(unitLabel)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
                    .frame(minWidth: 90)
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        targetValue = max(1, targetValue - 1)
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 28)).foregroundStyle(.secondary)
                    }
                    Button {
                        targetValue = min(999, targetValue + 1)
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 28)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var unitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unit".localized())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Unit".localized(), selection: $unit) {
                ForEach(StudySessionGoalUnit.allCases) { u in
                    Text(u.displayName).tag(u)
                }
            }
            .pickerStyle(.segmented)
            if unit == .custom {
                TextField("Custom unit (e.g. pages)".localized(), text: $customUnitLabel)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var unitLabel: String {
        if unit == .custom, !customUnitLabel.trimmingCharacters(in: .whitespaces).isEmpty {
            return customUnitLabel
        }
        return unit.shortLabel
    }

    private var footerActions: some View {
        VStack(spacing: 10) {
            Button(action: saveAndDismiss) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save Goal".localized())
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(canSave ? Color.accentColor : Color(.systemGray4)))
                .foregroundColor(.white)
            }
            .disabled(!canSave)
            Button("Start without goal".localized()) {
                timer.clearDraftGoal()
                dismiss()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Hydrate / Save

    private func hydrate() {
        if let g = timer.draftGoal {
            selectedSource = g.source
            selectedSourceID = g.sourceID
            selectedSourceTitle = g.sourceTitle
            title = g.title
            targetValue = g.targetValue
            unit = g.unit
            customUnitLabel = g.customUnitLabel ?? ""
        } else {
            // sensible defaults
            selectedSource = .custom
            title = ""
            targetValue = 20
            unit = .count
        }
    }

    private func saveAndDismiss() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        let goal = StudySessionGoal(
            title: trimmedTitle,
            source: selectedSource,
            sourceID: selectedSourceID,
            sourceTitle: selectedSourceTitle,
            unit: unit,
            customUnitLabel: unit == .custom ? customUnitLabel.trimmingCharacters(in: .whitespaces) : nil,
            targetValue: targetValue
        )
        timer.selectGoal(goal)
        dismiss()
    }
}

#Preview {
    SessionGoalSheet(timer: StudyTimerManager.shared)
        .environment(RepositoryContainer())
}
