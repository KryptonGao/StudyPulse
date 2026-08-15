//
//  TrendsViewModel.swift
//  StudyPulse
//
//  趋势页 VM。负责按 subject 分组 + 排序 + 关注科目识别。
//  Trends-page VM. Group by subject, sort, detect subjects needing attention.
//
import Foundation

struct SubjectRadarSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    let subject: String
    let coverage: Double
    let reviewFrequency: Double
    let mistakeRate: Double
    let averageScore: Double
    let studyTime: Double
    let hrvPerformance: Double
    let gradeCount: Int
    let mistakeCount: Int
    let reviewedMistakes: Int
    let studyMinutes: Int

    var values: [Double] {
        [coverage, reviewFrequency, mistakeRate, averageScore, studyTime, hrvPerformance]
    }
}

@MainActor
@Observable
final class TrendsViewModel {

    // MARK: - 依赖项 / Dependencies
    private let container: RepositoryContainer

    // MARK: - 输出状态 / Output state
    /// 按 subject 分组,每组按日期升序 / Grouped by subject, sorted asc.
    private(set) var gradesBySubject: [String: [Grade]] = [:]
    /// 启用的 + 有成绩的科目 / Enabled subjects that actually have grades.
    private(set) var activeSubjects: [String] = []
    /// 需要关注的科目(平均 < 70 或近期下滑 > 15) / Subjects needing attention.
    private(set) var subjectsNeedingAttention: [String] = []
    private(set) var radarSnapshots: [SubjectRadarSnapshot] = []
    private(set) var radarAIAnalysis: String?
    private(set) var isRadarAILoading = false
    private(set) var radarAIError: String?

    private var radarAITask: Task<Void, Never>?

    // MARK: - 初始化 / Initialization
    init(container: RepositoryContainer) {
        self.container = container
    }

    /// 工厂方法 / Factory.
    static func makeDefault(container: RepositoryContainer) -> TrendsViewModel {
        TrendsViewModel(container: container)
    }

    // MARK: - 业务方法 / Business methods
    /// 集中重算 3 个缓存 / Recompute all 3 caches.
    func recompute() {
        let filteredGrades = container.gradeRepo.filteredGrades
        let subjects = container.subjectRepo.subjects

        // 1. 单次 group by subject + sort
        var groups: [String: [Grade]] = [:]
        for g in filteredGrades {
            groups[g.subject, default: []].append(g)
        }
        var sorted: [String: [Grade]] = [:]
        for (subject, arr) in groups {
            sorted[subject] = arr.sorted { $0.date < $1.date }
        }
        gradesBySubject = sorted

        // 2. 启用的 + 有成绩的科目
        let enabledNames = subjects.filter { $0.enabled }.map { $0.name }
        activeSubjects = enabledNames.filter { !(sorted[$0]?.isEmpty ?? true) }

        // 3. 需要关注:平均 < 70 或最近 3 次下滑 > 15
        // 阈值 70 / 15:低于 70 直接红牌;最近 3 次跌幅 > 15 提示
        var needAttention: [String] = []
        for subject in activeSubjects {
            guard let arr = sorted[subject], arr.count >= 2 else { continue }
            let recent = Array(arr.suffix(3))
            // 平均 < 70 → 关注
            let avg = recent.reduce(0.0) { $0 + $1.score } / Double(recent.count)
            if avg < 70 {
                needAttention.append(subject)
                continue
            }
            if recent.count >= 2 {
                // 最近 vs 最早跌幅 > 15 → 关注
                guard let first = recent.first?.score, let last = recent.last?.score else { continue }
                if last < first - 15 {
                    needAttention.append(subject)
                }
            }
        }
        subjectsNeedingAttention = needAttention
        radarSnapshots = makeRadarSnapshots(subjects: activeSubjects, grades: filteredGrades)
    }

    func requestRadarAIAnalysis() {
        radarAITask?.cancel()
        guard !radarSnapshots.isEmpty else { return }
        isRadarAILoading = true
        radarAIError = nil
        radarAITask = Task { [weak self] in
            guard let self else { return }
            do {
                let prompt = SubjectRadarLLM.makePrompt(
                    radarSnapshots,
                    languageCode: container.envManager.preferences.appLanguage
                )
                var accumulated = ""
                _ = try await LLMClient.shared.stream(
                    prompt: prompt,
                    config: LLMConfig.from(container.envManager.preferences),
                    caller: "SubjectRadar"
                ) { delta in
                    accumulated += delta
                    self.radarAIAnalysis = accumulated
                }
                self.radarAIAnalysis = SubjectRadarLLM.clean(accumulated)
            } catch is CancellationError {
                return
            } catch {
                self.radarAIError = error.localizedDescription
            }
            self.isRadarAILoading = false
        }
    }

    private func makeRadarSnapshots(subjects: [String], grades: [Grade]) -> [SubjectRadarSnapshot] {
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let recentGrades = grades.filter { $0.date >= cutoff }
        let mistakes = container.mistakeRepo.filteredMistakeSets.filter { $0.date >= cutoff }
        let subjectRecords = container.subjectRepo.subjects
        let fullScores = Dictionary(uniqueKeysWithValues: subjectRecords.map { ($0.name, $0.fullScore) })
        let sessions = container.studySessionRepo
            .sessions(from: cutoff, to: now)
            .filter(\.completed)
        let subjectIDs = Dictionary(uniqueKeysWithValues: subjectRecords.map { ($0.id, $0.name) })
        let calendar = Calendar.current

        var minutesBySubject: [String: Double] = [:]
        var hrvDatesBySubject: [String: Set<String>] = [:]
        for session in sessions {
            let names = Set((session.difficultyAnnotations ?? []).compactMap { annotation in
                annotation.subjectId.flatMap { subjectIDs[$0] }
            })
            guard !names.isEmpty else { continue }
            let minutes = Double(session.durationSeconds) / 60.0 / Double(names.count)
            for name in names {
                minutesBySubject[name, default: 0] += minutes
                hrvDatesBySubject[name, default: []].insert(calendar.startOfDay(for: session.startDate).ISO8601Format())
            }
        }
        let hrvHistory = HealthHistoryStore.load().filter { $0.date >= cutoff }
        let hrvByDay = Dictionary(uniqueKeysWithValues: hrvHistory.compactMap { snapshot in
            snapshot.hrv.map { (calendar.startOfDay(for: snapshot.date).ISO8601Format(), $0) }
        })
        let hrvValues = hrvHistory.compactMap(\.hrv)
        let overallHRV = hrvValues.isEmpty ? 0 : hrvValues.reduce(0, +) / Double(hrvValues.count)
        let maxMinutes = max(minutesBySubject.values.max() ?? 0, 1)

        return subjects.map { subject in
            let subjectGrades = recentGrades.filter { $0.subject == subject }
            let subjectMistakes = mistakes.filter { $0.subject == subject }
            let taggedConcepts = Set(subjectMistakes.flatMap(\.tags).map { $0.lowercased() }).count
            let coverage = min(1, Double(min(subjectGrades.count, 6)) / 6.0 * 0.6 + Double(min(taggedConcepts, 10)) / 10.0 * 0.4)
            let reviewed = subjectMistakes.filter { $0.exposureCount > 0 }.count
            let reviewFrequency = subjectMistakes.isEmpty ? (subjectGrades.isEmpty ? 0.5 : 0.65) : min(1, Double(reviewed) / Double(subjectMistakes.count))
            let mistakeRate = 1 - min(1, Double(subjectMistakes.count) / Double(max(subjectGrades.count + subjectMistakes.count, 1)))
            let averageScore = subjectGrades.isEmpty ? 0.5 : subjectGrades.map { $0.scoreRate(subjectFullScore: fullScores[subject] ?? 100) }.reduce(0, +) / Double(subjectGrades.count)
            let minutes = minutesBySubject[subject, default: 0]
            let hrvValues = (hrvDatesBySubject[subject] ?? []).compactMap { hrvByDay[$0] }
            let hrvPerformance = hrvValues.isEmpty || overallHRV <= 0
                ? 0.5
                : max(0, min(1, 0.5 + ((hrvValues.reduce(0, +) / Double(hrvValues.count) / overallHRV) - 1) * 1.5))
            return SubjectRadarSnapshot(
                id: subject, subject: subject, coverage: coverage,
                reviewFrequency: reviewFrequency, mistakeRate: mistakeRate,
                averageScore: averageScore, studyTime: min(1, minutes / maxMinutes),
                hrvPerformance: hrvPerformance, gradeCount: subjectGrades.count,
                mistakeCount: subjectMistakes.count, reviewedMistakes: reviewed,
                studyMinutes: Int(minutes.rounded())
            )
        }
    }

    // MARK: - SubjectDetailView 派生数据 / Derived data for SubjectDetailView
    /// 给定 subject,返回其全部成绩(按时间升序) / All grades for a subject.
    func gradesForSubject(_ subject: String) -> [Grade] {
        gradesBySubject[subject] ?? []
    }

    /// 最近一条成绩 / Latest grade.
    func latestGrade(for subject: String) -> Grade? {
        gradesBySubject[subject]?.last
    }

    /// 完整历史(等同 `gradesForSubject`) / Full history (alias).
    func gradeHistory(for subject: String) -> [Grade] {
        gradesBySubject[subject] ?? []
    }

    // MARK: - SubjectDetailView 统计 / Statistics for SubjectDetailView
    /// 平均分(空返回 0) / Average score (0 when empty).
    func averageScore(for grades: [Grade]) -> Double {
        guard !grades.isEmpty else { return 0 }
        return grades.map { $0.score }.reduce(0, +) / Double(grades.count)
    }

    /// 平均排名(无效排名不参与,空返回 0) / Average rank (ignores invalid ranks).
    func averageRank(for grades: [Grade]) -> Int {
        let valid = grades.filter { ($0.ranking ?? 0) > 0 }
        guard !valid.isEmpty else { return 0 }
        let sum = valid.compactMap { $0.ranking }.reduce(0, +)
        return sum / valid.count
    }
}
