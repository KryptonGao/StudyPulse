//
//  VoiceMemoRecordingSheet.swift
//  StudyPulse
//
//  语音备忘录录制 sheet(录音 / 暂停 / 取消 / 完成)。
//  Voice-memo recording sheet (record / pause / cancel / done).
//

import SwiftUI

/// 语音备忘录录制 sheet(录音 / 暂停 / 取消 / 完成)。
/// 完成后通过 `onSave` 把音频文件名交回 caller。
/// Voice-memo recording sheet (record / pause / cancel / done).
/// On save, hands the audio file name back via `onSave`.
struct VoiceMemoRecordingSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// 录音管理器(负责 AVAudioSession / 文件落盘)
    /// Recording manager (handles AVAudioSession / file write).
    @State private var manager = VoiceMemoManager()

    /// 保存回调(传回录音文件相对路径)
    /// Save callback (returns the relative path of the recorded file).
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // 大号时间码:分:秒.厘秒(0.01s 精度)
                // Large timer: mm:ss.cs (0.01s precision).
                Text(timeString(from: manager.currentTime))
                    .scaledFont(size: 64, weight: .thin, design: .monospaced)
                    .monospacedDigit()
                    .padding(.top, 40)

                if !manager.hasPermission {
                    Text("请在设置中允许麦克风权限。".localized())
                        .foregroundColor(.red)
                        .font(.subheadline)
                }

                HStack(spacing: 40) {
                    if manager.isRecording || manager.isPaused || manager.currentFileName != nil {
                        Button(role: .destructive) {
                            manager.cancelRecording()
                            dismiss()
                        } label: {
                            Image(systemName: "trash.circle.fill")
                                .resizable()
                                .frame(width: 50, height: 50)
                        }
                        .accessibilityLabel("a11y.discardRecording".localized())
                        .tint(.red)
                    }

                    Button {
                        if manager.isRecording {
                            if manager.isPaused {
                                manager.resumeRecording()
                            } else {
                                manager.pauseRecording()
                            }
                        } else if manager.currentFileName == nil {
                            manager.startRecording()
                        }
                    } label: {
                        Image(systemName: manager.isRecording && !manager.isPaused ? "pause.circle.fill" : "record.circle.fill")
                            .resizable()
                            .frame(width: 80, height: 80)
                    }
                    .accessibilityLabel((manager.isRecording && !manager.isPaused) ? "a11y.pause".localized() : "a11y.record".localized())
                    .tint(manager.isRecording && !manager.isPaused ? .orange : .red)
                    .disabled(!manager.hasPermission)

                    if manager.isRecording || manager.isPaused || manager.currentFileName != nil {
                        Button {
                            manager.stopRecording()
                            if let filename = manager.currentFileName {
                                onSave(filename)
                            }
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .resizable()
                                .frame(width: 50, height: 50)
                        }
                        .accessibilityLabel("a11y.saveRecording".localized())
                        .tint(.green)
                    }
                }

                Spacer()
            }
            .navigationTitle("录音".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".localized()) {
                        manager.cancelRecording()
                        dismiss()
                    }
                }
            }
        }
        // 固定 350pt 高度,避免过大的 sheet 浪费屏幕
        // Fixed 350pt height to avoid wasting screen real-estate.
        .presentationDetents([.height(350)])
    }

    /// 把 TimeInterval 格式化为 "mm:ss.cs"(0.01s 精度)
    /// Format a TimeInterval as "mm:ss.cs" (centisecond precision).
    private func timeString(from time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}
