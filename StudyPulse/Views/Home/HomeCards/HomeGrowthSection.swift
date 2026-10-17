//
//  HomeGrowthSection.swift
//  StudyPulse
//
//  「成长」区块:虚拟植物 + 迷你学习热力图合并成一张卡。iPhone 显示 16 周,iPad 显示 40 周。
//  完整 90 天热力图仍在趋势页(`LearningHeatmapView`);植物详情与成就页由此进入。
//  Growth zone: the virtual plant and a mini learning heatmap in one card — 16 weeks on iPhone,
//  40 on iPad. The full 90-day heatmap stays on the Trends page; plant detail and achievements
//  are reachable from here.
//

import SwiftUI

/// 「成长」区块各子模块的开关(来自 `HomeLayoutPreference`)。
/// Per-module switches for the Growth zone (from `HomeLayoutPreference`).
struct HomeGrowthOptions {
    var showsPlant = true
    var showsHeatmap = true
}

struct HomeGrowthSection: View {
    let options: HomeGrowthOptions

    @Environment(RepositoryContainer.self) private var container
    @Environment(AchievementManager.self) private var achievementManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var plantManager = PlantManager.shared

    private var accent: Color { container.envManager.effectiveAccentColor }
    private var showsPlant: Bool { options.showsPlant && container.envManager.preferences.plantCardEnabled }
    private var weeks: Int { (sizeClass == .regular || isIPad) ? 40 : 16 }

    var body: some View {
        if showsPlant || options.showsHeatmap {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HomeZoneHeader(title: "home.v2.zone.growth".localized()) {
                    NavigationLink("home.v2.growth.achievements".localized(), value: HomeRoute.achievements)
                }
                card
            }
            .debugLayoutBoundsAuto()
        }
    }

    private var card: some View {
        HStack(alignment: .center, spacing: DesignToken.Spacing.large) {
            if showsPlant { plantBox }
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                if showsPlant { stageHeader }
                if options.showsHeatmap { heatmap }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
    }

    // MARK: - Plant

    private var plantBox: some View {
        let stage = plantManager.currentStage
        let petal = PetalColorCatalog
            .resolve(container.envManager.preferences.plantPetalColorId)
            .resolved(colorScheme: colorScheme)
        return NavigationLink(value: HomeRoute.plant) {
            PlantCanvasView(stage: stage, petalColor: petal, accent: accent)
                .frame(width: 160, height: 200)
                .scaleEffect(0.56)
                .frame(width: 96, height: 112)
                .background(
                    LinearGradient(
                        colors: [Color.green.opacity(0.10), Color.green.opacity(0.22)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("plant.card.title".localized())
    }

    private var stageHeader: some View {
        let stage = plantManager.currentStage
        return VStack(alignment: .leading, spacing: 2) {
            Text(stage.localizedTitle)
                .font(.subheadline.weight(.bold))
            Text(stage.localizedSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Heatmap

    private var heatmap: some View {
        let points = pointsByDay
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let total = weeks * 7
        let start = cal.date(byAdding: .day, value: -(total - 1), to: today) ?? today
        var activeDays = 0
        var levels: [HeatmapActivityLevel] = []
        levels.reserveCapacity(total)
        for offset in 0..<total {
            let day = cal.date(byAdding: .day, value: offset, to: start) ?? start
            let level = HeatmapActivityLevel.from(points: points[day] ?? 0)
            if level != .none { activeDays += 1 }
            levels.append(level)
        }
        return VStack(alignment: .leading, spacing: 6) {
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(0..<7, id: \.self) { row in
                    GridRow {
                        ForEach(0..<weeks, id: \.self) { column in
                            let level = levels[column * 7 + row]
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(level == .none ? Color(.tertiarySystemFill) : accent.opacity(level.opacity))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            Text(String(format: "home.v2.growth.summary".localized(), weeks, activeDays))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "home.v2.growth.summary".localized(), weeks, activeDays))
    }

    /// 自然日 → 当日活动点数 / Calendar day → that day's activity points.
    private var pointsByDay: [Date: Int] {
        var result: [Date: Int] = [:]
        for log in achievementManager.snapshot.logs {
            result[Calendar.current.startOfDay(for: log.date), default: 0] += log.totalActivityPoints
        }
        return result
    }
}
