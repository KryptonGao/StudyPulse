//
//  MarkdownPreviewView.swift
//  StudyPulse
//
//  Scrollable preview that renders a markdown string via
//  SwiftStreamingMarkdown's `MarkdownView`. Adapts to light/dark mode
//  automatically through the package's render config.
//
//  可滚动的 Markdown 预览,通过 SwiftStreamingMarkdown 的
//  MarkdownView 渲染,深浅色模式由包的 render config 自动适配。
//

import SwiftUI
import SwiftStreamingMarkdown

/// 可滚动的 Markdown 内容预览。
/// The scrollable rendered preview of markdown content.
struct MarkdownPreviewView: View {
    /// 要渲染的原始 markdown 源
    /// The raw markdown source to render.
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if text.isEmpty {
                    emptyPreview
                } else {
                    MarkdownView(text: text.normalisingSingleDollarMath(), config: .previewConfig)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 不填背景色,让父层透出来,使预览从编辑器无缝流出,
        // 在分隔线处没有可见的"色块"。
        // No background fill — let the parent show through so the
        // preview flows seamlessly out of the editor without a
        // visible "block" at the divider.
    }

    /// 文本为空时显示的占位
    /// Empty-state placeholder shown when `text` is empty.
    private var emptyPreview: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.viewfinder")
                .scaledFont(size: 32)
                .foregroundColor(.secondary.opacity(0.5))
            Text("Start typing markdown above")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

/// 用于快照 / 分享视图的简化预览。
/// A simplified preview used for snapshot / share views.
struct StaticMarkdownPreviewView: View {
    let markdownText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MarkdownView(text: markdownText.normalisingSingleDollarMath(), config: .previewConfig)
            }
            .padding(12)
        }
    }
}

// MARK: - Render config used by the app's previews
// MARK: - 应用预览所用的渲染配置

// 暴露为 internal(非 private)是为了让其他 view
// (例如 MistakeSetDetailView 的只读页)能复用同一个渲染配置
// 和单美元数学公式归一化逻辑。
// Internal (not private) so other views in the app — e.g. the
// `MistakeSetDetailView` read-only page — can reuse the same renderer
// config and single-dollar math normalisation.
extension MarkdownRenderConfig {
    /// 块间距更紧凑,与之前的内嵌预览样式保持一致。
    /// Lighter block spacing matches the previous in-house preview layout.
    static let previewConfig: MarkdownRenderConfig = {
        // 起始 = 包默认配置,关闭文字动画,块间距改为 8pt
        // Start from the package default, disable text animation, set block spacing to 8pt.
        var config = MarkdownRenderConfig.default
        config = config.withShouldAnimateText(value: false)
        config = config.withBlockSpacing(value: 8)
        return config
    }()

    /// 流式输出用:在 `previewConfig` 基础上开启逐词淡入(新到的词各自淡入,而不是整段跳出)。
    /// 仅在正在流式输出时使用;流结束后切回 `previewConfig`,已在渐显的词会自然完成。
    /// Streaming variant of `previewConfig` with per-word fade-in enabled, so new words
    /// ink in one by one instead of popping. Used only while a reply is streaming.
    static let streamingConfig: MarkdownRenderConfig = previewConfig.withShouldAnimateText(value: true)

    /// 按是否正在流式输出选择配置。
    /// Picks the config for the current streaming state.
    static func chatConfig(isStreaming: Bool) -> MarkdownRenderConfig {
        isStreaming ? streamingConfig : previewConfig
    }
}

#Preview {
    let sampleMD = """
    # Sample Markdown

    This is a **bold** and *italic* paragraph with `inline code`.

    ## Math Formulas

    Inline: $E = mc^2$

    Display:
    $$
    \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}
    $$

    ## Chemistry

    $\\ce{H2O}$ is water. Reaction:
    $$
    \\ce{2H2 + O2 -> 2H2O}
    $$

    ### Lists

    - Item one
    - Item **two**
    - Item *three*

    1. First step
    2. Second step

    ### Tasks

    - [x] Completed task
    - [ ] Pending task

    > This is a blockquote with **bold** text.

    ```
    func hello() {
        print("Hello World")
    }
    ```

    | Name | Score |
    |------|-------|
    | Math | 95    |
    | English | 88 |
    """
    MarkdownPreviewView(text: sampleMD)
}

// MARK: - Single-dollar inline math normalisation
// MARK: - 单美元行内数学公式归一化

// 暴露为 internal(非 private)是为了让 MistakeSetDetailView 和
// 其他应用内的只读 markdown 渲染器,可以在把源交给
// MarkdownView 之前先归一化 `$…$` → `\(…\)`。
// Internal (not private) so `MistakeSetDetailView` and other read-only
// markdown renderers in the app can normalise `$…$` → `\(…\)` before
// passing the source to `MarkdownView`.
extension String {
    /// SwiftStreamingMarkdown 的 LaTeX 预处理器只识别定界符
    /// `$$…$$`(块)、`\[…\]`(块)和 `\(…\)`(行内)。
    /// 不识别更常见的单美元形式 `$…$` 表示行内数学,
    /// 所以本辅助在把源交给 MarkdownView 之前把所有 `$…$`
    /// 改写为 `\(…\)`。
    ///
    /// 规则:
    /// - 开头的 `$` 之前不能是反斜杠(即 `\$` 保持字面美元符号)
    ///   也不能紧邻另一个 `$`(让 `$$…$$` 块公式得以保留)。
    /// - 结尾的 `$` 对称处理。
    /// - 中间内容不能再含 `$` 或换行,匹配必须保持在单行、
    ///   原始定界符之内。
    /// - 单独一个开 `$` 未闭合(例如 "100$ price")保持不变。
    /// SwiftStreamingMarkdown's LaTeX pre-processor only recognises the
    /// delimiters `$$…$$` (block), `\[…\]` (block) and `\(…\)` (inline).
    /// It does **not** recognise the more common single-dollar form
    /// `$…$` for inline math, so this helper rewrites every occurrence
    /// of `$…$` into `\(…\)` before the source is handed to `MarkdownView`.
    ///
    /// Rules:
    /// - The opening `$` must not be preceded by a backslash (i.e. `\$`
    ///   is left untouched as a literal dollar sign) and must not be
    ///   adjacent to another `$` (so `$$…$$` block math is preserved).
    /// - The closing `$` is treated symmetrically.
    /// - The body must not contain another `$` or a newline, so the
    ///   match stays on a single line and inside the original delimiters.
    /// - An unmatched opening `$` (e.g. "100$ price") is left as-is.
    func normalisingSingleDollarMath() -> String {
        // 先将不支持的 cases 环境替换为 array 环境
        // First replace unsupported cases environment with array environment
        let replacedCases = self
            .replacingOccurrences(of: "\\begin{cases}", with: "\\left\\{\\begin{array}{l}")
            .replacingOccurrences(of: "\\end{cases}", with: "\\end{array}\\right.")

        // 正则解析:
        // (?<!\$)(?<!\\)\$(?!\$)  – 开头 $,不是 \$、$$ 或 $$ 右侧一部分
        // ([^\$\n]+?)              – 行内公式主体(无 $,无 \n)
        // \$(?!\$)                 – 结尾 $,不是 $$ 的一部分
        // Regex breakdown:
        // (?<!\$)(?<!\\)\$(?!\$)  – opening $ that is not part of \$, $$
        //                         or the right side of a $$ sequence
        // ([^\$\n]+?)              – the inline math body (no $, no \n)
        // \$(?!\$)                 – closing $ that is not part of $$
        let pattern = #"(?<!\$)(?<!\\)\$(?!\$)([^\$\n]+?)\$(?!\$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return replacedCases
        }
        let range = NSRange(replacedCases.startIndex..., in: replacedCases)
        // 替换模板:把捕获组用 \( ... \) 包裹
        // Replacement template: wrap the captured group in \( ... \).
        return regex.stringByReplacingMatches(
            in: replacedCases,
            options: [],
            range: range,
            withTemplate: "\\\\($1\\\\)"
        )
    }
}
