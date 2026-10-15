//
//  OnboardingProfileFormView.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/6/30.
//
//  首次启动 OnBoarding 流程中的「基础信息填写」单页视图。
//  - 复用 OnboardingView 的玻璃质感 + 渐变背景视觉风格。
//  - 每个 step 显示一个填写块；校验失败时阻塞「下一步」按钮。
//  - 选科切换教育阶段 / 地区时自动清空已选并提示。
//

import SwiftUI

/// 填写单页的视图：渲染当前 step 的填写卡片。
///
/// 数据通过 Binding 透传，父级 OnboardingView 持有 @State 草稿。
struct OnboardingProfileFormView: View {
    let step: OnboardingProfileStep
    @Binding var draft: OnboardingProfileDraft
    @Binding var selectedSubjectNames: [String]
    let context: OnboardingProfileContext

    /// 切换教育阶段 / 地区时，需要提示用户并清空选科；父级用 binding 拿到事件。
    var onSubjectListChanged: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                stepHeader
                stepCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Header

    private var stepHeader: some View {
        VStack(spacing: 10) {
            iconBadge
            VStack(spacing: 6) {
                Text(step.title)
                    .scaledFont(size: 26, weight: .bold, design: .rounded)
                    .multilineTextAlignment(.center)
                Text(step.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [step.color.opacity(0.28), step.color.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 140, height: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .strokeBorder(step.color.opacity(0.2), lineWidth: 1)
                )
            Image(systemName: step.icon)
                .scaledFont(size: 64, weight: .medium)
                .foregroundStyle(step.color.gradient)
                .symbolRenderingMode(.hierarchical)
        }
    }

    // MARK: - Card

    @ViewBuilder
    private var stepCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case .identity:   identityFields
            case .ageGender:  ageGenderFields
            case .school:     schoolFields
            case .education:  educationFields
            case .subjects:   subjectsFields
            case .goals:      goalsFields
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassSurface(cornerRadius: 24))
    }

    // MARK: - Section: identity

    private var identityFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeledField(
                title: "Display Name".localized(),
                required: true
            ) {
                TextField("e.g. Alex".localized(), text: $draft.username)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(fieldBackground)
            }
            labeledField(
                title: "Real Name".localized(),
                required: false,
                footer: "Leave blank if you prefer to stay anonymous.".localized()
            ) {
                TextField("e.g. Chen Kai".localized(), text: $draft.realName)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(fieldBackground)
            }
        }
    }

    // MARK: - Section: age & gender

    private var ageGenderFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeledField(title: "Age".localized(), required: true) {
                HStack {
                    Stepper(
                        value: Binding(
                            get: { draft.age == 0 ? 16 : draft.age },
                            set: { draft.age = $0 }
                        ),
                        in: 6...99
                    ) {
                        Text(draft.age == 0 ? "—".localized() : "\(draft.age)")
                            .font(.title3.weight(.semibold))
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(fieldBackground)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Gender".localized())
                    .font(.subheadline.weight(.semibold))
                Picker("Gender".localized(), selection: $draft.gender) {
                    Text("Not Specified".localized()).tag("Not Specified")
                    Text("Male".localized()).tag("Male")
                    Text("Female".localized()).tag("Female")
                    Text("Other".localized()).tag("Other")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Section: school

    private var schoolFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeledField(
                title: "School".localized(),
                required: true
            ) {
                TextField("e.g. Tsinghua High School".localized(), text: $draft.schoolName)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(fieldBackground)
            }
            HStack(spacing: 12) {
                labeledField(title: "Grade".localized(), required: true) {
                    TextField("e.g. Grade 11".localized(), text: $draft.grade)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(fieldBackground)
                }
                labeledField(title: "Class".localized(), required: false) {
                    TextField("e.g. 3".localized(), text: $draft.className)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(fieldBackground)
                }
            }
            labeledField(title: "Student ID".localized(), required: false) {
                TextField("Optional".localized(), text: $draft.studentId)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(fieldBackground)
            }
            HStack(spacing: 12) {
                yearPicker(
                    title: "Enrollment Year".localized(),
                    binding: $draft.enrollmentYear
                )
                yearPicker(
                    title: "Target Exam Year".localized(),
                    binding: $draft.examYear
                )
            }
        }
    }

    private func yearPicker(title: String, binding: Binding<Int>) -> some View {
        labeledField(title: title, required: false) {
            Picker(title, selection: binding) {
                ForEach((context.currentYear - 5)...(context.currentYear + 6), id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fieldBackground)
        }
    }

    // MARK: - Section: education stage + region

    private var educationFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Education Stage".localized())
                    .font(.subheadline.weight(.semibold))
                stageChips
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Region / Education System".localized())
                    .font(.subheadline.weight(.semibold))
                regionPicker
            }
            if let region = context.region, !region.notes.isEmpty {
                Label(region.notes, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stageChips: some View {
        let columns = [
            GridItem(.adaptive(minimum: 130), spacing: 8)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(EducationStage.allCases) { stage in
                let selected = stage.rawValue == draft.educationStage
                Button {
                    if selected { return }
                    let oldStage = EducationStage(rawValue: draft.educationStage) ?? .highSchool
                    if oldStage != stage {
                        // 切换教育阶段：地区重置为该阶段的默认地区；选科清空
                        let newDefault = EducationConfig.defaultRegion(for: stage)
                        draft.educationStage = stage.rawValue
                        draft.regionCode = newDefault.name
                        if !selectedSubjectNames.isEmpty {
                            selectedSubjectNames = []
                            onSubjectListChanged()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: stageIcon(stage))
                        Text(stageLabel(stage).localized())
                            .lineLimit(1)
                    }
                    .font(.footnote.weight(selected ? .semibold : .regular))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule()
                            .fill(selected ? stageColor(stage).opacity(0.25) : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(selected ? stageColor(stage) : Color.clear, lineWidth: 1.5)
                    )
                    .foregroundStyle(selected ? stageColor(stage) : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var regionPicker: some View {
        let available = EducationConfig.availableRegions(for: context.educationStage)
        return Menu {
            ForEach(available) { region in
                Button {
                    if region.name == draft.regionCode { return }
                    draft.regionCode = region.name
                    if !selectedSubjectNames.isEmpty {
                        selectedSubjectNames = []
                        onSubjectListChanged()
                    }
                } label: {
                    HStack {
                        Text(regionLabel(region))
                        if region.name == draft.regionCode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(.purple)
                Text(regionLabel(currentRegion))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(fieldBackground)
        }
    }

    private var currentRegion: EducationRegion {
        context.region ?? EducationConfig.defaultRegion(for: context.educationStage)
    }

    private func regionLabel(_ region: EducationRegion) -> String {
        if region.category == .international {
            return String(format: "Intl. %@".localized(), region.displayName)
        }
        return region.displayName.localized()
    }

    private func stageLabel(_ stage: EducationStage) -> String {
        switch stage {
        case .primarySchool: return "Primary School"
        case .middleSchool: return "Middle School"
        case .highSchool: return "High School"
        case .internationalHighSchool: return "International HS"
        case .university: return "University"
        case .graduate: return "Graduate"
        }
    }

    private func stageIcon(_ stage: EducationStage) -> String {
        switch stage {
        case .primarySchool: return "pencil.and.outline"
        case .middleSchool: return "book.closed"
        case .highSchool: return "graduationcap"
        case .internationalHighSchool: return "globe"
        case .university: return "building.columns"
        case .graduate: return "doc.text"
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

    // MARK: - Section: subjects

    private var subjectsFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Subjects".localized())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(selectedSubjectNames.count) selected".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if context.availableSubjects.isEmpty {
                Text("No subjects available for this region.".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                subjectGrid
            }
        }
    }

    private var subjectGrid: some View {
        let columns = [
            GridItem(.adaptive(minimum: 150), spacing: 10)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(context.availableSubjects) { subject in
                subjectChip(subject)
            }
        }
    }

    private func subjectChip(_ subject: SubjectConfig) -> some View {
        let isOn = selectedSubjectNames.contains(subject.name)
        let isRequired = subject.isRequired
        return Button {
            guard !isRequired else { return } // 必修不能取消
            if isOn {
                selectedSubjectNames.removeAll { $0 == subject.name }
            } else {
                selectedSubjectNames.append(subject.name)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.circle.fill" : (isRequired ? "lock.circle.fill" : "circle"))
                    .foregroundStyle(isOn ? Color.accentColor : (isRequired ? .secondary : .secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(subject.displayName.localized())
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                    if let category = subject.category {
                        Text(category.localized())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .disabled(isRequired && isOn) // 必修始终勾选，不可关闭
    }

    // MARK: - Section: goals

    private var goalsFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Optional".localized())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            labeledField(
                title: "Target School".localized(),
                required: false
            ) {
                TextField("e.g. Peking University".localized(), text: $draft.targetSchool)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(fieldBackground)
            }
            labeledField(
                title: "Target Score".localized(),
                required: false
            ) {
                TextField("e.g. 680".localized(), value: $draft.targetScore, format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(fieldBackground)
            }
        }
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func labeledField<Content: View>(
        title: String,
        required: Bool,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if required {
                    Text("*")
                        .foregroundStyle(.red)
                }
            }
            content()
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
    }

    @ViewBuilder
    private func glassSurface(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}
