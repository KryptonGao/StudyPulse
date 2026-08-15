import os

import Foundation

/// 单次心率采样点（Apple Watch 通过 HealthKit 写入）。
/// A single heart-rate sample written by Apple Watch via HealthKit.
nonisolated struct HeartRateSample: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let bpm: Double
}

/// 学习会话中遇到的难题标注（用户在心率峰值处手动登记）。
/// A difficulty annotation logged by the user at a high-heart-rate point
/// during a study session.
nonisolated struct DifficultyAnnotation: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    /// 在会话时间轴上的位置
    /// Position on the session timeline.
    let timestamp: Date
    /// 标注时的心率（若有）
    /// Heart rate at the annotation moment, if available.
    let heartRate: Double?
    /// 用户输入的难题描述
    /// User-entered description of the difficulty encountered.
    let note: String
    /// 可选关联学科
    /// Optional associated subject id.
    let subjectId: UUID?
}

/// 单次已完成的专注计时会话，持久化用于趋势分析。
/// A single completed study timer session, persisted for trend analysis.
nonisolated struct StudySession: Codable, Identifiable, Equatable, Sendable {
    /// 唯一会话 id
    /// Unique session identifier.
    let id: UUID
    /// 会话开始时间
    /// When the session started.
    let startDate: Date
    /// 时长（秒）
    /// Duration in seconds.
    let durationSeconds: Int
    /// 会话开始时所处的强度档位
    /// The intensity tier active when the session was started.
    let intensity: SessionIntensity
    /// 是否自然完成（true）或被取消（false）
    /// Whether the session completed naturally (true) or was cancelled (false).
    let completed: Bool
    /// 会话期间采集的心率样本（仅自然完成且开启采集时存在）
    /// Heart-rate samples collected during the session (only present when
    /// the session completed naturally and streaming was enabled).
    let heartRateSamples: [HeartRateSample]?
    /// 用户在心率峰值处登记的难题标注
    /// Difficulty annotations logged by the user at high-HR points.
    let difficultyAnnotations: [DifficultyAnnotation]?
    /// Optional time-investment project. Legacy sessions decode as unassigned.
    let investmentTarget: InvestmentTarget?
    /// How this record was created.
    let source: StudySessionSource
    /// Time zone used for natural-day streak boundaries.
    let timeZoneIdentifier: String?

    /// 成员初始化器
    /// Memberwise initializer.
    nonisolated init(
        id: UUID,
        startDate: Date,
        durationSeconds: Int,
        intensity: SessionIntensity,
        completed: Bool,
        heartRateSamples: [HeartRateSample]? = nil,
        difficultyAnnotations: [DifficultyAnnotation]? = nil,
        investmentTarget: InvestmentTarget? = nil,
        source: StudySessionSource = .timer,
        timeZoneIdentifier: String? = TimeZone.autoupdatingCurrent.identifier
    ) {
        self.id = id
        self.startDate = startDate
        self.durationSeconds = durationSeconds
        self.intensity = intensity
        self.completed = completed
        self.heartRateSamples = heartRateSamples
        self.difficultyAnnotations = difficultyAnnotations
        self.investmentTarget = investmentTarget
        self.source = source
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// 自定义解码器:新字段用 decodeIfPresent 兜底,保证旧 JSON 兼容。
    /// Custom decoder: new fields use decodeIfPresent so legacy JSON
    /// without them decodes without throwing.
    private enum CodingKeys: String, CodingKey {
        case id, startDate, durationSeconds, intensity, completed
        case heartRateSamples, difficultyAnnotations
        case investmentTarget, source, timeZoneIdentifier
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startDate = try c.decode(Date.self, forKey: .startDate)
        durationSeconds = try c.decode(Int.self, forKey: .durationSeconds)
        intensity = try c.decode(SessionIntensity.self, forKey: .intensity)
        completed = try c.decode(Bool.self, forKey: .completed)
        heartRateSamples = try c.decodeIfPresent([HeartRateSample].self, forKey: .heartRateSamples)
        difficultyAnnotations = try c.decodeIfPresent([DifficultyAnnotation].self, forKey: .difficultyAnnotations)
        investmentTarget = try c.decodeIfPresent(InvestmentTarget.self, forKey: .investmentTarget)
        source = try c.decodeIfPresent(StudySessionSource.self, forKey: .source) ?? .timer
        timeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(intensity, forKey: .intensity)
        try c.encode(completed, forKey: .completed)
        try c.encodeIfPresent(heartRateSamples, forKey: .heartRateSamples)
        try c.encodeIfPresent(difficultyAnnotations, forKey: .difficultyAnnotations)
        try c.encodeIfPresent(investmentTarget, forKey: .investmentTarget)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(timeZoneIdentifier, forKey: .timeZoneIdentifier)
    }

    /// 专注会话强度档位。
    /// Focus session intensity tier.
    enum SessionIntensity: String, Codable, Equatable, Sendable, CaseIterable {
        case peak
        case deepFocus
        case steady
        case light
        case recovery

        /// 本地化显示名
        /// Localized display name.
        var displayName: String {
            switch self {
            case .peak: return "Peak Performance".localized()
            case .deepFocus: return "Deep Focus".localized()
            case .steady: return "Steady Rhythm".localized()
            case .light: return "Light Review".localized()
            case .recovery: return "Recovery".localized()
            }
        }

        /// SF Symbol 图标
        /// SF Symbol icon.
        var icon: String {
            switch self {
            case .peak: return "bolt.heart.fill"
            case .deepFocus: return "brain.head.profile"
            case .steady: return "chart.bar.fill"
            case .light: return "book.closed.fill"
            case .recovery: return "bed.double.fill"
            }
        }

        /// 6 位 hex (RRGGBB) 主色，用于 Live Activity / Dynamic Island。
        /// 与 StudyTimerView / StudyTimerCard 中的取值保持一致。
        /// 6-digit hex (RRGGBB) for the Live Activity / Dynamic Island
        /// accent color. Mirrors the values used in StudyTimerView /
        /// StudyTimerCard.
        var colorHex: String {
            switch self {
            case .peak: return "34C759"        // green
            case .deepFocus: return "0A84FF"    // blue
            case .steady: return "5856D6"       // indigo
            case .light: return "FF9500"        // orange
            case .recovery: return "FF3B30"     // red
            }
        }

        /// 推荐会话时长（秒），由强度档位决定。
        /// Recommended session duration in seconds based on the intensity tier.
        var recommendedDurationSeconds: Int {
            switch self {
            case .peak: return 50 * 60       // 50 min
            case .deepFocus: return 45 * 60   // 45 min
            case .steady: return 35 * 60      // 35 min
            case .light: return 25 * 60       // 25 min
            case .recovery: return 20 * 60    // 20 min
            }
        }
    }

    /// 从 `StudyIntensity`（算法层）映射到 `SessionIntensity`（持久化层）。
    /// Convert from `StudyIntensity` (algorithm) to `SessionIntensity` (persistence).
    nonisolated static func fromAlgorithmIntensity(_ intensity: StudyIntensity) -> SessionIntensity {
        switch intensity {
        case .peak: return .peak
        case .deepFocus: return .deepFocus
        case .steady: return .steady
        case .light: return .light
        case .recovery: return .recovery
        }
    }
}

/// Metadata used by history, trend, and time-investment lists.
///
/// The telemetry arrays deliberately do not belong to this value.  A list can
/// therefore be rendered without decoding the potentially large heart-rate
/// stream and annotation payload for every historical session.
nonisolated struct StudySessionSummary: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let startDate: Date
    let durationSeconds: Int
    let intensity: StudySession.SessionIntensity
    let completed: Bool
    let heartRateSampleCount: Int
    let difficultyAnnotationCount: Int
    let investmentTarget: InvestmentTarget?
    let source: StudySessionSource
    let timeZoneIdentifier: String?

    init(
        id: UUID,
        startDate: Date,
        durationSeconds: Int,
        intensity: StudySession.SessionIntensity,
        completed: Bool,
        heartRateSampleCount: Int = 0,
        difficultyAnnotationCount: Int = 0,
        investmentTarget: InvestmentTarget? = nil,
        source: StudySessionSource = .timer,
        timeZoneIdentifier: String? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.durationSeconds = durationSeconds
        self.intensity = intensity
        self.completed = completed
        self.heartRateSampleCount = heartRateSampleCount
        self.difficultyAnnotationCount = difficultyAnnotationCount
        self.investmentTarget = investmentTarget
        self.source = source
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    init(from session: StudySession) {
        self.init(
            id: session.id,
            startDate: session.startDate,
            durationSeconds: session.durationSeconds,
            intensity: session.intensity,
            completed: session.completed,
            heartRateSampleCount: session.heartRateSamples?.count ?? 0,
            difficultyAnnotationCount: session.difficultyAnnotations?.count ?? 0,
            investmentTarget: session.investmentTarget,
            source: session.source,
            timeZoneIdentifier: session.timeZoneIdentifier
        )
    }

    /// A compatibility value for code that only needs session metadata.
    func asSession() -> StudySession {
        StudySession(
            id: id,
            startDate: startDate,
            durationSeconds: durationSeconds,
            intensity: intensity,
            completed: completed,
            investmentTarget: investmentTarget,
            source: source,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

/// Legacy JSON reader retained only for the idempotent SwiftData migration.
enum StudySessionStore {
    /// 持久化文件名
    /// Persistence file name.
    nonisolated static let fileName = "study_sessions.json"
    /// 持久化文件 URL
    /// Persistence file URL.
    nonisolated static func fileURL() throws -> URL {
        let dir = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return dir.appendingPathComponent(fileName)
    }

    /// 加载全部已保存的会话
    /// Load all persisted sessions.
    nonisolated static func load() -> [StudySession] {
        guard let url = try? fileURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            let decoded = try JSONDecoder().decode([StudySession].self, from: data)
            return decoded
        } catch {
            Log.app.error("StudySessionStore decode failed: \(error.localizedDescription)")
            return []
        }
    }

}

struct WeekdayHourSlotBucket: Sendable {
    let weekday: Int
    let hourSlot: HabitInsight.HourSlot
    let sessionCount: Int
    let avgDurationMinutes: Double
    let completedRatio: Double
    let peakIntensityRatio: Double
}

extension StudySessionStore {
    nonisolated static func aggregateByWeekdayHourSlot(
        sessions suppliedSessions: [StudySession],
        days: Int = 90
    ) -> [WeekdayHourSlotBucket] {
        aggregateByWeekdayHourSlotImpl(sessions: suppliedSessions, days: days)
    }

    private nonisolated static func aggregateByWeekdayHourSlotImpl(
        sessions suppliedSessions: [StudySession],
        days: Int
    ) -> [WeekdayHourSlotBucket] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let sessions = suppliedSessions.filter { $0.startDate >= cutoff }
        var grouped: [String: [StudySession]] = [:]
        for session in sessions {
            let weekday = calendar.component(.weekday, from: session.startDate)
            let hour = calendar.component(.hour, from: session.startDate)
            let slot = HabitInsight.HourSlot.from(hour: hour)
            grouped["\(weekday)-\(slot.rawValue)", default: []].append(session)
        }
        return grouped.compactMap { key, values in
            let parts = key.split(separator: "-")
            guard parts.count == 2,
                  let weekday = Int(parts[0]),
                  let slotRawValue = Int(parts[1]),
                  let hourSlot = HabitInsight.HourSlot(rawValue: slotRawValue),
                  !values.isEmpty else { return nil }
            let totalMinutes = values.reduce(0.0) { total, session in
                total + Double(session.durationSeconds) / 60.0
            }
            let completedCount = values.reduce(into: 0) { count, session in
                if session.completed { count += 1 }
            }
            let peakCount = values.reduce(into: 0) { count, session in
                if session.intensity == .peak || session.intensity == .deepFocus { count += 1 }
            }
            let sampleCount = Double(values.count)
            return WeekdayHourSlotBucket(
                weekday: weekday,
                hourSlot: hourSlot,
                sessionCount: values.count,
                avgDurationMinutes: totalMinutes / sampleCount,
                completedRatio: Double(completedCount) / sampleCount,
                peakIntensityRatio: Double(peakCount) / sampleCount
            )
        }
    }
}
