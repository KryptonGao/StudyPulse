//
//  ProfileSettingsView.swift
//  StudyPulse
//

import SwiftUI

struct ProfileSettingsView: View {
    @Environment(RepositoryContainer.self) private var container

    // Local editing state — auto-saved on change
    @State private var username = ""
    @State private var realName = ""
    @State private var age = 0
    @State private var gender = "Not Specified"
    @State private var educationStage: EducationStage = .highSchool
    @State private var categoryFilter: EducationCategory? = nil
    @State private var regionCode = "mainland"
    @State private var grade = ""
    @State private var className = ""
    @State private var schoolName = ""
    @State private var studentId = ""
    @State private var enrollmentYear = Calendar.current.component(.year, from: Date())
    @State private var examYear = Calendar.current.component(.year, from: Date())
    @State private var targetSchool = ""
    @State private var targetScore: Double = 0
    @State private var showSmartRecommendation = false

    private var availableRegions: [EducationRegion] {
        var regions = EducationConfig.availableRegions(for: educationStage)
        if let filter = categoryFilter {
            regions = regions.filter { $0.category == filter }
        }
        return regions
    }

    private var currentRegion: EducationRegion? {
        EducationConfig.region(named: regionCode, stage: educationStage)
    }

    private var profileSubtitle: String {
        let p = container.profileRepo.profile
        if !p.studentId.isEmpty {
            return "Student ID · \(p.studentId)"
        } else if !p.schoolName.isEmpty {
            return p.schoolName
        } else {
            return "Tap to set up your profile".localized()
        }
    }

    // MARK: - Body

    var body: some View {
        let list = profileList
        let title = list.navigationTitle("Profile".localized())
        let inline = title.navigationBarTitleDisplayMode(.inline)
        let appeared = inline.onAppear { loadFromProfile() }
        let smartAlert = appeared.alert("Apply Smart Recommendation".localized(), isPresented: $showSmartRecommendation) {
            Button("Cancel".localized(), role: .cancel) { }
            Button("Apply".localized()) {
                applySmartRecommendation()
            }
        } message: {
            Text(String(format: "This will reset subject list and auto-check required subjects for %@ - %@. Existing enabled preferences will be kept.".localized(), currentRegion?.displayName ?? "", educationStage.rawValue))
        }
        return attachAutoSave(to: smartAlert)
    }

    // MARK: - List

    private var profileList: some View {
        List {
            // Apple ID style header (static, non-tappable)
            Section {
                VStack(spacing: 8) {
                    AvatarView(
                        username: container.profileRepo.profile.username,
                        avatarData: container.profileRepo.loadAvatar(),
                        size: 88
                    )
                    .padding(.top, 8)
                    TextField("Username", text: $username)
                        .multilineTextAlignment(.center)
                        .scaledFont(size: 24, weight: .bold)
                        .padding(.top, 4)
                    Text(profileSubtitle)
                        .scaledFont(size: 14)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .listSectionSpacing(.custom(0))

            // Edit avatar (separate row)
            Section {
                NavigationLink(destination: AvatarEditView()) {
                    HStack(spacing: 14) {
                        AvatarView(
                            username: container.profileRepo.profile.username,
                            avatarData: container.profileRepo.loadAvatar(),
                            size: 36
                        )
                        Text("Edit Avatar".localized())
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
            }

            educationStageSection
            regionSection
            personalInfoSection
            schoolInfoSection
            academicYearSection
            if educationStage == .highSchool || educationStage == .university {
                goalsSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .containerBackground(.clear, for: .navigation)
        .debugModeContainer()
        .debugLayoutBoundsAuto()
    }

    // MARK: - Auto-save bindings

    private func attachAutoSave<V: View>(to view: V) -> some View {
        view
            .onChange(of: educationStage) { _, newValue in
                if EducationConfig.region(named: regionCode, stage: newValue) == nil {
                    regionCode = EducationConfig.defaultRegion(for: newValue).name
                }
                saveToProfile()
            }
            .onChange(of: categoryFilter) { _, _ in
                if !availableRegions.contains(where: { $0.name == regionCode }) {
                    regionCode = availableRegions.first?.name ?? "mainland"
                }
                saveToProfile()
            }
            .onChange(of: regionCode) { _, _ in saveToProfile() }
            .onChange(of: username) { _, _ in saveToProfile() }
            .onChange(of: realName) { _, _ in saveToProfile() }
            .onChange(of: age) { _, _ in saveToProfile() }
            .onChange(of: gender) { _, _ in saveToProfile() }
            .onChange(of: grade) { _, _ in saveToProfile() }
            .onChange(of: className) { _, _ in saveToProfile() }
            .onChange(of: schoolName) { _, _ in saveToProfile() }
            .onChange(of: studentId) { _, _ in saveToProfile() }
            .onChange(of: enrollmentYear) { _, _ in saveToProfile() }
            .onChange(of: examYear) { _, _ in saveToProfile() }
            .onChange(of: targetSchool) { _, _ in saveToProfile() }
            .onChange(of: targetScore) { _, _ in saveToProfile() }
    }

    // MARK: - Sections

    private var educationStageSection: some View {
        Section(header: Text("Education Stage".localized())) {
            Menu {
                ForEach(EducationStage.allCases) { stage in
                    Button {
                        educationStage = stage
                    } label: {
                        HStack {
                            Text(stageLabel(stage).localized())
                            if educationStage == stage {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "graduationcap.fill")
                        .foregroundColor(stageColor(educationStage))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stage".localized())
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(stageLabel(educationStage).localized())
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
    }

    private var regionSection: some View {
        Section(header: Text("Region / Education System".localized())) {
            Picker("Category".localized(), selection: $categoryFilter) {
                Text("All".localized()).tag(EducationCategory?.none)
                Text("Domestic".localized()).tag(EducationCategory?.some(.domestic))
                Text("International".localized()).tag(EducationCategory?.some(.international))
            }
            .pickerStyle(.segmented)

            Picker("Region".localized(), selection: $regionCode) {
                ForEach(availableRegions) { region in
                    Text(region.category == .international
                        ? String(format: "Intl. %@".localized(), region.displayName)
                        : region.displayName)
                        .tag(region.name)
                }
            }

            if educationStage != .primarySchool {
                Button(action: { showSmartRecommendation = true }) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                            .appleIntelligenceForeground()
                        Text("Apply Smart Subject Recommendation".localized())
                            .appleIntelligenceForeground()
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }


                NavigationLink(destination: AchievementsView()) {
                    HStack(spacing: 14) {
                        Image(systemName: "rosette")
                            .foregroundColor(.orange)
                        Text("Achievements".localized())
                            .foregroundColor(.primary)
                    }
                }

                NavigationLink(destination: DailyGoalsConfigView()) {
                    HStack(spacing: 14) {
                        Image(systemName: "target")
                            .foregroundColor(.purple)
                        Text("Daily Goals".localized())
                            .foregroundColor(.primary)
                    }
                }

                NavigationLink(destination: EditSubjectsView()) {
                    HStack(spacing: 14) {
                        Image(systemName: "book.closed")
                            .foregroundColor(.gray)
                        Text("Edit Subjects".localized())
                            .foregroundColor(.primary)
                    }
                }
            }
        }
    }

    private var personalInfoSection: some View {
        Section(header: Text("Personal Info".localized())) {
            HStack {
                Image(systemName: "person.text.rectangle")
                    .foregroundColor(.orange)
                    .frame(width: 30)
                Text("Real Name".localized())
                Spacer()
                TextField("Real Name".localized(), text: $realName)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.pink)
                    .frame(width: 30)
                Text("Age".localized())
                Spacer()
                TextField("Age".localized(), value: $age, formatter: NumberFormatter())
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Image(systemName: "person.fill")
                    .foregroundColor(.blue)
                    .frame(width: 30)
                Text("Gender".localized())
                Spacer()
                Picker("Gender".localized(), selection: $gender) {
                    Text("Not Specified".localized()).tag("Not Specified")
                    Text("Male".localized()).tag("Male")
                    Text("Female".localized()).tag("Female")
                    Text("Other".localized()).tag("Other")
                }
                .labelsHidden()
            }
        }
    }

    private var schoolInfoSection: some View {
        Section(header: Text("School Info".localized())) {
            HStack {
                Image(systemName: "building.columns")
                    .foregroundColor(.indigo)
                    .frame(width: 30)
                Text("School".localized())
                Spacer()
                TextField("School Name".localized(), text: $schoolName)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Image(systemName: "number")
                    .foregroundColor(.purple)
                    .frame(width: 30)
                Text("Student ID".localized())
                Spacer()
                TextField("Student ID".localized(), text: $studentId)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Image(systemName: "graduationcap")
                    .foregroundColor(.green)
                    .frame(width: 30)
                Text("Grade".localized())
                Spacer()
                TextField("e.g. Grade 11".localized(), text: $grade)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Image(systemName: "person.3")
                    .foregroundColor(.teal)
                    .frame(width: 30)
                Text("Class".localized())
                Spacer()
                TextField("Class".localized(), text: $className)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var academicYearSection: some View {
        Section(header: Text("Academic Year".localized())) {
            HStack {
                Image(systemName: "calendar.badge.plus")
                    .foregroundColor(.cyan)
                    .frame(width: 30)
                Text("Enrollment Year".localized())
                Spacer()
                Picker("Year".localized(), selection: $enrollmentYear) {
                    ForEach((enrollmentYear-5)...(enrollmentYear+5), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .labelsHidden()
            }
            HStack {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundColor(.mint)
                    .frame(width: 30)
                Text("Target Exam Year".localized())
                Spacer()
                Picker("Year".localized(), selection: $examYear) {
                    ForEach((examYear-5)...(examYear+5), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var goalsSection: some View {
        Section(header: Text("Goals".localized())) {
            HStack {
                Image(systemName: "target")
                    .foregroundColor(.red)
                    .frame(width: 30)
                Text("Target School".localized())
                Spacer()
                TextField("e.g. Tsinghua University".localized(), text: $targetSchool)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .frame(width: 30)
                Text("Target Score".localized())
                Spacer()
                TextField("Target".localized(), value: $targetScore, formatter: NumberFormatter())
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Helpers

    private func stageLabel(_ stage: EducationStage) -> String {
        switch stage {
        case .primarySchool: return "Primary School".localized()
        case .middleSchool: return "Middle School".localized()
        case .highSchool: return "High School".localized()
        case .internationalHighSchool: return "International High School".localized()
        case .university: return "University".localized()
        case .graduate: return "Graduate".localized()
        }
    }

    private func stageColor(_ stage: EducationStage) -> Color {
        switch stage {
        case .primarySchool: return .orange
        case .middleSchool: return .green
        case .highSchool: return .blue
        case .internationalHighSchool: return .purple
        case .university: return .indigo
        case .graduate: return .pink
        }
    }

    private func loadFromProfile() {
        username = container.profileRepo.profile.username
        realName = container.profileRepo.profile.realName
        age = container.profileRepo.profile.age
        gender = container.profileRepo.profile.gender
        educationStage = EducationStage(rawValue: container.profileRepo.profile.educationStage) ?? .highSchool
        regionCode = container.profileRepo.profile.regionCode
        grade = container.profileRepo.profile.grade
        className = container.profileRepo.profile.className
        schoolName = container.profileRepo.profile.schoolName
        studentId = container.profileRepo.profile.studentId
        enrollmentYear = container.profileRepo.profile.enrollmentYear
        examYear = container.profileRepo.profile.examYear
        targetSchool = container.profileRepo.profile.targetSchool
        targetScore = container.profileRepo.profile.targetScore
    }

    private func saveToProfile() {
        container.profileRepo.profile.username = username
        container.profileRepo.profile.realName = realName
        container.profileRepo.profile.age = age
        container.profileRepo.profile.gender = gender
        container.profileRepo.profile.educationStage = educationStage.rawValue
        container.profileRepo.profile.regionCode = regionCode
        container.profileRepo.profile.educationLevel = educationStage.rawValue
        if let region = currentRegion {
            container.profileRepo.profile.educationSystem = region.displayName
            container.profileRepo.profile.region = region.displayName
        }
        container.profileRepo.profile.grade = grade
        container.profileRepo.profile.className = className
        container.profileRepo.profile.schoolName = schoolName
        container.profileRepo.profile.studentId = studentId
        container.profileRepo.profile.enrollmentYear = enrollmentYear
        container.profileRepo.profile.examYear = examYear
        container.profileRepo.profile.targetSchool = targetSchool
        container.profileRepo.profile.targetScore = targetScore
        container.profileRepo.saveProfile()
    }

    private func applySmartRecommendation() {
        container.applySmartSubjectRecommendation(stage: educationStage, regionCode: regionCode)
    }
}
