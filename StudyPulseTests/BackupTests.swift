import XCTest
import SwiftData
import CryptoKit
@testable import StudyPulse

final class BackupTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BackupWrappingKeyStore.setOverrideKeyForTesting(SymmetricKey(size: .bits256))
    }

    override func tearDown() {
        BackupWrappingKeyStore.setOverrideKeyForTesting(nil)
        super.tearDown()
    }

    @MainActor
    func testRestorePreflightFailureLeavesLiveStoreUntouched() async throws {
        let archive = try makeEmptyArchive()
        defer { try? FileManager.default.removeItem(at: archive) }
        var validated = try await BackupValidator.validate(archiveURL: archive)
        defer { validated.cleanup() }

        let duplicate = Subject(name: "Duplicate ID")
        validated.content.subjects = [duplicate, duplicate]

        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let existing = Grade(subject: "Math", score: 88, examName: "Existing")
        container.mainContext.insert(GradeRecord(from: existing))
        try container.mainContext.save()

        XCTAssertThrowsError(
            try BackupImporter.validateInTemporaryStore(validated.content)
        )

        XCTAssertEqual(
            try container.mainContext.fetchCount(
                FetchDescriptor<GradeRecord>()
            ),
            1
        )
        XCTAssertEqual(
            try container.mainContext.fetch(FetchDescriptor<GradeRecord>()).map(\.id),
            [existing.id]
        )
    }

    func testManifestRoundTrip() throws {
        let source = BackupManifest(
            appVersion: "3.1",
            appBuild: "42",
            recordCounts: ["grades": 7],
            includesMedia: true,
            includesDerivedHealthData: false,
            locale: "zh-Hans"
        )
        let data = try BackupDateCoding.encoder().encode(source)
        let decoded = try BackupDateCoding.decoder().decode(BackupManifest.self, from: data)
        XCTAssertEqual(decoded, source)
    }

    func testManifestBackwardCompatibleDefaults() throws {
        let json = """
        {"formatIdentifier":"com.chenkai.gao.studypulse.backup","formatVersion":1,
         "createdAt":"2026-07-24T00:00:00Z"}
        """.data(using: .utf8)!
        let decoded = try BackupDateCoding.decoder().decode(BackupManifest.self, from: json)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertFalse(decoded.includesMedia)
        XCTAssertFalse(decoded.encrypted)
        XCTAssertEqual(decoded.warnings, [])
    }

    func testLegacyHealthHistoryDateFormatStillDecodes() throws {
        let snapshot = DailyHealthSnapshot(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            hrv: 42,
            restingHeartRate: nil,
            respiratoryRate: nil,
            sleepHours: nil,
            deepSleepHours: nil,
            remSleepHours: nil,
            exerciseMinutes: nil
        )
        let legacy = try JSONEncoder().encode([snapshot])
        let decoded = try JSONDecoder().decode([DailyHealthSnapshot].self, from: legacy)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.hrv, 42)
    }

    func testJSONLMultipleRecordsRoundTrip() throws {
        let values = [
            BackupRecordDTO(id: UUID(), value: Subject(name: "Math")),
            BackupRecordDTO(id: UUID(), value: Subject(name: "Physics")),
        ]
        let data = try BackupJSONL.encode(values)
        let decoded = try BackupJSONL.decode(
            BackupRecordDTO<Subject>.self,
            from: data,
            path: "subjects.jsonl"
        )
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.map(\.value.name), ["Math", "Physics"])
    }

    func testJSONLCorruptionIsRejected() throws {
        let data = Data("{\"id\":\"broken\"}\n".utf8)
        XCTAssertThrowsError(
            try BackupJSONL.decode(BackupRecordDTO<Subject>.self, from: data, path: "x")
        )
    }

    func testPreferencesWhitelistNeverContainsAPIKey() throws {
        var preferences = AppPreferences()
        preferences.llmAPIKey = "top-secret"
        preferences.llmBaseURL = "https://secret.example"
        preferences.llmProviders = [
            LLMProvider(name: "private", baseURL: "https://provider.example", legacyAPIKey: "also-secret", model: "x")
        ]
        let data = try BackupDateCoding.encoder().encode(BackupPreferencesDTO(preferences: preferences))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("top-secret"))
        XCTAssertFalse(text.contains("also-secret"))
        XCTAssertFalse(text.contains("provider.example"))
        XCTAssertFalse(text.contains("llmAPIKey"))
    }

    func testChecksumKnownValue() {
        XCTAssertEqual(
            BackupChecksum.sha256(data: Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testHMACKnownValue() {
        let key = SymmetricKey(data: Data(repeating: 0x0b, count: 32))
        let mac = HMAC<SHA256>.authenticationCode(for: Data("abc".utf8), using: key)
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(
            hex,
            "cc2b6e43b092526c09f6b2db76c7dc2867ebfdf7d1b170f2d8f73a3894792e12"
        )
        XCTAssertTrue(
            HMAC<SHA256>.isValidAuthenticationCode(
                mac,
                authenticating: Data("abc".utf8),
                using: key
            )
        )
    }

    func testIntegrityRecordDoesNotContainKeyMaterial() throws {
        let checksums = BackupChecksums(files: ["manifest.json": String(repeating: "a", count: 64)])
        let integrity = try BackupChecksum.makeIntegrity(checksums: checksums, password: "secret-pass")
        let json = String(decoding: try BackupDateCoding.encoder().encode(integrity), as: UTF8.self)
        XCTAssertEqual(integrity.keySource, BackupEncryption.Header.passwordSource)
        XCTAssertFalse(json.contains("secret-pass"))
        XCTAssertNil(integrity.mac.range(of: "secret-pass"))
        XCTAssertEqual(integrity.algorithm, BackupIntegrity.hmacSHA256)
        try BackupChecksum.verifyIntegrity(integrity, checksums: checksums, password: "secret-pass")
        XCTAssertThrowsError(
            try BackupChecksum.verifyIntegrity(integrity, checksums: checksums, password: "wrong")
        ) { error in
            guard let backupError = error as? BackupError,
                  case .authenticationFailed = backupError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testUnsafeArchivePathsAreRejected() {
        XCTAssertFalse(BackupArchive.isSafeRelativePath("../Documents/data"))
        XCTAssertFalse(BackupArchive.isSafeRelativePath("/private/data"))
        XCTAssertFalse(BackupArchive.isSafeRelativePath("media//file"))
        XCTAssertFalse(BackupArchive.isSafeRelativePath("C:/file"))
        XCTAssertTrue(BackupArchive.isSafeRelativePath("media/images/a.jpg"))
    }

    func testArchiveCreatedByExporterAcceptsDirectoryEntries() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DirectoryEntry-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("data", isDirectory: true)
        let archive = fm.temporaryDirectory.appendingPathComponent("DirectoryEntry-\(UUID().uuidString).studypulsebackup")
        defer {
            try? fm.removeItem(at: root)
            try? fm.removeItem(at: archive)
        }
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: nested.appendingPathComponent("manifest.json"))
        try BackupArchive.create(from: root, at: archive)

        XCTAssertNoThrow(try BackupArchive.validateEntryPaths(at: archive))
    }

    func testEmptyBackupValidates() async throws {
        let archive = try makeEmptyArchive()
        defer { try? FileManager.default.removeItem(at: archive) }
        let result = try await BackupValidator.validate(archiveURL: archive)
        defer { result.cleanup() }
        XCTAssertEqual(result.content.grades.count, 0)
        XCTAssertEqual(result.manifest.formatVersion, 1)
    }

    func testTamperedChecksumIsRejected() async throws {
        let archive = try makeEmptyArchive(mutate: { root in
            try Data("tampered\n".utf8).write(to: root.appendingPathComponent("data/grades.jsonl"))
        })
        defer { try? FileManager.default.removeItem(at: archive) }
        do {
            _ = try await BackupValidator.validate(archiveURL: archive)
            XCTFail("Expected checksum rejection")
        } catch let error as BackupError {
            guard case .checksumMismatch("data/grades.jsonl") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRecomputedChecksumsWithoutKeyAreRejected() async throws {
        let archive = try makeEmptyArchive(mutate: { root in
            try Data("tampered\n".utf8).write(to: root.appendingPathComponent("data/grades.jsonl"))
            var checksumMap: [String: String] = [:]
            for path in BackupValidator.requiredFiles where path != "checksums.json" {
                checksumMap[path] = try BackupChecksum.sha256(
                    fileURL: root.appendingPathComponent(path)
                )
            }
            try BackupDateCoding.encoder(pretty: true)
                .encode(BackupChecksums(files: checksumMap))
                .write(to: root.appendingPathComponent("checksums.json"))
        })
        defer { try? FileManager.default.removeItem(at: archive) }
        do {
            _ = try await BackupValidator.validate(archiveURL: archive)
            XCTFail("Expected HMAC rejection")
        } catch let error as BackupError {
            guard case .authenticationFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMissingIntegrityOnPlaintextArchiveIsRejected() async throws {
        let archive = try makeEmptyArchive(includeIntegrity: false)
        defer { try? FileManager.default.removeItem(at: archive) }
        do {
            _ = try await BackupValidator.validate(archiveURL: archive)
            XCTFail("Expected missing authentication")
        } catch let error as BackupError {
            guard case .missingAuthentication = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testWrongDeviceWrappingKeyFailsHMAC() async throws {
        let archive = try makeEmptyArchive()
        defer { try? FileManager.default.removeItem(at: archive) }
        BackupWrappingKeyStore.setOverrideKeyForTesting(SymmetricKey(size: .bits256))
        do {
            _ = try await BackupValidator.validate(archiveURL: archive)
            XCTFail("Expected HMAC rejection after wrapping-key change")
        } catch let error as BackupError {
            guard case .authenticationFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMissingManifestIsRejected() async throws {
        let archive = try makeEmptyArchive(removeManifest: true)
        defer { try? FileManager.default.removeItem(at: archive) }
        do {
            _ = try await BackupValidator.validate(archiveURL: archive)
            XCTFail("Expected missing manifest")
        } catch let error as BackupError {
            guard case .missingManifest = error else { return XCTFail("Unexpected: \(error)") }
        }
    }

    func testUnsupportedVersionIsRejected() async throws {
        let archive = try makeEmptyArchive(formatVersion: 99)
        defer { try? FileManager.default.removeItem(at: archive) }
        do {
            _ = try await BackupValidator.validate(archiveURL: archive)
            XCTFail("Expected unsupported version")
        } catch let error as BackupError {
            guard case .unsupportedFormatVersion(99) = error else { return XCTFail("Unexpected: \(error)") }
        }
    }

    func testCountMismatchIsRejected() async throws {
        let archive = try makeEmptyArchive(overrides: ["grades": 1])
        defer { try? FileManager.default.removeItem(at: archive) }
        do {
            _ = try await BackupValidator.validate(archiveURL: archive)
            XCTFail("Expected count mismatch")
        } catch let error as BackupError {
            guard case .countMismatch("grades") = error else { return XCTFail("Unexpected: \(error)") }
        }
    }

    func testSensitivePayloadDetection() {
        XCTAssertFalse(
            BackupEncryption.containsSensitivePayload(
                diaryCount: 0,
                includesHealthHistory: false,
                coachItemCount: 0,
                mediaFileCount: 0
            )
        )
        XCTAssertTrue(
            BackupEncryption.containsSensitivePayload(
                diaryCount: 1,
                includesHealthHistory: false,
                coachItemCount: 0,
                mediaFileCount: 0
            )
        )
        XCTAssertTrue(
            BackupEncryption.containsSensitivePayload(
                diaryCount: 0,
                includesHealthHistory: true,
                coachItemCount: 0,
                mediaFileCount: 0
            )
        )
        XCTAssertTrue(
            BackupEncryption.containsSensitivePayload(
                diaryCount: 0,
                includesHealthHistory: false,
                coachItemCount: 2,
                mediaFileCount: 0
            )
        )
        XCTAssertTrue(
            BackupEncryption.containsSensitivePayload(
                diaryCount: 0,
                includesHealthHistory: false,
                coachItemCount: 0,
                mediaFileCount: 1
            )
        )
    }

    func testPasswordEnvelopeIsNotAZipAndRoundTrips() throws {
        let plaintext = Data("study-pulse-backup-zip-bytes".utf8)
        let envelope = try BackupEncryption.encrypt(plaintext: plaintext, password: "correct horse")
        XCTAssertTrue(BackupEncryption.isEncryptedEnvelope(data: envelope))
        XCTAssertNotEqual(Array(envelope.prefix(2)), [0x50, 0x4B])
        let opened = try BackupEncryption.decrypt(envelope: envelope, password: "correct horse")
        XCTAssertEqual(opened, plaintext)
        XCTAssertThrowsError(
            try BackupEncryption.decrypt(envelope: envelope, password: nil)
        ) { error in
            guard let backupError = error as? BackupError,
                  case .passwordRequired = backupError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(
            try BackupEncryption.decrypt(envelope: envelope, password: "wrong")
        ) { error in
            guard let backupError = error as? BackupError,
                  case .decryptionFailed = backupError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDeviceKeyEnvelopeRoundTripsOnThisDevice() throws {
        BackupWrappingKeyStore.setOverrideKeyForTesting(SymmetricKey(size: .bits256))
        defer { BackupWrappingKeyStore.setOverrideKeyForTesting(nil) }
        let plaintext = Data("device-bound-backup".utf8)
        let envelope = try BackupEncryption.encrypt(plaintext: plaintext, password: nil)
        XCTAssertTrue(BackupEncryption.isEncryptedEnvelope(data: envelope))
        let opened = try BackupEncryption.decrypt(envelope: envelope, password: nil)
        XCTAssertEqual(opened, plaintext)
    }

    func testPlaintextArchiveMarkedEncryptedIsRejected() async throws {
        let archive = try makeEmptyArchive(encrypted: true)
        defer { try? FileManager.default.removeItem(at: archive) }
        do {
            _ = try await BackupValidator.validate(archiveURL: archive)
            XCTFail("Expected encryption inconsistency")
        } catch let error as BackupError {
            guard case .encryptionInconsistent = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testLegacyEncryptedArchiveWithoutHMACStillValidatesViaAEAD() async throws {
        let zip = try makeEmptyArchive(encrypted: true, includeIntegrity: false)
        let envelope = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-enc-\(UUID().uuidString).studypulsebackup")
        defer {
            try? FileManager.default.removeItem(at: zip)
            try? FileManager.default.removeItem(at: envelope)
        }
        try BackupEncryption.encryptFile(at: zip, to: envelope, password: "legacy-secret")
        let result = try await BackupValidator.validate(
            archiveURL: envelope,
            password: "legacy-secret"
        )
        defer { result.cleanup() }
        XCTAssertTrue(result.manifest.encrypted)
    }

    func testTamperedEncryptedEnvelopeIsRejected() async throws {
        let zip = try makeEmptyArchive(encrypted: true)
        let envelope = FileManager.default.temporaryDirectory
            .appendingPathComponent("tamper-enc-\(UUID().uuidString).studypulsebackup")
        defer {
            try? FileManager.default.removeItem(at: zip)
            try? FileManager.default.removeItem(at: envelope)
        }
        try BackupEncryption.encryptFile(at: zip, to: envelope, password: "restore-secret")
        var data = try Data(contentsOf: envelope)
        data[data.count - 1] ^= 0x01
        try data.write(to: envelope, options: .atomic)
        do {
            _ = try await BackupValidator.validate(
                archiveURL: envelope,
                password: "restore-secret"
            )
            XCTFail("Expected AEAD rejection")
        } catch let error as BackupError {
            guard case .decryptionFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPasswordEncryptedArchiveValidates() async throws {
        let zip = try makeEmptyArchive(encrypted: true)
        let envelope = FileManager.default.temporaryDirectory
            .appendingPathComponent("encrypted-\(UUID().uuidString).studypulsebackup")
        defer {
            try? FileManager.default.removeItem(at: zip)
            try? FileManager.default.removeItem(at: envelope)
        }
        try BackupEncryption.encryptFile(at: zip, to: envelope, password: "restore-secret")
        let envelopeData = try Data(contentsOf: envelope)
        XCTAssertTrue(BackupEncryption.isEncryptedEnvelope(data: envelopeData))
        XCTAssertNotEqual(Array(envelopeData.prefix(2)), [0x50, 0x4B])

        let result = try await BackupValidator.validate(
            archiveURL: envelope,
            password: "restore-secret"
        )
        defer { result.cleanup() }
        XCTAssertTrue(result.manifest.encrypted)
        XCTAssertEqual(result.content.grades.count, 0)
    }

    func testLargeJSONLPerformance() throws {
        let rows = (0..<10_000).map {
            let subject = Subject(name: "Subject-\($0)")
            return BackupRecordDTO(id: subject.id, value: subject)
        }
        measure {
            let encoded = try? BackupJSONL.encode(rows)
            XCTAssertNotNil(encoded)
        }
    }

    private func makeEmptyArchive(
        formatVersion: Int = 1,
        overrides: [String: Int] = [:],
        removeManifest: Bool = false,
        encrypted: Bool = false,
        includeIntegrity: Bool = true,
        mutate: ((URL) throws -> Void)? = nil
    ) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("BackupFixture-\(UUID().uuidString)")
        let data = root.appendingPathComponent("data")
        try fm.createDirectory(at: data, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let jsonl = [
            "grades.jsonl", "mistakes.jsonl", "exams.jsonl", "comprehensive_exams.jsonl",
            "tasks.jsonl", "phases.jsonl", "routines.jsonl", "routine_instances.jsonl",
            "diary_entries.jsonl", "study_sessions.jsonl", "coach_data.jsonl",
        ]
        for name in jsonl {
            try Data().write(to: data.appendingPathComponent(name))
        }
        let encoder = BackupDateCoding.encoder(pretty: true)
        try encoder.encode([Subject]()).write(to: data.appendingPathComponent("subjects.json"))
        try encoder.encode(UserProfile()).write(to: data.appendingPathComponent("profile.json"))
        try encoder.encode(PlantState()).write(to: data.appendingPathComponent("plant_state.json"))
        try encoder.encode(AchievementsSnapshot.empty).write(to: data.appendingPathComponent("achievements.json"))
        try encoder.encode(BackupPreferencesDTO(preferences: AppPreferences())).write(to: data.appendingPathComponent("preferences.json"))

        var counts = [
            "subjects": 0, "grades": 0, "mistakes": 0, "exams": 0,
            "comprehensiveExams": 0, "tasks": 0, "phases": 0, "routines": 0,
            "routineInstances": 0, "diaryEntries": 0, "studySessions": 0,
            "profile": 1, "plantState": 1, "achievements": 1, "coachGoals": 0,
            "coachAnalyses": 0, "coachProposals": 0, "coachChats": 0, "coachMessages": 0,
        ]
        overrides.forEach { counts[$0.key] = $0.value }
        let manifest = BackupManifest(
            formatVersion: formatVersion,
            appVersion: "1",
            appBuild: "1",
            recordCounts: counts,
            includesMedia: false,
            includesDerivedHealthData: false,
            encrypted: encrypted,
            locale: "en"
        )
        try encoder.encode(manifest).write(to: root.appendingPathComponent("manifest.json"))

        var checksumMap: [String: String] = [:]
        for path in BackupValidator.requiredFiles where path != "checksums.json" {
            let url = root.appendingPathComponent(path)
            checksumMap[path] = try BackupChecksum.sha256(fileURL: url)
        }
        let checksums = BackupChecksums(files: checksumMap)
        try encoder.encode(checksums).write(to: root.appendingPathComponent("checksums.json"))
        if includeIntegrity {
            let integrity = try BackupChecksum.makeIntegrity(checksums: checksums, password: nil)
            try encoder.encode(integrity).write(to: root.appendingPathComponent("integrity.json"))
        }
        try mutate?(root)
        if removeManifest {
            try fm.removeItem(at: root.appendingPathComponent("manifest.json"))
        }
        let archive = fm.temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).studypulsebackup")
        try BackupArchive.create(from: root, at: archive)
        return archive
    }
}
