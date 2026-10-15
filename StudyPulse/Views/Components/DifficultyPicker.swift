// MARK: - DifficultyPicker
// MARK: - 难度选择器

/// 1-5 星难度自评控件。
/// 横向 5 颗星;点第 N 颗把 difficulty 设为 N;再点同颗回到 0(未评)
/// 0 颗星显示灰色描边,表示"未评"
/// 用于 MistakeDetailEditView / NewMistakeSetView 的 basicInfoSection
///
/// Difficulty self-rating control (1-5 stars).
/// - Tap the Nth star to set difficulty = N; tap the same star again to clear (0 = unrated).
/// - 0 stars shows as outlined gray (unrated).
/// - Used by MistakeDetailEditView / NewMistakeSetView basicInfoSection.
//

import SwiftUI

struct DifficultyPicker: View {
    @Binding var difficulty: Int
    /// 表头文案(可外部传入已本地化的字符串)
    /// Header label (caller may pass an already-localized string).
    var label: String = "Difficulty".localized()
    /// 是否只读(展示用,不可点)
    /// Whether the picker is read-only (display only).
    var isReadOnly: Bool = false
    /// 0 = 未评 / 1-5
    /// 0 = unrated / 1-5 = rated.
    static let maxStars: Int = 5
    /// 字号 / 间距参数
    /// Font size and inter-star spacing.
    var starSize: CGFloat = 28
    var starSpacing: CGFloat = 4

    var body: some View {
        HStack(spacing: starSpacing) {
            if !label.isEmpty {
                Text(label)
                    .foregroundColor(.secondary)
                Spacer(minLength: 8)
            }

            HStack(spacing: starSpacing) {
                ForEach(1...Self.maxStars, id: \.self) { index in
                    Button {
                        guard !isReadOnly else { return }
                        // 同一颗再点 → 清除到 0(未评)
                        if difficulty == index {
                            difficulty = 0
                        } else {
                            difficulty = index
                        }
                    } label: {
                        Image(systemName: index <= difficulty ? "star.fill" : "star")
                            .scaledFont(size: starSize, weight: .semibold)
                            .foregroundStyle(starColor(for: index))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .disabled(isReadOnly)
                    .accessibilityLabel(Text(String(format: "%d star".localized(), index)))
                }
            }

            // 右侧文字提示(1★ / 3★ / 5★ 含义)
            if !isReadOnly {
                Text(label(for: difficulty))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 56, alignment: .leading)
            }
        }
    }

    /// 单颗星颜色:difficulty == 0 全部灰;有评 → 1-2 绿,3 蓝,4-5 红
    /// Per-star color: when unrated all stars are gray; otherwise 1-2 green, 3 blue, 4-5 red.
    private func starColor(for index: Int) -> Color {
        guard index <= difficulty, difficulty > 0 else {
            return .gray.opacity(0.4)
        }
        // 颜色阈值:1-2 绿(易),3 蓝(中),4-5 橙(难)
        // Color thresholds: 1-2 green (easy), 3 blue (medium), 4-5 orange (hard).
        switch difficulty {
        case 1, 2: return .green
        case 3:   return .blue
        case 4, 5: return .orange
        default:  return .gray
        }
    }

    /// 当前 difficulty 的语义标签(0=未评)
    /// Semantic label for the current difficulty (0 = unrated).
    private func label(for value: Int) -> String {
        switch value {
        case 0: return "Unrated".localized()
        case 1: return "Easy".localized()
        case 2: return "Basic".localized()
        case 3: return "Medium".localized()
        case 4: return "Hard".localized()
        case 5: return "Extreme".localized()
        default: return ""
        }
    }
}

#Preview {
    struct Container: View {
        @State var d: Int = 3
        var body: some View {
            VStack(spacing: 24) {
                DifficultyPicker(difficulty: $d)
                DifficultyPicker(difficulty: $d, isReadOnly: true)
                Text("Selected: \(d)").font(.caption)
            }
            .padding()
        }
    }
    return Container()
}
