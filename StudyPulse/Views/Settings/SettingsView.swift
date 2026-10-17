//
//  SettingsView.swift
//  StudyPulse
//
//  设置首页:搜索 → 个人资料卡 → 三格状态(健康 / AI / 备份)→ 五组单行设置。
//  Settings home: search, profile card, three status tiles (health / AI / backup)
//  and five grouped single-line rows that show their current value.
//

import SwiftUI

/// 一行设置 / One settings row.
private struct SettingsRowItem: Identifiable {
    let id: String
    let title: String
    let icon: String
    let tint: Color
    var value: String = ""
    var badge: Int? = nil
    let destination: AnyView
}

private struct SettingsGroup: Identifiable {
    let id: String
    let title: String
    let rows: [SettingsRowItem]
}

struct SettingsView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(HealthKitManager.self) private var hrvManager
    @Environment(AchievementManager.self) private var achievementManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// 异步加载的头像数据，避免 body 中同步读文件
    @State private var avatarData: Data? = nil
    @State private var query = ""

    private var lastBackupAt: Date? {
        UserDefaults.standard.object(forKey: "studyPulse.lastFullBackupAt") as? Date
    }

    var body: some View {
        TwoPane(masterWidth: 380, placeholderTitle: "settings.v2.pane.placeholder".localized(), placeholderIcon: "gearshape") {
            content
        }
    }

    private var content: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        PaneLink(id: "profile", destination: { ProfileSettingsView() }, label: {
                            profileRow.paneSelected("profile")
                        })
                        .debugLayoutBoundsAuto()
                    }
                    Section {
                        statusTiles
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    ForEach(groups) { group in
                        Section(group.title) { rows(group.rows) }
                    }
                    Section {
                        Text(versionLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                } else {
                    Section { rows(filtered) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground).opacity(DesignToken.Opacity.rootBackground))
            .searchable(text: $query, prompt: "settings.v2.search".localized())
            .task { avatarData = await container.loadAvatarAsync() }
            .containerBackground(.clear, for: .navigation)
            .debugModeContainer()
            .debugLayoutBoundsAuto()
            .navigationTitle("Settings".localized())
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - 资料 / Profile

    private var profileRow: some View {
        HStack(spacing: 14) {
            AvatarView(
                username: container.profileRepo.profile.username,
                avatarData: avatarData,
                size: 60
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(container.profileRepo.profile.username)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text(profileSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("settings.v2.profile.hint".localized())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }

    private var profileSubtitle: String {
        let p = container.profileRepo.profile
        let parts = [p.grade, p.schoolName, p.studentId.isEmpty ? "" : "\(p.studentId)"].filter { !$0.isEmpty }
        return parts.isEmpty ? "Tap to set up your profile".localized() : parts.joined(separator: " · ")
    }

    // MARK: - 状态三格 / Status tiles

    private var statusTiles: some View {
        let backupStale = lastBackupAt.map { Date().timeIntervalSince($0) > 7 * 86_400 } ?? true
        let health = hrvManager.hrvEnabled && hrvManager.isAuthorized
        let ai = container.envManager.llmConfig.isConfigured
        return HStack(spacing: 10) {
            tile(
                title: "settings.v2.health".localized(), icon: "heart.fill", tint: .pink,
                value: health ? "settings.v2.connected".localized() : "settings.v2.notConnected".localized(),
                ok: health, sub: "HRV · Sleep · HR".localized(),
                destination: AnyView(HealthSettingsView())
            )
            tile(
                title: "AI", icon: "brain", tint: .teal,
                value: ai ? "settings.v2.configured".localized() : "settings.v2.notConfigured".localized(),
                ok: ai, sub: ai ? (container.envManager.llmConfig.model ?? "") : "LLM".localized(),
                destination: AnyView(LLMSettingsView())
            )
            tile(
                title: "settings.v2.backup".localized(), icon: "archivebox.fill", tint: .orange,
                value: lastBackupAt.map { $0.formatted(.relative(presentation: .named)) } ?? "settings.v2.never".localized(),
                ok: !backupStale, sub: "settings.v2.backup.hint".localized(),
                destination: AnyView(BackupRestoreView())
            )
        }
    }

    private func tile(title: String, icon: String, tint: Color, value: String, ok: Bool, sub: String, destination: AnyView) -> some View {
        PaneLink(id: "tile-\(title)", showsDisclosure: false, destination: { destination }, label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(ok ? Color.green : Color.orange)
                        .imageScale(.small)
                    Text(value)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(ok ? Color.primary : Color.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        })
        .buttonStyle(.plain)
    }

    // MARK: - 行 / Rows

    private func rows(_ items: [SettingsRowItem]) -> some View {
        ForEach(items) { item in
            PaneLink(id: item.id, destination: { item.destination }, label: {
                HStack(spacing: 12) {
                    Image(systemName: item.icon)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(item.tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(item.title)
                    Spacer(minLength: 8)
                    if let badge = item.badge {
                        Text("\(badge)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                    if !item.value.isEmpty {
                        Text(item.value).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    PaneChevron()
                }
                .paneSelected(item.id)
            })
            .debugLayoutBoundsAuto()
        }
    }

    // MARK: - 分组 / Groups

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "StudyPulse \(version) (\(build))"
    }

    private var groups: [SettingsGroup] {
        let streak = achievementManager.snapshot.streak.current
        let phaseName = container.phaseRepo.activePhase?.name ?? ""
        let llm = container.envManager.llmConfig
        let coachOn = container.envManager.preferences.coachEnabled
        let backup = lastBackupAt.map { $0.formatted(.relative(presentation: .named)) } ?? ""

        return [
            SettingsGroup(id: "personal", title: "settings.v2.group.personal".localized(), rows: [
                SettingsRowItem(id: "appearance", title: "settings.v2.row.appearance".localized(), icon: "paintpalette.fill", tint: .blue,
                                destination: AnyView(AppearanceSettingsView())),
                SettingsRowItem(id: "themeShop", title: SettingsCategory.themeShop.title, icon: "sparkles.rectangle.stack.fill", tint: .purple,
                                destination: AnyView(ThemeShopView())),
                SettingsRowItem(id: "homeLayout", title: "settings.v2.row.homeLayout".localized(), icon: "square.grid.2x2.fill", tint: .green,
                                destination: AnyView(HomeLayoutSettingsView()))
            ]),
            SettingsGroup(id: "study", title: "settings.v2.group.study".localized(), rows: [
                SettingsRowItem(id: "goals", title: "settings.v2.row.goals".localized(), icon: "trophy.fill", tint: .orange,
                                value: streak > 0 ? String(format: "settings.v2.streak".localized(), streak) : "",
                                destination: AnyView(DailyGoalsConfigView())),
                SettingsRowItem(id: "phase", title: "settings.v2.row.phase".localized(), icon: "flag.fill", tint: .indigo,
                                value: phaseName, destination: AnyView(PhaseManagementView())),
                SettingsRowItem(id: "health", title: SettingsCategory.health.title, icon: "heart.fill", tint: .pink,
                                destination: AnyView(HealthSettingsView())),
                SettingsRowItem(id: "reports", title: SettingsCategory.reports.title, icon: "chart.bar.xaxis", tint: .indigo,
                                destination: AnyView(WeeklyReportSettingsView())),
                SettingsRowItem(id: "diary", title: "settings.v2.row.diary".localized(), icon: "moon.fill", tint: .orange,
                                destination: AnyView(DiarySettingsView()))
            ]),
            SettingsGroup(id: "ai", title: "AI", rows: [
                SettingsRowItem(id: "llm", title: "settings.v2.row.llm".localized(), icon: "brain", tint: .teal,
                                value: llm.isConfigured ? (llm.model ?? "") : "",
                                destination: AnyView(LLMSettingsView())),
                SettingsRowItem(id: "coach", title: "AI Coach".localized(), icon: "target", tint: .purple,
                                value: coachOn ? "settings.v2.on".localized() : "settings.v2.off".localized(),
                                destination: AnyView(LLMSettingsView()))
            ]),
            SettingsGroup(id: "data", title: "settings.v2.group.data".localized(), rows: [
                SettingsRowItem(id: "backup", title: "settings.v2.row.backup".localized(), icon: "archivebox.fill", tint: .green,
                                value: backup, destination: AnyView(BackupRestoreView())),
                SettingsRowItem(id: "data", title: SettingsCategory.data.title, icon: "externaldrive.fill", tint: .blue,
                                destination: AnyView(DataManagementSettingsView()))
            ]),
            SettingsGroup(id: "support", title: "settings.v2.group.support".localized(), rows: [
                SettingsRowItem(id: "faq", title: SettingsCategory.faq.title, icon: "questionmark.circle.fill", tint: .blue,
                                destination: AnyView(QASettingsView())),
                SettingsRowItem(id: "contribution", title: SettingsCategory.contribution.title, icon: "hand.raised.fingers.spread.fill", tint: .purple,
                                destination: AnyView(ContributionSettingsView())),
                SettingsRowItem(id: "about", title: SettingsCategory.about.title, icon: "info.circle.fill", tint: .gray,
                                destination: AnyView(AboutSettingsView()))
            ])
        ]
    }

    private var filtered: [SettingsRowItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return groups.flatMap(\.rows).filter { $0.title.lowercased().contains(q) || $0.value.lowercased().contains(q) }
    }
}

#Preview {
    SettingsView()
        .environment(RepositoryContainer())
        .environment(HealthKitManager.shared)
        .environment(AchievementManager.shared)
}
