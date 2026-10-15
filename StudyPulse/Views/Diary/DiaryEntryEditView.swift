//
//  DiaryEntryEditView.swift
//  StudyPulse
//
//  学习日记编辑器:心情 emoji 选择 + 精力分值 + 精力标签 + Markdown 内容。
//  Diary entry editor: mood emoji picker + energy score + energy tag + markdown content.
//

import SwiftUI

struct DiaryEntryEditView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    /// 正在编辑的日记(nilonI 新建)。调用方传入已有 entry 时为编辑模式。
    /// The entry being edited. `nil`-on-init is handled by caller via
    /// a non-optional `DiaryEntry` initialized before presentation.
    @State private var entry: DiaryEntry
    /// 是否为新建模式(决定保存时调用 add 还是 update)
    /// Whether this is a new entry (controls add vs update on save).
    private let isNew: Bool
    /// 关闭后的回调(可选)
    /// Optional completion callback.
    var onSaved: ((DiaryEntry) -> Void)? = nil

    /// 新建入口
    init(onSaved: ((DiaryEntry) -> Void)? = nil) {
        self._entry = State(initialValue: DiaryEntry(date: .now))
        self.isNew = true
        self.onSaved = onSaved
    }

    /// 编辑入口
    init(editing entry: DiaryEntry, onSaved: ((DiaryEntry) -> Void)? = nil) {
        self._entry = State(initialValue: entry)
        self.isNew = false
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 心情 / Mood
                Section {
                    moodPicker
                } header: {
                    Text("Today's Mood".localized())
                }

                // MARK: - 精力 / Energy
                Section {
                    energyPicker
                    energyTagChips
                } header: {
                    Text("Energy Level".localized())
                }

                // MARK: - 内容 / Content
                Section {
                    CompactMarkdownEditorView(text: $entry.content, title: "Diary Content".localized())
                } header: {
                    Text("Reflection".localized())
                } footer: {
                    Text("Free-form Markdown. Math, lists, and headings are supported.".localized())
                }
            }
            .navigationTitle(isNew ? "New Diary Entry".localized() : "Edit Diary Entry".localized())
            .navigationBarTitleDisplayMode(.inline)
            .containerBackground(.clear, for: .navigation)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel".localized()) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save".localized()) { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - 心情选择器 / Mood Picker

    /// 5 段 emoji 横排,选中态放大 + 描边。
    /// 5 emoji in a row; selected one scales up with a capsule border.
    private var moodPicker: some View {
        HStack(spacing: 12) {
            ForEach(1...5, id: \.self) { score in
                let emoji = DiaryEntry(moodScore: score).moodEmoji
                let isSelected = entry.moodScore == score
                Button {
                    entry.moodScore = score
                } label: {
                    Text(emoji)
                        .scaledFont(size: isSelected ? 40 : 30)
                        .padding(8)
                        .background(
                            Capsule()
                                .fill(isSelected ? container.envManager.effectiveAccentColor.opacity(0.15) : Color.clear)
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? container.envManager.effectiveAccentColor : Color.clear, lineWidth: 2)
                        )
                        .scaleEffect(isSelected ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3), value: entry.moodScore)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - 精力分值选择器 / Energy Picker

    /// 5 段竖条 ProgressView + 标签,1-5 对应填充高度。
    /// 5 vertical bars; the chosen level fills up to that height.
    private var energyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { level in
                    let isFilled = level <= entry.energyScore
                    Button {
                        entry.energyScore = level
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isFilled ? container.envManager.effectiveAccentColor : Color(.tertiarySystemFill))
                                .frame(height: CGFloat(level) * 12)
                            Text("\(level)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 70, alignment: .bottom)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            Text(energyLabel(for: entry.energyScore))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// 精力分值对应的描述文案
    /// Description for a given energy level.
    private func energyLabel(for level: Int) -> String {
        switch level {
        case 1: return "Exhausted".localized()
        case 2: return "Tired".localized()
        case 3: return "Normal".localized()
        case 4: return "Energetic".localized()
        case 5: return "Fully Charged".localized()
        default: return ""
        }
    }

    // MARK: - 精力标签 / Energy Tag Chips

    /// 单选 chip 组,选中态填充主题色。
    /// Single-select chip group; selected chip fills with the accent color.
    private var energyTagChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(DiaryEntry.allEnergyTags, id: \.self) { tag in
                let isSelected = entry.energyTag == tag
                Button {
                    entry.energyTag = isSelected ? "" : tag
                } label: {
                    Text(tag)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected ? container.envManager.effectiveAccentColor : Color(.tertiarySystemFill))
                        )
                        .foregroundColor(isSelected ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 保存 / Save

    private func save() {
        if isNew {
            container.diaryRepo.add(entry)
        } else {
            container.diaryRepo.update(entry)
        }
        onSaved?(entry)
        dismiss()
    }
}

// MARK: - 预览 / Preview

#Preview("New Entry") {
    DiaryEntryEditView()
        .environment(RepositoryContainer())
}

#Preview("Editing") {
    let sample = DiaryEntry(date: .now, moodScore: 4, energyScore: 3, energyTag: "专注", content: "# 今天\n\n完成了数学三章的复习。")
    DiaryEntryEditView(editing: sample)
        .environment(RepositoryContainer())
}
