//
//  MistakeDetailEditViewModel.swift
//  StudyPulse
//
//  Created by Antigravity on 2026/7/12.
//
//  错题详情编辑页 ViewModel。加载 `MistakeNote` 到表单状态,
//  接管图片 / OCR / 录音 / AI 解析 sheet,变更写回 Repository。
//  Mistake-detail edit page VM. Loads a `MistakeNote` into form state,
//  owns image/OCR/voice/AI sheets, writes changes back to Repository.
//

import Foundation
import SwiftUI
import UIKit

@MainActor
@Observable
final class MistakeDetailEditViewModel {
    // MARK: - 依赖项 / Dependencies
    private let container: RepositoryContainer
    /// 正在编辑的错题(只读引用,改动先存到本地表单)
    /// The mistake being edited (read-only ref; edits live in local form).
    let mistakeSet: MistakeNote

    // MARK: - 表单状态 / Form state
    var editedTitle = ""
    var selectedSubject = ""
    var editedOriginalQuestion = ""
    var editedSource = ""
    var editedErrorReason = ""
    var editedWrongSolution = ""
    var editedCorrectSolution = ""
    var editedDate = Date()
    var editedDifficulty = 0
    var editedTags: [String] = []
    var audioFileName: String?

    /// 当前正在编辑的分区 / The section currently being edited.
    var selectedSection: EditSection = .question

    // MARK: - 图片状态 / Image state
    // 持有 Data 而非 UIImage,避免主线程同步解码大图。
    // Hold `Data` instead of `UIImage` to avoid synchronous full-image decode on the main thread.
    var questionImagesData: [Data] = []
    var reasonImagesData: [Data] = []
    var wrongSolutionImagesData: [Data] = []
    var correctSolutionImagesData: [Data] = []

    // MARK: - OCR & 弹窗状态 / OCR & sheet state
    var showingImagePicker = false
    var showingPhotoCapture = false
    var showingHandwritingSheet = false
    var showingAudioRecordingSheet = false
    var isProcessingOCR = false
    var showingOCRAlert = false
    var ocrErrorMessage = ""
    var reviewEnabled = false
    var showingAIAnalysis = false

    // MARK: - 初始化 / Initialization
    init(container: RepositoryContainer, mistakeSet: MistakeNote) {
        self.container = container
        self.mistakeSet = mistakeSet
        initializeData()
    }

    /// 把 `mistakeSet` 的字段拷贝到本地表单
    /// Copy `mistakeSet` fields into local form state.
    private func initializeData() {
        editedTitle = mistakeSet.title
        selectedSubject = mistakeSet.subject
        editedOriginalQuestion = mistakeSet.originalQuestion
        editedSource = mistakeSet.source
        editedErrorReason = mistakeSet.errorReason
        editedWrongSolution = mistakeSet.wrongSolution
        editedCorrectSolution = mistakeSet.correctSolution
        editedDate = mistakeSet.date
        editedDifficulty = mistakeSet.difficulty
        editedTags = mistakeSet.tags
        audioFileName = mistakeSet.audioFileName

        // 直接持有 Data;解码延迟到 CachedAsyncImage 的后台 Task
        // Hold `Data` directly; decode is deferred to CachedAsyncImage's background task.
        questionImagesData = mistakeSet.questionImages
        reasonImagesData = mistakeSet.reasonImages
        wrongSolutionImagesData = mistakeSet.wrongSolutionImages
        correctSolutionImagesData = mistakeSet.correctSolutionImages

        reviewEnabled = mistakeSet.isInReviewQueue
    }

    // MARK: - 计算属性 / Computed properties
    /// 启用的科目名列表(picker 用) / Enabled subject names (for picker).
    var availableSubjects: [String] {
        container.subjectRepo.subjects.filter { $0.enabled }.map { $0.name }
    }

    /// 当前选中分区的文字绑定(路由到对应字段)
    /// Text binding for the current section (routed to the matching field).
    var currentSectionTextBinding: Binding<String> {
        Binding(
            get: {
                switch self.selectedSection {
                case .question: return self.editedOriginalQuestion
                case .reason: return self.editedErrorReason
                case .wrong: return self.editedWrongSolution
                case .correct: return self.editedCorrectSolution
                }
            },
            set: { newValue in
                switch self.selectedSection {
                case .question: self.editedOriginalQuestion = newValue
                case .reason: self.editedErrorReason = newValue
                case .wrong: self.editedWrongSolution = newValue
                case .correct: self.editedCorrectSolution = newValue
                }
            }
        )
    }

    /// 当前选中分区的图片数组绑定
    /// Image-array binding for the current section.
    var currentSectionImagesBinding: Binding<[Data]> {
        Binding(
            get: {
                switch self.selectedSection {
                case .question: return self.questionImagesData
                case .reason: return self.reasonImagesData
                case .wrong: return self.wrongSolutionImagesData
                case .correct: return self.correctSolutionImagesData
                }
            },
            set: { newValue in
                switch self.selectedSection {
                case .question: self.questionImagesData = newValue
                case .reason: self.reasonImagesData = newValue
                case .wrong: self.wrongSolutionImagesData = newValue
                case .correct: self.correctSolutionImagesData = newValue
                }
            }
        )
    }

    // MARK: - 操作 / Actions
    /// 把图片追加到当前选中分区(PHPicker / camera 回调天然给 UIImage)。
    /// 内部 JPEG 0.8 编码,与原 saveChanges 路径一致,无质量损失。
    /// Append an image to the current section (PHPicker / camera give UIImage).
    /// Encodes JPEG at 0.8 internally, matching the original saveChanges path — no quality loss.
    func addImageToCurrentSection(_ image: UIImage) {
        if let data = image.jpegData(compressionQuality: 0.8) {
            appendImageData(data)
        }
    }

    /// 直接把 Data 追加到当前选中分区(handwriting PNG 等路径)。
    /// Append raw `Data` to the current section (e.g. handwriting PNG).
    func addImageDataToCurrentSection(_ data: Data) {
        appendImageData(data)
    }

    private func appendImageData(_ data: Data) {
        switch selectedSection {
        case .question: questionImagesData.append(data)
        case .reason:   reasonImagesData.append(data)
        case .wrong:    wrongSolutionImagesData.append(data)
        case .correct:  correctSolutionImagesData.append(data)
        }
    }

    /// 触发 OCR:取当前分区的最后一张图片 Data,在后台线程解码并识别文字,
    /// 追加到该分区的文字字段。
    /// Trigger OCR: take the last image `Data`, decode + recognize on a
    /// background task, and append the recognized text to the section.
    func triggerOCR() {
        let currentImages = currentSectionImagesBinding.wrappedValue
        guard let lastImageData = currentImages.last else { return }
        isProcessingOCR = true

        Task {
            do {
                // OCR 需要较高分辨率,单张全解(可接受)
                // OCR needs higher resolution; decode one image fully (acceptable).
                let recognizedText = try await Task.detached(priority: .userInitiated) {
                    try await OCRManager.recognizeText(from: lastImageData)
                }.value
                if !recognizedText.isEmpty {
                    let currentText = currentSectionTextBinding.wrappedValue
                    if !currentText.isEmpty {
                        // 已有内容 → 空行分隔追加 / Append with blank-line sep.
                        currentSectionTextBinding.wrappedValue = currentText + "\n\n" + recognizedText
                    } else {
                        // 空白 → 直接填充 / Fill directly when empty.
                        currentSectionTextBinding.wrappedValue = recognizedText
                    }
                }
            } catch {
                ocrErrorMessage = error.localizedDescription
                showingOCRAlert = true
            }
            isProcessingOCR = false
        }
    }

    /// 删除当前关联的录音 / Delete the attached voice memo.
    func deleteVoiceMemo() {
        if let filename = audioFileName {
            AudioStorage.delete(filename: filename)
            audioFileName = nil
        }
    }

    /// 把当前表单写回 Repository:SRS 同步 + 通知重排
    /// Write the form back: sync SRS state + reschedule notifications.
    func saveChanges() {
        var updatedMistake = mistakeSet
        updatedMistake.title = editedTitle
        updatedMistake.subject = selectedSubject
        updatedMistake.originalQuestion = editedOriginalQuestion
        updatedMistake.source = editedSource
        updatedMistake.errorReason = editedErrorReason
        updatedMistake.wrongSolution = editedWrongSolution
        updatedMistake.correctSolution = editedCorrectSolution
        updatedMistake.date = editedDate
        // 难度裁剪到合法范围 / Clamp difficulty to legal range.
        updatedMistake.difficulty = max(0, min(DifficultyPicker.maxStars, editedDifficulty))
        updatedMistake.tags = editedTags
        updatedMistake.audioFileName = audioFileName

        // 数据已在 add 时编码,直接写回
        // Data was encoded at add time; write straight through.
        updatedMistake.questionImages = questionImagesData
        updatedMistake.reasonImages = reasonImagesData
        updatedMistake.wrongSolutionImages = wrongSolutionImagesData
        updatedMistake.correctSolutionImages = correctSolutionImagesData

        // 同步 SRS 状态 / Sync SRS state.
        if reviewEnabled && !updatedMistake.isInReviewQueue {
            // 首次进入复习队列 → 用 initial() 初始化 / Initialize with .initial().
            updatedMistake.reviewState = .initial()
        } else if !reviewEnabled && updatedMistake.isInReviewQueue {
            if var state = updatedMistake.reviewState {
                // 退出复习队列 → 把下次复习推到"永远不会"
                // Push next review to "never".
                state.nextReviewDate = Date.distantFuture
                updatedMistake.reviewState = state
            }
        }

        container.mistakeRepo.update(updatedMistake)
        Haptics.success()

        // 重排 / 取消通知 / Reschedule or cancel the notification.
        if reviewEnabled {
            SRSReviewNotifications.shared.rescheduleAll(mistakes: container.mistakeRepo.mistakeSets)
        } else {
            SRSReviewNotifications.shared.cancel(for: updatedMistake.id)
        }
    }
}
