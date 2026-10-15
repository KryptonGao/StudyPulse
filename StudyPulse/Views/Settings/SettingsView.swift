//
//  SettingsView.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/3/21.
//

import SwiftUI

struct SettingsView: View {
    @Environment(RepositoryContainer.self) private var container
    /// 异步加载的头像数据，避免 body 中同步读文件
    @State private var avatarData: Data? = nil

    var body: some View {
        NavigationStack {
            List {
                // Pinned profile row (tap to enter Apple ID style page)
                Section {
                    NavigationLink(destination: ProfileSettingsView()) {
                        profileRow
                    }
                    .debugLayoutBoundsAuto()
                }

                // Settings categories
                Section {
                    ForEach(SettingsCategory.allCases) { category in
                        NavigationLink(destination: category.destination) {
                            SettingsCategoryRow(category: category)
                        }
                        .debugLayoutBoundsAuto()
                    }
                }
            }
        .task {
            avatarData = await container.loadAvatarAsync()
        }
  .listStyle(.insetGrouped)
  .containerBackground(.clear, for: .navigation)
  .debugModeContainer()
  .debugLayoutBoundsAuto()
  .navigationTitle("Settings".localized())
  .navigationBarTitleDisplayMode(.large)
        }
    }

    private var profileRow: some View {
        HStack(spacing: 14) {
            AvatarView(
                username: container.profileRepo.profile.username,
                avatarData: avatarData,
                size: 64
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(container.profileRepo.profile.username)
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundColor(.primary)
                Text(profileSubtitle)
                    .scaledFont(size: 13)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }

    private var profileSubtitle: String {
        let p = container.profileRepo.profile
        if !p.studentId.isEmpty {
            return "Student ID · \(p.studentId)"
        } else if !p.schoolName.isEmpty {
            return p.schoolName
        } else {
            return "Tap to set up your profile".localized()
        }
    }
}

#Preview {
    SettingsView()
        .environment(RepositoryContainer())
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    SettingsView()
        .environment(RepositoryContainer())
        .preferredColorScheme(.dark)
}
