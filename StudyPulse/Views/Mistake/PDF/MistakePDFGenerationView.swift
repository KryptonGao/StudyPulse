//
//  MistakePDFGenerationView.swift
//  StudyPulse
//
//  错题 PDF 生成进度 sheet:
//  - ProgressView(value: 0...1) 显示当前进度
//  - 完成后回调 onCompleted(data) 触发 fileExporter
//  - 失败时回调 onError(message) 让父视图弹错
//  - 整个生成过程在 MainActor 串行执行(ImageRenderer 必须在主线程)
//
//  Mistake PDF generation progress sheet:
//  - ProgressView(value: 0...1) drives the current progress
//  - On success: onCompleted(data) triggers a fileExporter
//  - On failure: onError(message) lets the parent surface the error
//  - Runs serially on the MainActor (ImageRenderer must be on main)
//

import SwiftUI

/// 错题 PDF 生成进度页:snapshot → data → 父视图保存/分享。
/// Mistake PDF generation progress page: snapshot → data → parent saves / shares.
struct MistakePDFGenerationView: View {
    /// 已渲染好的"待导出"快照(由父视图提供)
    /// Pre-rendered export snapshot (provided by the parent).
    let snapshot: MistakePDFSnapshot
    /// 成功回调(传回 PDF 的 Data)
    /// Success callback (returns the PDF data).
    let onCompleted: (Data) -> Void
    /// 错误回调(传回错误信息)
    /// Error callback (returns the error message).
    let onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    /// 当前进度 0...1
    /// Current progress 0...1.
    @State private var progress: Double = 0
    /// 是否正在生成
    /// Whether generation is in progress.
    @State private var isGenerating: Bool = true
    /// 错误信息
    /// Error message.
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                if let errorMessage = errorMessage {
                    errorState(message: errorMessage)
                } else if isGenerating {
                    generatingState
                } else {
                    completedState
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Generating PDF".localized())
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isGenerating)
        }
        .task {
            await generate()
        }
    }

    // MARK: - States

    private var generatingState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .scaledFont(size: 60)
                .foregroundColor(.orange)

            Text("Generating PDF...".localized())
                .font(.headline)

            VStack(spacing: 8) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 320)

                Text(String(format: "%.0f%%", progress * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Text(String(format: "%d mistakes".localized(), snapshot.mistakeCount))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var completedState: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .scaledFont(size: 60)
                .foregroundColor(.green)
            Text("PDF Generated".localized())
                .font(.headline)
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .scaledFont(size: 60)
                .foregroundColor(.red)
            Text("Generation Failed".localized())
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Close".localized()) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Generation

    @MainActor
    private func generate() async {
        isGenerating = true
        progress = 0
        errorMessage = nil

        // 让 UI 先更新一帧再开始重活，避免被同步渲染阻塞
        await Task.yield()

        // MistakePDFRenderer.makePDF 自身在 MainActor 上同步执行；
        // progress 回调也在主线程触发，会更新 SwiftUI @State。
        let data = MistakePDFRenderer.makePDF(from: snapshot) { p in
            progress = p
        }

        isGenerating = false

        if let pdfData = data {
            // 短暂显示完成状态再回调
            try? await Task.sleep(nanoseconds: 300_000_000)
            onCompleted(pdfData)
            dismiss()
        } else {
            errorMessage = "PDF generation returned no data.".localized()
            Log.record(.error, category: "Export", message: "错题 PDF 生成返回空 / Mistake PDF generation returned nil: count=\(snapshot.mistakeCount)")
        }
    }
}
