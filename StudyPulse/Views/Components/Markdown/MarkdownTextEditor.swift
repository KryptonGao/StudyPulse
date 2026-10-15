//
//  MarkdownTextEditor.swift
//  StudyPulse
//
//  Cursor-aware `UITextView` wrapper used by `MarkdownEditorView`.
//  The stock SwiftUI `TextEditor` does not expose its `selectedRange`,
//  so a UIViewRepresentable is required for the keyboard accessory
//  toolbar (`MarkdownKeyboardToolbar`) to insert and wrap text at the
//  current cursor position. The accessory is mounted as the text
//  view's `inputAccessoryView`, giving it the same Notes-style
//  positioning above the keyboard.
//
//  MarkdownEditorView 使用的光标感知 UITextView 包装。
//  系统 SwiftUI TextEditor 不暴露 selectedRange,所以需要
//  UIViewRepresentable,键盘附件工具栏才能在当前光标处插入/
//  包裹文本。附件以 inputAccessoryView 形式挂到 textView,
//  实现 Notes 风格:浮在键盘上方。
//

import SwiftUI
import UIKit

// MARK: - Cursor-aware Markdown Text Editor
// MARK: - 光标感知 Markdown 编辑器

/// 把 `UITextView` 包装为 SwiftUI View,暴露 text 和 selectedRange
/// 为 binding,并把 markdown 键盘附件工具栏挂为 inputAccessoryView。
/// A `UITextView` wrapper that exposes its `text` and `selectedRange`
/// as SwiftUI bindings, and installs the markdown keyboard accessory
/// toolbar as its `inputAccessoryView`.
struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var font: UIFont = .preferredFont(forTextStyle: .body)

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = font
        view.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        view.textContainer.lineFragmentPadding = 0
        view.text = text
        view.selectedRange = clampedRange(selectedRange, in: text)

        // 安装 markdown 键盘附件
        // Install the markdown keyboard accessory
        let toolbar = MarkdownKeyboardToolbar(
            text: $text,
            selectedRange: $selectedRange
        )
        let host = UIHostingController(rootView: toolbar)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.autoresizingMask = [.flexibleWidth]
        host.view.frame = CGRect(
            x: 0,
            y: 0,
            width: max(view.bounds.width, 320),
            height: 60
        )
        view.inputAccessoryView = host.view
        context.coordinator.hostController = host

        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // UIViewRepresentable 的 Coordinator 会跨 SwiftUI 更新复用，必须同步
        // 最新的 Binding；否则切换错题分区后，旧 Coordinator 可能把旧值写回表单。
        // UIViewRepresentable reuses its Coordinator across SwiftUI updates, so keep
        // its Binding in sync or a section switch can write stale text back to the form.
        context.coordinator.parent = self

        // 当用户使用中文拼音或 IME 处于"标记文本(Marked Text)"组合状态时,
        // 切勿修改 uiView.text 或 uiView.selectedRange,否则一定会中断/吞除拼音或候选词。
        // When the user is composing with a Chinese pinyin IME or any IME is in a "marked text"
        // composing state, never modify `uiView.text` or `uiView.selectedRange`, otherwise
        // the pinyin / candidate will be eaten.
        // 图片选择器关闭后 UITextView 偶尔仍会短暂保留 marked range。若外部
        // 文本已经改变（例如 AI 识别结果），仍需同步；只有内容本身未改变时
        // 才跳过更新，以免打断用户正在进行的拼音组合输入。
        if uiView.markedTextRange != nil, uiView.isFirstResponder, uiView.text == text {
            return
        }
        context.coordinator.isApplyingExternalText = true
        defer { context.coordinator.isApplyingExternalText = false }
        if uiView.text != text {
            uiView.text = text
        }
        let target = clampedRange(selectedRange, in: text)
        if uiView.selectedRange != target {
            uiView.selectedRange = target
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
        uiView.inputAccessoryView = nil
        if let host = coordinator.hostController {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            coordinator.hostController = nil
        }
    }

    /// 把外部传入的 NSRange 夹紧到 text 内的合法范围,
    /// 防止在文本刚刚缩短(例如工具栏包裹后游标越界)时
    /// 程序设置选区导致崩溃。
    /// Clamp an external `NSRange` to the valid range within `text` so
    /// that programmatically setting the selection cannot crash when
    /// the text was just shortened (e.g. after the toolbar wrapped
    /// something and the cursor offset became out of bounds).
    private func clampedRange(_ range: NSRange, in text: String) -> NSRange {
        let count = text.count
        let location = min(max(range.location, 0), count)
        let length = min(max(range.length, 0), count - location)
        return NSRange(location: location, length: length)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextEditor
        var isApplyingExternalText = false
        /// 在底层 UIView 生命周期内一直持有,
        /// 让键盘附件保持存活。
        /// Retained for the lifetime of the underlying UIView so the
        /// keyboard accessory stays alive.
        var hostController: UIHostingController<MarkdownKeyboardToolbar>?

        init(_ parent: MarkdownTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            // 只有正在交互的编辑器可以写回 Binding。已被分区切换淘汰的
            // UITextView 可能仍收到延迟 delegate 回调，必须忽略。
            guard !isApplyingExternalText, textView.isFirstResponder else { return }
            parent.text = textView.text
            // 拼音组合中不要回写 selectedRange,避免打断 IME。
            // Don't write back selectedRange during IME composing to avoid disrupting the IME.
            if textView.markedTextRange == nil {
                parent.selectedRange = textView.selectedRange
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingExternalText, textView.isFirstResponder else { return }
            guard textView.markedTextRange == nil else { return }
            if parent.selectedRange != textView.selectedRange {
                parent.selectedRange = textView.selectedRange
            }
        }
    }
}

// MARK: - Markdown Keyboard Toolbar
// MARK: - Markdown 键盘附件工具栏

/// 横向、可滚动的键盘附件,带常用 markdown 语法的快速插入按钮。
/// 背景是圆角胶囊,使用 iOS 26+ 的真实 `glassEffect` 材质,
/// 旧系统回退到 `.regularMaterial`。
/// A horizontal, scrolling keyboard accessory with quick-insert buttons
/// for common markdown syntax. The background is a capsule ("rounded
/// rect with both sides fully rounded") that uses the real iOS 26
/// `glassEffect` material when running on iOS 26+, and falls back to
/// `.regularMaterial` on older OSes.
struct MarkdownKeyboardToolbar: View {
    @Binding var text: String
    @Binding var selectedRange: NSRange

    /// 玻璃胶囊高度(60pt)
    /// Glass capsule height (60pt).
    private let glassHeight: CGFloat = 60
    /// 玻璃下方留白(12pt),让玻璃看起来"浮"在键盘上方
    /// Gap below the glass (12pt) so the glass appears to float above the keyboard.
    private let bottomGap: CGFloat = 12
    /// 玻璃左右缩进(12pt)
    /// Left/right margin (12pt).
    private let horizontalMargin: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            // 玻璃胶囊本身保持 60pt 高，左右各缩进 12pt 让它变窄。
            // 玻璃底下的 12pt 留白让玻璃看起来像是浮在键盘上方。
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                toolbarButton("bold") { MarkdownFormatting.wrap(prefix: "**", suffix: "**", placeholder: "bold", into: &text, range: &selectedRange) }
                toolbarButton("italic") { MarkdownFormatting.wrap(prefix: "*", suffix: "*", placeholder: "italic", into: &text, range: &selectedRange) }
                toolbarButton("textformat.size") { MarkdownFormatting.insertLinePrefix("# ", into: &text, range: &selectedRange) }
                listMenuButton
                toolbarButton("text.quote") { MarkdownFormatting.insertLinePrefix("> ", into: &text, range: &selectedRange) }
                toolbarButton("chevron.left.forwardslash.chevron.right") { MarkdownFormatting.wrap(prefix: "`", suffix: "`", placeholder: "code", into: &text, range: &selectedRange) }
                toolbarButton("curlybraces") { MarkdownFormatting.insertBlock(prefix: "```\n", suffix: "\n```", placeholder: "code", into: &text, range: &selectedRange) }
                mathMenuButton
                toolbarButton("link") { MarkdownFormatting.wrap(prefix: "[", suffix: "](url)", placeholder: "text", into: &text, range: &selectedRange) }
                toolbarButton("minus") { MarkdownFormatting.insertAtCursor("\n---\n", into: &text, range: &selectedRange) }
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(height: glassHeight)
            .background {
                // 液态玻璃背景：iOS 26+ 用系统真正的 `glassEffect`，
                // 低版本用 `.regularMaterial` 兜底。不要自己造液态玻璃。
                //
                // 注意：`glassEffect(_:in:)` 必须作用在透明画布上
                // （`Color.clear`），并通过 `in:` 把形状传进去。
                // 直接给 `Capsule()` 调 `glassEffect` 会得到一个
                // 几乎不透明的大色块，而不是液态玻璃。
                if #available(iOS 26, *) {
                    Color.clear
                        .glassEffect(.regular, in: Capsule())
                } else {
                    Capsule()
                        .fill(.regularMaterial)
                }
            }
            .padding(.horizontal, horizontalMargin)

            // 玻璃胶囊下方的留白，让玻璃看起来"浮"在键盘上方
            Color.clear
                .frame(height: bottomGap)
        }
        .frame(height: glassHeight + bottomGap)
    }

    // MARK: - Button
    // MARK: - 按钮

    /// 单个工具栏按钮(SF Symbol + 点击执行的动作)
    /// Single toolbar button (SF Symbol + tap action).
    @ViewBuilder
    private func toolbarButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .scaledFont(size: 20, weight: .medium)
                .frame(width: 44, height: 44)
                .foregroundColor(.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityName(forSymbol: systemName))
    }

    /// 工具栏图标按钮的 VoiceOver 名称 / VoiceOver names for the icon-only toolbar buttons.
    private static func accessibilityName(forSymbol systemName: String) -> String {
        switch systemName {
        case "bold": return "a11y.md.bold".localized()
        case "italic": return "a11y.md.italic".localized()
        case "textformat.size": return "a11y.md.heading".localized()
        case "text.quote": return "a11y.md.quote".localized()
        case "chevron.left.forwardslash.chevron.right": return "a11y.md.inlineCode".localized()
        case "curlybraces": return "a11y.md.codeBlock".localized()
        case "link": return "a11y.md.link".localized()
        case "minus": return "a11y.md.divider".localized()
        default: return systemName
        }
    }

    /// 把"无序 / 有序 / 待办"三种列表合并到一个按钮:
    /// 点击 `list.bullet` 弹出 iOS 原生菜单,三选一后插入对应 markdown。
    /// Combine "bullet / numbered / checklist" into one button: tap
    /// `list.bullet` to bring up the native iOS menu, then pick one
    /// to insert the matching markdown.
    @ViewBuilder
    private var listMenuButton: some View {
        Menu {
            Button {
                MarkdownFormatting.insertLinePrefix("- ", into: &text, range: &selectedRange)
            } label: {
                Label("Bullet".localized(), systemImage: "list.bullet")
            }
            Button {
                MarkdownFormatting.insertLinePrefix("1. ", into: &text, range: &selectedRange)
            } label: {
                Label("Number".localized(), systemImage: "list.number")
            }
            Button {
                MarkdownFormatting.insertLinePrefix("- [ ] ", into: &text, range: &selectedRange)
            } label: {
                Label("Checklist".localized(), systemImage: "checklist")
            }
        } label: {
            Image(systemName: "list.bullet")
                .scaledFont(size: 20, weight: .medium)
                .frame(width: 44, height: 44)
                .foregroundColor(.primary)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .accessibilityLabel("a11y.md.math".localized())
    }

    /// 把"行内公式 / 行间公式"合并到一个按钮:
    /// 点击 `function` 弹出 iOS 原生菜单,二选一后插入 `$…$` 或 `$$…$$`。
    /// Combine "inline / block math" into one button: tap `function`
    /// to bring up the native iOS menu, then pick one to insert
    /// `$…$` (inline) or `$$…$$` (block).
    @ViewBuilder
    private var mathMenuButton: some View {
        Menu {
            Button {
                MarkdownFormatting.wrap(prefix: "$", suffix: "$", placeholder: "x", into: &text, range: &selectedRange)
            } label: {
                Label("Inline Math".localized(), systemImage: "x.squareroot")
            }
            Button {
                MarkdownFormatting.insertBlock(prefix: "$$\n", suffix: "\n$$", placeholder: "x", into: &text, range: &selectedRange)
            } label: {
                Label("Block Math".localized(), systemImage: "function")
            }
        } label: {
            Image(systemName: "function")
                .scaledFont(size: 20, weight: .medium)
                .frame(width: 44, height: 44)
                .foregroundColor(.primary)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
    }

    // 文本操作 helper 之前作为 `private func` 写在这里。
    // 它们被抽到 `MarkdownFormatting` 中,这样 iPad 菜单栏命令
    // (`MarkdownCommands`)就能调用与屏幕工具栏相同的代码路径
    // —— 保持两个入口行为一致。
    // Text manipulation helpers used to live here as `private func`
    // methods. They were extracted to `MarkdownFormatting` so the
    // iPad menu-bar commands (`MarkdownCommands`) can call the same
    // code path as the on-screen toolbar — keeping both inputs
    // behaviourally identical.
}
