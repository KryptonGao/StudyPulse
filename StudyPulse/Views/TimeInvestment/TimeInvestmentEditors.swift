import SwiftUI

struct TimeInvestmentTargetPicker: View {
    @ObservedObject var viewModel: TimeInvestmentViewModel
    @Binding var selection: InvestmentTarget?

    var body: some View {
        Picker("time.investment.project".localized(), selection: $selection) {
            Text("time.investment.chooseProject".localized())
                .tag(nil as InvestmentTarget?)
            ForEach(viewModel.activeSubjects) { subject in
                Text(subject.name)
                    .tag(InvestmentTarget.subject(subject.id) as InvestmentTarget?)
                ForEach(viewModel.children(of: nil, subjectID: subject.id)) { task in
                    Text("↳ \(task.name)")
                        .tag(InvestmentTarget.subTask(task.id) as InvestmentTarget?)
                    ForEach(viewModel.children(of: task.id, subjectID: subject.id)) { child in
                        Text("  ↳ \(child.name)")
                            .tag(InvestmentTarget.subTask(child.id) as InvestmentTarget?)
                    }
                }
            }
        }
    }
}

struct TimeInvestmentSubjectEditor: View {
    @Environment(\.dismiss) private var dismiss
    let editing: TimeInvestmentSubject?
    let nextSortOrder: Int
    let onSave: (TimeInvestmentSubject) -> Void

    @State private var name: String
    @State private var symbolName: String
    @State private var theme: TimeInvestmentTheme
    @State private var startDate: Date

    private let symbols = [
        "book.closed.fill", "cross.case.fill", "atom", "function",
        "character.book.closed.fill", "laptopcomputer", "music.note", "paintbrush.fill"
    ]

    init(
        editing: TimeInvestmentSubject?,
        nextSortOrder: Int,
        onSave: @escaping (TimeInvestmentSubject) -> Void
    ) {
        self.editing = editing
        self.nextSortOrder = nextSortOrder
        self.onSave = onSave
        _name = State(initialValue: editing?.name ?? "")
        _symbolName = State(initialValue: editing?.symbolName ?? "book.closed.fill")
        _theme = State(initialValue: editing?.theme ?? .ocean)
        _startDate = State(initialValue: editing?.startDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("time.investment.project".localized()) {
                    TextField("time.investment.projectName".localized(), text: $name)
                    DatePicker(
                        "time.investment.startDate".localized(),
                        selection: $startDate,
                        displayedComponents: .date
                    )
                }
                Section("time.investment.icon".localized()) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                        ForEach(symbols, id: \.self) { symbol in
                            Button {
                                symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 48, height: 44)
                                    .background(
                                        symbolName == symbol ? Color.accentColor.opacity(0.16) : .clear,
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(symbolName == symbol ? .isSelected : [])
                        }
                    }
                }
                Section("time.investment.color".localized()) {
                    HStack {
                        ForEach(TimeInvestmentTheme.allCases, id: \.self) { value in
                            Button {
                                theme = value
                            } label: {
                                Circle()
                                    .fill(Color(hex: value.colorHex))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if theme == value {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(value == .sunshine ? .black : .white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(
                editing == nil
                    ? "time.investment.addProject".localized()
                    : "time.investment.editProject".localized()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized()) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save".localized()) {
                        var value = editing ?? TimeInvestmentSubject(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            sortOrder: nextSortOrder
                        )
                        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        value.symbolName = symbolName
                        value.theme = theme
                        value.startDate = startDate
                        onSave(value)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct SubTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    let subjectID: UUID
    let parentID: UUID?
    let editing: SubTask?
    let allSubTasks: [SubTask]
    let onSave: (SubTask) -> Void
    @State private var name: String
    @State private var selectedParentID: UUID?

    init(
        subjectID: UUID,
        parentID: UUID?,
        editing: SubTask?,
        allSubTasks: [SubTask],
        onSave: @escaping (SubTask) -> Void
    ) {
        self.subjectID = subjectID
        self.parentID = parentID
        self.editing = editing
        self.allSubTasks = allSubTasks
        self.onSave = onSave
        _name = State(initialValue: editing?.name ?? "")
        _selectedParentID = State(initialValue: editing?.parentSubTaskID ?? parentID)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("time.investment.subprojectName".localized(), text: $name)
                Picker("time.investment.parent".localized(), selection: $selectedParentID) {
                    Text("time.investment.rootProject".localized()).tag(nil as UUID?)
                    ForEach(
                        allSubTasks.filter {
                            $0.subjectID == subjectID
                                && $0.id != editing?.id
                                && $0.parentSubTaskID == nil
                        }
                    ) { task in
                        Text(task.name).tag(task.id as UUID?)
                    }
                }
            }
            .navigationTitle(
                editing == nil
                    ? "time.investment.addSubproject".localized()
                    : "time.investment.editSubproject".localized()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized()) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save".localized()) {
                        var value = editing ?? SubTask(
                            subjectID: subjectID,
                            parentSubTaskID: selectedParentID,
                            name: name,
                            sortOrder: allSubTasks.filter { $0.subjectID == subjectID }.count
                        )
                        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        value.parentSubTaskID = selectedParentID
                        onSave(value)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct GoalRewardEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TimeInvestmentViewModel
    let onSave: (GoalReward) -> Void
    @State private var title = ""
    @State private var symbolName = "gift.fill"
    @State private var target: InvestmentTarget?
    @State private var thresholdHours = 10.0

    var body: some View {
        NavigationStack {
            Form {
                TextField("time.investment.rewardName".localized(), text: $title)
                TextField("time.investment.rewardIcon".localized(), text: $symbolName)
                TimeInvestmentTargetPicker(viewModel: viewModel, selection: $target)
                Section {
                    Stepper(value: $thresholdHours, in: 0.5...10_000, step: 0.5) {
                        LabeledContent(
                            "time.investment.targetHours".localized(),
                            value: thresholdHours.formatted(.number.precision(.fractionLength(0...1)))
                        )
                    }
                }
            }
            .navigationTitle("time.investment.addReward".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized()) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save".localized()) {
                        guard let target else { return }
                        onSave(
                            GoalReward(
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                symbolName: symbolName.isEmpty ? "gift.fill" : symbolName,
                                target: target,
                                thresholdSeconds: Int(thresholdHours * 3600)
                            )
                        )
                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || target == nil
                    )
                }
            }
        }
    }
}

struct StudySessionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let existing: StudySession?
    @ObservedObject var viewModel: TimeInvestmentViewModel
    let onSave: (StudySession?, InvestmentTarget, Date, Int) -> Void
    @State private var target: InvestmentTarget?
    @State private var startDate: Date
    @State private var durationMinutes: Int

    init(
        existing: StudySession?,
        viewModel: TimeInvestmentViewModel,
        onSave: @escaping (StudySession?, InvestmentTarget, Date, Int) -> Void
    ) {
        self.existing = existing
        self.viewModel = viewModel
        self.onSave = onSave
        _target = State(initialValue: existing?.investmentTarget)
        _startDate = State(initialValue: existing?.startDate ?? .now)
        _durationMinutes = State(initialValue: max(1, (existing?.durationSeconds ?? 25 * 60) / 60))
    }

    var body: some View {
        NavigationStack {
            Form {
                TimeInvestmentTargetPicker(viewModel: viewModel, selection: $target)
                DatePicker(
                    "time.investment.sessionStart".localized(),
                    selection: $startDate
                )
                Stepper(value: $durationMinutes, in: 1...(24 * 60)) {
                    LabeledContent(
                        "time.investment.duration".localized(),
                        value: TimeInvestmentFormatter.compactDuration(seconds: durationMinutes * 60)
                    )
                }
            }
            .navigationTitle(
                existing == nil
                    ? "time.investment.manualLog".localized()
                    : "time.investment.editSession".localized()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized()) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save".localized()) {
                        guard let target else { return }
                        onSave(existing, target, startDate, durationMinutes)
                        dismiss()
                    }
                    .disabled(target == nil)
                }
            }
        }
    }
}

struct UnassignedSessionsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TimeInvestmentViewModel
    @State private var selectedIDs = Set<UUID>()
    @State private var target: InvestmentTarget?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(viewModel.unassignedSessions) { session in
                    Button {
                        if selectedIDs.contains(session.id) {
                            selectedIDs.remove(session.id)
                        } else {
                            selectedIDs.insert(session.id)
                        }
                    } label: {
                        HStack {
                            Image(
                                systemName: selectedIDs.contains(session.id)
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .foregroundStyle(selectedIDs.contains(session.id) ? Color.accentColor : .secondary)
                            VStack(alignment: .leading) {
                                Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.primary)
                                Text(TimeInvestmentFormatter.compactDuration(seconds: session.durationSeconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: DesignToken.Spacing.small) {
                    TimeInvestmentTargetPicker(viewModel: viewModel, selection: $target)
                        .pickerStyle(.menu)
                    Button {
                        guard let target else { return }
                        viewModel.assign(sessionIDs: selectedIDs, to: target)
                        selectedIDs.removeAll()
                        if viewModel.unassignedSessions.isEmpty { dismiss() }
                    } label: {
                        Text(
                            String(
                                format: "time.investment.assignSelected".localized(),
                                selectedIDs.count
                            )
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIDs.isEmpty || target == nil)
                }
                .padding(DesignToken.Spacing.large)
                .background(.bar)
            }
            .navigationTitle("time.investment.unassigned".localized())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized()) { dismiss() }
                }
            }
        }
    }
}
