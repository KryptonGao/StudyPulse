//
//  ZoomableImageView.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/6/5.
//
//  可缩放图片查看器。点击图片进入全屏,支持双指缩放与双击缩放/还原。
//  Tappable image viewer. Tapping the image enters fullscreen with pinch
//  zoom and double-tap to zoom / reset.
//

import SwiftUI
import UIKit

/// 缩略图:点按进入全屏缩放器。
/// Thumbnail: tap to enter the fullscreen zoom view.
struct ZoomableImageView: View {
    let image: UIImage
    /// 是否显示全屏缩放器
    /// Whether the fullscreen zoom view is presented.
    @State private var showFullscreen = false

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .onTapGesture {
                showFullscreen = true
            }
            .sheet(isPresented: $showFullscreen) {
                FullscreenZoomableView(image: image)
            }
    }
}

/// 全屏缩放 + 关闭按钮。
/// Fullscreen zoom view with a dismiss button.
private struct FullscreenZoomableView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ZoomableScrollView(image: image)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding(8)
                    }
                    .accessibilityLabel("Close".localized())
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                }
                Spacer()
            }
        }
    }
}

/// UIScrollView 包装,实现 1x–5x 缩放 + 双击缩放到点击处。
/// UIScrollView wrapper that implements 1x–5x zoom + double-tap-to-zoom.
private struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.delegate = context.coordinator
        // 缩放范围 1x – 5x,搭配双击缩放
        // Zoom range 1x – 5x, paired with double-tap-to-zoom.
        scrollView.maximumZoomScale = 5.0
        scrollView.minimumZoomScale = 1.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.contentSize = image.size

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = CGRect(origin: .zero, size: image.size)
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        // 双击手势
        // Double-tap gesture
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        if let imageView = scrollView.subviews.first as? UIImageView {
            imageView.image = image
            imageView.frame = CGRect(origin: .zero, size: image.size)
            scrollView.contentSize = image.size
            updateZoomScale(for: scrollView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func updateZoomScale(for scrollView: UIScrollView) {
        guard let imageView = scrollView.subviews.first as? UIImageView else { return }

        let imageViewSize = imageView.bounds.size
        let scrollViewSize = scrollView.bounds.size

        let widthScale = scrollViewSize.width / imageViewSize.width
        let heightScale = scrollViewSize.height / imageViewSize.height

        let minScale = min(widthScale, heightScale)

        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = 5.0
        scrollView.setZoomScale(minScale, animated: false)
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            scrollView.subviews.first
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView = scrollView.subviews.first as? UIImageView else { return }

            let offsetX = (scrollView.bounds.width > scrollView.contentSize.width)
                ? (scrollView.bounds.width - scrollView.contentSize.width) * 0.5
                : 0.0

            let offsetY = (scrollView.bounds.height > scrollView.contentSize.height)
                ? (scrollView.bounds.height - scrollView.contentSize.height) * 0.5
                : 0.0

            imageView.center = CGPoint(x: scrollView.contentSize.width * 0.5 + offsetX,
                                       y: scrollView.contentSize.height * 0.5 + offsetY)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let touchPoint = gesture.location(in: scrollView)
                let zoomRect = CGRect(
                    x: touchPoint.x - scrollView.bounds.width / 4,
                    y: touchPoint.y - scrollView.bounds.height / 4,
                    width: scrollView.bounds.width / 2,
                    height: scrollView.bounds.height / 2
                )
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }
    }
}

#if DEBUG
#Preview {
    if let image = UIImage(systemName: "photo.fill") {
        ZoomableImageView(image: image)
    }
}
#endif
