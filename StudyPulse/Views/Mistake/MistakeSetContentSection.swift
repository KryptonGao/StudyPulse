//
//  MistakeSetContentSection.swift
//  StudyPulse
//
//  错题详情页的"主体内容"区块:原题 / 错因 / 错解 / 正解 四段 Markdown。
//  Each section uses `MarkdownView` (with `normalisingSingleDollarMath` for
//  the `$...$` → `$ ... $` rewrite) and a horizontal image strip (if any).
//
//  Phase 3 拆分 (2026-07-14):原 `MistakeSetDetailView.swift` 抽出,可独立预览。
//

import SwiftUI
import SwiftStreamingMarkdown

/// 错题详情页的"主体内容"区块:原题 / 错因 / 错解 / 正解 四段 Markdown。
/// Main body of the mistake detail page: original question / error reason /
/// wrong solution / correct solution (all rendered via `MarkdownView`).
struct MistakeSetContentSection: View {
    let mistake: MistakeNote

    /// 行背景:左侧一条语义色竖条,区分原题 / 错因 / 错解 / 正解。
    /// Row background with a semantic leading bar to tell the four blocks apart.
    private func bar(_ color: Color) -> some View {
        Color(.secondarySystemGroupedBackground)
            .overlay(alignment: .leading) { color.frame(width: 4) }
    }

    var body: some View {
        // Question Section
        // 原题段:MarkdownView + 题图横滑(若存在)
        // Question section: MarkdownView + question-image strip (if any).
        if !mistake.originalQuestion.isEmpty {
            Section(header: Text("Original Question".localized())) {
                MarkdownView(
                    // normalisingSingleDollarMath 把 "$...$" → "$ ... $",
                    // 让 SwiftUI Markdown / MathJax 都能正确解析
                    // normalisingSingleDollarMath rewrites "$...$" to "$ ... $"
                    // so both SwiftUI Markdown and MathJax render it.
                    text: mistake.originalQuestion.normalisingSingleDollarMath(),
                    config: .previewConfig
                )
                .fixedSize(horizontal: false, vertical: true)

                if !mistake.questionImages.isEmpty {
                    MistakeImageStrip(images: mistake.questionImages)
                }
            }
            .listRowBackground(bar(.blue))
        }

        // Error Reason Section
        // 错因段:MarkdownView + 错因图(若存在)
        // Error reason section: MarkdownView + reason images (if any).
        if !mistake.errorReason.isEmpty {
            Section(header: Text("Error Reason".localized())) {
                MarkdownView(
                    text: mistake.errorReason.normalisingSingleDollarMath(),
                    config: .previewConfig
                )
                .fixedSize(horizontal: false, vertical: true)

                if !mistake.reasonImages.isEmpty {
                    MistakeImageStrip(images: mistake.reasonImages)
                }
            }
            .listRowBackground(bar(.orange))
        }

        // Wrong Solution Section
        // 错解段:红 ✗ 图标作为 header 装饰
        // Wrong-solution section: red ✗ icon in the header.
        if !mistake.wrongSolution.isEmpty {
            Section {
                MarkdownView(
                    text: mistake.wrongSolution.normalisingSingleDollarMath(),
                    config: .previewConfig
                )
                .fixedSize(horizontal: false, vertical: true)
                .listRowBackground(bar(.red))

                if !mistake.wrongSolutionImages.isEmpty {
                    MistakeImageStrip(images: mistake.wrongSolutionImages)
                }
            }
            header: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Wrong Solution".localized())
                }
            }
        }

        // Correct Solution Section
        // 正解段:绿 ✓ 图标作为 header 装饰
        // Correct-solution section: green ✓ icon in the header.
        if !mistake.correctSolution.isEmpty {
            Section {
                MarkdownView(
                    text: mistake.correctSolution.normalisingSingleDollarMath(),
                    config: .previewConfig
                )
                .fixedSize(horizontal: false, vertical: true)
                .listRowBackground(bar(.green))

                if !mistake.correctSolutionImages.isEmpty {
                    MistakeImageStrip(images: mistake.correctSolutionImages)
                }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Correct Solution".localized())
                }
            }
        }
    }
}

/// 错题图横滑条(共享给 4 段内容)
/// Horizontal image strip used by all 4 mistake content sections.
struct MistakeImageStrip: View {
    let images: [Data]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images.indices, id: \.self) { index in
                    ThumbnailImageView(data: images[index])
                        .frame(width: 150, height: 150)
                        .clipped()
                        .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview / 独立预览入口

#Preview("Content Sections") {
    let m = MistakeNote(
        title: "二次函数顶点公式",
        subject: "Mathematics",
        originalQuestion: "已知 \\(f(x) = x^2 - 4x + 3\\),求顶点坐标。",
        source: "数学课本",
        date: Date(),
        errorReason: "忘记配方。",
        wrongSolution: "x = -b/2a = -(-4)/(2·1) = **2**  ←  算错符号",
        correctSolution: "顶点坐标: \\((2, -1)\\)。\n\n- 先配方: \\(x^2 - 4x + 3 = (x-2)^2 - 1\\)\n- 所以顶点为 (2, -1)"
    )
    List {
        MistakeSetContentSection(mistake: m)
    }
    .listStyle(.insetGrouped)
}
