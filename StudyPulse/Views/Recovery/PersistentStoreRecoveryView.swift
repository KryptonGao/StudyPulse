//
//  PersistentStoreRecoveryView.swift
//  StudyPulse
//

import SwiftUI

struct PersistentStoreRecoveryView: View {
    let controller: PersistentStoreLaunchController

    @State private var showsRecoveryConfirmation = false
    @State private var showsTechnicalDetails = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .scaledFont(size: 54, weight: .semibold)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        Text("学习数据库需要恢复")
                            .font(.title2.bold())

                        Text("数据库未能完成打开或版本迁移。原数据库仍保留在设备上，StudyPulse 没有创建空数据库，也没有删除你的学习数据。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        Button {
                            controller.retry()
                        } label: {
                            Label("重试打开数据库", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button(role: .destructive) {
                            showsRecoveryConfirmation = true
                        } label: {
                            Label(
                                "备份原数据库并创建新数据库",
                                systemImage: "externaldrive.badge.plus"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .disabled(controller.isWorking)

                    if controller.isWorking {
                        ProgressView("正在处理…")
                    }

                    DisclosureGroup(
                        "技术详情",
                        isExpanded: $showsTechnicalDetails
                    ) {
                        Text(controller.error?.localizedDescription ?? "未知数据库错误")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    .font(.footnote)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 28)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("数据恢复")
            .navigationBarTitleDisplayMode(.inline)
        }
        .confirmationDialog(
            "创建新的数据库？",
            isPresented: $showsRecoveryConfirmation,
            titleVisibility: .visible
        ) {
            Button("备份并创建新数据库", role: .destructive) {
                controller.performDisasterRecovery()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("StudyPulse 会先把原数据库及其日志文件完整移动到带时间戳的备份目录，然后创建新数据库。只有在新数据库创建成功后才会继续启动；失败时会自动还原原数据库。")
        }
    }
}
