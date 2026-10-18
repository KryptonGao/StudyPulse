//
//  AIModeMessageView.swift
//  StudyPulse
//
//  One chat turn in AI Mode, drawn with `StreamingReply`: user turns are a tinted
//  glass bubble with reference tags; assistant turns sit under a glass header pill
//  (thinking / writing / stopped), render full Markdown, and lift on long press into
//  Copy / Regenerate. Source chips, follow-ups and a helpful toggle sit below.
//  Local analysis is always labelled as such.
//

import SwiftUI
import SwiftStreamingMarkdown

struct AIModeMessageView: View {
    let message: AIChatMessage
    var viewModel: AIModeViewModel
    let onOpenSource: (AISourceLink) -> Void

    @Environment(\.aiTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch message.role {
        case .user: userTurn
        case .assistant: assistantTurn
        }
    }

    // MARK: User

    private var userTurn: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !message.references.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.references) { reference in
                        Label(reference.scopeLabel, systemImage: reference.domain.systemImage)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(theme.muted)
                    }
                }
            }
            StreamingReply(text: .constant(message.content), role: .user, phase: .done, style: replyStyle)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: Assistant

    private var isStreaming: Bool { message.status == .streaming }

    private var assistantTurn: some View {
        VStack(alignment: .leading, spacing: 10) {
            StreamingReply(
                text: .constant(message.content),
                role: .assistant,
                phase: replyPhase,
                style: replyStyle,
                body: AnyView(markdown)
            ) { action in
                // Copy is done by the reply itself; Regenerate asks the model again.
                if action == .regenerate { viewModel.retry(message.id) }
            }
            Group {
                if message.status == .failed {
                    pillButton("aiMode.action.useLocal".localized(), systemImage: "chart.bar.doc.horizontal") {
                        viewModel.useLocalAnalysis(for: message.id)
                    }
                }
                if message.status == .stopped {
                    Text("aiMode.status.stopped".localized())
                        .font(.footnote)
                        .foregroundStyle(theme.muted)
                }
                if message.status == .interrupted {
                    Text("aiMode.status.interrupted".localized())
                        .font(.footnote)
                        .foregroundStyle(theme.muted)
                }
                if !message.actions.isEmpty, !isStreaming, message.status != .failed {
                    actionCards
                }
                if !message.sources.isEmpty, !isStreaming {
                    sources
                }
                if !message.followUps.isEmpty, message.status == .complete {
                    followUps
                }
                if !isStreaming, message.status != .failed, !message.content.isEmpty {
                    actions
                }
            }
            // What arrives when the reply ends (cards, sources, follow-ups, actions) eases in under the text
            // instead of popping into place.
            .transition(.opacity.combined(with: .offset(y: 6)))
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.4), value: message.status)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Where the reply is in its life, for the header pill and the dots.
    private var replyPhase: StreamingReply.Phase {
        switch message.status {
        case .streaming: return message.content.isEmpty ? .thinking : .streaming
        case .failed: return .error(message.errorDescription ?? "aiMode.error.generic".localized())
        case .complete, .stopped, .interrupted: return .done
        }
    }

    /// The reply's palette comes from the AI Mode theme so both appearances stay consistent.
    private var replyStyle: StreamingReply.Style {
        var style = StreamingReply.Style()
        style.userBlock = theme.accent.opacity(0.2)
        style.cursor = theme.accent
        style.dots = [theme.accent, theme.accent.opacity(0.65), theme.accent.opacity(0.4)]
        style.signal = Color(light: 0xE5786C, dark: 0xB4554B)
        style.ink = theme.ink
        style.text = theme.ink
        style.muted = theme.muted
        style.mark = theme.accent
        style.markInk = .white
        style.actionInk = theme.ink
        style.success = Color(light: 0xA9DCB7, dark: 0x2F5A3D)
        style.assistantName = message.origin == .localAnalysis
            ? "aiMode.origin.local".localized()
            : (message.modelName ?? "aiMode.origin.model".localized())
        return style
    }

    private var markdown: some View {
        MarkdownView(
            text: message.content.normalisingSingleDollarMath(),
            config: .chatConfig(isStreaming: isStreaming)
        )
        // The markdown view owns its own text selection, which would swallow the long press that lifts
        // the reply. Copy in the lifted actions (or the row below) takes the whole message instead.
        .allowsHitTesting(false)
    }

    // MARK: Write proposals

    private var actionCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(message.actions) { action in
                actionCard(action)
            }
            if message.actions.filter({ $0.status == .pending }).count > 1 {
                Button {
                    viewModel.applyAllActions(in: message.id)
                } label: {
                    Label("aiMode.action.addAll".localized(), systemImage: "checkmark.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if message.actions.contains(where: { $0.status == .pending }) {
                Text("aiMode.action.hint".localized())
                    .font(.caption2)
                    .foregroundStyle(theme.muted)
            }
        }
    }

    private func actionCard(_ action: AIProposedAction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: action.kind == .addGrade ? "chart.line.uptrend.xyaxis" : "checklist")
                .font(.subheadline)
                .foregroundStyle(theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(actionKindLabel(action)).font(.caption).foregroundStyle(theme.muted)
                Text(actionTitle(action)).font(.subheadline.weight(.semibold)).foregroundStyle(theme.ink)
                if let detail = actionDetail(action) {
                    Text(detail).font(.caption).foregroundStyle(theme.muted)
                }
                if let error = action.errorMessage, action.status == .failed {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            actionControls(action)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func actionControls(_ action: AIProposedAction) -> some View {
        switch action.status {
        case .pending, .failed:
            VStack(spacing: 6) {
                Button("aiMode.action.add".localized()) {
                    viewModel.applyAction(action.id, in: message.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("aiMode.action.dismiss".localized()) {
                    viewModel.dismissAction(action.id, in: message.id)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(theme.muted)
            }
        case .applied:
            VStack(alignment: .trailing, spacing: 6) {
                Label("aiMode.action.applied".localized(), systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                Button("aiMode.action.undo".localized()) {
                    viewModel.undoAction(action.id, in: message.id)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(theme.muted)
            }
        case .dismissed:
            Text("aiMode.action.dismissed".localized()).font(.caption).foregroundStyle(theme.muted)
        case .undone:
            Text("aiMode.action.undone".localized()).font(.caption).foregroundStyle(theme.muted)
        }
    }

    private func actionKindLabel(_ action: AIProposedAction) -> String {
        switch action.kind {
        case .addGrade: return "aiMode.action.kind.grade".localized()
        case .addTask:
            return action.task?.type == .reading
                ? "aiMode.action.kind.reading".localized()
                : "aiMode.action.kind.homework".localized()
        }
    }

    private func actionTitle(_ action: AIProposedAction) -> String {
        if let grade = action.grade {
            return "\(grade.subjectDisplayName) \(formatted(grade.score))/\(formatted(grade.fullScore))"
        }
        return action.task?.title ?? ""
    }

    private func actionDetail(_ action: AIProposedAction) -> String? {
        if let grade = action.grade {
            let day = grade.date.formatted(date: .abbreviated, time: .omitted)
            return grade.examName.isEmpty ? day : "\(grade.examName) · \(day)"
        }
        if let task = action.task {
            let due = String(format: "aiMode.action.due".localized(), task.dueDate.formatted(date: .abbreviated, time: .shortened))
            return task.subjectDisplayName.isEmpty ? due : "\(task.subjectDisplayName) · \(due)"
        }
        return nil
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("aiMode.sources.title".localized())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.muted)
            FlowLayout(spacing: 6) {
                ForEach(message.sources) { source in
                    Button { onOpenSource(source) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: source.domain?.systemImage ?? "link").font(.caption2)
                            Text(source.label).font(.caption).lineLimit(1)
                        }
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.accentSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var followUps: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(message.followUps, id: \.self) { question in
                Button {
                    viewModel.send(question)
                } label: {
                    HStack(spacing: 6) {
                        Text(question)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.caption)
                    }
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isGenerating)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 18) {
            if !message.content.isEmpty {
                iconAction("doc.on.doc", label: "aiMode.action.copy".localized()) { viewModel.copy(message.id) }
                iconAction(
                    message.feedbackHelpful == true ? "hand.thumbsup.fill" : "hand.thumbsup",
                    label: "aiMode.action.helpful".localized()
                ) { viewModel.toggleHelpful(message.id) }
            }
            if message.status != .failed {
                iconAction("arrow.clockwise", label: "aiMode.action.retry".localized()) { viewModel.retry(message.id) }
                    .disabled(viewModel.isGenerating)
            }
        }
        .foregroundStyle(theme.muted)
    }

    // MARK: Helpers

    private func iconAction(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.subheadline)
                .frame(minWidth: 28, minHeight: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func pillButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(theme.accentSoft, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isGenerating)
    }
}
