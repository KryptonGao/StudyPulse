import Foundation

@MainActor
@Observable
final class BackupRestoreViewModel {
    enum Operation: Equatable {
        case idle
        case exporting
        case validating
        case restoring
    }

    var includesMedia = true
    var includesDerivedHealthData = false
    var backupPassword = ""
    var restorePassword = ""
    var operation: Operation = .idle
    var progress: Double = 0
    var exportDocument: BackupDocument?
    var exportFilename = "StudyPulse.studypulsebackup"
    var validatedBackup: ValidatedBackup?
    var restoreMode: BackupRestoreMode = .replace
    var message: String?
    var errorMessage: String?
    var showExporter = false
    var showImporter = false
    var showRestoreConfirmation = false

    var lastBackupAt: Date? {
        UserDefaults.standard.object(forKey: "studyPulse.lastFullBackupAt") as? Date
    }

    var isBusy: Bool { operation != .idle }

    func createBackup(container: RepositoryContainer) {
        guard !isBusy else { return }
        operation = .exporting
        progress = 0
        errorMessage = nil
        Task {
            defer { operation = .idle }
            do {
                let result = try await BackupExporter.export(
                    container: container,
                    options: BackupExportOptions(
                        includesMedia: includesMedia,
                        includesDerivedHealthData: includesDerivedHealthData,
                        password: backupPassword
                    ),
                    progress: { [weak self] in self?.progress = $0 }
                )
                let data = try await Task.detached {
                    try Data(contentsOf: result.archiveURL)
                }.value
                exportDocument = BackupDocument(data: data)
                exportFilename = result.archiveURL.lastPathComponent
                try? FileManager.default.removeItem(at: result.archiveURL)
                showExporter = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func validate(url: URL, forRestore: Bool) {
        guard !isBusy else { return }
        operation = .validating
        progress = 0.1
        errorMessage = nil
        validatedBackup?.cleanup()
        validatedBackup = nil
        Task {
            defer { operation = .idle }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let value = try await BackupValidator.validate(
                    archiveURL: url,
                    password: restorePassword
                )
                validatedBackup = value
                progress = 1
                if forRestore {
                    showRestoreConfirmation = true
                } else {
                    message = "Backup validation succeeded.".localized()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func restore(container: RepositoryContainer) {
        guard let validatedBackup, !isBusy else { return }
        operation = .restoring
        progress = 0
        errorMessage = nil
        Task {
            defer {
                operation = .idle
                validatedBackup.cleanup()
                self.validatedBackup = nil
            }
            do {
                let result = try await BackupRestoreCoordinator.restore(
                    validated: validatedBackup,
                    mode: restoreMode,
                    container: container,
                    progress: { [weak self] in self?.progress = $0 }
                )
                message = String(
                    format: "Restore completed with %d warning(s).".localized(),
                    result.warnings.count
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

}
