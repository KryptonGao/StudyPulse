//
//  NewTaskView.swift
//  StudyPulse
//
//  新建作业 / 阅读材料表单：标题、类型、科目、截止日期、提醒时间、重要程度、备注、是否同步到系统 Reminders。
//  Form for adding a new homework / reading task with type / subject / due date / reminder time /
//  importance / notes / sync to system Reminders options.
//

import SwiftUI

struct NewTaskView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    /// 预设类型（作业 / 阅读），由父视图传入；用户在表单内仍可切换
    let initialType: TaskType

    // 表单状态
    @State private var title: String = ""
    @State private var type: TaskType
    @State private var subject: String = ""
    @State private var importance: Int = 3
    @State private var notes: String = ""
    // 默认截止时间 = 明天 18:00；提醒时间 = 截止前 1 小时
    @State private var dueDate: Date
    @State private var reminderDate: Date

    @State private var syncToReminders: Bool = true
    @State private var showingResultAlert: Bool = false
    @State private var resultAlertMessage: String = ""
    @State private var isSaving: Bool = false

    init(initialType: TaskType) {
        self.initialType = initialType
        _type = State(initialValue: initialType)

        let now = Date()
        let cal = Calendar.current
        let defaultDue = cal.date(bySettingHour: 18, minute: 0, second: 0,
                                  of: cal.date(byAdding: .day, value: 1, to: now) ?? now) ?? now
        let defaultReminder = cal.date(byAdding: .hour, value: -1, to: defaultDue) ?? defaultDue
        _dueDate = State(initialValue: defaultDue)
        _reminderDate = State(initialValue: defaultReminder)
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
                                     ? "A reminder will be created in the system Reminders app with the schedule above. The app will request Reminders permission on first save.".localized()
                                     : "Skip syncing to system Reminders. You can manage this task only inside StudyPulse.".localized())) {
                    Toggle("Add to System Reminders".localized(), isOn: $syncToReminders)
                }
            }
            .adaptiveForm()
            .navigationTitle("New Task".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel".localized()) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save".localized()) {
                        saveTask()
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

    private func saveTask() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        isSaving = true

        let task = TaskItem(
            title: trimmedTitle,
            type: type,
            dueDate: dueDate,
            reminderDate: reminderDate,
            subject: subject,
            importance: importance,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isCompleted: false
        )

        if !syncToReminders {
            container.addTask(task, syncToReminders: false)
            Haptics.success()
            isSaving = false
            dismiss()
            return
        }

        Task {
            do {
                let result = try await CalendarManager.shared.addTaskToReminders(
                    title: trimmedTitle,
                    dueDate: dueDate,
                    alarmDate: reminderDate,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    subject: subject.isEmpty ? nil : subject
                )
                await MainActor.run {
                    container.addTask(task, syncToReminders: true, reminderResult: result)
                    Haptics.success()
                    isSaving = false
                    resultAlertMessage = "Saved and added to system Reminders.".localized()
                    showingResultAlert = true
                }
            } catch {
                await MainActor.run {
                    // Reminders 同步失败：仍然把任务存到本地
                    container.addTask(task, syncToReminders: false)
                    Haptics.success()
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
    mockContainer.subjectRepo.subjects = [
        Subject(name: "Mathematics", enabled: true),
        Subject(name: "Physics", enabled: true)
    ]
    return NewTaskView(initialType: .homework)
        .environment(mockContainer)
}
