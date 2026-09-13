import Foundation

nonisolated enum BackupError: LocalizedError, Sendable {
    case invalidArchive
    case missingManifest
    case invalidFormatIdentifier
    case unsupportedFormatVersion(Int)
    case encryptedArchiveUnsupported
    case passwordRequired
    case decryptionFailed
    case encryptionInconsistent
    case deviceBoundBackupUnreadable
    case dangerousPath(String)
    case missingRequiredFile(String)
    case checksumMismatch(String)
    case malformedData(String)
    case invalidRelationship(String)
    case countMismatch(String)
    case exportFailed(String)
    case restoreFailed(String)
    case rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "The selected file is not a valid StudyPulse backup.".localized()
        case .missingManifest: return "The backup manifest is missing.".localized()
        case .invalidFormatIdentifier: return "This file was not created by StudyPulse backup.".localized()
        case .unsupportedFormatVersion(let version): return String(format: "Backup format version %d is not supported.".localized(), version)
        case .encryptedArchiveUnsupported: return "This encrypted backup format is not supported by this version.".localized()
        case .passwordRequired: return "A password is required to open this backup.".localized()
        case .decryptionFailed: return "Could not decrypt the backup.".localized()
        case .encryptionInconsistent: return "The backup encryption flag does not match the archive.".localized()
        case .deviceBoundBackupUnreadable: return "This encrypted backup cannot be read on this device.".localized()
        case .dangerousPath: return "The backup contains an unsafe file path.".localized()
        case .missingRequiredFile(let path): return String(format: "Required backup file is missing: %@".localized(), path)
        case .checksumMismatch(let path): return String(format: "Backup integrity check failed for %@.".localized(), path)
        case .malformedData(let path): return String(format: "Backup data could not be decoded: %@".localized(), path)
        case .invalidRelationship(let detail): return String(format: "Backup relationships are invalid: %@".localized(), detail)
        case .countMismatch(let kind): return String(format: "Backup record count does not match for %@.".localized(), kind)
        case .exportFailed(let detail): return String(format: "Could not create backup: %@".localized(), detail)
        case .restoreFailed(let detail): return String(format: "Could not restore backup: %@".localized(), detail)
        case .rollbackFailed(let detail): return String(format: "Restore failed and the recovery point could not be reapplied: %@".localized(), detail)
        }
    }
}
