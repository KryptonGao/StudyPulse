import SwiftUI

/// End-of-session retro sheet: quick completion + optional difficulty/interruption.
/// Must be skippable for non-essential fields.
struct SessionGoalRetroSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var timer: StudyTimerManager

    // Local draft for retro fields - initialized from active session's goal.
    @State private var completedValue: Double = 0
    @State private var completedText: String = ""
    @State private var selectedDifficulty: StudySessionDifficulty?
    @State private var selectedReason: StudySessionInterruptionReason = .none
    @State private var note: String = ""
    @State private var isSkippingDifficulty = true

    private var goal: StudySessionGoal? { timer.sessions.first?.goal ?? timer.activeGoal }
    private var targetValue: Double { goal?.targetValue ?? 1 }
    private var unitLabel: String { goal?.unitLabel ?? "items" }

    private var canSave: Bool {
        // completedText must parse to >=0 if provided; empty means skip
        if completedText.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return Double(completedText) != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    completionSection
                    difficultySection
                    interruptionSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Session Complete".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip".localized()) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save".localized()) { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear { hydrate() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let g = goal {
                Label(g.title, systemImage: g.source.icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(String(format: "Target: %@ %@".localized(), formatTarget(g.targetValue), g.unitLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let rate = g.completionRate {
                    ProgressView(value: rate)
                        .tint(rate >= 1 ? .green : .accentColor)
                }
            } else {
                Text("No goal set".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func formatTarget(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    private var completionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Completion".localized())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                TextField("Completed".localized(), text: $completedText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(width: 90)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
                    .onChange(of: completedText) { _, new in
                        // clamp numeric
                        if let v = Double(new) {
                            completedValue = max(0, v)
                        }
                    }
                Text("/ \(formatTarget(targetValue)) \(unitLabel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let v = Double(completedText), targetValue > 0 {
                        let rate = min(v / targetValue, 1.0)
                        Text(String(format: "%.0f%%", rate * 100))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(rate >= 1 ? .green : .primary)
                        ProgressView(value: rate)
                            .frame(width: 80)
                    } else {
                        Text("--")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            HStack(spacing: 8) {
                ForEach([0.5, 0.8, 1.0], id: \.self) { frac in
                    Button {
                        let v = targetValue * frac
                        completedText = v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
                    } label: {
                        Text(String(format: "%.0f%%", frac * 100))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button("Clear".localized()) { completedText = "" }
                    .font(.caption)
            }
            Text("You can skip if not applicable".localized())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Difficulty (optional)".localized())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(isSkippingDifficulty ? "Set".localized() : "Skip".localized()) {
                    withAnimation(.easeInOut(duration: 0.18)) { isSkippingDifficulty.toggle() }
                }
                .font(.caption)
            }
            if !isSkippingDifficulty {
                HStack(spacing: 8) {
                    ForEach(StudySessionDifficulty.allCases) { d in
                        Button {
                            selectedDifficulty = d
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: d.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(d.displayName)
                                    .font(.caption2.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedDifficulty == d ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemFill))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedDifficulty == d ? Color.accentColor : Color.clear, lineWidth: 1.2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Tap Set to rate difficulty".localized())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var interruptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("If incomplete, why? (optional)".localized())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Reason".localized(), selection: $selectedReason) {
                ForEach(StudySessionInterruptionReason.allCases) { r in
                    Text(r.displayName).tag(r)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
            if selectedReason != .none {
                TextField("Note (optional)".localized(), text: $note, axis: .vertical)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
                    .lineLimit(2...4)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func hydrate() {
        if let g = goal {
            if let cv = g.completedValue {
                completedText = cv.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", cv) : String(format: "%.1f", cv)
                completedValue = cv
            } else {
                // default to target for convenience? keep empty to encourage explicit
                completedText = ""
            }
            selectedDifficulty = g.difficulty
            isSkippingDifficulty = g.difficulty == nil
            selectedReason = g.interruptionReason ?? .none
            note = g.interruptionNote ?? ""
        }
    }

    private func save() {
        let cv: Double? = {
            let t = completedText.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return nil }
            return Double(t)
        }()
        let diff = isSkippingDifficulty ? nil : selectedDifficulty
        let reason: StudySessionInterruptionReason? = selectedReason == .none ? nil : selectedReason
        _ = timer.finalizeGoal(completedValue: cv, difficulty: diff, interruptionReason: reason, interruptionNote: note)
        dismiss()
    }
}

#Preview {
    SessionGoalRetroSheet(timer: StudyTimerManager.shared)
}
