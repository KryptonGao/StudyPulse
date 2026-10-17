//
//  HomeHeaderSection.swift
//  StudyPulse
//
//  主页顶部:日期 + 问候 + 头像,下一行是当前阶段胶囊与恢复状态胶囊,可选一行每日金句。
//  取代 WelcomeHeaderCard。头像进入设置;阶段胶囊复用全局 `PhaseSelectorView`。
//  Home header: date + greeting + avatar, then the phase pill and a recovery pill, plus an
//  optional one-line daily quote. Replaces WelcomeHeaderCard. The avatar opens Settings; the
//  phase pill reuses the global `PhaseSelectorView`.
//

import SwiftUI

struct HomeHeaderSection: View {
    /// 综合恢复分;nil 时不显示恢复胶囊 / Recovery score; nil hides the recovery pill.
    let recoveryScore: Int?
    let showsQuote: Bool

    @Environment(RepositoryContainer.self) private var container
    /// 异步加载的头像数据,避免 body 中同步读文件
    /// Asynchronously loaded avatar data; avoids synchronous file I/O in body.
    @State private var avatarData: Data? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            HStack(alignment: .top, spacing: DesignToken.Spacing.medium) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DateFormatters.weekdayDate.string(from: Date()))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(greetingText)
                        .font(DesignToken.Font.titleLarge)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                NavigationLink(destination: SettingsView()) {
                    AvatarView(
                        username: container.profileRepo.profile.username,
                        avatarData: avatarData,
                        size: 40,
                        showBorder: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings".localized())
            }

            HStack(spacing: DesignToken.Spacing.small) {
                PhaseSelectorView()
                if let recoveryScore {
                    recoveryPill(score: recoveryScore)
                }
                Spacer(minLength: 0)
            }

            if showsQuote {
                Text(QuoteProvider.dailyQuote())
                    .font(.footnote.italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DesignToken.Spacing.tiny)
        .task {
            avatarData = await container.loadAvatarAsync()
        }
        .debugLayoutBoundsAuto()
    }

    // MARK: - Pieces

    private func recoveryPill(score: Int) -> some View {
        let level = RecoveryLevel(score: score)
        return NavigationLink(value: HomeRoute.bodyMindDetail) {
            Label(level.localizedLabel, systemImage: "heart.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(level.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(level.color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 按时段问候;有用户名时附带称呼。
    /// Time-of-day greeting, with the user's name appended when available.
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        switch hour {
        case ..<12: greeting = "Good Morning".localized()
        case ..<18: greeting = "Good Afternoon".localized()
        default: greeting = "Good Evening".localized()
        }
        let name = container.profileRepo.profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return greeting }
        return String(format: "home.v2.greeting.named".localized(), greeting, name)
    }
}
