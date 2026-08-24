import Foundation

nonisolated struct BackupManifest: Codable, Equatable, Sendable {
    static let expectedFormatIdentifier = "com.chenkai.gao.studypulse.backup"
    static let currentFormatVersion = 1
    static let currentSchemaVersion = 5

    var formatIdentifier: String
    var formatVersion: Int
    var appVersion: String
    var appBuild: String
    var schemaVersion: Int
    var createdAt: Date
    var recordCounts: [String: Int]
    var includesMedia: Bool
    var includesDerivedHealthData: Bool
    var encrypted: Bool
    var locale: String
    var mediaFileCount: Int
    var mediaBytes: Int64
    var missingMediaCount: Int
    var warnings: [String]

    init(
        formatIdentifier: String = Self.expectedFormatIdentifier,
        formatVersion: Int = Self.currentFormatVersion,
        appVersion: String,
        appBuild: String,
        schemaVersion: Int = Self.currentSchemaVersion,
        createdAt: Date = .now,
        recordCounts: [String: Int],
        includesMedia: Bool,
        includesDerivedHealthData: Bool,
        encrypted: Bool = false,
        locale: String,
        mediaFileCount: Int = 0,
        mediaBytes: Int64 = 0,
        missingMediaCount: Int = 0,
        warnings: [String] = []
    ) {
        self.formatIdentifier = formatIdentifier
        self.formatVersion = formatVersion
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.schemaVersion = schemaVersion
        // ISO-8601 backup dates are encoded with second precision. Normalize
        // here so a manifest is stable across an encode/decode round trip.
        self.createdAt = Date(
            timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down)
        )
        self.recordCounts = recordCounts
        self.includesMedia = includesMedia
        self.includesDerivedHealthData = includesDerivedHealthData
        self.encrypted = encrypted
        self.locale = locale
        self.mediaFileCount = mediaFileCount
        self.mediaBytes = mediaBytes
        self.missingMediaCount = missingMediaCount
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case formatIdentifier, formatVersion, appVersion, appBuild, schemaVersion
        case createdAt, recordCounts, includesMedia, includesDerivedHealthData
        case encrypted, locale, mediaFileCount, mediaBytes, missingMediaCount, warnings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatIdentifier = try c.decode(String.self, forKey: .formatIdentifier)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? "Unknown"
        appBuild = try c.decodeIfPresent(String.self, forKey: .appBuild) ?? "Unknown"
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        recordCounts = try c.decodeIfPresent([String: Int].self, forKey: .recordCounts) ?? [:]
        includesMedia = try c.decodeIfPresent(Bool.self, forKey: .includesMedia) ?? false
        includesDerivedHealthData = try c.decodeIfPresent(Bool.self, forKey: .includesDerivedHealthData) ?? false
        encrypted = try c.decodeIfPresent(Bool.self, forKey: .encrypted) ?? false
        locale = try c.decodeIfPresent(String.self, forKey: .locale) ?? "und"
        mediaFileCount = try c.decodeIfPresent(Int.self, forKey: .mediaFileCount) ?? 0
        mediaBytes = try c.decodeIfPresent(Int64.self, forKey: .mediaBytes) ?? 0
        missingMediaCount = try c.decodeIfPresent(Int.self, forKey: .missingMediaCount) ?? 0
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

nonisolated enum BackupDateCoding {
    static func encoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
