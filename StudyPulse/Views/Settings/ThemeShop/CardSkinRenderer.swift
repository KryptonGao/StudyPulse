//
//  CardSkinRenderer.swift
//  StudyPulse
//
//  卡片皮肤的视图渲染层。
//  View-level rendering for `CardSkin` — keeps the model in `ThemeShop.swift`
//  plain data and isolated from SwiftUI view building.
//
//  用法：
//      VStack { ... }
//          .cardSkin(container.envManager.effectiveCardSkin, glassEnabled: container.envManager.glassEffectEnabled)
//
//  替换原：
//      .background(Color(.systemBackground))
//      .cornerRadius(20)
//      .shadow(...)
//
//  iOS 26 glass 优先级：
//      - `skin.isGlass && glassEnabled` 走 `GlassCardBackground`（系统 glassEffect）
//      - 否则走 skin 自定义背景
//

import SwiftUI

// MARK: - View extension

extension View {
    /// 自动使用环境中的 `AppEnvironmentManager` 渲染卡片背景 + 边框 + 阴影。
    func cardSkin() -> some View {
        modifier(EnvironmentCardSkinModifier())
    }

    /// 用指定 `CardSkin` 渲染卡片背景 + 边框 + 阴影。
    /// 保留 `.cornerRadius` / `.shadow` 行为一致；老调用点可直接平替。
    func cardSkin(_ skin: CardSkin, glassEnabled: Bool = false) -> some View {
        modifier(CardSkinModifier(skin: skin, glassEnabled: glassEnabled))
    }
}

/// 从环境对象自动获取属性并渲染的修饰符
@MainActor
private struct EnvironmentCardSkinModifier: ViewModifier {
    @Environment(RepositoryContainer.self) private var container
    
    func body(content: Content) -> some View {
        content.cardSkin(container.envManager.effectiveCardSkin, glassEnabled: container.envManager.glassEffectEnabled)
    }
}

/// 单 skin 渲染修饰符。`@MainActor` 因为要构建 `View`。
@MainActor
private struct CardSkinModifier: ViewModifier {
    let skin: CardSkin
    let glassEnabled: Bool
    @Environment(\.exportMode) private var exportMode

    func body(content: Content) -> some View {
        // 导出模式(`ImageRenderer` 截图)下强制走非 glass 分支:
        // iOS 26 的 `glassEffect` 是实时 UIKit 材质,在 ImageRenderer 渲染管线里
        // 会变成几乎透明的 `Color.clear`,导致整张卡片在导出的图里显灰、
        // 边框/阴影消失。直接用 `backgroundFill()` 走系统颜色,保证导出图清晰。
        // Force the non-glass branch in export mode (`ImageRenderer` rasterisation):
        // iOS 26 `glassEffect` is a live UIKit material and renders as near-transparent
        // in `ImageRenderer`, making the exported card look washed out / borderless.
        // Falling back to `backgroundFill()` ensures the exported image stays clean.
        let effectiveGlass = glassEnabled && !exportMode
        if skin.isGlass && effectiveGlass {
            // iOS 26 glass path：保持现有 `GlassCardBackground` 行为
            content
                .background(GlassCardBackground(cornerRadius: skin.cornerRadius, style: .regular))
        } else {
            content
                .background(skin.backgroundFill())
                .overlay(
                    RoundedRectangle(cornerRadius: skin.cornerRadius, style: .continuous)
                        .stroke(skin.accentColor.opacity(skin.borderOpacity), lineWidth: skin.borderWidth)
                )
                .shadow(
                    color: Color.black.opacity(skin.shadowOpacity),
                    radius: skin.shadowRadius,
                    x: 0,
                    y: skin.shadowRadius * 0.4
                )
        }
    }
}

// MARK: - CardSkin view extensions

@MainActor
extension CardSkin {
    /// 渲染卡片背景填充（按 `styleVariant` 分支）。
    @ViewBuilder
    func backgroundFill() -> some View {
        switch styleVariant {
        case .plain:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.systemBackground))

        case .gradient:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        accentColor.opacity(0.15),
                        Color(.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

        case .frosted:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)

        case .aurora:
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.systemBackground))
                LinearGradient(
                    colors: [
                        Color(red: 0.45, green: 0.30, blue: 0.95).opacity(0.10),
                        accentColor.opacity(0.10),
                        Color(red: 0.10, green: 0.60, blue: 0.85).opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }

        case .sakura:
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.systemBackground))
                LinearGradient(
                    colors: [
                        accentColor.opacity(0.20),
                        Color(red: 1.0, green: 0.85, blue: 0.90).opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                // 樱花瓣装饰：3 个不同位置的粉点（SF Symbol）
                ZStack {
                    Image(systemName: "leaf.fill")
                        .foregroundColor(accentColor.opacity(0.18))
                        .scaledFont(size: 22)
                        .offset(x: -50, y: -20)
                        .rotationEffect(.degrees(-15))
                    Image(systemName: "leaf.fill")
                        .foregroundColor(accentColor.opacity(0.12))
                        .scaledFont(size: 16)
                        .offset(x: 55, y: 25)
                        .rotationEffect(.degrees(35))
                    Image(systemName: "leaf.fill")
                        .foregroundColor(accentColor.opacity(0.10))
                        .scaledFont(size: 12)
                        .offset(x: 30, y: -35)
                        .rotationEffect(.degrees(-40))
                }
            }

        case .galaxy:
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.systemBackground))
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.05, blue: 0.30).opacity(0.18),
                        accentColor.opacity(0.15),
                        Color(red: 0.30, green: 0.20, blue: 0.55).opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                // 星空装饰：稀疏的星点
                ZStack {
                    ForEach(0..<6, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 2, height: 2)
                            .offset(
                                x: CGFloat([-50, -20, 15, 40, 65, -35][i]),
                                y: CGFloat([-25, 18, -10, 30, -8, 32][i])
                            )
                    }
                }
            }

        case .parchment:
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.94, blue: 0.86),
                            Color(red: 0.94, green: 0.88, blue: 0.76)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
        }
    }

    /// 渲染卡片阴影（在 modifier 内部以 `.shadow` 形式挂载，单独抽出供自定义阴影场景使用）。
    var shadow: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowRadius / 2)
    }
}
