//
//  HomeRoute.swift
//  StudyPulse
//
//  主页 NavigationStack 的类型化路由。各区块用 `NavigationLink(value:)` 声明跳转,
//  由 HomeView 统一注册 destination,避免每张卡片各自持有 push 逻辑。
//  Typed routes for the Home NavigationStack. Sections declare pushes with
//  `NavigationLink(value:)`; HomeView registers the destinations in one place.
//

import SwiftUI

/// 主页内可 push 的目的地 / Destinations pushable from Home.
enum HomeRoute: Hashable {
    case diary
    case plant
    case achievements
    case bodyMindDetail
    case exam(UUID)
    case task(UUID)
    case mistake(UUID)
}

// MARK: - 切换 Tab 的环境入口 / Tab-switch environment entry

private struct SelectAppTabKey: EnvironmentKey {
    static let defaultValue: (AppTab) -> Void = { _ in }
}

extension EnvironmentValues {
    /// 由 `ContentView` 注入,让子页面(如主页「全部待办」)切换底部 Tab。
    /// Injected by `ContentView` so child screens (e.g. Home's "All to-dos") can switch the root tab.
    var selectAppTab: (AppTab) -> Void {
        get { self[SelectAppTabKey.self] }
        set { self[SelectAppTabKey.self] = newValue }
    }
}

// MARK: - 区块标题 / Zone header

/// 主页区块标题:`title3` 粗体 + 可选右侧操作(通常是「查看全部」类链接)。
/// Home zone header: bold `title3` plus an optional trailing action (usually a "see all" link).
struct HomeZoneHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
                .font(.subheadline)
        }
        .padding(.horizontal, DesignToken.Spacing.tiny)
    }
}

extension HomeZoneHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}
