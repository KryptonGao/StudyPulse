//
//  OnboardingView.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/6/27.
//  原生 iOS 26 风格的引导页：渐变背景 + 玻璃质感卡片 + 大圆角，
//  使用 TabView 分页，每页聚焦一个特性。
//
//  扩展：
//  - 首次启动 welcome 流程可在介绍页之后追加 6 页「基础信息填写」步骤，
//    全部完成后才回调 onFinish，进入主页面。
//  - 草稿数据持久化到 UserDefaults，强杀后可恢复。
//

import SwiftUI

/// 原生 iOS 26 风格的引导页视图，替代 WSOnBoarding 的 StandardWelcomeView。
struct OnboardingView: View {
    let config: OnboardingConfig
    /// 用户点击「继续 / 完成」或「跳过」时回调
    let onFinish: () -> Void
    /// 当用户完成 profile 流程时调用（在 onFinish 之前）。
    /// 仅在 config.profileFlow != nil 时会触发。
    /// 即使用户走「跳过 / 直接完成」也会触发，参数就是当前草稿状态。
    var onProfileComplete: ((OnboardingProfileDraft, [String]) -> Void)? = nil

    @State private var currentPage = 0
    @State private var flowState: OnboardingFlowState = OnboardingFlowState()
    @State private var showSubjectResetToast = false
    @State private var toastTask: Task<Void, Never>?

    /// 介绍阶段总页数 = 1（Hero）+ features.count
    private var introPageCount: Int { 1 + config.features.count }
    /// profile 阶段总页数（nil 表示没有 profile 流程）
    private var profilePageCount: Int { config.profileFlow == nil ? 0 : OnboardingProfileStep.allCases.count }
    /// 总页数
    private var totalPages: Int { introPageCount + profilePageCount }
    /// 是否为最后一页
    private var isLastPage: Bool { currentPage >= totalPages - 1 }
    /// 当前是否在 profile 阶段
    private var isProfilePhase: Bool {
        guard config.profileFlow != nil else { return false }
        return currentPage >= introPageCount
    }
    /// 当前 profile 步骤（仅在 profile 阶段有效）
    private var currentProfileStep: OnboardingProfileStep? {
        guard isProfilePhase, let _ = config.profileFlow else { return nil }
        let idx = currentPage - introPageCount
        return OnboardingProfileStep(rawValue: idx)
    }

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                TabView(selection: $currentPage) {
                    heroPage
                        .tag(0)
                    ForEach(Array(config.features.enumerated()), id: \.offset) { index, feature in
                        featurePage(feature, index: index)
                            .tag(index + 1)
                    }
                    if let _ = config.profileFlow {
                        ForEach(OnboardingProfileStep.allCases) { step in
                            profilePage(step)
                                .tag(step.stepIndex(base: introPageCount))
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: currentPage)
                .onChange(of: currentPage) { _, newPage in
                    // 切换页时落盘草稿
                    if config.profileFlow != nil {
                        var snapshot = flowState
                        snapshot.currentStep = newPage
                        OnboardingFlowStateStore.save(snapshot)
                    }
                }

                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }

            if showSubjectResetToast {
                subjectResetToast
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear { restoreDraftIfNeeded() }
    }

    // MARK: - Draft restore

    private func restoreDraftIfNeeded() {
        guard config.profileFlow != nil else { return }
        if let saved = OnboardingFlowStateStore.load() {
            flowState = saved
            // 仅当 currentStep 在有效范围内才恢复，否则回退到当前页（避免越界）
            if saved.currentStep >= 0 && saved.currentStep < totalPages {
                currentPage = saved.currentStep
            }
        } else {
            flowState = OnboardingFlowState()
            // 首次进入：让用户从介绍页开始
            currentPage = 0
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            // 基础渐变：主色淡化到系统背景色
            LinearGradient(
                colors: [
                    config.primaryColor.opacity(0.18),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 装饰性模糊光晕
            Circle()
                .fill(config.primaryColor.opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 100)
                .offset(x: -180, y: -260)
                .ignoresSafeArea()

            Circle()
                .fill(config.primaryColor.opacity(0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: 200, y: 360)
                .ignoresSafeArea()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            pageIndicator
            Spacer()
            if !isLastPage && !isProfilePhase {
                Button("Skip".localized(), action: handleSkip)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            } else if isProfilePhase, let step = currentProfileStep, !step.isRequired {
                // profile 阶段的可选步骤提供「稍后填写」入口
                Button(config.profileFlow?.skipGoalsText ?? "Skip".localized()) {
                    finishOnboarding()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        .frame(height: 32)
    }

    private var pageIndicator: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(0..<totalPages, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage ? config.primaryColor : Color.secondary.opacity(0.3))
                        .frame(width: i == currentPage ? 22 : 6, height: 6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentPage)
                }
            }
            if isProfilePhase, let header = config.profileFlow?.sectionHeader {
                Text(header)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Hero page

    private var heroPage: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer().frame(height: 24)

                if config.pageType == .whatsNew {
                    whatsNewBadge
                }

                appIcon

                VStack(spacing: 12) {
                    Text(config.appName)
                        .scaledFont(size: 40, weight: .bold, design: .rounded)
                        .multilineTextAlignment(.center)

                    Text(config.introText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let disclaimer = config.disclaimerText, !disclaimer.isEmpty {
                    disclaimerCard(disclaimer)
                        .padding(.top, 4)
                }

                Spacer().frame(height: 8)
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var appIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            config.primaryColor,
                            config.primaryColor.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .shadow(color: config.primaryColor.opacity(0.4), radius: 24, y: 12)

            Image(systemName: config.iconSymbol)
                .scaledFont(size: 56, weight: .semibold)
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var whatsNewBadge: some View {
        Text("What's New".localized())
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(config.primaryColor)
            )
    }

    // MARK: - Feature page

    private func featurePage(_ feature: OnboardingConfig.Feature, index: Int) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer().frame(height: 24)

                featureIconBadge(feature)

                VStack(spacing: 14) {
                    Text("\(index + 1) / \(config.features.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(feature.title)
                        .scaledFont(size: 30, weight: .bold, design: .rounded)
                        .multilineTextAlignment(.center)

                    Text(feature.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }

                Spacer().frame(height: 8)
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func featureIconBadge(_ feature: OnboardingConfig.Feature) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            feature.color.opacity(0.28),
                            feature.color.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 200, height: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 48, style: .continuous)
                        .strokeBorder(feature.color.opacity(0.2), lineWidth: 1)
                )

            Image(systemName: feature.icon)
                .scaledFont(size: 96, weight: .medium)
                .foregroundStyle(feature.color.gradient)
                .symbolRenderingMode(.hierarchical)
        }
    }

    // MARK: - Disclaimer

    private func disclaimerCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(config.primaryColor)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassSurface(cornerRadius: 16))
    }

    // MARK: - Profile page

    @ViewBuilder
    private func profilePage(_ step: OnboardingProfileStep) -> some View {
        OnboardingProfileFormView(
            step: step,
            draft: $flowState.draft,
            selectedSubjectNames: $flowState.selectedSubjectNames,
            context: makeProfileContext(),
            onSubjectListChanged: { handleSubjectsReset() }
        )
    }

    private func makeProfileContext() -> OnboardingProfileContext {
        let stage = EducationStage(rawValue: flowState.draft.educationStage) ?? .highSchool
        let region = EducationConfig.region(named: flowState.draft.regionCode, stage: stage)
            ?? EducationConfig.defaultRegion(for: stage)
        let subjects = region.subjects
        return OnboardingProfileContext(
            educationStage: stage,
            regionCode: flowState.draft.regionCode,
            region: region,
            availableSubjects: subjects,
            currentYear: Calendar.current.component(.year, from: Date())
        )
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button(action: handlePrimaryTap) {
                HStack(spacing: 8) {
                    Text(primaryButtonTitle)
                        .font(.headline)
                    if !isLastPage {
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    config.primaryColor,
                                    config.primaryColor.opacity(0.85)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: config.primaryColor.opacity(0.35), radius: 14, y: 8)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isPrimaryEnabled)
            .opacity(isPrimaryEnabled ? 1.0 : 0.45)

            if isProfilePhase, let step = currentProfileStep, !step.isRequired {
                Text("You can update these goals anytime in Settings.".localized())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var primaryButtonTitle: String {
        if isLastPage {
            return config.profileFlow?.finishButtonText ?? config.continueButtonText
        }
        return "Next".localized()
    }

    /// 「下一步」按钮是否可用：填写阶段必须通过校验
    private var isPrimaryEnabled: Bool {
        guard isProfilePhase, let step = currentProfileStep else {
            return true
        }
        return validate(step: step)
    }

    private func validate(step: OnboardingProfileStep) -> Bool {
        let d = flowState.draft
        switch step {
        case .identity:
            return !d.username.trimmingCharacters(in: .whitespaces).isEmpty
        case .ageGender:
            return d.age >= 6 && d.age <= 99
        case .school:
            return !d.schoolName.trimmingCharacters(in: .whitespaces).isEmpty
                && !d.grade.trimmingCharacters(in: .whitespaces).isEmpty
        case .education:
            // 阶段和地区总是有默认值的
            return EducationStage(rawValue: d.educationStage) != nil
        case .subjects:
            return !flowState.selectedSubjectNames.isEmpty
        case .goals:
            return true // 可选
        }
    }

    private func handlePrimaryTap() {
        if isLastPage {
            finishOnboarding()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                currentPage += 1
            }
        }
    }

    private func handleSkip() {
        finishOnboarding()
    }

    private func finishOnboarding() {
        // 提交时把草稿同步给父级
        let snapshot = flowState
        // 通知父级：profile 流程完成（即使 profileFlow == nil 也是 no-op）
        if config.profileFlow != nil {
            onProfileComplete?(snapshot.draft, snapshot.selectedSubjectNames)
        }
        // 清理：流程已结束，下次不再恢复
        OnboardingFlowStateStore.clear()
        onFinish()
    }

    // MARK: - Subject reset toast

    private func handleSubjectsReset() {
        toastTask?.cancel()
        showSubjectResetToast = true
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                showSubjectResetToast = false
            }
        }
    }

    private var subjectResetToast: some View {
        Text("Subject list reset for the new system".localized())
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.black.opacity(0.75))
            )
            .padding(.top, 80)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Glass surface helper

    /// iOS 26+ 使用 Liquid Glass 效果；旧版本回退到 .regularMaterial。
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

#Preview("Welcome") {
    OnboardingView(config: .welcome) {}
}

#Preview("What's New") {
    OnboardingView(config: .whatsNew) {}
}
