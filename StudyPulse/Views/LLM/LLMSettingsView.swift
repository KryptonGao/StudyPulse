//
//  LLMSettingsView.swift
//  StudyPulse
//
//  Settings → LLM 配置页。
//  主页面：开关、Cloud AI、Provider 列表、子页面入口
//  子页面：AI Coach、Rate Limits、Advanced
//

import SwiftUI
import os

struct LLMSettingsView: View {
    @Environment(RepositoryContainer.self) private var container

    @State private var temperature: Double = 0.7
    @State private var isTesting = false
    @State private var testAlertMessage: String? = nil
    @State private var testAlertSucceeded: Bool = false

    // Cloud AI
    @State private var cloudWorkerURL: String = ""
    @State private var cloudAPIKeyInput: String = ""
    @State private var isActivatingCloud: Bool = false
    @State private var isRefreshingProfile = false

    // Account
    @State private var showLoginSheet = false
    @State private var isLoggingOut = false

    var body: some View {
        List {
            Section {
                SettingsDetailHeader(category: .llm)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // ── 1. General ──
            Section {
                Toggle(isOn: Binding(
                    get: { container.envManager.llmEnabled },
                    set: { container.envManager.llmEnabled = $0 }
                )) {
                    Label("Enable LLM Features".localized(), systemImage: "brain")
                }
            }

            // ── 2. Cloud AI ──
            Section {
                    if container.envManager.isCloudSessionLoggedIn {
                    // ── Account mode ──
                    cloudAccountRow
                    LLMThinkingModePicker(
                        mode: Binding(
                            get: { container.envManager.preferences.cloudThinkingMode },
                            set: { container.envManager.setCloudThinkingMode($0) }
                        )
                    )
                    Text("深度思考由服务器最终决定。关闭响应更快、消耗更少积分；自动适合大多数问题；开启优先深度推理。".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    DisclosureGroup("Account".localized()) {
                        Button {
                            Task { await refreshProfile() }
                        } label: {
                            Label("Refresh Profile".localized(), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isRefreshingProfile)

                        Button(role: .destructive) {
                            Task { await performLogout() }
                        } label: {
                            if isLoggingOut { ProgressView().scaleEffect(0.8) }
                            else { Label("Logout".localized(), systemImage: "rectangle.portrait.and.arrow.right") }
                        }
                        .disabled(isLoggingOut)
                    }

                    DisclosureGroup("Beta API Key (Optional)".localized()) {
                        TextField("Worker URL".localized(), text: $cloudWorkerURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                            .keyboardType(.URL).font(.subheadline)
                        SecureField("API Key (sp_xxx)".localized(), text: $cloudAPIKeyInput)
                            .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                            .font(.subheadline)
                        if !cloudAPIKeyInput.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button { activateCloudProvider() } label: {
                                HStack {
                                    if isActivatingCloud { ProgressView().scaleEffect(0.8) }
                                    Text("Save Key".localized())
                                }.frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isActivatingCloud)
                        }
                        if container.envManager.hasCloudProvider {
                            Button(role: .destructive) {
                                container.envManager.disconnectCloudKey()
                                cloudAPIKeyInput = ""
                            } label: {
                                Label("Disconnect Key".localized(), systemImage: "xmark.circle")
                            }
                        }
                    }
                } else {
                    // ── Welcome: email login is the primary entry point ──
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.teal.opacity(0.12))
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.teal)
                        }
                        .frame(width: 64, height: 64)

                        Text("StudyPulse Cloud AI".localized())
                            .font(.headline)

                        Text("Log in with your email to get started. New accounts receive a free plan with 50 daily requests.".localized())
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Button { showLoginSheet = true } label: {
                            Label("Login with Email".localized(), systemImage: "envelope.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    DisclosureGroup("Manual API Key Setup (Advanced)".localized()) {
                        TextField("Worker URL".localized(), text: $cloudWorkerURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                            .keyboardType(.URL).font(.subheadline)
                        SecureField("API Key (sp_xxx)".localized(), text: $cloudAPIKeyInput)
                            .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                            .font(.subheadline)

                        if container.envManager.hasCloudProvider {
                            if container.envManager.isCloudProviderActive {
                                Button(role: .destructive) {
                                    container.envManager.deactivateCloudProvider()
                                } label: {
                                    Label("Deactivate".localized(), systemImage: "xmark.circle")
                                }
                            } else {
                                Button { activateCloudProvider() } label: {
                                    HStack {
                                        if isActivatingCloud { ProgressView().scaleEffect(0.8) }
                                        Text("Activate".localized())
                                    }.frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isActivatingCloud)
                            }

                            Button(role: .destructive) {
                                container.envManager.deleteCloudProvider()
                                cloudAPIKeyInput = ""
                                cloudWorkerURL = container.envManager.preferences.cloudAIWorkerURL ?? "spapi.chenkai.space"
                            } label: {
                                Label("Remove".localized(), systemImage: "trash")
                            }
                        } else {
                            Button { activateCloudProvider() } label: {
                                HStack {
                                    if isActivatingCloud { ProgressView().scaleEffect(0.8) }
                                    Text("Activate".localized())
                                }.frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isActivatingCloud || cloudAPIKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            } header: {
                Text("Cloud AI".localized())
            }

            CloudAIQuotaListSection()

            // ── 3. Provider List (unified: Cloud AI + BYOK) ──
            Section {
                let allProviders = container.envManager.preferences.llmProviders
                if allProviders.isEmpty {
                    Text("No providers configured".localized()).foregroundColor(.secondary)
                }
                ForEach(allProviders) { provider in
                    unifiedProviderRow(provider)
                }
            } header: {
                Text("Active Model".localized())
            } footer: {
                Text("Tap a provider to make it active. Add your own OpenAI-compatible endpoints below.".localized())
            }

            // ── 4. Add BYOK Provider ──
            Section {
                Button { container.envManager.addLLMProvider() } label: {
                    Label("Add Custom Provider".localized(), systemImage: "plus.circle.fill")
                }
            }

            // ── 5. Sub-pages ──
            Section {
                NavigationLink(destination: LLMAICoachSettingsView()) {
                    Label("AI Coach".localized(), systemImage: "brain.head.profile")
                }
                NavigationLink(destination: LLMAdvancedSettingsView()) {
                    Label("Advanced".localized(), systemImage: "gearshape.2")
                }
            }

            // ── 6. Actions ──
            Section {
                // DEBUG: 显示 LLMConfig 诊断信息
                let cfg = container.envManager.llmConfig
                VStack(alignment: .leading, spacing: 2) {
                    Text("enabled=\(cfg.enabled ? "YES" : "NO") | isCloud=\(cfg.isCloudProvider ? "YES" : "NO") | baseURL=\(cfg.baseURL ?? "nil")")
                        .font(.caption2.monospaced()).foregroundColor(.orange)
                    Text("hasSession=\(cfg.sessionToken != nil ? "YES" : "NO") | hasAPIKey=\(cfg.apiKey != nil ? "YES" : "NO") | model=\(cfg.model ?? "nil")")
                        .font(.caption2.monospaced()).foregroundColor(.orange)
                    Text("→ isConfigured = \(cfg.isConfigured ? "TRUE" : "FALSE")")
                        .font(.caption2.monospaced().bold()).foregroundColor(cfg.isConfigured ? .green : .red)
                }

                Button {
                    Task { await runTestConnection() }
                } label: {
                    HStack {
                        if isTesting { ProgressView().scaleEffect(0.8) }
                        else { Image(systemName: "antenna.radiowaves.left.and.right") }
                        Text("Test Connection".localized())
                    }
                }
                .disabled(isTesting || !container.envManager.llmConfig.isConfigured)

                NavigationLink(destination: LLMChatView()) {
                    Label("AI Assistant".localized(), systemImage: "bubble.left.and.bubble.right.fill")
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
        .containerBackground(.clear, for: .navigation)
        .refreshable {
            if container.envManager.isCloudSessionLoggedIn {
                await container.envManager.refreshCloudQuota()
            }
        }
        .debugModeContainer()
        .debugLayoutBoundsAuto()
        .navigationTitle("LLM".localized())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            syncFromPreferences()
            if container.envManager.isCloudSessionLoggedIn {
                Task { await refreshProfile() }
            }
        }
        .sheet(isPresented: $showLoginSheet) { LoginView() }
        .alert(
            testAlertSucceeded ? "Connection successful".localized() : "Connection failed".localized(),
            isPresented: Binding(get: { testAlertMessage != nil }, set: { if !$0 { testAlertMessage = nil } })
        ) {
            Button("OK".localized(), role: .cancel) {}
        } message: {
            Text(testAlertMessage ?? "")
        }
    }

    // MARK: - Sub-views

    private var cloudAccountRow: some View {
        HStack {
            Image(systemName: "person.circle.fill").foregroundColor(.teal).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(container.envManager.preferences.cloudSessionEmail ?? "")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text("Logged in".localized()).font(.caption).foregroundColor(.secondary)
                    if let type = container.envManager.preferences.cloudMembershipType {
                        Text(membershipName(type))
                            .font(.caption2.weight(.bold))
                            .foregroundColor(membershipColor(type))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(membershipColor(type).opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
        }
    }

    /// Unified provider row: Cloud AI and BYOK share the same selectable list.
    private func unifiedProviderRow(_ provider: LLMProvider) -> some View {
        let isActive = provider.id == container.envManager.preferences.activeLLMProviderId
        let isCloud = provider.isCloudProvider
        let isConfigured = container.envManager.isLLMProviderConfigured(provider)

        let icon: String = isCloud ? "cloud.fill" : "server.rack"
        let iconColor: Color = isCloud ? .accentColor : .secondary
        let title = isCloud ? "StudyPulse Cloud AI".localized() : (provider.name.isEmpty ? "Unnamed".localized() : provider.name)
        let subtitle: String = {
            if isCloud {
                return container.envManager.isCloudSessionLoggedIn
                    ? String(format: "%@ · Account".localized(), provider.model)
                    : String(format: "%@ · Key".localized(), provider.model)
            }
            return isConfigured ? provider.model : "Incomplete configuration".localized()
        }()

        return HStack(spacing: 12) {
            Button { container.envManager.selectLLMProvider(provider.id) } label: {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isActive ? .green : .secondary.opacity(0.5))
                    .font(.title3)
            }.buttonStyle(.plain)

            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            if !isCloud {
                NavigationLink(destination: LLMProviderEditor(provider: provider)) {
                    EmptyView()
                }.frame(width: 0).opacity(0) // invisible chevron for tap area
            }

            if isActive {
                Image(systemName: "checkmark").foregroundColor(.green).font(.caption.weight(.bold))
            }
        }
        .swipeActions {
            if !isCloud {
                Button(role: .destructive) { container.envManager.deleteLLMProvider(provider.id) } label: {
                    Label("Delete".localized(), systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Helpers

    private func membershipColor(_ type: String) -> Color {
        switch type { case "pro": return .purple; case "plus": return .blue; default: return .secondary }
    }

    private func membershipName(_ type: String) -> String {
        switch type.lowercased() {
        case "free": return "Free".localized()
        case "plus": return "Plus".localized()
        case "pro": return "Pro".localized()
        default: return type.capitalized
        }
    }

    private func syncFromPreferences() {
        let prefs = container.envManager.preferences
        cloudWorkerURL = prefs.cloudAIWorkerURL ?? ""
        if container.envManager.hasCloudProvider {
            cloudAPIKeyInput = container.envManager.cloudAPIKey
        }
    }

    @MainActor private func activateCloudProvider() {
        let url = cloudWorkerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = cloudAPIKeyInput.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty, !key.isEmpty else { return }
        isActivatingCloud = true
        defer { isActivatingCloud = false }
        do { try container.envManager.activateCloudProvider(workerURL: url, apiKey: key) }
        catch {
            testAlertSucceeded = false
            testAlertMessage = String(format: "Failed to save API Key: %@".localized(), error.localizedDescription)
        }
    }

    @MainActor private func performLogout() async {
        isLoggingOut = true; defer { isLoggingOut = false }
        let token = container.envManager.cloudSessionToken ?? ""
        let url = container.envManager.preferences.cloudAIWorkerURL ?? ""
        if !token.isEmpty, !url.isEmpty {
            try? await AuthClient.shared.logout(sessionToken: token, workerURL: url)
        }
        container.envManager.cloudSessionLogout()
    }

    @MainActor private func runTestConnection() async {
        isTesting = true; defer { isTesting = false }
        do {
            try await LLMClient.shared.testConnection(config: container.envManager.llmConfig)
            testAlertSucceeded = true; testAlertMessage = "Endpoint reachable, model responded.".localized()
        } catch let error as LLMError {
            testAlertSucceeded = false; testAlertMessage = error.errorDescription
        } catch {
            testAlertSucceeded = false; testAlertMessage = error.localizedDescription
        }
    }

    @MainActor private func refreshProfile() async {
        isRefreshingProfile = true; defer { isRefreshingProfile = false }
        await container.envManager.refreshCloudProfile()
        // 确保 Cloud AI 是活跃 provider
        if let cloud = container.envManager.preferences.llmProviders.first(where: { $0.isCloudProvider }) {
            container.envManager.preferences.activeLLMProviderId = cloud.id
        }
    }
}

// MARK: - AI Coach Settings

private struct LLMAICoachSettingsView: View {
    @Environment(RepositoryContainer.self) private var container
    @State private var isForceRefreshingCoach = false
    @State private var lastRefreshSucceeded: Bool?
    @State private var lastRefreshDetail: String = ""
    @State private var showRefreshAlert = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { container.envManager.preferences.coachEnabled },
                    set: { container.envManager.preferences.coachEnabled = $0 }
                )) {
                    Label("Enable AI Coach".localized(), systemImage: "brain.head.profile")
                }
            } footer: {
                Text("AI Coach is a separate opt-in. Major health changes are judged on-device; only then is a proposed plan generated through your configured LLM.".localized())
            }

            if container.envManager.preferences.coachEnabled {
                Section {
                    Toggle(isOn: Binding(
                        get: { container.envManager.preferences.coachAdaptivePlanEnabled },
                        set: { container.envManager.preferences.coachAdaptivePlanEnabled = $0 }
                    )) {
                        Label("Adapt plan for health changes".localized(), systemImage: "heart.text.square")
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { container.envManager.preferences.coachNotificationEnabled },
                        set: { container.envManager.preferences.coachNotificationEnabled = $0; CoachNotifications.shared.reschedule(enabled: $0, hour: container.envManager.preferences.coachNotificationHour) }
                    )) {
                        Label("Daily Coach Notification".localized(), systemImage: "bell.badge")
                    }
                    Stepper(value: Binding(
                        get: { container.envManager.preferences.coachNotificationHour },
                        set: { container.envManager.preferences.coachNotificationHour = max(0, min(23, $0)); CoachNotifications.shared.reschedule(enabled: container.envManager.preferences.coachNotificationEnabled, hour: $0) }
                    ), in: 0...23) {
                        Text(String(format: "%02d:00", container.envManager.preferences.coachNotificationHour))
                    }
                }

                Section {
                    Button { Task { await forceRefreshCoach() } } label: {
                        HStack {
                            if isForceRefreshingCoach { ProgressView().scaleEffect(0.8) }
                            else { Image(systemName: "arrow.clockwise.circle.fill") }
                            Text("Force Refresh".localized())
                            Spacer()
                            if let lastRefreshSucceeded, !isForceRefreshingCoach {
                                Image(systemName: lastRefreshSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(lastRefreshSucceeded ? Color.green : Color.orange)
                            }
                        }
                    }
                    .disabled(isForceRefreshingCoach || !container.envManager.llmConfig.isConfigured)
                } footer: {
                    if let lastRefreshSucceeded {
                        Text(lastRefreshDetail)
                            .foregroundStyle(lastRefreshSucceeded ? Color.secondary : Color.red)
                    }
                }
            }
        }
        .navigationTitle("AI Coach".localized())
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            lastRefreshSucceeded == true
                ? "Coach refresh successful".localized()
                : "Coach refresh failed".localized(),
            isPresented: $showRefreshAlert
        ) {
            Button("OK".localized(), role: .cancel) {}
        } message: {
            Text(lastRefreshDetail)
        }
    }

    @MainActor private func forceRefreshCoach() async {
        isForceRefreshingCoach = true
        defer { isForceRefreshingCoach = false }
        do {
            _ = try await CoachCoordinator(container: container).forceRefreshProposal()
            lastRefreshSucceeded = true
            lastRefreshDetail = "A fresh AI Coach proposal is ready to review.".localized()
            showRefreshAlert = true
            Log.app.info("Coach Force Refresh succeeded")
            Log.record(.info, category: "App", message: "Coach Force Refresh succeeded")
        } catch {
            lastRefreshSucceeded = false
            lastRefreshDetail = coachRefreshFailureMessage(error)
            showRefreshAlert = true
            Log.app.error("Coach Force Refresh failed: \(error.localizedDescription, privacy: .public)")
            Log.record(.error, category: "App", message: "Coach Force Refresh failed: \(error.localizedDescription)")
        }
    }

    private func coachRefreshFailureMessage(_ error: Error) -> String {
        if let llmError = error as? LLMError, let description = llmError.errorDescription, !description.isEmpty {
            return description
        }
        if let coordinatorError = error as? CoachCoordinatorError,
           let description = coordinatorError.errorDescription,
           !description.isEmpty {
            return description
        }
        let description = error.localizedDescription
        return description.isEmpty ? "Coach refresh failed".localized() : description
    }
}

// MARK: - Advanced Settings

private struct LLMAdvancedSettingsView: View {
    @Environment(RepositoryContainer.self) private var container
    @State private var appendixInput: String = ""
    @State private var temperature: Double = 0.7
    @State private var radarCooldownMinutes: Int = 40
    @State private var overrideInput: String = ""

    var body: some View {
        List {
            // Temperature
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Temperature".localized()).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", temperature)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
                    }
                    Slider(value: $temperature, in: 0...2, step: 0.1)
                        .onChange(of: temperature) { _, v in container.envManager.setLLMTemperature(v) }
                }
            }

            // System Prompt
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("System Prompt Appendix".localized()).font(.caption).foregroundColor(.secondary)
                    TextEditor(text: $appendixInput)
                        .frame(minHeight: 100)
                        .onChange(of: appendixInput) { _, v in container.envManager.setLLMSystemPromptAppendix(v.isEmpty ? nil : v) }
                }
            } footer: {
                Text("Optional. Appended to the default system prompt for every AI feature.".localized())
            }

            // Rate Limits
            Section {
                Stepper(value: $radarCooldownMinutes, in: 5...180, step: 5) {
                    HStack {
                        Label("Recovery Radar Cooldown".localized(), systemImage: "heart.text.square")
                        Spacer()
                        Text(String(format: "%d min".localized(), radarCooldownMinutes)).foregroundColor(.secondary).monospacedDigit()
                    }
                }
                .onChange(of: radarCooldownMinutes) { _, v in container.envManager.setRadarAICooldownMinutes(v) }

                Toggle("Enable Habit Insight".localized(), isOn: Binding(
                    get: { container.envManager.preferences.habitInsightEnabled },
                    set: { container.envManager.setHabitInsightEnabled($0) }
                ))
                if container.envManager.preferences.habitInsightEnabled {
                    Stepper(value: Binding(
                        get: { container.envManager.preferences.habitInsightCooldownMinutes },
                        set: { container.envManager.setHabitInsightCooldownMinutes($0) }
                    ), in: 5...180, step: 5) {
                        Text("Habit Insight Cooldown".localized())
                    }
                    Toggle("Daily Notification".localized(), isOn: Binding(
                        get: { container.envManager.preferences.habitInsightNotificationEnabled },
                        set: { e in container.envManager.setHabitInsightNotificationEnabled(e)
                            let p = container.envManager.preferences
                            HabitInsightNotifications.shared.reschedule(enabled: e, hour: p.habitInsightNotificationHour, body: p.lastHabitInsightNotificationBody) }
                    ))
                    Stepper(value: Binding(
                        get: { container.envManager.preferences.habitInsightNotificationHour },
                        set: { h in container.envManager.setHabitInsightNotificationHour(h)
                            let p = container.envManager.preferences
                            HabitInsightNotifications.shared.reschedule(enabled: p.habitInsightNotificationEnabled, hour: h, body: p.lastHabitInsightNotificationBody) }
                    ), in: 0...23) {
                        Text("Notification Hour".localized())
                    }
                }
            } header: {
                Text("Rate Limits".localized())
            }

            // DEBUG override
            if container.envManager.debugModeEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "ladybug.fill").foregroundColor(.yellow)
                            Text("DEBUG: Override System Prompt".localized()).font(.caption.weight(.semibold))
                        }
                        TextEditor(text: $overrideInput)
                            .frame(minHeight: 140).font(.system(.footnote, design: .monospaced))
                            .onChange(of: overrideInput) { _, v in container.envManager.setLLMDebugOverrideSystemPrompt(v.isEmpty ? nil : v) }
                        if !overrideInput.isEmpty {
                            Button(role: .destructive) {
                                overrideInput = ""; container.envManager.setLLMDebugOverrideSystemPrompt(nil)
                            } label: { Label("Clear".localized(), systemImage: "trash").font(.caption) }
                        }
                    }
                } header: {
                    HStack { Image(systemName: "ladybug.fill").foregroundColor(.yellow); Text("DEBUG Override".localized()) }
                }
            }
        }
        .navigationTitle("Advanced".localized())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let prefs = container.envManager.preferences
            appendixInput = prefs.llmSystemPromptAppendix ?? ""
            temperature = prefs.llmTemperature
            radarCooldownMinutes = prefs.radarAICooldownMinutes
            overrideInput = prefs.debugOverrideSystemPrompt ?? ""
        }
    }
}

// MARK: - Provider Editor

private struct LLMProviderEditor: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    let provider: LLMProvider
    @State private var name: String
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var model: String
    @State private var multimodalEnabled: Bool
    @State private var thinkingEnabled: Bool
    @State private var saveError: String?

    init(provider: LLMProvider) {
        self.provider = provider
        _name = State(initialValue: provider.name)
        _baseURL = State(initialValue: provider.baseURL)
        _apiKey = State(initialValue: "")
        _model = State(initialValue: provider.model)
        _multimodalEnabled = State(initialValue: provider.multimodalEnabled)
        _thinkingEnabled = State(initialValue: provider.thinkingEnabled)
    }

    var body: some View {
        Form {
            if provider.isCloudProvider {
                Section {
                    HStack {
                        Image(systemName: "cloud.fill").foregroundColor(.accentColor)
                        Text("StudyPulse Cloud AI (Beta)".localized()).font(.headline)
                    }
                    Text(String(format: "Model: %@ · Multimodal: On · Thinking: Off".localized(), provider.model))
                        .font(.caption).foregroundColor(.secondary)
                    SecureField("API Key (sp_xxx)".localized(), text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                } header: { Text("Connection".localized()) }
            } else {
                Section {
                    TextField("Provider Name".localized(), text: $name)
                    TextField("https://api.openai.com", text: $baseURL, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled(true).keyboardType(.URL)
                    SecureField("API Key".localized(), text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                    TextField("gpt-4o-mini", text: $model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                    Toggle("Enable Multimodal".localized(), isOn: $multimodalEnabled)
                    Toggle("Enable Thinking".localized(), isOn: $thinkingEnabled)
                } header: { Text("Connection".localized()) }
            }

            Section {
                Button { container.envManager.selectLLMProvider(provider.id) } label: {
                    Label(provider.id == container.envManager.preferences.activeLLMProviderId
                        ? "Active Provider".localized() : "Use This Provider".localized(),
                        systemImage: provider.id == container.envManager.preferences.activeLLMProviderId
                        ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .disabled(provider.id == container.envManager.preferences.activeLLMProviderId)
            }
        }
        .navigationTitle("Provider".localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done".localized()) { if save() { dismiss() } }
            }
        }
        .task {
            apiKey = provider.isCloudProvider
                ? container.envManager.cloudAPIKey
                : container.envManager.llmAPIKey(for: provider.id)
        }
        .alert("Unable to Save API Key".localized(), isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK".localized(), role: .cancel) {}
        } message: { Text(saveError ?? "") }
    }

    private func save() -> Bool {
        do {
            let updatedProvider: LLMProvider
            if provider.isCloudProvider {
                updatedProvider = LLMProvider(id: provider.id, name: provider.name, baseURL: provider.baseURL,
                    model: provider.model, multimodalEnabled: provider.multimodalEnabled,
                    thinkingEnabled: provider.thinkingEnabled, isCloudProvider: true)
            } else {
                updatedProvider = LLMProvider(id: provider.id,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                    multimodalEnabled: multimodalEnabled, thinkingEnabled: thinkingEnabled)
            }
            try container.envManager.updateLLMProvider(updatedProvider, apiKey: apiKey)
            return true
        } catch {
            saveError = "The API key could not be stored securely.".localized()
            return false
        }
    }
}
