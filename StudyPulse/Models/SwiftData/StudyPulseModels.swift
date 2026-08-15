//
//  StudyPulseModels.swift
//  StudyPulse
//
//  SwiftData @Model 实体层。
//  SwiftData @Model entity layer.
//
//  设计：
//  - 每个业务模型都有一个对应的 @Model 实体（SubjectEntity / GradeEntity / ...）
//  - 实体字段对应原 struct 的字段；嵌套类型（ExamTimeSlot / ReviewState / [Data]）
//    被拍平为基本类型字段（[String] / Date / @Attribute(.externalStorage) Data）
//  - 实体与 struct 互转用 toSnapshot() / init(from:)
//  - 视图层继续用原 struct（DataManager observable 暴露 [struct]），不需要改 view
//
//  Design:
//  - Each domain model has a corresponding @Model entity (SubjectEntity / GradeEntity / ...)
//
//  SCHEMA FREEZE:
//  These record definitions are part of StudyPulseSchemaV1. Do not change their
//  persisted properties in place. Introduce changed record types in a new
//  VersionedSchema and add a stage to StudyPulseMigrationPlan instead.
//  - Entity fields mirror the struct's; nested types (ExamTimeSlot / ReviewState / [Data])
//    are flattened to primitive fields ([String] / Date / @Attribute(.externalStorage) Data)
//  - Use toSnapshot() / init(from:) to convert
//  - Views keep using the struct types via DataManager's observable arrays — no view changes
//

import Foundation
import SwiftData

// MARK: - Subject
// MARK: - 科目 / Subject

/// 科目持久化实体。镜像 `Subject` 值类型。
/// Subject persistence entity. Mirrors the `Subject` value type.
@Model
final class SubjectRecord {
    /// 唯一稳定 id
    /// Unique stable id.
    @Attribute(.unique) var id: UUID
    /// 内部标识名（如 "Mathematics"）
    /// Internal identifier name (e.g. "Mathematics").
    var name: String
    /// 是否启用
    /// Whether this subject is enabled.
    var enabled: Bool
    /// 科目满分
    /// Subject full score.
    var fullScore: Double
    /// 显示名（如 "数学"）
    /// Display name (e.g. "数学").
    var displayName: String

    init(id: UUID, name: String, enabled: Bool, fullScore: Double, displayName: String) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.fullScore = fullScore
        self.displayName = displayName
    }

    convenience init(from subject: Subject) {
        self.init(
            id: subject.id,
            name: subject.name,
            enabled: subject.enabled,
            fullScore: subject.fullScore,
            displayName: subject.displayName
        )
    }

    func toSnapshot() -> Subject {
        Subject(
            id: id,
            name: name,
            displayName: displayName,
            enabled: enabled,
            fullScore: fullScore
        )
    }
}

// MARK: - Grade
// MARK: - 成绩 / Grade

/// 成绩持久化实体。镜像 `Grade` 值类型。
/// Grade persistence entity. Mirrors the `Grade` value type.
@Model
final class GradeRecord {
    // 索引: 业务高频过滤字段;SwiftData 编译器会为这些字段建 B-Tree
    // 让 SortDescriptor(\.date, order: .reverse) / subject == X 等谓词走索引
    // Indexes: high-frequency filter fields; SwiftData builds B-Tree indexes so
    // SortDescriptor(\.date, order: .reverse) / subject == X predicates are fast.
    #Index<GradeRecord>([\.subject, \.date], [\.phaseId], [\.date])

    @Attribute(.unique) var id: UUID
    /// 科目名称
    /// Subject name.
    var subject: String
    /// 实际得分
    /// Actual score.
    var score: Double
    /// 赋分时的卷面分（如浙江高考赋分制）
    /// Raw score before rank-based assignment (e.g. Zhejiang gaokao).
    var rawScore: Double?
    /// 排名
    /// Ranking (optional).
    var ranking: Int?
    /// 重要程度 1-5
    /// Importance 1-5 stars.
    var importance: Int
    /// 卷面图片（兼容旧数据，外部存储避免占内存）
    /// Exam paper image (legacy, external storage to keep memory small).
    @Attribute(.externalStorage) var image: Data?
    /// 图片文件名（新方案）
    /// Image file name (new scheme).
    var imageFileName: String?
    /// 录入日期
    /// Record date.
    var date: Date
    /// 考试名称
    /// Exam name.
    var examName: String
    /// 关联的考试 ID；nil 表示未关联考试
    var examId: UUID?
    /// 该条成绩的满分（nil = 用科目默认）
    /// Full score for this grade (nil = use subject default).
    var fullScore: Double?
    /// 归属阶段 ID（关联 StudyPhaseRecord.id），nil = 未归类
    /// Owning phase id (links to StudyPhaseRecord.id); nil = uncategorized.
    var phaseId: UUID?

    init(
        id: UUID,
        subject: String,
        score: Double,
        rawScore: Double?,
        ranking: Int?,
        importance: Int,
        image: Data?,
        imageFileName: String?,
        date: Date,
        examName: String,
        examId: UUID?,
        fullScore: Double?,
        phaseId: UUID? = nil
    ) {
        self.id = id
        self.subject = subject
        self.score = score
        self.rawScore = rawScore
        self.ranking = ranking
        self.importance = importance
        self.image = image
        self.imageFileName = imageFileName
        self.date = date
        self.examName = examName
        self.examId = examId
        self.fullScore = fullScore
        self.phaseId = phaseId
    }

    convenience init(from grade: Grade) {
        self.init(
            id: grade.id,
            subject: grade.subject,
            score: grade.score,
            rawScore: grade.rawScore,
            ranking: grade.ranking,
            importance: grade.importance,
            image: grade.image,
            imageFileName: grade.imageFileName,
            date: grade.date,
            examName: grade.examName,
            examId: grade.examId,
            fullScore: grade.fullScore,
            phaseId: grade.phaseId
        )
    }

    func toSnapshot() -> Grade {
        Grade(
            id: id,
            subject: subject,
            score: score,
            rawScore: rawScore,
            ranking: ranking,
            importance: importance,
            image: image,
            imageFileName: imageFileName,
            date: date,
            examName: examName,
            examId: examId,
            fullScore: fullScore,
            phaseId: phaseId
        )
    }
}

// MARK: - MistakeNote
// MARK: - 错题笔记 / Mistake Note

/// 错题笔记持久化实体。镜像 `MistakeNote` 值类型。
/// Mistake note persistence entity. Mirrors `MistakeNote` value type.
@Model
final class MistakeNoteRecord {
    // 索引: SRS 队列 / 科目过滤 / 日期排序
    // Indexes: SRS queue / subject filter / date sort.
    #Index<MistakeNoteRecord>([\.subject], [\.date], [\.phaseId], [\.srsNextReviewDate])

    @Attribute(.unique) var id: UUID
    /// 题目标题
    /// Mistake title.
    var title: String
    /// 所属科目
    /// Owning subject.
    var subject: String
    /// 原题内容
    /// Original question text.
    var originalQuestion: String
    /// 题目来源
    /// Source of the question.
    var source: String
    /// 录入日期
    /// Recorded date.
    var date: Date
    /// 错误原因
    /// Error reason.
    var errorReason: String
    /// 错误解法
    /// Wrong solution.
    var wrongSolution: String
    /// 正确解法
    /// Correct solution.
    var correctSolution: String

    // SRS 状态（拍平为基本字段）
    // SRS state (flattened into primitive fields)
    /// 连续答对次数
    /// Consecutive correct count.
    var srsRepetitions: Int
    /// 难度系数 SM-2 EF
    /// SM-2 ease factor.
    var srsEaseFactor: Double
    /// 当前复习间隔（天）
    /// Current review interval (days).
    var srsIntervalDays: Int
    /// 下次复习日期
    /// Next review date.
    var srsNextReviewDate: Date?
    /// 上次复习日期
    /// Last review date.
    var srsLastReviewDate: Date?
    /// 累计 Again 次数
    /// Total lapse count.
    var srsLapses: Int

    // 4 段图片（拍平为 [Data]）
    // Four image sections (flattened into [Data])
    @Attribute(.externalStorage) var questionImagesData: [Data]
    @Attribute(.externalStorage) var reasonImagesData: [Data]
    @Attribute(.externalStorage) var wrongSolutionImagesData: [Data]
    @Attribute(.externalStorage) var correctSolutionImagesData: [Data]
    /// 归属阶段 ID（关联 StudyPhaseRecord.id），nil = 未归类
    /// Owning phase id (links to StudyPhaseRecord.id); nil = uncategorized.
    var phaseId: UUID?
    /// 曝光次数：详情页 / 闪卡被打开的累计次数
    /// Exposure count: total opens of the detail page / flashcard.
    var exposureCount: Int = 0
    /// 当前掌握度（0-1）
    /// Current mastery score (0-1).
    var masteryScore: Double = 0.0
    /// 掌握度历史（JSON 编码 [MasteryHistoryEntry]）
    /// Mastery history (JSON-encoded [MasteryHistoryEntry]).
    var masteryHistoryData: Data?
    /// 手写答题历史（JSON 编码 [HandwritingAnswerEntry]）
    /// Handwriting history (JSON-encoded [HandwritingAnswerEntry]).
    var handwritingHistoryData: Data?
    /// 用户自评难度 1-5 星;0 = 未评。SRS 调权用。
    /// User-rated difficulty 1-5; 0 = unrated. Drives SRS weight.
    var difficulty: Int = 0
    /// 自由标签(平铺为 [String]);与 [MistakeNote.tags] 互转。
    /// Free-form tags (flat [String]); round-trips with [MistakeNote.tags].
    var tags: [String] = []

    init(
        id: UUID,
        title: String,
        subject: String,
        originalQuestion: String,
        source: String,
        date: Date,
        errorReason: String,
        wrongSolution: String,
        correctSolution: String,
        srsRepetitions: Int,
        srsEaseFactor: Double,
        srsIntervalDays: Int,
        srsNextReviewDate: Date?,
        srsLastReviewDate: Date?,
        srsLapses: Int,
        questionImagesData: [Data],
        reasonImagesData: [Data],
        wrongSolutionImagesData: [Data],
        correctSolutionImagesData: [Data],
        phaseId: UUID? = nil,
        exposureCount: Int = 0,
        masteryScore: Double = 0.0,
        masteryHistoryData: Data? = nil,
        handwritingHistoryData: Data? = nil,
        difficulty: Int = 0,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.subject = subject
        self.originalQuestion = originalQuestion
        self.source = source
        self.date = date
        self.errorReason = errorReason
        self.wrongSolution = wrongSolution
        self.correctSolution = correctSolution
        self.srsRepetitions = srsRepetitions
        self.srsEaseFactor = srsEaseFactor
        self.srsIntervalDays = srsIntervalDays
        self.srsNextReviewDate = srsNextReviewDate
        self.srsLastReviewDate = srsLastReviewDate
        self.srsLapses = srsLapses
        self.questionImagesData = questionImagesData
        self.reasonImagesData = reasonImagesData
        self.wrongSolutionImagesData = wrongSolutionImagesData
        self.correctSolutionImagesData = correctSolutionImagesData
        self.phaseId = phaseId
        self.exposureCount = exposureCount
        self.masteryScore = masteryScore
        self.masteryHistoryData = masteryHistoryData
        self.handwritingHistoryData = handwritingHistoryData
        self.difficulty = difficulty
        self.tags = tags
    }

    convenience init(from note: MistakeNote) {
        let srs = note.reviewState
        let historyData: Data? = note.masteryHistory.isEmpty
            ? nil
            : try? JSONEncoder().encode(note.masteryHistory)
        let handwritingData: Data? = note.handwritingHistory.isEmpty
            ? nil
            : try? JSONEncoder().encode(note.handwritingHistory)
        self.init(
            id: note.id,
            title: note.title,
            subject: note.subject,
            originalQuestion: note.originalQuestion,
            source: note.source,
            date: note.date,
            errorReason: note.errorReason,
            wrongSolution: note.wrongSolution,
            correctSolution: note.correctSolution,
            srsRepetitions: srs?.repetitions ?? 0,
            srsEaseFactor: srs?.easeFactor ?? 2.5,
            srsIntervalDays: srs?.intervalDays ?? 0,
            srsNextReviewDate: srs?.nextReviewDate,
            srsLastReviewDate: srs?.lastReviewDate,
            srsLapses: srs?.lapses ?? 0,
            questionImagesData: note.questionImages,
            reasonImagesData: note.reasonImages,
            wrongSolutionImagesData: note.wrongSolutionImages,
            correctSolutionImagesData: note.correctSolutionImages,
            phaseId: note.phaseId,
            exposureCount: note.exposureCount,
            masteryScore: note.masteryScore,
            masteryHistoryData: historyData,
            handwritingHistoryData: handwritingData,
            difficulty: note.difficulty,
            tags: note.tags
        )
    }

    func toSnapshot() -> MistakeNote {
        let reviewState: ReviewState? = {
            guard let next = srsNextReviewDate else { return nil }
            return ReviewState(
                repetitions: srsRepetitions,
                easeFactor: srsEaseFactor,
                intervalDays: srsIntervalDays,
                nextReviewDate: next,
                lastReviewDate: srsLastReviewDate,
                lapses: srsLapses
            )
        }()

        let history: [MasteryHistoryEntry] = {
            guard let data = masteryHistoryData else { return [] }
            return (try? JSONDecoder().decode([MasteryHistoryEntry].self, from: data)) ?? []
        }()

        let handwriting: [HandwritingAnswerEntry] = {
            guard let data = handwritingHistoryData else { return [] }
            return (try? JSONDecoder().decode([HandwritingAnswerEntry].self, from: data)) ?? []
        }()

        return MistakeNote(
            id: id,
            title: title,
            subject: subject,
            originalQuestion: originalQuestion,
            source: source,
            date: date,
            errorReason: errorReason,
            wrongSolution: wrongSolution,
            correctSolution: correctSolution,
            questionImages: questionImagesData,
            reasonImages: reasonImagesData,
            wrongSolutionImages: wrongSolutionImagesData,
            correctSolutionImages: correctSolutionImagesData,
            reviewState: reviewState,
            phaseId: phaseId,
            exposureCount: exposureCount,
            masteryScore: masteryScore,
            masteryHistory: history,
            handwritingHistory: handwriting,
            difficulty: difficulty,
            tags: tags
        )
    }
}

// MARK: - Exam (单科)
// MARK: - 考试(单科) / Exam (single subject)

/// 单科考试持久化实体。镜像 `Exam` 值类型。
/// Single-subject exam persistence entity. Mirrors the `Exam` value type.
@Model
final class ExamRecord {
    // 索引: examDate 用于"未来 N 天的考试"查询排序
    // Indexes: examDate for "upcoming exams in N days" query/sort.
    #Index<ExamRecord>([\.examDate], [\.phaseId])

    @Attribute(.unique) var id: UUID
    /// 考试名称
    /// Exam name.
    var name: String
    /// 考试开始日期
    /// Exam start date.
    var examDate: Date
    /// 考试结束日期（多日考试）
    /// Exam end date (for multi-day exams).
    var examEndDate: Date?
    /// 重要程度 1-5
    /// Importance 1-5 stars.
    var importance: Int
    /// 科目名称
    /// Subject name.
    var subject: String
    /// 考试别称
    /// Exam alias (e.g. "midterm").
    var examName: String
    /// 掌握程度 0-100
    /// Mastery degree 0-100.
    var masteryDegree: Int
    /// 拍平 timeSlot 起始时间
    /// Flattened timeSlot start.
    var timeSlotStart: Date?
    /// 拍平 timeSlot 结束时间
    /// Flattened timeSlot end.
    var timeSlotEnd: Date?
    /// 归属阶段 ID（关联 StudyPhaseRecord.id），nil = 未归类
    /// Owning phase id; nil = uncategorized.
    var phaseId: UUID?
    /// 考前待办清单（JSON 编码 [ExamChecklistItem]）
    /// Pre-exam checklist (JSON-encoded [ExamChecklistItem]).
    var checklistData: Data?
    /// 考场学校（SwiftData 轻量迁移需要 inline 默认值,否则老 store 打不开）
    /// Exam school (inline default required for SwiftData lightweight migration).
    var locationSchool: String = ""
    /// 教室 / 考场号
    /// Classroom / exam room.
    var locationClassroom: String = ""
    /// 座位号
    /// Seat number.
    var locationSeat: String = ""
    /// 考前 N 天倒计时通知（JSON 编码 [Int]）；nil = 字段未写入（默认计划）
    /// Pre-exam countdown days (JSON-encoded [Int]); nil = not set (use default).
    var countdownNotifyDaysData: Data?
    /// 考后复盘内容（JSON 编码 ExamReview）；nil = 尚未复盘
    /// Post-exam review content (JSON-encoded ExamReview). nil = not yet reviewed.
    var reviewData: Data?

    init(
        id: UUID,
        name: String,
        examDate: Date,
        examEndDate: Date?,
        importance: Int,
        subject: String,
        examName: String,
        masteryDegree: Int,
        timeSlotStart: Date?,
        timeSlotEnd: Date?,
        phaseId: UUID? = nil,
        checklistData: Data? = nil,
        locationSchool: String = "",
        locationClassroom: String = "",
        locationSeat: String = "",
        countdownNotifyDaysData: Data? = nil,
        reviewData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.examDate = examDate
        self.examEndDate = examEndDate
        self.importance = importance
        self.subject = subject
        self.examName = examName
        self.masteryDegree = masteryDegree
        self.timeSlotStart = timeSlotStart
        self.timeSlotEnd = timeSlotEnd
        self.phaseId = phaseId
        self.checklistData = checklistData
        self.locationSchool = locationSchool
        self.locationClassroom = locationClassroom
        self.locationSeat = locationSeat
        self.countdownNotifyDaysData = countdownNotifyDaysData
        self.reviewData = reviewData
    }

    convenience init(from exam: Exam) {
        let checklistData: Data? = exam.checklist.isEmpty ? nil : try? JSONEncoder().encode(exam.checklist)
        // 把 nil 和 [] 都当作 "未指定",用 nil 存；显式空数组也用 nil 存(语义上等价)
        let countdownData: Data?
        if let days = exam.countdownNotifyDays {
            countdownData = (try? JSONEncoder().encode(days)) ?? nil
        } else {
            countdownData = nil
        }
        let reviewData: Data? = exam.examReview.flatMap { try? JSONEncoder().encode($0) }
        self.init(
            id: exam.id,
            name: exam.name,
            examDate: exam.examDate,
            examEndDate: exam.examEndDate,
            importance: exam.importance,
            subject: exam.subject,
            examName: exam.examName,
            masteryDegree: exam.masteryDegree,
            timeSlotStart: exam.timeSlot?.startTime,
            timeSlotEnd: exam.timeSlot?.endTime,
            phaseId: exam.phaseId,
            checklistData: checklistData,
            locationSchool: exam.locationSchool,
            locationClassroom: exam.locationClassroom,
            locationSeat: exam.locationSeat,
            countdownNotifyDaysData: countdownData,
            reviewData: reviewData
        )
    }

    func toSnapshot() -> Exam {
        let timeSlot: ExamTimeSlot? = {
            if let s = timeSlotStart, let e = timeSlotEnd {
                return ExamTimeSlot(startTime: s, endTime: e)
            }
            return nil
        }()
        let checklist: [ExamChecklistItem] = {
            guard let data = checklistData else { return [] }
            return (try? JSONDecoder().decode([ExamChecklistItem].self, from: data)) ?? []
        }()
        let countdownDays: [Int]? = {
            guard let data = countdownNotifyDaysData else { return nil }
            return try? JSONDecoder().decode([Int].self, from: data)
        }()
        let examReview: ExamReview? = {
            guard let data = reviewData else { return nil }
            return try? JSONDecoder().decode(ExamReview.self, from: data)
        }()
        return Exam(
            id: id,
            name: name,
            date: examDate,
            importance: importance,
            subject: subject,
            examName: examName,
            masteryDegree: masteryDegree,
            timeSlot: timeSlot,
            examEndDate: examEndDate,
            phaseId: phaseId,
            checklist: checklist,
            locationSchool: locationSchool,
            locationClassroom: locationClassroom,
            locationSeat: locationSeat,
            countdownNotifyDays: countdownDays,
            examReview: examReview
        )
    }
}

// MARK: - ComprehensiveExam (综合)
// MARK: - 综合考试 / Comprehensive Exam

/// 综合考试持久化实体。镜像 `comprehensiveExam` 值类型。
/// Comprehensive exam persistence entity. Mirrors `comprehensiveExam` value type.
@Model
final class ComprehensiveExamRecord {
    // 索引: examDate 用于"未来 N 天的综合考试"查询排序
    // Indexes: examDate for "upcoming comprehensive exams in N days".
    #Index<ComprehensiveExamRecord>([\.examDate], [\.phaseId])

    @Attribute(.unique) var id: UUID
    /// 考试名称
    /// Exam name.
    var name: String
    /// 考试开始日期
    /// Exam start date.
    var examDate: Date
    /// 考试结束日期
    /// Exam end date.
    var examEndDate: Date?
    /// 重要程度 1-5
    /// Importance 1-5 stars.
    var importance: Int
    /// 拍平 [String] 科目列表
    /// Flattened [String] subject list.
    var subjects: [String]
    /// 考试别称
    /// Exam alias.
    var examName: String
    /// 掌握程度 0-100
    /// Mastery degree 0-100.
    var masteryDegree: Int
    /// 拍平 subjectTimeSlots：JSON 编码后存
    /// Flattened subjectTimeSlots: JSON-encoded.
    var subjectTimeSlotsData: Data?
    /// 归属阶段 ID（关联 StudyPhaseRecord.id），nil = 未归类
    /// Owning phase id; nil = uncategorized.
    var phaseId: UUID?

    init(
        id: UUID,
        name: String,
        examDate: Date,
        examEndDate: Date?,
        importance: Int,
        subjects: [String],
        examName: String,
        masteryDegree: Int,
        subjectTimeSlotsData: Data?,
        phaseId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.examDate = examDate
        self.examEndDate = examEndDate
        self.importance = importance
        self.subjects = subjects
        self.examName = examName
        self.masteryDegree = masteryDegree
        self.subjectTimeSlotsData = subjectTimeSlotsData
        self.phaseId = phaseId
    }

    convenience init(from exam: comprehensiveExam) {
        let slotsData: Data?
        if let slots = exam.subjectTimeSlots,
           let data = try? JSONEncoder().encode(slots) {
            slotsData = data
        } else {
            slotsData = nil
        }
        self.init(
            id: exam.id,
            name: exam.name,
            examDate: exam.examDate,
            examEndDate: exam.examEndDate,
            importance: exam.importance,
            subjects: exam.subject,
            examName: exam.examName,
            masteryDegree: exam.masteryDegree,
            subjectTimeSlotsData: slotsData,
            phaseId: exam.phaseId
        )
    }

    func toSnapshot() -> comprehensiveExam {
        let slots: [String: ExamTimeSlot]? = {
            guard let data = subjectTimeSlotsData else { return nil }
            return try? JSONDecoder().decode([String: ExamTimeSlot].self, from: data)
        }()
        return comprehensiveExam(
            id: id,
            name: name,
            date: examDate,
            importance: importance,
            subject: subjects,
            examName: examName,
            masteryDegree: masteryDegree,
            examEndDate: examEndDate,
            subjectTimeSlots: slots,
            phaseId: phaseId
        )
    }
}

// MARK: - TaskItem (作业 / 阅读材料)
// MARK: - 待办 / Task Item

/// 作业 / 阅读材料持久化实体。镜像 `TaskItem` 值类型。
/// Task item persistence entity. Mirrors `TaskItem` value type.
@Model
final class TaskItemRecord {
    // 索引: dueDate 用于按时间排序;isCompleted 用于过滤未完成任务
    // Indexes: dueDate for time sort; isCompleted for filtering open tasks.
    #Index<TaskItemRecord>([\.dueDate], [\.phaseId], [\.isCompleted])

    @Attribute(.unique) var id: UUID
    /// 任务标题
    /// Task title.
    var title: String
    /// TaskType 拍平为 rawValue
    /// TaskType flattened to rawValue.
    var typeRaw: String
    /// 截止日期
    /// Due date.
    var dueDate: Date
    /// 提醒时间
    /// Reminder date.
    var reminderDate: Date
    /// 关联科目
    /// Related subject.
    var subject: String
    /// 重要程度 1-5
    /// Importance 1-5.
    var importance: Int
    /// 备注
    /// Notes.
    var notes: String
    /// 是否已完成
    /// Whether completed.
    var isCompleted: Bool
    /// 关联 EKReminder 标识
    /// Linked EKReminder identifier.
    var reminderEventId: String?
    /// 关联 EKReminder 所在 calendar
    /// EKReminder's calendar identifier.
    var reminderCalendarId: String?
    /// 创建时间
    /// Created at.
    var createdAt: Date
    /// 归属阶段 ID（关联 StudyPhaseRecord.id），nil = 未归类
    /// Owning phase id; nil = uncategorized.
    var phaseId: UUID?
    /// Optional Coach execution metadata, encoded as JSON for schema stability.
    var coachExecutionData: Data?
    var coachGoalId: UUID?
    var coachProposalId: UUID?

    init(
        id: UUID,
        title: String,
        typeRaw: String,
        dueDate: Date,
        reminderDate: Date,
        subject: String,
        importance: Int,
        notes: String,
        isCompleted: Bool,
        reminderEventId: String?,
        reminderCalendarId: String?,
        createdAt: Date,
        phaseId: UUID? = nil,
        coachExecutionData: Data? = nil,
        coachGoalId: UUID? = nil,
        coachProposalId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.typeRaw = typeRaw
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.subject = subject
        self.importance = importance
        self.notes = notes
        self.isCompleted = isCompleted
        self.reminderEventId = reminderEventId
        self.reminderCalendarId = reminderCalendarId
        self.createdAt = createdAt
        self.phaseId = phaseId
        self.coachExecutionData = coachExecutionData
        self.coachGoalId = coachGoalId
        self.coachProposalId = coachProposalId
    }

    convenience init(from task: TaskItem) {
        self.init(
            id: task.id,
            title: task.title,
            typeRaw: task.type.rawValue,
            dueDate: task.dueDate,
            reminderDate: task.reminderDate,
            subject: task.subject,
            importance: task.importance,
            notes: task.notes,
            isCompleted: task.isCompleted,
            reminderEventId: task.reminderEventId,
            reminderCalendarId: task.reminderCalendarId,
            createdAt: task.createdAt,
            phaseId: task.phaseId,
            coachExecutionData: task.coachExecutionData,
            coachGoalId: task.coachGoalId,
            coachProposalId: task.coachProposalId
        )
    }

    func toSnapshot() -> TaskItem {
        let type = TaskType(rawValue: typeRaw) ?? .homework
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
            reminderEventId: reminderEventId,
            reminderCalendarId: reminderCalendarId,
            createdAt: createdAt,
            phaseId: phaseId,
            coachExecutionData: coachExecutionData,
            coachGoalId: coachGoalId,
            coachProposalId: coachProposalId
        )
    }
}

// MARK: - AI Coach persistence

@Model
final class CoachGoalRecord {
    @Attribute(.unique) var id: UUID
    var payload: Data
    var updatedAt: Date

    init(from goal: CoachGoal) {
        id = goal.id; payload = (try? JSONEncoder().encode(goal)) ?? Data(); updatedAt = goal.updatedAt
    }

    func toSnapshot() -> CoachGoal? { try? JSONDecoder().decode(CoachGoal.self, from: payload) }
}

@Model
final class CoachAnalysisRecord {
    @Attribute(.unique) var id: UUID
    var goalID: UUID
    var payload: Data
    var calculatedAt: Date

    init(from analysis: CoachAnalysis) {
        id = analysis.id; goalID = analysis.goalID
        payload = (try? JSONEncoder().encode(analysis)) ?? Data(); calculatedAt = analysis.calculatedAt
    }

    func toSnapshot() -> CoachAnalysis? { try? JSONDecoder().decode(CoachAnalysis.self, from: payload) }
}

@Model
final class CoachProposalRecord {
    @Attribute(.unique) var id: UUID
    var goalID: UUID
    var statusRaw: String
    var payload: Data
    var createdAt: Date

    init(from proposal: CoachProposal) {
        id = proposal.id; goalID = proposal.goalID; statusRaw = proposal.status.rawValue
        payload = (try? JSONEncoder().encode(proposal)) ?? Data(); createdAt = proposal.createdAt
    }

    func toSnapshot() -> CoachProposal? { try? JSONDecoder().decode(CoachProposal.self, from: payload) }
}

@Model
final class CoachConversationMessageRecord {
    #Index<CoachConversationMessageRecord>([\.goalID], [\.chatID], [\.createdAt])
    @Attribute(.unique) var id: UUID
    var goalID: UUID?
    /// Denormalized so chat history can be fetched without decoding payload.
    /// Optional keeps V1/V4 records migratable; new writes always populate it.
    var chatID: UUID?
    var roleRaw: String
    var payload: Data
    var createdAt: Date

    init(from message: CoachConversationMessage) {
        id = message.id; goalID = message.goalID; chatID = message.chatID; roleRaw = message.role.rawValue
        payload = (try? JSONEncoder().encode(message)) ?? Data(); createdAt = message.createdAt
    }

    func toSnapshot() -> CoachConversationMessage? { try? JSONDecoder().decode(CoachConversationMessage.self, from: payload) }
}

@Model
final class CoachChatRecord {
    #Index<CoachChatRecord>([\.goalID], [\.updatedAt])
    @Attribute(.unique) var id: UUID
    var goalID: UUID?
    /// List-facing chat fields. The payload remains the compatibility source
    /// for records written before schema V5.
    var title: String?
    var isArchived: Bool?
    var createdAt: Date?
    var payload: Data
    var updatedAt: Date

    init(from chat: CoachChat) {
        id = chat.id; goalID = chat.goalID; title = chat.title; isArchived = chat.isArchived; createdAt = chat.createdAt
        payload = (try? JSONEncoder().encode(chat)) ?? Data(); updatedAt = chat.updatedAt
    }

    func toSnapshot() -> CoachChat? { try? JSONDecoder().decode(CoachChat.self, from: payload) }

    func toSummary() -> CoachChat? {
        guard let title, let isArchived, let createdAt else { return toSnapshot() }
        return CoachChat(
            id: id,
            goalID: goalID,
            title: title,
            isArchived: isArchived,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class StudySessionRecord {
    #Index<StudySessionRecord>([\.startDate], [\.investmentTargetID])
    @Attribute(.unique) var id: UUID
    var startDate: Date
    /// Denormalized list/filter fields. Optional keeps existing V1 records
    /// readable while allowing old payloads to be backfilled lazily.
    var durationSeconds: Int?
    var intensityRaw: String?
    var completed: Bool?
    var investmentTargetKindRaw: String?
    var investmentTargetID: UUID?
    var sourceRaw: String?
    var timeZoneIdentifier: String?
    var heartRateSampleCount: Int?
    var difficultyAnnotationCount: Int?
    var payload: Data

    init(from session: StudySession) {
        id = session.id; startDate = session.startDate
        durationSeconds = session.durationSeconds
        intensityRaw = session.intensity.rawValue
        completed = session.completed
        investmentTargetKindRaw = session.investmentTarget?.kindRawValue
        investmentTargetID = session.investmentTarget?.rawID
        sourceRaw = session.source.rawValue
        timeZoneIdentifier = session.timeZoneIdentifier
        heartRateSampleCount = session.heartRateSamples?.count ?? 0
        difficultyAnnotationCount = session.difficultyAnnotations?.count ?? 0
        payload = (try? JSONEncoder().encode(session)) ?? Data()
    }

    func toSnapshot() -> StudySession? { try? JSONDecoder().decode(StudySession.self, from: payload) }

    func toSummary() -> StudySessionSummary? {
        if let durationSeconds,
           let intensityRaw,
           let intensity = StudySession.SessionIntensity(rawValue: intensityRaw),
           let completed,
           let sourceRaw,
           let source = StudySessionSource(rawValue: sourceRaw),
           let heartRateSampleCount,
           let difficultyAnnotationCount {
            let target = investmentTargetKindRaw.flatMap { kind in
                investmentTargetID.flatMap { InvestmentTarget(kindRawValue: kind, id: $0) }
            }
            return StudySessionSummary(
                id: id,
                startDate: startDate,
                durationSeconds: durationSeconds,
                intensity: intensity,
                completed: completed,
                heartRateSampleCount: heartRateSampleCount,
                difficultyAnnotationCount: difficultyAnnotationCount,
                investmentTarget: target,
                source: source,
                timeZoneIdentifier: timeZoneIdentifier
            )
        }

        // Only legacy records take this compatibility path. New records never
        // decode their telemetry payload for a list query.
        return toSnapshot().map(StudySessionSummary.init)
    }
}

// MARK: - Time Investment

@Model
final class TimeInvestmentSubjectRecord {
    #Index<TimeInvestmentSubjectRecord>([\.sortOrder], [\.isArchived])
    @Attribute(.unique) var id: UUID
    var name: String
    var symbolName: String
    var themeRaw: String
    var startDate: Date
    var sortOrder: Int
    var createdAt: Date
    var isArchived: Bool

    init(from subject: TimeInvestmentSubject) {
        id = subject.id
        name = subject.name
        symbolName = subject.symbolName
        themeRaw = subject.theme.rawValue
        startDate = subject.startDate
        sortOrder = subject.sortOrder
        createdAt = subject.createdAt
        isArchived = subject.isArchived
    }

    func apply(_ subject: TimeInvestmentSubject) {
        name = subject.name
        symbolName = subject.symbolName
        themeRaw = subject.theme.rawValue
        startDate = subject.startDate
        sortOrder = subject.sortOrder
        createdAt = subject.createdAt
        isArchived = subject.isArchived
    }

    func toSnapshot() -> TimeInvestmentSubject {
        TimeInvestmentSubject(
            id: id,
            name: name,
            symbolName: symbolName,
            theme: TimeInvestmentTheme(rawValue: themeRaw) ?? .ocean,
            startDate: startDate,
            sortOrder: sortOrder,
            createdAt: createdAt,
            isArchived: isArchived
        )
    }
}

@Model
final class SubTaskRecord {
    #Index<SubTaskRecord>([\.subjectID], [\.parentSubTaskID], [\.sortOrder], [\.isArchived])
    @Attribute(.unique) var id: UUID
    var subjectID: UUID
    var parentSubTaskID: UUID?
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var isArchived: Bool

    init(from subTask: SubTask) {
        id = subTask.id
        subjectID = subTask.subjectID
        parentSubTaskID = subTask.parentSubTaskID
        name = subTask.name
        sortOrder = subTask.sortOrder
        createdAt = subTask.createdAt
        isArchived = subTask.isArchived
    }

    func apply(_ subTask: SubTask) {
        subjectID = subTask.subjectID
        parentSubTaskID = subTask.parentSubTaskID
        name = subTask.name
        sortOrder = subTask.sortOrder
        createdAt = subTask.createdAt
        isArchived = subTask.isArchived
    }

    func toSnapshot() -> SubTask {
        SubTask(
            id: id,
            subjectID: subjectID,
            parentSubTaskID: parentSubTaskID,
            name: name,
            sortOrder: sortOrder,
            createdAt: createdAt,
            isArchived: isArchived
        )
    }
}

@Model
final class GoalRewardRecord {
    #Index<GoalRewardRecord>([\.targetID], [\.createdAt], [\.unlockedAt])
    @Attribute(.unique) var id: UUID
    var title: String
    var symbolName: String
    var targetKindRaw: String
    var targetID: UUID
    var thresholdSeconds: Int
    var createdAt: Date
    var unlockedAt: Date?

    init(from reward: GoalReward) {
        id = reward.id
        title = reward.title
        symbolName = reward.symbolName
        targetKindRaw = reward.target.kindRawValue
        targetID = reward.target.rawID
        thresholdSeconds = reward.thresholdSeconds
        createdAt = reward.createdAt
        unlockedAt = reward.unlockedAt
    }

    func apply(_ reward: GoalReward) {
        title = reward.title
        symbolName = reward.symbolName
        targetKindRaw = reward.target.kindRawValue
        targetID = reward.target.rawID
        thresholdSeconds = reward.thresholdSeconds
        createdAt = reward.createdAt
        unlockedAt = unlockedAt ?? reward.unlockedAt
    }

    func toSnapshot() -> GoalReward? {
        guard let target = InvestmentTarget(kindRawValue: targetKindRaw, id: targetID) else {
            return nil
        }
        return GoalReward(
            id: id,
            title: title,
            symbolName: symbolName,
            target: target,
            thresholdSeconds: thresholdSeconds,
            createdAt: createdAt,
            unlockedAt: unlockedAt
        )
    }
}

@Model
final class ExamSimulationRecord {
    #Index<ExamSimulationRecord>([\.createdAt], [\.statusRaw])
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var subject: String?
    var startedAt: Date?
    var endedAt: Date?
    var durationSeconds: Int?
    var statusRaw: String?
    var totalScore: Int?
    var questionCount: Int?
    var answeredCount: Int?
    var hasAnalysis: Bool?
    var payload: Data

    init(from simulation: ExamSimulation) {
        id = simulation.id
        createdAt = simulation.createdAt
        subject = simulation.subject
        startedAt = simulation.startedAt
        endedAt = simulation.endedAt
        durationSeconds = simulation.durationSeconds
        statusRaw = simulation.status.rawValue
        totalScore = simulation.totalScore
        questionCount = simulation.questionRecords.count
        answeredCount = simulation.answeredCount
        hasAnalysis = simulation.analysis != nil
        payload = (try? JSONEncoder().encode(simulation)) ?? Data()
    }

    func toSnapshot() -> ExamSimulation? {
        try? JSONDecoder().decode(ExamSimulation.self, from: payload)
    }

    func toSummary() -> ExamSimulation? {
        guard let subject, let durationSeconds, let statusRaw,
              let status = ExamSimulationStatus(rawValue: statusRaw),
              questionCount != nil, answeredCount != nil, hasAnalysis != nil else {
            return toSnapshot()
        }
        return ExamSimulation(
            id: id,
            subject: subject,
            createdAt: createdAt,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            status: status,
            questionRecords: [],
            events: [],
            totalScore: totalScore,
            analysis: nil,
            lastError: nil
        )
    }
}

@Model
final class ExamGoalRecord {
    #Index<ExamGoalRecord>([\.createdAt], [\.examDate], [\.phaseId])
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var examName: String?
    var subject: String?
    var examDate: Date?
    var currentScore: Double?
    var targetScore: Double?
    var fullScore: Double?
    var phaseId: UUID?
    var payload: Data

    init(from goal: ExamGoal) {
        id = goal.id
        createdAt = goal.createdAt
        examName = goal.examName
        subject = goal.subject
        examDate = goal.examDate
        currentScore = goal.currentScore
        targetScore = goal.targetScore
        fullScore = goal.fullScore
        phaseId = goal.phaseId
        payload = (try? JSONEncoder().encode(goal)) ?? Data()
    }

    func toSnapshot() -> ExamGoal? {
        try? JSONDecoder().decode(ExamGoal.self, from: payload)
    }

    func toSummary() -> ExamGoal? {
        guard let examName, let subject, let examDate, let currentScore,
              let targetScore, let fullScore else { return toSnapshot() }
        return ExamGoal(
            id: id,
            examName: examName,
            subject: subject,
            examDate: examDate,
            currentScore: currentScore,
            targetScore: targetScore,
            fullScore: fullScore,
            phaseId: phaseId,
            createdAt: createdAt
        )
    }
}

@Model
final class ExamPlanRecord {
    #Index<ExamPlanRecord>([\.examGoalID], [\.createdAt])
    @Attribute(.unique) var id: UUID
    var examGoalID: UUID
    var createdAt: Date
    var improvementTarget: Double?
    var summary: String?
    var modelInfo: String?
    var payload: Data

    init(from plan: ExamPlan) {
        id = plan.id
        examGoalID = plan.examGoalID
        createdAt = plan.createdAt
        improvementTarget = plan.improvementTarget
        summary = plan.summary
        modelInfo = plan.modelInfo
        payload = (try? JSONEncoder().encode(plan)) ?? Data()
    }

    func toSnapshot() -> ExamPlan? {
        try? JSONDecoder().decode(ExamPlan.self, from: payload)
    }

    func toSummary() -> ExamPlan? {
        guard let improvementTarget, let summary else { return toSnapshot() }
        return ExamPlan(
            id: id,
            examGoalID: examGoalID,
            improvementTarget: improvementTarget,
            summary: summary,
            weakPoints: [],
            phases: [],
            dailyTasks: [],
            modelInfo: modelInfo,
            createdAt: createdAt
        )
    }
}

// MARK: - UserProfile (单例)
// MARK: - 用户资料(单例) / User Profile (singleton)

/// 用户资料持久化实体。镜像 `UserProfile` 值类型（单例）。
/// User profile persistence entity. Mirrors `UserProfile` (singleton).
@Model
final class UserProfileRecord {
    @Attribute(.unique) var id: UUID
    /// 用户名
    /// Username.
    var username: String
    /// 年龄
    /// Age.
    var age: Int
    /// 教育水平（旧字段）
    /// Education level (legacy).
    var educationLevel: String
    /// 教育体系（旧字段）
    /// Education system (legacy).
    var educationSystem: String
    /// 地区（旧字段）
    /// Region (legacy).
    var region: String
    /// 拍平 [Subject]
    /// Flattened [Subject].
    var selectedSubjectsData: Data?
    /// 主题模式
    /// Theme mode.
    var theme: String
    /// 头像文件名
    /// Avatar file name.
    var avatarFileName: String?
    /// 真实姓名
    /// Real name.
    var realName: String
    /// 年级
    /// Grade (e.g. 高一).
    var grade: String
    /// 班级
    /// Class name.
    var className: String
    /// 学校
    /// School name.
    var schoolName: String
    /// 学号
    /// Student id.
    var studentId: String
    /// 入学年份
    /// Enrollment year.
    var enrollmentYear: Int
    /// 考试年份
    /// Exam year.
    var examYear: Int
    /// 教育阶段
    /// Education stage.
    var educationStage: String
    /// 地区代码
    /// Region code.
    var regionCode: String
    /// 性别
    /// Gender.
    var gender: String
    /// 目标学校
    /// Target school.
    var targetSchool: String
    /// 目标总分
    /// Target total score.
    var targetScore: Double

    init(
        id: UUID,
        username: String,
        age: Int,
        educationLevel: String,
        educationSystem: String,
        region: String,
        selectedSubjectsData: Data?,
        theme: String,
        avatarFileName: String?,
        realName: String,
        grade: String,
        className: String,
        schoolName: String,
        studentId: String,
        enrollmentYear: Int,
        examYear: Int,
        educationStage: String,
        regionCode: String,
        gender: String,
        targetSchool: String,
        targetScore: Double
    ) {
        self.id = id
        self.username = username
        self.age = age
        self.educationLevel = educationLevel
        self.educationSystem = educationSystem
        self.region = region
        self.selectedSubjectsData = selectedSubjectsData
        self.theme = theme
        self.avatarFileName = avatarFileName
        self.realName = realName
        self.grade = grade
        self.className = className
        self.schoolName = schoolName
        self.studentId = studentId
        self.enrollmentYear = enrollmentYear
        self.examYear = examYear
        self.educationStage = educationStage
        self.regionCode = regionCode
        self.gender = gender
        self.targetSchool = targetSchool
        self.targetScore = targetScore
    }

    convenience init(from profile: UserProfile) {
        let subjectsData = try? JSONEncoder().encode(profile.selectedSubjects)
        self.init(
            id: UUID(),
            username: profile.username,
            age: profile.age,
            educationLevel: profile.educationLevel,
            educationSystem: profile.educationSystem,
            region: profile.region,
            selectedSubjectsData: subjectsData,
            theme: profile.theme,
            avatarFileName: profile.avatarFileName,
            realName: profile.realName,
            grade: profile.grade,
            className: profile.className,
            schoolName: profile.schoolName,
            studentId: profile.studentId,
            enrollmentYear: profile.enrollmentYear,
            examYear: profile.examYear,
            educationStage: profile.educationStage,
            regionCode: profile.regionCode,
            gender: profile.gender,
            targetSchool: profile.targetSchool,
            targetScore: profile.targetScore
        )
    }

    func toSnapshot() -> UserProfile {
        var profile = UserProfile()
        profile.username = username
        profile.age = age
        profile.educationLevel = educationLevel
        profile.educationSystem = educationSystem
        profile.region = region
        if let data = selectedSubjectsData,
           let subjects = try? JSONDecoder().decode([Subject].self, from: data) {
            profile.selectedSubjects = subjects
        }
        profile.theme = theme
        profile.avatarFileName = avatarFileName
        profile.realName = realName
        profile.grade = grade
        profile.className = className
        profile.schoolName = schoolName
        profile.studentId = studentId
        profile.enrollmentYear = enrollmentYear
        profile.examYear = examYear
        profile.educationStage = educationStage
        profile.regionCode = regionCode
        profile.gender = gender
        profile.targetSchool = targetSchool
        profile.targetScore = targetScore
        return profile
    }
}

// MARK: - Study Phase (学期 / 假期阶段)
// MARK: - 学期 / 假期阶段 / Study Phase

/// 学期 / 假期阶段持久化实体。镜像 `StudyPhase` 值类型。
/// Study phase persistence entity. Mirrors `StudyPhase` value type.
@Model
final class StudyPhaseRecord {
    @Attribute(.unique) var id: UUID
    /// 阶段名称,如 "2026 春季学期" / "2026 暑假" / "高考冲刺"
    /// Phase name (e.g. "2026 Spring Semester", "2026 Summer Break").
    var name: String
    /// 阶段开始日期
    /// Phase start date.
    var startDate: Date
    /// 阶段结束日期
    /// Phase end date.
    var endDate: Date
    /// 是否已归档
    /// Whether archived.
    var isArchived: Bool
    /// 归档时间
    /// Archive timestamp.
    var archivedAt: Date?
    /// 目标列表(JSON 编码 [PhaseGoal],以 [Data] 形式存)
    /// Goal list (JSON-encoded [PhaseGoal], stored as [Data]).
    var goalsData: Data?
    /// 创建时间
    /// Created at.
    var createdAt: Date

    init(
        id: UUID,
        name: String,
        startDate: Date,
        endDate: Date,
        isArchived: Bool,
        archivedAt: Date?,
        goalsData: Data?,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.goalsData = goalsData
        self.createdAt = createdAt
    }

    convenience init(from phase: StudyPhase) {
        let data: Data? = try? JSONEncoder().encode(phase.goals)
        self.init(
            id: phase.id,
            name: phase.name,
            startDate: phase.startDate,
            endDate: phase.endDate,
            isArchived: phase.isArchived,
            archivedAt: phase.archivedAt,
            goalsData: data,
            createdAt: phase.createdAt
        )
    }

    func toSnapshot() -> StudyPhase {
        let goals: [PhaseGoal] = {
            guard let data = goalsData else { return [] }
            return (try? JSONDecoder().decode([PhaseGoal].self, from: data)) ?? []
        }()
        return StudyPhase(
            id: id,
            name: name,
            startDate: startDate,
            endDate: endDate,
            isArchived: isArchived,
            archivedAt: archivedAt,
            goals: goals,
            createdAt: createdAt
        )
    }
}

// MARK: - Routine Record (例程模板)
// MARK: - 例程模板 / Routine Record

/// 例程模板持久化实体。镜像 `Routine` 值类型。
/// Routine template persistence entity. Mirrors `Routine` value type.
@Model
final class RoutineRecord {
    #Index<RoutineRecord>([\.enabled], [\.createdAt], [\.phaseId])

    @Attribute(.unique) var id: UUID
    /// 例程标题
    /// Routine title.
    var title: String
    /// RoutineType 拍平为 rawValue
    /// RoutineType flattened to rawValue.
    var typeRaw: String
    /// 关联科目(可空)
    /// Related subject (optional).
    var subject: String?
    /// 触发的星期集合(Calendar.weekday: 1=周日 ... 7=周六)
    /// 拍平为 [Int]
    /// Active weekdays (Calendar.weekday: 1=Sun ... 7=Sat), flattened to [Int].
    var weekdays: [Int]
    /// 当日窗口开始时间(时:分部分有效)
    /// Day-window start time (hour/minute part is significant).
    var startTime: Date
    /// 当日窗口结束时间(时:分部分有效)
    /// Day-window end time (hour/minute part is significant).
    var endTime: Date
    /// 是否启用
    /// Whether enabled.
    var enabled: Bool
    /// 创建时间
    /// Created at.
    var createdAt: Date
    /// 归属阶段 ID
    /// Owning phase id.
    var phaseId: UUID?

    init(
        id: UUID,
        title: String,
        typeRaw: String,
        subject: String?,
        weekdays: [Int],
        startTime: Date,
        endTime: Date,
        enabled: Bool,
        createdAt: Date,
        phaseId: UUID?
    ) {
        self.id = id
        self.title = title
        self.typeRaw = typeRaw
        self.subject = subject
        self.weekdays = weekdays
        self.startTime = startTime
        self.endTime = endTime
        self.enabled = enabled
        self.createdAt = createdAt
        self.phaseId = phaseId
    }

    convenience init(from routine: Routine) {
        self.init(
            id: routine.id,
            title: routine.title,
            typeRaw: routine.type.rawValue,
            subject: routine.subject,
            weekdays: routine.weekdays,
            startTime: routine.startTime,
            endTime: routine.endTime,
            enabled: routine.enabled,
            createdAt: routine.createdAt,
            phaseId: routine.phaseId
        )
    }

    func toSnapshot() -> Routine {
        let type = RoutineType(rawValue: typeRaw) ?? .general
        return Routine(
            id: id,
            title: title,
            type: type,
            subject: subject,
            weekdays: weekdays,
            startTime: startTime,
            endTime: endTime,
            enabled: enabled,
            createdAt: createdAt,
            phaseId: phaseId
        )
    }
}

// MARK: - Routine Instance Record (例程在某天的实例)
// MARK: - 例程实例 / Routine Instance Record

/// 例程实例持久化实体。镜像 `RoutineInstance` 值类型。
/// Routine instance persistence entity. Mirrors `RoutineInstance` value type.
@Model
final class RoutineInstanceRecord {
    #Index<RoutineInstanceRecord>([\.routineId], [\.dateKey], [\.date])

    @Attribute(.unique) var id: UUID
    /// idempotency key(routineId + yyyyMMdd),业务层用
    /// 由 routineId + dateKey 复合组成;这里用 @Attribute(.unique) + 重复字段组合查重
    /// Idempotency key (routineId + yyyyMMdd); used to dedupe spawns.
    var idempotencyKey: String
    /// 所属 routine id
    /// Owning routine id.
    var routineId: UUID
    /// 所属 routine 标题(冗余)
    /// Owning routine title (denormalized).
    var title: String
    /// 例程类型
    /// Routine type.
    var typeRaw: String
    /// 关联科目(冗余)
    /// Related subject (denormalized).
    var subject: String?
    /// 当日窗口开始时间
    /// Day-window start time.
    var startTime: Date
    /// 当日窗口结束时间
    /// Day-window end time.
    var endTime: Date
    /// 当日起点
    /// Day anchor (start-of-day).
    var date: Date
    /// 当日 yyyyMMdd
    /// Day key (yyyyMMdd).
    var dateKey: String
    /// 是否已完成
    /// Whether completed.
    var isCompleted: Bool
    /// 完成时间
    /// Completion timestamp.
    var completedAt: Date?
    /// spawn 时错题数量快照
    /// Mistake count snapshot at spawn time.
    var spawnedMistakeCount: Int

    init(
        id: UUID,
        idempotencyKey: String,
        routineId: UUID,
        title: String,
        typeRaw: String,
        subject: String?,
        startTime: Date,
        endTime: Date,
        date: Date,
        dateKey: String,
        isCompleted: Bool,
        completedAt: Date?,
        spawnedMistakeCount: Int
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.routineId = routineId
        self.title = title
        self.typeRaw = typeRaw
        self.subject = subject
        self.startTime = startTime
        self.endTime = endTime
        self.date = date
        self.dateKey = dateKey
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.spawnedMistakeCount = spawnedMistakeCount
    }

    convenience init(from instance: RoutineInstance) {
        self.init(
            id: instance.id,
            idempotencyKey: instance.idempotencyKey,
            routineId: instance.routineId,
            title: instance.title,
            typeRaw: instance.type.rawValue,
            subject: instance.subject,
            startTime: instance.startTime,
            endTime: instance.endTime,
            date: instance.date,
            dateKey: instance.dateKey,
            isCompleted: instance.isCompleted,
            completedAt: instance.completedAt,
            spawnedMistakeCount: instance.spawnedMistakeCount
        )
    }

    func toSnapshot() -> RoutineInstance {
        let type = RoutineType(rawValue: typeRaw) ?? .general
        return RoutineInstance(
            id: id,
            routineId: routineId,
            title: title,
            type: type,
            subject: subject,
            startTime: startTime,
            endTime: endTime,
            date: date,
            isCompleted: isCompleted,
            completedAt: completedAt,
            spawnedMistakeCount: spawnedMistakeCount
        )
    }
}

// MARK: - Diary Entry Record (学习日记)
// MARK: - 学习日记 / Diary Entry Record

/// 学习日记持久化实体。镜像 `DiaryEntry` 值类型。
/// Diary entry persistence entity. Mirrors the `DiaryEntry` value type.
@Model
final class DiaryEntryRecord {
    // 索引: 日期排序 + 阶段过滤为高频查询
    // Indexes: date sort + phase filter are the high-frequency queries.
    #Index<DiaryEntryRecord>([\.date], [\.phaseId])

    @Attribute(.unique) var id: UUID
    /// 日记日期(当天 0 点归一化)
    /// Diary date (normalized to start-of-day).
    var date: Date
    /// 心情分值 1-5
    /// Mood score 1-5.
    var moodScore: Int
    /// 精力分值 1-5
    /// Energy score 1-5.
    var energyScore: Int
    /// 精力标签(专注/疲惫/焦虑/兴奋/平静/烦躁/迷茫 之一;可空)
    /// Energy tag (focus/tired/anxious/excited/calm/irritable/confused; may be empty).
    var energyTag: String
    /// 自由 Markdown 文字
    /// Free-form Markdown content.
    var content: String
    /// 预留未来长文 / 附件存储(当前未使用)
    /// Reserved for future long-form / attachment storage (currently unused).
    @Attribute(.externalStorage) var contentData: Data?
    /// 归属阶段 ID(关联 StudyPhaseRecord.id),nil = 未归类
    /// Owning phase id; nil = uncategorized.
    var phaseId: UUID?
    /// 创建时间
    /// Created timestamp.
    var createdAt: Date
    /// 最近更新时间
    /// Last-updated timestamp.
    var updatedAt: Date

    init(
        id: UUID,
        date: Date,
        moodScore: Int,
        energyScore: Int,
        energyTag: String,
        content: String,
        contentData: Data? = nil,
        phaseId: UUID? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.date = date
        self.moodScore = moodScore
        self.energyScore = energyScore
        self.energyTag = energyTag
        self.content = content
        self.contentData = contentData
        self.phaseId = phaseId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    convenience init(from entry: DiaryEntry) {
        self.init(
            id: entry.id,
            date: entry.date,
            moodScore: entry.moodScore,
            energyScore: entry.energyScore,
            energyTag: entry.energyTag,
            content: entry.content,
            contentData: nil,
            phaseId: entry.phaseId,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt
        )
    }

    func toSnapshot() -> DiaryEntry {
        DiaryEntry(
            id: id,
            date: date,
            moodScore: moodScore,
            energyScore: energyScore,
            energyTag: energyTag,
            content: content,
            phaseId: phaseId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
