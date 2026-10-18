//
//  AIModeRootView.swift
//  StudyPulse
//
//  Full-screen AI Mode. On iPhone the drawer slides the main panel to the
//  right; on wide iPad layouts the sidebar is fixed. The main panel hosts a
//  NavigationStack so data rows and source chips push the app's existing
//  detail screens without leaving the space.
//

import SwiftUI

struct AIModeRootView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel: AIModeViewModel
    @State private var path: [AIModeRoute] = []
    /// Finger travel of the drawer drag; the panel follows it one to one, with no animation.
    @State private var dragOffset: CGFloat = 0
    /// Whether the message list keeps scrolling to the newest text. Off once the reader drags away from the bottom.
    @State private var followsBottom = true
    @State private var userIsScrolling = false
    /// How far the list is from its bottom edge, updated every frame without invalidating the view.
    @State private var scrollMetrics = ScrollMetrics()
    @State private var scrollPosition = ScrollPosition()
    /// Whether the current drag drives the drawer (decided once, from its first movement).
    @State private var dragDrivesDrawer: Bool?
    /// The composer's glass in screen coordinates, so the reasoning slider can float right above it.
    @State private var composerGlass: CGRect = .zero

    init(container: RepositoryContainer, hrvManager: HealthKitManager) {
        _viewModel = State(initialValue: AIModeViewModel.makeDefault(container: container, hrvManager: hrvManager))
    }

    private var appearance: AIModeAppearance {
        container.envManager.preferences.aiModeAppearance.flatMap(AIModeAppearance.init(rawValue:)) ?? .pureBlue
    }

    private var theme: AIModeTheme { .make(appearance) }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 900
            let drawerWidth: CGFloat = wide ? 320 : max(geo.size.width - 58, 260)
            Group {
                if wide {
                    HStack(spacing: 0) {
                        sidebar.frame(width: drawerWidth)
                        Divider().overlay(theme.line)
                        mainPanel.background(theme.paper.ignoresSafeArea())
                    }
                } else {
                    compactLayout(drawerWidth: drawerWidth)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(theme.drawer.ignoresSafeArea())
        .environment(\.aiTheme, theme)
        .tint(theme.accent)
        .task { viewModel.dataViewModel.recompute() }
        .onChange(of: viewModel.dataViewModel.inputSignature) { _, _ in
            viewModel.dataViewModel.recompute()
        }
        .sheet(isPresented: Binding(
            get: { viewModel.needsHealthConsent },
            set: { if !$0 { viewModel.declineHealthConsent() } }
        )) {
            HealthDataLLMConsentSheet { allowed in
                if allowed { viewModel.retryAfterHealthConsent() } else { viewModel.declineHealthConsent() }
            }
            .environment(container)
        }
    }

    // MARK: Layouts

    private var drawerSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0.08)
    }

    private func compactLayout(drawerWidth: CGFloat) -> some View {
        let open = viewModel.drawerOpen
        let base: CGFloat = open ? drawerWidth : 0
        // The panel sits exactly where the finger puts it, clamped to the drawer's travel.
        let offset = min(max(base + dragOffset, 0), drawerWidth)
        let progress = drawerWidth > 0 ? offset / drawerWidth : 0
        return ZStack(alignment: .leading) {
            theme.drawer.ignoresSafeArea()
            sidebar
                .frame(width: drawerWidth)
                // A little parallax: the drawer slides out from under the panel as it opens.
                .offset(x: (progress - 1) * 40)
                .opacity(offset > 0 ? 1 : 0)
                .allowsHitTesting(open)
                .accessibilityHidden(!open)
            mainPanel
                .background {
                    // Full-screen card: the shape ignores the safe area so the rounded
                    // corners sit on the screen edge while content stays inside it.
                    RoundedRectangle(cornerRadius: offset > 0 ? 36 : 0, style: .continuous)
                        .fill(theme.paper)
                        .shadow(color: .black.opacity(0.10 * progress), radius: 14, x: -4)
                        .ignoresSafeArea()
                }
                .offset(x: offset)
                .overlay {
                    if open {
                        Color.black.opacity(0.001)
                            .offset(x: offset)
                            .onTapGesture { setDrawer(false) }
                            .accessibilityLabel("aiMode.drawer.close".localized())
                            .accessibilityAddTraits(.isButton)
                    }
                }
        }
        .animation(drawerSpring, value: viewModel.drawerOpen)
        .simultaneousGesture(drawerDrag(drawerWidth: drawerWidth), including: path.isEmpty ? .all : .subviews)
    }

    /// Drags the drawer with the finger. Closed, it starts from the leading edge; open, from anywhere.
    /// Release picks the side the panel was heading to, using the predicted end so a flick works.
    private func drawerDrag(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                if dragDrivesDrawer == nil {
                    let horizontal = abs(value.translation.width) > abs(value.translation.height)
                    let fromEdge = value.startLocation.x < 48
                    dragDrivesDrawer = horizontal && (viewModel.drawerOpen || fromEdge)
                    if dragDrivesDrawer == true {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                guard dragDrivesDrawer == true else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let drove = dragDrivesDrawer == true
                dragDrivesDrawer = nil
                guard drove else { return }
                let base: CGFloat = viewModel.drawerOpen ? drawerWidth : 0
                let projected = base + value.predictedEndTranslation.width
                let shouldOpen = projected > drawerWidth / 2
                withAnimation(drawerSpring) {
                    viewModel.drawerOpen = shouldOpen
                    dragOffset = 0
                }
            }
    }

    private func setDrawer(_ open: Bool) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(drawerSpring) { viewModel.drawerOpen = open }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        AIModeSidebar(
            viewModel: viewModel,
            appearance: appearance,
            onSetAppearance: { container.envManager.setAIModeAppearance($0) },
            onOpenAISettings: {
                viewModel.closeDrawer()
                path.append(.aiSettings)
            },
            onExit: { dismiss() }
        )
    }

    // MARK: Main panel

    private var mainPanel: some View {
        NavigationStack(path: $path) {
            sceneContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .containerBackground(theme.paper, for: .navigation)
                .navigationDestination(for: AIModeRoute.self) { route in
                    destination(route)
                }
        }
    }

    @ViewBuilder
    private var sceneContent: some View {
        switch viewModel.scene {
        case .welcome:
            chatScaffold {
                AIModeWelcomeView(viewModel: viewModel, onOpenAISettings: { path.append(.aiSettings) })
            }
        case .chat:
            chatScaffold { messageList }
        case .data(let domain):
            AIModeDataPage(domain: domain, viewModel: viewModel, onDrawer: { setDrawer(true) })
                .id(domain)
        }
    }

    private func chatScaffold<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .aiModeToolbar(
                title: viewModel.conversation?.title ?? "",
                showsWordmark: viewModel.scene == .welcome,
                trailing: viewModel.scene == .welcome ? .none : .newChat,
                onDrawer: { setDrawer(true) },
                onTrailing: { viewModel.newConversation() }
            )
            // The glass composer floats over the replies; the system softens the scroll edge behind it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AIModeComposer(viewModel: viewModel)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        // Strip the composer's outer padding (12 sides, 4 top, 8 bottom) to get its glass surface.
                        composerGlass = CGRect(
                            x: frame.minX + 12, y: frame.minY + 4,
                            width: max(frame.width - 24, 0), height: max(frame.height - 12, 0)
                        )
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .aiReasoningOverlay(viewModel: viewModel, anchor: composerGlass)
            }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(viewModel.messages) { message in
                    AIModeMessageView(message: message, viewModel: viewModel, onOpenSource: open)
                        .id(message.id)
                }
            }
            // 26pt: the lifted reply's card reaches 12pt past its text and swells 2%.
            .padding(.horizontal, 26)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($scrollPosition)
        .scrollDismissesKeyboard(.interactively)
        // Short chats grow downward from the top; only a reopened conversation starts at the bottom. A blanket
        // bottom anchor pins short content to the bottom edge and fights the follow-scroll, so it shivers.
        .defaultScrollAnchor(.top)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        // Follow the reply only while the reader is at the bottom. A drag upward hands the scroll view back to
        // them until they return to the bottom, so streaming never fights the finger.
        .onScrollPhaseChange { _, phase in
            userIsScrolling = phase == .interacting || phase == .decelerating
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentSize.height + geometry.contentInsets.bottom
                - geometry.contentOffset.y - geometry.containerSize.height
        } action: { _, distance in
            scrollMetrics.distance = distance
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let distance = geometry.contentSize.height + geometry.contentInsets.bottom
                - geometry.contentOffset.y - geometry.containerSize.height
            return distance < 72
        } action: { _, nearBottom in
            // Content growing under a still reader also reads as "away from the bottom"; only the reader moves it.
            if userIsScrolling { followsBottom = nearBottom }
        }
        .onChange(of: viewModel.messages.count) { _, _ in
            // A new turn (the reader's own question, or the reply's first frame) always brings the bottom back.
            followsBottom = true
            guard scrollMetrics.distance > 2 else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { scrollPosition.scrollTo(edge: .bottom) }
        }
        .onChange(of: viewModel.messages.last?.status) { _, _ in
            // A failed / stopped / finished reply grows (retry actions, sources); keep it in view if it was followed.
            guard followsBottom, scrollMetrics.distance > 2 else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { scrollPosition.scrollTo(edge: .bottom) }
        }
        .onChange(of: viewModel.messages.last?.content.count) { _, _ in
            // Short content that still fits needs no scrolling.
            guard viewModel.isGenerating, followsBottom, !userIsScrolling, scrollMetrics.distance > 2 else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { scrollPosition.scrollTo(edge: .bottom) }
        }
    }

    // MARK: Source routing

    private func open(_ source: AISourceLink) {
        if let route = AIModeRoute(source: source) {
            path.append(route)
        } else if let domain = source.domain {
            viewModel.showData(domain)
        }
    }

    // MARK: Destinations

    @ViewBuilder
    private func destination(_ route: AIModeRoute) -> some View {
        switch route {
        case .mistake(let id):
            if let note = container.mistakeRepo.mistakeSets.first(where: { $0.id == id }) {
                MistakeSetDetailView(mistakeSet: note)
            } else {
                AIMissingRecordView()
            }
        case .exam(let id):
            if container.examRepo.examSets.contains(where: { $0.id == id }) {
                ExamDetailView(examId: id)
            } else {
                AIMissingRecordView()
            }
        case .comprehensiveExam(let id):
            if let exam = container.examRepo.comprehensiveExamSets.first(where: { $0.id == id }) {
                ComprehensiveExamDetailView(exam: exam)
            } else {
                AIMissingRecordView()
            }
        case .diary:
            DiaryView()
        case .timeInvestment:
            TimeInvestmentView(container: container)
        case .subject(let name):
            AIModeSubjectDestination(subject: name, container: container)
        case .aiSettings:
            LLMSettingsView()
        case .healthSettings:
            HealthSettingsView()
        }
    }
}

/// Shown when a cited record was deleted after the answer was written.
private struct AIMissingRecordView: View {
    var body: some View {
        ContentUnavailableView(
            "aiMode.record.missing.title".localized(),
            systemImage: "tray",
            description: Text("aiMode.record.missing.message".localized())
        )
    }
}

/// Hosts `SubjectDetailView` with its own trends view model.
private struct AIModeSubjectDestination: View {
    let subject: String
    @State private var viewModel: TrendsViewModel
    @State private var mode: TrendsDisplayMode = .score

    init(subject: String, container: RepositoryContainer) {
        self.subject = subject
        _viewModel = State(initialValue: TrendsViewModel.makeDefault(container: container))
    }

    var body: some View {
        SubjectDetailView(subject: subject, viewModel: viewModel, displayMode: $mode)
            .task { viewModel.recompute() }
    }
}


/// A plain reference box: written every scroll frame, read on demand, never observed.
private final class ScrollMetrics {
    var distance: CGFloat = 0
}
