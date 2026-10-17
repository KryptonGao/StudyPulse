//
//  HomeLayoutSettingsView.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/6/20.
//
//  主页布局设置:主页由五个固定区块组成(顺序不可调),这里按区块分组,
//  只控制各区块内子模块的显示 / 隐藏。已收进详情页的卡片(趋势 / 脑力 / 记忆气候等)不在此列。
//  Home layout settings: Home has five fixed zones (order is not adjustable). Modules are grouped
//  by zone and only their visibility is toggled. Cards that moved into detail pages (trends, brain
//  usage, memory climate…) are not listed.
//

import SwiftUI

// MARK: - HomeLayoutSettingsView
// MARK: - 主页布局设置视图

struct HomeLayoutSettingsView: View {
    /// 当前编辑中的布局条目(只切换 enabled,顺序保持不变)。
    /// In-progress layout items (only `enabled` is toggled; order is untouched).
    @State private var items: [HomeCardItem] = HomeLayoutPreference.load().items
    @State private var dynamicEnabled: Bool = HomeLayoutPreference.load().dynamicLayoutEnabled
    @Environment(\.dismiss) private var dismiss

    /// 区块分组;每组列出该区块内可开关的模块。
    /// Zone groups; each lists the toggleable modules inside that zone.
    private struct Zone: Identifiable {
        let id: String
        let title: String
        let types: [HomeCardType]
    }

    private var zones: [Zone] {
        [
            Zone(id: "now", title: "home.v2.layout.now".localized(),
                 types: [.dailyPlan, .streakProgress, .quickActions, .dailyQuote]),
            Zone(id: "today", title: "home.v2.zone.today".localized(),
                 types: [.flashcardReview, .unregisteredExamsReminder, .upcomingExams, .examReversePlanner, .examRoleSimulator]),
            Zone(id: "progress", title: "home.v2.zone.progress".localized(),
                 types: [.weeklyFocus, .subjectSnapshot, .recentGrades, .studySuggestions]),
            Zone(id: "bodyMind", title: "home.v2.zone.bodyMind".localized(),
                 types: [.hrvStatus, .diary, .habitInsight]),
            Zone(id: "growth", title: "home.v2.zone.growth".localized(),
                 types: [.plant, .learningHeatmap]),
            Zone(id: "ask", title: "home.v2.layout.ask".localized(),
                 types: [.homeAsk]),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(zones) { zone in
                    Section {
                        ForEach(zone.types, id: \.self) { type in
                            Toggle(isOn: binding(for: type)) {
                                Label(type.displayName, systemImage: type.icon)
                            }
                        }
                    } header: {
                        Text(zone.title)
                    } footer: {
                        if zone.id == "now" {
                            Text("home.v2.layout.footer".localized())
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
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

    /// 给定卡片类型,返回开关绑定;设置后立即写回 `HomeLayoutPreference`。
    /// Toggle binding for a card type; immediately written back to `HomeLayoutPreference`.
    private func binding(for type: HomeCardType) -> Binding<Bool> {
        Binding(
            get: { items.first(where: { $0.type == type })?.enabled ?? true },
            set: { newValue in
                if let index = items.firstIndex(where: { $0.type == type }) {
                    items[index].enabled = newValue
                    save()
                }
            }
        )
    }

    private func save() {
        HomeLayoutPreference(items: items, dynamicLayoutEnabled: dynamicEnabled).save()
    }
}

#Preview {
    HomeLayoutSettingsView()
}
