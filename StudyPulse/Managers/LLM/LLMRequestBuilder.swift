//
//  LLMRequestBuilder.swift
//  StudyPulse
//
//  把 StudyPulse 内部数据(学习建议上下文 / 错题 / 周报 / 对话历史)
//  拼装成 `LLMPrompt`(system + messages)与可选的 `suggestionParser`。
//  Assembles StudyPulse internal data (study-suggestion context, mistakes,
//  weekly report, chat history) into `LLMPrompt` (system + messages) and
//  optional parsers.
//
//  全部为纯函数 / enum,无副作用,易测。
//  All pure functions / enums; no side effects, easy to unit-test.
//
//  内置场景(共 10 个 prompt 工厂) / Built-in scenarios (10 prompt factories):
//    1. StudySuggestionsLLM          — 学习建议 3 条
//    2. MistakeAnalysisLLM           — 错题 AI 解析(3 段固定格式)
//    3. WeeklyReportLLM              — 周/月报 AI 总结
//    4. LLMChatLLM                   — AI 助手自由对话
//    5. ScorePredictionLLM           — 预测分数 AI 二次意见
//    6. ComprehensiveScorePrediction — 综合考试 AI 二次意见
//    7. AIDiscussionLLM              — "深入探讨" 多轮对话
//    8. SimilarQuestionLLM           — AI 相似题变式
//    8b.SimilarQuestionGradingLLM    — AI 变式题判分
//    9. HomeAskRouterLLM             — 主页 AI 提问 路由阶段
//    +  HomeAskAnswerLLM             — 主页 AI 提问 回答阶段
//    10.QuizGenerationLLM            — AI 自测出题
//    10b.QuizGradingLLM              — AI 自测判分
//
//  关键解析逻辑 / Key parsing logic:
//    • StudySuggestionsLLM.parse   — 正则提取 `- **<icon> <title>** — <desc>`
//    • SimilarQuestionGradingLLM.parse — 提取"评分"段的第一个 0-100 整数
//    • HomeAskRouterLLM.parse      — 提取最外层 JSON 对象,容错回退到全部分类
//    • BodyRadarLLM.parse          — 解析 `## 强度/标题/建议/依据` 4 段
//
//  Created for LLM BYOK integration (2026-07-11).
//

import Foundation
import SwiftUI

// MARK: - Shared LaTeX formatting rule (injected into all math-related system prompts)

/// 所有可能输出数学公式的 system prompt 末尾必须追加此规则。
/// 原因：iosMath 渲染引擎不支持 `\begin{cases}` 等 LaTeX 环境，渲染时会静默产生空白。
/// Must be appended to every system prompt that may output math.
/// Reason: the iosMath rendering engine does not support `\begin{cases}` and similar
/// LaTeX environments; they are silently rendered as blank space.
private let latexFormattingRule = """

        【数学公式格式强制规则 — 不得违反】
        严禁使用 `\\begin{cases}` / `\\end{cases}` 语法（渲染引擎不支持，会变为空白）。
        严禁使用 `\\begin{align}` / `\\begin{align*}` / `\\begin{array}` 等任何 LaTeX 环境块。
        方程组 / 不等式组必须改用以下方式之一：
        方式 A（推荐）：每个方程单独一行，用行内公式 + 序号，例如：
          方程①：$2x - 3 \\geq 5$
          方程②：$x + 4 < 10$
        方式 B：整个方程组写成一行行内公式（用分号分隔），例如：$2x-3\\geq5;\\;x+4<10$
        行内公式使用 `$...$`，块级公式使用 `$$...$$`，但块级公式内不得含任何 `\\begin{...}` 环境。
        """

// MARK: - 1) Study Suggestions (学习建议)

/// 学习建议 prompt 工厂。
enum StudySuggestionsLLM {
    /// 默认 system prompt。要求 LLM 输出 Markdown 列表,
    /// 3 条,每条格式 `- **<icon> <title>** — <description>`。
    static let defaultSystem: String = """
        你是 StudyPulse 的学习教练。基于用户提供的成绩、错题、考试和身体数据,生成 3 条个性化、可执行的中文学习建议。
        要求:
        1. 每条建议聚焦一个不同维度(弱势科目 / 即将考试 / 错题复习 / 身体状态 / 持续提升),不要重复。
        2. 严格使用 Markdown 列表输出,每条格式:
           - **<SF Symbol 名> <建议标题>** — <一句话建议,20-60 字>
        3. SF Symbol 名从以下选择(不要自造):exclamationmark.triangle.fill / timer / doc.text.magnifyingglass / chart.line.uptrend.xyaxis / chart.line.downtrend.xyaxis / hand.thumbsup.fill / lightbulb.fill / heart.text.square / brain.head.profile
        4. 严禁输出 JSON、解释、客套话、Markdown 标题、代码块;只输出 3 行 Markdown 列表。
        """ + latexFormattingRule

    /// 构造 prompt。`context` 由 `StudySuggestionsContext` 提供,内部由
    /// `LLMClient` 之外的 View / ViewModel 准备(避免循环依赖)。
    static func makePrompt(_ context: StudySuggestionsContext) -> LLMPrompt {
        let userJSON = encodeContext(context)
        return LLMPrompt(
            system: defaultSystem,
            messages: [.user(userJSON)],
            sensitivity: context.bodyStatusSuggestion == nil ? .ordinary : .healthSensitive
        )
    }

    /// 解析 LLM 输出为 `[StudySuggestion]`。
    /// Parse LLM output into `[StudySuggestion]`.
    /// 行格式:`- **<icon> <title>** — <description>`
    /// Line format: `- **<icon> <title>** — <description>`
    /// 解析失败返回 `nil`,UI 端应回退到本地建议。
    /// Returns `nil` on failure; the UI should fall back to local suggestions.
    static func parse(_ output: String) -> [StudySuggestion]? {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var results: [StudySuggestion] = []
        for line in lines {
            // 仅解析以 "- **" 开头的行
            guard line.hasPrefix("- **") || line.hasPrefix("-**") else { continue }
            // 提取 **...** 之间的 icon + title
            guard let boldRange = line.range(of: "**"),
                  let boldEnd = line.range(of: "**", range: boldRange.upperBound..<line.endIndex) else { continue }
            let boldContent = String(line[boldRange.upperBound..<boldEnd.lowerBound])
            // 在 boldContent 中找第一个空格分隔 icon / title
            let parts = boldContent.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let icon = String(parts.first ?? "lightbulb.fill")
            let title = String(parts.count > 1 ? parts[1] : Substring(boldContent))
            // 提取 — 之后的描述
            let afterBold = line[boldEnd.upperBound...]
            let descText: String
            if let dashRange = afterBold.range(of: "—") {
                descText = String(afterBold[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if let dashRange = afterBold.range(of: "-") {
                // fallback to ASCII dash
                descText = String(afterBold[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                descText = String(afterBold).trimmingCharacters(in: .whitespaces)
            }
            guard !descText.isEmpty else { continue }
            results.append(StudySuggestion(
                icon: icon,
                title: title,
                description: descText,
                priority: .medium,
                color: .blue
            ))
        }
        return results.isEmpty ? nil : Array(results.prefix(3))
    }

    // MARK: - Context Encoder (上下文序列化)

    private static func encodeContext(_ c: StudySuggestionsContext) -> String {
        // 简化版:只输出与决策相关的字段(避免 token 爆炸)
        let gradeCount = c.grades.count
        let weakSubjects = c.grades.isEmpty
            ? "无"
            : Dictionary(grouping: c.grades, by: \.subject)
                .map { (subject, items) in "\(subject)=\(String(format: "%.1f", items.map(\.score).reduce(0, +) / Double(items.count)))" }
                .sorted()
                .joined(separator: ", ")
        let mistakeCount = c.mistakeSets.count
        let upcoming = c.examSets
            .filter { $0.examDate >= c.now && $0.examDate <= Calendar.current.date(byAdding: .day, value: 14, to: c.now) ?? c.now }
            .prefix(5)
            .map { "\($0.subject)/\($0.name)(\($0.examDate.formatted(date: .abbreviated, time: .omitted)))" }
            .joined(separator: ", ")
        let body = c.bodyStatusSuggestion.map { "体力=\($0.title)" } ?? "无"
        return """
        当前日期:\(c.now.formatted(date: .abbreviated, time: .omitted))
        成绩数:\(gradeCount),各科均分:{\(weakSubjects)}
        错题数:\(mistakeCount)
        未来 14 天考试:\(upcoming.isEmpty ? "无" : upcoming)
        身体状态:\(body)
        """
    }
}

// MARK: - 2) Mistake Analysis (错题 AI 解析)

/// 错题 AI 解析 prompt 工厂。
/// Mistake AI analysis prompt factory. Output format: 4 fixed sections
/// (`## 错因分析` / `## 错因标签` / `## 正确思路` / `## 类似题建议`) for consistent UI rendering.
enum MistakeAnalysisLLM {
    static let defaultSystem: String = """
        你是错题分析专家。给定错题内容,结合题目内容分析用户可能的心理和习惯原因(例如概念混淆、计算粗心、跳步、审题不清等),输出 Markdown 总结,中文。
        严格使用以下结构(每个 ## 标题独占一行,小标题顺序固定):

        ## 错因分析
        - 知识点: <知识点定位>
        - 思维习惯: <分析思维习惯,例如概念混淆/跳步/思维定势等>
        - 情绪状态: <分析答题时的可能情绪状态,如焦虑/急躁/紧张/疲劳等>
        - 行为模式: <分析行为模式,如计算粗心/审题不清/笔误等>

        ## 错因标签
        <根据上述分析,提取 1-3 个对应的标准错因标签,用英文逗号分隔。标准标签必须从以下集合中选择:概念混淆, 计算粗心, 跳步, 审题不清, 思维定势, 逻辑不严密, 考试焦虑, 急躁粗心, 笔误, 遗漏条件>

        ## 正确思路
        <3-6 行,分步骤展示解题路径,必要时用列表>

        ## 类似题建议
        <1-3 条,具体可练习的方向>

        ## 错误模式
        {"pattern_ids":["condition_omission"],"confidence":0.0,"evidence":"用一句话指出证据"}

        pattern_ids 只能从以下 ID 中选择: condition_omission, concept_confusion, formula_misuse, calculation_error, unit_error, incomplete_reading, logic_jump, boundary_omission, memory_error, unclear_expression, method_selection, other。没有足够证据时返回空数组。

        严禁输出解释、客套话、代码块语言标签。错误模式段中的 JSON 必须是单行、可直接解析的合法 JSON。
        """ + latexFormattingRule

    /// 构造 prompt。
    /// `mistake` 字段为空时自动用 `(空)` 占位,避免 LLM 误判。
    static func makePrompt(
        subject: String,
        title: String,
        question: String,
        wrongSolution: String,
        correctSolution: String,
        reason: String
    ) -> LLMPrompt {
        let user = """
        学科:\(subject.isEmpty ? "(未填)" : subject)
        标题:\(title.isEmpty ? "(未填)" : title)
        题干:
        \(question.isEmpty ? "(空)" : question)
        错解:
        \(wrongSolution.isEmpty ? "(空)" : wrongSolution)
        正解:
        \(correctSolution.isEmpty ? "(空)" : correctSolution)
        学生自述错因:
        \(reason.isEmpty ? "(空)" : reason)
        """
        return LLMPrompt(system: defaultSystem, messages: [.user(user)])
    }

    /// 从 AI 解析的完整文本中解析出 "## 错因标签" 这一节的标签列表。
    /// Parse tag list under "## 错因标签" from the LLM output.
    static func parseTags(from text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var foundSection = false
        var sectionContent = ""
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("##") {
                if trimmed.contains("错因标签") {
                    foundSection = true
                } else if foundSection {
                    break
                }
            } else if foundSection {
                if !trimmed.isEmpty {
                    if sectionContent.isEmpty {
                        sectionContent = trimmed
                    } else {
                        sectionContent += " " + trimmed
                    }
                }
            }
        }
        
        if sectionContent.isEmpty {
            return []
        }
        
        return sectionContent
            .components(separatedBy: CharacterSet(charactersIn: ",，"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Extract the "正确思路" section from the LLM output.
    static func parseCorrectApproach(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var foundSection = false
        var sectionLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("##") {
                if trimmed.contains("正确思路") {
                    foundSection = true
                } else if foundSection {
                    break
                }
            } else if foundSection {
                sectionLines.append(line)
            }
        }
        
        if sectionLines.isEmpty {
            return text
        }
        
        return sectionLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract the "错因分析" section from the LLM output.
    static func parseErrorReason(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var foundSection = false
        var sectionLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("##") {
                if trimmed.contains("错因分析") {
                    foundSection = true
                } else if foundSection {
                    break
                }
            } else if foundSection {
                sectionLines.append(line)
            }
        }
        
        if sectionLines.isEmpty {
            return ""
        }
        
        return sectionLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse the structured error-pattern JSON without making the rest of the
    /// Markdown response depend on JSON parsing.
    static func parsePatternResult(from text: String) -> MistakePatternAIResult? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end else { return nil }
        let jsonText = String(text[start...end])
        struct Payload: Decodable {
            let pattern_ids: [String]
            let confidence: Double
            let evidence: String
        }
        guard let data = jsonText.data(using: .utf8), let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let patterns = payload.pattern_ids.compactMap { MistakePattern(rawValue: $0) }
        return MistakePatternAIResult(patternIDs: patterns, confidence: min(1, max(0, payload.confidence)), evidence: payload.evidence)
    }
}

// MARK: - 8) AI Similar Question (AI 相似题变式)

/// AI 相似题组卷 prompt 工厂。
enum SimilarQuestionLLM {
    static let defaultSystem: String = """
        你是资深的学科命题专家。基于用户提供的原题、错因和正确解法，生成一道相似的变式题。
        要求变式题考查相同的核心知识点，但具体情境或数据必须不同。
        严格使用以下 JSON 格式输出，不要包含任何 Markdown 代码块标签（如 ```json），直接输出 JSON：
        {
          "question": "<变式题题目内容（支持 Markdown / LaTeX）>",
          "correctSolution": "<变式题的正确解法，分步骤详细说明>"
        }
        """ + latexFormattingRule

    static func makePrompt(
        subject: String,
        title: String,
        originalQuestion: String,
        correctSolution: String,
        errorReason: String
    ) -> LLMPrompt {
        let user = """
        学科:\(subject.isEmpty ? "(未填)" : subject)
        原题标题:\(title.isEmpty ? "(未填)" : title)
        原题内容:
        \(originalQuestion.isEmpty ? "(空)" : originalQuestion)
        原题正解:
        \(correctSolution.isEmpty ? "(空)" : correctSolution)
        原错因:
        \(errorReason.isEmpty ? "(空)" : errorReason)
        """
        return LLMPrompt(system: defaultSystem, messages: [.user(user)])
    }
}

// MARK: - 8b) AI Similar Question Grading (AI 变式题判分)

/// AI 变式题判分 prompt 工厂。
/// 把"AI 变式题 + 标准解法 + 用户的 Markdown 作答"一起喂给 LLM,让 LLM 给出
/// 评分、扣分点和订正建议。判分结果会作为"用户是否答对"的依据反馈到原题掌握度。
enum SimilarQuestionGradingLLM {
    static let defaultSystem: String = """
        你是严格的学科阅卷老师。学生对一道 AI 生成的变式题提交了 Markdown 格式的作答,
        你需要对照"标准解法"判分,并给出可操作的订正建议。
        输出使用 Markdown,严格使用以下结构(每个 ## 标题独占一行,顺序固定):

        ## 评分
        - 得分: <0-100 的整数,只写数字>
        - 是否正确: <是 / 否>(得分 ≥ 80 视为正确)

        ## 缺失/错误步骤
        <2-6 条 bullet,按"关键步骤"逐项对照,指出学生漏掉 / 写错的点;
        若作答完全正确,这一段写"- 无明显问题"。>

        ## 订正建议
        <2-5 句,具体到该题的关键步骤,告诉学生应该怎么补;允许使用 Markdown 列表。>

        严禁输出解释、客套话、JSON、代码块语言标签。
        不要重复原题或标准解法全文;只引用与扣分相关的关键步骤。
        """ + latexFormattingRule

    /// 构造 prompt。
    /// - Parameters:
    ///   - subject: 学科(可空)
    ///   - question: AI 生成的变式题题干
    ///   - correctSolution: AI 给出的标准解法
    ///   - userAnswer: 学生的 Markdown 作答
    static func makePrompt(
        subject: String,
        question: String,
        correctSolution: String,
        userAnswer: String
    ) -> LLMPrompt {
        let user = """
        学科:\(subject.isEmpty ? "(未填)" : subject)

        --- 变式题题干 ---
        \(question.isEmpty ? "(空)" : question)

        --- 标准解法 ---
        \(correctSolution.isEmpty ? "(空)" : correctSolution)

        --- 学生作答(可能为空或包含不完整步骤) ---
        \(userAnswer.isEmpty ? "(空)" : userAnswer)
        """
        return LLMPrompt(system: defaultSystem, messages: [.user(user)])
    }

    /// 解析 LLM 输出为结构化的判分结果。解析失败 → 返回 `nil`,UI 端应回退到本地提示。
    /// 仅提取"评分"段;其余 Markdown 文本(`gradingDetail`)原样返回,直接渲染。
    static func parse(_ output: String) -> GradingResult? {
        let sections = parseSections(output)
        guard let evaluation = sections["评分"] else { return nil }
        // 提取 0-100 的整数
        let scoreRegex = try? NSRegularExpression(pattern: "(\\d{1,3})", options: [])
        let nsEvaluation = evaluation as NSString
        let range = NSRange(location: 0, length: nsEvaluation.length)
        var score: Int? = nil
        if let match = scoreRegex?.firstMatch(in: evaluation, options: [], range: range),
           match.numberOfRanges > 1 {
            let r = match.range(at: 1)
            if r.location != NSNotFound {
                score = Int(nsEvaluation.substring(with: r))
            }
        }
        guard let score, (0...100).contains(score) else { return nil }
        let isCorrect = score >= 80
        // 拼接除"评分"段外的所有 section 作为可读详情
        let detail = sections
            .filter { $0.key != "评分" }
            .map { (key, value) in "## \(key)\n\(value)" }
            .joined(separator: "\n\n")
        return GradingResult(score: score, isCorrect: isCorrect, detail: detail)
    }

    /// 判分结果。`score` 0-100,`isCorrect` 由 score >= 80 推断,`detail` 包含
    /// "缺失/错误步骤"和"订正建议"两段(原样 Markdown,直接交给 `MarkdownView` 渲染)。
    struct GradingResult: Equatable {
        let score: Int
        let isCorrect: Bool
        let detail: String
    }

    // MARK: - Helpers

    /// 解析 `## 标题\n...\n## 标题\n...` 这种 section 结构。
    private static func parseSections(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = output.components(separatedBy: .newlines)
        var currentTitle: String? = nil
        var currentBody: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                if let t = currentTitle {
                    result[t] = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                }
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentBody = []
            } else if currentTitle != nil {
                currentBody.append(raw)
            }
        }
        if let t = currentTitle {
            result[t] = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}

// MARK: - 3) Weekly Report Summary (周报 AI 总结)

/// 周/月报 AI 总结 prompt 工厂。
enum WeeklyReportLLM {
    static let defaultSystem: String = """
        你是 StudyPulse 学习报告分析师。基于给定的周/月数据,生成 200-400 字的中文 Markdown 总结。
        严格使用以下结构(每个 ## 标题独占一行,顺序固定):

        ## 整体表现
        <1-2 句总评 + 关键数字(学习时长 / 成绩数 / 错题数)>

        ## 学科亮点
        <1-3 条,基于数据中的强项 / 进步>

        ## 改进建议
        <1-3 条,基于数据中的弱项 / 错题 / 持续下滑>

        不要重复输入数据;不要输出客套话、JSON、代码块。
        """ + latexFormattingRule

    /// 当本周期有日记数据(diaryCount > 0)且用户未关闭元认知反思开关时使用的扩展 system prompt。
    /// 在原 3 段后追加第 4 段 `## 元认知反思`,引导用户自我觉察。
    /// Extended system prompt used when the period has diary data
    /// (diaryCount > 0) and the metacognition toggle is on. Appends a 4th
    /// `## 元认知反思` section to guide user self-reflection.
    static let extendedSystemWithMetacognition: String = """
        你是 StudyPulse 学习报告分析师。基于给定的周/月数据,生成 200-500 字的中文 Markdown 总结。
        严格使用以下结构(每个 ## 标题独占一行,顺序固定):

        ## 整体表现
        <1-2 句总评 + 关键数字(学习时长 / 成绩数 / 错题数)>

        ## 学科亮点
        <1-3 条,基于数据中的强项 / 进步>

        ## 改进建议
        <1-3 条,基于数据中的弱项 / 错题 / 持续下滑>

        ## 元认知反思
        <1-2 句,基于心情 / 精力数据与学习表现的关联,引导自我觉察。例如:低精力高错题时指出"疲惫时易出错";情绪稳定时鼓励保持。>

        不要重复输入数据;不要输出客套话、JSON、代码块。
        """ + latexFormattingRule

    static func makePrompt(_ data: WeeklyReportManager.ReportData, includeMetacognition: Bool = true) -> LLMPrompt {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let daily = data.dailyStudyMinutes
            .map { "\(f.string(from: $0.date))=\($0.minutes)m" }
            .joined(separator: ", ")
        let subs = data.subjectDistribution
            .map { "\($0.subject)=\($0.mistakeCount)(\(String(format: "%.0f%%", $0.percentage)))" }
            .joined(separator: ", ")

        // 日记维度:仅当有数据 + includeMetacognition=true 时才输出扩展 system + 日记上下文。
        // Diary dimension: only emit extended system + diary context when data
        // exists AND `includeMetacognition` is true.
        let hasDiary = data.diaryCount > 0 && includeMetacognition
        let systemPrompt = hasDiary ? extendedSystemWithMetacognition : defaultSystem

        var userLines: [String] = [
            "报告周期:\(data.period.displayName)(\(f.string(from: data.startDate)) ~ \(f.string(from: data.endDate)))",
            "总学习时长(分钟):\(data.totalStudyMinutes)",
            "完成的番茄数:\(data.sessionCount)",
            "平均番茄时长(分钟):\(String(format: "%.1f", data.averageSessionMinutes))",
            "成绩数:\(data.gradeCount)",
            "平均得分率:\(String(format: "%.0f%%", data.averageScoreRate * 100))",
            "错题数:\(data.mistakeCount)",
            "考试数:\(data.examCount)",
            "强项学科:\(data.topSubject ?? "无")",
            "弱势学科:\(data.weakestSubject ?? "无")",
            "错题学科分布:{\(subs.isEmpty ? "无" : subs)}",
            "每日学习分钟数:{\(daily.isEmpty ? "无" : daily)}"
        ]

        if hasDiary {
            let moodStr = data.averageMoodScore.map { String(format: "%.1f", $0) } ?? "无"
            let energyStr = data.averageEnergyScore.map { String(format: "%.1f", $0) } ?? "无"
            let moodDistStr = data.moodDistribution
                .map { "\($0.emoji) \($0.count)次" }
                .joined(separator: ", ")
            userLines.append("日记条目数:\(data.diaryCount)")
            userLines.append("平均心情(1-5):\(moodStr)")
            userLines.append("平均精力(1-5):\(energyStr)")
            userLines.append("高频情绪:{\(moodDistStr.isEmpty ? "无" : moodDistStr)}")
            userLines.append("低能量标签次数:\(data.lowEnergyTagCount)(焦虑/疲惫/烦躁/迷茫)")
        }

        let user = userLines.joined(separator: "\n")
        return LLMPrompt(
            system: systemPrompt,
            messages: [.user(user)],
            sensitivity: hasDiary ? .healthSensitive : .ordinary
        )
    }
}

// MARK: - 6) Comprehensive Exam Score Prediction (综合考试 AI 预测)

/// 综合考试预测的 AI 第二意见 prompt 工厂。
/// 调用方先跑本地算法拿到 per-subject + total 的预测,再调用 LLM 给出"总分二次意见"。
enum ComprehensiveScorePredictionLLM {
    static let defaultSystem: String = """
        你是 StudyPulse 的考试预测分析师。基于给定的综合考试默认预测结果(各科 + 总分),给出"二次意见"。
        严格使用以下 Markdown 结构(每个 ## 标题独占一行,顺序固定):

        ## AI 总分预测
        - 点估计: <整数,基于 default 预测上下浮动>
        - 区间: <下限> ~ <上限>(用整数)
        - 置信度: <高 / 中 / 低>(根据各科样本量与波动判断)

        ## 各科关键观察
        <1-2 行/科,聚焦波动最大 / 最稳定 / 趋势最关键的科目>

        ## 总分风险点
        <1-3 条,影响总分达成的可能风险,每条 1 行>

        ## 复习建议
        <1-3 条,基于各科状态的优先级建议,每条 1 行>

        不要重复输入数据;不要输出客套话、JSON、代码块。
        """ + latexFormattingRule

    /// 构造 prompt。
    static func makePrompt(
        exam: comprehensiveExam,
        target: ComprehensivePredictionTarget
    ) -> LLMPrompt {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let subjectLines = target.perSubject
            .map { item -> String in
                let r = item.result
                let range = "\(Int(r.lowerBound.rounded()))~\(Int(r.upperBound.rounded()))"
                let n = r.usedSampleSize
                let half = String(format: "%.1f", r.halfWidth)
                return "  - \(item.subject): 点估计=\(Int(r.predicted.rounded())), 95% CI=[\(range)], ±\(half) pts, n=\(n), 满分=\(Int(r.fullScore.rounded()))"
            }
            .joined(separator: "\n")
        let totalHalf = (target.totalUpper - target.totalLower) / 2.0
        let user = """
        综合考试名称:\(exam.name)
        考试日期:\(f.string(from: exam.examDate))
        距离考试:\(max(0, Calendar.current.dateComponents([.day], from: Date(), to: exam.examDate).day ?? 0)) 天
        学科数:\(target.perSubject.count)
        满分合计:\(Int(target.totalFull.rounded()))

        --- 各科默认预测 ---
        \(subjectLines.isEmpty ? "(无)" : subjectLines)

        --- 总分默认预测 ---
        点估计:\(Int(target.totalPredicted.rounded()))
        95% 区间:[\(Int(target.totalLower.rounded())), \(Int(target.totalUpper.rounded()))]
        区间半宽:±\(String(format: "%.1f", totalHalf))
        """
        return LLMPrompt(system: defaultSystem, messages: [.user(user)])
    }
}

// MARK: - 5) Score Prediction (预测分数 AI 分析)

/// 预测分数的 AI 补充分析 prompt 工厂。
/// 调用方先跑本地 `ScorePredictor` 拿到默认预测结果,再调用 LLM 给出"二次意见"
/// (可能给出不同的预测区间、关键驱动因素、风险点、复习建议)。
enum ScorePredictionLLM {
    static let defaultSystem: String = """
        你是 StudyPulse 的考试预测分析师。基于给定的历史成绩、错题复习情况和默认算法的预测结果,给出"二次意见"。
        严格使用以下 Markdown 结构(每个 ## 标题独占一行,顺序固定):

        ## AI 预测分数
        - 点估计: <整数,满分 = (满分),允许 ±3 分浮动>
        - 区间: <下限> ~ <上限>(用整数)
        - 置信度: <高 / 中 / 低>(根据样本量与波动判断)

        ## 关键驱动因素
        <3-5 条,基于成绩趋势 / 错题状态,每条 1 行>

        ## 风险点
        <1-3 条,影响达成的可能风险,每条 1 行>

        ## 复习建议
        <1-3 条,基于错题结构给出的具体方向,每条 1 行>

        不要重复输入数据;不要输出客套话、JSON、代码块。
        """ + latexFormattingRule

    /// 构造 prompt。
    /// - Parameters:
    ///   - exam: 目标考试
    ///   - history: 同科目历史成绩
    ///   - defaultResult: 本地 ScorePredictor 算出的结果
    ///   - fullScore: 满分
    ///   - mistakeContext: 同科目错题上下文(可空)
    static func makePrompt(
        exam: Exam,
        history: [Grade],
        defaultResult: ScorePredictionResult,
        fullScore: Double,
        mistakeContext: MistakeContext
    ) -> LLMPrompt {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let historyLines = history.sorted(by: { $0.date < $1.date })
            .suffix(15)
            .map { g in
                let full = g.fullScore ?? fullScore
                return "\(f.string(from: g.date))  \(Int(g.score.rounded()))/\(Int(full.rounded()))  \(g.examName.isEmpty ? "(无标题)" : g.examName)"
            }
            .joined(separator: "\n")
        let recentScores: [Double] = history.suffix(5).map { $0.score }
        let recentMean: Double = recentScores.isEmpty ? 0 : recentScores.reduce(0, +) / Double(recentScores.count)
        let user = """
        学科:\(exam.subject)
        考试名称:\(exam.name)
        考试日期:\(f.string(from: exam.examDate))
        距离考试:\(max(0, Calendar.current.dateComponents([.day], from: Date(), to: exam.examDate).day ?? 0)) 天
        满分:\(Int(fullScore))

        --- 历史成绩(最多 15 条,按日期升序) ---
        \(historyLines.isEmpty ? "(无)" : historyLines)
        历史样本数:\(history.count)
        最近 5 次均分:\(String(format: "%.1f", recentMean))

        --- 默认算法预测 ---
        点估计:\(Int(defaultResult.predicted.rounded()))
        95% 区间:[\(Int(defaultResult.lowerBound.rounded())), \(Int(defaultResult.upperBound.rounded()))]
        区间半宽:±\(String(format: "%.1f", defaultResult.halfWidth))
        窗口:\(Int(defaultResult.windowDays)) 天 / EWMA \(Int(defaultResult.halfLifeDays)) 天
        样本量:\(defaultResult.usedSampleSize)
        """
        + (mistakeContext.reviewedMistakeCount > 0
           ? """

        --- 错题复习状态 ---
        已复习错题数:\(mistakeContext.reviewedMistakeCount)
        平均掌握度:\(String(format: "%.0f%%", mistakeContext.averageMastery * 100))
        总曝光次数:\(mistakeContext.totalExposureCount)
        """
           : "\n--- 错题复习状态 ---\n(本科目暂无错题数据)\n")
        return LLMPrompt(system: defaultSystem, messages: [.user(user)])
    }
}

// MARK: - 7) AI Discussion (深入探讨)

/// "深入探讨" 对话页 prompt 工厂。
/// 把预测数据作为 system 上下文,让 LLM 基于此与用户多轮对话。
enum AIDiscussionLLM {
    /// 默认 system prompt(包含用户语言指引)
    /// - Parameters:
    ///   - context: 预测 / 错题 / 考试等结构化上下文
    ///   - previousAIPrediction: 上一次的 AI 预测原文(用于在 system prompt 中显式标注"这是你刚才的输出")
    static func defaultSystem(context: String, previousAIPrediction: String?) -> String {
        let previousBlock: String
        if let prev = previousAIPrediction, !prev.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            previousBlock = """

            ========================================
            你刚才已经给出的预测(用户会基于此继续提问,务必主动引用 / 衔接):
            ========================================
            \(prev)
            """
        } else {
            previousBlock = ""
        }
        return """
        你是 StudyPulse 的 AI 学习助手。用户会基于下面这段"预测 / 分析上下文",以及你刚才给出的预测,继续深入讨论。
        回答要:
        1. 严格基于上下文提供的数据;不要编造成绩 / 错题 / 考试信息;
        2. 优先给出可操作建议(分科目 / 错题 / 时间分配等),1-3 句起步,长时用列表;
        3. 使用 Markdown 渲染(标题 / 列表 / 表格 / 行内代码);
        4. 跟随用户提问的语言(中文 / 英文 / 日文 / 韩文等);
        5. **重要**:如果 system prompt 包含"你刚才已经给出的预测",请主动引用 / 衔接那段内容(例如"在我刚才的预测中..." / "基于上一次的预测..."),不要把对话当成全新话题。

        --- 预测 / 分析上下文 ---
        \(context)\(previousBlock)
        """ + latexFormattingRule
    }
}

// MARK: - Mistake Debate (错题辩论)

/// 辩论模式的追问强度。值类型可安全地跨并发任务传递。
nonisolated enum MistakeDebateDifficulty: String, CaseIterable, Sendable {
    case gentle
    case strict
    case tricky

    var title: String {
        switch self {
        case .gentle: return "温和"
        case .strict: return "严格"
        case .tricky: return "刁钻"
        }
    }

    var icon: String {
        switch self {
        case .gentle: return "leaf"
        case .strict: return "checkmark.seal"
        case .tricky: return "bolt"
        }
    }

    var instruction: String {
        switch self {
        case .gentle:
            return "语气鼓励，先肯定合理部分；每次只指出一个关键漏洞，给学生足够提示。"
        case .strict:
            return "像认真批改的出题老师；要求学生说明每一步依据，发现跳步或概念混淆就追问。"
        case .tricky:
            return "像竞赛或口试老师；主动寻找边界条件、隐藏假设和反例，但仍必须基于题目事实。"
        }
    }

    var localizedTitle: String { title.localized() }
}

/// 苏格拉底式错题辩论 prompt。
enum MistakeDebateLLM {
    static func defaultSystem(context: String, difficulty: MistakeDebateDifficulty) -> String {
        """
        你是 StudyPulse 的出题老师，正在和学生进行“错题辩论”。你的目标不是直接讲答案，而是让学生为自己的思路辩护，从而发现并修正深层理解漏洞。

        辩论规则：
        1. 当前难度是【\(difficulty.title)】：\(difficulty.instruction)
        2. 每次只问一个清晰、可回答的问题，优先质疑学生刚刚说出的具体一步。
        3. 不要一开始公布标准答案；除非学生已经连续解释清楚，才用简短总结确认关键原则。
        4. 如果学生回答正确，继续追问“为什么”或边界条件；如果回答有误，先指出矛盾并给一个小提示，不要替他完成整道题。
        5. 可以要求学生重算、举反例、解释公式来源或说明某一步成立的条件。不要编造题目中没有的信息。
        6. 对话语言跟随学生；保持像真实老师一样简洁、有针对性。每轮最多 2 个短段落。
        7. 当学生已经完整辩护时，输出“辩论总结”，列出：守住的关键点、最终修正点、下次遇到同类题的自检问题。

        --- 错题资料（仅作为事实依据） ---
        \(context)
        """ + latexFormattingRule
    }
}

// MARK: - 4) Free-form Chat (AI 助手)

/// AI 助手对话 prompt 工厂。
enum LLMChatLLM {
    static let defaultSystem: String = """
        你是 StudyPulse 的 AI 学习助手。你能基于用户的成绩、错题、考试和身体数据回答问题。
        必须使用用户提问的语言作答：用户用中文就用中文，用英文才用英文。不要默认改成英文。
        回答尽量使用 Markdown(标题 / 列表 / 表格 / 代码块)。
        如果用户问的与学习数据无关,可以正常回答;不要主动编造未提供的个人数据。
        """ + latexFormattingRule
}

// MARK: - 9) Home Ask (主页 AI 提问: 路由 + 回答 两阶段)

/// 主页"AI 提问"的两阶段 prompt 工厂:
/// 1. 路由阶段:让 LLM 判断回答用户问题需要哪些数据类别
/// 2. 回答阶段:把抓取到的数据 + 用户问题合并,让 LLM 给出最终答案
enum HomeAskRouterLLM {
    /// 用户可路由到的数据类别
    enum Category: String, Codable, CaseIterable {
        case body      // 身体状态(HRV / RHR / 睡眠 / 呼吸 / 锻炼 / 基线)
        case grades    // 成绩(单科 / 综合 / 历史 / 即将考试)
        case trends    // 趋势(周报 / 月报 AI 总结 / 成绩走势统计)
        case review    // 复习(错题 / 待复习闪卡 / 复习计划)
    }

    /// 路由结果
    struct Routing: Codable, Equatable {
        var categories: [Category]
        var reasoning: String
    }

    /// 路由阶段的 system prompt
    static let defaultSystem: String = """
        你是 StudyPulse 的"数据路由器"。用户会问一个学习 / 身体相关的问题,你的任务
        是判断回答这个问题需要哪些数据,从以下类别中选 1-4 个:

        - "body":   身体状态数据(HRV / 静息心率 / 恢复性睡眠 / 呼吸 / 今日锻炼)
        - "grades": 成绩数据(单科 / 综合预测 / 历史成绩 / 即将到来的考试)
        - "trends": 趋势数据(周报 / 月报 AI 总结 / 成绩走势统计)
        - "review": 复习数据(错题 / 待复习闪卡 / 复习计划)

        严格输出 JSON,无任何额外文字、Markdown、代码块、解释。
        Schema:{"categories": ["body","review"], "reasoning": "<20 字内中文解释>"}
        """

    /// 构造路由 prompt
    static func makePrompt(question: String) -> LLMPrompt {
        return LLMPrompt(
            system: defaultSystem,
            messages: [.user(question)]
        )
    }

    /// 解析 LLM 路由输出。容错:解析失败返回包含全部分类 + 空 reasoning 的兜底。
    /// Parse LLM routing output. Fallback: if parsing fails, return all
    /// categories + empty reasoning (so the answer stage still gets data).
    static func parse(_ output: String) -> Routing {
        // 尝试提取最外层 JSON 对象(LLM 可能夹杂 <think> / ```json ```)
        // Extract the outermost JSON object (LLM may embed `<think>` / ```json```)
        guard let jsonString = extractFirstJSONObject(output) else {
            return Routing(
                categories: Category.allCases,
                reasoning: "解析失败,默认提供全部数据"
            )
        }
        guard let data = jsonString.data(using: .utf8),
              let routing = try? JSONDecoder().decode(Routing.self, from: data) else {
            return Routing(
                categories: Category.allCases,
                reasoning: "解析失败,默认提供全部数据"
            )
        }
        // 至少返回 1 个类别;空数组兜底为全部
        // At least 1 category; empty array → fallback to all
        let cats = routing.categories.isEmpty ? Category.allCases : routing.categories
        return Routing(categories: cats, reasoning: routing.reasoning)
    }

    /// 简易 JSON 提取器 / Naïve outermost-JSON extractor:
    /// - 按字符扫描,维护 brace depth + string 状态
    /// - 支持 \" 转义;遇到配对的 `{...}` 立即返回子串
    /// - Scans char-by-char, tracks brace depth and string state;
    ///   returns the substring on the first balanced `{...}`.
    private static func extractFirstJSONObject(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        for idx in text.indices[start...] {
            let ch = text[idx]
            if escape { escape = false; continue }
            if ch == "\\" { escape = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...idx])
                }
            }
        }
        return nil
    }
}

/// 第二阶段:把路由抓到的数据 + 用户问题合并,让 LLM 给出最终答案
enum HomeAskAnswerLLM {
    /// 回答阶段 system prompt
    static let defaultSystem: String = """
        你是 StudyPulse 的学习顾问。基于系统提供的"问题"和"相关数据",给出准确、可操作的回答。
        回答要求:
        1. **严格基于提供的数据**:不要编造任何未在数据中出现的成绩 / 错题 / 身体指标;
        2. **优先引用具体数字**:学科、分数、时间、HRV 值、置信区间等;
        3. **给出可执行建议**:分学科 / 时间块 / 强度 / 休息时机等;
        4. **1-3 句起步,长时用列表 / 表格**;
        5. **使用 Markdown 渲染**:标题 / 列表 / 表格 / 行内代码;
        6. **跟随用户语言**(中文 / 英文 / 日文 / 韩文等),默认中文;
        7. **如果数据不足以回答问题**,直接说缺什么,不要硬猜;
        8. 不要再做路由判断,你的任务只是基于现有数据回答。
        """ + latexFormattingRule

    /// 构造回答 prompt
    /// - Parameters:
    ///   - question: 用户当前轮的问题
    ///   - activeCategories: 路由阶段确定的数据类别
    ///   - dataSections: 已经被路由选中的数据(Markdown 文本)
    static func makePrompt(
        question: String,
        activeCategories: [HomeAskRouterLLM.Category],
        dataSections: [String]
    ) -> LLMPrompt {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let catLine = activeCategories.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
        let dataBlock = dataSections.isEmpty
            ? "(本轮未选择任何数据类别 — 你只能基于通用学习常识回答,且必须说明这一点)"
            : dataSections.joined(separator: "\n\n")
        let user = """
        当前时间:\(f.string(from: Date()))
        本次路由选中的数据类别:[\(catLine)]

        ==== 相关数据 ====
        \(dataBlock)

        ==== 用户问题 ====
        \(question)
        """
        return LLMPrompt(
            system: defaultSystem,
            messages: [.user(user)],
            sensitivity: activeCategories.contains(.body) || activeCategories.contains(.trends)
                ? .healthSensitive
                : .ordinary
        )
    }
}

// MARK: - 8) Body Radar AI Suggestion (恢复雷达 AI 建议)

/// 身体雷达 / 恢复准备度的 AI 增强 prompt 工厂。
/// 调用方先跑本地 `StudyReadinessAlgorithm.recommend` 拿到默认建议,
/// 再用 `buildBodyReadinessContext(...)` 把所有今日信号 + 30 天基线 +
/// 预校准分数一起喂给 LLM,让 LLM 在本地算法基础上产出更个性化、可操作的建议。
///
/// UI 层:保留本地算法的 `icon / priority / color`(因为这些与强度是绑定的),
/// 替换 `title / description` 为 LLM 输出。解析失败 → 回退本地版本。
enum BodyRadarLLM {
    /// 默认 system prompt
    static let defaultSystem: String = """
        你是 StudyPulse 的"恢复准备度"教练。给定用户今日的身体信号(HRV / 静息心率 / 呼吸 /
        恢复性睡眠 / 今日锻炼 / 近期活动)+ 30 天个人基线 + 本地算法的"强度 + 焦点"建议 +
        近期学习压力标注,你的任务是:基于完整数据校准本地建议,产出更具体、更可操作的中文建议。
        严格使用以下 Markdown 结构(每个 ## 标题独占一行,顺序固定):

        ## 强度
        <peak / deepFocus / steady / light / recovery — 与本地一致或根据数据微调 1 档>

        ## 标题
        <8-18 字,贴切今日状态的标题(中文,不要用"建议"两个字开头)>

        ## 建议
        <2-5 句,具体到学科分配 / 时间块 / 强度 / 休息时机。允许使用 Markdown 列表。
        若提供了「近期学习压力标注」,请针对性回应其中提到的具体难题。
        不要再写"依据"段,所有依据会单独输出。>

        ## 依据
        <3-6 条 bullet,每条引用 1 个具体信号 vs 基线 / 参考值的对比,
        例如"- 恢复性睡眠 6.2h — vs 你的 30 天均值 7.4h(↓1.2h,校准分 0.42)"。
        若有「近期学习压力标注」,至少 1 条引用具体事件。>

        不要重复输入数据;不要输出客套话、JSON、代码块;不要解释你做了什么。
        """

    /// 构造 prompt。`context` 由 `StudyReadinessAlgorithm.buildBodyReadinessContext(...)` 给出。
    static func makePrompt(_ context: BodyReadinessContext) -> LLMPrompt {
        let user = encodeContext(context)
        return LLMPrompt(system: defaultSystem, messages: [.user(user)], sensitivity: .healthSensitive)
    }

    /// 解析 LLM 输出,合并到 `fallback`(保留 icon / priority / color)。
    /// Parse LLM output, merge into `fallback` (keep icon / priority / color).
    /// 解析失败 → 返回 `nil`,UI 端应回退到 `fallback`。
    /// Returns `nil` on failure; the UI should fall back to `fallback`.
    ///
    /// 期望的 4 段 / Expected 4 sections:
    ///   ## 强度  →  仅在 BodyRadarLLM 内部用于协议一致性,UI 不直接展示
    ///   ## 标题  →  StudySuggestion.title
    ///   ## 建议  →  StudySuggestion.description 第一段
    ///   ## 依据  →  拼到 description 末尾(以 "依据:" 开头)
    static func parse(_ output: String, fallback: StudySuggestion) -> StudySuggestion? {
        let sections = parseSections(output)
        guard let title = sections["标题"], !title.isEmpty else { return nil }
        let advice = sections["建议"] ?? ""
        let reasoning = sections["依据"] ?? ""
        let description: String
        if advice.isEmpty && reasoning.isEmpty {
            return nil
        } else if reasoning.isEmpty {
            description = advice
        } else if advice.isEmpty {
            description = "\n依据:\(reasoning)"
        } else {
            description = advice + "\n\n依据:\n" + reasoning
        }
        return StudySuggestion(
            icon: fallback.icon,
            title: title,
            description: description,
            priority: fallback.priority,
            color: fallback.color
        )
    }

    // MARK: - Context encoder

    private static func encodeContext(_ c: BodyReadinessContext) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let b = c.bodyStatus
        let ref = c.ageReference
        func bl(_ stats: PersonalBaselineStats?) -> String {
            guard let s = stats else { return "无" }
            return String(format: "均值=%.2f σ=%.2f n=%d", s.mean, s.stdDev, s.sampleCount)
        }
        func val(_ v: Double?, format: String = "%.2f") -> String {
            guard let v = v else { return "无" }
            return String(format: format, v)
        }
        func cal(_ cal: CalibratedValue) -> String {
            let src = cal.comparedTo == .personal ? "个人基线" : "年龄参考"
            return String(format: "校准=%.2f (%@)", cal.score, src)
        }
        let hrvLine: String
        if let z = c.hrv.zScore {
            hrvLine = "HRV: \(val(c.hrv.todayHRV))ms, 类别=\(c.hrv.category.rawValue), z=\(String(format: "%+.2fσ", z))"
        } else {
            hrvLine = "HRV: \(val(c.hrv.todayHRV))ms, 类别=\(c.hrv.category.rawValue)"
        }
        let sleepBreakdown: String
        if let deep = b.deepSleepHours, let rem = b.remSleepHours {
            sleepBreakdown = String(format: "深睡=%.1fh + REM=%.1fh", deep, rem)
        } else if let deep = b.deepSleepHours {
            sleepBreakdown = String(format: "深睡=%.1fh", deep)
        } else if let rem = b.remSleepHours {
            sleepBreakdown = String(format: "REM=%.1fh", rem)
        } else {
            sleepBreakdown = "无细分"
        }
        let local = c.localSuggestion.map { s in
            "标题=\(s.title); 强度=\(s.priority) ; 颜色=\(colorName(s.color))"
        } ?? "无"
        // 近期学习压力标注(7 天内,用户在心率峰值处登记的难题)
        let annos = c.recentDifficultyAnnotations
        let annoBlock: String
        if annos.isEmpty {
            annoBlock = "无近期压力标注"
        } else {
            let lines = annos.prefix(15).map { a -> String in
                let hrStr = a.heartRate.map { " HR=\(Int($0))bpm" } ?? ""
                let note = a.note.isEmpty ? "(无文字)" : a.note
                let ts = f.string(from: a.timestamp)
                return "- [\(ts)]\(hrStr): \(note)"
            }
            annoBlock = "共 \(annos.count) 条\n" + lines.joined(separator: "\n")
        }
        // 近期心情/精力日记(7 天内,主观恢复度)
        // Recent mood/energy diary entries (last 7 days, subjective recovery)
        let moods = c.recentMoodEntries
        let moodBlock: String
        if moods.isEmpty {
            moodBlock = "无近期心情记录"
        } else {
            let avgMood = moods.map { $0.moodScore }.reduce(0, +) / moods.count
            let avgEnergy = moods.map { $0.energyScore }.reduce(0, +) / moods.count
            let lowEnergyTags = moods.filter { DiaryEntry.lowEnergyTags.contains($0.energyTag) }.count
            let lines = moods.prefix(10).map { e -> String in
                let ts = f.string(from: e.date)
                let preview = e.content.isEmpty ? "(无文字)" : String(e.content.prefix(40))
                return "- [\(ts)] 心情=\(e.moodScore)/5 精力=\(e.energyScore)/5 标签=\(e.energyTag): \(preview)"
            }
            moodBlock = """
            共 \(moods.count) 条 | 平均心情=\(String(format: "%.1f", Double(avgMood))) 平均精力=\(String(format: "%.1f", Double(avgEnergy))) 低精力标签数=\(lowEnergyTags)
            \(lines.joined(separator: "\n"))
            """
        }
        return """
        当前时间:\(f.string(from: c.now))
        年龄:\(c.age.map { "\($0)岁" } ?? "未知(用 adult 兜底)")

        ===== 今日身体信号 =====
        \(hrvLine)
        静息心率: \(val(b.restingHeartRate, format: "%.0f bpm"))   \(cal(c.rhrCalibration))
        呼吸: \(val(b.respiratoryRate, format: "%.0f 次/分"))   \(cal(c.rrCalibration))
        恢复性睡眠: \(val(b.restorativeSleepHours, format: "%.1fh"))  (\(sleepBreakdown))   \(cal(c.sleepCalibration))
        总睡眠: \(val(b.lastNightSleepHours, format: "%.1fh"))(类别: \(b.sleepQuality.rawValue))
        今日锻炼: \(val(b.exerciseMinutesToday, format: "%.0f min"))   \(cal(c.exerciseCalibration))
        最近一次心率: \(val(b.latestHeartRate, format: "%.0f bpm"))(若比静息高 ≥25 bpm 视为活动后)

        ===== 30 天个人基线 =====
        HRV: \(bl(c.baselines.hrv))
        静息心率: \(bl(c.baselines.restingHeartRate))
        呼吸: \(bl(c.baselines.respiratoryRate))
        恢复性睡眠: \(bl(c.baselines.restorativeSleepHours))
        总睡眠: \(bl(c.baselines.sleepHours))
        今日锻炼: \(bl(c.baselines.exerciseMinutes))
        年龄参考范围(RHR low/mid/high): \(Int(ref.restingHeartRate.low))/\(Int(ref.restingHeartRate.mid))/\(Int(ref.restingHeartRate.high))

        ===== 近期学习压力标注(7 天内)=====
        \(annoBlock)

        ===== 近期心情/精力(7 天内)=====
        \(moodBlock)

        ===== 本地算法已给出建议 =====
        \(local)

        (用户也会看到这条本地建议作为兜底;你的输出应在此基础上做得更具体、引用上面的数据点)
        """
    }

    // MARK: - Helpers

    /// 解析 `## 标题\\nxxx\\n## 建议\\n...` 这种 section 结构。
    private static func parseSections(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = output.components(separatedBy: .newlines)
        var currentTitle: String? = nil
        var currentBody: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                if let t = currentTitle {
                    result[t] = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                }
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentBody = []
            } else if currentTitle != nil {
                currentBody.append(raw)
            }
        }
        if let t = currentTitle {
            result[t] = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func priorityName(_ p: StudySuggestion.Priority) -> String {
        switch p {
        case .high: return "high"
        case .medium: return "medium"
        case .low: return "low"
        }
    }

    private static func colorName(_ color: Color) -> String {
        switch color {
        case .green: return "green"
        case .blue: return "blue"
        case .orange: return "orange"
        case .red: return "red"
        default: return "other"
        }
    }
}

// MARK: - Habit Insight AI Interpretation
enum HabitInsightLLM {
    static let defaultSystem = """
    你是 StudyPulse 的学习习惯洞察教练。根据最近 90 天按星期和时段聚合的学习数据，以及本地检测出的模式，输出具体、可执行的中文解读。
    严格使用以下结构：
    ## 模式
    <peakEfficiency / procrastination / streakDay / weakDay>
    ## 标题
    <8-18 字中文标题>
    ## 解读
    <2-4 句，引用具体数据点分析可能原因>
    ## 建议
    <2-4 条可执行的 Markdown bullet>
    不要输出客套话、JSON 或代码块。
    """

    static func makePrompt(_ context: HabitInsightContext) -> LLMPrompt {
        let insights = context.insights.map { "- \($0.patternKind.rawValue): \($0.title), confidence=\(String(format: "%.2f", $0.confidence))" }.joined(separator: "\n")
        let buckets = context.allBuckets.map { "\($0.weekday)/\($0.hourSlot.displayName): n=\($0.sessionCount), avg=\(String(format: "%.1f", $0.avgDurationMinutes))m, completed=\(String(format: "%.2f", $0.completedRatio)), peak=\(String(format: "%.2f", $0.peakIntensityRatio))" }.joined(separator: "\n")
        let user = "语言：\(context.languageCode)\n今日 weekday：\(context.todayWeekday)\n总样本：\(context.sessionTotal)\n\n本地模式：\n\(insights.isEmpty ? "无" : insights)\n\n聚合数据：\n\(buckets)"
        return LLMPrompt(system: defaultSystem, messages: [.user(user)])
    }

    static func parse(_ output: String, fallback: HabitInsight) -> HabitInsight? {
        var sections: [String: String] = [:]
        var current: String?
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") { current = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces); sections[current!] = "" }
            else if let current {
                let separator = sections[current, default: ""].isEmpty ? "" : "\n"
                sections[current, default: ""] += separator + line
            }
        }
        guard let title = sections["标题"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let interpretation = sections["解读"]?.trimmingCharacters(in: .whitespacesAndNewlines), !interpretation.isEmpty,
              let advice = sections["建议"]?.trimmingCharacters(in: .whitespacesAndNewlines), !advice.isEmpty else { return nil }
        return HabitInsight(id: fallback.id, patternKind: fallback.patternKind, weekday: fallback.weekday, hourSlot: fallback.hourSlot,
            title: title, description: interpretation + "\n\n建议：\n" + advice, icon: fallback.icon, color: fallback.color,
            priority: fallback.priority, confidence: fallback.confidence)
    }
}

struct HabitInsightContext: Sendable {
    let insights: [HabitInsight]
    let allBuckets: [WeekdayHourSlotBucket]
    let todayWeekday: Int
    let todayBestSlot: HabitInsight?
    let sessionTotal: Int
    let languageCode: String
}

// MARK: - 9) Subject Mastery Radar AI

enum SubjectRadarLLM {
    private static let chineseSystem = """
        你是 StudyPulse 的学习分析教练。输入是用户最近 30 天各科目的六维掌握度数据：知识点覆盖、复习频率、错题率（已反向为越高越好）、平均分、学习时长、HRV 表现。请找出最需要优先干预的弱势科目，并给出具体可执行的学习建议。
        严格输出以下 Markdown 结构，不要输出 JSON、代码块或客套话：

        ## 弱势科目
        <列出 1-3 个科目，并引用最关键的低分维度>

        ## 学习建议
        <3-5 条具体建议，包含科目、复习频率或时间块>
        输出总长度不超过 500 个汉字；每条建议不超过 60 个汉字。
        """

    private static let englishSystem = """
        You are StudyPulse's learning analysis coach. The input contains each subject's six dimensions from the last 30 days: knowledge coverage, review frequency, mistake performance (higher is better), average score, study time, and HRV performance. Identify the subjects that need priority intervention and provide concrete, actionable study advice.
        Strictly output this Markdown structure. Do not output JSON, code fences, or pleasantries:

        ## Weak Subjects
        <List 1-3 subjects and cite their most important low dimensions.>

        ## Study Advice
        <Give 3-5 concrete suggestions, including subjects, review frequency, or time blocks.>
        Keep the total response under 500 words; keep each recommendation under 60 words.
        """

    static func makePrompt(_ snapshots: [SubjectRadarSnapshot], languageCode: String? = nil) -> LLMPrompt {
        let lines = snapshots.map { s in
            String(format: "- %@: coverage %.0f%%, review %.0f%%, mistake performance %.0f%%, average score %.0f%%, study time %d min, HRV performance %.0f%%; grades %d, mistakes %d, reviewed %d.",
                   s.subject, s.coverage * 100, s.reviewFrequency * 100,
                   s.mistakeRate * 100, s.averageScore * 100, s.studyMinutes,
                   s.hrvPerformance * 100, s.gradeCount, s.mistakeCount, s.reviewedMistakes)
        }.joined(separator: "\n")
        let language = languageCode?.lowercased() ?? ""
        let systemBase = language.hasPrefix("zh") ? chineseSystem : englishSystem
        let outputLanguage: String
        if language == "zh-hant" || language == "zh-tw" {
            outputLanguage = "请使用繁體中文回答。"
        } else if language.hasPrefix("zh") {
            outputLanguage = "请使用简体中文回答。"
        } else if language.hasPrefix("ja") {
            outputLanguage = "Respond in Japanese."
        } else if language.hasPrefix("ko") {
            outputLanguage = "Respond in Korean."
        } else {
            outputLanguage = "Respond in English."
        }
        let system = systemBase + "\n" + outputLanguage
        let user = language.hasPrefix("zh") ? "最近 30 天数据：\n\(lines)" : "Data from the last 30 days:\n\(lines)"
        return LLMPrompt(system: system, messages: [.user(user)], sensitivity: .healthSensitive)
    }

    static func clean(_ output: String) -> String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 10) AI Quiz Generation (AI 自测出题)

/// AI 自测出题 prompt 工厂
enum QuizGenerationLLM {
    static let defaultSystem: String = """
        你是严格而专业的学科教育命题专家。基于用户提供的参考内容（如该科目的历史错题或指定的章节知识点），生成 5 到 10 道具有针对性的自测题目。
        要求：
        1. 题目类型必须包含“选择题 (multiple_choice)”和“填空题 (fill_in_the_blank)”。
        2. 出题必须考查核心知识点，题目难度合理。
        3. 选择题必须包含 4 个选项，每个选项必须以 "A. ", "B. ", "C. ", "D. " 开头。
        4. 填空题的题干中必须使用“_____”（五个下划线）来指示空格位置。填空题的选项为 null 或空数组。
        5. 严格使用以下 JSON 数组格式输出，不要包含任何 Markdown 代码块标签（如 ```json），直接输出 JSON：
        [
          {
            "type": "multiple_choice",
            "question": "<题干内容，支持 Markdown / LaTeX 数学公式>",
            "options": ["A. <选项A内容>", "B. <选项B内容>", "C. <选项C内容>", "D. <选项D内容>"],
            "correctAnswer": "<正确选项，例如 A/B/C/D 中的一个字符>",
            "solution": "<本题的详细步骤解析，支持 Markdown / LaTeX>"
          },
          {
            "type": "fill_in_the_blank",
            "question": "<题干内容（填空位置用 _____ 表示），支持 Markdown / LaTeX>",
            "options": null,
            "correctAnswer": "<正确填空文本，若有多种正确形式可用斜杠 / 隔开>",
            "solution": "<本题的详细步骤解析，支持 Markdown / LaTeX>"
          }
        ]
        """ + latexFormattingRule

    /// 构造自测出题 prompt
    static func makePrompt(
        subject: String,
        scope: String, // "mistakes" 或 "chapter"
        referenceMistakes: [MistakeNote],
        chapterTopic: String,
        count: Int
    ) -> LLMPrompt {
        var contextStr = ""
        if scope == "mistakes" {
            contextStr = "自测范围：基于该学科的错题\n参考错题列表（共\(referenceMistakes.count)道）：\n"
            for (idx, m) in referenceMistakes.enumerated() {
                contextStr += """
                \(idx + 1). 错题标题: \(m.title)
                   原题干: \(m.originalQuestion)
                   正确解法: \(m.correctSolution)
                   我的错因分析: \(m.errorReason)
                
                """
            }
        } else {
            contextStr = "自测范围：基于指定的章节/知识点\n章节知识点描述：\(chapterTopic)\n"
        }

        let user = """
        学科：\(subject)
        题目数量：\(count) 道题
        \(contextStr)
        请根据上述背景生成 \(count) 道题目（选择题与填空题混合，各占一部分）。
        """
        
        return LLMPrompt(system: defaultSystem, messages: [.user(user)])
    }
}

// MARK: - 10b) AI Quiz Grading (AI 自测判分)

/// AI 自测判分 prompt 工厂
enum QuizGradingLLM {
    static let defaultSystem: String = """
        你是严谨认真的学科阅卷老师。用户完成了一套 AI 生成的自测卷，你需要根据“题目”、“标准正确答案及解析”以及“用户实际作答”进行打分和评估。
        要求：
        1. 评分满分为 100 分。将 100 分平分到每道题（例如 10 道题，每题 10 分）。
        2. 选择题：完全匹配才得分。例如正确答案是 A，用户选 A 则得满分，否则得 0 分。
        3. 填空题：对比标准答案，如果意思完全正确或数学/化学等式等价，应给满分或相应的分数。
        4. 如果单题得分率为 80% 或以上，判定该题 isCorrect = true，否则 isCorrect = false。
        5. 为每道题提供具体的“feedback”（评分依据、指出哪里写错、应如何订正，支持 Markdown）。
        6. 严格使用以下 JSON 格式输出，不要包含任何 Markdown 代码块标签（如 ```json），直接输出 JSON：
        {
          "totalScore": <整卷总得分，0-100的整数>,
          "results": [
            {
              "index": <题目序号，从 0 开始的整数>,
              "score": <该题得分，整数>,
              "isCorrect": <是否正确，布尔值>,
              "feedback": "<单题的判分理由与订正建议，支持 Markdown / LaTeX>"
            }
          ]
        }
        """ + latexFormattingRule

    /// 构造自测判分 prompt
    static func makePrompt(
        subject: String,
        questions: [QuizQuestion],
        userAnswers: [UUID: String]
    ) -> LLMPrompt {
        var userText = "学科：\(subject)\n\n"
        for (idx, q) in questions.enumerated() {
            let answer = userAnswers[q.id] ?? "(未作答)"
            userText += """
            --- 题目 \(idx + 1) ---
            类型: \(q.type == "multiple_choice" ? "选择题" : "填空题")
            题干: \(q.question)
            \(q.type == "multiple_choice" ? "选项: \(q.options?.joined(separator: ", ") ?? "")\n" : "")标准答案: \(q.correctAnswer)
            解析: \(q.solution)
            用户作答: \(answer)
            
            """
        }
        
        return LLMPrompt(system: defaultSystem, messages: [.user(userText)])
    }
}

// MARK: - 14) Study Session Stress Interpretation (学习会话压力解读)

/// 单次学习会话的心率压力解读 prompt 工厂。
/// 输入:会话元信息 + 心率样本 + 难题标注 + RHR 基线。
/// 输出:3 段 Markdown(`## 压力模式 / ## 触发因素 / ## 建议`)。
///
/// Prompt factory for interpreting a single study session's heart-rate
/// stress pattern. Input: session metadata + HR samples + difficulty
/// annotations + RHR baseline. Output: 3 Markdown sections.
enum StudySessionStressLLM {
    static let defaultSystem: String = """
    你是一位学习生理学专家。给定用户一次学习会话的心率曲线(采样点)、
    难题标注、静息心率基线,你的任务是解读本次会话的压力模式。
    严格使用以下 Markdown 结构(每个 ## 标题独占一行,顺序固定):

    ## 压力模式
    <2-4 句,描述本次会话心率曲线的整体形态(上升 / 平稳 / 骤升骤降 / 间歇峰值),
    引用具体 bpm 数值与时间点。>

    ## 触发因素
    <2-4 句,结合难题标注推测可能的压力源。若标注为空,基于心率峰值出现的时间点
    推测(如"会话中段出现 110bpm 峰值,可能是遇到难点")。>

    ## 建议
    <2-4 条 bullet,每条具体可执行的下一次学习改进建议,例如:
    - 难点出现时主动暂停 30 秒深呼吸
    - 把卡住的题目单独标记,会话结束后集中请教
    - 若峰值集中在某学科,下次先复习相关基础概念>

    不要重复输入数据;不要输出客套话、JSON、代码块;不要解释你做了什么。
    """ + latexFormattingRule

    static func makePrompt(
        session: StudySession,
        rhrBaseline: Double?
    ) -> LLMPrompt {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let start = session.startDate
        let durationMin = session.durationSeconds / 60
        let intensity = session.intensity.displayName

        // 心率样本(最多 30 个点,避免 prompt 过长)
        let samples = (session.heartRateSamples ?? []).prefix(30)
        let sampleLines: String
        if samples.isEmpty {
            sampleLines = "(无心率样本)"
        } else {
            sampleLines = samples.map { s in
                let offset = Int(s.timestamp.timeIntervalSince(start))
                let mm = offset / 60
                let ss = offset % 60
                return String(format: "+%02d:%02d  %.0f bpm", mm, ss, s.bpm)
            }.joined(separator: "\n")
        }

        // 难题标注
        let annos = session.difficultyAnnotations ?? []
        let annoLines: String
        if annos.isEmpty {
            annoLines = "(无标注)"
        } else {
            annoLines = annos.map { a in
                let offset = Int(a.timestamp.timeIntervalSince(start))
                let mm = offset / 60
                let ss = offset % 60
                let hrStr = a.heartRate.map { " HR=\(Int($0))" } ?? ""
                return String(format: "+%02d:%02d%@  %@", mm, ss, hrStr, a.note)
            }.joined(separator: "\n")
        }

        let rhrLine = rhrBaseline.map { String(format: "%.0f bpm", $0) } ?? "未知"
        let userText = """
        会话开始:\(f.string(from: start))
        时长:\(durationMin) 分钟
        强度档位:\(intensity)
        静息心率基线:\(rhrLine)

        ===== 心率采样(\(samples.count) 个点)=====
        \(sampleLines)

        ===== 难题标注(\(annos.count) 条)=====
        \(annoLines)
        """
        return LLMPrompt(system: defaultSystem, messages: [.user(userText)], sensitivity: .healthSensitive)
    }

    /// 解析输出:直接返回 Markdown 文本(不做结构化解析)。
    /// Parse output: return the Markdown text as-is (no structured parsing).
    static func parse(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
