import SwiftUI

/// Dashboard card showing goal completion rate, interruption frequency and per-source efficiency.
struct FocusStatsCard: View {
    var stats: FocusSessionStatsEngine.Stats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Focus Efficiency".localized(), systemImage: "target")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(stats.totalSessions) sessions".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                metric(
                    title: "Goal completion".localized(),
                    value: stats.avgCompletionRate.map { String(format: "%.0f%%", $0 * 100) } ?? "--",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                Divider().frame(height: 36)
                metric(
                    title: "With goal".localized(),
                    value: "\(stats.goalSessions)/\(stats.totalSessions)",
                    icon: "flag.fill",
                    color: .blue
                )
                Divider().frame(height: 36)
                metric(
                    title: "Interrupted".localized(),
                    value: String(format: "%.1f /sess", stats.avgInterruptionCount),
                    icon: "exclamationmark.triangle.fill",
                    color: .orange
                )
            }

            if !stats.efficiencyBySource.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("By type".localized())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(stats.efficiencyBySource.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { src in
                                let rate = stats.efficiencyBySource[src] ?? 0
                                VStack(spacing: 4) {
                                    Text(src.displayName)
                                        .font(.caption2.weight(.medium))
                                    Text(String(format: "%.0f%%", rate * 100))
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.accentColor)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color(.tertiarySystemFill)))
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func metric(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 14))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    FocusStatsCard(stats: .init(totalSessions: 12, goalSessions: 8, avgCompletionRate: 0.78, avgInterruptionCount: 0.3, efficiencyBySource: [.todo: 0.85, .custom: 0.6], difficultyBreakdown: [:], interruptionBreakdown: [:]))
        .padding()
}
