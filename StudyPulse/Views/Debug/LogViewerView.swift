//
//  LogViewerView.swift
//  StudyPulse
//
//  In-app 日志查看器（Debug 模式 → 日志查看器）。
//  Renders the in-memory LogStore buffer with level / category filters and search.
//
//  数据源：LogStore actor 的快照（最多 5000 条）
//  Source: a snapshot from the LogStore actor (max 5000 entries)
//

import SwiftUI
import UniformTypeIdentifiers
import os

struct LogViewerView: View {
    @State private var allEntries: [LogEntry] = []
    @State private var levelFilter: LogLevel? = nil
    @State private var categoryFilter: String? = nil
    @State private var searchText: String = ""
    @State private var selectedEntry: LogEntry? = nil
    @State private var showingClearConfirm: Bool = false

    // Export state
    @State private var isExportingLog = false
    @State private var exportLogDocument: LogDocument? = nil

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            entryList
            footer
        }
        .navigationTitle("debug.logViewer".localized())
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        exportLog()
                    } label: {
                        Label("Export Log".localized(), systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showingClearConfirm = true
                    } label: {
                        Label("debug.clearLogs".localized(), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            while !Task.isCancelled {
                allEntries = await LogStore.shared.allEntries
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .sheet(item: $selectedEntry) { entry in
            LogEntryDetailSheet(entry: entry)
        }
        .alert("debug.clearLogs".localized(), isPresented: $showingClearConfirm) {
            Button("Cancel".localized(), role: .cancel) {}
            Button("Clear".localized(), role: .destructive) {
                Task {
                    await LogStore.shared.clear()
                    allEntries = []
                }
            }
        } message: {
            Text("debug.clearLogsConfirm".localized())
        }
        .fileExporter(
            isPresented: $isExportingLog,
            document: exportLogDocument,
            contentType: .log,
            defaultFilename: exportLogDocument?.fileName
        ) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                exportLogDocument = nil
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Level filter
            Menu {
                Button {
                    levelFilter = nil
                } label: {
                    Label("All".localized(), systemImage: levelFilter == nil ? "checkmark" : "")
                }
                Divider()
                ForEach([LogLevel.debug, .info, .notice, .warning, .error, .fault], id: \.self) { level in
                    Button {
                        levelFilter = level
                    } label: {
                        HStack {
                            Text(level.displayName)
                            if levelFilter == level {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                FilterChip(
                    title: levelFilter?.displayName ?? "All".localized(),
                    systemImage: levelFilter == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill",
                    isActive: levelFilter != nil
                )
            }

            // Category filter
            Menu {
                Button {
                    categoryFilter = nil
                } label: {
                    Label("All".localized(), systemImage: categoryFilter == nil ? "checkmark" : "")
                }
                Divider()
                ForEach(knownCategories, id: \.self) { cat in
                    Button {
                        categoryFilter = cat
                    } label: {
                        HStack {
                            Text(cat)
                            if categoryFilter == cat {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                FilterChip(
                    title: categoryFilter ?? "All".localized(),
                    systemImage: "tag",
                    isActive: categoryFilter != nil
                )
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Entry List

    private var entryList: some View {
        let filtered = filteredEntries
        return Group {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No Data".localized(),
                    systemImage: "doc.text",
                    description: Text("No log entries match the current filters.".localized())
                )
            } else {
                List {
                    ForEach(filtered) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            LogEntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        let total = allEntries.count
        let shown = filteredEntries.count
        return HStack {
            Text("\(shown) / \(total) " + "entries".localized())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Max 5000 (FIFO)".localized())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Helpers

    private var filteredEntries: [LogEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allEntries.reversed().filter { entry in
            if let lvl = levelFilter, entry.level != lvl { return false }
            if let cat = categoryFilter, entry.category != cat { return false }
            if !q.isEmpty {
                return entry.message.lowercased().contains(q)
                    || entry.category.lowercased().contains(q)
            }
            return true
        }
    }

    private var knownCategories: [String] {
        var seen: Set<String> = []
        return allEntries.compactMap { entry in
            seen.insert(entry.category).inserted ? entry.category : nil
        }
    }

    private func exportLog() {
        Task { @MainActor in
            let logText = await LogStore.shared.exportAsText()
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "StudyPulse_Log_\(df.string(from: Date())).log"
            exportLogDocument = LogDocument(content: logText, fileName: fileName)
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            isExportingLog = true
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let systemImage: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .scaledFont(size: 11)
            Text(title)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(isActive ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill))
        )
        .foregroundColor(isActive ? .accentColor : .primary)
    }
}

// MARK: - Row

private struct LogEntryRow: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .scaledFont(size: 11, design: .monospaced)
                    .foregroundColor(.secondary)
                Text(entry.level.displayName)
                    .scaledFont(size: 10, weight: .bold, design: .monospaced)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(entry.level.badgeColor.opacity(0.18))
                    .foregroundColor(entry.level.badgeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(entry.category)
                    .scaledFont(size: 10, design: .monospaced)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color(.tertiarySystemFill))
                    .foregroundColor(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Spacer(minLength: 0)
            }
            Text(entry.message)
                .scaledFont(size: 12, design: .monospaced)
                .foregroundColor(.primary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail Sheet

private struct LogEntryDetailSheet: View {
    let entry: LogEntry
    @Environment(\.dismiss) private var dismiss
    @State private var copyConfirm: Bool = false

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    detailRow("Timestamp".localized(), value: Self.isoFormatter.string(from: entry.timestamp))
                    detailRow("Level".localized(), value: entry.level.displayName)
                    detailRow("Category".localized(), value: entry.category)
                    Divider()
                    Text("Message".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.message)
                        .scaledFont(size: 13, design: .monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Log Entry".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close".localized()) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = entry.message
                        copyConfirm = true
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("a11y.copy".localized())
                }
            }
            .alert("Copied".localized(), isPresented: $copyConfirm) {
                Button("OK".localized()) {}
            } message: {
                Text("Log message copied to clipboard.".localized())
            }
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .scaledFont(size: 13, design: .monospaced)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - LogLevel Display

private extension LogLevel {
    var displayName: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        }
    }

    var badgeColor: Color {
        switch self {
        case .debug: return .gray
        case .info: return .blue
        case .notice: return .indigo
        case .warning: return .orange
        case .error: return .red
        case .fault: return .pink
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        LogViewerView()
    }
}
#endif
