//
//  QASettingsView.swift
//  StudyPulse
//
//  设置页 - 常见问题 (FAQ)
//  内容从 FAQ.json 加载,使用 List + DisclosureGroup 展开模式呈现。
//  支持 .searchable() 全文搜索与匹配高亮。
//

import SwiftUI
import SwiftStreamingMarkdown

// MARK: - 数据模型 (Codable)

/// FAQ 顶层文档结构
struct FAQDocument: Codable {
    let version: String
    let lastUpdated: String
    let title: String
    let subtitle: String
    let categories: [FAQCategory]
}

/// FAQ 分类
struct FAQCategory: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let items: [FAQItem]
}

/// FAQ 单条问答
struct FAQItem: Codable, Identifiable, Hashable {
    let id: String
    let icon: String?
    let question: String
    let answer: String
}

// MARK: - 加载器

/// 负责从 Bundle / 备用路径加载并解析 FAQ.json
enum FAQLoader {
    /// 加载 FAQ 内容,优先从主 Bundle 读取,缺失时回退到仓库文档目录
    @MainActor
    static func load() async -> Result<FAQDocument, Error> {
        // 1. 主 Bundle
        if let url = Bundle.main.url(forResource: "FAQ", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let doc = try JSONDecoder().decode(FAQDocument.self, from: data)
                return .success(doc)
            } catch {
                return .failure(error)
            }
        }
        // 2. 仓库文档目录(开发态回退)
        let candidates = [
            "/Users/chenkaigao/Documents/Program/Swift/StudyPulse/docs/reference/FAQ.json"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: path))
                    let doc = try JSONDecoder().decode(FAQDocument.self, from: data)
                    return .success(doc)
                } catch {
                    return .failure(error)
                }
            }
        }
        return .failure(FAQLoadError.fileNotFound)
    }
}

private enum FAQLoadError: LocalizedError {
    case fileNotFound
    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "FAQ.json was not found in the app bundle."
        }
    }
}

// MARK: - 主视图

struct QASettingsView: View {
    @State private var document: FAQDocument? = nil
    @State private var loadError: String? = nil
    @State private var searchText: String = ""

    var body: some View {
        Group {
            if let document {
                faqList(document: document)
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
        .navigationTitle("FAQ".localized())
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search FAQ".localized()
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .task {
            await loadFAQ()
        }
    }

    // MARK: 列表

    @ViewBuilder
    private func faqList(document: FAQDocument) -> some View {
        let categories = filteredCategories(in: document)
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let totalMatched = categories.reduce(0) { $0 + $1.items.count }

        List {
            Section {
                headerCard(document: document)
            }

            if isSearching {
                Section {
                    searchStatusBar(matched: totalMatched)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }

            if categories.isEmpty && isSearching {
                Section {
                    noResultsView(query: searchText)
                        .listRowInsets(EdgeInsets(top: 32, leading: 16, bottom: 32, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(categories) { category in
                    Section {
                        ForEach(category.items) { item in
                            QARow(item: item, searchQuery: searchText)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    } header: {
                        categoryHeader(category: category)
                    }
                }
            }

            Section {
                footerNote
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: 过滤逻辑

    private func filteredCategories(in doc: FAQDocument) -> [FAQCategory] {
        let raw = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return doc.categories }
        let query = raw.lowercased()
        return doc.categories.compactMap { category in
            let matched = category.items.filter { item in
                item.question.lowercased().contains(query) ||
                item.answer.lowercased().contains(query)
            }
            guard !matched.isEmpty else { return nil }
            return FAQCategory(
                id: category.id,
                title: category.title,
                icon: category.icon,
                items: matched
            )
        }
    }

    // MARK: 头部卡片 (修复对齐 - 使用 listRowBackground 与 list 行边对齐)

    private func headerCard(document: FAQDocument) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.blue.opacity(0.18))
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundColor(.blue)
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
                metaItem(icon: "doc.text", text: "FAQ.json")
                Divider().frame(height: 12)
                metaItem(icon: "calendar", text: document.lastUpdated)
                Divider().frame(height: 12)
                metaItem(icon: "list.bullet.rectangle", text: "\(totalCount(of: document)) Q&A")
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

    private func metaItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundColor(.secondary)
    }

    private func totalCount(of doc: FAQDocument) -> Int {
        doc.categories.reduce(0) { $0 + $1.items.count }
    }

    // MARK: 搜索状态条

    private func searchStatusBar(matched: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
            Text("\(matched) result\(matched == 1 ? "" : "s") for \"\(searchText)\"")
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
            .accessibilityLabel("Clear search")
        }
        .padding(.vertical, 4)
    }

    // MARK: 无结果视图

    private func noResultsView(query: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No results found".localized())
                .font(.headline)
            Text("No FAQ item matches \"\(query)\".".localized())
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

    // MARK: 分类头

    private func categoryHeader(category: FAQCategory) -> some View {
        HStack(spacing: 8) {
            Image(systemName: category.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue)
            Text(category.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            Text("(\(category.items.count))")
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
            Text("Loading FAQ...".localized())
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
            Text("FAQ Not Available".localized())
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("Please add FAQ.json to the StudyPulse target in Xcode (Copy Bundle Resources).".localized())
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 底部注释

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                Text("FAQ content is stored in FAQ.json and shipped as a bundle resource.".localized())
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "envelope")
                    .font(.caption)
                Text("Still have questions? Reach us via Settings → About → Feedback.".localized())
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
    }

    // MARK: 加载 FAQ

    private func loadFAQ() async {
        let result = await FAQLoader.load()
        switch result {
        case .success(let doc):
            document = doc
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }
}

// MARK: - 单条问答行 (DisclosureGroup)

struct QARow: View {
    let item: FAQItem
    var searchQuery: String = ""
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            answerView
                .padding(.top, 8)
                .padding(.leading, 4)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                    Image(systemName: item.icon ?? "questionmark.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                }
                .frame(width: 30, height: 30)

                highlightedQuestion
            }
        }
        .padding(.vertical, 6)
    }

    /// 高亮问题文本中的搜索匹配
    @ViewBuilder
    private var highlightedQuestion: some View {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Text(item.question)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            highlightedText(item.question, query: trimmed)
                .font(.system(size: 15, weight: .medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 用 AttributedString 高亮匹配子串
    private func highlightedText(_ text: String, query: String) -> Text {
        var attr = AttributedString(text)
        var searchStart = attr.startIndex
        while searchStart < attr.endIndex,
              let range = attr[searchStart..<attr.endIndex].range(of: query, options: .caseInsensitive) {
            attr[range].backgroundColor = .yellow.opacity(0.45)
            attr[range].foregroundColor = .primary
            searchStart = range.upperBound
        }
        return Text(attr)
    }

    /// 答案渲染:行内 Markdown(`**bold**` / 列表 / `code`),借助 SwiftStreamingMarkdown
    @ViewBuilder
    private var answerView: some View {
        if item.answer.contains("**") || item.answer.contains("\n-") || item.answer.contains("`") {
            // 含 Markdown 的答案
            MarkdownView(text: item.answer, config: .previewConfig)
                .padding(.vertical, 4)
        } else {
            Text(item.answer)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 辅助扩展

private extension NSRange {
    /// 将 NSRange 转换为 String 的 Range<String.Index>
    func range(in text: String) -> Range<String.Index>? {
        guard location != NSNotFound,
              let utf16Start = text.utf16.index(text.utf16.startIndex,
                                                 offsetBy: location,
                                                 limitedBy: text.utf16.endIndex),
              let utf16End = text.utf16.index(utf16Start,
                                              offsetBy: length,
                                              limitedBy: text.utf16.endIndex),
              let start = String.Index(utf16Start, within: text),
              let end = String.Index(utf16End, within: text) else {
            return nil
        }
        return start..<end
    }
}

#Preview {
    NavigationStack {
        QASettingsView()
    }
}
