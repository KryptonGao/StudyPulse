//
//  AvatarView.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/6/7.
//

import SwiftUI

// MARK: - 头像显示组件
// MARK: - Avatar Display Component

/// 用户头像:有 data 走图片,否则走首字符 + 哈希色背景。
/// User avatar: renders the image when `avatarData` is provided,
/// otherwise falls back to the user's initial over a stable color
/// (hashed from the username).
struct AvatarView: View {
    let username: String
    let avatarData: Data?
    var size: CGFloat = 80
    /// 是否绘制边框
    /// Whether to draw a border ring.
    var showBorder: Bool = true

    /// 异步解码的缩略图(从 `ImageCache.thumbnail` 取,带下采样)。
    /// Async-decoded thumbnail (from `ImageCache.thumbnail`,with downsampling).
    @State private var avatarImage: UIImage?

    /// 根据用户名生成稳定的颜色
    /// Stable color derived from the username hash.
    private var backgroundColor: Color {
        let colors: [Color] = [
            .blue, .purple, .pink, .red, .orange,
            .yellow, .green, .mint, .teal, .cyan, .indigo
        ]
        let hash = abs(username.hashValue)
        return colors[hash % colors.count]
    }

    /// 提取用户名的首字符(支持中文和英文)
    /// Extracts the first character of the username (supports CJK and Latin).
    private var initial: String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstChar = trimmed.first {
            return String(firstChar).uppercased()
        }
        return "?"
    }

    var body: some View {
        Group {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            backgroundColor.opacity(0.8),
                            backgroundColor
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Text(initial)
                        .font(.system(size: size * 0.45, weight: .bold, design: .rounded)) // fixed-size-ok: geometry-derived
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Group {
                if showBorder {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.8),
                                    Color.white.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                }
            }
        )
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .task(id: avatarData) {
            // 异步解码 + 下采样到屏幕尺寸 2x(避免主线程同步解码大图)。
            // Async decode + downsample to 2x screen pixels (avoids sync main-thread decode of large images).
            guard let data = avatarData else { avatarImage = nil; return }
            let targetSize = size
            avatarImage = await Task.detached(priority: .userInitiated) {
                ImageCache.thumbnail(from: data, maxDimension: targetSize)
            }.value
        }
    }
}

// MARK: - 头像选择器
// MARK: - Avatar Picker

/// 头像编辑页:从相册选 / 拍照 / 移除。
/// Avatar editor screen: choose from library / take photo / remove.
struct AvatarEditView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) var dismiss

    @State private var avatarData: Data?
    @State private var showingImagePicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary

    var body: some View {
        VStack(spacing: 24) {
            // 头像预览
            // Avatar preview
            AvatarView(
                username: container.profileRepo.profile.username,
                avatarData: avatarData,
                size: 140
            )
            .padding(.top, 32)

            Text("Tap below to change your avatar".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Button(action: {
                    imagePickerSourceType = .photoLibrary
                    showingImagePicker = true
                }) {
                    Label("Choose from Library".localized(), systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button(action: {
                        imagePickerSourceType = .camera
                        showingImagePicker = true
                    }) {
                        Label("Take Photo".localized(), systemImage: "camera")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }

                if container.profileRepo.profile.avatarFileName != nil {
                    Button(action: removeAvatar) {
                        Label("Remove Avatar".localized(), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .adaptiveMaxWidth(480)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Change Avatar".localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveAvatar()
                    dismiss()
                }
                .bold()
            }
        }
        .onAppear {
            avatarData = container.profileRepo.loadAvatar()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(sourceType: imagePickerSourceType, image: .constant(nil)) { image in
                if let image = image,
                   let resized = resizeImage(image, targetSize: CGSize(width: 400, height: 400)),
                   let data = resized.jpegData(compressionQuality: 0.8) {
                    avatarData = data
                }
            }
        }
    }

    private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage? {
        // 头像输出统一 400x400,JPEG 0.8(磁盘占位小,质量也够用)
        // Avatars are normalized to 400x400 JPEG q=0.8 (small disk footprint, plenty of quality).
        let size = image.size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let ratio = min(widthRatio, heightRatio)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: rect)
        }
    }

    private func saveAvatar() {
        if let data = avatarData {
            if let filename = container.saveAvatar(data) {
                container.profileRepo.profile.avatarFileName = filename
                container.profileRepo.saveProfile()
            }
        }
    }

    private func removeAvatar() {
        if let filename = container.profileRepo.profile.avatarFileName {
            container.deleteAvatar(filename: filename)
            container.profileRepo.profile.avatarFileName = nil
            container.profileRepo.saveProfile()
            avatarData = nil
        }
    }
}

#Preview {
    AvatarView(
        username: "Student",
        avatarData: nil,
        size: 100
    )
}
