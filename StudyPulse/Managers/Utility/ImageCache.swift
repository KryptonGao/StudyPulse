//
//  ImageCache.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/6/5.
//

import UIKit
import CryptoKit

// MARK: - Image Cache Manager (图片缓存管理器)

/// 轻量级内存图片缓存
/// 使用 NSCache 避免重复解码 Data → UIImage，提升列表滚动性能
/// 最大缓存 50 张图片，支持缩略图生成
nonisolated final class ImageCache: @unchecked Sendable {
    @MainActor static let shared = ImageCache()
    
    /// NSCache 内存缓存（自动 LRU 淘汰）
    private let cache = NSCache<NSString, UIImage>()
    /// Keys are tracked separately because NSCache does not expose its count.
    /// The set is reconciled with NSCache whenever `entryCount` is read.
    private var keys: Set<String> = []
    /// 线程安全锁
    private let lock = NSLock()
    
    init(countLimit: Int = 50) {
        // countLimit 是 NSCache 的近似 LRU 上限;50 张 ≈ 50MB 内存预算
        // countLimit is the approximate LRU cap of NSCache; 50 images ≈ 50MB budget.
        cache.countLimit = countLimit
    }
    
    /// 根据图片 Data 生成缓存 Key（使用哈希值）
    static func dataCacheKey(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "d:\(hex)"
    }

    private func makeKey(_ data: Data) -> NSString {
        NSString(string: Self.dataCacheKey(data))
    }

    /// 按文件名缓存的 Key(头像 / 成绩图片,文件名稳定)
    private func makeFilenameKey(_ filename: String) -> NSString {
        NSString(string: Self.filenameCacheKey(filename))
    }

    static func filenameCacheKey(_ filename: String) -> String {
        "f:\(filename)"
    }

    /// 从 Data 缓存获取
    func getImage(_ data: Data) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        let key = makeKey(data)
        let image = cache.object(forKey: key)
        if image == nil { keys.remove(key as String) }
        return image
    }

    /// 存入 Data 缓存
    func putImage(_ image: UIImage, _ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        let key = makeKey(data)
        cache.setObject(image, forKey: key)
        keys.insert(key as String)
    }

    /// 按文件名获取
    func getImageByFilename(_ filename: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        let key = makeFilenameKey(filename)
        let image = cache.object(forKey: key)
        if image == nil { keys.remove(key as String) }
        return image
    }

    /// 按文件名存入
    func putImageByFilename(_ image: UIImage, _ filename: String) {
        lock.lock()
        defer { lock.unlock() }
        let key = makeFilenameKey(filename)
        cache.setObject(image, forKey: key)
        keys.insert(key as String)
    }

    /// Number of live cached entries. This intentionally does not estimate
    /// decoded UIImage memory usage.
    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        keys = keys.filter { cache.object(forKey: $0 as NSString) != nil }
        return keys.count
    }

    /// 清空内存缓存。
    /// Drops all cached images from the in-memory NSCache.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
        keys.removeAll()
    }
    
    /// 生成缩略图(固定最大尺寸,减少内存占用)。
    /// 用 `CGImageSourceCreateThumbnailAtIndex` 直接生成下采样缩略图,
    /// 避免先把整个原图解码到内存(适合 avatar / 错题图 等大图场景)。
    /// - Parameters:
    ///   - data: 原始图片数据
    ///   - maxDimension: 最大边长(默认 300px)
    /// - Returns: 下采样后的缩略图
    /// Generate a downsampled thumbnail with a fixed max dimension to reduce memory.
    /// Uses `CGImageSourceCreateThumbnailAtIndex` to downsample at decode time,
    /// avoiding a full-resolution decode of the original (suitable for avatars / mistake images).
    /// - Parameters:
    ///   - data: Original image data.
    ///   - maxDimension: Max edge length (default 300px).
    /// - Returns: The downsampled thumbnail, or nil if decode fails.
    static func thumbnail(from data: Data, maxDimension: CGFloat = 300) -> UIImage? {
        // Keep this helper usable from background decoding tasks. Accessing
        // UIScreen.main is main-actor isolated under Swift 6; a 3x upper
        // bound is a safe approximation for all supported iPhone/iPad scales.
        let maxPixels = Int(maxDimension * 3.0)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // 解码失败时回退到 UIImage(data:)
            // Fall back to UIImage(data:) on CGImageSource failure.
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}
