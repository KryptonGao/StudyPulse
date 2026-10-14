//
//  HomeCardChrome.swift
//  StudyPulse
//
//  主页卡片共用外观:标题 / 容器 / sparkline / 涨跌徽章。
//  Shared Home card chrome: header, container, sparkline, delta badge.
//

import SwiftUI
import Charts

// MARK: - Card Container

/// 主页卡片统一容器:内边距 + 宽度撑满 + `cardSkin()`(遵守 exportMode)。
/// Unified Home card container: padding + full width + `cardSkin()` (export-mode aware).
struct HomeCardContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            content()
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
    }
}

// MARK: - Card Header

/// 主页卡片统一标题:图标 + 标题 + 次要副标 + 右侧 accessory。
/// Unified Home card header: icon + title + secondary subtitle + trailing accessory.
struct HomeCardHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = .accentColor
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignToken.Spacing.small) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(DesignToken.Font.titleSmall)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(DesignToken.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension HomeCardHeader where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, tint: Color = .accentColor) {
        self.init(icon: icon, title: title, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

// MARK: - Sparkline

/// 极简折线 + 面积图(无坐标轴),用于 KPI / 科目行。至少 2 个点才渲染。
/// Minimal line + area chart without axes for KPI / subject rows. Needs at least 2 points.
struct HomeSparkline: View {
    let values: [Double]
    var tint: Color = .accentColor
    var height: CGFloat = 28

    private struct Point: Identifiable {
        let id: Int
        let value: Double
    }

    private var points: [Point] {
        values.enumerated().map { Point(id: $0.offset, value: $0.element) }
    }

    var body: some View {
        if values.count >= 2 {
            let lo = values.min() ?? 0
            let hi = values.max() ?? 1
            let pad = max((hi - lo) * 0.15, 0.5)
            Chart(points) { point in
                LineMark(x: .value("Index", point.id), y: .value("Value", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                AreaMark(
                    x: .value("Index", point.id),
                    yStart: .value("Base", lo - pad),
                    yEnd: .value("Value", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(tint.opacity(0.12))
            }
            .chartYScale(domain: (lo - pad)...(hi + pad))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: height)
            .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: height)
        }
    }
}

// MARK: - Delta Badge

/// 涨跌徽章:▲ / ▼ + 数值;`delta` 为 nil 或接近 0 时显示平稳符号。
/// Delta badge: ▲ / ▼ + value; shows a flat marker when `delta` is nil or ~0.
struct HomeDeltaBadge: View {
    let delta: Double?
    /// 数值格式(默认 1 位小数)/ Value format (default 1 decimal).
    var format: String = "%.1f"
    /// 为 false 时,下降视为好事(如错题数)/ When false, a decrease is considered good.
    var higherIsBetter: Bool = true

    var body: some View {
        let value = delta ?? 0
        let isFlat = delta == nil || abs(value) < 0.05
        let isGood = higherIsBetter ? value > 0 : value < 0
        let color: Color = isFlat ? .secondary : (isGood ? .green : .red)
        HStack(spacing: 2) {
            Image(systemName: isFlat ? "minus" : (value > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"))
                .font(.system(size: 8, weight: .bold))
            if !isFlat {
                Text(String(format: format, abs(value)))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
    }
}

#Preview("HomeCardChrome") {
    HomeCardContainer {
        HomeCardHeader(icon: "chart.bar.fill", title: "Weekly Focus", subtitle: "7 days", tint: .blue) {
            HomeDeltaBadge(delta: 12.5)
        }
        HomeSparkline(values: [60, 72, 65, 80, 77, 90, 88], tint: .blue, height: 44)
    }
    .padding()
    .environment(RepositoryContainer())
}
