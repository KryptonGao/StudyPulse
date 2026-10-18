//
//  AIModeSidebar.swift
//  StudyPulse
//
//  The drawer of AI Mode, built from native pieces: a sidebar-style `List`
//  (six data entries, grouped conversation history with swipe / context actions),
//  system `.searchable`, and an account menu (appearance, AI settings, back to the
//  normal app) next to the "new chat" button.
//

import SwiftUI

struct AIModeSidebar: View {
    var viewModel: AIModeViewModel
    let appearance: AIModeAppearance
    let onSetAppearance: (AIModeAppearance) -> Void
    let onOpenAISettings: () -> Void
    let onExit: () -> Void

    @Environment(\.aiTheme) private var theme
    @State private var renaming: AIConversation?
    @State private var renameText = ""
    @State private var deleting: AIConversation?

    var body: some View {
        @Bindable var vm = viewModel
        NavigationStack {
            List {
                if !isSearching {
                    Section("aiMode.sidebar.myData".localized()) {
                        ForEach(AIDataDomain.allCases) { domain in
                            dataRow(domain)
                        }
                    }
                }
                history
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(theme.drawer)
            .scrollDismissesKeyboard(.interactively)
            .searchable(
                text: $vm.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "aiMode.sidebar.search".localized()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Label {
                        Text("aiMode.title".localized()).font(.title3.weight(.semibold))
                    } icon: {
                        Image(systemName: "leaf.fill").foregroundStyle(theme.accent)
                    }
                    .labelStyle(.titleAndIcon)
                    .accessibilityElement(children: .combine)
                }
            }
            .containerBackground(theme.drawer, for: .navigation)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .background(theme.drawer)
        .alert("aiMode.history.rename".localized(), isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField("aiMode.history.renamePlaceholder".localized(), text: $renameText)
            Button("Cancel".localized(), role: .cancel) { renaming = nil }
            Button("OK".localized()) {
                if let target = renaming { viewModel.rename(target.id, title: renameText) }
                renaming = nil
            }
        }
        .confirmationDialog(
            "aiMode.history.deleteConfirm".localized(),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("aiMode.history.delete".localized(), role: .destructive) {
                if let target = deleting { viewModel.delete(target.id) }
                deleting = nil
            }
            Button("Cancel".localized(), role: .cancel) { deleting = nil }
        }
    }

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Data entries

    private func meta(for domain: AIDataDomain) -> String? {
        let meta = viewModel.dataViewModel.meta
        switch domain {
        case .grades: return meta.subjectCount > 0 ? String(format: "aiMode.meta.subjects".localized(), meta.subjectCount) : nil
        case .mistakes: return meta.dueMistakeCount > 0 ? String(format: "aiMode.meta.due".localized(), meta.dueMistakeCount) : nil
        case .exams: return meta.upcomingExamCount > 0 ? String(format: "aiMode.meta.exams".localized(), meta.upcomingExamCount) : nil
        case .time, .health, .diary: return nil
        }
    }

    private func dataRow(_ domain: AIDataDomain) -> some View {
        Button {
            viewModel.showData(domain)
        } label: {
            HStack {
                Label(AIModeLabels.domainName(domain), systemImage: domain.systemImage)
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 0)
                if let meta = meta(for: domain) {
                    Text(meta).font(.footnote).foregroundStyle(theme.muted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: History

    @ViewBuilder
    private var history: some View {
        let groups = viewModel.historyGroups
        if groups.isEmpty {
            Section {
                Text(isSearching ? "aiMode.history.noResults".localized() : "aiMode.history.empty".localized())
                    .font(.footnote)
                    .foregroundStyle(theme.muted)
                    .listRowBackground(Color.clear)
            }
        } else {
            ForEach(groups) { group in
                Section(group.titleKey.localized()) {
                    ForEach(group.conversations) { conversation in
                        historyRow(conversation)
                    }
                }
            }
        }
    }

    private func historyRow(_ conversation: AIConversation) -> some View {
        let active = viewModel.conversation?.id == conversation.id
        return Button {
            viewModel.open(conversation.id)
        } label: {
            Label(
                conversation.title.isEmpty ? "aiMode.history.untitled".localized() : conversation.title,
                systemImage: "bubble.left"
            )
            .lineLimit(1)
            .foregroundStyle(theme.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(active ? theme.soft : Color.clear)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleting = conversation
            } label: { Label("aiMode.history.delete".localized(), systemImage: "trash") }
            Button {
                renameText = conversation.title
                renaming = conversation
            } label: { Label("aiMode.history.rename".localized(), systemImage: "pencil") }
            .tint(theme.accent)
        }
        .contextMenu {
            Button {
                renameText = conversation.title
                renaming = conversation
            } label: { Label("aiMode.history.rename".localized(), systemImage: "pencil") }
            Button(role: .destructive) {
                deleting = conversation
            } label: { Label("aiMode.history.delete".localized(), systemImage: "trash") }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("aiMode.menu.appearance".localized(), selection: Binding(
                    get: { appearance }, set: { onSetAppearance($0) }
                )) {
                    Text("aiMode.appearance.pureBlue".localized()).tag(AIModeAppearance.pureBlue)
                    Text("aiMode.appearance.warmSerif".localized()).tag(AIModeAppearance.warmSerif)
                }
                Button(action: onOpenAISettings) {
                    Label("aiMode.menu.aiSettings".localized(), systemImage: "slider.horizontal.3")
                }
                Button(action: onExit) {
                    Label("aiMode.menu.exit".localized(), systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "person.fill")
                    .font(.body)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .tint(theme.ink)
            .accessibilityLabel("aiMode.menu.title".localized())

            Button {
                viewModel.newConversation()
            } label: {
                Label("aiMode.sidebar.newChat".localized(), systemImage: "plus")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.drawer)
    }
}
