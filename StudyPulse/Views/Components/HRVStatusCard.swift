//
//  HRVStatusCard.swift
//  StudyPulse
//
//  Dashboard card showing recovery readiness as a 4-axis radar / polygon
//  chart (HRV, heart rate, recovery sleep, respiratory rate) and an
//  integrated study suggestion derived from the same signals.
//  仪表盘卡片:用 4 轴雷达 / 多边形图(HRV、心率、恢复睡眠、呼吸频率)
//  展示恢复度,并从同一组信号中派生学习建议。
//
//  Phase 3 拆分 (2026-07-14):原 951 行单文件 → orchestrator 留本文件,
//  拆出 4 个独立子文件:
//  - BodyRadarValues.swift             (6 轴归一化数值 + 颜色 / 文本)
//  - BodyRadarChart.swift              (6 轴多边形 Path 绘制)
//  - FitnessRingView.swift             (单环进度环,Activity-ring 风格)
//  - HRVStatusSuggestionSection.swift  (本地 + LLM 增强建议区,含 AI debug 入口)
//
//  本文件只剩:主 View 编排(header / chart / axis row / suggestion / AI 请求生命周期 / 冷却计时 / discussion sheet)。
//

import SwiftUI
import os

/// 恢复雷达卡:HRV/HR/睡眠/呼吸 4 轴雷达 + 整合学习建议。
/// Recovery radar card: 4-axis radar (HRV/HR/Sleep/Respiratory) + integrated study suggestion.
struct HRVStatusCard: View {
    @Environment(HealthKitManager.self) private var hrvManager: HealthKitManager
    @Environment(RepositoryContainer.self) private var container
    @State private var animateIn = false

    // LLM 增强雷达建议
    // LLM enhancement state.
    @State private var aiSuggestion: StudySuggestion? = nil
    @State private var aiLoading: Bool = false
    @State private var aiErrorMessage: String? = nil
    @State private var aiTask: Task<Void, Never>? = nil
    @State private var lastAIFullText: String? = nil
    @State private var lastBodyReadinessContext: BodyReadinessContext? = nil
    @State private var showDiscussion: Bool = false

    // 冷却时间由设置页控制;“立刻分析”仍可绕过冷却。
    /// Radar LLM cooldown in seconds, configured in LLM settings.
    private var radarAICooldownSeconds: TimeInterval {
        TimeInterval(container.envManager.preferences.radarAICooldownMinutes * 60)
    }
    /// 距下次可自动请求的剩余秒数(基于 `lastRadarAIRequestTime` 计算)。
    /// 倒计时显示由 `TimelineView(.periodic(by: 1))` 每秒重绘,不再用 1Hz Timer 唤醒。
    /// Seconds remaining until the next automatic request is allowed (computed from `lastRadarAIRequestTime`).
    /// The countdown text is redrawn by `TimelineView(.periodic(by: 1))`,no more 1Hz Timer wakeups.
    private var cooldownRemainingSeconds: Int {
        guard let last = container.envManager.preferences.lastRadarAIRequestTime else { return 0 }
        let elapsed = Date().timeIntervalSince(last)
        return max(0, Int((radarAICooldownSeconds - elapsed).rounded()))
    }

    /// 缓存的雷达数值(避免主 body 与 axisValuesRow 各调用一次 compute)。
    /// 在 `.task` 中初始化,在 onChange 中重算,主 body 评估时 0 次 compute。
    /// Cached radar values (avoids calling `BodyRadarValues.compute` twice per body evaluation).
    /// Initialized in `.task`,refreshed in `onChange`,0 `compute` calls per body evaluation.
    @State private var cachedRadar: BodyRadarValues?
    /// 缓存的 7 天 difficulty annotations(避免每次 body 评估都磁盘读)。
    /// Cached 7-day difficulty annotations (avoids disk read on every body evaluation).
    @State private var recentAnnotations: [DifficultyAnnotation] = []

    /// 今日的本地算法建议(用于 AI 流式期间显示 + AI 解析失败的兜底)
    private var localSuggestion: StudySuggestion? {
        StudyReadinessAlgorithm.recommend(
            hrvEnabled: hrvManager.hrvEnabled,
            hrvOnboardingCompleted: hrvManager.hrvOnboardingCompleted,
            isAuthorized: hrvManager.isAuthorized,
            hrv: hrvManager.readiness,
            bodyStatus: hrvManager.bodyStatus,
            baselines: hrvManager.personalBaselines,
            age: container.profileRepo.profile.age
        )
    }

    /// 当前展示的建议:AI 成功时用 AI,否则本地
    private var displayedSuggestion: StudySuggestion? {
        aiSuggestion ?? localSuggestion
    }

    /// 最近 7 天心情/精力日记(供雷达心理稳定性轴 + LLM context)
    /// Recent 7-day mood/energy diary entries (for radar stability axis + LLM context)
    private var recentMoodEntries: [DiaryEntry] {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
        return container.diaryRepo.entriesInRange(sevenDaysAgo, Date())
    }

    var body: some View {
        if hrvManager.hrvEnabled && hrvManager.hrvOnboardingCompleted {
            VStack(alignment: .leading, spacing: 14) {
                header

                if hrvManager.isHealthBootstrapping {
                    // 后台仍在跑 14 天 HRV 查询 + PersonalBaselines 重算
                    // 时显示 Loading 占位,避免首屏卡住。
                    loadingPlaceholder
                } else {
                    if hrvManager.hrvDetailLevel != .suggestionOnly {
                        if let radar = cachedRadar {
                            BodyRadarChart(values: radar)
                                .frame(height: 220)
                                .padding(.vertical, 4)
                        }
                    }

                    if hrvManager.hrvDetailLevel == .chartAndData {
                        axisValuesRow
                    }

                    suggestionRow
                }
            }
            .padding(DesignToken.Spacing.cardPadding)
            .cardSkin()
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(accent.opacity(0.25), lineWidth: 1)
            )
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 10)
            .task {
                let cutoff = Calendar.current.date(
                    byAdding: .day, value: -7, to: .now
                ) ?? .now
                recentAnnotations = container.studySessionRepo
                    .sessions(from: cutoff, to: .now)
                    .flatMap { $0.difficultyAnnotations ?? [] }
                refreshRadar()
                refreshAI()
            }
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    animateIn = true
                }
            }
            .onDisappear {
                aiTask?.cancel()
            }
            .onChange(of: hrvManager.bodyStatus) { _, _ in refreshAI(); refreshRadar() }
            .onChange(of: hrvManager.readiness) { _, _ in refreshAI(); refreshRadar() }
            .onChange(of: hrvManager.personalBaselines) { _, _ in refreshAI(); refreshRadar() }
            .onChange(of: container.mistakeRepo.filteredMistakeSets) { _, _ in refreshRadar() }
            .debugLayoutBoundsAuto()
        }
    }

    // MARK: - Loading Placeholder / 后台 bootstrap 期间的占位

    /// Placeholder shown while the background bootstrap is still
    /// running. Keeps the layout stable (no half-rendered radar) and
    /// signals that data is on the way.
    /// 后台 bootstrap 期间显示柔和的灰色卡,避免渲染残缺的雷达图/建议。
    private var loadingPlaceholder: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading...".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(.vertical, 8)
    }

    // MARK: - Header / 顶部标题
    private var header: some View {
        HStack {
            Image(systemName: "heart.text.square.fill")
                .foregroundStyle(accent.gradient)
                .font(.title3)
            Text("Recovery Radar".localized())
                .font(.headline)
                .fontWeight(.bold)
            Spacer()
            readinessBadge
        }
    }

    // MARK: - Axis values row / 各轴数值行
    /// Numeric readout for each of the four radar dimensions.
    /// Shown only at the highest detail level. The workout slot is
    /// rendered as a 3-ring fitness ring instead of a plain text tile.
    /// 4 轴雷达各维度的数值读数,只在最高细节级别显示。
    /// 运动那一格用 3 圈 fitness ring 渲染,而不是普通文本块。
    private var axisValuesRow: some View {
        // 复用主 body 的 cachedRadar;若缓存尚未就绪(.task 还在后台读 annotations)
        // 则显示空占位 HStack,等下一次 body 评估自动填上。
        // Reuse cachedRadar from the main body; if the cache isn't ready yet
        // (`.task` still reading annotations in the background),show an empty
        // HStack placeholder and let the next body evaluation fill it in.
        Group {
            if let radar = cachedRadar {
                HStack(spacing: 6) {
                    axisTile(title: "HRV", value: radar.hrvValueText, color: radar.hrvColor)
                    axisTile(title: "Heart Rate".localized(), value: radar.heartRateValueText, color: radar.heartRateColor)
                    axisTile(title: "Recovery Sleep".localized(), value: radar.sleepValueText, color: radar.sleepColor)
                    workoutTile(minutes: hrvManager.bodyStatus.exerciseMinutesToday)
                    axisTile(title: "Respiratory".localized(), value: radar.respiratoryValueText, color: radar.respiratoryColor)
                    axisTile(title: "Stability".localized(), value: radar.psychologicalStabilityValueText, color: radar.psychologicalStabilityColor)
                }
            } else {
                HStack(spacing: 6) { Color.clear.frame(height: 40) }
            }
        }
    }

    private func axisTile(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.08))
        )
    }

    /// Workout tile — small 3-ring fitness ring in the same visual
    /// language as the iOS Activity rings.
    /// 运动 tile:小型 3 圈 fitness ring,沿用 iOS Activity ring 的视觉语言。
    private func workoutTile(minutes: Double?) -> some View {
        // 每日运动目标:30 分钟即 100%
        // Daily workout goal: 30 minutes → 100% progress.
        let goal = 30.0
        let progress = min(1.0, (minutes ?? 0) / goal)
        let color = FitnessRingView.colorFor(progress: progress)
        return VStack(spacing: 3) {
            FitnessRingView(progress: progress, lineWidth: 3.5, size: 26)
                .frame(width: 26, height: 26)
            Text(String(format: "%.0f min", minutes ?? 0))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Workout".localized())
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.08))
        )
    }

    // MARK: - Integrated suggestion row / 整合建议
    /// 雷达建议:本地算法 + LLM 增强。
    /// - 未配置 LLM → 直接显示本地建议
    /// - 已配置 LLM → 显示本地建议作为兜底,流式 LLM 增强版本覆盖
    /// - LLM 失败 → 静默回退本地,底部小灰字提示
    private var suggestionRow: some View {
        Group {
            if let suggestion = displayedSuggestion {
                VStack(alignment: .leading, spacing: 8) {
                    integratedSuggestionView(suggestion, isAIEnhanced: aiSuggestion != nil)
                    // AI 状态栏(loading chip / 错误提示 / 深入探讨)
                    suggestionFooter
                    // DEBUG 模式:卡片底部显示 LLM 调用指示器
                    LLMCallIndicator(caller: "BodyRadar")
                }
            } else if hrvManager.readiness.category == .insufficient {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(hrvManager.readiness.suggestion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !hrvManager.readiness.suggestion.isEmpty {
                Text(hrvManager.readiness.suggestion)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showDiscussion) {
            AIDiscussionSheet(
                title: "雷达建议 · 深入探讨".localized(),
                context: buildRadarDiscussionContext(),
                initialAssistantMessage: lastAIFullText ?? localSuggestion?.description,
                onDismiss: { showDiscussion = false }
            )
            .adaptiveSheet(detents: [.large])
        }
    }

    /// 建议底部的 AI 状态 / 操作栏
    @ViewBuilder
    private var suggestionFooter: some View {
        let configured = container.envManager.llmConfig.isConfigured
        HStack(spacing: 8) {
            // AI chip / 冷却倒计时
            if configured {
                if aiLoading {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.55)
                        Text("AI".localized())
                            .font(.caption2.weight(.bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.teal.opacity(0.12)))
                    .foregroundColor(.teal)
                } else if aiSuggestion != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2.weight(.bold))
                        Text("AI".localized())
                            .font(.caption2.weight(.bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.teal.opacity(0.18)))
                    .foregroundColor(.teal)
                } else if let msg = aiErrorMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if cooldownRemainingSeconds > 0 {
                    // 冷却中:每秒重绘倒计时(TimelineView 替代 1Hz Timer)。
                    // Per-second countdown redraw via TimelineView (replaces 1Hz Timer).
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(formatCooldown(cooldownRemainingSeconds))
                                .font(.caption2.monospacedDigit())
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            // 立刻分析:在冷却中 / 无 AI 结果时都允许点击(强制重置请求时间)
            if configured && localSuggestion != nil {
                Button {
                    requestAIImmediately()
                } label: {
                    Label("立刻分析".localized(), systemImage: "bolt.fill")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.teal)
                .disabled(aiLoading)
            }
            // 深入探讨:当 AI 已给结果 / 本地建议有内容时显示
            if localSuggestion != nil {
                Button {
                    showDiscussion = true
                } label: {
                    Label("深入探讨".localized(), systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.teal)
            }
        }
    }

    private func integratedSuggestionView(_ s: StudySuggestion, isAIEnhanced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(s.color.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: s.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(s.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(s.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    if isAIEnhanced {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundColor(.teal)
                    }
                }
                Text(s.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(s.color.opacity(0.08))
        )
    }

    // MARK: - AI 生命周期 / AI lifecycle

    /// 拉取最新数据后决定:本地建议立刻就位;若 LLM 已配置且不在冷却中则流式增强
    /// - 冷却:距上次请求小于用户设置的时间时跳过,显示本地建议 + 倒计时
    /// - "立刻分析" 按钮调用 `requestAIImmediately()` 强制绕过冷却
    private func refreshAI() {
        // 数据变更时,本地建议永远是 fallback;AI 状态重置
        aiTask?.cancel()
        aiLoading = false
        aiErrorMessage = nil
        aiSuggestion = nil
        lastAIFullText = nil

        guard container.envManager.llmConfig.isConfigured else { return }
        guard let local = localSuggestion else { return }

        // 冷却中 → 不发请求,但刷新倒计时让用户看到剩余时间
        if !canRequestNow() {
            return
        }

        runLLMRequest(fallback: local)
    }

    /// 用户点击"立刻分析":无视设置的冷却时间,立刻发请求并重置冷却起点。
    /// 公开入口:UI 上的 ⚡ 按钮直接调用此方法。
    func requestAIImmediately() {
        aiTask?.cancel()
        aiLoading = false
        aiErrorMessage = nil
        aiSuggestion = nil
        lastAIFullText = nil

        guard container.envManager.llmConfig.isConfigured else { return }
        guard let local = localSuggestion else { return }
        runLLMRequest(fallback: local)
    }

    /// 实际发起 LLM 请求的内部方法;请求前重置冷却起点,请求完成后再次刷新倒计时。
    private func runLLMRequest(fallback: StudySuggestion) {
        // 构造 LLM 上下文(包含 30 天基线 + 今日信号 + 本地建议)
        // 使用缓存的 recentAnnotations(避免每次都磁盘读 7 天的 difficulty annotations)
        let context = StudyReadinessAlgorithm.buildBodyReadinessContext(
            hrvEnabled: hrvManager.hrvEnabled,
            hrvOnboardingCompleted: hrvManager.hrvOnboardingCompleted,
            isAuthorized: hrvManager.isAuthorized,
            hrv: hrvManager.readiness,
            bodyStatus: hrvManager.bodyStatus,
            baselines: hrvManager.personalBaselines,
            age: container.profileRepo.profile.age,
            recentDifficultyAnnotations: recentAnnotations,
            recentMoodEntries: recentMoodEntries
        )
        lastBodyReadinessContext = context

        let config = container.envManager.llmConfig
        let prompt = BodyRadarLLM.makePrompt(context)
        aiLoading = true
        aiTask = Task {
            var accumulated = ""
            do {
                _ = try await LLMClient.shared.stream(prompt: prompt, config: config, caller: "BodyRadar") { snapshot in
                    accumulated = snapshot
                }
                if let parsed = BodyRadarLLM.parse(accumulated, fallback: fallback) {
                    aiSuggestion = parsed
                    lastAIFullText = accumulated
                    aiErrorMessage = nil
                } else {
                    aiErrorMessage = "AI 建议不可用,显示本地版本".localized()
                }
            } catch is CancellationError {
                // 正常取消
            } catch {
                aiErrorMessage = "AI 建议不可用,显示本地版本".localized()
                Log.llm.error("BodyRadarLLM stream failed: \(error.localizedDescription, privacy: .public)")
            }
            // 成功 / 失败 / 取消都重置冷却起点 —— 一次请求就消耗一次配额
            container.envManager.preferences.lastRadarAIRequestTime = Date()
            // 倒计时显示由 TimelineView + computed property 自动刷新,不再需要 updateCooldownRemaining
            aiLoading = false
        }
    }

    // MARK: - 雷达数值缓存 / Radar cache

    /// 重新计算 `cachedRadar`(在 `.task` 与各 `onChange` 中调用)。
    /// 主 body 评估时 0 次 compute;与原实现相比每次 body 评估减少 2 次 compute。
    /// Recompute `cachedRadar` (called from `.task` and `onChange`).
    /// 0 `compute` calls per body evaluation; removes the previous 2× per-eval cost.
    private func refreshRadar() {
        cachedRadar = BodyRadarValues.compute(
            hrv: hrvManager.readiness,
            body: hrvManager.bodyStatus,
            baselines: hrvManager.personalBaselines,
            age: container.profileRepo.profile.age,
            mistakes: container.mistakeRepo.filteredMistakeSets,
            recentAnnotations: recentAnnotations,
            recentMoodEntries: recentMoodEntries
        )
    }

    // MARK: - 冷却辅助 / Cooldown helpers

    /// 是否在冷却中(且未强制)
    private func canRequestNow() -> Bool {
        guard let last = container.envManager.preferences.lastRadarAIRequestTime else { return true }
        return Date().timeIntervalSince(last) >= radarAICooldownSeconds
    }

    /// 把剩余秒数格式化成 "mm:ss"(> 1 小时显示 "Hh Mm")
    private func formatCooldown(_ seconds: Int) -> String {
        if seconds <= 0 { return "00:00" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// 给"深入探讨" sheet 用的上下文:复刻 prompt 中的关键字段
    private func buildRadarDiscussionContext() -> String {
        guard let ctx = lastBodyReadinessContext else {
            // 兜底:在 lastBodyReadinessContext 没初始化时用当前数据
            let temp = StudyReadinessAlgorithm.buildBodyReadinessContext(
                hrvEnabled: hrvManager.hrvEnabled,
                hrvOnboardingCompleted: hrvManager.hrvOnboardingCompleted,
                isAuthorized: hrvManager.isAuthorized,
                hrv: hrvManager.readiness,
                bodyStatus: hrvManager.bodyStatus,
                baselines: hrvManager.personalBaselines,
                age: container.profileRepo.profile.age,
                recentDifficultyAnnotations: recentAnnotations,
                recentMoodEntries: recentMoodEntries
            )
            lastBodyReadinessContext = temp
            return BodyRadarLLM.makePrompt(temp).messages.first?.content
                ?? "雷达建议上下文"
        }
        return BodyRadarLLM.makePrompt(ctx).messages.first?.content
            ?? "雷达建议上下文"
    }

    // MARK: - Computed Properties / 计算属性
    private var accent: Color {
        if let cachedRadar {
            return cachedRadar.recoveryLevel.color
        }

        switch hrvManager.readiness.category {
        case .excellent: return .green
        case .normal: return .blue
        case .low: return .orange
        case .loading, .insufficient, .noAuthorization, .queryFailed: return .secondary
        }
    }

    private var readinessBadge: some View {
        Text(badgeLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(accent.opacity(0.15)))
            .foregroundColor(accent)
    }

    private var badgeLabel: String {
        if let cachedRadar {
            return "\(cachedRadar.recoveryScore) / 100 · \(cachedRadar.recoveryLevel.localizedLabel)"
        }

        switch hrvManager.readiness.category {
        case .excellent: return "Excellent".localized()
        case .normal: return "Normal".localized()
        case .low: return "Low".localized()
        case .loading: return "Loading...".localized()
        case .insufficient: return "Collecting".localized()
        case .noAuthorization: return "-"
        case .queryFailed: return "Error".localized()
        }
    }
}
