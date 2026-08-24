//
//  VoiceMemoManager.swift
//  StudyPulse
//
//  Created for Voice Memos feature.
//

import Foundation
import AVFoundation
import os

/// Manages recording and playback of voice memos.
/// 管理语音备忘录的录音与播放。
@MainActor
@Observable
final class VoiceMemoManager: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {

    private let logger = Logger(subsystem: "com.chenkai.gao.studypulse", category: "VoiceMemoManager")

    var isRecording = false
    var isPlaying = false
    var isPaused = false

    var currentTime: TimeInterval = 0.0
    var duration: TimeInterval = 0.0

    var hasPermission = false

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    var currentFileName: String?

    override init() {
        super.init()
        // 启动时立即检查麦克风权限 / Check mic permission on launch
        checkPermission()
    }

    /// 检查 / 请求麦克风权限。
    /// Check or request microphone permission.
    func checkPermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            self.hasPermission = true
        case .denied:
            self.hasPermission = false
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] allowed in
                Task { @MainActor in
                    self?.hasPermission = allowed
                }
            }
        @unknown default:
            self.hasPermission = false
        }
    }
    
    // MARK: - Recording
    // MARK: - 录音 / Recording

    /// 开始一次新的录音会话（需要麦克风权限）。
    /// Start a new recording session (mic permission required).
    func startRecording() {
        guard hasPermission else {
            logger.error("No permission to record audio")
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            // playAndRecord + 默认扬声器 + 蓝牙：同时允许录音与外放
            // playAndRecord + defaultToSpeaker + bluetooth: record + play out loud simultaneously
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let filename = AudioStorage.generateFileName()
            let url = AudioStorage.url(for: filename)

            // AAC / 44.1kHz / 单声道 / 高质量 → 适合语音备忘录
            // AAC / 44.1 kHz / mono / high quality — ideal for voice memos.
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            
            self.currentFileName = filename
            self.isRecording = true
            self.isPaused = false
            self.currentTime = 0.0
            
            startTimer()
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    /// 暂停当前录音（不释放 recorder）。
    /// Pause the current recording without releasing the recorder.
    func pauseRecording() {
        guard isRecording else { return }
        audioRecorder?.pause()
        isPaused = true
        stopTimer()
    }

    /// 从暂停中恢复录音。
    /// Resume recording from a paused state.
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        audioRecorder?.record()
        isPaused = false
        startTimer()
    }

    /// 停止录音（保留录音文件）。
    /// Stop recording (keeps the audio file).
    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        stopTimer()

        // 关闭音频会话，避免持续占用硬件
        // Tear down the audio session to release hardware.
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false)

        // 录音文件敏感:锁屏后不可读(best-effort 加固,失败不影响保存结果)
        // Voice memos are sensitive: complete protection after unlock only.
        if let filename = currentFileName {
            let url = AudioStorage.url(for: filename)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path
            )
        }
    }

    /// 取消录音并删除已生成的文件。
    /// Cancel recording and delete the file created so far.
    func cancelRecording() {
        stopRecording()
        if let filename = currentFileName {
            AudioStorage.delete(filename: filename)
            currentFileName = nil
        }
    }

    // MARK: - Playback
    // MARK: - 播放 / Playback

    /// 加载指定文件名的音频到播放器（不自动开始播放）。
    /// Load an audio file by filename into the player (does not start playback).
    func loadAudio(filename: String) {
        let url = AudioStorage.url(for: filename)
        do {
            // 播放模式（不需要录音权限）
            // Playback mode (no mic permission required).
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            self.duration = audioPlayer?.duration ?? 0.0
            self.currentTime = 0.0
            self.currentFileName = filename
        } catch {
            logger.error("Failed to load audio for playback: \(error.localizedDescription)")
        }
    }

    /// 播放指定文件名的音频（如已加载则直接播放）。
    /// Play the audio with the given filename (loads it first if needed).
    func playAudio(filename: String) {
        if currentFileName != filename || audioPlayer == nil {
            loadAudio(filename: filename)
        }

        audioPlayer?.play()
        isPlaying = true
        startTimer()
    }

    /// 暂停播放。
    /// Pause playback.
    func pauseAudio() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }

    /// 停止播放并把进度归零。
    /// Stop playback and reset the playhead.
    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        self.currentTime = 0.0
        stopTimer()
    }

    /// 跳转到指定时间（秒）。
    /// Seek to a specific time (seconds).
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        self.currentTime = time
    }

    // MARK: - Delegates
    // MARK: - 委托回调 / Delegates
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.isRecording = false
            self.stopTimer()
        }
    }
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0.0
            self.stopTimer()
        }
    }
    
    // MARK: - Timer
    // MARK: - 定时器 / Timer

    /// 启动 0.1s 定时器，每 100ms 同步一次 recorder/player 的 currentTime。
    /// Starts a 0.1s timer that mirrors recorder/player currentTime every 100 ms.
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isRecording {
                    self.currentTime = self.audioRecorder?.currentTime ?? 0.0
                } else if self.isPlaying {
                    self.currentTime = self.audioPlayer?.currentTime ?? 0.0
                }
            }
        }
    }

    /// 停掉定时器并释放引用。
    /// Stops the timer and releases the reference.
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
