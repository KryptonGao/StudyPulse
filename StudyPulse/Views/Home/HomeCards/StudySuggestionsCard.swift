//
//  StudySuggestionsCard.swift
//  StudyPulse
//
//  主页"学习建议"卡片:基于 grades / mistakes / exams / 身体状态
// 给出 3 条最高优先级建议。建议生成已迁入 HomeViewModel.generateSuggestions(...)
// (底层调用 SuggestionEngine);卡片本身只负责渲染。
//
//  Home "Study Suggestions" card: produces the top-3 highest-priority suggestions
//  based on grades / mistakes / exams / body status. Suggestion generation has
//  been moved into HomeViewModel.generateSuggestions(...) (calls SuggestionEngine
//  underneath); this card only renders.
//
//  LLM BYOK 增强(2026-07-11):当 `AppPreferences.llmEnabled == true` 时,
//  卡片额外调用 `LLMClient.stream` 拉取 3 条 AI 建议并流式覆盖本地结果;
//  失败时静默回退到本地建议 + 显示 "AI 建议不可用"。
//  LLM BYOK enhancement (2026-07-11): when `AppPreferences.llmEnabled == true`,
//  the card additionally calls `LLMClient.stream` to fetch 3 AI suggestions and
//  stream-overrides the local result; on failure it silently falls back to
//  local suggestions + shows "AI suggestions unavailable".
//
//  Extracted from HomeView.swift during card-extraction refactor (2026-07-05).
//

import SwiftUI

/// 主页"学习建议"卡片。
/// 由父 View 注入 `HomeViewModel`(VM 暴露 `generateSuggestions(limit:)`)。
/// 卡片观察 `HealthKitManager.shared` 的 `bodyStatus`,身体状态变化时刷新建议。
/// Home "Study Suggestions" card.
/// The parent View injects `HomeViewModel` (VM exposes `generateSuggestions(limit:)`).
/// The card observes `HealthKitManager.shared.bodyStatus` and refreshes suggestions
/// when the body status changes.
struct StudySuggestionsCard: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(HealthKitManager.self) private var healthManager: HealthKitManager
    @Environment(RepositoryContainer.self) private var container

    /// 本地建议(由 `HomeViewModel.generateSuggestions` 产生,作为 fallback)
    /// Local suggestions (produced by `HomeViewModel.generateSuggestions`, used as fallback).
    @State private var localSuggestions: [StudySuggestion] = []
    /// AI 建议(流式累积,任意时刻可被本地覆盖以回退)
    /// AI suggestions (streamed-accumulated; can be overwritten by nil to fall back).
    @State private var aiSuggestions: [StudySuggestion]? = nil
    /// 当前 LLM 流式任务;进入卡片/重新加载前 cancel 旧任务
    /// Current LLM streaming task; cancel any in-flight task before entering / reloading.
    @State private var aiTask: Task<Void, Never>? = nil
    /// AI 错误信息(用于显示"AI 建议不可用"小灰字)
    /// AI error message (shown as the small grey "AI suggestions unavailable" hint).
    @State private var aiErrorMessage: String? = nil
    /// AI 加载中(用于显示 progress chip)
    /// Whether AI suggestions are currently loading (drives the progress chip).
    @State private var aiLoading: Bool = false
    @State private var showingHealthDataConsent: Bool = false

    /// 冷却时长(秒):默认 40 分钟,跟雷达卡片同。
    /// Cooldown duration (seconds). Same 40-minute rate limit as the body-radar card.
    private static let suggestionsAICooldownSeconds: TimeInterval = 40 * 60
    /// 距下次可自动请求的剩余秒数(基于 `lastStudySuggestionsAIRequestTime` 计算)。
    /// 倒计时显示由 `TimelineView(.periodic(by: 1))` 每秒重绘,不再用 1Hz Timer 唤醒。
    /// Remaining seconds until the next auto-request is allowed (computed from `lastStudySuggestionsAIRequestTime`).
    /// The countdown text is redrawn by `TimelineView(.periodic(by: 1))`,no more 1Hz Timer wakeups.
    private var cooldownRemainingSeconds: Int {
        guard let last = container.envManager.preferences.lastStudySuggestionsAIRequestTime else { return 0 }
        let elapsed = Date().timeIntervalSince(last)
        return max(0, Int((Self.suggestionsAICooldownSeconds - elapsed).rounded()))
    }

    /// 当前展示的建议(优先 AI,失败/未启用时本地)
    /// Suggestions currently displayed (prefer AI, fall back to local on failure / disabled).
    private var displayed: [StudySuggestion] {
        aiSuggestions ?? localSuggestions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Study Suggestions".localized())
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)

                if container.envManager.llmConfig.isConfigured && aiSuggestions != nil {
                    aiChip
                } else if container.envManager.llmConfig.isConfigured && aiLoading {
                    aiLoadingChip
                }

                Spacer()

                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.yellow)
            }

            if displayed.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Start adding grades to get suggestions!".localized())
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(displayed.prefix(3), id: \.id) { suggestion in
                        SuggestionRowView(suggestion: suggestion)
                    }
                    if container.envManager.llmConfig.isConfigured && aiErrorMessage != nil && aiSuggestions == nil {
                        Text(aiErrorMessage ?? "")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            // DEBUG 模式:卡片底部显示 LLM 调用指示器(让用户能看出刚刚的请求来自哪个卡片)
            if container.envManager.llmConfig.isConfigured {
                LLMCallIndicator(caller: "StudySuggestions")
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
        .onAppear {
            reload()
        }
        .onDisappear {
            aiTask?.cancel()
        }
        .debugLayoutBoundsAuto()
        .onChange(of: healthManager.bodyStatus) { _, _ in reload() }
        .sheet(isPresented: $showingHealthDataConsent) {
            HealthDataLLMConsentSheet { allowed in
                if allowed {
                    aiTask = Task { await streamAI() }
                }
            }
            .environment(container)
        }
    }

    // MARK: - AI chip

    /// 标题右侧的「AI」徽标(已成功拿到 AI 建议时)
    /// "AI" badge on the right of the title (shown when AI suggestions are ready).
    private var aiChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text("AI".localized())
                .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.teal.opacity(0.18)))
        .foregroundColor(.teal)
    }

    /// 标题右侧的「AI」加载中徽标(请求进行中时)
    /// "AI" loading badge on the right of the title (shown while the request is in flight).
    private var aiLoadingChip: some View {
        HStack(spacing: 4) {
            ProgressView().scaleEffect(0.55)
            Text("AI".localized())
                .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.teal.opacity(0.12)))
        .foregroundColor(.teal)
    }

    // MARK: - Reload

    /// 拉取最新 3 条本地建议 + 可选的 AI 建议。
    /// 失败时静默回退到本地版本。
    /// Fetch the latest 3 local suggestions + optional AI suggestions.
    /// On failure it silently falls back to the local version.
    private func reload() {
        // 1) 本地建议总是先就位
        localSuggestions = viewModel.generateSuggestions(limit: 3)

        // 2) 如果 LLM 未配置 / 未启用,直接展示本地版本
        guard container.envManager.llmConfig.isConfigured else {
            aiSuggestions = nil
            aiErrorMessage = nil
            aiLoading = false
            return
        }

        // 3) 取消上一次流式任务
        aiTask?.cancel()
        aiErrorMessage = nil
        aiSuggestions = nil

        // 4) 冷却期内直接跳过 LLM,显示本地版本
        //    跟 BodyRadar 卡片行为一致:不阻塞 UI、也不报错。
        guard canRequestNow() else {
            aiLoading = false
            return
        }

        aiLoading = true
        aiTask = Task {
            await streamAI()
        }
    }

    @MainActor
    private func streamAI() async {
        let config = container.envManager.llmConfig
        let context = viewModel.buildSuggestionsContext()
        let prompt = StudySuggestionsLLM.makePrompt(context)
        var accumulated = ""
        do {
            _ = try await LLMClient.shared.stream(prompt: prompt, config: config, caller: "StudySuggestions") { snapshot in
                accumulated = snapshot
            }
            if let parsed = StudySuggestionsLLM.parse(accumulated) {
                aiSuggestions = parsed
                aiErrorMessage = nil
            } else {
                // 解析失败 → 回退本地
                aiSuggestions = nil
                aiErrorMessage = "AI 建议不可用,显示本地版本".localized()
            }
        } catch is CancellationError {
            // 正常取消,保持当前状态
        } catch let error as LLMError {
            aiSuggestions = nil
            aiErrorMessage = "AI 建议不可用,显示本地版本".localized()
            if error == .healthDataConsentRequired {
                showingHealthDataConsent = true
            }
        } catch {
            aiSuggestions = nil
            aiErrorMessage = "AI 建议不可用,显示本地版本".localized()
        }
        // 成功 / 失败 / 取消都重置冷却起点
        container.envManager.preferences.lastStudySuggestionsAIRequestTime = Date()
        aiLoading = false
    }

    // MARK: - 冷却辅助
    // MARK: - Cooldown Helpers

    /// 当前是否允许发起一次 LLM 请求(距离上次已过完冷却期)。
    /// Whether a new LLM request is allowed right now (cooldown elapsed since the last request).
    private func canRequestNow() -> Bool {
        guard let last = container.envManager.preferences.lastStudySuggestionsAIRequestTime else { return true }
        return Date().timeIntervalSince(last) >= Self.suggestionsAICooldownSeconds
    }
}

// MARK: - 建议行视图
// MARK: - Suggestion Row View

/// 单条学习建议行(展开/收起描述)。
/// Single study-suggestion row (expand / collapse the description).
struct SuggestionRowView: View {
    let suggestion: StudySuggestion
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(suggestion.color.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: suggestion.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(suggestion.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(suggestion.description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                }

                Spacer()

                PriorityIndicator(priority: suggestion.priority)
            }

            if !isExpanded {
                Button(action: { isExpanded = true }) {
                    Text("Read more".localized())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground).opacity(0.6))
        .cornerRadius(14)
    }
}

// MARK: - 优先级指示器
// MARK: - Priority Indicator

/// SuggestionRowView 右上角小色块(HIGH / MED / LOW)。
/// Small colored chip in the top-right of SuggestionRowView (HIGH / MED / LOW).
struct PriorityIndicator: View {
    let priority: StudySuggestion.Priority

    var body: some View {
        ZStack {
            Capsule()
                .fill(color.opacity(0.15))

            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .frame(height: 20)
    }

    private var label: String {
        switch priority {
        case .high: return "HIGH".localized()
        case .medium: return "MED".localized()
        case .low: return "LOW".localized()
        }
    }

    private var color: Color {
        // 优先级颜色:HIGH 红 / MED 橙 / LOW 绿
        // Priority colors: HIGH red / MED orange / LOW green.
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }
}
