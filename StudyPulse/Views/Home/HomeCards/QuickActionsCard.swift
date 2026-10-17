//
//  QuickActionsCard.swift
//  StudyPulse
//
//  主页快捷动作 dock:记成绩 / 记错题 / 新考试 / 计时,4 个固定入口,永远在首屏内。
//  Home quick-action dock: add grade / add mistake / new exam / timer — four fixed entries
//  that always sit on the first screen.
//
//  iPad 上「记错题」走 NavigationLink 推到 HomeView 的 NavigationStack
//  (`usesInternalNavigationStack: false`),避免误触关闭整个表单;iPhone 走 sheet。
//  On iPad "New Mistake" is pushed onto HomeView's stack instead of a sheet.
//

import SwiftUI

struct QuickActionsCard: View {
    @Environment(RepositoryContainer.self) private var container
    @State private var showingAddGrade = false
    @State private var showingNewExam = false
    @State private var showingNewMistake = false
    @State private var showingTimer = false

    var body: some View {
        HStack(spacing: DesignToken.Spacing.small) {
            DockButton(title: "Add Grade".localized(), icon: "pencil.line", tint: .cyan) {
                showingAddGrade = true
            }
            if UIDevice.current.userInterfaceIdiom == .pad {
                NavigationLink {
                    NewMistakeSetView(container: container, usesInternalNavigationStack: false)
                        .environment(container)
                        .adaptiveSheet()
                } label: {
                    DockLabel(title: "New Mistake".localized(), icon: "book.closed.fill", tint: .orange)
                }
                .buttonStyle(DockPressStyle())
            } else {
                DockButton(title: "New Mistake".localized(), icon: "book.closed.fill", tint: .orange) {
                    showingNewMistake = true
                }
            }
            DockButton(title: "New Exam".localized(), icon: "calendar.badge.plus", tint: .purple) {
                showingNewExam = true
            }
            DockButton(title: "Study Timer".localized(), icon: "timer", tint: .green) {
                showingTimer = true
            }
        }
        .sheet(isPresented: $showingAddGrade) {
            AddGradeView(container: container)
                .environment(container)
                .adaptiveSheet()
        }
        .sheet(isPresented: $showingNewExam) {
            NewExamSetView(container: container)
                .adaptiveSheet()
        }
        .sheet(isPresented: $showingNewMistake) {
            NewMistakeSetView(container: container)
                .environment(container)
                .adaptiveSheet()
        }
        .fullScreenCover(isPresented: $showingTimer) {
            StudyTimerView()
        }
        .debugLayoutBoundsAuto()
    }
}

// MARK: - Dock button

private struct DockButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DockLabel(title: title, icon: icon, tint: tint)
        }
        .buttonStyle(DockPressStyle())
    }
}

/// 图标方块 + 单行标题;按卡片皮肤绘制背景。
/// Icon tile + one-line title, drawn on the card skin.
private struct DockLabel: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, DesignToken.Spacing.medium)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .cardSkin()
    }
}

/// 按下缩放反馈 / Press-scale feedback.
private struct DockPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    QuickActionsCard()
        .padding()
        .environment(RepositoryContainer())
        .environment(StudyTimerManager.shared)
        .environment(HealthKitManager.shared)
}
