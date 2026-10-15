//
//  ScaledFont.swift
//  StudyPulse
//
//  随 Dynamic Type 缩放的「自定义字号」修饰符。
//  Dynamic Type–aware replacement for `.font(.system(size:))`.
//
//  字体规范(三选一,优先级自上而下):
//  1. `DesignToken.Font.*` 语义 token(基于系统 text style,自动缩放);
//  2. 系统 text style(`.font(.subheadline)` 等);
//  3. 设计稿要求的特殊字号 → `.scaledFont(size:weight:design:)`(本文件)。
//  严禁再写 `.font(.system(size:))`,`scripts/check_fonts.sh` 会拦截。
//
//  Font policy, in priority order: DesignToken.Font tokens → system text styles →
//  `.scaledFont(size:)` for off-scale sizes. Raw `.font(.system(size:))` is forbidden
//  (enforced by `scripts/check_fonts.sh`).
//

import SwiftUI

extension View {
    /// 默认字号下与 `.font(.system(size:weight:design:))` 视觉完全一致,但会随用户的
    /// Dynamic Type 设置缩放。较大字号(图标 / 大数字)限制最大放大倍数,避免撑破固定尺寸容器。
    /// Looks identical to `.font(.system(size:...))` at the default content size but scales with
    /// Dynamic Type. Large sizes (icons / display numbers) cap their growth so fixed frames survive.
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design))
    }
}

private struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let baseSize: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: Self.textStyle(for: size))
        baseSize = size
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        let capped = min(scaledSize, baseSize * Self.maxScale(for: baseSize))
        return content.font(.system(size: capped, weight: weight, design: design))
    }

    /// 按字号选取最接近的 text style,使缩放曲线与系统文本一致。
    /// Picks the closest text style so the scaling curve matches system text.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<13.5: return .footnote
        case ..<15.5: return .subheadline
        case ..<16.5: return .callout
        case ..<17.5: return .body
        case ..<21: return .title3
        case ..<27: return .title2
        case ..<33: return .title
        default: return .largeTitle
        }
    }

    /// 字号越大允许的最大放大倍数越小。
    /// The larger the base size, the smaller the allowed growth.
    private static func maxScale(for size: CGFloat) -> CGFloat {
        switch size {
        case 40...: return 1.3
        case 28...: return 1.6
        case 20...: return 2.0
        default: return 3.5
        }
    }
}
