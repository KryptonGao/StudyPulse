//
//  AnnotationListView.swift
//  StudyPulse
//
//  难题标注列表:展示会话中所有标注,支持点击编辑、左滑删除。
//  Difficulty annotation list: shows all annotations in a session,
//  with tap-to-edit and swipe-to-delete.
//

import SwiftUI

// MARK: - AnnotationListView

struct AnnotationListView: View {
    let annotations: [DifficultyAnnotation]
    let subjects: [Subject]
    var onEdit: (DifficultyAnnotation) -> Void
    var onDelete: (DifficultyAnnotation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Difficulty Annotations".localized())
                    .scaledFont(size: 14, weight: .semibold)
                Spacer()
                Text("\(annotations.count)")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
            }

            if annotations.isEmpty {
                emptyState
            } else {
                ForEach(annotations.sorted(by: { $0.timestamp < $1.timestamp })) { anno in
                    annotationRow(anno)
                }
            }
        }
    }

    // MARK: - Row

    private func annotationRow(_ anno: DifficultyAnnotation) -> some View {
        Button {
            onEdit(anno)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 2) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .scaledFont(size: 14)
                        .foregroundColor(.orange)
                    if let hr = anno.heartRate {
                        Text("\(Int(hr))")
                            .scaledFont(size: 10, weight: .semibold, design: .rounded)
                            .foregroundColor(.pink)
                    }
                }
                .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(anno.note)
                        .scaledFont(size: 14)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        Text(anno.timestamp, format: .dateTime.hour().minute().second())
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let sid = anno.subjectId,
                           let subj = subjects.first(where: { $0.id == sid }) {
                            Text(subj.displayName)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete(anno)
            } label: {
                Label("Delete".localized(), systemImage: "trash")
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "lightbulb")
                .scaledFont(size: 22)
                .foregroundColor(.secondary)
            Text("Tap a highlighted peak or long-press the chart to log a difficulty.".localized())
                .scaledFont(size: 12)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - Preview

#Preview {
    let now = Date()
    return AnnotationListView(
        annotations: [
            DifficultyAnnotation(id: UUID(), timestamp: now.addingTimeInterval(300), heartRate: 110, note: "几何证明没有思路,卡了很久", subjectId: nil),
            DifficultyAnnotation(id: UUID(), timestamp: now.addingTimeInterval(900), heartRate: 98, note: "计算量大,中间出错两次", subjectId: nil)
        ],
        subjects: [],
        onEdit: { _ in },
        onDelete: { _ in }
    )
    .padding()
}
