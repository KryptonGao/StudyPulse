//
//  AboutView.swift
//  StudyPulse

import SwiftUI
import UIKit

struct AboutView: View {
    /// Debug 模式彩蛋:连点版本号 7 次解锁
    @State private var versionTapCount: Int = 0
    @State private var lastVersionTapTime: Date = .distantPast
    @State private var showDebug: Bool = false

    private let requiredTaps = 7
    private let tapWindowSeconds: TimeInterval = 5.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .center, spacing: 20) {
                    Image(systemName: "graduationcap.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.blue)

                    Text("StudyPulse")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Group {
                        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                            Text("Version \(version)")
                        }
                    }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleVersionTap()
                        }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("About StudyPulse".localized())
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("StudyPulse is a comprehensive learning management application designed to help students track their academic performance, analyze trends, and manage their study materials effectively.".localized())

                        Text("Features:".localized())
                        Text("- Track grades across multiple subjects".localized())
                        Text("- Visualize progress with interactive charts".localized())
                        Text("- Manage mistake collections with detailed analysis".localized())
                        Text("- Personalized learning recommendations".localized())
                        Text("- Support for photo uploads for exam papers and mistakes".localized())
                    }
                    .padding()

                    Spacer()
                }
                .padding()
            }
            .adaptiveMaxWidth(640)
            .navigationTitle("About".localized())
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showDebug) {
                DebugView()
            }
        }
    }

    /// 版本号连点解锁彩蛋
    /// Tap the version label `requiredTaps` times within `tapWindowSeconds` to unlock Debug.
    private func handleVersionTap() {
        let now = Date()
        if now.timeIntervalSince(lastVersionTapTime) > tapWindowSeconds {
            versionTapCount = 0
        }
        versionTapCount += 1
        lastVersionTapTime = now

        if versionTapCount >= requiredTaps {
            versionTapCount = 0
            Haptics.impact(.medium)
            showDebug = true
        }
    }
}
