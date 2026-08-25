//
//  ImageStorage.swift
//  StudyPulse
//
//  图片文件存储 helper(共享给 GradeRepository / ProfileRepository 头像)。
//  File-system image storage helper shared by GradeRepository (grade images)
//  and ProfileRepository (avatar).
//
//  iOS 26+ target:nonisolated 静态方法 + 路径缓存,避免每次访问都 stat 文件系统。
//

import Foundation
import os

/// 共享的图片文件系统操作。
/// Shared file-system image storage. Thread-safe via internal lock.
nonisolated enum ImageStorage {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _cachedImagesDir: URL?

    /// Documents/images/ 目录(自动创建)。返回 nil 表示沙盒异常(用户数据无法落盘)。
    nonisolated static func imagesDirectory() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = _cachedImagesDir { return cached }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            Log.data.error("ImageStorage 无法解析 Documents 目录 / Failed to resolve Documents directory")
            return nil
        }
        let url = docs.appendingPathComponent("images")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        _cachedImagesDir = url
        return url
    }

    /// 把二进制图片写入 images/<filename>。失败(目录不可用 / 写盘失败)返回 false。
    @discardableResult
    nonisolated static func save(_ data: Data, filename: String) -> Bool {
        guard let dir = imagesDirectory() else {
            Log.data.error("ImageStorage save 跳过(目录不可用) / Skipped save (no dir): \(filename, privacy: .public)")
            return false
        }
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            // 锁屏后不可读(best-effort 加固,失败不影响保存结果)
            // Complete protection after unlock only (best-effort hardening).
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path
            )
            Log.data.debug("ImageStorage save OK / saved: \(filename, privacy: .public) bytes=\(data.count, privacy: .public)")
            return true
        } catch {
            Log.data.error("ImageStorage save failed: \(filename, privacy: .public) \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 同步读取图片数据。目录不可用或文件不存在时返回 nil。
    nonisolated static func load(filename: String) -> Data? {
        guard let dir = imagesDirectory() else { return nil }
        let url = dir.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    /// 异步读取图片数据(后台线程,避免阻塞 UI)。目录不可用时返回 nil。
    nonisolated static func loadAsync(filename: String) async -> Data? {
        guard let dir = imagesDirectory() else { return nil }
        let url = dir.appendingPathComponent(filename)
        return await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
    }

    /// 删除指定文件名的图片。文件不存在也视为成功;目录不可用时静默 no-op。
    nonisolated static func delete(filename: String) {
        guard let dir = imagesDirectory() else { return }
        let url = dir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - DataFileIO(给 App Intent / 后台线程用)
//
// 线程安全的 JSON 文件读取 helper。避免受 @MainActor 限制。
nonisolated enum DataFileIO {
    /// Documents 目录;沙盒异常时返回 nil(调用方需要兜底)。
    static func getDocsDir() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// 从指定 URL 加载并解码 JSON 数据。文件不存在返回 nil,解码失败返回 nil。
    static func load<T: Codable>(url: URL, decoder: JSONDecoder = JSONDecoder()) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.data.debug("DataFileIO 跳过(文件不存在) / File missing: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let result = try decoder.decode(T.self, from: data)
            Log.data.debug("DataFileIO 加载成功 / Loaded: \(url.lastPathComponent, privacy: .public), bytes=\(data.count, privacy: .public)")
            return result
        } catch {
            Log.data.error("DataFileIO 加载失败 / Load failed: \(url.lastPathComponent, privacy: .public), error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
