//
//  DataExportManager.swift
//  StudyPulse
//
//  Created by Chenkai Gao on 2026/6/7.
//
//  CSV 导入/导出：
//  - 导出成绩 / 错题 / 考试（含综合考试）/ 任务（作业 + 阅读材料）到 RFC 4180 兼容的 CSV
//  - 解析时统一走支持引号转义的 parseCSVRows，能处理字段内含逗号 / 引号 / 换行
//  - 考试 type 列：single / comprehensive（同时兼容旧的中文"单科" / "综合"）
//  - 任务 type 列：homework / reading（同时兼容中文"作业" / "阅读"）
//

import Foundation
import os

/// CSV 导入导出
@MainActor
enum DataExportManager {

    // MARK: - Headers
    // MARK: - 表头 / Headers

    /// 成绩 CSV 表头
    /// Grade CSV header.
    static let gradesHeader = [
        "ID", "Subject", "Score", "FullScore", "ScoreRate",
        "RawScore", "Ranking", "Importance", "ExamName", "Date"
    ]

    /// 错题 CSV 表头
    /// 旧版：10 列 (无曝光/掌握度)，向后兼容
    /// 13 列版：尾部追加 ExposureCount / MasteryScore / MasteryHistory
    /// 15 列版：尾部再追加 Difficulty / Tags
    /// Mistake CSV header.
    /// Legacy: 10 columns (no exposure / mastery), backward compatible.
    /// 13-col version: appends ExposureCount / MasteryScore / MasteryHistory.
    /// 15-col version: appends Difficulty / Tags.
    static let mistakesHeader = [
        "ID", "Title", "Subject", "OriginalQuestion", "Source",
        "Date", "ErrorReason", "WrongSolution", "CorrectSolution", "SRSEnabled",
        "ExposureCount", "MasteryScore", "MasteryHistory",
        "Difficulty", "Tags"
    ]

    /// 考试 CSV 表头
    /// Exam CSV header.
    static let examsHeader = [
        "ID", "Name", "Subject", "Date", "ExamEndDate", "Importance", "Mastery", "Type"
    ]

    /// 任务（作业 / 阅读材料）CSV 表头
    /// Task (homework / reading material) CSV header
    static let tasksHeader = [
        "ID", "Title", "Type", "Subject", "DueDate", "ReminderTime",
        "Importance", "Notes", "IsCompleted", "CreatedAt"
    ]

    // MARK: - Export
    // MARK: - 导出 / Export

    /// 导出成绩到 CSV
    /// Export grades to CSV.
    static func exportGradesToCSV(grades: [Grade], subjects: [Subject]) -> String {
        var csv = joinRow(gradesHeader)

        for grade in grades {
            let subjectFullScore = subjects.first(where: { $0.name == grade.subject })?.fullScore ?? 100
            let fullScore = grade.fullScore ?? subjectFullScore
            let scoreRate = grade.scoreRate(subjectFullScore: subjectFullScore)

            let row: [String] = [
                grade.id.uuidString,
                grade.subject,
                String(format: "%.1f", grade.score),
                String(format: "%.1f", fullScore),
                String(format: "%.1f%%", scoreRate * 100),
                grade.rawScore.map { String(format: "%.1f", $0) } ?? "",
                grade.ranking.map { String($0) } ?? "",
                String(grade.importance),
                grade.examName,
                formatDate(grade.date)
            ]
            csv += joinRow(row)
        }

        return csv
    }

    /// 导出错题到 CSV
    /// Export mistakes to CSV.
    static func exportMistakesToCSV(mistakes: [MistakeNote]) -> String {
        var csv = joinRow(mistakesHeader)

        for mistake in mistakes {
            let masteryHistoryJSON: String = {
                guard !mistake.masteryHistory.isEmpty,
                      let data = try? JSONEncoder().encode(mistake.masteryHistory),
                      let str = String(data: data, encoding: .utf8) else { return "" }
                return escapeCSV(str)
            }()

            // tags 用 `;` 分隔(避开逗号);escapeCSV 仍会把含特殊字符的 tag 包进双引号
            // Tags are joined with `;` to dodge commas; escapeCSV still wraps tags with special chars in double quotes.
            let tagsJoined = mistake.tags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ";")

            let row: [String] = [
                mistake.id.uuidString,
                mistake.title,
                mistake.subject,
                mistake.originalQuestion,
                mistake.source,
                formatDate(mistake.date),
                mistake.errorReason,
                mistake.wrongSolution,
                mistake.correctSolution,
                mistake.isInReviewQueue ? "true" : "false",
                String(mistake.exposureCount),
                String(format: "%.4f", mistake.masteryScore),
                masteryHistoryJSON,
                String(mistake.difficulty),
                tagsJoined
            ]
            csv += joinRow(row)
        }

        return csv
    }

    /// 导出考试（单科 + 综合）到 CSV
    /// Type 列：single / comprehensive
    /// Export exams (single-subject + comprehensive) to CSV.
    /// Type column: single / comprehensive.
    static func exportExamsToCSV(exams: [Exam], comprehensiveExams: [comprehensiveExam]) -> String {
        var csv = joinRow(examsHeader)

        for exam in exams {
            let row: [String] = [
                exam.id.uuidString,
                exam.name,
                exam.subject,
                formatDate(exam.examDate),
                exam.examEndDate.map(formatDate) ?? "",
                String(exam.importance),
                String(exam.masteryDegree),
                "single"
            ]
            csv += joinRow(row)
        }

        for exam in comprehensiveExams {
            let row: [String] = [
                exam.id.uuidString,
                exam.name,
                exam.subject.joined(separator: ";"),
                formatDate(exam.examDate),
                exam.examEndDate.map(formatDate) ?? "",
                String(exam.importance),
                String(exam.masteryDegree),
                "comprehensive"
            ]
            csv += joinRow(row)
        }

        return csv
    }

    /// 导出任务（作业 + 阅读材料）到 CSV
    /// Type 列：homework / reading
    /// Export tasks (homework + reading) to CSV.
    /// - Parameter tasks: 任务列表（不再按类型拆分；同一文件内通过 Type 列区分）
    ///   The list of tasks. Single / reading are mixed; the `Type` column tells them apart.
    static func exportTasksToCSV(tasks: [TaskItem]) -> String {
        var csv = joinRow(tasksHeader)

        for task in tasks {
            let row: [String] = [
                task.id.uuidString,
                task.title,
                task.type.rawValue,
                task.subject,
                formatDate(task.dueDate),
                formatDate(task.reminderDate),
                String(task.importance),
                task.notes,
                task.isCompleted ? "true" : "false",
                formatDate(task.createdAt)
            ]
            csv += joinRow(row)
        }

        return csv
    }

    // MARK: - Import
    // MARK: - 导入 / Import

    // MARK: - Import (with diagnostics)
    // MARK: - 导入（含诊断信息）/ Import with diagnostics

    /// 从 CSV 解析成绩，附带诊断信息
    /// Parse grades from a CSV string with diagnostic info.
    static func parseGradesWithDiagnostics(
        from csvString: String,
        subjects: [Subject],
        fileName: String = "grades.csv"
    ) -> (items: [Grade], diagnostics: ImportDiagnostics) {
        let rows = parseCSVRows(csvString)
        let encoding = rows.isEmpty ? "(empty)" : "utf-8"

        guard rows.count > 0 else {
            return ([], ImportDiagnostics.failure(
                code: .E002, message: "Empty CSV", fileName: fileName, encoding: nil
            ))
        }
        let header = rows[0]
        // 行数上限:超限部分跳过,防止恶意超大行数 DoS
        // Row cap: skip rows beyond the limit to guard against huge imports.
        let dataRows = Array(rows.dropFirst().prefix(maxImportDataRows))
        guard dataRows.count > 0 else {
            return ([], ImportDiagnostics.failure(
                code: .E003, message: "Header only, no data rows", fileName: fileName,
                encoding: encoding, headerColumnCount: header.count
            ))
        }
        if header.count < gradesHeader.count {
            return ([], ImportDiagnostics.failure(
                code: .E102, message: "Header columns < expected",
                fileName: fileName, encoding: encoding, headerColumnCount: header.count,
                dataRowCount: dataRows.count,
                firstFailure: "expected=\(gradesHeader.count) got=\(header.count) headers=\(header)"
            ))
        }
        // 检查表头语义
        // Inspect header semantics.
        let expectedHeader = Set(gradesHeader)
        let actualHeader = Set(header)
        if !expectedHeader.isSubset(of: actualHeader) && !Set(expectedHeader).isSubset(of: actualHeader) {
            // 不阻止,只是警告
            // Don't block; just warn.
        }

        var grades: [Grade] = []
        var firstFailure: String?
        for (idx, row) in dataRows.enumerated() {
            if let grade = parseGradeRow(row, subjects: subjects) {
                grades.append(grade)
            } else if firstFailure == nil {
                firstFailure = "row #\(idx + 2) col=\(row.count) cells=\(row.prefix(5))"
            }
        }
        if grades.isEmpty {
            return ([], ImportDiagnostics.failure(
                code: .E004, message: "All rows failed to parse",
                fileName: fileName, encoding: encoding, headerColumnCount: header.count,
                dataRowCount: dataRows.count, firstFailure: firstFailure
            ))
        }
        let diag = ImportDiagnostics.success(
            fileName: fileName, encoding: encoding,
            headerColumnCount: header.count, dataRowCount: dataRows.count,
            successfulRowCount: grades.count
        )
        if grades.count < dataRows.count {
            return (grades, ImportDiagnostics(
                code: .E005, message: "Some rows skipped",
                fileName: fileName, encoding: encoding, headerColumnCount: header.count,
                dataRowCount: dataRows.count, successfulRowCount: grades.count,
                skippedRowCount: dataRows.count - grades.count,
                firstFailure: firstFailure
            ))
        }
        return (grades, diag)
    }

    /// 从 CSV 解析错题，附带诊断信息
    /// Parse mistakes from a CSV string with diagnostic info.
    static func parseMistakesWithDiagnostics(
        from csvString: String,
        fileName: String = "mistakes.csv"
    ) -> (items: [MistakeNote], diagnostics: ImportDiagnostics) {
        let rows = parseCSVRows(csvString)
        let encoding = rows.isEmpty ? "(empty)" : "utf-8"

        guard rows.count > 0 else {
            return ([], ImportDiagnostics.failure(
                code: .E002, message: "Empty CSV", fileName: fileName, encoding: nil
            ))
        }
        let header = rows[0]
        // 行数上限:超限部分跳过,防止恶意超大行数 DoS
        // Row cap: skip rows beyond the limit to guard against huge imports.
        let dataRows = Array(rows.dropFirst().prefix(maxImportDataRows))
        guard dataRows.count > 0 else {
            return ([], ImportDiagnostics.failure(
                code: .E003, message: "Header only, no data rows", fileName: fileName,
                encoding: encoding, headerColumnCount: header.count
            ))
        }

        var mistakes: [MistakeNote] = []
        var firstFailure: String?
        for (idx, row) in dataRows.enumerated() {
            if let mistake = parseMistakeRow(row) {
                mistakes.append(mistake)
            } else if firstFailure == nil {
                firstFailure = "row #\(idx + 2) col=\(row.count) got=\(row.prefix(5))"
            }
        }
        Log.export.info("错题 CSV 解析 / Mistakes CSV parsed: fileName=\(fileName, privacy: .public), dataRowCount=\(dataRows.count, privacy: .public), success=\(mistakes.count, privacy: .public)")
        if mistakes.isEmpty {
            return ([], ImportDiagnostics.failure(
                code: .E004, message: "All rows failed to parse",
                fileName: fileName, encoding: encoding, headerColumnCount: header.count,
                dataRowCount: dataRows.count, firstFailure: firstFailure
            ))
        }
        if mistakes.count < dataRows.count {
            return (mistakes, ImportDiagnostics(
                code: .E005, message: "Some rows skipped",
                fileName: fileName, encoding: encoding, headerColumnCount: header.count,
                dataRowCount: dataRows.count, successfulRowCount: mistakes.count,
                skippedRowCount: dataRows.count - mistakes.count,
                firstFailure: firstFailure
            ))
        }
        return (mistakes, ImportDiagnostics.success(
            fileName: fileName, encoding: encoding, headerColumnCount: header.count,
            dataRowCount: dataRows.count, successfulRowCount: mistakes.count
        ))
    }

    /// 从 CSV 解析考试，附带诊断信息
    /// Parse exams from a CSV string with diagnostic info.
    static func parseExamsWithDiagnostics(
        from csvString: String,
        fileName: String = "exams.csv"
    ) -> (single: [Exam], comprehensive: [comprehensiveExam], diagnostics: ImportDiagnostics) {
        let rows = parseCSVRows(csvString)
        let encoding = rows.isEmpty ? "(empty)" : "utf-8"

        guard rows.count > 0 else {
            return ([], [], ImportDiagnostics.failure(
                code: .E002, message: "Empty CSV", fileName: fileName, encoding: nil
            ))
        }
        let header = rows[0]
        // 行数上限:超限部分跳过,防止恶意超大行数 DoS
        // Row cap: skip rows beyond the limit to guard against huge imports.
        let dataRows = Array(rows.dropFirst().prefix(maxImportDataRows))
        guard dataRows.count > 0 else {
            return ([], [], ImportDiagnostics.failure(
                code: .E003, message: "Header only, no data rows", fileName: fileName,
                encoding: encoding, headerColumnCount: header.count
            ))
        }

        var singleExams: [Exam] = []
        var compExams: [comprehensiveExam] = []
        var firstFailure: String?
        for (idx, row) in dataRows.enumerated() {
            switch parseExamRow(row) {
            case .single(let e): singleExams.append(e)
            case .comprehensive(let e): compExams.append(e)
            case .invalid:
                if firstFailure == nil {
                    firstFailure = "row #\(idx + 2) col=\(row.count) type=\(row.last ?? "?")"
                }
            }
        }
        if singleExams.isEmpty && compExams.isEmpty {
            return ([], [], ImportDiagnostics.failure(
                code: .E004, message: "All rows failed to parse",
                fileName: fileName, encoding: encoding, headerColumnCount: header.count,
                dataRowCount: dataRows.count, firstFailure: firstFailure
            ))
        }
        let success = singleExams.count + compExams.count
        if success < dataRows.count {
            return (singleExams, compExams, ImportDiagnostics(
                code: .E005, message: "Some rows skipped",
                fileName: fileName, encoding: encoding, headerColumnCount: header.count,
                dataRowCount: dataRows.count, successfulRowCount: success,
                skippedRowCount: dataRows.count - success, firstFailure: firstFailure
            ))
        }
        return (singleExams, compExams, ImportDiagnostics.success(
            fileName: fileName, encoding: encoding, headerColumnCount: header.count,
            dataRowCount: dataRows.count, successfulRowCount: success
        ))
    }

    /// 从 CSV 解析任务，附带诊断信息
    /// Parse tasks from a CSV string with diagnostic info.
    static func parseTasksWithDiagnostics(
        from csvString: String,
        fileName: String = "tasks.csv"
    ) -> (items: [TaskItem], diagnostics: ImportDiagnostics) {
        let rows = parseCSVRows(csvString)
        let encoding = rows.isEmpty ? "(empty)" : "utf-8"

        guard rows.count > 0 else {
            return ([], ImportDiagnostics.failure(
                code: .E002, message: "Empty CSV", fileName: fileName, encoding: nil
            ))
        }
        let header = rows[0]
        // 行数上限:超限部分跳过,防止恶意超大行数 DoS
        // Row cap: skip rows beyond the limit to guard against huge imports.
        let dataRows = Array(rows.dropFirst().prefix(maxImportDataRows))
        guard dataRows.count > 0 else {
            return ([], ImportDiagnostics.failure(
                code: .E003, message: "Header only, no data rows", fileName: fileName,
                encoding: encoding, headerColumnCount: header.count
            ))
        }
        if header.count < tasksHeader.count {
            return ([], ImportDiagnostics.failure(
                code: .E102, message: "Header columns < expected",
                fileName: fileName, encoding: encoding, headerColumnCount: header.count,
                dataRowCount: dataRows.count,
                firstFailure: "expected=\(tasksHeader.count) got=\(header.count) headers=\(header)"
            ))
        }

        var tasks: [TaskItem] = []
        var firstFailure: String?
        for (idx, row) in dataRows.enumerated() {
            if let task = parseTaskRow(row) {
                tasks.append(task)
            } else if firstFailure == nil {
                firstFailure = "row #\(idx + 2) col=\(row.count) type=\(row.count > 2 ? row[2] : "?")"
            }
        }
        if tasks.isEmpty {
            return ([], ImportDiagnostics.failure(
                code: .E004, message: "All rows failed to parse",
                fileName: fileName, encoding: encoding, headerColumnCount: header.count,
                dataRowCount: dataRows.count, firstFailure: firstFailure
            ))
        }
        if tasks.count < dataRows.count {
            return (tasks, ImportDiagnostics(
                code: .E005, message: "Some rows skipped",
                fileName: fileName, encoding: encoding, headerColumnCount: header.count,
                dataRowCount: dataRows.count, successfulRowCount: tasks.count,
                skippedRowCount: dataRows.count - tasks.count, firstFailure: firstFailure
            ))
        }
        return (tasks, ImportDiagnostics.success(
            fileName: fileName, encoding: encoding, headerColumnCount: header.count,
            dataRowCount: dataRows.count, successfulRowCount: tasks.count
        ))
    }

    /// 导入文件大小上限(5MB):防止恶意超大 CSV 撑爆内存
    /// Import file-size cap (5 MB) to guard against OOM from huge CSVs.
    static let maxImportFileSizeBytes = 5 * 1024 * 1024
    /// 导入数据行上限:超过部分跳过(计入 skippedRowCount 诊断)
    /// Import row cap: rows beyond this are skipped (reported as skippedRowCount).
    static let maxImportDataRows = 10_000

    /// 读取 CSV 文本，依次尝试多种编码。
    /// 失败时返回 (.failure, nil)；成功时返回 (.success, encodingName, content)
    /// Read CSV text by trying several encodings in order.
    /// On failure returns (.failure, nil); on success (.success, encodingName, content)
    static func readCSV(from fileURL: URL) -> (result: ReadResult, encoding: String?, content: String?) {
        // 先校验文件大小,超限直接拒绝,避免读入超大文件
        // Reject oversized files before reading anything into memory.
        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maxImportFileSizeBytes {
            Log.export.warning("CSV 文件超过大小上限,拒绝导入 / CSV exceeds size cap: \(size, privacy: .public) bytes")
            return (.failure, nil, nil)
        }
        let encodings: [(String.Encoding, String)] = [
            (.utf8, "utf-8"),
            (.utf16, "utf-16"),
            (.utf16LittleEndian, "utf-16le"),
            (.utf16BigEndian, "utf-16be"),
            (.windowsCP1252, "windows-1252"),
            (.isoLatin1, "iso-8859-1")
        ]
        // iOS sandboxed fileImporter URL 需要先开 security scope
        // iOS-sandboxed fileImporter URLs need to open a security scope first.
        let needsScope = fileURL.startAccessingSecurityScopedResource()
        defer {
            if needsScope { fileURL.stopAccessingSecurityScopedResource() }
        }
        for (encoding, name) in encodings {
            if let str = try? String(contentsOf: fileURL, encoding: encoding) {
                if str.isEmpty {
                    return (.empty, name, "")
                }
                return (.success, name, str)
            }
        }
        return (.failure, nil, nil)
    }

    enum ReadResult {
        case success
        case empty
        case failure
    }

    /// 从 CSV 解析成绩
    /// Parse grades from a CSV string.
    static func parseGrades(from csvString: String, subjects: [Subject]) -> [Grade] {
        let rows = parseCSVRows(csvString)
        guard rows.count > 1 else { return [] }

        var grades: [Grade] = []
        for row in rows.dropFirst().prefix(maxImportDataRows) {
            if let grade = parseGradeRow(row, subjects: subjects) {
                grades.append(grade)
            }
        }
        return grades
    }

    /// 从 CSV 解析错题
    /// Parse mistakes from a CSV string.
    static func parseMistakes(from csvString: String) -> [MistakeNote] {
        let rows = parseCSVRows(csvString)
        Log.export.info("开始解析错题 CSV / Parsing mistakes CSV: rowCount=\(rows.count, privacy: .public)")
        guard rows.count > 1 else {
            Log.export.warning("CSV 缺少数据行 / CSV has no data rows")
            return []
        }

        var mistakes: [MistakeNote] = []
        for row in rows.dropFirst().prefix(maxImportDataRows) {
            if let mistake = parseMistakeRow(row) {
                mistakes.append(mistake)
                Log.export.debug("解析成功 / Parsed mistake: title=\(mistake.title, privacy: .public)")
            } else {
                Log.export.error("解析失败：字段数量异常 / Parse failed: unexpected field count=\(row.count, privacy: .public), expected \(mistakesHeader.count)")
            }
        }
        Log.export.info("错题 CSV 解析完成 / Finished parsing mistakes: success=\(mistakes.count, privacy: .public)")
        return mistakes
    }

    /// 从 CSV 解析考试（单科 + 综合），根据 Type 列区分
    /// Parse exams (single-subject + comprehensive) from a CSV. The Type column distinguishes them.
    static func parseExams(from csvString: String) -> (single: [Exam], comprehensive: [comprehensiveExam]) {
        let rows = parseCSVRows(csvString)
        guard rows.count > 1 else { return ([], []) }

        var singleExams: [Exam] = []
        var comprehensiveExams: [comprehensiveExam] = []

        for row in rows.dropFirst().prefix(maxImportDataRows) {
            switch parseExamRow(row) {
            case .single(let exam):
                singleExams.append(exam)
            case .comprehensive(let exam):
                comprehensiveExams.append(exam)
            case .invalid:
                continue
            }
        }

        return (singleExams, comprehensiveExams)
    }

    /// 从 CSV 解析任务（作业 + 阅读材料），根据 Type 列区分
    /// Parse tasks (homework + reading) from a CSV.
    /// - Returns: 解析得到的所有任务（成功解析的，失败行会被跳过）
    ///   All tasks that parsed successfully. Bad rows are silently skipped.
    static func parseTasks(from csvString: String) -> [TaskItem] {
        let rows = parseCSVRows(csvString)
        guard rows.count > 1 else { return [] }

        var tasks: [TaskItem] = []
        for row in rows.dropFirst().prefix(maxImportDataRows) {
            if let task = parseTaskRow(row) {
                tasks.append(task)
            }
        }
        return tasks
    }

    // MARK: - Row Parsers (private)
    // MARK: - 行级解析器（私有）/ Row parsers (private)

    private static func parseGradeRow(_ fields: [String], subjects: [Subject]) -> Grade? {
        // 兼容旧版本（无 ScoreRate 列时也能解析）
        // 旧版列数 = 10（ID, Subject, Score, FullScore, ScoreRate, RawScore, Ranking, Importance, ExamName, Date）
        // 新版同旧版，列定义未变
        // Backward compatible with legacy (works even without the ScoreRate column).
        // Legacy column count = 10. The current schema is the same 10 columns.
        guard fields.count >= gradesHeader.count else { return nil }

        let subjectName = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let score = Double(fields[2].trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let fullScore = Double(fields[3].trimmingCharacters(in: .whitespacesAndNewlines))
        // fields[4] is ScoreRate — derived, not parsed
        // fields[4] is ScoreRate, derived — not parsed.
        let rawScore = Double(fields[5].trimmingCharacters(in: .whitespacesAndNewlines))
        let ranking = Int(fields[6].trimmingCharacters(in: .whitespacesAndNewlines))
        let importance = Int(fields[7].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 3
        let examName = fields[8].trimmingCharacters(in: .whitespacesAndNewlines)
        let date = parseDate(fields[9].trimmingCharacters(in: .whitespacesAndNewlines))

        return Grade(
            subject: subjectName,
            score: score,
            rawScore: rawScore,
            ranking: ranking,
            importance: importance,
            image: nil,
            imageFileName: nil,
            date: date,
            examName: examName,
            fullScore: fullScore
        )
    }

    private static func parseMistakeRow(_ fields: [String]) -> MistakeNote? {
        // 兼容多种列数：
        //  9 列：最旧版（无 SRSEnabled）
        //  10 列：旧版（带 SRSEnabled）
        //  13 列：带 SRSEnabled + ExposureCount + MasteryScore + MasteryHistory
        //  15 列：再追加 Difficulty / Tags
        // Backward compatible with multiple column counts:
        //  9 cols: legacy (no SRSEnabled)
        //  10 cols: SRSEnabled added
        //  13 cols: + ExposureCount / MasteryScore / MasteryHistory
        //  15 cols: + Difficulty / Tags
        guard fields.count >= 9 else { return nil }

        let title = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let originalQuestion = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let source = fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
        let date = parseDate(fields[5].trimmingCharacters(in: .whitespacesAndNewlines))
        let errorReason = fields[6].trimmingCharacters(in: .whitespacesAndNewlines)
        let wrongSolution = fields[7].trimmingCharacters(in: .whitespacesAndNewlines)
        let correctSolution = fields[8].trimmingCharacters(in: .whitespacesAndNewlines)
        // SRSEnabled：true / 1 / yes / 是 视作开启 SM-2 间隔复习
        // 缺列或空值时按 false 处理
        // SRSEnabled: true / 1 / yes / 是 enable SM-2 spaced repetition.
        // Missing column or empty value → treated as false.
        let srsEnabledRaw = fields.count > 9
            ? fields[9].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            : ""
        let srsEnabled = srsEnabledRaw == "true" || srsEnabledRaw == "1" || srsEnabledRaw == "yes" || srsEnabledRaw == "是"
        let reviewState: ReviewState? = srsEnabled ? ReviewState.initial(now: date) : nil

        // 新增字段（v2.0+）：曝光次数 / 掌握度 / 掌握度历史
        // 旧版 CSV 没有这些列，按 0 / 0 / [] 处理
        // New fields (v2.0+): exposure count / mastery / mastery history.
        // Legacy CSVs without these columns fall back to 0 / 0 / [].
        let exposureCount: Int = {
            guard fields.count > 10 else { return 0 }
            let raw = fields[10].trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(raw) ?? 0
        }()
        let masteryScore: Double = {
            guard fields.count > 11 else { return 0.0 }
            let raw = fields[11].trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(raw) ?? 0.0
        }()
        let masteryHistory: [MasteryHistoryEntry] = {
            guard fields.count > 12 else { return [] }
            let raw = fields[12].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty,
                  let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([MasteryHistoryEntry].self, from: data)
            else { return [] }
            // 上限 200 条:恶意超大数组直接整段丢弃(截断会破坏时间序列语义)
            // Cap at 200 entries: oversized payloads are dropped whole.
            guard decoded.count <= 200 else {
                Log.export.warning("masteryHistory 超过 200 条,已丢弃 / masteryHistory exceeds 200 entries, dropped: count=\(decoded.count, privacy: .public)")
                return []
            }
            return decoded
        }()

        // 15 列：Difficulty / Tags
        // 15 columns: Difficulty / Tags.
        let difficulty: Int = {
            guard fields.count > 13 else { return 0 }
            let raw = fields[13].trimmingCharacters(in: .whitespacesAndNewlines)
            let v = Int(raw) ?? 0
            return max(0, min(5, v))
        }()
        let tags: [String] = {
            guard fields.count > 14 else { return [] }
            let raw = fields[14].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return [] }
            return raw
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }()

        return MistakeNote(
            title: title,
            subject: subject,
            originalQuestion: originalQuestion,
            source: source,
            date: date,
            errorReason: errorReason,
            wrongSolution: wrongSolution,
            correctSolution: correctSolution,
            reviewState: reviewState,
            exposureCount: exposureCount,
            masteryScore: masteryScore,
            masteryHistory: masteryHistory,
            difficulty: difficulty,
            tags: tags
        )
    }

    private enum ParsedExam {
        case single(Exam)
        case comprehensive(comprehensiveExam)
        case invalid
    }

    private static func parseExamRow(_ fields: [String]) -> ParsedExam {
        // 新版 8 列：ID, Name, Subject, Date, ExamEndDate, Importance, Mastery, Type
        // 旧版 7 列：ID, Name, Subject, Date, Importance, Mastery, Type
        // New schema: 8 columns including ExamEndDate.
        // Legacy: 7 columns (no ExamEndDate).
        guard fields.count >= 7 else { return .invalid }

        let name = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let subjectStr = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let date = parseDate(fields[3].trimmingCharacters(in: .whitespacesAndNewlines))

        // 8 列格式带 examEndDate
        // The 8-column layout carries examEndDate.
        let examEndDate: Date?
        let importance: Int
        let mastery: Int
        let typeRaw: String
        if fields.count >= 8 {
            examEndDate = fields[4].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : parseDate(fields[4].trimmingCharacters(in: .whitespacesAndNewlines))
            importance = Int(fields[5].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
            mastery = Int(fields[6].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            typeRaw = fields[7].trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // 兼容 7 列旧格式
            // Backward compatibility for 7-column legacy format.
            examEndDate = nil
            importance = Int(fields[4].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
            mastery = Int(fields[5].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            typeRaw = fields[6].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        switch normalizeExamType(typeRaw) {
        case .single:
            return .single(Exam(
                name: name,
                date: date,
                importance: importance,
                subject: subjectStr,
                examName: name,
                masteryDegree: mastery,
                examEndDate: examEndDate
            ))
        case .comprehensive:
            let subjects = subjectStr.components(separatedBy: ";")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return .comprehensive(comprehensiveExam(
                name: name,
                date: date,
                importance: importance,
                subject: subjects,
                examName: name,
                masteryDegree: mastery,
                examEndDate: examEndDate
            ))
        case .unknown:
            return .invalid
        }
    }

    private enum ExamKind { case single, comprehensive, unknown }

    /// 兼容英文（single / comprehensive）和中文（单科 / 综合）
    /// Accepts both English (single / comprehensive) and Chinese (单科 / 综合) labels.
    private static func normalizeExamType(_ raw: String) -> ExamKind {
        let lower = raw.lowercased()
        if lower == "single" || lower == "单科" { return .single }
        if lower == "comprehensive" || lower == "综合" { return .comprehensive }
        return .unknown
    }

    /// 解析一条任务行（兼容 homework / reading 两种类型）
    /// Parse a single task row. Accepts both English (homework / reading) and Chinese (作业 / 阅读) type values.
    private static func parseTaskRow(_ fields: [String]) -> TaskItem? {
        guard fields.count >= tasksHeader.count else { return nil }

        // 0=ID, 1=Title, 2=Type, 3=Subject, 4=DueDate, 5=ReminderTime,
        // 6=Importance, 7=Notes, 8=IsCompleted, 9=CreatedAt
        // 任务行字段顺序 / Task row field order.
        let idString = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID(uuidString: idString) ?? UUID()
        let title = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let typeRaw = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let dueDate = parseDate(fields[4].trimmingCharacters(in: .whitespacesAndNewlines))
        let reminderDate = parseDate(fields[5].trimmingCharacters(in: .whitespacesAndNewlines))
        let importance = Int(fields[6].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 3
        let notes = fields[7].trimmingCharacters(in: .whitespacesAndNewlines)
        let isCompletedRaw = fields[8].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isCompleted = (isCompletedRaw == "true" || isCompletedRaw == "1" || isCompletedRaw == "yes" || isCompletedRaw == "是")
        let createdAt = parseDate(fields[9].trimmingCharacters(in: .whitespacesAndNewlines))

        guard let type = normalizeTaskType(typeRaw) else { return nil }

        return TaskItem(
            id: id,
            title: title,
            type: type,
            dueDate: dueDate,
            reminderDate: reminderDate,
            subject: subject,
            importance: importance,
            notes: notes,
            isCompleted: isCompleted,
            reminderEventId: nil,
            reminderCalendarId: nil,
            createdAt: createdAt
        )
    }

    /// 兼容英文（homework / reading）和中文（作业 / 阅读），直接返回模型层的 `TaskType`。
    /// Accept English (homework / reading) and Chinese (作业 / 阅读). Returns the model-layer `TaskType`.
    private static func normalizeTaskType(_ raw: String) -> TaskType? {
        let lower = raw.lowercased()
        if lower == "homework" || lower == "作业" { return .homework }
        if lower == "reading" || lower == "阅读" { return .reading }
        return nil
    }

    // MARK: - CSV Low-Level
    // MARK: - CSV 底层 / CSV low-level

    /// 解析整个 CSV 字符串为行（每行是字段数组）。
    /// 支持引号转义（"" 表示字面量 "），可处理字段内含 , " 换行。
    /// Parses a whole CSV string into rows of field arrays.
    /// Handles quoted escapes (`""` → literal `"`) and fields containing commas, quotes, or newlines.
    private static func parseCSVRows(_ csvString: String) -> [[String]] {
        var cleaned = csvString
        if cleaned.hasPrefix("\u{FEFF}") {
            cleaned = String(cleaned.dropFirst())
        }

        // 统一换行符
        // Normalize line endings.
        cleaned = cleaned
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        let chars = Array(cleaned)
        var i = 0
        let n = chars.count

        while i < n {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < n && chars[i + 1] == "\"" {
                        // "" -> 字面量 "
                        // "" → literal " character.
                        currentField.append("\"")
                        i += 2
                        continue
                    } else {
                        inQuotes = false
                        i += 1
                        continue
                    }
                } else {
                    currentField.append(c)
                    i += 1
                    continue
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                    i += 1
                    continue
                } else if c == "," {
                    currentRow.append(currentField)
                    currentField = ""
                    i += 1
                    continue
                } else if c == "\n" {
                    currentRow.append(currentField)
                    // 跳过纯空行 / Skip blank lines.
                    if !(currentRow.count == 1 && currentRow[0].isEmpty) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    currentField = ""
                    i += 1
                    continue
                } else {
                    currentField.append(c)
                    i += 1
                    continue
                }
            }
        }

        // 收尾
        // Flush the trailing row/field.
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !(currentRow.count == 1 && currentRow[0].isEmpty) {
                rows.append(currentRow)
            }
        }

        return rows
    }

    /// 把一行字段拼成 CSV 行（自动加引号转义）
    /// Joins a field array into a CSV line (auto-escapes via quotes).
    private static func joinRow(_ fields: [String]) -> String {
        return fields.map(escapeCSV).joined(separator: ",") + "\n"
    }

    /// RFC 4180 转义：包含 , " 换行的字段用 " 包起来，内部 " 变 ""
    /// 另外做 CSV 公式注入防护:首字符为 = + - @ 时加 \t 前缀,
    /// 防止 Excel/Numbers 打开导出文件时执行公式(OWASP 惯例)。
    /// 导入侧所有字段均会 trim 掉 \t,导出→再导入 roundtrip 无损。
    /// RFC 4180 escape: fields containing `,` `"` or newlines are wrapped in `"`,
    /// and inner `"` becomes `""`.
    /// Also guards against CSV formula injection: a leading `= + - @` gets a
    /// `\t` prefix so Excel/Numbers won't execute it (OWASP convention).
    /// The importer trims `\t`, so export→import round-trips losslessly.
    private static func escapeCSV(_ string: String) -> String {
        var field = string
        if let first = field.first, "=+-@".contains(first) {
            field = "\t" + field
        }
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func parseDate(_ string: String) -> Date {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return Date() }

        // 依次尝试常见格式,命中即返回。
        // Try common formats in order; first hit wins.
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return Date()
    }
}
