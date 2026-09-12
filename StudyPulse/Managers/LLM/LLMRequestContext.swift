import Foundation
import SwiftUI

nonisolated enum LLMThinkingMode: String, Codable, CaseIterable, Sendable {
    case off
    case auto
    case on

    var title: String {
        switch self {
        case .off: return "关闭"
        case .auto: return "自动"
        case .on: return "开启"
        }
    }

    var subtitle: String {
        switch self {
        case .off: return "响应更快，消耗更少积分"
        case .auto: return "复杂问题自动启用，推荐"
        case .on: return "优先进行深度推理，可能消耗更多积分"
        }
    }
}

nonisolated struct LLMRequestContext: Sendable, Equatable {
    var caller: String
    var thinking: LLMThinkingMode
    var locale: String?

    static func make(caller: String, config: LLMConfig) -> LLMRequestContext {
        LLMRequestContext(
            caller: caller,
            thinking: LLMCallerPolicy.thinking(for: caller, userPreference: config.thinkingMode),
            locale: config.locale
        )
    }
}

nonisolated enum LLMCallerPolicy {
    private static let interactive: Set<String> = [
        "LLMChat", "MistakeAI", "MistakeDebate",
        "SimilarQuestion", "AISimilarQuestion",
        "SimilarQuestionGrading", "AISimilarGrading",
        "AIQuiz", "QuizGeneration", "AIQuizGrading", "QuizGrading",
        "AIDiscussion", "AICoach", "AICoach-Conversation",
        "HomeAsk-Answer", "ExamSimulationGeneration", "ExamSimulationGrading",
        "ExamAutopsy",
    ]

    private static let defaults: [String: LLMThinkingMode] = [
        "HomeAsk-Router": .off,
        "StudySuggestions": .off,
        "WeeklyReport": .off,
        "HabitInsight": .off,
        "ScorePrediction": .off,
        "SubjectRadar": .off,
        "BrainUsageQuota": .off,
        "BodyRadar": .off,
        "StudySessionStress": .off,
        "LLMChat": .auto,
        "MistakeAI": .auto,
        "SimilarQuestion": .auto,
        "AISimilarQuestion": .auto,
        "SimilarQuestionGrading": .auto,
        "AISimilarGrading": .auto,
        "AIDiscussion": .auto,
        "AICoach": .auto,
        "AICoach-Conversation": .auto,
        "KnowledgeFaultLine": .auto,
        "AIQuiz": .auto,
        "QuizGeneration": .auto,
        "AIQuizGrading": .auto,
        "QuizGrading": .auto,
        "ExamSimulationGeneration": .auto,
        "ExamSimulationGrading": .auto,
        "ExamRoleAnalysis": .auto,
        "ExamReadiness": .auto,
        "ExamReversePlanner": .auto,
        "AutoMindMap": .auto,
        "AutoMindMapDelta": .auto,
        "HomeAsk-Answer": .auto,
        "MistakeDebate": .on,
        "ExamAutopsy": .auto,
        "MistakeImageRecognition": .auto,
        "Legacy": .auto,
    ]

    static func defaultThinking(for caller: String) -> LLMThinkingMode {
        defaults[caller] ?? .auto
    }

    static func isInteractive(_ caller: String) -> Bool {
        interactive.contains(caller)
    }

    static func thinking(for caller: String, userPreference: LLMThinkingMode) -> LLMThinkingMode {
        isInteractive(caller) ? userPreference : defaultThinking(for: caller)
    }
}

struct LLMThinkingModePicker: View {
    @Binding var mode: LLMThinkingMode
    var compact: Bool = false

    var body: some View {
        if compact {
            picker.pickerStyle(.menu)
        } else {
            picker
        }
    }

    private var picker: some View {
        Picker("深度思考".localized(), selection: $mode) {
            ForEach(LLMThinkingMode.allCases, id: \.self) { item in
                Text(item.title.localized()).tag(item)
            }
        }
    }
}

struct CloudThinkingToolbarModifier: ViewModifier {
    @Environment(RepositoryContainer.self) private var container

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if container.envManager.llmConfig.isCloudProvider {
                    LLMThinkingModePicker(
                        mode: Binding(
                            get: { container.envManager.preferences.cloudThinkingMode },
                            set: { container.envManager.setCloudThinkingMode($0) }
                        ),
                        compact: true
                    )
                    .accessibilityLabel("深度思考".localized())
                }
            }
        }
    }
}

extension View {
    func cloudThinkingToolbar() -> some View {
        modifier(CloudThinkingToolbarModifier())
    }
}
