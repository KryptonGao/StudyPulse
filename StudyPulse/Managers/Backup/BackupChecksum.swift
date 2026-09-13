import CryptoKit
import Foundation

nonisolated enum BackupChecksum {
    static func sha256(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Canonical HMAC message: sorted `path=sha256` lines. Independent of
    /// `checksums.json` JSON formatting so authenticity tracks file hashes,
    /// not pretty-print noise.
    static func canonicalIntegrityMessage(checksums: BackupChecksums) -> Data {
        var lines = ["checksum-algorithm=\(checksums.algorithm.uppercased())"]
        for path in checksums.files.keys.sorted() {
            let digest = (checksums.files[path] ?? "").lowercased()
            lines.append("\(path)=\(digest)")
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    static func makeIntegrity(checksums: BackupChecksums, password: String?) throws -> BackupIntegrity {
        let salt = try BackupEncryption.makeRandomSalt()
        let keySource = password == nil
            ? BackupEncryption.Header.deviceSource
            : BackupEncryption.Header.passwordSource
        let kdf = password == nil
            ? BackupEncryption.Header.hkdfSHA256
            : BackupEncryption.Header.pbkdf2SHA256
        let iterations = password == nil ? nil : BackupEncryption.pbkdf2Iterations
        let key = try BackupEncryption.deriveIntegrityKey(
            keySource: keySource,
            password: password,
            salt: salt,
            iterations: iterations
        )
        let mac = HMAC<SHA256>.authenticationCode(
            for: canonicalIntegrityMessage(checksums: checksums),
            using: key
        )
        return BackupIntegrity(
            algorithm: BackupIntegrity.hmacSHA256,
            keySource: keySource,
            kdf: kdf,
            salt: salt.base64EncodedString(),
            iterations: iterations,
            mac: mac.map { String(format: "%02x", $0) }.joined()
        )
    }

    static func verifyIntegrity(
        _ integrity: BackupIntegrity,
        checksums: BackupChecksums,
        password: String?
    ) throws {
        guard integrity.algorithm.uppercased() == BackupIntegrity.hmacSHA256 else {
            throw BackupError.authenticationFailed
        }
        guard integrity.kdf == BackupEncryption.Header.hkdfSHA256
            || integrity.kdf == BackupEncryption.Header.pbkdf2SHA256 else {
            throw BackupError.encryptedArchiveUnsupported
        }
        guard let salt = Data(base64Encoded: integrity.salt) else {
            throw BackupError.authenticationFailed
        }
        let key: SymmetricKey
        do {
            key = try BackupEncryption.deriveIntegrityKey(
                keySource: integrity.keySource,
                password: BackupEncryption.normalizedPassword(password),
                salt: salt,
                iterations: integrity.iterations
            )
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.authenticationFailed
        }
        guard let mac = data(fromHex: integrity.mac), mac.count == 32 else {
            throw BackupError.authenticationFailed
        }
        let message = canonicalIntegrityMessage(checksums: checksums)
        guard HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: message, using: key) else {
            throw BackupError.authenticationFailed
        }
    }

    static func data(fromHex hex: String) -> Data? {
        let normalized = hex.lowercased()
        guard normalized.count == 64, normalized.count.isMultiple(of: 2),
              normalized.allSatisfy(\.isHexDigit) else {
            return nil
        }
        var data = Data(capacity: 32)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let next = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
