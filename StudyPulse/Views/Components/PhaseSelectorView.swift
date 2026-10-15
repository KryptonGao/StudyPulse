//
//  PhaseSelectorView.swift
//  StudyPulse
//
//  全局 phase 切换器(胶囊 pill),放在各主页面 toolbar 顶部。
//  Global phase switcher pill shown in each main page's toolbar.
//
//  - 胶囊颜色:未选 phase 灰,选了之后用 effectiveAccentColor
//  - 第一项"全部数据"用于清空当前 phase
//  - 已归档 phase 名字后面会标 "· Archived"
//  - 数据按 phaseRepo.phases 的当前顺序(降序)
//
//  - Capsule color: gray when no phase is active, otherwise `effectiveAccentColor`.
//  - First item "All Data" clears the active phase.
//  - Archived phases get a "· Archived" suffix.
//  - Phases are listed in `phaseRepo.phases` order (descending).
//

import SwiftUI

/// 全局 phase 切换器。
/// Global phase switcher. Shows current phase (or "All Data") and opens a menu
/// to switch. Embedded in each main page's toolbar.
struct PhaseSelectorView: View {
    @Environment(RepositoryContainer.self) private var container

    var body: some View {
        Menu {
            // 全部数据选项
            // "All Data" option
            Button {
                container.activatePhase(nil)
            } label: {
                Label {
                    Text("All Data".localized())
                } icon: {
                    Image(systemName: container.envManager.activePhaseId == nil
                         ? "checkmark.circle.fill"
                         : "circle")
                }
            }

            if !container.phaseRepo.phases.isEmpty {
                Divider()
                // 按 phaseRepo.phases 当前顺序(已是降序)
                // In the existing order of `phaseRepo.phases` (already descending).
                ForEach(container.phaseRepo.phases) { phase in
                    Button {
                        container.activatePhase(phase)
                    } label: {
                        Label {
                            HStack {
                                Text(phase.name)
                                if phase.isArchived {
                                    Text("·")
                                    Text("Archived".localized())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: container.envManager.activePhaseId == phase.id
                                 ? "checkmark.circle.fill"
                                 : "circle")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.clock")
                    .scaledFont(size: 12, weight: .semibold)
                Text(labelText)
                    .scaledFont(size: 13, weight: .semibold)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .scaledFont(size: 9, weight: .bold)
            }
            .foregroundColor(container.envManager.activePhaseId == nil
                             ? Color.secondary
                             : container.envManager.effectiveAccentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(container.envManager.activePhaseId == nil
                          ? Color.secondary.opacity(0.12)
                          : container.envManager.effectiveAccentColor.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        container.envManager.activePhaseId == nil
                            ? Color.secondary.opacity(0.25)
                            : container.envManager.effectiveAccentColor.opacity(0.35),
                        lineWidth: 0.5
                    )
            )
        }
        .accessibilityLabel(Text("Study Phase".localized()))
    }

    private var labelText: String {
        if let phase = container.phaseRepo.activePhase {
            return phase.name
        }
        return "All Data".localized()
    }
}
