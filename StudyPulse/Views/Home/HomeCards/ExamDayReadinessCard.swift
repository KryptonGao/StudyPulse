//
//  ExamDayReadinessCard.swift
//  StudyPulse
//
//  Home card and detail sheet for the derived exam-day readiness forecast.
//

import Charts
import SwiftUI

struct ExamDayReadinessCard: View {
    @Bindable var viewModel: HomeViewModel
    @State private var showingSheet = false

    private var nearest: ExamDayReadiness? { viewModel.examReadiness.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("examReadiness.title".localized(), systemImage: "chart.line.uptrend.xyaxis.circle.fill")
                    .scaledFont(size: 18, weight: .semibold)
                Spacer()
                Button("examReadiness.sheetTitle".localized()) {
                    showingSheet = true
                }
                .font(.caption.weight(.medium))
                .disabled(viewModel.examReadiness.isEmpty)
            }

            if let nearest {
                readinessSummary(nearest)
                recoveryChart
            } else {
                emptyState
            }
        }
        .padding(DesignToken.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
        .sheet(isPresented: $showingSheet) {
            ExamDayReadinessSheet(
                readiness: viewModel.examReadiness
            )
        }
        .debugLayoutBoundsAuto()
    }

    @ViewBuilder
    private func readinessSummary(_ readiness: ExamDayReadiness) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(readiness.examName)
                    .font(.headline)
                    .lineLimit(1)
                Text(daysText(readiness.daysRemaining))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                if let score = readiness.predictedScore {
                    Text(String(format: "%.0f%%", score * 100))
                        .scaledFont(size: 30, weight: .bold, design: .rounded)
                        .foregroundStyle(color(for: readiness.riskCategory))
                } else {
                    Text("—")
                        .scaledFont(size: 30, weight: .bold, design: .rounded)
                        .foregroundStyle(.secondary)
                }
                Text(riskText(for: readiness.riskCategory))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: readiness.riskCategory))
            }
        }

        Text(readiness.advice)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if readiness.confidence > 0 {
            Text(String(format: "examReadiness.confidenceLabel".localized(), readiness.confidence * 100))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else {
            Text("examReadiness.emptyHint".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var recoveryChart: some View {
        let points = viewModel.recoveryPoints.filter(\.isValid)
        if points.count >= 2 {
            Chart(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Recovery", point.score)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.blue.gradient)
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Recovery", point.score)
                )
                .foregroundStyle(Color.blue.opacity(0.08).gradient)
            }
            .chartYScale(domain: 0...1)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 64)
            .accessibilityLabel("examReadiness.trendLabel".localized())
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "heart.text.square")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("examReadiness.emptyHint".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func daysText(_ days: Int) -> String {
        if days <= 0 { return "examReadiness.today".localized() }
        return String(format: "examReadiness.daysRemaining".localized(), days)
    }

    private func riskText(for category: RiskCategory) -> String {
        "riskCategory.\(category.rawValue)".localized()
    }

    private func color(for category: RiskCategory) -> Color {
        switch category {
        case .strong: return .green
        case .steady: return .blue
        case .atRisk: return .orange
        case .critical: return .red
        }
    }
}

struct ExamDayReadinessSheet: View {
    let readiness: [ExamDayReadiness]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if readiness.isEmpty {
                    Text("examReadiness.emptyHint".localized())
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(readiness) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.examName)
                                        .font(.headline)
                                    Text(item.examDate, format: .dateTime.month().day().year())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                scoreView(item)
                            }
                            Text(item.advice)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ForEach(item.reasoningLines, id: \.self) { line in
                                Label(line, systemImage: "circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("examReadiness.sheetTitle".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized()) { dismiss() }
                }
            }
        }
    }

    private func scoreView(_ item: ExamDayReadiness) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(item.predictedScore.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                .font(.title3.weight(.bold))
                .foregroundStyle(color(for: item.riskCategory))
            Text("riskCategory.\(item.riskCategory.rawValue)".localized())
                .font(.caption2.weight(.medium))
                .foregroundStyle(color(for: item.riskCategory))
        }
    }

    private func color(for category: RiskCategory) -> Color {
        switch category {
        case .strong: return .green
        case .steady: return .blue
        case .atRisk: return .orange
        case .critical: return .red
        }
    }
}
