//
//  TwoPane.swift
//  StudyPulse
//
//  iPad「列表 | 详情」双栏:左栏是页面本身,右栏显示被选中的详情。
//  用 HStack 而不是再嵌套一层 NavigationSplitView(根视图已经是 split view,嵌套行为不稳定)。
//  iPad "list | detail" panes: the page itself on the left, the selected detail on the right.
//  Built with an HStack rather than a second NavigationSplitView, because the root already
//  is one and nesting them is unreliable.
//

import SwiftUI

// MARK: - Model / 右栏状态

@MainActor
@Observable
final class DetailPaneModel {
    private(set) var content: AnyView?
    private(set) var selectedID: AnyHashable?

    func show(id: AnyHashable, content: AnyView) {
        selectedID = id
        self.content = content
    }

    func clear() {
        selectedID = nil
        content = nil
    }
}

private struct DetailPaneKey: EnvironmentKey {
    static let defaultValue: DetailPaneModel? = nil
}

extension EnvironmentValues {
    /// 非 nil 表示当前处于 iPad 双栏中:详情应显示在右栏而不是 push。
    /// Non-nil while inside an iPad two-pane: details go to the right pane instead of pushing.
    var detailPane: DetailPaneModel? {
        get { self[DetailPaneKey.self] }
        set { self[DetailPaneKey.self] = newValue }
    }
}

private struct InDetailPaneKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 当前视图是否显示在双栏右栏里。右栏共用外层导航栏,详情自己的标题不会显示,需要自绘。
    /// Whether the view is shown in the right pane. That pane shares the outer navigation bar,
    /// so a detail's own navigation title is invisible and it must draw one itself.
    var isInDetailPane: Bool {
        get { self[InDetailPaneKey.self] }
        set { self[InDetailPaneKey.self] = newValue }
    }
}

// MARK: - Container / 容器

struct TwoPane<Master: View>: View {
    /// 双栏所需的最小总宽度;窄于它(分屏多任务)时回退为单栏 push。
    /// Minimum total width for two panes; narrower (Split View) falls back to push navigation.
    private let minimumWidth: CGFloat = 720
    var masterWidth: CGFloat = 400
    var placeholderTitle: String
    var placeholderIcon: String
    @ViewBuilder var master: () -> Master

    @State private var model = DetailPaneModel()

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= minimumWidth {
                HStack(spacing: 0) {
                    master()
                        .frame(width: masterWidth)
                        .environment(\.detailPane, model)
                    Divider()
                    detail
                }
            } else {
                master()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            if let content = model.content {
                NavigationStack { content }
                    .environment(\.isInDetailPane, true)
                    .id(model.selectedID)
            } else {
                ContentUnavailableView(placeholderTitle, systemImage: placeholderIcon)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).opacity(DesignToken.Opacity.rootBackground))
    }
}

// MARK: - Link / 链接

/// 双栏中把详情放到右栏;单栏中回退为普通 NavigationLink。
/// In a two-pane puts the detail in the right pane; otherwise behaves like a NavigationLink.
struct PaneLink<Label: View>: View {
    @Environment(\.detailPane) private var pane

    private let id: AnyHashable
    private let paneContent: () -> AnyView
    private let fallback: (Label) -> AnyView
    private let label: Label

    /// 回退为 `NavigationLink(value:)`(目的地由外层 `navigationDestination` 提供)。
    /// Falls back to `NavigationLink(value:)` (destination registered by an outer `navigationDestination`).
    init<V: Hashable, Content: View>(
        value: V,
        @ViewBuilder pane: @escaping () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.id = AnyHashable(value)
        self.paneContent = { AnyView(pane()) }
        self.fallback = { label in AnyView(NavigationLink(value: value) { label }) }
        self.label = label()
    }

    /// 回退为 `NavigationLink(destination:)`。
    /// Falls back to `NavigationLink(destination:)`.
    /// `showsDisclosure: false` 用于 List 里自绘的卡片行:隐藏 NavigationLink 自带的箭头。
    /// `showsDisclosure: false` is for custom card rows inside a List: hides the built-in arrow.
    init<ID: Hashable, Destination: View>(
        id: ID,
        showsDisclosure: Bool = true,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        self.id = AnyHashable(id)
        self.paneContent = { AnyView(destination()) }
        if showsDisclosure {
            self.fallback = { label in AnyView(NavigationLink(destination: destination()) { label }) }
        } else {
            self.fallback = { label in
                AnyView(
                    label.overlay {
                        NavigationLink(destination: destination()) { EmptyView() }.opacity(0)
                    }
                )
            }
        }
        self.label = label()
    }

    var body: some View {
        if let pane {
            Button {
                pane.show(id: id, content: paneContent())
            } label: { label }
            .buttonStyle(.plain)
        } else {
            fallback(label)
        }
    }
}

extension View {
    /// 在双栏中显示选中态高亮;否则不变。
    /// Highlights the row selected in the right pane (no-op outside a two-pane).
    func paneSelected(_ id: some Hashable) -> some View {
        modifier(PaneSelectedModifier(id: AnyHashable(id)))
    }
}

private struct PaneSelectedModifier: ViewModifier {
    @Environment(\.detailPane) private var pane
    let id: AnyHashable

    func body(content: Content) -> some View {
        content.background(pane?.selectedID == id ? Color.accentColor.opacity(0.12) : .clear)
    }
}

/// 双栏里的按钮行没有 NavigationLink 自带的披露箭头,这里补上;单栏时不显示以免重复。
/// Rows in a two-pane are buttons with no built-in disclosure arrow; add one (hidden otherwise).
struct PaneChevron: View {
    @Environment(\.detailPane) private var pane

    var body: some View {
        if pane != nil {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
    }
}
