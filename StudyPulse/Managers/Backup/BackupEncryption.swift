import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Outer envelope for sensitive StudyPulse backups.
///
/// The on-disk file is **not** a ZIP: `SPBKENC1` + header + AES-GCM sealed box.
/// The ZIP (and `manifest.encrypted == true`) lives only inside the ciphertext.
nonisolated enum BackupEncryption {
    static let magic = Data("SPBKENC1".utf8)
    static let currentVersion = 1
    static let pbkdf2Iterations = 210_000
    static let saltSize = 16
    static let keySize = 32
    static let maxHeaderLength = 16_384
    static let hkdfInfo = Data("StudyPulseBackupV1".utf8)

    nonisolated struct Header: Codable, Equatable, Sendable {
        var formatIdentifier: String
        var version: Int
        var keySource: String
        var kdf: String
        var cipher: String
        var salt: String
        var iterations: Int?

        static let deviceSource = "device"
        static let passwordSource = "password"
        static let hkdfSHA256 = "hkdf-sha256"
        static let pbkdf2SHA256 = "pbkdf2-sha256"
        static let aes256GCM = "aes-256-gcm"
    }

    static func containsSensitivePayload(
        diaryCount: Int,
        includesHealthHistory: Bool,
        coachItemCount: Int,
        mediaFileCount: Int
    ) -> Bool {
        diaryCount > 0
            || includesHealthHistory
            || coachItemCount > 0
            || mediaFileCount > 0
    }

    static func normalizedPassword(_ password: String?) -> String? {
        guard let trimmed = password?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func isEncryptedEnvelope(data: Data) -> Bool {
        data.starts(with: magic)
    }

    static func isEncryptedEnvelope(at url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: magic.count) ?? Data()
        return prefix == magic
    }

    static func encryptFile(at source: URL, to destination: URL, password: String?) throws {
        let plaintext = try Data(contentsOf: source)
        let envelope = try encrypt(plaintext: plaintext, password: normalizedPassword(password))
        try envelope.write(to: destination, options: .atomic)
    }

    static func decryptFile(from source: URL, to destination: URL, password: String?) throws {
        let envelope = try Data(contentsOf: source)
        let plaintext = try decrypt(envelope: envelope, password: normalizedPassword(password))
        try plaintext.write(to: destination, options: .atomic)
    }

    static func encrypt(plaintext: Data, password: String?) throws -> Data {
        var saltBytes = [UInt8](repeating: 0, count: saltSize)
        let saltStatus = SecRandomCopyBytes(kSecRandomDefault, saltSize, &saltBytes)
        guard saltStatus == errSecSuccess else {
            throw BackupError.exportFailed("Could not generate backup encryption salt")
        }
        let salt = Data(saltBytes)
        let key: SymmetricKey
        let header: Header
        if let password {
            key = try derivePasswordKey(password: password, salt: salt, iterations: pbkdf2Iterations)
            header = Header(
                formatIdentifier: BackupManifest.expectedFormatIdentifier,
                version: currentVersion,
                keySource: Header.passwordSource,
                kdf: Header.pbkdf2SHA256,
                cipher: Header.aes256GCM,
                salt: salt.base64EncodedString(),
                iterations: pbkdf2Iterations
            )
        } else {
            key = try deriveDeviceKey(salt: salt)
            header = Header(
                formatIdentifier: BackupManifest.expectedFormatIdentifier,
                version: currentVersion,
                keySource: Header.deviceSource,
                kdf: Header.hkdfSHA256,
                cipher: Header.aes256GCM,
                salt: salt.base64EncodedString(),
                iterations: nil
            )
        }

        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(plaintext, using: key)
        } catch {
            throw BackupError.exportFailed("AES-GCM encryption failed")
        }
        guard let combined = sealed.combined else {
            throw BackupError.exportFailed("AES-GCM encryption produced an incomplete box")
        }

        let headerData = try BackupDateCoding.encoder().encode(header)
        guard headerData.count <= maxHeaderLength else {
            throw BackupError.exportFailed("Backup encryption header is too large")
        }

        var envelope = Data()
        envelope.append(magic)
        let headerCount = UInt32(headerData.count)
        envelope.append(contentsOf: [
            UInt8(truncatingIfNeeded: headerCount >> 24),
            UInt8(truncatingIfNeeded: headerCount >> 16),
            UInt8(truncatingIfNeeded: headerCount >> 8),
            UInt8(truncatingIfNeeded: headerCount)
        ])
        envelope.append(headerData)
        envelope.append(combined)
        return envelope
    }

    static func decrypt(envelope: Data, password: String?) throws -> Data {
        guard envelope.count > magic.count + 4, envelope.starts(with: magic) else {
            throw BackupError.invalidArchive
        }
        let headerLength = readUInt32BE(envelope, offset: magic.count)
        guard headerLength > 0, headerLength <= maxHeaderLength else {
            throw BackupError.invalidArchive
        }
        let headerStart = magic.count + 4
        let headerEnd = headerStart + Int(headerLength)
        guard envelope.count > headerEnd else { throw BackupError.invalidArchive }
        let header: Header
        do {
            header = try BackupDateCoding.decoder().decode(
                Header.self,
                from: envelope.subdata(in: headerStart..<headerEnd)
            )
        } catch {
            throw BackupError.invalidArchive
        }
        guard header.formatIdentifier == BackupManifest.expectedFormatIdentifier,
              header.cipher == Header.aes256GCM,
              let salt = Data(base64Encoded: header.salt),
              salt.count == saltSize else {
            throw BackupError.invalidArchive
        }
        guard header.version == currentVersion,
              header.kdf == Header.hkdfSHA256 || header.kdf == Header.pbkdf2SHA256 else {
            throw BackupError.encryptedArchiveUnsupported
        }

        let key: SymmetricKey
        switch header.keySource {
        case Header.passwordSource:
            guard let password else { throw BackupError.passwordRequired }
            let iterations = header.iterations ?? pbkdf2Iterations
            guard iterations > 0, iterations <= 5_000_000 else {
                throw BackupError.encryptedArchiveUnsupported
            }
            key = try derivePasswordKey(password: password, salt: salt, iterations: iterations)
        case Header.deviceSource:
            do {
                key = try deriveDeviceKey(salt: salt)
            } catch {
                throw BackupError.deviceBoundBackupUnreadable
            }
        default:
            throw BackupError.encryptedArchiveUnsupported
        }

        let combined = envelope.subdata(in: headerEnd..<envelope.count)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            if header.keySource == Header.deviceSource {
                throw BackupError.deviceBoundBackupUnreadable
            }
            throw BackupError.decryptionFailed
        }
    }

    private static func derivePasswordKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        var derived = Data(count: keySize)
        let status: Int32 = password.withCString { pointer in
            derived.withUnsafeMutableBytes { derivedBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pointer,
                        password.utf8.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        keySize
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw BackupError.exportFailed("PBKDF2 key derivation failed")
        }
        return SymmetricKey(data: derived)
    }

    private static func deriveDeviceKey(salt: Data) throws -> SymmetricKey {
        let wrapping = try BackupWrappingKeyStore.loadOrCreate()
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: wrapping,
            salt: salt,
            info: hkdfInfo,
            outputByteCount: keySize
        )
    }

    private static func readUInt32BE(_ data: Data, offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}

nonisolated enum BackupWrappingKeyStore {
    static let service = Bundle.main.bundleIdentifier.map { "\($0).backup-keys" }
        ?? "Gao.Chenkai.StudyPulse.backup-keys"
    static let account = "backup-wrapping-key-v1"

    private static let store = KeychainStore(service: service)
    private static let override = OverrideBox()

    private final class OverrideBox: @unchecked Sendable {
        let lock = NSLock()
        var data: Data?
    }

    /// Test-only injection. Production code must leave this `nil` so the
    /// wrapping key comes from Keychain.
    static func setOverrideKeyForTesting(_ key: SymmetricKey?) {
        override.lock.lock()
        defer { override.lock.unlock() }
        if let key {
            override.data = key.withUnsafeBytes { Data($0) }
        } else {
            override.data = nil
        }
    }

    static func loadOrCreate() throws -> SymmetricKey {
        override.lock.lock()
        let injected = override.data
        override.lock.unlock()
        if let injected, injected.count == BackupEncryption.keySize {
            return SymmetricKey(data: injected)
        }
        if let existing = try store.read(account: account),
           let data = Data(base64Encoded: existing),
           data.count == BackupEncryption.keySize {
            return SymmetricKey(data: data)
        }
        var bytes = [UInt8](repeating: 0, count: BackupEncryption.keySize)
        let status = SecRandomCopyBytes(kSecRandomDefault, BackupEncryption.keySize, &bytes)
        guard status == errSecSuccess else {
            throw BackupError.exportFailed("Could not generate backup wrapping key")
        }
        let data = Data(bytes)
        try store.write(data.base64EncodedString(), account: account)
        return SymmetricKey(data: data)
    }
}
