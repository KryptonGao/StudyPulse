//
//  WelcomeHeaderCard.swift
//  StudyPulse
//
//  主页顶部欢迎区(紧凑单行):问候语 + 当前日期 + 头像按钮。
//  去掉静态大标题,把首屏让给「今日 Top-3」与 KPI。点击头像通过 NavigationLink 进入设置。
//  Compact one-line welcome strip: greeting + current date + avatar button. The static headline
//  is gone so the first screen goes to Today's Top 3 and the KPIs. Tapping the avatar opens Settings.
//
//  Extracted from HomeView.swift during card-extraction refactor (2026-07-05).
//

import SwiftUI

/// 主页顶部欢迎区域。
/// Home top welcome region.
struct WelcomeHeaderCard: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(RepositoryContainer.self) private var container
    /// 异步加载的头像数据,避免 body 中同步读文件
    /// Asynchronously loaded avatar data; avoids synchronous file I/O in body.
    @State private var avatarData: Data? = nil

    var body: some View {
        HStack(alignment: .center, spacing: DesignToken.Spacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText())
                    .font(DesignToken.Font.titleMedium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(currentDateText())
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

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
        .task {
            avatarData = await container.loadAvatarAsync()
        }
        .debugLayoutBoundsAuto()
    }

    private func greetingText() -> String {
        // 按时段返回问候语:<12 早、<18 午、其余晚
        // Time-of-day greeting: <12 morning, <18 afternoon, otherwise evening.
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return "Good Morning".localized()
        } else if hour < 18 {
            return "Good Afternoon".localized()
        } else {
            return "Good Evening".localized()
        }
    }

    /// 当前日期长格式字符串(本地化)
    /// Current date in the long localized format.
    private func currentDateText() -> String {
        DateFormatters.fullDate.string(from: Date())
    }
}
