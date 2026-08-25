//
//  ExamReadinessLLM.swift
//  StudyPulse
//
//  Optional BYOK refinement for the local exam-readiness result. The local
//  engine remains the source of truth and this parser returns nil on failure.
//

import Foundation

nonisolated struct ExamReadinessLLMContext: Sendable {
    let examName: String
    let daysRemaining: Int
    let predictedScore: Double?
    let riskCategory: RiskCategory
    let trendSlope: Double
    let confidence: Double
    let localAdvice: String
    let reasoningLines: [String]
}
nonisolated enum ExamReadinessLLM {
    static let defaultSystem: String = """
        你是 StudyPulse 的考前恢复教练。输入是本地算法已经计算出的考试状态预测。
        只给出一段 2-4 句、具体而克制的中文建议：说明今天到考试前应该如何安排学习强度、休息和睡眠。
        不得否定本地预测，不得给出医学诊断，不得输出分数之外的确定性承诺，不得输出标题、JSON 或代码块。
        如果置信度低，明确使用“趋势参考”措辞。
        """

    static func context(from readiness: ExamDayReadiness) -> ExamReadinessLLMContext {
        ExamReadinessLLMContext(
            examName: readiness.examName,
            daysRemaining: readiness.daysRemaining,
            predictedScore: readiness.predictedScore,
            riskCategory: readiness.riskCategory,
            trendSlope: readiness.trendSlope,
            confidence: readiness.confidence,
            localAdvice: readiness.advice,
            reasoningLines: readiness.reasoningLines
        )
    }

    static func makePrompt(_ context: ExamReadinessLLMContext) -> LLMPrompt {
        let score = context.predictedScore.map { String(format: "%.0f%%", $0 * 100) } ?? "暂无数值"
        let reasons = context.reasoningLines.map { "- \($0)" }.joined(separator: "\n")
        let user = """
        考试：\(context.examName)
        剩余天数：\(context.daysRemaining)
        本地预测：\(score)
        风险类别：\(context.riskCategory.rawValue)
        恢复趋势：\(String(format: "%.3f/天", context.trendSlope))
        数据覆盖度：\(String(format: "%.0f%%", context.confidence * 100))
        本地建议：\(context.localAdvice)
        依据：
        \(reasons)
        """
        return LLMPrompt(
            system: defaultSystem,
            messages: [.user(user)],
            sensitivity: .healthSensitive
        )
    }

    static func parse(_ output: String) -> String? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("```") else { return nil }
        return String(text.prefix(500))
    }
}
