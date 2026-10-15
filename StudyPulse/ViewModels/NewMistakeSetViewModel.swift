//
//  NewMistakeSetViewModel.swift
//  StudyPulse
//
//  Created by Antigravity on 2026/7/12.
//
//  新增错题 ViewModel。负责"题面/错因/错误解法/正确解法"四区表单、
//  图片 / OCR / 手写 sheet,以及保存 + SRS 初始化。
//  New-mistake VM. Four-section form (question/reason/wrong/correct),
//  image/OCR/handwriting sheets, save + SRS init.
//

import Foundation
import SwiftUI
import UIKit
import os
import AVFoundation

@MainActor
@Observable
final class NewMistakeSetViewModel {
    // MARK: - 依赖项 / Dependencies
    private let container: RepositoryContainer

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
    var imagePickerRoute: ImagePickerRoute?
    var showingHandwritingSheet = false
    var isProcessingOCR = false
    var showingOCRAlert = false
    var ocrErrorMessage = ""
    private(set) var aiPhotoRecognitionState: AIPhotoRecognitionState = .idle
    var showingAIPhotoRecognitionError = false
    var aiPhotoRecognitionErrorMessage = ""
    var showingCameraAccessError = false
    var cameraAccessErrorMessage = ""
    /// 新建错题是否直接加入复习队列 / Join the review queue immediately?
    var reviewEnabled = true

    private var aiRecognitionTask: Task<Void, Never>?
    private var lastAIImageData: Data?

    enum AIPhotoRecognitionState: Equatable {
        case idle, loading, failed, succeeded
    }

    enum ImagePickerRoute: String, Identifiable {
        case library, camera, aiLibrary, aiCamera
        var id: String { rawValue }
    }

    // MARK: - 初始化 / Initialization
    /// 默认选中第一个可用科目 / Pre-selects the first available subject.
    init(container: RepositoryContainer) {
        self.container = container
        if let first = availableSubjects.first {
            selectedSubject = first
        }
    }

    /// 从外部预填 subject + title(供 Siri / 快捷指令等入口)
    /// Pre-fills subject & title from an external entry (Siri / Shortcuts, etc.).
    func presetValues(subject: String, title: String) {
        self.selectedSubject = subject
        self.editedTitle = title
    }

    /// 用示例错题覆盖表单(模板/示例库使用)
    /// Overwrite the form with a sample mistake (for templates / sample library).
    func seedSampleMistake(_ sample: SampleMistake) {
        self.editedTitle = sample.title
        self.selectedSubject = sample.subject
        self.editedOriginalQuestion = sample.originalQuestion
        self.editedSource = sample.source
        self.editedErrorReason = sample.errorReason
        self.editedWrongSolution = sample.wrongSolution
        self.editedCorrectSolution = sample.correctSolution
        self.editedDate = sample.date
        self.selectedSection = sample.selectedSection
    }

    // MARK: - 计算属性 / Computed properties
    /// 启用的科目名列表 / Enabled subject names.
    var availableSubjects: [String] {
        container.subjectRepo.subjects.filter { $0.enabled }.map { $0.name }
    }

    /// 是否禁用"保存"按钮 / Whether the save button is disabled.
    var isSaveDisabled: Bool {
        editedTitle.isEmpty || editedOriginalQuestion.isEmpty
    }

    var isAIPhotoRecognitionEnabled: Bool {
        let config = container.envManager.llmConfig
        return config.isConfigured && config.multimodalEnabled
    }

    /// 当前选中分区的文字绑定(路由到对应字段)
    /// Text binding for the current section (routed to the matching field).
    var currentSectionTextBinding: Binding<String> {
        textBinding(for: selectedSection)
    }

    /// Binding captures a concrete section. An outgoing editor can therefore
    /// never write its delayed UIKit callback into the newly selected section.
    func textBinding(for section: EditSection) -> Binding<String> {
        Binding(
            get: {
                switch section {
                case .question: return self.editedOriginalQuestion
                case .reason: return self.editedErrorReason
                case .wrong: return self.editedWrongSolution
                case .correct: return self.editedCorrectSolution
                }
            },
            set: { newValue in
                switch section {
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
    /// 内部 JPEG 0.8 编码,与原 saveMistake 路径一致,无质量损失。
    /// Append an image to the current section (PHPicker / camera give UIImage).
    /// Encodes JPEG at 0.8 internally, matching the original saveMistake path — no quality loss.
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

    func presentImagePicker(_ route: ImagePickerRoute) {
        guard route == .camera || route == .aiCamera else {
            imagePickerRoute = route
            return
        }

        #if targetEnvironment(simulator)
        imagePickerRoute = route == .aiCamera ? .aiLibrary : .library
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            imagePickerRoute = route
        case .notDetermined:
            Task { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard let self else { return }
                if granted {
                    self.imagePickerRoute = route
                } else {
                    self.showCameraAccessDenied()
                }
            }
        case .denied, .restricted:
            showCameraAccessDenied()
        @unknown default:
            showCameraAccessDenied()
        }
        #endif
    }

    private func showCameraAccessDenied() {
        cameraAccessErrorMessage = "Camera access is unavailable. Enable it in Settings or choose a photo from the library.".localized()
        showingCameraAccessError = true
    }

    /// AI only pre-fills the editable form. It never persists a mistake by itself.
    func recognizeMistakePhoto(_ image: UIImage) {
        guard isAIPhotoRecognitionEnabled, let data = image.jpegData(compressionQuality: 0.85) else { return }
        questionImagesData.append(data)
        lastAIImageData = data
        aiRecognitionTask?.cancel()
        aiPhotoRecognitionState = .loading
        showingAIPhotoRecognitionError = false
        runAIRecognition(with: data)
    }

    func retryAIPhotoRecognition() {
        guard let data = lastAIImageData, isAIPhotoRecognitionEnabled else { return }
        aiRecognitionTask?.cancel()
        aiPhotoRecognitionState = .loading
        showingAIPhotoRecognitionError = false
        runAIRecognition(with: data)
    }

    func cancelAIPhotoRecognition() {
        aiRecognitionTask?.cancel()
        aiRecognitionTask = nil
        aiPhotoRecognitionState = .idle
    }

    private func runAIRecognition(with data: Data) {
        let config = container.envManager.llmConfig
        aiRecognitionTask = Task { [weak self] in
            do {
                let result = try await MistakeImageRecognitionLLM.analyze(imageData: data, config: config)
                guard !Task.isCancelled else { return }
                self?.editedOriginalQuestion = result.question
                self?.editedErrorReason = result.errorReason
                self?.editedWrongSolution = result.wrongSolution
                self?.editedCorrectSolution = result.correctSolution
                self?.selectedSection = .question
                self?.aiPhotoRecognitionState = .succeeded
                Log.llm.info("Mistake image recognition applied question=\(result.question.count) reason=\(result.errorReason.count) wrong=\(result.wrongSolution.count) correct=\(result.correctSolution.count)")
            } catch is CancellationError {
                self?.aiPhotoRecognitionState = .idle
            } catch {
                guard !Task.isCancelled else { return }
                self?.aiPhotoRecognitionState = .failed
                self?.aiPhotoRecognitionErrorMessage = error.localizedDescription
                self?.showingAIPhotoRecognitionError = true
            }
        }
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
        let destinationText = textBinding(for: selectedSection)
        isProcessingOCR = true

        Task {
            do {
                // OCR 需要较高分辨率,单张全解(可接受)
                // OCR needs higher resolution; decode one image fully (acceptable).
                let recognizedText = try await Task.detached(priority: .userInitiated) {
                    try await OCRManager.recognizeText(from: lastImageData)
                }.value
                if !recognizedText.isEmpty {
                    let currentText = destinationText.wrappedValue
                    if !currentText.isEmpty {
                        // 已有内容 → 空行分隔追加 / Append with blank-line sep.
                        destinationText.wrappedValue = currentText + "\n\n" + recognizedText
                    } else {
                        // 空白 → 直接填充 / Fill directly when empty.
                        destinationText.wrappedValue = recognizedText
                    }
                }
            } catch {
                ocrErrorMessage = error.localizedDescription
                showingOCRAlert = true
            }
            isProcessingOCR = false
        }
    }

    /// 把当前表单保存为新错题:可选初始化 SRS 状态 + 通知重排
    /// Persist the form as a new mistake: optionally init SRS + reschedule.
    func saveMistake() {
        let newMistake = MistakeNote(
            title: editedTitle.isEmpty ? "Untitled".localized() : editedTitle,
            subject: selectedSubject,
            originalQuestion: editedOriginalQuestion,
            source: editedSource,
            date: editedDate,
            errorReason: editedErrorReason,
            wrongSolution: editedWrongSolution,
            correctSolution: editedCorrectSolution,
            // 数据已在 add 时编码,直接写回
            // Data was encoded at add time; write straight through.
            questionImages: questionImagesData,
            reasonImages: reasonImagesData,
            wrongSolutionImages: wrongSolutionImagesData,
            correctSolutionImages: correctSolutionImagesData,
            // 启用复习 → 用 .initial() 初始化 SRS;否则不进入复习队列
            // Review enabled → init SRS with .initial(); else skip the queue.
            reviewState: reviewEnabled ? .initial() : nil,
            // 难度裁剪到合法范围 / Clamp difficulty to legal range.
            difficulty: max(0, min(DifficultyPicker.maxStars, editedDifficulty)),
            tags: editedTags
        )
        container.addMistake(newMistake)
        Haptics.success()

        // 重排复习通知 / Reschedule review notifications.
        if reviewEnabled {
            SRSReviewNotifications.shared.rescheduleAll(mistakes: container.mistakeRepo.mistakeSets)
        }
    }
}
