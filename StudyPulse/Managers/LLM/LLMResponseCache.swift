//
//  LLMResponseCache.swift
//  StudyPulse
//
//  LLM 响应缓存(LRU + TTL)。
//  - key = caller + sha256(effectiveSystem + messages + model + temperature)
//  - 容量 10 条;TTL 10 分钟
//  - 线程安全:Swift actor
//
//  目的:用户切换页面重新进入时(如退出 BodyRadar 卡片再返回),
//  相同 prompt 在 10 分钟窗口内不重复走网络。
//
//  Created for performance optimization (2026-07-18, P1-4).
//

import Foundation
import CryptoKit
import os

/// LLM 响应缓存(LRU + TTL)。
/// LLM response cache (LRU + TTL).
///
/// `LLMClient.complete` / `stream` 在调用网络前先查缓存;命中且未过期则直接返回缓存。
/// key 包含 `caller` 与完整 `messages`(含 system prompt),避免不同 caller 串扰。
/// Before each network call, `LLMClient.complete` / `stream` consults this cache;
/// on a fresh hit, the cached response is returned directly.
/// The key includes `caller` and the full `messages` (including system prompt),
/// preventing cross-caller collisions.
actor LLMResponseCache {
    static let shared = LLMResponseCache()

    private struct Entry {
        let response: String
        let timestamp: Date
    }

    /// 容量上限(条)。
    /// Capacity (number of entries).
    private let capacity: Int
    /// TTL(秒):超过此时间的条目视为过期。
    /// TTL (seconds): entries older than this are treated as expired.
    private let ttl: TimeInterval
    private var store: [String: Entry] = [:]
    /// LRU 顺序:最早访问的 key 在前。
    /// LRU order: least-recently accessed keys first.
    private var lruOrder: [String] = []
    init(capacity: Int = 10, ttl: TimeInterval = 600) {
        self.capacity = capacity
        self.ttl = ttl
    }

    /// Number of fresh entries currently held in memory.
    var entryCount: Int {
        removeExpiredEntries(referenceDate: Date())
        return store.count
    }

    /// 查询缓存。命中且未过期返回响应,否则返回 nil(并顺手清理过期项)。
    /// Look up the cache. Returns the response on a fresh hit,nil otherwise
    /// (expired entries are evicted opportunistically).
    func get(caller: String, prompt: LLMPrompt, config: LLMConfig) -> String? {
        let key = makeKey(caller: caller, prompt: prompt, config: config)
        guard let entry = store[key] else {
            Log.llm.debug("LLMResponseCache miss / caller=\(caller, privacy: .public)")
            return nil
        }
        if Date().timeIntervalSince(entry.timestamp) > ttl {
            // 过期:清除并返回 nil
            store.removeValue(forKey: key)
            lruOrder.removeAll { $0 == key }
            Log.llm.debug("LLMResponseCache expired / caller=\(caller, privacy: .public)")
            return nil
        }
        // 命中:把 key 移到 LRU 末尾(最近使用)
        lruOrder.removeAll { $0 == key }
        lruOrder.append(key)
        Log.llm.debug("LLMResponseCache hit / caller=\(caller, privacy: .public)")
        return entry.response
    }

    /// 写入缓存。超过 capacity 时按 LRU 淘汰最旧条目。
    /// Insert into the cache. Evicts the least-recently-used entry when over capacity.
    func set(caller: String, prompt: LLMPrompt, config: LLMConfig, response: String) {
        let key = makeKey(caller: caller, prompt: prompt, config: config)
        store[key] = Entry(response: response, timestamp: Date())
        lruOrder.removeAll { $0 == key }
        lruOrder.append(key)
        while lruOrder.count > capacity {
            let oldest = lruOrder.removeFirst()
            store.removeValue(forKey: oldest)
        }
    }

    /// 清空所有缓存(Debug 面板「清除缓存」按钮用)。
    /// Clear all cached entries (Debug panel "Clear cache" button).
    func clear() {
        store.removeAll()
        lruOrder.removeAll()
        Log.llm.info("LLMResponseCache cleared")
    }

    private func removeExpiredEntries(referenceDate: Date) {
        let expiredKeys = store.compactMap { key, entry in
            referenceDate.timeIntervalSince(entry.timestamp) > ttl ? key : nil
        }
        guard !expiredKeys.isEmpty else { return }
        let expired = Set(expiredKeys)
        for key in expired { store.removeValue(forKey: key) }
        lruOrder.removeAll { expired.contains($0) }
    }

    /// 计算 key:caller + sha256(effectiveSystem + messages + images + model + temperature)。
    /// 图片内容也必须参与 key，否则不同图片会错误命中同一个识别结果。
    /// Compute the key from effectiveSystem, messages, images, model and temperature.
    /// Image contents must be included or different photos can reuse one result.
    private func makeKey(caller: String, prompt: LLMPrompt, config: LLMConfig) -> String {
        let effectiveSystem = prompt.effectiveSystem(appendix: config.systemPromptAppendix)
        var messageContents = ""
        for m in prompt.messages {
            messageContents += m.role.rawValue + ":" + m.content + "\n"
            for imageDataURL in m.imageDataURLs {
                messageContents += "image:" + imageDataURL + "\n"
            }
        }
        let model = config.model ?? ""
        let temperature = config.temperature
        let blob = "\(effectiveSystem)\n\(messageContents)\nmodel=\(model)\ntemperature=\(temperature)\nmultimodal=\(config.multimodalEnabled)\nthinking=\(config.thinkingEnabled)\nthinkingMode=\(config.thinkingMode.rawValue)\nsensitivity=\(prompt.sensitivity.rawValue)"
        let hash = SHA256.hash(data: Data(blob.utf8))
        let hashHex = hash.map { String(format: "%02x", $0) }.joined()
        return "\(caller):\(hashHex)"
    }
}
