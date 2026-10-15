//
//  DataAdminView.swift
//  StudyPulse
//

import SwiftUI

// MARK: - DataAdminView
struct DataAdminView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Data Admin".localized())) {
                    NavigationLink {
                        GradeAdminView()
                    } label: {
                        Label("Grades (\(container.gradeRepo.grades.count))".localized(), systemImage: "chart.bar.fill")
                    }

                    NavigationLink {
                        ExamAdminView()
                    } label: {
                        Label("Exams (\(container.examRepo.examSets.count + container.examRepo.comprehensiveExamSets.count))".localized(), systemImage: "calendar")
                    }

                    NavigationLink {
                        MistakeAdminView()
                    } label: {
                        Label("Mistakes (\(container.mistakeRepo.mistakeSets.count))".localized(), systemImage: "book.fill")
                    }
                }
            }
            .adaptiveForm()
            .navigationTitle("Data Admin".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized()) { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}

// MARK: - GradeAdminView
struct GradeAdminView: View {
    @Environment(RepositoryContainer.self) private var container
    @State private var editingGrade: Grade?

    var body: some View {
        List {
            if container.gradeRepo.grades.isEmpty {
                Text("No grades".localized()).foregroundColor(.secondary)
            } else {
                ForEach(container.gradeRepo.grades) { grade in
                    Button {
                        editingGrade = grade
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(grade.subject)
                                    .scaledFont(size: 15, weight: .medium)
                                Text(grade.examName)
                                    .scaledFont(size: 12)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1f", grade.score))
                                    .scaledFont(size: 16, weight: .bold, design: .monospaced)
                                Text(grade.date.formatted(date: .numeric, time: .omitted))
                                    .scaledFont(size: 11)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for i in indexSet.sorted(by: >) {
                        container.deleteGrade(container.gradeRepo.grades[i])
                    }
                }
            }
        }
        .navigationTitle("Grades".localized())
        .adaptiveMaxWidth(820)
        .sheet(item: $editingGrade) { grade in
            GradeEditSheet(grade: grade) { updated in
                container.gradeRepo.update(updated)
                editingGrade = nil
            }
        }
    }
}

// MARK: - ExamAdminView
struct ExamAdminView: View {
    @Environment(RepositoryContainer.self) private var container
    @State private var editingExam: Exam?
    @State private var editingCompExam: comprehensiveExam?

    var body: some View {
        List {
            if !container.examRepo.examSets.isEmpty {
                Section(header: Text("Regular Exams (\(container.examRepo.examSets.count))".localized())) {
                    ForEach(container.examRepo.examSets) { exam in
                        Button {
                            editingExam = exam
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exam.examName)
                                        .scaledFont(size: 15, weight: .medium)
                                    Text(exam.subject)
                                        .scaledFont(size: 12)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(exam.examDate.formatted(date: .numeric, time: .omitted))
                                        .scaledFont(size: 12)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 2) {
                                        Image(systemName: "star.fill").scaledFont(size: 10).foregroundColor(.yellow)
                                        Text("\(exam.importance)").scaledFont(size: 12).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        for i in indexSet.sorted(by: >) {
                            container.deleteExam(container.examRepo.examSets[i])
                        }
                    }
                }
            }

            if !container.examRepo.comprehensiveExamSets.isEmpty {
                Section(header: Text("Comprehensive (\(container.examRepo.comprehensiveExamSets.count))".localized())) {
                    ForEach(container.examRepo.comprehensiveExamSets) { exam in
                        Button {
                            editingCompExam = exam
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exam.name)
                                        .scaledFont(size: 15, weight: .medium)
                                    Text(exam.subject.joined(separator: ", "))
                                        .scaledFont(size: 12)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(exam.examDate.formatted(date: .numeric, time: .omitted))
                                        .scaledFont(size: 12)
                                        .foregroundColor(.secondary)
                                    Image(systemName: "square.stack.3d.up.fill")
                                        .scaledFont(size: 12)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        for i in indexSet.sorted(by: >) {
                            container.deleteComprehensiveExam(container.examRepo.comprehensiveExamSets[i])
                        }
                    }
                }
            }

            if container.examRepo.examSets.isEmpty && container.examRepo.comprehensiveExamSets.isEmpty {
                Text("No exams".localized()).foregroundColor(.secondary)
            }
        }
        .navigationTitle("Exams".localized())
        .adaptiveMaxWidth(820)
        .sheet(item: $editingExam) { exam in
            ExamEditSheet(exam: exam) { updated in
                container.examRepo.updateExam(updated)
                editingExam = nil
            }
        }
        .sheet(item: $editingCompExam) { exam in
            CompExamEditSheet(exam: exam) { updated in
                container.examRepo.updateComprehensiveExam(updated)
                editingCompExam = nil
            }
        }
    }
}

// MARK: - MistakeAdminView
struct MistakeAdminView: View {
    @Environment(RepositoryContainer.self) private var container
    @State private var editingMistake: MistakeNote?

    var body: some View {
        List {
            if container.mistakeRepo.mistakeSets.isEmpty {
                Text("No mistakes".localized()).foregroundColor(.secondary)
            } else {
                ForEach(container.mistakeRepo.mistakeSets) { mistake in
                    // iPad 用 NavigationLink 推到 MistakeDetailEditView(传 false 让它别再包自己的 stack);
                    // iPhone 继续走 Button + sheet。
                    // iPad: NavigationLink to MistakeDetailEditView (pass false so it
                    // doesn't double-wrap the stack); iPhone: Button + .sheet below.
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        NavigationLink {
                            MistakeDetailEditView(
                                container: container,
                                mistakeSet: mistake,
                                usesInternalNavigationStack: false
                            )
                            .adaptiveSheet()
                        } label: {
                            mistakeRow(mistake: mistake)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            editingMistake = mistake
                        } label: {
                            mistakeRow(mistake: mistake)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet.sorted(by: >) {
                        container.deleteMistake(container.mistakeRepo.mistakeSets[i])
                    }
                }
            }
        }
        .navigationTitle("Mistakes".localized())
        .adaptiveMaxWidth(820)
        .sheet(item: $editingMistake) { mistake in
            MistakeDetailEditView(container: container, mistakeSet: mistake)
        }
    }

    /// Shared row content for the mistake admin list (used by both iPad
    /// NavigationLink and iPhone Button paths).
    @ViewBuilder
    private func mistakeRow(mistake: MistakeNote) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mistake.title)
                    .scaledFont(size: 15, weight: .medium)
                if !mistake.subject.isEmpty {
                    Text(mistake.subject)
                        .scaledFont(size: 12)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(mistake.date.formatted(date: .numeric, time: .omitted))
                .scaledFont(size: 12)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - GradeEditSheet
struct GradeEditSheet: View {
    let grade: Grade
    let onSave: (Grade) -> Void
    @Environment(\.presentationMode) var presentationMode

    @State private var subject: String
    @State private var score: Double
    @State private var examName: String
    @State private var date: Date
    @State private var importance: Int
    @State private var rawScore: Double
    @State private var ranking: String

    init(grade: Grade, onSave: @escaping (Grade) -> Void) {
        self.grade = grade
        self.onSave = onSave
        _subject = State(initialValue: grade.subject)
        _score = State(initialValue: grade.score)
        _examName = State(initialValue: grade.examName)
        _date = State(initialValue: grade.date)
        _importance = State(initialValue: grade.importance)
        _rawScore = State(initialValue: grade.rawScore ?? grade.score)
        _ranking = State(initialValue: grade.ranking.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Grade Details".localized())) {
                    HStack {
                        Text("Subject".localized())
                        TextField("Subject".localized(), text: $subject).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Exam Name".localized())
                        TextField("Exam".localized(), text: $examName).multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date".localized(), selection: $date, displayedComponents: .date)
                }
                Section(header: Text("Score".localized())) {
                    HStack {
                        Text("Score".localized())
                        Spacer()
                        Stepper(String(format: "%.1f", score), value: $score, in: 0...1000, step: 0.5)
                    }
                    HStack {
                        Text("Raw Score".localized())
                        Spacer()
                        Stepper(String(format: "%.1f", rawScore), value: $rawScore, in: 0...1000, step: 0.5)
                    }
                    HStack {
                        Text("Ranking".localized())
                        TextField("Ranking".localized(), text: $ranking)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }
                Section(header: Text("Importance".localized())) {
                    HStack {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= importance ? "star.fill" : "star")
                                .foregroundColor(i <= importance ? .yellow : .gray)
                                .onTapGesture { importance = i }
                        }
                    }
                }
            }
            .adaptiveForm()
            .navigationTitle("Edit Grade".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel".localized()) { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save".localized()) {
                        var updated = grade
                        updated.subject = subject
                        updated.score = score
                        updated.examName = examName
                        updated.date = date
                        updated.importance = importance
                        updated.rawScore = rawScore
                        updated.ranking = Int(ranking)
                        onSave(updated)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - ExamEditSheet
struct ExamEditSheet: View {
    let exam: Exam
    let onSave: (Exam) -> Void
    @Environment(\.presentationMode) var presentationMode

    @State private var examName: String
    @State private var subject: String
    @State private var date: Date
    @State private var importance: Int

    init(exam: Exam, onSave: @escaping (Exam) -> Void) {
        self.exam = exam
        self.onSave = onSave
        _examName = State(initialValue: exam.examName)
        _subject = State(initialValue: exam.subject)
        _date = State(initialValue: exam.examDate)
        _importance = State(initialValue: exam.importance)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Exam Details".localized())) {
                    HStack {
                        Text("Exam Name".localized())
                        TextField("Name".localized(), text: $examName).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Subject".localized())
                        TextField("Subject".localized(), text: $subject).multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date".localized(), selection: $date, displayedComponents: .date)
                }
                Section(header: Text("Importance".localized())) {
                    HStack {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= importance ? "star.fill" : "star")
                                .foregroundColor(i <= importance ? .yellow : .gray)
                                .onTapGesture { importance = i }
                        }
                    }
                }
            }
            .adaptiveForm()
            .navigationTitle("Edit Exam".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel".localized()) { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save".localized()) {
                        var updated = exam
                        updated.examName = examName
                        updated.subject = subject
                        updated.examDate = date
                        updated.importance = importance
                        onSave(updated)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - CompExamEditSheet
struct CompExamEditSheet: View {
    let exam: comprehensiveExam
    let onSave: (comprehensiveExam) -> Void
    @Environment(\.presentationMode) var presentationMode

    @State private var name: String
    @State private var aliasName: String
    @State private var subjectsText: String
    @State private var date: Date
    @State private var importance: Int
    @State private var masteryDegree: Double

    init(exam: comprehensiveExam, onSave: @escaping (comprehensiveExam) -> Void) {
        self.exam = exam
        self.onSave = onSave
        _name = State(initialValue: exam.name)
        _aliasName = State(initialValue: exam.examName)
        _subjectsText = State(initialValue: exam.subject.joined(separator: ", "))
        _date = State(initialValue: exam.examDate)
        _importance = State(initialValue: exam.importance)
        _masteryDegree = State(initialValue: Double(exam.masteryDegree))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Exam Details".localized())) {
                    HStack {
                        Text("Name".localized())
                        TextField("Name".localized(), text: $name).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Alias".localized())
                        TextField("Alias".localized(), text: $aliasName).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Subjects".localized())
                        TextField("Comma separated".localized(), text: $subjectsText).multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date".localized(), selection: $date, displayedComponents: .date)
                }
                Section(header: Text("Status".localized())) {
                    HStack {
                        Text("Mastery".localized())
                        Slider(value: $masteryDegree, in: 0...100, step: 1)
                        Text("\(Int(masteryDegree))%".localized()).font(.caption).foregroundColor(.secondary)
                    }
                }
                Section(header: Text("Importance".localized())) {
                    HStack {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= importance ? "star.fill" : "star")
                                .foregroundColor(i <= importance ? .yellow : .gray)
                                .onTapGesture { importance = i }
                        }
                    }
                }
            }
            .adaptiveForm()
            .navigationTitle("Edit Comp Exam".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel".localized()) { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save".localized()) {
                        var updated = exam
                        updated.name = name
                        updated.examName = aliasName
                        updated.subject = subjectsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        updated.examDate = date
                        updated.importance = importance
                        updated.masteryDegree = Int(masteryDegree)
                        onSave(updated)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    DataAdminView()
        .environment(RepositoryContainer())
}
