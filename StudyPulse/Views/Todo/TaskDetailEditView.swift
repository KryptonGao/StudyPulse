//
//  TaskDetailEditView.swift
//  StudyPulse
//
//  任务编辑页：复用 NewTaskView 字段,根据是否已同步到系统 Reminders 决定是 add 还是 update。
//  Task edit page: shares fields with NewTaskView, decides between add / update for Reminders based on whether the task is already synced.
//

import SwiftUI

struct TaskDetailEditView: View {
    let originalTask: TaskItem
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    // 表单状态
    @State private var title: String
    @State private var type: TaskType
    @State private var subject: String
    @State private var importance: Int
    @State private var notes: String
    @State private var dueDate: Date
    @State private var reminderDate: Date

    /// 是否仍然要同步到系统 Reminders（如果原本同步过，编辑页默认仍开启）
    @State private var syncToReminders: Bool
    /// Reminders 状态：false = 尚未同步 / true = 已同步（编辑时只更新 Reminder，不再新建）
    private let isAlreadySynced: Bool

    @State private var showingResultAlert: Bool = false
    @State private var resultAlertMessage: String = ""
    @State private var isSaving: Bool = false

    init(task: TaskItem) {
        self.originalTask = task
        _title = State(initialValue: task.title)
        _type = State(initialValue: task.type)
        _subject = State(initialValue: task.subject)
        _importance = State(initialValue: task.importance)
        _notes = State(initialValue: task.notes)
        _dueDate = State(initialValue: task.dueDate)
        _reminderDate = State(initialValue: task.reminderDate)
        let synced = task.reminderEventId != nil
        self.isAlreadySynced = synced
        _syncToReminders = State(initialValue: synced)
    }

    private var availableSubjects: [String] {
        container.subjectRepo.subjects.filter { $0.enabled }.map { $0.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Task Type".localized())) {
                    Picker("Type".localized(), selection: $type) {
                        Text("Homework".localized()).tag(TaskType.homework)
                        Text("Reading".localized()).tag(TaskType.reading)
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Basic Info".localized())) {
                    TextField("Task Title".localized(), text: $title)

                    if availableSubjects.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("No subjects enabled. Add subjects in Settings → Profile.".localized())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Subject".localized(), selection: $subject) {
                            Text("None".localized()).tag("")
                            ForEach(availableSubjects, id: \.self) { s in
                                Text(s.localized()).tag(s)
                            }
                        }
                    }
                }

                Section(header: Text("Schedule".localized()),
                        footer: Text("Set the deadline and the time you want to be reminded. The reminder time is usually earlier than the deadline.".localized())) {
                    DatePicker("Due Date".localized(), selection: $dueDate)
                    DatePicker("Reminder Time".localized(), selection: $reminderDate,
                               in: ...dueDate)
                }

                Section(header: Text("Assessment".localized())) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Importance".localized())
                            Spacer()
                            Text("\(importance) / 5".localized())
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            ForEach(1...5, id: \.self) { index in
                                Image(systemName: index <= importance ? "star.fill" : "star")
                                    .foregroundColor(index <= importance ? .yellow : .gray)
                                    .font(.title3)
                                    .onTapGesture {
                                        withAnimation { importance = index }
                                    }
                            }
                        }
                    }
                }

                Section(header: Text("Notes".localized()),
                        footer: Text("Optional details.".localized())) {
                    TextField("Notes".localized(), text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section(header: Text("Reminders".localized()),
                        footer: Text(syncToReminders
                                     ? (isAlreadySynced
                                        ? "Update the linked Reminder in the system Reminders app. If the original Reminder was deleted externally, a new one will be created.".localized()
                                        : "A new reminder will be created in the system Reminders app on save.".localized())
                                     : "Disable this to keep the task only inside StudyPulse. The linked Reminder, if any, will be removed.".localized())) {
                    Toggle("Sync with System Reminders".localized(), isOn: $syncToReminders)
                }
            }
            .adaptiveForm()
            .navigationTitle("Edit Task".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel".localized()) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save".localized()) {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .alert("Reminders".localized(), isPresented: $showingResultAlert) {
                Button("OK".localized()) {
                    showingResultAlert = false
                    dismiss()
                }
            } message: {
                Text(resultAlertMessage)
            }
            .containerBackground(.clear, for: .navigation)
            .debugModeContainer()
            .debugLayoutBoundsAuto()
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        isSaving = true
        Haptics.success()

        var updated = originalTask
        updated.title = trimmedTitle
        updated.type = type
        updated.subject = subject
        updated.importance = importance
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.dueDate = dueDate
        updated.reminderDate = reminderDate
        // isCompleted 维持原值（编辑时不应被覆盖）

        let wasSynced = isAlreadySynced

        // 1. 关闭 Reminders 同步：删除已有 Reminder
        if !syncToReminders {
            if let oldId = originalTask.reminderEventId {
                Task {
                    try? await CalendarManager.shared.removeTaskFromReminders(calendarItemId: oldId)
                }
            }
            updated.reminderEventId = nil
            updated.reminderCalendarId = nil
            container.taskRepo.update(updated, reminderResult: nil)
            isSaving = false
            dismiss()
            return
        }

        // 2. 开启 Reminders 同步：尝试 update（或重建）
        Task {
            do {
                if wasSynced,
                   let oldId = originalTask.reminderEventId,
                   let oldCalId = originalTask.reminderCalendarId {
                    // 已有 reminder：尝试更新；若 update 返回 false（reminder 已被外部删除）则新建
                    let updatedOK = try await CalendarManager.shared.updateTaskInReminders(
                        calendarItemId: oldId,
                        calendarId: oldCalId,
                        title: trimmedTitle,
                        dueDate: dueDate,
                        alarmDate: reminderDate,
                        notes: updated.notes,
                        subject: subject.isEmpty ? nil : subject,
                        isCompleted: updated.isCompleted
                    )
                    if !updatedOK {
                        // 旧的 Reminder 已被外部删除,回退到新建
                        let newResult = try await CalendarManager.shared.addTaskToReminders(
                            title: trimmedTitle,
                            dueDate: dueDate,
                            alarmDate: reminderDate,
                            notes: updated.notes,
                            subject: subject.isEmpty ? nil : subject
                        )
                        await MainActor.run {
                            container.taskRepo.update(updated, reminderResult: newResult)
                            isSaving = false
                            resultAlertMessage = "Saved and re-linked to system Reminders.".localized()
                            showingResultAlert = true
                        }
                        return
                    }
                    await MainActor.run {
                        // update 成功,identifier 不变
                        container.taskRepo.update(updated, reminderResult: nil)
                        isSaving = false
                        resultAlertMessage = "Saved.".localized()
                        showingResultAlert = true
                    }
                } else {
                    // 之前未同步:新建
                    let newResult = try await CalendarManager.shared.addTaskToReminders(
                        title: trimmedTitle,
                        dueDate: dueDate,
                        alarmDate: reminderDate,
                        notes: updated.notes,
                        subject: subject.isEmpty ? nil : subject
                    )
                    await MainActor.run {
                        container.taskRepo.update(updated, reminderResult: newResult)
                        isSaving = false
                        resultAlertMessage = "Saved and added to system Reminders.".localized()
                        showingResultAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    // Reminders 失败:仍把任务存到本地,但清掉 Reminders 关联
                    var fallback = updated
                    fallback.reminderEventId = nil
                    fallback.reminderCalendarId = nil
                    container.taskRepo.update(fallback, reminderResult: nil)
                    isSaving = false
                    resultAlertMessage = "Saved to StudyPulse, but Reminders sync failed: \(error.localizedDescription)"
                    showingResultAlert = true
                }
            }
        }
    }
}

#Preview {
    let mockContainer = RepositoryContainer()
    let task = TaskItem(
        title: "Math Homework Ch.3",
        type: .homework,
        dueDate: Date().addingTimeInterval(86400 * 2),
        reminderDate: Date().addingTimeInterval(86400),
        subject: "Mathematics",
        importance: 4,
        notes: "Problems 1-20"
    )
    mockContainer.taskRepo.add([task])
    return TaskDetailEditView(task: task)
        .environment(mockContainer)
}
