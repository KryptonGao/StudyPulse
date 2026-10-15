//
//  UpcomingExamsCard.swift
//  StudyPulse
//
//  主页"即将到来的考试"卡片:14 天内考试列表(取前 3 个)。
// 含 CompactExamCard(行卡,带日期色块 + 倒计时)。
//  Home "Upcoming Exams" card: list of exams within the next 14 days (top 3 shown).
//  Includes CompactExamCard (row card with date color block + countdown).
//
//  Extracted from HomeView.swift during card-extraction refactor (2026-07-05).
//

import SwiftUI

/// 主页"即将到来的考试"区域。
/// 之前直接读 `container.examRepo.filteredExamSets` 现地计算 14 天窗口。
/// Home "Upcoming Exams" region.
/// Previously read `container.examRepo.filteredExamSets` and computed the 14-day window inline.
struct UpcomingExamsCard: View {
    @Environment(RepositoryContainer.self) private var container

    /// 14 天窗口内、按日期正序排列的考试列表(now ~ now+14d)。
    /// Exams within the 14-day window (now ~ now+14d), sorted ascending by exam date.
    var upcomingExams: [Exam] {
        // 14 天窗口:now ~ now+14d 内、未结束的考试算「即将到来」
        // 14-day window: exams in (now, now+14d] count as "upcoming".
        let twoWeeksFromNow = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        return container.examRepo.filteredExamSets
            .filter { $0.examDate > Date() && $0.examDate <= twoWeeksFromNow }
            .sorted { $0.examDate < $1.examDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Upcoming Exams".localized())
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(upcomingExams.count)")
                    .scaledFont(size: 14, weight: .bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(.systemOrange), Color(.orange)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }

            VStack(spacing: 12) {
                ForEach(upcomingExams.prefix(3)) { exam in
                    CompactExamCard(exam: exam)
                        .equatable()
                }
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
        .debugLayoutBoundsAuto()
    }
}

// MARK: - 紧凑考试卡片
// MARK: - Compact Exam Card

/// UpcomingExamsCard 内的行式考试卡(左侧日期色块 + 中部信息 + 倒计时)。
/// Row-style exam card inside UpcomingExamsCard (left date color block + middle info + countdown).
struct CompactExamCard: View, Equatable {
    let exam: Exam
    @State private var animateIn = false

    /// 只按 exam.id 比较,避免在 DataManager 变化时重建无关卡片
    /// Only compare by exam.id so unrelated DataManager changes don't rebuild this card.
    static func == (lhs: CompactExamCard, rhs: CompactExamCard) -> Bool {
        lhs.exam.id == rhs.exam.id
    }

    private var daysRemaining: Int {
        let components = Calendar.current.dateComponents([.day], from: Date(), to: exam.examDate)
        return max(0, components.day ?? 0)
    }

    private var daysRemainingText: String {
        if daysRemaining == 0 {
            return "Today!".localized()
        } else if daysRemaining == 1 {
            return "Tomorrow".localized()
        } else {
            return "\(daysRemaining) " + "days".localized()
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(dayString(from: exam.examDate))
                    .scaledFont(size: 20, weight: .bold)
                    .foregroundColor(.primary)

                Text(monthString(from: exam.examDate))
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundColor(.secondary)
            }
            .frame(width: 60)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(exam.name)
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(exam.subject.localized())
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(.systemBlue).opacity(0.8), Color(.blue)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )

                    Text(daysRemainingText)
                        .scaledFont(size: 12, weight: .medium)
                        // 3 天内显示红色提醒,其余用次要色
                        // Within 3 days → red (urgent); otherwise secondary color.
                        .foregroundColor(daysRemaining <= 3 ? Color(.systemRed) : .secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(14)
        .background(Color(.systemBackground).opacity(0.6))
        .cornerRadius(14)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                animateIn = true
            }
        }
    }

    private func dayString(from date: Date) -> String {
        DateFormatters.dayOfMonth.string(from: date)
    }

    private func monthString(from date: Date) -> String {
        DateFormatters.monthShort.string(from: date)
    }
}
