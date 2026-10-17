//
//  PageKit.swift
//  StudyPulse
//
//  非主页分页(趋势 / 错题 / 待办 / 教练 / 设置)共用的原生积木:
//  阶段条、迷你走势、进度环、计数 chip、数据小块、横幅、科目主色。
//  Shared native building blocks for the non-home pages.
//

import SwiftUI
import Charts

// MARK: - Phase bar

/// 大标题下方、靠右的阶段切换条(取代 toolbar `.principal`)。
/// Trailing phase switcher placed under the large title (replaces toolbar `.principal`).
struct PhaseBar: View {
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            PhaseSelectorView()
        }
    }
}

// MARK: - Subject palette

/// 科目主色(同一科在趋势 / 错题 / 待办里保持同色)。
/// Per-subject colour, consistent across Trends / Mistakes / Todo.
enum SubjectPalette {
    static func color(for subject: String) -> Color {
        switch subject {
        case "Chinese": return .red
        case "Mathematics", "Mathematics A", "Mathematics B": return .blue
        case "English": return .green
        case "Science": return .teal
        case "Physics": return .orange
        case "Chemistry": return .purple
        case "Biology": return .mint
        case "History": return .brown
        case "Geography": return .indigo
        case "Politics": return .pink
        case "Information Technology": return .cyan
        case "Art", "Music": return .pink
        case "PE & Health": return .red
        default:
            // 自定义科目:按名称稳定取色,避免每次刷新颜色跳变
            let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .indigo, .mint]
            let seed = subject.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
            return palette[seed % palette.count]
        }
    }
}

// MARK: - Sparkline

struct MiniSparkline: View {
    let values: [Double]
    var color: Color = .accentColor
    var size: CGSize = CGSize(width: 64, height: 26)

    var body: some View {
        if values.count >= 2 {
            let lo = (values.min() ?? 0) - 2
            let hi = (values.max() ?? 1) + 2
            Chart(Array(values.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("i", index), yStart: .value("lo", lo), yEnd: .value("v", value))
                    .foregroundStyle(color.opacity(0.14))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("i", index), y: .value("v", value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: lo...hi)
            .frame(width: size.width, height: size.height)
            .clipped()
            .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: size.width, height: size.height)
        }
    }
}

// MARK: - Progress ring

struct MiniRing: View {
    /// 0...1
    let progress: Double
    var color: Color = .accentColor
    var lineWidth: CGFloat = 4
    var size: CGFloat = 34
    var label: String? = nil

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let label {
                Text(label)
                    .font(.system(size: size * 0.28, weight: .heavy, design: .rounded)) // fixed-size-ok: 随环尺寸缩放
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Count chips

struct ChipItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var systemImage: String? = nil
    var count: Int? = nil
}

/// 可见的筛选 chip 条(取代藏在 Menu 里的筛选)。
/// A visible filter chip strip (replaces filters hidden in a Menu).
struct ChipBar<ID: Hashable>: View {
    let items: [ChipItem<ID>]
    @Binding var selection: ID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignToken.Spacing.small) {
                ForEach(items) { item in
                    let on = item.id == selection
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selection = item.id }
                    } label: {
                        HStack(spacing: 5) {
                            if let icon = item.systemImage { Image(systemName: icon).imageScale(.small) }
                            Text(item.title)
                            if let count = item.count {
                                Text("\(count)").foregroundStyle(on ? .white.opacity(0.8) : .secondary)
                            }
                        }
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, DesignToken.Spacing.tiny)
        }
        .scrollClipDisabled()
    }
}

// MARK: - Stat tile

/// 数值 + 说明的小块。
/// A small value + caption tile.
struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DesignToken.CornerRadius.medium))
    }
}

// MARK: - Delta label

struct DeltaLabel: View {
    let value: Double
    var format: String = "%.1f"
    /// 数值越大越好(排名等取反)/ higher is better (invert for rank).
    var higherIsBetter = true

    var body: some View {
        let good = higherIsBetter ? value >= 0 : value <= 0
        let flat = abs(value) < 0.05
        HStack(spacing: 2) {
            Image(systemName: flat ? "minus" : (value > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"))
                .imageScale(.small)
            Text(String(format: format, abs(value)))
                .monospacedDigit()
        }
        .font(.system(.caption, design: .rounded, weight: .bold))
        .foregroundStyle(flat ? Color.secondary : (good ? Color.green : Color.red))
    }
}

// MARK: - Banner

/// 列表上方的提示横幅(例如过期 / 到期提醒)。
/// An inline banner above a list (e.g. overdue / due reminders).
struct InlineBanner: View {
    let systemImage: String
    let message: Text
    var actionTitle: String? = nil
    var tint: Color = .orange
    var action: (() -> Void)? = nil

    var body: some View {
        let content = HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tint)
            message.font(.subheadline)
            Spacer(minLength: 8)
            if let actionTitle {
                HStack(spacing: 2) {
                    Text(actionTitle)
                    Image(systemName: "chevron.right").imageScale(.small)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: DesignToken.CornerRadius.large))

        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

// MARK: - Card container

/// 页面级卡片:统一内边距 + 主题 `cardSkin`。
/// Page-level card: uniform padding + the themed `cardSkin`.
struct PageCard<Content: View>: View {
    var padding: CGFloat = DesignToken.Spacing.cardPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSkin()
    }
}

#Preview("PageKit") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                MiniSparkline(values: [80, 83, 82, 86, 85, 88], color: .blue)
                MiniRing(progress: 0.62, color: .orange, size: 44, label: "62")
                DeltaLabel(value: -8)
            }
            HStack {
                StatTile(value: "71", label: "平均")
                StatTile(value: "88", label: "最高")
            }
            InlineBanner(systemImage: "exclamationmark.triangle.fill", message: Text("3 items overdue"), actionTitle: "Review")
        }
        .padding()
    }
    .environment(RepositoryContainer())
}
