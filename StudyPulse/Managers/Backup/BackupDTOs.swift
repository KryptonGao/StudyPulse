import Foundation

/// Versioned wire envelope. The payload is a Codable value snapshot, never a SwiftData model.
/// The envelope gives future importers a stable place for per-record migrations.
nonisolated struct BackupRecordDTO<Value: Codable>: Codable {
    var dtoVersion: Int
    var id: UUID
    var updatedAt: Date?
    var value: Value

    init(id: UUID, updatedAt: Date? = nil, value: Value, dtoVersion: Int = 1) {
        self.dtoVersion = dtoVersion
        self.id = id
        self.updatedAt = updatedAt
        self.value = value
    }

    private enum CodingKeys: String, CodingKey { case dtoVersion, id, updatedAt, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dtoVersion = try c.decodeIfPresent(Int.self, forKey: .dtoVersion) ?? 1
        value = try c.decode(Value.self, forKey: .value)
        id = try c.decodeIfPresent(UUID.self, forKey: .id)
            ?? ((try? BackupDateCoding.encoder().encode(value))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["id"] as? String)
                .flatMap(UUID.init(uuidString:))
            ?? UUID()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

nonisolated enum BackupJSONL {
    static func encode<T: Encodable>(_ values: [T]) throws -> Data {
        let encoder = BackupDateCoding.encoder()
        var data = Data()
        for value in values {
            data.append(try encoder.encode(value))
            data.append(0x0A)
        }
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, path: String) throws -> [T] {
        let decoder = BackupDateCoding.decoder()
        return try data.split(separator: 0x0A, omittingEmptySubsequences: true).enumerated().map { index, line in
            do {
                return try decoder.decode(type, from: Data(line))
            } catch {
                throw BackupError.malformedData("\(path):\(index + 1)")
            }
        }
    }
}

/// Explicit allow-list. LLM credentials, provider endpoints, health baselines,
/// debug flags and request/cache timestamps deliberately have no representation.
nonisolated struct BackupPreferencesDTO: Codable, Equatable, Sendable {
    var dtoVersion: Int = 1
    var appLanguage: String?
    var colorSchemeRaw: String
    var chartTypeRaw: String
    var accentPaletteId: String?
    var glassEffectEnabled: Bool
    var learningHeatmapOnTrends: Bool
    var subjectMasteryRadarOnTrends: Bool
    var activePhaseId: UUID?
    var cardSkinId: String?
    var timerAnimationId: String?
    var plantCardEnabled: Bool
    var plantPetalColorId: String?
    var diaryEnabled: Bool
    var diaryDailyReminderEnabled: Bool
    var diaryDailyReminderHour: Int
    var habitInsightEnabled: Bool
    var habitInsightNotificationEnabled: Bool
    var habitInsightNotificationHour: Int

    init(preferences p: AppPreferences) {
        appLanguage = p.appLanguage
        colorSchemeRaw = p.colorScheme.rawValue
        chartTypeRaw = p.chartType.rawValue
        accentPaletteId = p.accentPaletteId
        glassEffectEnabled = p.glassEffectEnabled
        learningHeatmapOnTrends = p.learningHeatmapOnTrends
        subjectMasteryRadarOnTrends = p.subjectMasteryRadarOnTrends
        activePhaseId = p.activePhaseId
        cardSkinId = p.cardSkinId
        timerAnimationId = p.timerAnimationId
        plantCardEnabled = p.plantCardEnabled
        plantPetalColorId = p.plantPetalColorId
        diaryEnabled = p.diaryEnabled
        diaryDailyReminderEnabled = p.diaryDailyReminderEnabled
        diaryDailyReminderHour = p.diaryDailyReminderHour
        habitInsightEnabled = p.habitInsightEnabled
        habitInsightNotificationEnabled = p.habitInsightNotificationEnabled
        habitInsightNotificationHour = p.habitInsightNotificationHour
    }

    func applying(to original: AppPreferences) -> AppPreferences {
        var p = original
        p.appLanguage = appLanguage
        p.colorScheme = ColorSchemeOption(rawValue: colorSchemeRaw) ?? .system
        p.chartType = ChartType(rawValue: chartTypeRaw) ?? .line
        p.accentPaletteId = accentPaletteId
        p.glassEffectEnabled = glassEffectEnabled
        p.learningHeatmapOnTrends = learningHeatmapOnTrends
        p.subjectMasteryRadarOnTrends = subjectMasteryRadarOnTrends
        p.activePhaseId = activePhaseId
        p.cardSkinId = cardSkinId
        p.timerAnimationId = timerAnimationId
        p.plantCardEnabled = plantCardEnabled
        p.plantPetalColorId = plantPetalColorId
        p.diaryEnabled = diaryEnabled
        p.diaryDailyReminderEnabled = diaryDailyReminderEnabled
        p.diaryDailyReminderHour = diaryDailyReminderHour
        p.habitInsightEnabled = habitInsightEnabled
        p.habitInsightNotificationEnabled = habitInsightNotificationEnabled
        p.habitInsightNotificationHour = habitInsightNotificationHour
        return p
    }

    private enum CodingKeys: String, CodingKey {
        case dtoVersion, appLanguage, colorSchemeRaw, chartTypeRaw, accentPaletteId
        case glassEffectEnabled, learningHeatmapOnTrends, subjectMasteryRadarOnTrends
        case activePhaseId, cardSkinId, timerAnimationId, plantCardEnabled
        case plantPetalColorId, diaryEnabled, diaryDailyReminderEnabled
        case diaryDailyReminderHour, habitInsightEnabled
        case habitInsightNotificationEnabled, habitInsightNotificationHour
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dtoVersion = try c.decodeIfPresent(Int.self, forKey: .dtoVersion) ?? 1
        appLanguage = try c.decodeIfPresent(String.self, forKey: .appLanguage)
        colorSchemeRaw = try c.decodeIfPresent(String.self, forKey: .colorSchemeRaw) ?? "system"
        chartTypeRaw = try c.decodeIfPresent(String.self, forKey: .chartTypeRaw) ?? "line"
        accentPaletteId = try c.decodeIfPresent(String.self, forKey: .accentPaletteId)
        glassEffectEnabled = try c.decodeIfPresent(Bool.self, forKey: .glassEffectEnabled) ?? false
        learningHeatmapOnTrends = try c.decodeIfPresent(Bool.self, forKey: .learningHeatmapOnTrends) ?? true
        subjectMasteryRadarOnTrends = try c.decodeIfPresent(Bool.self, forKey: .subjectMasteryRadarOnTrends) ?? true
        activePhaseId = try c.decodeIfPresent(UUID.self, forKey: .activePhaseId)
        cardSkinId = try c.decodeIfPresent(String.self, forKey: .cardSkinId)
        timerAnimationId = try c.decodeIfPresent(String.self, forKey: .timerAnimationId)
        plantCardEnabled = try c.decodeIfPresent(Bool.self, forKey: .plantCardEnabled) ?? true
        plantPetalColorId = try c.decodeIfPresent(String.self, forKey: .plantPetalColorId)
        diaryEnabled = try c.decodeIfPresent(Bool.self, forKey: .diaryEnabled) ?? true
        diaryDailyReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .diaryDailyReminderEnabled) ?? false
        diaryDailyReminderHour = try c.decodeIfPresent(Int.self, forKey: .diaryDailyReminderHour) ?? 22
        habitInsightEnabled = try c.decodeIfPresent(Bool.self, forKey: .habitInsightEnabled) ?? false
        habitInsightNotificationEnabled = try c.decodeIfPresent(Bool.self, forKey: .habitInsightNotificationEnabled) ?? true
        habitInsightNotificationHour = try c.decodeIfPresent(Int.self, forKey: .habitInsightNotificationHour) ?? 7
    }
}

nonisolated struct BackupChecksums: Codable, Equatable, Sendable {
    var algorithm: String = "SHA-256"
    var files: [String: String]
}

nonisolated enum BackupCoachKind: String, Codable, Sendable {
    case goal, analysis, proposal, chat, message
}

nonisolated struct BackupCoachRow: Codable, Sendable {
    var kind: BackupCoachKind
    var payload: Data
}

nonisolated struct BackupExportOptions: Sendable {
    var includesMedia = true
    var includesDerivedHealthData = false
    /// Optional passphrase for portable AES-GCM backups. Empty / nil uses the
    /// on-device wrapping key stored in Keychain.
    var password: String? = nil
}

nonisolated enum BackupRestoreMode: String, CaseIterable, Sendable {
    case replace
    case merge
}
