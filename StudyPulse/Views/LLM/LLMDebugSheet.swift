//
//  LLMDebugSheet.swift
//  StudyPulse
//
//  DEBUG 模式专用:显示最近一次 LLM 调用的全部调试信息
//  - URL / Model / Temperature
//  - 完整 prompt (system + messages)
//  - 思考时间 (elapsed seconds)
//  - 响应 / 错误
//  - 一键复制为 JSON
//
//  DEBUG-only: shows the full debug info of the most recent LLM call.
//  - URL / Model / Temperature
//  - Full prompt (system + messages)
//  - Thinking time (elapsed seconds)
//  - Response / error
//  - One-tap copy as JSON
//
//  仅当 `AppEnvironmentManager.debugModeEnabled == true` 时挂载入口按钮。
//  Only mounts the entry button when `AppEnvironmentManager.debugModeEnabled == true`.
//

import SwiftUI

/// DEBUG 模式下面板:展示最近一次 LLM 调用的 URL / Prompt / 思考时间 / 响应。
/// DEBUG-mode panel showing the most recent LLM call's URL / prompt / thinking time / response.
struct LLMDebugSheet: View {
    @Environment(LLMClient.self) private var client: LLMClient
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    /// 自定义"最近一次"指针:为 nil 时顶部显示"最近调用"选择器(可切换不同 caller)。
    /// 传入非 nil 时,顶部隐藏选择器,只显示该 caller 的最近一次。
    /// Custom "most recent" pointer: when nil, a caller picker is shown at
    /// the top. When non-nil, the picker is hidden and only that caller's
    /// most recent call is displayed.
    let filterCaller: String?

    /// 当一个页面上有多个 AI 功能时,传入此值可只显示本功能相关的最近一次。
    /// Pass this to scope the panel to one caller's most recent call
    /// (used when a page hosts multiple AI features).
    init(filterCaller: String? = nil) {
        self.filterCaller = filterCaller
    }

    /// 用户在 picker 里临时选择的 caller(用于 filterCaller == nil 时的浏览)
    /// Caller selected by the user in the picker (for browsing when
    /// `filterCaller == nil`).
    @State private var selectedCaller: String? = nil

    /// 按 caller 分组的最近调用(用于顶部 picker / 历史列表)
    /// Group recent calls by caller for the picker / history list.
    private var callsByCaller: [(caller: String, info: LLMCallDebugInfo)] {
        let groups = Dictionary(grouping: client.recentCalls) { $0.caller }
        return groups
            .map { (caller: $0.key, info: $0.value.last!) }
            // 最新一组在前
            // Newest group first.
            .sorted { $0.info.startTime > $1.info.startTime }
    }

    /// 当前要展示的 call info(filterCaller > selectedCaller > 全局最近)
    /// The call info to display (filterCaller > selectedCaller > global most-recent).
    private var displayInfo: LLMCallDebugInfo? {
        if let filterCaller {
            return client.recentCalls.last(where: { $0.caller == filterCaller })
        }
        if let selectedCaller {
            return client.recentCalls.last(where: { $0.caller == selectedCaller })
        }
        return client.lastCallInfo
    }

    var body: some View {
        NavigationStack {
            Group {
                if displayInfo == nil && client.recentCalls.isEmpty {
                    emptyView
                } else if let info = displayInfo {
                    contentList(info: info)
                } else {
                    // filterCaller 指定但还没有该 caller 的调用 → 引导用户触发
                    pendingView
                }
            }
            .navigationTitle("LLM Debug".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close".localized()) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let info = displayInfo {
                        Button {
                            UIPasteboard.general.string = info.asDebugJSON()
                        } label: {
                            Label("Copy JSON".localized(), systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty / 空态

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "ladybug")
                .scaledFont(size: 48)
                .foregroundColor(.secondary)
            Text("暂无 LLM 调用记录".localized())
                .font(.headline)
            Text("触发任意 AI 功能后,这里会显示 URL / Prompt / 思考时间 / 响应。".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pendingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .scaledFont(size: 40)
                .foregroundColor(.secondary)
            Text("该模块还没有 LLM 调用".localized())
                .font(.headline)
            Text("请先触发该功能,再打开此面板。".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content / 内容区

    @ViewBuilder
    private func contentList(info: LLMCallDebugInfo) -> some View {
        List {
            // 顶部 caller picker(filterCaller 为 nil 时才有;列出本次会话所有 caller)
            // Top caller picker (only when filterCaller == nil; lists every
            // caller seen in this session).
            if filterCaller == nil && !callsByCaller.isEmpty {
                Section {
                    ForEach(callsByCaller, id: \.caller) { entry in
                        Button {
                            selectedCaller = entry.caller
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle")
                                    .foregroundColor(.teal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.caller)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                    Text(relativeTime(entry.info.startTime) + " · " +
                                         String(format: "%.1fs", entry.info.elapsedSeconds) +
                                         (entry.info.error == nil ? " · OK" : " · ERR"))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if entry.caller == (selectedCaller ?? client.lastCallInfo?.caller ?? "") {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.teal)
                                }
                            }
                        }
                    }
                    Button {
                        selectedCaller = nil
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.secondary)
                            Text("显示最近一次(不限 caller)".localized())
                                .font(.subheadline)
                            Spacer()
                            if selectedCaller == nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.teal)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundColor(.secondary)
                        Text("最近调用(按 caller 分组)".localized())
                    }
                } footer: {
                    Text("本页是 home 入口,不同卡片(caller)都会在此显示;点选切换查看。".localized())
                        .font(.caption2)
                }
            }

            Section {
                debugRow(label: "调用方".localized(), value: info.caller)
                debugRow(label: "时间".localized(), value: timestampString(info.startTime))
                debugRow(
                    label: "思考时间".localized(),
                    value: String(format: "%.2f s", info.elapsedSeconds),
                    accent: info.error == nil ? .green : .red
                )
                if let err = info.error {
                    debugRow(label: "错误".localized(), value: err, accent: .red)
                }
                debugRow(label: "Stream".localized(), value: info.streaming ? "true" : "false")
            } header: {
                Text("概览".localized())
            }

            Section {
                copyableRow(label: "URL".localized(), value: info.url, systemImage: "link")
                debugRow(label: "Model".localized(), value: info.model)
                debugRow(label: "Temperature".localized(), value: String(format: "%.2f", info.temperature))
            } header: {
                Text("请求".localized())
            }

            Section {
                copyableRow(
                    label: "System".localized(),
                    value: info.systemPrompt,
                    systemImage: "doc.plaintext"
                )
            } header: {
                Text("System Prompt".localized())
            } footer: {
                Text(overrideStatusText(info: info))
                    .font(.caption2)
            }

            if !info.messages.isEmpty {
                Section {
                    ForEach(Array(info.messages.enumerated()), id: \.offset) { idx, msg in
                        copyableRow(
                            label: "[\(idx + 1)] \(msg.role.rawValue)",
                            value: msg.content,
                            systemImage: iconForRole(msg.role)
                        )
                    }
                } header: {
                    Text("Messages (\(info.messages.count))".localized())
                }
            }

            if let resp = info.response, !resp.isEmpty {
                Section {
                    copyableRow(
                        label: "Response".localized(),
                        value: resp,
                        systemImage: "arrow.down.circle"
                    )
                } header: {
                    Text("响应".localized())
                }
            }

            Section {
                HStack {
                    Text("JSON 长度:".localized())
                    Spacer()
                    Text("\(info.asDebugJSON().count) chars")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            } footer: {
                Text("点击右上角「Copy JSON」可把整条调用打包为 JSON 复制到剪贴板,便于上报 / 比对。".localized())
                    .font(.caption2)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Reusable rows / 可复用行

    private func debugRow(label: String, value: String, accent: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.monospaced())
                .foregroundColor(accent)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func copyableRow(label: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers / 辅助方法

    /// 不同 message role 对应的 SF Symbol
    /// SF Symbol used for each LLM message role.
    private func iconForRole(_ role: LLMRole) -> String {
        switch role {
        case .system: return "gearshape"
        case .user: return "person"
        case .assistant: return "brain"
        case .tool: return "wrench"
        }
    }

    /// 把 Date 格式化为 "yyyy-MM-dd HH:mm:ss" 本地时间字符串
    /// Format a Date as "yyyy-MM-dd HH:mm:ss" local time string.
    private func timestampString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    /// 简单的中文相对时间(如 "12s 前")
    /// Simple relative time in Chinese (e.g. "12s 前").
    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "\(Int(interval))s 前" }
        if interval < 3600 { return "\(Int(interval / 60))m 前" }
        if interval < 86400 { return "\(Int(interval / 3600))h 前" }
        return "\(Int(interval / 86400))d 前"
    }

    /// 根据 `container.envManager.preferences.debugOverrideSystemPrompt` 显示 override 实际状态。
    /// Reads the override directly from the injected `AppEnvironmentManager`
    /// (do NOT instantiate `AppPreferences()` here — that returns an empty
    /// default-initialized struct and the override is always reported as
    /// "未设置").
    private func overrideStatusText(info: LLMCallDebugInfo) -> String {
        let override = container.envManager.preferences.debugOverrideSystemPrompt
        if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "DEBUG 自定义系统提示:已生效(完全替换默认 + appendix)".localized()
        }
        return "DEBUG 自定义系统提示:未设置(回退到默认 + appendix)".localized()
    }
}
