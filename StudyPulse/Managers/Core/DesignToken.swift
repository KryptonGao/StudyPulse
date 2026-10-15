//
//  DesignToken.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/7/14.
//

import SwiftUI

/// StudyPulse 统一设计语言常量体系 (Design Tokens)
/// StudyPulse Design Tokens Constants
enum DesignToken {
    
    // MARK: - Spacing (间距)
    enum Spacing {
        /// 极小间距 (4pt)：微小边距、小图标与文字间距
        static let tiny: CGFloat = 4
        /// 小间距 (8pt)：子视图紧凑排布
        static let small: CGFloat = 8
        /// 中间距 (12pt)：通用元素间距、卡片内部子视图间距
        static let medium: CGFloat = 12
        /// 大间距 (16pt)：默认卡片边距、内容外边距
        static let large: CGFloat = 16
        /// 超大间距 (24pt)：页面上下安全边距、核心区块间距
        static let extraLarge: CGFloat = 24
        /// 区域/卡片之间的垂直间距 (20pt)：模块间隔
        static let section: CGFloat = 20
        
        /// 主页面水平内边距 (iPhone 20pt, iPad 24pt)
        static var mainHorizontal: CGFloat {
            isIPad ? 24 : 20
        }
        
        /// 主页面水平内边距 (iPhone 20pt, iPad 24pt)，根据 sizeClass 判断
        static func mainHorizontal(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
            sizeClass == .regular ? 24 : 20
        }
        
        /// 二级页水平内边距 (16pt)
        static let secondaryHorizontal: CGFloat = 16
        
        /// 统一默认卡片内边距 (16pt)
        static let cardPadding: CGFloat = 16
        
        /// 统一默认卡片间距/区块间距 (20pt)
        static let cardSpacing: CGFloat = 20
    }
    
    // MARK: - Corner Radius (圆角)
    enum CornerRadius {
        /// 小圆角 (8pt)：微型标签、迷你徽章
        static let small: CGFloat = 8
        /// 中圆角 (12pt)：按钮、细条目卡片、小型弹窗
        static let medium: CGFloat = 12
        /// 大圆角 (16pt)：标准卡片圆角
        static let large: CGFloat = 16
        /// 超大圆角 (24pt)：页面顶部底色卡、底栏浮层
        static let extraLarge: CGFloat = 24
        
        /// 统一默认卡片圆角 (16pt)
        static let card: CGFloat = 16
        /// 统一默认按钮圆角 (12pt)
        static let button: CGFloat = 12
    }
    
    // MARK: - Opacity & Transparency (透明度)
    enum Opacity {
        /// 页面根背景透明度 (0.4)
        static let rootBackground: Double = 0.4
        /// 通用卡片背景透明度 (0.85)
        static let cardBackground: Double = 0.85
        /// 描边/分割线透明度 (0.15)
        static let border: Double = 0.15
        /// 阴影透明度 (0.08)
        static let shadow: Double = 0.08
    }
    
    // MARK: - Font & Typography (字体规范)
    /// 语义字体 token:基于系统 text style,自动随 Dynamic Type 缩放(rounded 设计)。
    /// 括号内为默认内容尺寸下的 pt 值。非标准字号请用 `.scaledFont(size:)`。
    /// Semantic font tokens built on system text styles, so they scale with Dynamic Type.
    /// Point values in parentheses are at the default content size. Use `.scaledFont(size:)` for off-scale sizes.
    enum Font {
        /// 大标题 (28pt) - 页面顶部大标题
        static let titleLarge: SwiftUI.Font = .system(.title, design: .rounded, weight: .bold)
        /// 中标题 (22pt) - 主要栏目、二级页面标题
        static let titleMedium: SwiftUI.Font = .system(.title2, design: .rounded, weight: .bold)
        /// 小标题 (17pt) - 卡片标题、模态框标题
        static let titleSmall: SwiftUI.Font = .system(.headline, design: .rounded, weight: .semibold)
        /// 强调正文 (16pt) - 列表大文字、正文重点
        static let bodyBold: SwiftUI.Font = .system(.callout, design: .rounded, weight: .semibold)
        /// 标准正文 (15pt) - 卡片正文、列表条目文字
        static let body: SwiftUI.Font = .system(.subheadline, design: .rounded, weight: .regular)
        /// 次要正文 (13pt) - 描述文字、小副标题
        static let subheadline: SwiftUI.Font = .system(.footnote, design: .rounded, weight: .regular)
        /// 辅助/辅助信息 (11pt) - 脚注、时间戳、次要标签
        static let caption: SwiftUI.Font = .system(.caption2, design: .rounded, weight: .regular)
    }
}
