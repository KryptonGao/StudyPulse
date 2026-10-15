//
//  AudioPlaybackView.swift
//  StudyPulse
//
//  错题附带的语音备忘录播放控件。
//  Voice-memo playback control for a mistake's attached audio.
//

import SwiftUI

/// 错题附带的语音备忘录播放控件(播放/暂停 + 进度条 + 可选删除)。
/// Voice-memo playback control attached to a mistake
/// (play/pause + progress bar + optional delete).
struct AudioPlaybackView: View {
    /// 音频文件名(由 `AudioStorage` 管理)
    /// Audio file name (managed by `AudioStorage`).
    let audioFileName: String
    /// 删除回调(为 nil 时不显示删除按钮)
    /// Delete callback (when nil, the delete button is hidden).
    let onDelete: (() -> Void)?

    /// 复用 `VoiceMemoManager` 处理播放状态
    /// Reuses `VoiceMemoManager` to drive the playback state.
    @State private var manager = VoiceMemoManager()

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if manager.isPlaying {
                    manager.pauseAudio()
                } else {
                    manager.playAudio(filename: audioFileName)
                }
            } label: {
                Image(systemName: manager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(manager.isPlaying ? "a11y.pause".localized() : "a11y.play".localized())
            .tint(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                // duration 还没拿到时,显示 0% 进度
                // Before duration is known, render a 0% progress bar.
                ProgressView(value: manager.duration > 0 ? manager.currentTime / manager.duration : 0)
                    .progressViewStyle(.linear)

                HStack {
                    Text(timeString(from: manager.currentTime))
                    Spacer()
                    Text(timeString(from: manager.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
            }

            if let onDelete = onDelete {
                Button(role: .destructive) {
                    manager.stopAudio()
                    AudioStorage.delete(filename: audioFileName)
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .accessibilityLabel("Delete".localized())
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .onAppear {
            manager.loadAudio(filename: audioFileName)
        }
        .onDisappear {
            // 离开时务必停止播放,避免后台仍在占用音频会话
            // Always stop on disappear to release the audio session.
            manager.stopAudio()
        }
    }

    /// 把 TimeInterval 格式化为 "mm:ss"
    /// Format a TimeInterval as "mm:ss".
    private func timeString(from time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
