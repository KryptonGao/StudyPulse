import SwiftUI

/// Compact row shown in `StudyTimerSetupSheet` summarizing the draft goal.
/// Taps open `SessionGoalSheet`.
struct SessionGoalPickerRow: View {
    @Bindable var timer: StudyTimerManager
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            HStack {
                Text("Focus Goal".localized())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onEdit()
                } label: {
                    Text(timer.draftGoal == nil ? "Add Goal".localized() : "Edit".localized())
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                if timer.draftGoal != nil {
                    Button {
                        timer.clearDraftGoal()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let goal = timer.draftGoal {
                goalCard(goal)
            } else {
                emptyCard
            }
        }
    }

    private func goalCard(_ goal: StudySessionGoal) -> some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                Image(systemName: goal.source.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(sourceColor(goal.source)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.title.isEmpty ? goal.sourceTitle ?? goal.source.displayName : goal.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Label(goal.source.displayName, systemImage: goal.source.icon)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("· \(goal.progressText)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyCard: some View {
        Button(action: onEdit) {
            HStack(spacing: 10) {
                Image(systemName: "target")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set a focus goal".localized())
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    Text("Todo · Mistake · Knowledge · Custom".localized())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundColor(Color(.separator).opacity(0.6))
            )
        }
        .buttonStyle(.plain)
    }

    private func sourceColor(_ source: StudySessionGoalSource) -> Color {
        switch source {
        case .todo: return .green
        case .mistakeCluster: return .orange
        case .knowledgePoint: return .purple
        case .custom: return .blue
        case .timeInvestment: return .indigo
        }
    }
}

#Preview {
    let t = StudyTimerManager.shared
    SessionGoalPickerRow(timer: t) {}
        .padding()
        .environment(RepositoryContainer())
}
