//
//  TagEditorView.swift
//  StudyPulse
//
//  标签输入控件:TextField 输入新标签 → 回车 / "," 提交 → 追加为胶囊。
//  同时给出基于 suggestedTags(全库聚合) 的自动联想。
//  用法见 MistakeDetailEditView / NewMistakeSetView。
//
//  Tag input: type a new tag + Enter / "," to commit. Also shows
//  autocomplete suggestions from `suggestedTags`.
//
//  分隔符:",",";" 也算提交(支持一次粘贴多个标签)
//  去重:大小写不敏感
//  Suggestions:大小写不敏感 + 不含已选 + 含当前输入子串
//  Delimiters: "," / ";" both commit (supports pasting multiple tags).
//  Dedup: case-insensitive.
//  Suggestions: case-insensitive, exclude already-selected, contain current input.
//

import SwiftUI

/// 标签输入控件:TextField + 已选胶囊 + 自动联想建议。
/// Tag input control: TextField + selected pills + autocomplete suggestions.
struct TagEditorView: View {
    @Binding var tags: [String]
    /// 全库所有已存在的标签,用于自动联想
    /// All existing tags in the library, used for autocomplete.
    var suggestedTags: [String] = []
    /// 表头文案
    /// Header label.
    var label: String = "Tags".localized()
    /// 表头内嵌输入框 placeholder
    /// Placeholder for the inline input field.
    var placeholder: String = "Add Tag".localized()

    @State private var input: String = ""
    /// 输入框焦点状态(用于触发自动聚焦等)
    /// Input field focus state (used to trigger autofocus, etc.).
    @FocusState private var inputFocused: Bool

    /// 当前输入匹配的(大小写不敏感、不在已选)建议
    /// Suggestions that match the current input (case-insensitive, exclude already-selected).
    private var suggestions: [String] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let existingLower = Set(tags.map { $0.lowercased() })
        let pool = suggestedTags
            .filter { !$0.isEmpty }
            .filter { !existingLower.contains($0.lowercased()) }
            .filter { lower.isEmpty || $0.lowercased().contains(lower) }
        return Array(pool.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundColor(.secondary)
                Spacer()
            }

            // 已选标签胶囊
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                        tagPill(tag)
                    }
                }
            }

            // 输入区
            HStack(spacing: 8) {
                TextField(placeholder, text: $input)
                    .focused($inputFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { commit() }
                    .onChange(of: input) { _, new in
                        // 逗号 / 分号 也算分隔符(用户图方便)
                        if new.contains(",") || new.contains(";") {
                            commit()
                        }
                    }

                if !input.isEmpty {
                    Button {
                        commit()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.purple)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 联想建议
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tag suggestions".localized())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                            Button {
                                appendTag(s)
                            } label: {
                                Text("#\(s)")
                                    .font(.caption)
                                    .foregroundStyle(Color.purple)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(Color.purple.opacity(0.08))
                                    )
                                    .overlay(
                                        Capsule().stroke(Color.purple.opacity(0.35), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tagPill(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .font(.caption)
            Button {
                removeTag(tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("a11y.removeTag".localized())
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.purple)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.purple.opacity(0.15))
        )
    }

    private func commit() {
        // 一次性 commit 多个分隔符(用户粘贴 "a, b, c")
        let raw = input
        let parts = raw
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for p in parts { appendTag(p) }
        input = ""
    }

    private func appendTag(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 大小写不敏感去重
        let lower = trimmed.lowercased()
        if tags.contains(where: { $0.lowercased() == lower }) { return }
        tags.append(trimmed)
    }

    private func removeTag(_ tag: String) {
        let lower = tag.lowercased()
        tags.removeAll { $0.lowercased() == lower }
    }
}

#Preview {
    struct Container: View {
        @State var tags: [String] = ["函数", "导数"]
        var body: some View {
            TagEditorView(
                tags: $tags,
                suggestedTags: ["函数", "导数", "三角", "解析几何", "不等式", "数列"]
            )
            .padding()
        }
    }
    return Container()
}
