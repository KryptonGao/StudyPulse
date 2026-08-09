//
//  ContributionSettingsView.swift
//  StudyPulse
//
//  设置页 - 贡献指南 (Contribution Guide)
//  内容从 CONTRIBUTING.json 加载,使用 List + DisclosureGroup 展开模式呈现。
//

import SwiftUI
import SwiftStreamingMarkdown

// MARK: - 数据模型 (Codable)

/// 贡献指南顶层文档结构
struct ContributionDocument: Codable {
    let version: String
    let lastUpdated: String
    let title: String
    let subtitle: String
    let repository: String
    let license: String
    let welcome: String
    let sections: [ContributionSection]
}

/// 贡献指南章节
struct ContributionSection: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let items: [ContributionItem]
}

/// 贡献指南单条目
struct ContributionItem: Codable, Identifiable, Hashable {
    let id: String
    let icon: String?
    let title: String
    let content: String
}

// MARK: - 加载器

/// 负责从 Bundle / 备用路径加载并解析 CONTRIBUTING.json
enum ContributionLoader {
    @MainActor
    static func load() async -> Result<ContributionDocument, Error> {
        // 1. 主 Bundle
        if let url = Bundle.main.url(forResource: "CONTRIBUTING", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let doc = try JSONDecoder().decode(ContributionDocument.self, from: data)
                return .success(doc)
            } catch {
                return .failure(error)
            }
        }
        // 2. 仓库文档目录(开发态回退)
        let candidates = [
            "/Users/chenkaigao/Documents/Program/Swift/StudyPulse/docs/reference/CONTRIBUTING.json"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: path))
                    let doc = try JSONDecoder().decode(ContributionDocument.self, from: data)
                    return .success(doc)
                } catch {
                    return .failure(error)
                }
            }
        }
        return .failure(ContributionLoadError.fileNotFound)
    }
}

private enum ContributionLoadError: LocalizedError {
    case fileNotFound
    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "CONTRIBUTING.json was not found in the app bundle."
        }
    }
}

// MARK: - 主视图

struct ContributionSettingsView: View {
    @State private var document: ContributionDocument? = nil
    @State private var loadError: String? = nil
    @State private var searchText: String = ""

    var body: some View {
        Group {
            if let document {
                contentList(document: document)
            } else if let loadError {
                errorView(message: loadError)
            } else {
                loadingView
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .containerBackground(.clear, for: .navigation)
        .debugModeContainer()
        .debugLayoutBoundsAuto()
        .navigationTitle("Contribution".localized())
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Guide".localized()
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .task {
            await loadDoc()
        }
    }

    // MARK: 内容列表

    @ViewBuilder
    private func contentList(document: ContributionDocument) -> some View {
        let sections = filteredSections(in: document)
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let totalMatched = sections.reduce(0) { $0 + $1.items.count }

        List {
            Section {
                headerCard(document: document)
            }

            if isSearching {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                        Text("\(totalMatched) result\(totalMatched == 1 ? "" : "s") for \"\(searchText)\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            } else {
                // 欢迎语区块
                Section {
                    welcomeCard(text: document.welcome)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }

            if sections.isEmpty && isSearching {
                Section {
                    noResultsView(query: searchText)
                        .listRowInsets(EdgeInsets(top: 32, leading: 16, bottom: 32, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            ContributionRow(item: item, searchQuery: searchText)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    } header: {
                        sectionHeader(section: section)
                    }
                }
            }

            Section {
                footerNote(document: document)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: 过滤逻辑

    private func filteredSections(in doc: ContributionDocument) -> [ContributionSection] {
        let raw = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return doc.sections }
        let query = raw.lowercased()
        return doc.sections.compactMap { section in
            let matched = section.items.filter { item in
                item.title.lowercased().contains(query) ||
                item.content.lowercased().contains(query)
            }
            guard !matched.isEmpty else { return nil }
            return ContributionSection(
                id: section.id,
                title: section.title,
                icon: section.icon,
                items: matched
            )
        }
    }

    // MARK: 头部卡片

    private func headerCard(document: ContributionDocument) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.purple.opacity(0.18))
                Image(systemName: "hand.raised.fingers.spread.fill")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundColor(.purple)
            }
            .frame(width: 110, height: 110)

            Text(document.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(document.subtitle)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                metaItem(icon: "doc.text", text: "CONTRIBUTING.json")
                Divider().frame(height: 12)
                metaItem(icon: "calendar", text: document.lastUpdated)
                Divider().frame(height: 12)
                metaItem(icon: "doc.badge.gearshape", text: document.license)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: 欢迎语卡片

    private func welcomeCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("Welcome".localized())
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            if text.contains("**") || text.contains("\n-") || text.contains("`") {
                MarkdownView(text: text, config: .previewConfig)
            } else {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.purple.opacity(0.08))
        )
    }

    private func metaItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundColor(.secondary)
    }

    // MARK: 无结果视图

    private func noResultsView(query: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No results found".localized())
                .font(.headline)
            Text("No contribution entry matches \"\(query)\".".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                searchText = ""
            } label: {
                Label("Clear search".localized(), systemImage: "xmark.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 章节头

    private func sectionHeader(section: ContributionSection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: section.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.purple)
            Text(section.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            Text("(\(section.items.count))")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: 加载 / 错误

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading...".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Contribution Guide Not Available".localized())
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("Please add CONTRIBUTING.json to the StudyPulse target in Xcode (Copy Bundle Resources).".localized())
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 底部注释

    private func footerNote(document: ContributionDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption)
                Text("Repository: \(document.repository)")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                Text("Content stored in CONTRIBUTING.json and shipped as a bundle resource.".localized())
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
    }

    // MARK: 加载

    private func loadDoc() async {
        let result = await ContributionLoader.load()
        switch result {
        case .success(let doc):
            document = doc
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }
}

// MARK: - 单条贡献条目行 (DisclosureGroup)

struct ContributionRow: View {
    let item: ContributionItem
    var searchQuery: String = ""
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            contentView
                .padding(.top, 8)
                .padding(.leading, 4)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.purple.opacity(0.12))
                    Image(systemName: item.icon ?? "chevron.right.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.purple)
                }
                .frame(width: 30, height: 30)

                highlightedTitle
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var highlightedTitle: some View {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Text(item.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            highlightedText(item.title, query: trimmed)
                .font(.system(size: 15, weight: .medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func highlightedText(_ text: String, query: String) -> Text {
        var attr = AttributedString(text)
        let lowerQuery = query.lowercased()
        // 在 AttributedString 上直接搜索(不依赖 NSRange 转换)
        var searchStart = attr.startIndex
        while searchStart < attr.endIndex,
              let range = attr[searchStart..<attr.endIndex].range(of: lowerQuery, options: .caseInsensitive) {
            attr[range].backgroundColor = .yellow.opacity(0.45)
            attr[range].foregroundColor = .primary
            searchStart = range.upperBound
        }
        return Text(attr)
    }

    @ViewBuilder
    private var contentView: some View {
        if item.content.contains("**") || item.content.contains("\n-") || item.content.contains("`") || item.content.contains("```") {
            MarkdownView(text: item.content, config: .previewConfig)
                .padding(.vertical, 4)
        } else {
            Text(item.content)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        ContributionSettingsView()
    }
}
