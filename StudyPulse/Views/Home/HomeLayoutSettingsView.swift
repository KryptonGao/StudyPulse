//
//  HomeLayoutSettingsView.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/6/20.
//

import SwiftUI

// MARK: - HomeLayoutSettingsView
// MARK: - 主页布局设置视图

/// 主页卡片布局设置：拖拽排序 + 开关控制显示/隐藏
/// Home card layout settings: drag to reorder + toggle to show/hide.
struct HomeLayoutSettingsView: View {
    /// 当前编辑中的布局条目(可拖拽、可切换 enabled)。
    /// In-progress layout items being edited (draggable, toggleable `enabled`).
    @State private var items: [HomeCardItem] = HomeLayoutPreference.load().items
    /// 动态排布开关:开启后锁定手动排序。
    /// Dynamic layout switch: locks manual ordering while on.
    @State private var dynamicEnabled: Bool = HomeLayoutPreference.load().dynamicLayoutEnabled
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: dynamicBinding) {
                        Label("home.layout.dynamic.title".localized(), systemImage: "wand.and.sparkles")
                    }
                } footer: {
                    Text("home.layout.dynamic.footer".localized())
                }

                Section {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Image(systemName: item.type == .dailyPlan ? "pin.fill" : (dynamicEnabled ? "lock.fill" : "line.3.horizontal"))
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: 24)

                            Image(systemName: item.type.icon)
                                .foregroundColor(.accentColor)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.type.displayName)
                                    .font(.system(size: 16))
                                // Top-3 始终置顶,在此说明避免用户困惑
                                // Top 3 is always pinned first; explain it here to avoid confusion.
                                if item.type == .dailyPlan {
                                    Text("home.layout.pinned".localized())
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Toggle("", isOn: binding(for: item))
                                .labelsHidden()
                        }
                        .padding(.vertical, 4)
                        .moveDisabled(dynamicEnabled || item.type == .dailyPlan)
                    }
                    .onMove { source, destination in
                        items.move(fromOffsets: source, toOffset: destination)
                        save()
                    }
                } header: {
                    Text("Home Cards".localized())
                } footer: {
                    Text((dynamicEnabled ? "home.layout.locked.footer" : "homeLayout.footer").localized())
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(dynamicEnabled ? .inactive : .active))
            .containerBackground(.clear, for: .navigation)
            .debugModeContainer()
            .debugLayoutBoundsAuto()
            .navigationTitle("Home Layout".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        HomeLayoutPreference.resetToDefault()
                        let reset = HomeLayoutPreference.load()
                        items = reset.items
                        dynamicEnabled = reset.dynamicLayoutEnabled
                    } label: {
                        Label("Reset to Default".localized(), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    /// 动态排布开关绑定,变更后立即持久化。
    /// Binding for the dynamic layout switch; persisted immediately.
    private var dynamicBinding: Binding<Bool> {
        Binding(
            get: { dynamicEnabled },
            set: { newValue in
                dynamicEnabled = newValue
                save()
            }
        )
    }

    /// 给定一个 `HomeCardItem`,返回一个安全的 `Binding<Bool>` 用于开关控件;
    /// 设置后立即写回 `HomeLayoutPreference`。
    /// For a given `HomeCardItem`, returns a safe `Binding<Bool>` for the toggle control; immediately writes back to `HomeLayoutPreference` on change.
    private func binding(for item: HomeCardItem) -> Binding<Bool> {
        Binding(
            get: {
                items.first(where: { $0.id == item.id })?.enabled ?? true
            },
            set: { newValue in
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].enabled = newValue
                    save()
                }
            }
        )
    }

    /// 把当前 `items` 持久化到 `HomeLayoutPreference`(UserDefaults)。
    /// Persist the current `items` to `HomeLayoutPreference` (UserDefaults).
    private func save() {
        let pref = HomeLayoutPreference(items: items, dynamicLayoutEnabled: dynamicEnabled)
        pref.save()
    }
}

#Preview {
    HomeLayoutSettingsView()
}
