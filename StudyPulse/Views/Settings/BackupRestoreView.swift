import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(RepositoryContainer.self) private var container
    @State private var viewModel = BackupRestoreViewModel()
    @State private var importPurpose: ImportPurpose = .restore

    private enum ImportPurpose { case restore, validate }

    var body: some View {
        Form {
            Section {
                Toggle("Include media files".localized(), isOn: $viewModel.includesMedia)
                Toggle("Include body status history".localized(), isOn: $viewModel.includesDerivedHealthData)
                SecureField("Backup password (optional)".localized(), text: $viewModel.backupPassword)
                SecureField("Restore password (if set)".localized(), text: $viewModel.restorePassword)
            } header: {
                Text("Backup contents".localized())
            } footer: {
                Text("Body status history is health-related sensitive information. It is excluded by default. Backups that include diary, health history, coach conversations, or media are encrypted. Leave the backup password empty to use this device's key; set a password to restore on another device.".localized())
            }

            Section {
                Button {
                    viewModel.createBackup(container: container)
                } label: {
                    Label("Create Full Backup".localized(), systemImage: "archivebox")
                }
                Button {
                    importPurpose = .restore
                    viewModel.showImporter = true
                } label: {
                    Label("Restore from Backup".localized(), systemImage: "arrow.counterclockwise")
                }
                Button {
                    importPurpose = .validate
                    viewModel.showImporter = true
                } label: {
                    Label("Validate Backup".localized(), systemImage: "checkmark.shield")
                }
                if let date = viewModel.lastBackupAt {
                    LabeledContent("Last backup".localized(), value: date.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .disabled(viewModel.isBusy)

            if viewModel.isBusy {
                Section {
                    ProgressView(value: viewModel.progress)
                    Text(operationLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let backup = viewModel.validatedBackup {
                backupSummary(backup)
            }
        }
        .navigationTitle("Full Backup & Restore".localized())
        .fileExporter(
            isPresented: $viewModel.showExporter,
            document: viewModel.exportDocument,
            contentType: .studyPulseBackup,
            defaultFilename: viewModel.exportFilename
        ) { result in
            if case .failure(let error) = result {
                viewModel.errorMessage = error.localizedDescription
            } else {
                viewModel.message = "Backup created successfully.".localized()
            }
            viewModel.exportDocument = nil
        }
        .fileImporter(
            isPresented: $viewModel.showImporter,
            allowedContentTypes: [.studyPulseBackup, .zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.validate(url: url, forRestore: importPurpose == .restore)
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Confirm Restore".localized(),
            isPresented: $viewModel.showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Picker("Restore mode".localized(), selection: $viewModel.restoreMode) {
                Text("Replace current data (Recommended)".localized()).tag(BackupRestoreMode.replace)
                Text("Merge by UUID".localized()).tag(BackupRestoreMode.merge)
            }
            Button(
                viewModel.restoreMode == .replace
                    ? "Replace Current Data".localized()
                    : "Merge Backup".localized(),
                role: .destructive
            ) {
                viewModel.restore(container: container)
            }
            Button("Cancel".localized(), role: .cancel) {}
        } message: {
            Text("Replace mode overwrites current backed-up data. A recovery point is created automatically first.".localized())
        }
        .alert("Backup".localized(), isPresented: Binding(
            get: { viewModel.message != nil },
            set: { if !$0 { viewModel.message = nil } }
        )) {
            Button("OK".localized()) {}
        } message: {
            Text(viewModel.message ?? "")
        }
        .alert("Backup Error".localized(), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK".localized()) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func backupSummary(_ backup: ValidatedBackup) -> some View {
        Section("Backup Summary".localized()) {
            LabeledContent("Created".localized(), value: backup.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("App version".localized(), value: "\(backup.manifest.appVersion) (\(backup.manifest.appBuild))")
            LabeledContent("Format version".localized(), value: "\(backup.manifest.formatVersion)")
            LabeledContent("Records".localized(), value: "\(backup.manifest.recordCounts.values.reduce(0, +))")
            LabeledContent("Media".localized(), value: "\(backup.manifest.mediaFileCount) · \(ByteCountFormatter.string(fromByteCount: backup.manifest.mediaBytes, countStyle: .file))")
            LabeledContent("Health history".localized(), value: backup.manifest.includesDerivedHealthData ? "Included".localized() : "Excluded".localized())
            LabeledContent("Encrypted".localized(), value: backup.manifest.encrypted ? "Yes".localized() : "No".localized())
            LabeledContent("Integrity".localized(), value: "Verified".localized())
            if !backup.warnings.isEmpty {
                Label(
                    String(format: "%d warning(s)".localized(), backup.warnings.count),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
            DisclosureGroup("Record counts".localized()) {
                ForEach(backup.manifest.recordCounts.keys.sorted(), id: \.self) { key in
                    LabeledContent(key, value: "\(backup.manifest.recordCounts[key] ?? 0)")
                }
            }
        }
    }

    private var operationLabel: String {
        switch viewModel.operation {
        case .idle: ""
        case .exporting: "Creating backup…".localized()
        case .validating: "Validating backup…".localized()
        case .restoring: "Restoring data…".localized()
        }
    }
}
