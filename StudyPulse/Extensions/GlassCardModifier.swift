//  GlassCardModifier.swift
//  StudyPulse
//
//  玻璃效果修饰符:iOS 26+ 用系统 `glassEffect`;老版本 fallback `.regularMaterial`。
//  Glass-effect modifier: iOS 26+ uses system `glassEffect`; older falls back to `.regularMaterial`.
//  默认关闭(由 AppEnvironmentManager.glassEffectEnabled 控制)。卡片入口统一用 `.cardSkin()`
//  (`CardSkinRenderer`),它在开启玻璃时才会使用本背景;旧的 `.glassCard(enabled:)` 修饰符已删除。
//  Disabled by default (toggled by AppEnvironmentManager.glassEffectEnabled). Cards go through
//  `.cardSkin()` (CardSkinRenderer), which uses this background only when glass is on; the old
//  `.glassCard(enabled:)` modifier was removed.
//

import SwiftUI

/// 玻璃卡片背景 / Glass card background.
struct GlassCardBackground: View {
    var cornerRadius: CGFloat = 18  // 卡片圆角 / Card corner radius.
    var style: GlassStyle = .regular  // 玻璃样式 / Glass style.

    /// 玻璃样式 / Glass style options.
    enum GlassStyle {
        case regular  // 标准 / Standard glass.
        case clear  // 透明 / Clear glass (more lightweight).
    }

    var body: some View {
        if #available(iOS 26, *) {
            // 必须作用在透明画布(`Color.clear`)上 + `in:` 传入形状;
            // 直接给形状调 `glassEffect` 会得到几乎不透明的大色块。
            // Apply to a transparent canvas (`Color.clear`) with shape via `in:`;
            // applying `glassEffect` directly to the shape yields a near-opaque block.
            Color.clear
                .glassEffect(
                    style == .regular ? .regular : .clear,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            // iOS 26 之前没有 glassEffect,regularMaterial 兜底 / Pre-iOS 26 fallback.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}
