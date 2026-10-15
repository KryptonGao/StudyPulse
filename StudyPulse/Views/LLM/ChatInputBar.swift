import SwiftUI
import PhotosUI
import UIKit

/// Shared chat composer. Multimodal mode adds image attachments and uses a
/// two-row composer while focused; regular text-only chats keep the compact
/// legacy layout.
struct ChatInputBar: View {
    @Binding var text: String
    let placeholder: String
    let isStreaming: Bool
    let canSend: Bool
    let onSend: () -> Void
    var onCancel: (() -> Void)? = nil
    var multimodalEnabled: Bool = false
    @Binding var attachments: [LLMImageAttachment]
    var onSendWithImages: (([LLMImageAttachment]) -> Void)? = nil

    @FocusState private var focused: Bool
    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var selectedPhoto: PhotosPickerItem?

    init(
        text: Binding<String>,
        placeholder: String = "Ask anything...".localized(),
        isStreaming: Bool,
        canSend: Bool,
        onSend: @escaping () -> Void,
        onCancel: (() -> Void)? = nil,
        multimodalEnabled: Bool = false,
        attachments: Binding<[LLMImageAttachment]> = .constant([]),
        onSendWithImages: (([LLMImageAttachment]) -> Void)? = nil
    ) {
        _text = text
        self.placeholder = placeholder
        self.isStreaming = isStreaming
        self.canSend = canSend
        self.onSend = onSend
        self.onCancel = onCancel
        self.multimodalEnabled = multimodalEnabled
        _attachments = attachments
        self.onSendWithImages = onSendWithImages
    }

    var body: some View {
        Group {
            if multimodalEnabled {
                multimodalComposer
            } else {
                textOnlyComposer
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .sheet(isPresented: $showCamera) {
            CameraImagePicker { image in
                append(image: image)
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotos, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run { append(image: image) }
                }
                await MainActor.run { selectedPhoto = nil }
            }
        }
    }

    private var textOnlyComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            inputCapsule
            sendButton
        }
    }

    private var multimodalComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                attachmentStrip
            }
            ZStack(alignment: .bottom) {
                multimodalTextField
                    .padding(.leading, 48)
                    .padding(.trailing, 52)
                    .frame(height: focused ? 96 : 52)
                HStack(spacing: 12) {
                    plusButton
                    Spacer(minLength: 0)
                    sendButton
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(composerBackground)
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(focused ? 0.15 : 0.08), lineWidth: focused ? 1 : 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }

    private var multimodalTextField: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(1...5)
            .focused($focused)
            .padding(.vertical, 8)
            .frame(height: focused ? 96 : 52, alignment: .top)
            .clipped()
    }

    private var inputCapsule: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(1...5)
            .focused($focused)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(composerBackground)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(focused ? 0.15 : 0.08), lineWidth: focused ? 1 : 0.5))
            .onSubmit { submit() }
    }

    private var composerBackground: some View {
        Group {
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24))
            } else {
                RoundedRectangle(cornerRadius: 24).fill(.regularMaterial)
            }
        }
    }

    private var sendButton: some View {
        Group {
            if isStreaming, let onCancel {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .scaledFont(size: 32)
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("a11y.stopGenerating".localized())
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .scaledFont(size: 32)
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                }
                .accessibilityLabel("a11y.send".localized())
                .disabled(!canSend)
            }
        }
    }

    private var plusButton: some View {
        Menu {
            Button {
                showCamera = true
            } label: {
                Label("Camera".localized(), systemImage: "camera")
            }
            Button {
                showPhotos = true
            } label: {
                Label("Photos".localized(), systemImage: "photo")
            }
        } label: {
            Image(systemName: "plus")
                .scaledFont(size: 25, weight: .regular)
                .frame(width: 36, height: 36)
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("Add image".localized())
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    if let image = UIImage(data: attachment.data) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Button {
                                attachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, .black.opacity(0.55))
                            }
                            .accessibilityLabel("a11y.removeAttachment".localized())
                            .offset(x: 5, y: -5)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }

    private func append(image: UIImage) {
        guard attachments.count < 4,
              let data = image.resizedForLLM().jpegData(compressionQuality: 0.7) else { return }
        attachments.append(LLMImageAttachment(data: data))
    }

    private func submit() {
        guard canSend else { return }
        focused = false
        if let onSendWithImages {
            onSendWithImages(attachments)
        } else {
            onSend()
        }
        attachments.removeAll()
    }
}

private extension UIImage {
    func resizedForLLM(maxDimension: CGFloat = 1024) -> UIImage {
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1 else { return self }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onImage(image) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    }
}
