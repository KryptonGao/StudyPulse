//
//  DiaryHomeCard.swift
//  StudyPulse
//
//  首页"学习日记"卡片:今日 emoji(大,只读)+ 精力 tag + 最近日记预览。
//  整个卡片可点击 → 导航到二级 DiaryView 页面;在 DiaryView 中才允许编辑/添加。
//
//  Home "Study Diary" card: today's emoji (large, read-only) + energy tag
//  + latest entry preview. The whole card is tappable and navigates to
//  the secondary DiaryView page; editing happens inside DiaryView.
//
//

import SwiftUI

struct DiaryHomeCard: View {
    @Environment(RepositoryContainer.self) private var container

    /// 今日日记(若有)
    /// Today's diary entry, if any.
    private var today: DiaryEntry? {
        container.diaryRepo.todayEntry()
    }

    /// 最近一条日记(用于预览;可能与 today 重合)
    /// The latest diary entry (for preview; may coincide with today).
    private var latest: DiaryEntry? {
        container.diaryRepo.filteredDiaryEntries.first
    }

    var body: some View {
        // 整张卡片用 NavigationLink 推送到 DiaryView。
        // 注意:NavigationLink 内部不能再嵌套 Button,否则会拦截 tap。
        // 注意:这里 emoji 是纯 Text(只读),无 Button,确保整张卡可点。
        // The whole card uses NavigationLink to push DiaryView.
        // Note: NavigationLink must not wrap a Button, otherwise the
        // inner Button hijacks the tap. The emoji here is plain Text
        // (read-only), so the entire card is tappable.
        NavigationLink(value: HomeCardType.diary) {
            VStack(alignment: .leading, spacing: 10) {
                // 头部:标题(NavigationLink 自带右侧 chevron,无需手写)
                // Header: title only. NavigationLink supplies its own chevron.
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                        .font(.title3)
                        .foregroundColor(container.envManager.effectiveAccentColor)
                    Text("Study Diary".localized())
                        .font(.headline.weight(.bold))
                        .foregroundColor(.primary)
                }

                // 主体:今日 emoji(只读)+ 精力 tag + 最近日记预览
                // Body: today's emoji (read-only) + energy tag + latest entry preview.
                HStack(alignment: .center, spacing: 14) {
                    // 今日 emoji(只读,无 Button,确保 NavigationLink 可点)
                    // Today's emoji (read-only; plain Text so NavigationLink stays tappable).
                    Text(today?.moodEmoji ?? "➕")
                        .scaledFont(size: 48)
                        .frame(width: 72, height: 72)
                        .background(
                            Circle()
                                .fill(container.envManager.effectiveAccentColor.opacity(0.12))
                        )
                        .accessibilityLabel(moodAccessibilityLabel)

                    VStack(alignment: .leading, spacing: 4) {
                        if let today {
                            Text(today.moodEmoji + " " + moodLabel(today.moodScore))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            if !today.energyTag.isEmpty {
                                Text(today.energyTag)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color(.tertiarySystemFill)))
                            }
                        } else {
                            Text("No Diary Entries Yet".localized())
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text("Track your mood, energy, and reflections to see patterns over time.".localized())
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer()
                }

                // 最近一条日记内容预览(2 行截断)
                // Latest entry content preview (2 lines truncated).
                if let latest, !latest.content.isEmpty, latest.id != today?.id {
                    Text(latest.content)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
            .padding(DesignToken.Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardSkin()
    }

    /// 今日 moodScore 对应的简短文案
    /// Short label for today's mood score.
    private var moodAccessibilityLabel: String {
        guard let today else { return "No Diary Entries Yet".localized() }
        return "Today: " + moodLabel(today.moodScore)
    }

    /// moodScore → 文案
    /// moodScore → label.
    private func moodLabel(_ score: Int) -> String {
        switch score {
        case 1: return "Sad".localized()
        case 2: return "Low".localized()
        case 3: return "OK".localized()
        case 4: return "Good".localized()
        case 5: return "Great".localized()
        default: return ""
        }
    }
}

// MARK: - 预览 / Preview

#Preview("With Today") {
    let container = RepositoryContainer()
    DiaryHomeCard()
        .environment(container)
        .padding()
        .background(Color(.systemGroupedBackground))
        .onAppear {
            container.diaryRepo.add(DiaryEntry(date: .now, moodScore: 4, energyScore: 3, energyTag: "专注", content: "# 今天\n完成数学三章复习。"))
        }
}

#Preview("Empty") {
    DiaryHomeCard()
        .environment(RepositoryContainer())
        .padding()
        .background(Color(.systemGroupedBackground))
}
