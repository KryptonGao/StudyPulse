//
//  ThemeShopView.swift
//  StudyPulse
//
//  主题 / 皮肤商店主页 — 设置顶级分类的 destination。
//  Three independent cosmetic categories (Primary / Card Skin / Timer Animation).
//  Achievement-based unlock, no IAP. Debug mode unlocks everything for preview.
//

import SwiftUI

struct ThemeShopView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(AchievementManager.self) private var achievementManager: AchievementManager

    // 缓存：当前所有已解锁成就 id
    private var achievementSet: Set<String> {
        achievementManager.snapshot.achievements
            .filter { $0.unlockedAt != nil }
            .map { $0.definitionId }
            .reduce(into: Set<String>()) { $0.insert($1) }
    }

    private var isDebugMode: Bool { container.envManager.isDebugModeActive }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isDebugMode { debugBanner }
                LivePreviewSection(
                    accent: container.envManager.effectiveAccentPalette,
                    skin: container.envManager.effectiveCardSkin,
                    animation: container.envManager.effectiveTimerAnimation,
                    glassEnabled: container.envManager.glassEffectEnabled
                )
                .padding(.horizontal, 16)

                ThemeShopSectionView(
                    section: .accent,
                    items: ThemeShopCatalog.accentPalettes,
                    selectedId: container.envManager.preferences.accentPaletteId,
                    achievementSet: achievementSet,
                    isDebugMode: isDebugMode,
                    onSelect: { id in container.envManager.setAccentPaletteId(id) }
                )
                .padding(.horizontal, 16)

                ThemeShopSectionView(
                    section: .skin,
                    items: ThemeShopCatalog.cardSkins,
                    selectedId: container.envManager.preferences.cardSkinId,
                    achievementSet: achievementSet,
                    isDebugMode: isDebugMode,
                    onSelect: { id in container.envManager.setCardSkinId(id) }
                )
                .padding(.horizontal, 16)

                ThemeShopSectionView(
                    section: .animation,
                    items: ThemeShopCatalog.timerAnimations,
                    selectedId: container.envManager.preferences.timerAnimationId,
                    achievementSet: achievementSet,
                    isDebugMode: isDebugMode,
                    onSelect: { id in container.envManager.setTimerAnimationId(id) }
                )
                .padding(.horizontal, 16)

                Spacer().frame(height: 40)
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("theme.shop.title".localized())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Debug Banner

    private var debugBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "ladybug.fill")
                .foregroundColor(.white)
            Text("theme.shop.debugBanner".localized())
                .scaledFont(size: 13, weight: .semibold)
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.purple, Color.blue],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - LivePreviewSection

/// 顶部实时预览区域：3 张示例卡片 + mini ring。
struct LivePreviewSection: View {
    let accent: AccentPalette
    let skin: CardSkin
    let animation: TimerAnimation
    let glassEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "eye.fill")
                    .scaledFont(size: 13, weight: .semibold)
                Text("theme.shop.preview.title".localized())
                    .scaledFont(size: 15, weight: .bold)
                Spacer()
            }
            .foregroundColor(.secondary)

            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 10) {
                        Image(systemName: ["book.fill", "flame.fill", "chart.line.uptrend.xyaxis"][i])
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundColor(accent.color)
                        Text([
                                "Live Preview Card".localized(),
                                "Live Preview Card".localized(),
                                "Live Preview Card".localized()
                            ][i])
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(i * 25 + 10)")
                            .scaledFont(size: 14, weight: .bold, design: .monospaced)
                            .foregroundColor(accent.color)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSkin(skin, glassEnabled: glassEnabled)
                }

                // mini ring (计时器动画缩略)
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(animation.colors[0].opacity(0.20), lineWidth: 6)
                            .frame(width: 60, height: 60)
                        Circle()
                            .trim(from: 0, to: 0.65)
                            .stroke(
                                AngularGradient(colors: animation.colors + [animation.colors[0]], center: .center),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(-90))
                        Text("25:00")
                            .scaledFont(size: 12, weight: .bold, design: .monospaced)
                            .foregroundColor(animation.primaryColor)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(animation.localizedName)
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundColor(.primary)
                        Text(animation.localizedDescription)
                            .scaledFont(size: 12)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSkin(skin, glassEnabled: glassEnabled)
            }
        }
    }
}

// MARK: - Section Identifier

/// 标记当前 section 的语义类型,让 ThemeShopItemCard 能用同一个组件渲染不同预览。
enum ThemeShopSection: String {
    case accent, skin, animation

    var title: String {
        switch self {
        case .accent: return "theme.shop.section.accent".localized()
        case .skin: return "theme.shop.section.skin".localized()
        case .animation: return "theme.shop.section.animation".localized()
        }
    }

    var headerIcon: String {
        switch self {
        case .accent: return "paintpalette.fill"
        case .skin: return "rectangle.on.rectangle.fill"
        case .animation: return "timer"
        }
    }
}

// MARK: - ThemeShopSectionView

struct ThemeShopSectionView<Item: ThemeShopItemViewable>: View {
    let section: ThemeShopSection
    let items: [Item]
    let selectedId: String?
    let achievementSet: Set<String>
    let isDebugMode: Bool
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: section.headerIcon)
                    .scaledFont(size: 13, weight: .semibold)
                Text(section.title)
                    .scaledFont(size: 15, weight: .bold)
                Spacer()
            }
            .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        let unlocked = ThemeShopCatalog.isUnlocked(
                            unlockAchievementId: item.unlockAchievementId,
                            achievementIds: achievementSet,
                            isDebugMode: isDebugMode
                        )
                        ThemeShopItemCard(
                            title: item.localizedName,
                            iconName: item.icon,
                            unlockHint: item.unlockHint(
                                achievementTitle: achievementTitle(for: item.unlockAchievementId)
                            ),
                            isSelected: selectedId == item.id,
                            isUnlocked: unlocked,
                            preview: { ThemeShopItemPreviewRenderer.preview(for: item) }
                        )
                        .onTapGesture {
                            guard unlocked else {
                                if !isDebugMode { return }
                                onSelect(item.id)
                                return
                            }
                            onSelect(item.id)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
    }

    private func achievementTitle(for achId: String?) -> String {
        guard let achId else { return "" }
        return "achievement.\(achId).title".localized()
    }
}

// MARK: - ThemeShopItemViewable

protocol ThemeShopItemViewable: Identifiable, Hashable {
    var id: String { get }
    var displayNameKey: String { get }
    var descriptionKey: String { get }
    var unlockAchievementId: String? { get }
    var icon: String { get }
    var localizedName: String { get }
    var localizedDescription: String { get }
    func unlockHint(achievementTitle: String) -> String
}

extension ThemeShopItemViewable {
    func unlockHint(achievementTitle: String) -> String {
        if unlockAchievementId == nil {
            return "theme.shop.unlocked".localized()
        }
        return String(format: "theme.shop.locked.unlockAt".localized(), achievementTitle)
    }
}

extension AccentPalette: ThemeShopItemViewable {}
extension CardSkin: ThemeShopItemViewable {}
extension TimerAnimation: ThemeShopItemViewable {}

// MARK: - ThemeShopItemPreviewRenderer

/// 把不同 catalog item 的预览图集中到一处渲染,避免在泛型约束里出现 `some View`。
@MainActor
enum ThemeShopItemPreviewRenderer {
    @ViewBuilder
    static func preview(for item: any ThemeShopItemViewable) -> some View {
        if let accent = item as? AccentPalette {
            AccentPreview(accent: accent)
        } else if let skin = item as? CardSkin {
            CardSkinPreview(skin: skin)
        } else if let anim = item as? TimerAnimation {
            TimerAnimationPreview(animation: anim)
        } else {
            Image(systemName: item.icon)
                .scaledFont(size: 20, weight: .semibold)
        }
    }
}

private struct AccentPreview: View {
    let accent: AccentPalette

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [accent.primary, accent.secondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: accent.icon)
                    .scaledFont(size: 20, weight: .semibold)
                    .foregroundColor(.white)
            )
    }
}

private struct CardSkinPreview: View {
    let skin: CardSkin

    var body: some View {
        RoundedRectangle(cornerRadius: skin.cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [skin.accentColor.opacity(0.30), Color(.secondarySystemGroupedBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: skin.cornerRadius, style: .continuous)
                    .stroke(skin.accentColor.opacity(0.7), lineWidth: max(1, skin.borderWidth))
            )
            .overlay(
                Image(systemName: skin.icon)
                    .scaledFont(size: 20, weight: .semibold)
                    .foregroundColor(skin.accentColor)
            )
    }
}

private struct TimerAnimationPreview: View {
    let animation: TimerAnimation

    var body: some View {
        ZStack {
            Circle()
                .stroke(animation.colors[0].opacity(0.20), lineWidth: 4)
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    AngularGradient(colors: animation.colors + [animation.colors[0]], center: .center),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: animation.icon)
                .scaledFont(size: 18, weight: .semibold)
                .foregroundColor(animation.primaryColor)
        }
    }
}

// MARK: - ThemeShopItemCard

struct ThemeShopItemCard<Preview: View>: View {
    let title: String
    let iconName: String
    let unlockHint: String
    let isSelected: Bool
    let isUnlocked: Bool
    @ViewBuilder let preview: () -> Preview

    @Environment(RepositoryContainer.self) private var container

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                preview()
                    .frame(width: 70, height: 70)

                if isSelected {
                    Image(systemName: "checkmark.seal.fill")
                        .scaledFont(size: 18)
                        .foregroundStyle(.white)
                        .background(
                            Circle()
                                .fill(Color.green)
                                .frame(width: 22, height: 22)
                        )
                        .offset(x: 6, y: -6)
                } else if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(
                            Circle()
                                .fill(Color.gray.opacity(0.85))
                                .frame(width: 22, height: 22)
                        )
                        .offset(x: 6, y: -6)
                }
            }

            Text(title)
                .scaledFont(size: 11, weight: .semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: 80)

            if !isUnlocked {
                Text(unlockHint)
                    .scaledFont(size: 9)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 80)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: 90)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isSelected
                        ? container.envManager.effectiveAccentPalette.color.opacity(0.12)
                        : Color(.tertiarySystemBackground)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? container.envManager.effectiveAccentPalette.color : Color.clear,
                    lineWidth: isSelected ? 1.5 : 0
                )
        )
        .opacity(isUnlocked ? 1.0 : 0.65)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ThemeShopView()
            .environment(RepositoryContainer())
            .environment(AchievementManager.shared)
    }
}
#endif
