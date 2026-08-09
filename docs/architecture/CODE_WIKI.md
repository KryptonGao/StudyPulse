# StudyPulse — Code Wiki

> A comprehensive code reference for the StudyPulse iOS app. This file provides the full picture with tables, ASCII flowcharts and diagrams.

---

## Table of Contents

1. Getting Started
2. Architecture Overview
3. Repository Layout
4. Data Models Reference
5. Managers Reference
6. Views Reference
7. Home Card System
8. Education Systems
9. HRV / HealthKit Subsystem
9.5 LLM (BYOK) Subsystem
9.6 Audio (Voice Memos) Subsystem
10. Image, OCR and CSV Pipelines
11. iPad Adaptation
12. Localization
13. Privacy Permissions
14. Widget Extension
15. Dependencies (SPM)
16. Build & Run
17. Coding Standards
18. Performance Notes
19. Known Issues / TODO
20. Changelog (Agent-Facing)

---

## 1. Getting Started

### 1.1 Prerequisites

| Item | Requirement |
|---|---|
| macOS | 15.0 or higher |
| Xcode | 26.x (26.3 recommended) |
| iOS Deployment Target | 18.6+ |
| Swift | 6.0 |
| Supported Devices | iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) |

### 1.2 Quick Start

```bash
# Clone the repository and open in Xcode
open StudyPulse.xcodeproj

# Resolve Swift packages
# Xcode → File → Packages → Resolve Package Versions
# Then Cmd+R to run
```

CLI build:

```bash
./scripts/build.sh              # Debug, iPhone 17 simulator
./scripts/build.sh release      # Release
./scripts/build.sh clean        # Clean build folder
./scripts/build.sh list         # List available simulators
```

### 1.3 Key Concepts

| Concept | Description |
|---|---|
| Architecture | MVVM + Repository; views inject `RepositoryContainer` via `@Environment(RepositoryContainer.self)`; ViewModels are `@MainActor ObservableObject` |
| Persistence | SwiftData `@Model` entity layer (`Models/SwiftData/StudyPulseModels.swift`) backed by `ModelContainer`; legacy JSON files in `~/Documents/*.json` migrated on first launch via `ModelContainerFactory.migrateFromJSONIfNeeded` |
| Image / Audio | `~/Documents/images/grade_UUID.jpg` / `avatar_UUID.jpg`; custom backgrounds in `Application Support/Backgrounds/bg_<uuid>.jpg`; voice memos in `~/Documents/audio/<uuid>.m4a` |
| Preferences | UserDefaults — `AppPreferences` (lang / theme / chart / accent / glass / heatmap / phase / debug / **LLM BYOK**) + `HomeLayoutPreference` + HRV prefs + migration flag |
| Startup | `StudyPulseApp` calls `container.asyncInit()` inside `.task`; then `hrvManager.bootstrap()` + `AchievementManager.shared.bootstrap(container:)` |
| Global Education | 15+ education systems (CN, UK, IB, AP, SAT, ACT, GRE, GMAT, TOEFL, IELTS, DSE, etc.) |
| Universal Layout | iPhone TabView + iPad NavigationSplitView with `iPadLayout` helpers |
| HRV / Readiness | Apple Watch SDNN (HRV) + multi-dim BodyStatus; 14-day HRV baseline + 30-day personal baselines; Z-score classification; 5-intensity × 5-focus grid |
| Customizable Home | 11 card types (incl. `learningHeatmap` / `streakProgress` / `homeAsk`), drag-to-reorder + per-card on/off; iPad two-column `LazyVGrid` with full-width `block` rendering |
| Liquid Glass | Global `AppPreferences.glassEffectEnabled`; `.glassCard(enabled:cornerRadius:)` opt-in modifier using iOS 26 `glassEffect` (fallback to `.regularMaterial`) |
| Custom Accent | 11 `ThemeAccent` presets (system/blue/cyan/teal/green/mint/orange/red/pink/purple/indigo) |
| BYOK LLM | 4 user-facing AI features (StudySuggestions / MistakeAI / WeeklyReport / HomeAsk) + 1 settings page; OpenAI Chat Completions compatible; falls back to local silently on failure |
| Audio | Voice memos on Mistake — `AVAudioRecorder` (record) + `AVAudioPlayer` (play) |

---

## 2. Architecture Overview

StudyPulse follows an **MVVM + Repository** pattern. SwiftUI views read state through ViewModels that own `@Published` data from a `RepositoryContainer`; the container aggregates 7 `@MainActor` Repository classes that read / write to a SwiftData `ModelContainer`. Pure-function business logic lives in `Services/` (no SwiftUI dependencies). Models are `nonisolated value type` `Codable` structs that the views consume directly, mapped bidirectionally to SwiftData `@Model` entities for persistence.

### 2.1 Layer Diagram

```
+---------------------------------------------------------------------------+
|                          StudyPulse iOS App                                |
+---------------------------------------------------------------------------+
|                                                                           |
|  +-------------- Presentation (SwiftUI, @MainActor) -------------------+ |
|  |  ContentView                                                         | |
|  |   |- iPhone TabView (5 tabs: Home / Trends / Mistakes / Exams / ...)| |
|  |   '- iPad NavigationSplitView (sidebar + detail)                    | |
|  |                                                                      | |
|  |  HomeView | TrendsView | MistakeView | ExamView | TodoView | ...     | |
|  |   + dynamic cards driven by HomeLayoutPreference                    | |
|  |   + sheets: AddGradeView, NewExamSetView, NewMistakeSetView,        | |
|  |             HomeAskSheet, MistakeAIAnalysisSheet, ...                | |
|  +----------------------------------------------------------------------+ |
|                              |                                            |
|                              v  (@Environment(RepositoryContainer.self))  |
|  +---------------- ViewModel Layer (@MainActor) ------------------------+ |
|  |  HomeViewModel  | TrendsViewModel  | MistakeViewModel                | |
|  |  ExamViewModel  | TodoViewModel    | SubjectMistakesViewModel         | |
|  |   - static func makeDefault(container:)                             | |
|  |   - @Published private(set) state                                   | |
|  +----------------------------------------------------------------------+ |
|                              |                                            |
|                              v                                            |
|  +---------------- Repository Layer (@MainActor) -----------------------+ |
|  |  RepositoryContainer (@Observable @MainActor)                        | |
|  |   - 7 Repositories (Grade/Mistake/Exam/Task/Phase/Profile/Subject)   | |
|  |   - modelContainer, isReady, pendingIntentAction                     | |
|  |   - facade: addGrade / addMistake / addExams / activatePhase ...     | |
|  +----------------------------------------------------------------------+ |
|                              |                                            |
|                              v                                            |
|  +---------------- Persistence Layer (SwiftData) ------------------------+ |
|  |  @Model entities (SubjectRecord / GradeRecord / MistakeNoteRecord /   | |
|  |  ExamRecord / ComprehensiveExamRecord / UserProfileRecord /          | |
|  |  TaskItemRecord / ReviewStateRecord / StudyPhaseRecord)              | |
|  |   - toSnapshot() / init(from:) bidirectional mapping                 | |
|  |   - @Attribute(.unique) id; @Attribute(.externalStorage) Data        | |
|  |   - #Index<...> on phaseId for fast phase filtering                  | |
|  +----------------------------------------------------------------------+ |
|                              |                                            |
|                              v                                            |
|  +---------------- Service Layer (pure functions) ----------------------+ |
|  |  DateFormatters  | SubjectAggregator  | SuggestionEngine              | |
|  |  ExamFilter      | MistakeFilter      | QuoteProvider                 | |
|  +----------------------------------------------------------------------+ |
|                                                                           |
|  +---------------- Cross-cutting Managers -------------------------------+ |
|  |  Core:        AppEnvironmentManager  |  RepositoryContainer           | |
|  |               ModelContainerFactory  |  CSVDocument | AppStyle       | |
|  |  Health:      HealthKitManager  |  StudyReadinessAlgorithm  |        | |
|  |               HealthHistoryStore                                  | |
|  |  LLM (BYOK):  LLMClient  | LLMConfig  | LLMError  | LLMPrompt       | |
|  |               LLMRequestBuilder  | LLMResponseParser              | |
|  |               HomeAskDataProvider                                  | |
|  |  Audio:       AudioStorage  | VoiceMemoManager                    | |
|  |  Logging:     Log  | LogStore  | LogDocument  | LagMonitor        | |
|  |  PDF:         MistakePDFRenderer  | MistakePDFDocument             | |
|  |  Report:      ReportRenderer  | ReportImageDocument               | |
|  |  Study:       StudyTimerManager  | DailyGoalReminder  | SRS*Notif  | |
|  |               ExamReviewNotifications                              | |
|  |  Achievement: AchievementManager  | AchievementStore                | |
|  |  Utility:     CalendarManager  | EducationConfig  | ImageCache      | |
|  |               OCRManager  | SubjectInfo  | StringsLocalized         | |
|  |  Widget:      ExamWidgetData + Sync  | HRVWidgetData + Sync         | |
|  |               TrendWidgetData + Sync                                 | |
|  +----------------------------------------------------------------------+ |
|                                                                           |
+---------------------------------------------------------------------------+
```

### 2.2 Module Dependency Graph

```
+-------------------------+      +------------------------+      +------------------------+
| Views (SwiftUI)         | ---> | ViewModels              | ---> | RepositoryContainer    |
|  HomeView, TrendsView,   |      | (@MainActor              |      |  (@Observable)          |
|  MistakeView, ExamView,  |      |  ObservableObject)      |      |                        |
|  TodoView, +sheets      |      |  static makeDefault()   |      |  7 @MainActor          |
+-------------------------+      +------------------------+      |  Repositories          |
             |                                                  +-----------+------------+
             |                                                              |
             |                                                              v
             |                                                  +------------------------+
             |                                                  | SwiftData ModelContainer|
             |                                                  |  @Model entities        |
             |                                                  +-----------+------------+
             |                                                              |
             | (Views may also call LLMClient.shared for AI features)      |
             v                                                              v
+-------------------------+      +------------------------+      +------------------------+
| LLMClient.shared        |      | HealthKitManager       |      | WidgetDataSyncManager  |
|  (BYOK, OpenAI-compat)  |      |  (HRV + BodyStatus)    |      |  (App Group container) |
+-------------------------+      +------------------------+      +------------------------+
```

Services (pure functions: `SubjectAggregator`, `SuggestionEngine`, `ExamFilter`, `MistakeFilter`, `DateFormatters`, `QuoteProvider`) are called by ViewModels and Views directly — they don't depend on SwiftUI (except `QuoteProvider` because `StudySuggestion.color: Color`).

### 2.3 Data Persistence Flow

```
[App Launch]
StudyPulseApp
  └─ .task { await container.asyncInit() }
       ├─ ModelContainerFactory.makeContainer()         (singleton)
       ├─ migrateFromJSONIfNeeded(context:)              (one-shot, UserDefaults flag)
       ├─ 7 Repositories serial loadAll(context:)        (Task.detached, MainActor.assign)
       ├─ gradeRepo.migrateInlineImagesIfNeeded()         (image Data → files)
       ├─ subjectRepo.initializeDefaultSubjects()         (first run only)
       ├─ observeActivePhaseChanges()                    (0.5s polling)
       └─ isReady = true
            ├─ hrvManager.bootstrap()
            └─ AchievementManager.shared.bootstrap(container:)

[User Edit]
View → ViewModel method
   └─ container.addGrade(grade)              (facade)
        ├─ gradeRepo.add(grade) → SwiftData context.insert + save
        ├─ @Published var grades updated → SwiftUI re-render
        ├─ AchievementManager.shared.recordGradeRecorded()
        ├─ TrendWidgetSyncManager.syncTrend(...)
        └─ SubjectAggregator caches invalidated
```

---

## 3. Repository Layout

```
StudyPulse/
├── StudyPulse.xcodeproj/                  # Xcode project (StudyPulse + StudyPulseWidgetExtension targets)
│
├── Packages/                              # Local / vendored SPM packages
│   ├── SwiftStreamingMarkdown-0.2.0/      # Markdown + LaTeX streaming render
│   └── Vendored/                          # swift-cmark / swift-markdown / highlightswift / iosMath
│
├── StudyPulse/                            # Main app sources
│   ├── StudyPulseApp.swift                # @main entry; container + hrv/StudyTimer singletons; .task asyncInit
│   ├── StudyPulse.entitlements            # HealthKit + App Groups + Live Activities
│   ├── StudyPulseWidgetExtension.entitlements
│   ├── Assets.xcassets                    # AccentColor / AppIcon / StudyPulseIcon (SVG)
│   │
│   ├── Models/                            # Data models
│   │   ├── DataModels.swift               # Subject / Grade / MistakeNote / Exam / comprehensiveExam /
│   │   │                                  # ExamTimeSlot / UserProfile / TaskItem / TaskType / TodoEntry
│   │   │                                  # StudyPhase / PhaseGoal / ExamChecklistItem / ExamReview
│   │   ├── AppPreferences.swift           # AppPreferences (lang/theme/chart/accent/glass/heatmap/phase/
│   │   │                                  #  cardSkin/timerAnimation/plant/debug/LLM BYOK); custom init(from:)
│   │   ├── HomeLayoutPreference.swift     # HomeCardItem[] (order + enabled)
│   │   ├── HealthHistory.swift            # DailyHealthSnapshot
│   │   ├── StudySession.swift
│   │   ├── SpacedRepetition.swift         # ReviewState (SM-2)
│   │   ├── Achievements.swift             # AchievementsSnapshot / DailyGoalConfig / StreakState
│   │   ├── AchievementCatalog.swift
│   │   ├── StudyReport.swift
│   │   ├── MistakePDFSnapshot.swift
│   │   └── SwiftData/
│   │       └── StudyPulseModels.swift     # @Model entities (9 types) + toSnapshot() / init(from:)
│   │
│   ├── Managers/                          # Cross-cutting managers
│   │   ├── Core/
│   │   │   ├── RepositoryContainer.swift  # @Observable @MainActor; 7 repos + modelContainer + isReady
│   │   │   ├── AppEnvironmentManager.swift# global AppPreferences + effectiveAccentColor + activePhaseId
│   │   │   ├── AppStyle.swift             # design system skeleton
│   │   │   ├── CSVDocument.swift          # FileDocument for CSV
│   │   │   ├── DataExportManager.swift    # CSV export (@MainActor enum)
│   │   │   └── ModelContainerFactory.swift# SwiftData singleton + JSON migration
│   │   ├── Health/
│   │   │   ├── HealthKitManager.swift     # HRV (SDNN) + BodyStatus
│   │   │   ├── HealthHistoryStore.swift   # 30-day DailyHealthSnapshot (NSLock)
│   │   │   └── StudyReadinessAlgorithm.swift # 5-intensity × 5-focus + BodyReadinessContext (LLM)
│   │   ├── Logging/
│   │   │   ├── Log.swift                  # LogLevel/LogEntry/LogStore (NSLock, 5000 entries)
│   │   │   ├── LogDocument.swift          # FileDocument
│   │   │   └── LagMonitor.swift           # CADisplayLink main-thread monitor
│   │   ├── PDF/
│   │   │   ├── MistakePDFRenderer.swift   # Core Text + NSAttributedString multi-page A4
│   │   │   └── MistakePDFDocument.swift
│   │   ├── Report/
│   │   │   ├── ReportRenderer.swift       # ImageRenderer + Core Graphics
│   │   │   └── ReportImageDocument.swift
│   │   ├── Study/
│   │   │   ├── StudyTimerManager.swift    # 5 intensity + Live Activity
│   │   │   ├── DailyGoalReminder.swift
│   │   │   ├── SRSReviewNotifications.swift
│   │   │   └── ExamReviewNotifications.swift
│   │   ├── Achievement/
│   │   │   ├── AchievementManager.swift   # @MainActor singleton; 3 record*() event entries
│   │   │   └── AchievementStore.swift     # NSLock JSON persistence
│   │   ├── Audio/
│   │   │   ├── AudioStorage.swift         # ~/Documents/audio/ file I/O
│   │   │   └── VoiceMemoManager.swift     # AVAudioRecorder session
│   │   ├── LLM/                           # BYOK LLM subsystem
│   │   │   ├── LLMConfig.swift            # immutable value type; AppPreferences bridge
│   │   │   ├── LLMError.swift             # 9 error cases
│   │   │   ├── LLMPrompt.swift            # system + messages
│   │   │   ├── LLMRequestBuilder.swift    # per-feature prompt factory
│   │   │   ├── LLMResponseParser.swift    # parse ## sections back to local model
│   │   │   ├── LLMClient.swift            # @MainActor singleton; complete / stream
│   │   │   └── HomeAskDataProvider.swift  # keyword → context category
│   │   ├── Utility/
│   │   │   ├── CalendarManager.swift      # EventKit
│   │   │   ├── EducationConfig.swift      # 15+ education systems
│   │   │   ├── ImageCache.swift           # nonisolated NSCache (50 items, 300px)
│   │   │   ├── OCRManager.swift           # Vision
│   │   │   ├── StringsLocalized.swift     # .localized()
│   │   │   └── SubjectInfo.swift
│   │   └── Widget/
│   │       ├── ExamWidgetData.swift       + WidgetDataSyncManager.swift
│   │       ├── HRVWidgetData.swift        + HRVWidgetSyncManager.swift
│   │       └── TrendWidgetData.swift      + TrendWidgetSyncManager.swift
│   │
│   ├── Repositories/                      # 7 domain repositories
│   │   ├── Protocols/                     # GradeRepository / MistakeRepository / ExamRepository /
│   │   │                                  # TaskRepository / PhaseRepository / ProfileRepository /
│   │   │                                  # SubjectRepository
│   │   ├── DefaultGradeRepository.swift
│   │   ├── DefaultMistakeRepository.swift
│   │   ├── DefaultExamRepository.swift
│   │   ├── DefaultTaskRepository.swift
│   │   ├── DefaultPhaseRepository.swift
│   │   ├── DefaultProfileRepository.swift
│   │   ├── DefaultSubjectRepository.swift
│   │   ├── ImageStorage.swift             # image file I/O
│   │   └── IntentActionStore.swift        # AppIntents cross-process bridge
│   │
│   ├── Services/                          # Pure-function helpers
│   │   ├── DateFormatters.swift
│   │   ├── SubjectAggregator.swift        # O(n) subject group/aggregate
│   │   ├── SuggestionEngine.swift         # StudySuggestionsContext → [StudySuggestion]
│   │   ├── ExamFilter.swift               # examsWithinDays / unregisteredExams
│   │   ├── MistakeFilter.swift
│   │   └── QuoteProvider.swift            # daily quote (only SwiftUI dependency: Color)
│   │
│   ├── ViewModels/                        # @MainActor ObservableObject
│   │   ├── HomeViewModel.swift            # SRS / recent grades / upcoming exams / chart subject / suggestions
│   │   ├── TrendsViewModel.swift
│   │   ├── MistakeViewModel.swift
│   │   ├── SubjectMistakesViewModel.swift
│   │   ├── ExamViewModel.swift
│   │   ├── TodoViewModel.swift
│   │   ├── LLMChatViewModel.swift         # in-memory conversation
│   │   ├── HomeAskViewModel.swift
│   │   └── ViewModelError.swift
│   │
│   ├── Views/                             # SwiftUI views
│   │   ├── ContentView.swift              # iPhone TabView / iPad NavigationSplitView
│   │   ├── Home/
│   │   │   ├── HomeView.swift
│   │   │   ├── HomeLayoutSettingsView.swift
│   │   │   ├── HomeUIState.swift
│   │   │   └── HomeCards/
│   │   │       ├── MainStatsCard / QuickActionsCard / RecentGradesCard / TrendChartCard
│   │   │       ├── StudySuggestionsCard  (LLM-augmented, 40-min cooldown)
│   │   │       ├── HRVStatusCard          (LLM-augmented, 40-min cooldown)
│   │   │       ├── StreakHomeCard / LearningHeatmapView (in Components/)
│   │   │       └── HomeAskCard            (LLM)
│   │   ├── Trends/TrendsView.swift
│   │   ├── Exam/                          # ExamView / ExamCalendarView / ExamDetailView /
│   │   │                                  # ExamDetailEditView / NewExamSetView / ExamReviewView /
│   │   │                                  # ScorePredictionEngine / ScorePredictionSheet
│   │   ├── Grade/AddGradeView.swift / SubjectScoreCard.swift
│   │   ├── Mistake/
│   │   │   ├── MistakeView.swift          (toolbar: PDF export, SRS enqueue, AI menu)
│   │   │   ├── MistakeDetailEditView.swift
│   │   │   ├── NewMistakeSetView.swift
│   │   │   ├── PDF/                       # MistakePDFExportSheet / MistakePDFGenerationView
│   │   │   ├── Audio/                     # AudioPlaybackView / VoiceMemoRecordingSheet
│   │   │   └── LLM/                       # AISimilarQuestionFlowView
│   │   ├── Flashcard/                     # FlashcardStudyView / CardView / SessionSummaryView / CalculatorView
│   │   ├── Todo/                          # TodoView / TodoRowView / NewTaskView / TaskDetailView / Edit
│   │   ├── Profile/                       # EditSubjectsView / PreferencesView / ProfileEditView
│   │   ├── StudyTimer/StudyTimerView.swift
│   │   ├── Report/                        # ReportContentView / ReportOptionsSheet / ReportShareSheet
│   │   ├── Settings/                      # SettingsView + 6-segment nav (Profile/Appearance/Health/
│   │   │                                  # Data/About/FAQ) + Achievements / DailyGoals / ChartType /
│   │   │                                  # Contribution / UserAgreement / PhaseManagement / PhaseEdit
│   │   ├── About/                         # AboutView / CopyrightView / HRVOnboardingView
│   │   ├── Admin/DataAdminView.swift
│   │   ├── OnBoarding/                    # OnboardingView (iOS 26 glass) + Flow + ProfileForm + Versioned
│   │   ├── LLM/                           # LLMSettingsView / LLMChatView / AIDiscussionSheet /
│   │   │                                  # MistakeAIAnalysisSheet / HomeAskSheet / HomeAskCard (in Home/)
│   │   │                                  # ChatBubble / ChatInputBar / LLMDebugSheet
│   │   ├── Components/                    # GradeChart / HRVStatus / LearningHeatmap / MasteryCurve /
│   │   │                                  # PhaseSelector / SectionHeader / StreakHome / StudyTimer /
│   │   │                                  # SubjectPicker / TrendChart / Markdown/ (Editor/Preview/TextEditor)
│   │   └── Helpers/                       # AvatarView / ImagePicker / PhotoCaptureView / ScoreColor /
│   │                                      # ZoomableImageView / iPadLayout
│   │
│   ├── Extensions/                        # AppleIntelligenceGradient / ColorExtensions / DateExtensions /
│   │                                      # GlassCardModifier
│   ├── Intents/                           # 6 AppIntents + IntentAction + IntentActionStore + SubjectEntity +
│   │                                      # IntentDataLoader + StudyPulseShortcuts
│   └── NotificationsControl/              # ExamPrepareNotifications
│
├── StudyPulseWidget/                      # WidgetKit + Live Activity
│   ├── ExamWidget.swift / Entry / Provider / Views (S/M/L)
│   ├── HRVWidget.swift / HRVWidgetData
│   ├── TrendWidget.swift / TrendWidgetData
│   ├── StudyTimerActivityAttributes.swift + StudyTimerLiveActivity.swift
│   ├── StudyPulseWidgetBundle.swift       # @main
│   └── en.lproj / zh-Hans.lproj / zh-Hant.lproj / ja.lproj / ko.lproj
│
├── TestData/                              # Sample CSVs + restore_sample_data.py
├── en.lproj / zh-Hans.lproj / zh-Hant.lproj / ja.lproj / ko.lproj
├── AGENTS.md / docs/architecture/CODE_WIKI.md / docs/architecture/CODE_WIKI_CN.md / README.md
└── scripts/build.sh
```

---

## 4. Data Models Reference

All models are `nonisolated value type` structs with `Codable + Sendable + Hashable` so they can be passed across actors without ceremony. Each persistent struct has a hand-written `init(from:)` + `CodingKeys` using `decodeIfPresent` to give defaults — required for backward-compatibility with old `UserDefaults` JSON.

### 4.1 Model Summary Table

| Model | File | Type | Persistence | Purpose |
|---|---|---|---|---|
| `Subject` | DataModels.swift | struct | SwiftData `SubjectRecord` | User subject list (name / displayName / enabled / fullScore) |
| `Grade` | DataModels.swift | struct | SwiftData `GradeRecord` | Single grade (with `imageFileName`, `phaseId?`) |
| `MistakeNote` | DataModels.swift | struct | SwiftData `MistakeNoteRecord` | 4-section mistake (each section's image file names; `reviewState?`; `phaseId?`; `audioFileName?`) |
| `Exam` | DataModels.swift | struct | SwiftData `ExamRecord` | Single-subject exam (`checklist` / `locationSchool` etc / `countdownNotifyDays` / `examReview?`; `phaseId?`) |
| `comprehensiveExam` | DataModels.swift | struct | SwiftData `ComprehensiveExamRecord` | Multi-subject exam (`phaseId?`) |
| `TaskItem` | DataModels.swift | struct | SwiftData `TaskItemRecord` | Homework / Reading (`phaseId?`) |
| `UserProfile` | DataModels.swift | struct | SwiftData `UserProfileRecord` | User profile + avatar + selectedSubjects |
| `StudyPhase` | DataModels.swift | struct | SwiftData `StudyPhaseRecord` | Study phase (semester / holiday) — `name` / `startDate` / `endDate` / `isArchived` / `goals` |
| `PhaseGoal` | DataModels.swift | struct | (in StudyPhase.goals) | Per-phase target score / notes |
| `AppPreferences` | AppPreferences.swift | struct | UserDefaults | lang / theme / chart / accent / glass / heatmap / phase / cardSkin / timerAnimation / plant / debug / **LLM BYOK** |
| `HomeLayoutPreference` | HomeLayoutPreference.swift | struct | UserDefaults | ordered `HomeCardItem[]` (with enabled flag + isFullWidth) |
| `HealthHistory` (`DailyHealthSnapshot`) | HealthHistory.swift | struct | `~/Documents/health_history.json` | 30-day rolling health snapshot |
| `StudySession` | StudySession.swift | struct | `~/Documents/study_sessions.json` | Completed study session (intensity / duration) |
| `ReviewState` (SM-2) | SpacedRepetition.swift | struct | (nested in MistakeNote) | SRS review state |
| `DailyGoalConfig` / `DailyActivityLog` / `StreakState` / `AchievementDefinition` / `AchievementProgress` / `AchievementsSnapshot` | Achievements.swift + AchievementCatalog.swift | struct | `~/Documents/achievements.json` (NSLock) | Streak + achievement system |
| `StudyReport` | StudyReport.swift | struct | in-memory | Immutable study report (used by `ReportRenderer`) |
| `MistakePDFSnapshot` / `MistakePDFSelection` | MistakePDFSnapshot.swift | struct / enum | in-memory | Immutable snapshot for PDF export |
| `LLMConfig` | LLMConfig.swift | struct (nonisolated, Sendable) | (transient — from `AppPreferences`) | LLM BYOK configuration snapshot |
| `LLMMessage` / `LLMRole` / `LLMPrompt` | LLMPrompt.swift | struct / enum (nonisolated, Sendable) | (transient) | Encapsulated messages for `LLMClient.complete/stream` |
| `LLMCallDebugInfo` | LLMClient.swift | struct (nonisolated, Sendable) | in-memory (20 entries) | Debug info for a single LLM call |
| `EducationStage` / `EducationCategory` / `SubjectConfig` / `EducationRegion` | DataModels.swift | enum / struct | (in `EducationConfig`) | Global education system registry |
| `ColorSchemeOption` / `ChartType` / `ThemeAccent` | AppPreferences.swift | enum | (in `AppPreferences`) | UI customization |
| `HomeCardType` / `HomeCardItem` | HomeLayoutPreference.swift | enum / struct | (in `HomeLayoutPreference`) | Home card system |

### 4.2 Subject Model

```swift
nonisolated struct Subject: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var displayName: String
    var enabled: Bool
    var fullScore: Double
}
```

### 4.3 Grade Model

```swift
nonisolated struct Grade: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var subject: String
    var score: Double
    var rawScore: Double?
    var ranking: Int?
    var importance: Int             // 1 ... 5
    var image: Data?                // legacy inline data; migrated to files
    var imageFileName: String?      // new file-based image (in images/)
    var date: Date
    var examName: String
    var fullScore: Double?          // per-record custom full-score
    var phaseId: UUID?              // study phase (nil = no phase)

    func scoreRate(subjectFullScore: Double = 100) -> Double
}
```

### 4.4 MistakeNote Model

```swift
nonisolated struct MistakeNote: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var subject: String
    var originalQuestion: String
    var source: String
    var date: Date
    var errorReason: String
    var wrongSolution: String
    var correctSolution: String

    // Per-section image files (in images/)
    var questionImages: [String]
    var reasonImages: [String]
    var wrongSolutionImages: [String]
    var correctSolutionImages: [String]

    // Voice memo
    var audioFileName: String?      // (in audio/)

    // SRS
    var reviewState: ReviewState?   // nil = not enqueued
    var phaseId: UUID?
}
```

### 4.5 Exam / comprehensiveExam / TaskItem

```swift
nonisolated struct Exam: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var subject: String                // single subject
    var examDate: Date
    var examEndDate: Date?             // multi-day exam
    var importance: Int                // 1...5
    var masteryDegree: Int             // 0 ... 100
    var notes: String
    var timeSlot: ExamTimeSlot?
    var checklist: [ExamChecklistItem]            // pre-exam checklist
    var locationSchool: String                     // exam location
    var locationClassroom: String
    var locationSeat: String
    var countdownNotifyDays: [Int]?               // nil = default [1,3,5,10,30]; [] = off
    var examReview: ExamReview?                    // post-exam review
    var phaseId: UUID?
}

nonisolated struct comprehensiveExam: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var subject: [String]            // multiple subjects
    var examDate: Date
    var examEndDate: Date?
    var importance: Int
    var masteryDegree: Int
    var notes: String
    var timeSlot: ExamTimeSlot?
    var phaseId: UUID?
}

nonisolated struct TaskItem: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var kind: TaskType                // .homework / .reading
    var dueDate: Date
    var reminderDate: Date?
    var notes: String
    var completed: Bool
    var reminderIdentifier: String?
    var subject: String?
    var phaseId: UUID?
}
```

### 4.6 UserProfile / StudyPhase

```swift
nonisolated struct UserProfile: Codable, Sendable {
    var username: String = "Student"
    var realName: String = ""
    var age: Int = 16
    var gender: String = "Not Specified"
    var grade: String = ""
    var className: String = ""
    var schoolName: String = ""
    var studentId: String = ""
    var enrollmentYear: Int
    var examYear: Int
    var targetSchool: String = ""
    var targetScore: Double = 0
    var educationStage: String        // EducationStage rawValue
    var regionCode: String             // EducationRegion name
    var selectedSubjects: [Subject] = []
    var theme: String = "Auto"
    var avatarFileName: String?
}

nonisolated struct StudyPhase: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var startDate: Date
    var endDate: Date
    var isArchived: Bool
    var archivedAt: Date?
    var goals: [PhaseGoal]            // per-subject target score + notes
    var createdAt: Date
}
```

### 4.7 AppPreferences & HomeLayoutPreference

```swift
struct AppPreferences: Codable {
    var appLanguage: String?                            // "en", "zh-Hans", ... nil = follow system
    var colorScheme: ColorSchemeOption = .system
    var chartType: ChartType = .line
    var accentPaletteId: String?                        // ThemeAccent rawValue
    var glassEffectEnabled: Bool = false                // iOS 26 Liquid Glass
    var learningHeatmapOnTrends: Bool = true
    var activePhaseId: UUID?
    var cardSkinId: String?
    var timerAnimationId: String?
    var plantCardEnabled: Bool = true
    var plantPetalColorId: String?
    // Debug
    var debugModeEnabled: Bool = false
    var debugVerboseLogging: Bool = false
    var debugFPSOverlay: Bool = false
    var debugLayoutBounds: Bool = false
    var debugLongPressInspect: Bool = false
    // LLM BYOK
    var llmEnabled: Bool = false
    var llmBaseURL: String?
    var llmAPIKey: String?
    var llmModel: String?
    var llmSystemPromptAppendix: String?
    var llmTemperature: Double = 0.7
    var lastRadarAIRequestTime: Date?                   // 40-min radar cooldown
    var lastStudySuggestionsAIRequestTime: Date?        // 40-min study-suggestions cooldown
    var debugOverrideSystemPrompt: String?              // DEBUG-only

    // custom init(from:) with decodeIfPresent defaults — see file
}

enum ColorSchemeOption: String, CaseIterable, Codable { case system, light, dark }
enum ChartType: String, CaseIterable, Codable { case line, bar, pie, scatter, heatmap, histogram }
enum ThemeAccent: String, CaseIterable { case system, blue, cyan, teal, green, mint, orange, red, pink, purple, indigo }

struct HomeLayoutPreference: Codable {
    var items: [HomeCardItem]          // ordered; each has enabled flag
}

struct HomeCardItem: Codable, Identifiable, Hashable {
    var id: String { type.rawValue }
    var type: HomeCardType
    var enabled: Bool
}

enum HomeCardType: String, CaseIterable, Codable {
    case hrvStatus
    case unregisteredExamsReminder
    case quickActions
    case studySuggestions
    case trendChart
    case upcomingExams
    case dailyQuote
    case recentGrades
    case streakProgress
    case learningHeatmap                // isFullWidth
    case homeAsk                        // AI question card
}

extension HomeCardType {
    var isFullWidth: Bool { self == .learningHeatmap }
}
```

### 4.8 LLMConfig / LLMPrompt / LLMCallDebugInfo

```swift
nonisolated struct LLMConfig: Sendable, Equatable {
    var enabled: Bool
    var baseURL: String?
    var apiKey: String?
    var model: String?
    var systemPromptAppendix: String?
    var temperature: Double
    var overrideSystemPrompt: String?  // DEBUG-only

    var isConfigured: Bool {
        enabled && !baseURL.isEmptyOrNil && !apiKey.isEmptyOrNil && !model.isEmptyOrNil
    }

    @MainActor static func from(_ prefs: AppPreferences) -> LLMConfig  // bridge
}

nonisolated struct LLMPrompt: Sendable {
    var system: String
    var messages: [LLMMessage]   // [user, assistant, ...]
    func toMessages() -> [(role: String, content: String)]
    func tokensApprox() -> Int
}

enum LLMMessage: Codable, Sendable {
    case user(String)
    case assistant(String)
    case system(String)
    var role: LLMRole
    var content: String
}

nonisolated struct LLMCallDebugInfo: Equatable, Sendable {
    let startTime: Date
    let endTime: Date
    let url: String
    let model: String
    let temperature: Double
    let systemPrompt: String
    let messages: [LLMMessage]
    let streaming: Bool
    var response: String?
    var error: String?
    let caller: String                      // tag: "MistakeAI" / "WeeklyReport" / "BodyRadar" / ...

    var elapsedSeconds: TimeInterval { endTime.timeIntervalSince(startTime) }
    func asDebugJSON() -> String
}
```

### 4.9 SwiftData @Model Entities

`Models/SwiftData/StudyPulseModels.swift` defines 9 `@Model final class` entities that mirror the struct models:

| Entity | Mirrors | Notable Fields |
|---|---|---|
| `SubjectRecord` | `Subject` | `@Attribute(.unique) name` |
| `GradeRecord` | `Grade` | `imageData: Data?` (`@Attribute(.externalStorage)`), `phaseId: UUID?` (`#Index`) |
| `MistakeNoteRecord` | `MistakeNote` | nested fields flattened + Data externalStorage; `reviewState*`; `audioFileName`; `phaseId: UUID?` |
| `ExamRecord` | `Exam` | `checklistData: Data?` + `locationSchool/Classroom/Seat` + `countdownNotifyDaysData: Data?` + `examReviewData: Data?`; `phaseId: UUID?` |
| `ComprehensiveExamRecord` | `comprehensiveExam` | `subjects: [String]`; `phaseId: UUID?` |
| `UserProfileRecord` | `UserProfile` | `avatarData: Data?` |
| `TaskItemRecord` | `TaskItem` | `phaseId: UUID?` |
| `ReviewStateRecord` | `ReviewState` | (nested in MistakeNoteRecord) |
| `StudyPhaseRecord` | `StudyPhase` | `goalsData: Data?` (JSON-encoded `[PhaseGoal]`) |

Each entity provides `toSnapshot() -> Struct` and `init(from: Struct)` for bidirectional mapping. The `ModelContainer` is built by `ModelContainerFactory.makeContainer()` with an explicit `modelTypes` array; `ModelContainerFactory.migrateFromJSONIfNeeded(context:)` is called once on first launch (UserDefaults flag) to populate these entities from the legacy `~/Documents/*.json` files.

---

## 5. Managers Reference

Managers live under `StudyPulse/Managers/` and are organized by sub-domain (`Core / Health / Logging / PDF / Report / Study / Utility / Widget / Achievement / Audio / LLM`). State-holding managers are `@MainActor`; pure helpers are `nonisolated`.

### 5.1 Manager Summary Table

| Manager | File | Actor / Scope | Key Collaborators | Purpose |
|---|---|---|---|---|
| `RepositoryContainer` | `Managers/Core/RepositoryContainer.swift` | `@Observable @MainActor` | 7 Repositories, ModelContainer, AppEnvironmentManager | Central state & cross-domain orchestration (addGrade / addMistake / activatePhase / todoEntries / bulkClearData) |
| `AppEnvironmentManager` | `Managers/Core/AppEnvironmentManager.swift` | `@MainActor ObservableObject` singleton | `AppPreferences`, UserDefaults | `setLanguage / setColorScheme / setAccent / setGlassEffect / setLearningHeatmapOnTrends / setActivePhase / setLLMEnabled / setLLMConfig / setLLMAPIKey(...)` + `effectiveColorScheme / effectiveAccentColor` |
| `ModelContainerFactory` | `Managers/Core/ModelContainerFactory.swift` | `nonisolated` enum | SwiftData | `ModelContainer` singleton + `migrateFromJSONIfNeeded(context:)` one-shot migration |
| `CSVDocument` / `DataExportManager` | `Managers/Core/{CSVDocument,DataExportManager}.swift` | `FileDocument` / `@MainActor enum` | — | CSV export for grades / mistakes / exams / tasks |
| `HealthKitManager` | `Managers/Health/HealthKitManager.swift` | `@MainActor ObservableObject` singleton | HKHealthStore, `HRVReadiness`, `BodyStatus`, `PersonalBaselines` | HRV (SDNN) readiness + 14-day baseline + multi-dim body status |
| `HealthHistoryStore` | `Managers/Health/HealthHistoryStore.swift` | `nonisolated` class (NSLock) | `DailyHealthSnapshot` | 30-day rolling health snapshot (persisted to `~/Documents/health_history.json`) |
| `StudyReadinessAlgorithm` | `Managers/Health/StudyReadinessAlgorithm.swift` | `nonisolated` (some methods `@MainActor`) | `AgeReference`, `BodyReadinessContext` | 5-intensity × 5-focus readiness; outputs `StudySuggestion[]` (local fallback when LLM off) |
| `Log` / `LogStore` | `Managers/Logging/Log.swift` | `LogLevel` / `LogEntry` / `LogStore` (NSLock, 5000 entries) | os.Logger | In-memory log buffer (subsystem categories: `.app / .widget / .notification / .ui / .data / .study / .health / .llm`) |
| `LogDocument` | `Managers/Logging/LogDocument.swift` | `FileDocument` | — | `.fileExporter` wrapper for `LogStore` |
| `LagMonitor` | `Managers/Logging/LagMonitor.swift` | `@MainActor` | `CADisplayLink` | Main-thread frame skip detector |
| `MistakePDFRenderer` | `Managers/PDF/MistakePDFRenderer.swift` | `@MainActor enum` | Core Text + `NSAttributedString` | Multi-page A4 (595×842 pt) PDF; selectable / searchable text via `CTFramesetter` |
| `MistakePDFDocument` | `Managers/PDF/MistakePDFDocument.swift` | `FileDocument` | `.pdf` UTType | `.fileExporter` wrapper for PDF Data |
| `ReportRenderer` | `Managers/Report/ReportRenderer.swift` | `ImageRenderer` + Core Graphics | `ReportContentView` | Renders `StudyReport` → PNG / JPEG |
| `ReportImageDocument` | `Managers/Report/ReportImageDocument.swift` | `FileDocument` | — | `.fileExporter` wrapper for image data |
| `StudyTimerManager` | `Managers/Study/StudyTimerManager.swift` | `@MainActor ObservableObject` | `ActivityKit`, `StudySession` | 5-intensity timer + Live Activity coordination |
| `DailyGoalReminder` / `SRSReviewNotifications` / `ExamReviewNotifications` | `Managers/Study/*.swift` | `nonisolated` | `UNUserNotificationCenter` | Local notification scheduling |
| `AchievementManager` | `Managers/Achievement/AchievementManager.swift` | `@MainActor ObservableObject` singleton | `AchievementStore` | 3 event entries: `recordGradeRecorded / recordMistakeReviewed / recordFocusMinutes`; `bootstrap(container:)` after `container.isReady` |
| `AchievementStore` | `Managers/Achievement/AchievementStore.swift` | NSLock JSON | `~/Documents/achievements.json` | Snapshot persistence + first-launch backfill from `grades.json` / `study_sessions.json` |
| `AudioStorage` | `Managers/Audio/AudioStorage.swift` | `nonisolated` struct | `~/Documents/audio/` | Generate filename, lookup URL, delete |
| `VoiceMemoManager` | `Managers/Audio/VoiceMemoManager.swift` | `@MainActor ObservableObject` | `AVAudioRecorder` | Recording session: request mic permission, start / pause / resume / stop / delete |
| `LLMClient` | `Managers/LLM/LLMClient.swift` | `@MainActor ObservableObject` singleton (`LLMClient.shared`) | URLSession, `LLMConfig` | `complete(prompt:config:caller:)` + `stream(prompt:config:caller:onDelta:)`; `lastCallInfo` + 20-entry ring `recentCalls` |
| `LLMConfig` | `Managers/LLM/LLMConfig.swift` | `nonisolated value type` | `AppPreferences` | `enabled / baseURL / apiKey / model / systemPromptAppendix / temperature / overrideSystemPrompt` |
| `LLMError` | `Managers/LLM/LLMError.swift` | `enum LocalizedError` | — | 9 error cases with localized descriptions |
| `LLMPrompt` | `Managers/LLM/LLMPrompt.swift` | `nonisolated value type` | `LLMMessage` | System + messages; `toMessages()` / `tokensApprox()` |
| `LLMRequestBuilder` | `Managers/LLM/LLMRequestBuilder.swift` | `enum` + sub-namespaces | `StudySuggestionsLLM / MistakeAILLM / WeeklyReportLLM / AIDiscussionLLM / BodyRadarLLM / HomeAskLLM / AISimilarQuestionLLM` | Per-feature prompt factory with fixed `## ...` output format |
| `LLMResponseParser` | `Managers/LLM/LLMResponseParser.swift` | `enum` | — | Parse `## 段落名` sections back to local model (preserves `icon/priority/color`) |
| `HomeAskDataProvider` | `Managers/LLM/HomeAskDataProvider.swift` | `enum` | — | Keyword → context category (`grade / mistake / trend / readiness`) for `HomeAskLLM` |
| `CalendarManager` | `Managers/Utility/CalendarManager.swift` | class singleton | EventKit | `addExamToCalendar` / `addTaskToReminders` |
| `EducationConfig` | `Managers/Utility/EducationConfig.swift` | `nonisolated` enum | `EducationRegion`, `SubjectConfig` | 15+ education systems |
| `ImageCache` | `Managers/Utility/ImageCache.swift` | `nonisolated` class singleton | `NSCache` | Thumbnail cache (50 items, 300 px) |
| `OCRManager` | `Managers/Utility/OCRManager.swift` | class singleton | Vision | `VNRecognizeTextRequest` (zh-Hans + en) |
| `StringsLocalized` | `Managers/Utility/StringsLocalized.swift` | extension | — | `String.localized` |
| `SubjectInfo` | `Managers/Utility/SubjectInfo.swift` | class | `Subject` | Display name + color + full-score fallback |
| `*WidgetData` + `*WidgetSyncManager` | `Managers/Widget/{Exam,HRV,Trend}*.swift` | class | App Group | Sync to widget extension via App Group + `WidgetCenter.reloadAllTimelines()` |

### 5.2 Repository Facade Flow (replaces the old DataManager flow)

```
[User taps Save in a sheet]
   |
   v
XxxViewModel.method()                  (@MainActor)
   |
   v
RepositoryContainer.addGrade(grade)    (facade; cross-domain orchestration)
   |
   +---> gradeRepo.add(grade)          (@MainActor; SwiftData context.insert + save)
   |
   +---> @Published var grades updated -> SwiftUI re-render
   |
   +---> AchievementManager.shared.recordGradeRecorded()  (cross-domain)
   +---> TrendWidgetSyncManager.syncTrend(grades:subjects:) (widget sync)
   +---> SRSReviewNotifications / ExamReviewNotifications (when applicable)

[Image]
   |
   +---> ImageCache.thumbnail(for: filename)   (nonisolated, thread-safe)
   |        +---> cache hit -> UIImage
   |        +---> cache miss -> load from disk -> cache -> return
   |
   +---> ZoomableImageView for full-screen pinch-zoom

[Voice memo]
   |
   +---> AudioStorage.url(for: filename)   -> ~/Documents/audio/<uuid>.m4a
   +---> AVAudioPlayer / AVAudioRecorder   in AudioPlaybackView / VoiceMemoRecordingSheet
```

### 5.3 EducationConfig → SubjectRepository Smart Recommendation

```
User selects EducationStage + EducationRegion on ProfileEditView
       |
       v
EducationConfig.availableRegions(for: stage)
       |
       v
[EducationRegion] list returned
       |
       v
User picks region -> region.name stored in UserProfile.regionCode
       |
       v
"Apply Smart Recommendation" -> SubjectRepository.applySmartSubjectRecommendation(stage, regionCode)
       |
       +---> EducationConfig.region(name) -> EducationRegion
       +---> iterate region.subjects (SubjectConfig[]) -> Subject (fullScore, displayName, enabled)
       +---> replace UserProfile.selectedSubjects (in SwiftData)
       |
       v
SwiftUI refreshes -> new subjects visible in TrendsView / AddGradeView
```

### 5.4 LLMClient Call Flow

```
View (e.g. StudySuggestionsCard) -> canRequestNow() (40-min cooldown check)
   |
   v
LLMClient.shared.stream(prompt: prompt, config: config, caller: "StudySuggestions")
   |
   +---> URLSession.dataTask: POST {baseURL}/v1/chat/completions
   |        Authorization: Bearer <apiKey>
   |        { model, temperature, stream: true, messages: [{role, content}, ...] }
   |
   +---> Parse SSE chunks (data: {...}) -> onDelta(so-far-complete text)
   |        AsyncStream consumed by SwiftUI MarkdownView (streaming)
   |
   +---> On success: LLMCallDebugInfo { response: ... } -> recentCalls.append (max 20)
   +---> On error: LLMError (9 cases) -> caught by caller -> silent fallback to local
   |
   v
LLMResponseParser.parseSections(rawText) -> [StudySuggestion] / parsed
        (preserves local icon/priority/color)
```

---

## 6. Views Reference

### 6.1 Tab & Navigation Flow

```
ContentView
  |
  +-- iPhone  -> TabView (5 tabs: Home / Trends / Mistakes / Exams / Todos)
  |
  +-- iPad    -> NavigationSplitView (sidebar + detail)
                   |
                   v
             [Home] [Trends] [Mistakes] [Exams] [Todos]   --- navigation items
                     |
                     v
                    HomeView ────────┬─→ AddGradeView (sheet)
                      |               ├─→ NewExamSetView (sheet)
                      |               ├─→ NewMistakeSetView (sheet)
                      |               ├─→ HomeLayoutSettingsView (sheet)
                      |               ├─→ HomeAskSheet (sheet via HomeAskCard)
                      |               ├─→ HRVOnboardingView (first-run sheet)
                      |               ├─→ LLMDebugSheet (DEBUG-only)
                      |               └─→ ExamDetailView (navigationDestination)
                      |
                    TrendsView ────→ per-subject detail + LearningHeatmapView (toggle)
                      |
                    MistakeView ───→ MistakeDetailEditView (sheet or nav destination)
                      |                       ├─→ OCRManager.recognizeText(in:)
                      |                       ├─→ PhotosPicker / ImagePicker
                      |                       ├─→ VoiceMemoRecordingSheet
                      |                       ├─→ Markdown preview
                      |                       └─→ MistakeAIAnalysisSheet (toolbar AI menu)
                      |                       └─→ AISimilarQuestionFlowView (toolbar AI menu)
                      |
                    ExamView ──────┬─→ NewExamSetView (+ button)
                      |              └─→ ExamDetailView (tap exam)
                      |                       ├─→ ExamDetailEditView (edit)
                      |                       └─→ MistakeDetailEditView (related mistake)
                      |                       └─→ ScorePredictionSheet (with 深入探讨 sheet)
                      |
                    TodoView ─────┬─→ NewTaskView (+ button, with New Exam)
                      |             └─→ TaskDetailView / ExamDetailView (tap row)
                      |                       └─→ TaskDetailEditView / ExamDetailEditView
                      |
                    SettingsView ───┬─→ Profile / Appearance / Health / Data / About / FAQ
                                     ├─→ Achievements / DailyGoals / ChartType / Contribution
                                     ├─→ UserAgreement
                                     └─→ PhaseManagement / PhaseEdit
```

### 6.2 Views Summary Table

| View | File | Role | Key Features |
|---|---|---|---|
| `ContentView` | `Views/ContentView.swift` | Root container | iPhone TabView (5 tabs) / iPad NavigationSplitView (sidebar) |
| `HomeView` | `Views/Home/HomeView.swift` | Dashboard | Welcome header, dynamic cards from `HomeLayoutPreference`, two-column `LazyVGrid` on iPad with full-width `block` rendering |
| `HomeViewModel` | `ViewModels/HomeViewModel.swift` | VM | SRS overview / recent grades / upcoming exams / unregistered / chart subject / suggestions |
| `TrendsView` | `Views/Trends/TrendsView.swift` | Trend analysis | Per-subject score cards, needs-attention alerts, optional `LearningHeatmapView` at top (controlled by `AppPreferences.learningHeatmapOnTrends`) |
| `MistakeView` | `Views/Mistake/MistakeView.swift` | Mistake list | Suggested review section, search, card layout, toolbar: PDF export / SRS enqueue / **AI menu (解析错因 / 相似题组卷)**, `.adaptiveMaxWidth(900)` |
| `MistakeDetailEditView` | `Views/Mistake/MistakeDetailEditView.swift` | Mistake editor | `EditSection` enum (Question/Reason/Wrong/Correct), per-section photo + OCR + Markdown preview, **voice memo recording** |
| `MistakeSetDetailView` (in MistakeView.swift) | detail | Detail page with **AI menu toolbar**, embedded `AudioPlaybackView` if `audioFileName` set |
| `NewMistakeSetView` | `Views/Mistake/NewMistakeSetView.swift` | New mistake | Same editing features, EditSection enum |
| `MistakePDFExportSheet` | `Views/Mistake/PDF/MistakePDFExportSheet.swift` | PDF options | Subjects / date range / individual picker, include-images toggle, live count |
| `MistakePDFGenerationView` | `Views/Mistake/PDF/MistakePDFGenerationView.swift` | PDF progress | `ProgressView` with current step |
| `AudioPlaybackView` | `Views/Mistake/Audio/AudioPlaybackView.swift` | Voice memo playback | `AVAudioPlayer` + progress bar + play/pause + delete |
| `VoiceMemoRecordingSheet` | `Views/Mistake/Audio/VoiceMemoRecordingSheet.swift` | Voice memo record | `AVAudioRecorder` + duration + pause/resume/finish |
| `AISimilarQuestionFlowView` | `Views/Mistake/LLM/AISimilarQuestionFlowView.swift` | AI similar question flow | Multi-step flow to generate similar exam questions from a mistake |
| `ExamView` | `Views/Exam/ExamView.swift` | Exam list | Calendar integration, days-remaining countdown, `.adaptiveMaxWidth(800)` |
| `ExamCalendarView` | `Views/Exam/ExamCalendarView.swift` | Calendar | Month grid of upcoming exams |
| `ExamDetailView` | `Views/Exam/ExamDetailView.swift` | Exam detail | Location / pre-exam checklist / countdown / review / ShareLink / 深入探讨 sheet |
| `ExamDetailEditView` | `Views/Exam/ExamDetailEditView.swift` | Exam editor | Edit exam fields |
| `NewExamSetView` | `Views/Exam/NewExamSetView.swift` | New exam | Create exam, calendar & reminder toggles |
| `ExamReviewView` | `Views/Exam/ExamReviewView.swift` | Exam review | Post-exam review entry |
| `ScorePredictionEngine` / `ScorePredictionSheet` | `Views/Exam/{ScorePredictionEngine,ScorePredictionSheet}.swift` | AI score prediction | Local + LLM prediction; **深入探讨** button (AIDiscussionSheet) |
| `TodoView` | `Views/Todo/TodoView.swift` | Unified todo | Type chips (All/Exams/Homework/Reading) + time grouping + list/calendar + Past Items; `.adaptiveMaxWidth(900)` |
| `TodoRowView` | `Views/Todo/TodoRowView.swift` | Row | One row per todo entry |
| `NewTaskView` / `TaskDetailView` / `TaskDetailEditView` | `Views/Todo/{New,Detail,DetailEdit}.swift` | Task | Homework / Reading CRUD with Reminders sync |
| `AddGradeView` | `Views/Grade/AddGradeView.swift` | Grade entry | Single / multi-subject input, custom full-score, raw score + ranking |
| `SubjectScoreCard` | `Views/Grade/SubjectScoreCard.swift` | Reusable | Gradient border + entrance animation, mini chart |
| `SettingsView` | `Views/Settings/SettingsView.swift` | Settings hub | 6-segment `NavigationLink` nav (Profile/Appearance/Health/Data/About/FAQ), `.adaptiveMaxWidth(720)` |
| `ProfileSettingsView` / `AppearanceSettingsView` / `HealthSettingsView` / `DataManagementSettingsView` / `AboutSettingsView` / `QASettingsView` | `Views/Settings/*SettingsView.swift` | Sub-pages | One per category |
| `AchievementsView` | `Views/Settings/AchievementsView.swift` | Streak / achievements | 30-day rolling + unlocked + today progress |
| `DailyGoalsConfigView` | `Views/Settings/DailyGoalsConfigView.swift` | Daily goals | Configure target + reminder time |
| `ChartTypeSettingsView` | `Views/Settings/ChartTypeSettingsView.swift` | Chart type | 6 chart types |
| `ContributionSettingsView` | `Views/Settings/ContributionSettingsView.swift` | Heatmap | GitHub-style heatmap config |
| `UserAgreementView` | `Views/Settings/UserAgreementView.swift` | Agreement | Full `docs/reference/USER_AGREEMENT.md` text |
| `PhaseManagementView` | `Views/Settings/PhaseManagementView.swift` | Phase mgmt | Active / archived / overview |
| `PhaseEditView` | `Views/Settings/PhaseEditView.swift` | Phase editor | Edit name / dates / goals |
| `ProfileEditView` | `Views/Profile/ProfileEditView.swift` | Profile editor | 12+ fields |
| `EditSubjectsView` | `Views/Profile/EditSubjectsView.swift` | Subject editor | Per-subject full-score customization |
| `PreferencesView` | `Views/Profile/PreferencesView.swift` | Prefs | Theme / language; `.adaptiveMaxWidth(640)` |
| `HomeLayoutSettingsView` | `Views/Home/HomeLayoutSettingsView.swift` | Home layout | Drag-to-reorder + per-card on/off toggle |
| `StudyTimerView` | `Views/StudyTimer/StudyTimerView.swift` | Timer | 5-intensity timer + Live Activity |
| `ReportContentView` / `ReportOptionsSheet` / `ReportShareSheet` | `Views/Report/*` | Study report | `ImageRenderer` PNG / JPEG output |
| `FlashcardStudyView` / `FlashcardCardView` / `FlashcardSessionSummaryView` / `FlashcardCalculatorView` | `Views/Flashcard/*` | SRS flashcards | SM-2 algorithm |
| `OnboardingView` / `OnboardingProfileFormView` | `Views/OnBoarding/*` | Onboarding | iOS 26 glass style + 6-page profile form + versioned welcome |
| `AboutView` / `CopyrightView` / `HRVOnboardingView` | `Views/About/*` | About | 3-page HRV explainer |
| `DataAdminView` | `Views/Admin/DataAdminView.swift` | Developer | Bulk data ops |
| `LLMSettingsView` | `Views/LLM/LLMSettingsView.swift` | LLM config | Master toggle + Base URL / API Key (masked) / Model / Temperature / System Prompt appendix / Test Connection |
| `LLMChatView` | `Views/LLM/LLMChatView.swift` | AI Assistant | In-memory chat; left/right bubble layout with streaming Markdown |
| `AIDiscussionSheet` | `Views/LLM/AIDiscussionSheet.swift` | 深入探讨 | Multi-turn chat sheet; first assistant message marked `isInitialContext` |
| `MistakeAIAnalysisSheet` | `Views/LLM/MistakeAIAnalysisSheet.swift` | Mistake AI | 3-section streaming analysis |
| `HomeAskSheet` | `Views/LLM/HomeAskSheet.swift` | HomeAsk sheet | Chat with LLM about grade/mistake/trend/readiness |
| `HomeAskCard` | `Views/Home/HomeCards/HomeAskCard.swift` | HomeAsk home card | Tap-to-open sheet |
| `ChatBubble` / `ChatInputBar` | `Views/LLM/{ChatBubble,ChatInputBar}.swift` | Chat components | Reusable across `LLMChatView` + `AIDiscussionSheet` + `HomeAskSheet` |
| `LLMDebugSheet` | `Views/LLM/LLMDebugSheet.swift` | LLM debug | Grouped `recentCalls` + JSON details (DEBUG-only) |
| `AvatarView` / `ImagePicker` / `PhotoCaptureView` / `ScoreColor` / `ZoomableImageView` / `iPadLayout` | `Views/Helpers/*` | Reusable | `iPadLayout` = `adaptiveMaxWidth` / `AdaptiveHStack` / `AdaptiveGridColumns` / `adaptiveCardPadding` |
| `GradeChartView` / `HRVStatusCard` / `LearningHeatmapView` / `MasteryCurveView` / `PhaseSelectorView` / `SectionHeader` / `StreakHomeCard` / `StudyTimerCard` / `SubjectPickerView` / `TrendChartView` | `Views/Components/*` | Reusable | `HRVStatusCard` has 3 detail levels + LLM augmentation (40-min cooldown); `LearningHeatmapView` is 7×13 GitHub-style 90-day heatmap |
| `MarkdownEditorView` / `MarkdownPreviewView` / `MarkdownTextEditor` | `Views/Components/Markdown/*` | Markdown | Edit + preview using `SwiftStreamingMarkdown` |

### 6.3 HomeView Card Slots

| Card Type | File | Default Enabled | Empty Hides | Purpose |
|---|---|---|---|---|
| `hrvStatus` | `Components/HRVStatusCard.swift` | Yes, but hides when HRV is not enabled | No | HRV + body readiness; LLM-augmented with 40-min cooldown |
| `unregisteredExamsReminder` | inline in `HomeView.swift` | Yes | Yes | Warns about exams in the past 3–7 days without matching grade |
| `quickActions` | inline in `HomeView.swift` | Yes | No | Quick shortcuts to AddGradeView / NewExamSetView / NewMistakeSetView / StudyTimerView |
| `studySuggestions` | `HomeCards/StudySuggestionsCard.swift` | Yes | No | Local suggestions + LLM-augmented (40-min cooldown) |
| `trendChart` | `Components/TrendChartView.swift` | Yes | Yes | Subject trends chart; hides when no recent grades |
| `upcomingExams` | inline in `HomeView.swift` | Yes | Yes | List of upcoming exams, tap → `ExamDetailView` |
| `dailyQuote` | inline in `HomeView.swift` | Yes | No | Daily inspirational quote |
| `recentGrades` | inline in `HomeView.swift` | Yes | Yes | Last 5 grades |
| `streakProgress` | `Components/StreakHomeCard.swift` | Yes | No | Streak / daily goal progress; tap → `AchievementsView` |
| `learningHeatmap` | `Components/LearningHeatmapView.swift` | Yes | Yes | 90-day GitHub-style heatmap; `isFullWidth: true` |
| `homeAsk` | `HomeCards/HomeAskCard.swift` | Yes | No | AI question card; tap → `HomeAskSheet`; not in long-press share menu |

HomeView rendering order comes from `HomeLayoutPreference.load().enabledTypes`. iPad uses block-rendering: full-width cards break the 2-column grid.

---

## 7. Home Card System

### 7.1 Card Type Listing

| HomeCardType | UI Component | Controlled By | Persistence |
|---|---|---|---|
| hrvStatus | HRVStatusCard | HealthKitManager.hrvEnabled + HomeLayoutPreference | UserDefaults (HomeLayoutPreference) |
| unregisteredExamsReminder | Inline in HomeView | DataManager grades vs exams (3–7 day window) | UserDefaults (HomeLayoutPreference) |
| quickActions | Inline in HomeView | Static | UserDefaults (HomeLayoutPreference) |
| studySuggestions | Inline in HomeView | Static / computed from data | UserDefaults (HomeLayoutPreference) |
| trendChart | GradeChartView | DataManager.grades (only visible when recent grades exist) | UserDefaults (HomeLayoutPreference) |
| upcomingExams | Inline in HomeView | DataManager.examSets + comprehensiveExamSets | UserDefaults (HomeLayoutPreference) |
| dailyQuote | Inline in HomeView | Static | UserDefaults (HomeLayoutPreference) |
| recentGrades | Inline in HomeView | DataManager.grades | UserDefaults (HomeLayoutPreference) |

### 7.2 Persistence Flow

```
User opens HomeLayoutSettingsView
       |
       v
HomeLayoutPreference.load() ← reads from UserDefaults
       |
       v
User drags to reorder, toggles on/off
       |
       v
HomeLayoutPreference.save() → writes to UserDefaults
       |
       v
HomeView.body reads enabledTypes → renders cards in user-defined order
       (iPad: two-column LazyVGrid; iPhone: single VStack)
```

### 7.3 mergeWithDefault When New Cards Are Added

```
App update ships with a new HomeCardType
       |
       v
HomeLayoutPreference.load()
       |
       +---> existing items (from UserDefaults) are kept in order
       +---> new card types, not yet present, are appended with enabled = true
       +---> any old unknown card types are removed
       |
       v
User sees old ordering preserved + new cards enabled at the end
```

---

## 8. Education Systems

### 8.1 System Tree

```
Education Systems (EducationConfig)
|
+-- Domestic
|   +-- China (Mainland Standard)
|   |   +-- Primary School
|   |   +-- Middle School
|   |   +-- High School
|   |
|   +-- Zhejiang
|   |   +-- Middle School
|   |   +-- High School (3+3)
|   |
|   +-- Shanghai
|   |   +-- Middle School
|   |   +-- High School (3+3)
|   |
|   +-- Taiwan
|   |   +-- Middle School
|   |   +-- GSAT (学测)
|   |
|   +-- Hong Kong
|       +-- DSE
|
|   +-- Singapore
|       +-- O-Level
|
+-- International
    +-- United Kingdom
    |   +-- IGCSE
    |   +-- A-Level
    |
    +-- IB
    |   +-- Diploma Programme (DP)
    |
    +-- United States
    |   +-- AP (Advanced Placement)
    |   +-- SAT (Scholastic Assessment Test)
    |   +-- ACT (American College Testing)
    |
    +-- Graduate & Language
        +-- GRE
        +-- GMAT
        +-- TOEFL
        +-- IELTS
```

### 8.2 Coverage Matrix

| Region | Primary | Middle | High School | Intl High School | University | Graduate |
|---|---|---|---|---|---|---|
| China Mainland | Yes | Yes | Yes | - | - | - |
| Zhejiang | - | Yes | Yes (3+3) | - | - | - |
| Shanghai | - | Yes | Yes (3+3) | - | - | - |
| Taiwan | - | Yes | Yes (学测) | - | - | - |
| Hong Kong | - | - | Yes (DSE) | - | - | - |
| Singapore | - | Yes (O-Level) | Yes (O-Level) | Yes | - | - |
| UK IGCSE | - | Yes | - | Yes | - | - |
| UK A-Level | - | - | Yes | Yes | - | - |
| IB Diploma | - | - | Yes | Yes | - | - |
| US AP | - | - | Yes | Yes | - | - |
| US SAT | - | - | - | - | Yes | - |
| US ACT | - | - | - | - | Yes | - |
| GRE / GMAT | - | - | - | - | - | Yes |
| TOEFL / IELTS | - | - | - | - | - | Yes |

### 8.3 Score Scale Reference

| System | Typical Scale | Example Subject Scores |
|---|---|---|
| China Mainland High | 100 / 150 | Chinese 150, Physics 100 |
| Zhejiang High (赋分) | 100 | All subjects 100 max |
| Hong Kong DSE | 1-7 (5** = 7) | All subjects 7 max |
| Taiwan 学测 | 100 | Math A / Math B each 100 |
| UK A-Level | 100 | A* = 90+ |
| IB DP | 1-7 | 6 subjects + TOK + EE = 45 max |
| US AP | 1-5 | 5 = max |
| US SAT | 200-800 | 1600 total |
| US ACT | 1-36 | 36 = max |
| GRE | 130-170 | 340 total |
| TOEFL | 0-120 | - |
| IELTS | 0-9 | - |

### 8.4 SubjectConfig Factories

```swift
// Required subject
SubjectConfig.required(name, displayName, fullScore, category)
// Elective subject
SubjectConfig.elective(name, displayName, fullScore, category)
```

Each EducationRegion.subjects is an array of SubjectConfig, which maps to Subject with the same name + displayName + fullScore.

---

## 9. HRV / HealthKit Subsystem

### 9.1 Architecture

```
+-----------------------------+
|  HealthKitManager            |
|  (@MainActor ObservableObject)|
|   - hrvEnabled: Bool          |
|   - hrvOnboardingCompleted    |
|   - isAuthorized: Bool        |
|   - readiness: HRVReadiness   |
|     (z-score, category, suggestion)
|   - dailyHRVHistory: [HRVSample]
|   - lastSampleCount: Int      |
|   - hrvDetailLevel: HRVDetailLevel (suggestionOnly/data/chart)
+--------------+---------------+
               | read HRV samples
               v
+-----------------------------+
|   HKHealthStore              |
|   heartRateVariabilitySDNN   |
|   (14-day window of samples) |
+--------------+---------------+
               |
               v
+-----------------------------+        +-----------------------------+
|  HRVStatusCard (HomeView)    |        |  HRVOnboardingView          |
|  (renders 1 of 3 detail      |        |  (3-page explainer +        |
|   levels based on hrvDetailLevel)    |   HealthKit authorization)  |
+-----------------------------+        +-----------------------------+
```

### 9.2 Readiness Calculation Flow

```
User opens HomeView (or taps "Refresh")
       |
       v
HealthKitManager.refreshReadiness()
       |
       +---> HKHealthStore.requestAuthorization (if needed)
       +---> HKSampleQuery for heartRateVariabilitySDNN, last 14 days
       |
       +---> Aggregate per calendar day (first sample per day, sorted desc)
       |
       +---> Baseline: mean + std of days AFTER today (requires ≥ 7 distinct days)
       |
       +---> z-score = (today_SDNN − mean) / stdDev
       |
       +---> Category:
       |       excellent (z > 1)
       |       normal    (-1 ≤ z ≤ 1)
       |       low       (z < -1)
       |       insufficient (< 7 days)
       |       noAuthorization
       |       queryFailed
       |
       +---> Suggestion string (localized)
       |
       v
@Published readiness updated → SwiftUI re-render HRVStatusCard
```

### 9.3 Category Table

| Category | Z-score Range | Suggestion Direction |
|---|---|---|
| excellent | z > 1 | "High recovery today — tackle challenging study." |
| normal | -1 ≤ z ≤ 1 | "Steady as usual — follow your plan." |
| low | z < -1 | "Low recovery — consider lighter tasks today." |
| insufficient | < 7 distinct days | "Wear your Apple Watch more often to establish a baseline." |
| noAuthorization | HealthKit denied | "Grant HealthKit access to see your HRV readiness." |
| queryFailed | Query error | "Something went wrong — try again later." |

---

## 9.5 LLM (BYOK) Subsystem

A **Bring-Your-Own-Key** OpenAI-Chat-Completions-compatible LLM integration. Users supply their own Base URL + API Key + Model name in `LLMSettingsView`; the system falls back to local-only features silently if LLM is disabled, fields are missing, or any network/parse error occurs.

### 9.5.1 Architecture

```
+----------------------------------+
| LLMSettingsView (config entry)   |  ---> toggles / sets prefs.llmEnabled
+----------------------------------+                |
                                                    v
+----------------------------------+
| AppPreferences                   |  ---> persisted in UserDefaults
|  - llmEnabled                    |
|  - llmBaseURL / llmAPIKey        |
|  - llmModel                      |
|  - llmSystemPromptAppendix       |
|  - llmTemperature                |
|  - lastRadarAIRequestTime        |  (40-min radar cooldown)
|  - lastStudySuggestionsAIRequestTime |  (40-min suggestions cooldown)
|  - debugOverrideSystemPrompt     |  (DEBUG-only)
+----------------------------------+
                |
                v
+----------------------------------+
| LLMConfig (nonisolated value)    |  ---> snapshot built by LLMConfig.from(prefs)
|  - enabled / baseURL / apiKey    |       (no reference held → UI updates visible)
|  - isConfigured: Bool            |
+----------------------------------+
                |
                v
+----------------------------------+
| LLMClient.shared                 |  @MainActor ObservableObject singleton
|  - complete(...) / stream(...)   |
|  - lastCallInfo: LLMCallDebugInfo|
|  - recentCalls: [LLMCallDebugInfo] (max 20 ring)
+----------------------------------+
                |
                v
+----------------------------------+
| LLMRequestBuilder + LLMResponseParser + HomeAskDataProvider
|  - per-feature prompt factories  |
|  - fixed ## ... output format    |
+----------------------------------+
                |
                v
+----------------------------------+
| 4 user-facing AI features       |
|  - StudySuggestionsCard          |  (40-min cooldown)
|  - HRVStatusCard                 |  (40-min cooldown)
|  - MistakeAIAnalysisSheet        |  (no cooldown, user-tap)
|  - HomeAskSheet / HomeAskCard    |  (no cooldown, chat-style)
+----------------------------------+
```

### 9.5.2 User-Facing AI Features

| Feature | Entry Point | Output Format | Cooldown |
|---|---|---|---|
| `StudySuggestionsCard` | Home page card | `## 强度/标题/建议/依据` × N (preserves local icon/priority/color) | 40 min (`lastStudySuggestionsAIRequestTime`) |
| `HRVStatusCard` Body Radar | Home page HRV card | `## 强度/标题/建议/依据` × 1 | 40 min (`lastRadarAIRequestTime`); user can tap "立刻分析" to bypass |
| `MistakeAIAnalysisSheet` | Mistake detail toolbar ✨ button | `## 错因分析 / ## 正确思路 / ## 类似题建议` | None |
| `WeeklyReportView` / `WeeklyReportSettingsView` | Weekly / monthly report | Free-form Markdown rendered in `SwiftStreamingMarkdown` | None |
| `AIDiscussionSheet` (深入探讨) | ScorePredictionSheet / MistakeAIAnalysisSheet | Multi-turn chat; first assistant message is system-prompt context (marked `isInitialContext`) | None |
| `LLMChatView` (AI Assistant) | Settings → LLM | Free-form chat | None (in-memory history only) |
| `HomeAskSheet` (HomeAsk) | Home page `HomeAskCard` | Multi-turn chat; `HomeAskDataProvider` picks 1 of 4 contexts (`grade/mistake/trend/readiness`) from user input keywords | None |

### 9.5.3 LLMCallDebugInfo

`LLMClient` records every call:

```swift
nonisolated struct LLMCallDebugInfo: Equatable, Sendable {
    let startTime: Date
    let endTime: Date
    let url: String
    let model: String
    let temperature: Double
    let systemPrompt: String
    let messages: [LLMMessage]
    let streaming: Bool
    var response: String?
    var error: String?
    let caller: String   // tag: "StudySuggestions" / "BodyRadar" / "MistakeAI" / "WeeklyReport" / "HomeAsk" / "AISimilarQuestion" / "AIDiscussion"
    var elapsedSeconds: TimeInterval { endTime.timeIntervalSince(startTime) }
    func asDebugJSON() -> String
}
```

- `LLMClient.lastCallInfo`: most recent call (read by `LLMCallIndicator` overlay on AI-enabled cards).
- `LLMClient.recentCalls`: ring buffer of last 20 calls (read by `LLMDebugSheet` in DEBUG mode, grouped by `caller`).

### 9.5.4 Error Categories (`LLMError`)

| Case | Cause | UI behavior |
|---|---|---|
| `.notConfigured` | master toggle off or missing fields | Silent skip, fall back to local |
| `.invalidURL` | `baseURL` is not a valid URL | Silent skip, fall back to local |
| `.unauthorized` | HTTP 401 | Silent skip, fall back to local (logged in `Log.llm`) |
| `.rateLimited` | HTTP 429 | Silent skip, fall back to local |
| `.serverError(statusCode, body)` | other 4xx / 5xx | Body is included in `errorDescription` for diagnosis |
| `.network` | underlying `URLError` | Silent skip, fall back to local |
| `.malformedResponse` | SSE chunks non-JSON | Silent skip, fall back to local |
| `.emptyResponse` | no `choices[0].message.content` | Silent skip, fall back to local |
| `.timeout` | `URLRequest` timed out | Silent skip, fall back to local |

**Never show an alert to the user.** Failures are logged to `Log.llm` category and only visible in `LogViewerView` (DEBUG mode).

### 9.5.5 Strict Rules

- `LLMClient` must use environment-provided `AppPreferences` (`@EnvironmentObject envManager.preferences`) — **never** `AppPreferences()` struct initializer (otherwise debug overrides don't reflect in UI).
- All AI features call `canRequestNow()` to enforce 40-min cooldown on radar and study-suggestions; only "立刻分析" button can bypass.
- `MistakeAIAnalysisSheet` and `BodyRadarLLM` preserve local `icon/priority/color` while replacing `title/description` from LLM output.
- "深入探讨" sheet places last AI output **only in system prompt** (with `===` separator and "务必主动引用" instruction) — not as the first assistant message (avoids `assistant → user` pattern that confuses LLMs). The message is still shown in the UI with `isInitialContext` visual treatment.
- `LLMChatView` conversation is in-memory only; `onDisappear` clears history.
- `HomeAskDataProvider` is keyword-driven (e.g. "成绩" → `grade`, "错题" → `mistake`, "趋势" → `trend`, "身体" → `readiness`).

---

## 9.6 Audio (Voice Memos) Subsystem

Per-`MistakeNote` voice memos using `AVFoundation`. Audio files live in `~/Documents/audio/<uuid>.m4a`; only the `filename` is stored on `MistakeNote.audioFileName: String?` (so the JSON stays tiny and CloudKit-friendly).

### 9.6.1 Architecture

```
+----------------------------------------+
| MistakeDetailEditView (record)         |
|   +---> tap mic button                 |
|              |                         |
|              v                         |
|   VoiceMemoRecordingSheet (modal)      |
|     +---> VoiceMemoManager             |
|     |        +---> AVAudioRecorder     |
|     |        +---> permission check    |
|     |        +---> pause/resume/stop   |
|     |                                  |
|     +---> AudioStorage.url(for: name)  |  --> ~/Documents/audio/<uuid>.m4a
|     +---> MistakeNote.audioFileName    |
+----------------------------------------+

+----------------------------------------+
| MistakeSetDetailView (playback)        |
|   if audioFileName != nil:             |
|     +---> AudioPlaybackView             |
|              +---> AVAudioPlayer       |
|              +---> progress + scrub    |
|              +---> delete              |
+----------------------------------------+
```

### 9.6.2 Files

| File | Role |
|---|---|
| `Managers/Audio/AudioStorage.swift` | `nonisolated` struct: generate `<uuid>.m4a` filename, resolve `URL`, delete |
| `Managers/Audio/VoiceMemoManager.swift` | `@MainActor` ObservableObject: request mic permission, `startRecording / pause / resume / stop / delete` |
| `Views/Mistake/Audio/VoiceMemoRecordingSheet.swift` | Sheet with timer + waveform + pause/resume/finish |
| `Views/Mistake/Audio/AudioPlaybackView.swift` | Detail-page embed: player + progress + delete |
| `MistakeNote.audioFileName: String?` | New optional field on the model |

### 9.6.3 Permissions

`Info.plist` must include `NSMicrophoneUsageDescription` (the prompt shown to the user when `AVAudioSession.requestRecordPermission` is called).

---

## 10. Image, OCR and CSV Pipelines

### 10.1 Image Pipeline

```
Capture Flow:
  PhotoCaptureView (camera) / ImagePicker (photo library)
          |
          v
     original image
          |
          v
     JPEG compression (Data)
          |
          v
     DataManager.saveGradeImage(data) or saveAvatar(data)
          |
          v
     generate filename (grade_UUID.jpg / avatar_UUID.jpg)
          |
          v
     DataFileIO.write to ~/Documents/images/
          |
          v
     filename stored back in Grade.imageFileName or UserProfile.avatarFileName

Display Flow:
  SwiftUI view (HomeView, ExamDetailView, ProfileEditView, ...)
          |
          v
     ImageCache.thumbnail(for: filename) — nonisolated, thread-safe
          |
          +-- cache hit → return UIImage
          +-- cache miss → load from disk → cache → return UIImage
          |
          v
     Full-screen → ZoomableImageView (pinch + double-tap zoom)
```

### 10.2 OCR Pipeline

```
User selects image in MistakeDetailEditView (Question/Reason/Wrong/Correct)
          |
          v
     OCRManager.shared.recognizeText(in: imageData)
          |
          +---> VNRecognizeTextRequest
          |       recognitionLevel = .accurate
          |       recognitionLanguages = ["zh-Hans", "en"]
          |
          +---> completion handler returns top-candidate string per observation
          |
          v
     Recognized text populated into the section text field
```

### 10.3 CSV Pipeline

```
User taps "Export" in SettingsView
          |
          v
     DataExportManager.build{Kind}CSV()  (@MainActor enum)
          |
          +-- headers
          +-- rows (properly escaped: commas, quotes, newlines)
          |
          v
     CSV String → CSVDocument (FileDocument) → UIActivityViewController → share / save
```

### 10.4 ImageCache Spec

| Property | Value |
|---|---|
| Scope | nonisolated class (Sendable-safe) |
| Singleton | `ImageCache.shared` |
| Max items | 50 |
| Max dimension | 300 px |
| Key source | filename (in `~/Documents/images/`) |
| Backing store | NSCache with cost-based eviction |

---

## 11. iPad Adaptation

### 11.1 iPad Layout Helpers

| Helper | File | Purpose |
|---|---|---|
| adaptiveMaxWidth(_:) | iPadLayout.swift | Center content on iPad; default 720 |
| AdaptiveHStack | iPadLayout.swift | HStack on iPad, VStack on iPhone |
| AdaptiveGridColumns(compact:regular:spacing:) | iPadLayout.swift | Grid columns — compact value for iPhone, regular value for iPad |
| adaptiveCardPadding() | iPadLayout.swift | 20pt outer padding on iPhone, 0 on iPad |

### 11.2 Per-view Maximum Widths

| View | Max Width (iPad) | Notes |
|---|---|---|
| PreferencesView | 640 | Language + theme pickers |
| SettingsView | 720 | Settings hub |
| ExamView | 800 | Exam list + upcoming |
| TrendsView | 900 | Per-subject charts |
| MistakeView | 900 | Mistake cards |
| HomeView | 1100 | Two-column LazyVGrid for dynamic cards; single-column stat header |

### 11.3 Root Layout Switch

```
ContentView
  ┌─ horizontalSizeClass
  │
  ├─ .compact → TabView { HomeView / TrendsView / MistakeView / ExamView / SettingsView }
  │
  └─ .regular → NavigationSplitView
                  ├ sidebar: List with NavigationLink(value: tab)
                  │         [Home] [Trends] [Mistakes] [Exams] [Settings]
                  │
                  └ detail: current tab view, wrapped in adaptiveMaxWidth()
```

### 11.4 Adaptation Principles

1. iPhone layouts are unchanged — all iPad-specific branches depend on `horizontalSizeClass == .regular` or `UIDevice.current.userInterfaceIdiom == .pad`.
2. Content is centered, not stretched to the edges.
3. Use the helpers in iPadLayout.swift instead of inline size-class branches in feature views.
4. The sidebar uses `.listStyle(.sidebar)` with `NavigationLink(value: tab)`.

---

## 12. Localization

### 12.1 Supported Languages

| Language | Key | Folder |
|---|---|---|
| English | en | en.lproj/Localizable.strings |
| Simplified Chinese | zh-Hans | zh-Hans.lproj/Localizable.strings |
| Traditional Chinese | zh-Hant | zh-Hant.lproj/Localizable.strings |
| Japanese | ja | ja.lproj/Localizable.strings |
| Korean | ko | ko.lproj/Localizable.strings |

### 12.2 String.localized() Extension

```swift
// StringsLocalized.swift
extension String {
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
}
```

Usage in views:

```swift
Text("home.welcome.title".localized)
```

### 12.3 Language Switching Flow

```
User opens PreferencesView → taps Language
         |
         v
AppEnvironmentManager.shared.setLanguage("zh-Hans")
         |
         +---> update preferences.appLanguage
         +---> write preferences to UserDefaults
         +---> set AppleLanguages in UserDefaults
         |
         v
Root view re-renders with new locale
```

On launch: `AppEnvironmentManager.shared.applyLanguageOnLaunch()` is called from `StudyPulseApp.init`, which applies the persisted language (if any).

---

## 13. Privacy Permissions

| Info.plist Key | Usage | Reason |
|---|---|---|
| NSCameraUsageDescription | Camera access | Take photos of mistakes to attach to MistakeNote |
| NSPhotoLibraryUsageDescription | Photo library | Select photos from photo library to attach |
| NSCalendarsUsageDescription | Calendar access | Add exams to system calendar |
| NSHealthShareUsageDescription | HealthKit | Read HRV (SDNN) samples to compute readiness; app does NOT write |

Entitlements:

| Entitlement | Value | Purpose |
|---|---|---|
| com.apple.developer.healthkit | true | Enable HealthKit APIs |

Note: NSHealthUpdateUsageDescription is NOT declared because the app never writes to HealthKit.

---

## 14. Widget Extension

### 14.1 Architecture

```
+-----------------------------------+
|     Main App (StudyPulse)         |
|                                   |
|  DataManager.saveExams() /        |
|    saveComprehensiveExams()       |
|           |                       |
|           v                       |
|  WidgetDataSyncManager            |
|   .syncExamsToWidget(exams)       |
|           |                       |
|           v                       |
|  App Group Container              |
|  (group.com.chenkai.gao.studypulse)|
|                                   |
+-----------+-----------------------+
            |
            v
+-----------+-----------------------+
|  StudyPulseWidget Extension        |
|                                    |
|  ExamWidgetProvider.getTimeline()  |
|           |                        |
|           +-- load ExamWidgetData  |
|               from App Group       |
|           +-- build TimelineEntry  |
|           +-- return to System     |
|                                    |
|  ExamWidgetViews (S / M / L)       |
|  rendered by WidgetKit             |
+------------------------------------+
```

### 14.2 Components

| Component | File | Purpose |
|---|---|---|
| ExamWidget | StudyPulseWidget/ExamWidget.swift | Widget definition |
| ExamWidgetData | StudyPulseWidget/ExamWidgetData.swift | Shared data model (name, subject, examDate, daysRemaining) |
| ExamWidgetEntry | StudyPulseWidget/ExamWidgetEntry.swift | Timeline entry |
| ExamWidgetProvider | StudyPulseWidget/ExamWidgetProvider.swift | Timeline provider |
| ExamWidgetViews | StudyPulseWidget/ExamWidgetViews.swift | Small / Medium / Large widget UI |
| StudyPulseWidgetBundle | StudyPulseWidget/StudyPulseWidgetBundle.swift | @main bundle |

### 14.3 How to Enable

1. Add a Widget Extension target in Xcode with bundle ID `Gao.Chenkai.StudyPulse.Widget` and deployment target iOS 18.6.
2. Enable App Group `group.com.chenkai.gao.studypulse` on BOTH the main app target AND the widget target.
3. If you change the App Group identifier, update `AppGroupConfig.identifier`.
4. Call `WidgetDataSyncManager.syncExamsToWidget()` after any exam add/edit in the main app, and also when the app becomes active.
5. Call `WidgetCenter.shared.reloadAllTimelines()` after writes.

---

## 15. Dependencies (SPM)

| Package | Source | Purpose |
|---|---|---|
| `SwiftStreamingMarkdown` | Local package (`Packages/SwiftStreamingMarkdown-0.2.0`) | Streaming Markdown + LaTeX render used by `LLMClient.stream`'s `MarkdownView` output and by `MistakeAIAnalysisSheet` / `WeeklyReportView` / `AIDiscussionSheet` |
| `Vendored` | Local `Packages/Vendored/` (swift-cmark / swift-markdown / highlightswift / iosMath) | Underlying Markdown / KaTeX primitives used by `SwiftStreamingMarkdown` |

Apple frameworks used:

- SwiftUI (with iOS 26 `glassEffect` for Liquid Glass)
- SwiftData (persistent layer)
- Charts
- Vision
- EventKit
- UserNotifications
- HealthKit
- WidgetKit + ActivityKit (Live Activity for StudyTimer)
- UniformTypeIdentifiers
- PhotosUI
- AVFoundation (AVAudioRecorder / AVAudioPlayer for voice memos)

**Note**: `@Equatable` macro from PointFree's `equatable` package is **not** used in `SwiftStreamingMarkdown` (was removed to avoid build slowdowns and link errors). `OnBoarding/` is now a first-class in-repo implementation (not via `WSOnBoarding`); it uses iOS 26 Liquid Glass styling directly.

---

## 16. Build & Run

### 16.1 Build Helper (scripts/build.sh)

| Command | Effect |
|---|---|
| `./scripts/build.sh` | Debug build, iPhone 17 simulator |
| `./scripts/build.sh release` | Release build |
| `./scripts/build.sh clean` | Clean build folder |
| `./scripts/build.sh list` | List available simulators |
| `./scripts/build.sh help` | Show all options |

### 16.2 Direct xcodebuild

```bash
xcodebuild \
  -project StudyPulse.xcodeproj \
  -scheme StudyPulse \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

### 16.3 Available Schemes & Configurations

| Kind | Values |
|---|---|
| Schemes | StudyPulse, StudyPulseWidgetExtension |
| Configurations | Debug, Release |

### 16.4 Resolving Packages

In Xcode: File → Packages → Resolve Package Versions

On the command line:

```bash
xcodebuild -resolvePackageDependencies -project StudyPulse.xcodeproj
```

---

## 17. Coding Standards

| Area | Rule |
|---|---|
| Concurrency | Swift 6 Strict Concurrency; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; `@MainActor` for state-holding managers and ViewModels; `nonisolated` for pure helpers and I/O |
| Models | `Codable`, `nonisolated`, `Sendable` value types; no class-based models |
| Persistence | SwiftData `@Model` entities in `Models/SwiftData/` with explicit `toSnapshot()` / `init(from:)`; legacy JSON files migrated once on first launch via `ModelContainerFactory.migrateFromJSONIfNeeded` |
| Repositories | One `Default*Repository` per domain (Grade/Mistake/Exam/Task/Phase/Profile/Subject); protocols in `Repositories/Protocols/`; aggregated by `RepositoryContainer` |
| Views | Place under `Views/` with subdirectories `Components/`, `Helpers/`, `Admin/`, `OnBoarding/`, `LLM/`, `Mistake/{PDF,Audio,LLM}/` |
| Managers | Place under `Managers/{Core,Health,Logging,PDF,Report,Study,Utility,Widget,Achievement,Audio,LLM}/`; own `@Published` state → mark `@MainActor` |
| Strings | Always use `"key".localized` — **never** write inline English |
| Colors / Dates | Use `ColorExtensions` / `DateExtensions` wrappers |
| Images | Persist as files in `~/Documents/images/` via `ImageStorage`; never inline `Data` in JSON (`Grade.imageData` only in `GradeRecord`) |
| Audio | Persist as files in `~/Documents/audio/<uuid>.m4a`; store `filename` only in `MistakeNote.audioFileName` |
| Voice memos | Use `AVFoundation` (`AVAudioRecorder` / `AVAudioPlayer`); `Info.plist` must declare `NSMicrophoneUsageDescription` |
| Mistake editing | Driven by `EditSection` enum (Question / Reason / Wrong / Correct) |
| Markdown | Use `SwiftStreamingMarkdown` `MarkdownView`; never roll a custom Markdown + KaTeX parser |
| Education systems | Always use `EducationConfig` (nonisolated enum) with `SubjectConfig` factories (`required(...)` / `elective(...)`) |
| iPad adaptation | Prefer helpers in `iPadLayout.swift` instead of inline size-class branches |
| Liquid Glass | Use `.glassCard(enabled:cornerRadius:)` modifier; falls back to `.regularMaterial` on iOS < 26 |
| LLM | `LLMClient` is `@MainActor` singleton; **always** receive `AppPreferences` from environment (never `AppPreferences()`); on any `LLMError` **silently fall back to local** and log to `Log.llm` — never show alert |
| LLM prompts | Per-feature prompt factory lives in `LLMRequestBuilder.<FeatureName>LLM`; output must follow a fixed `## ...` format so `LLMResponseParser` can merge back to local model while preserving `icon/priority/color` |
| LLM cooldowns | `canRequestNow()` enforced for 40-min cool cards (radar + study-suggestions); only "立刻分析" button can bypass |
| LLM UI | "深入探讨" sheet places last AI output only in system prompt (with `===` separator); never as first `assistant` conversation message |
| LLM debug | DEBUG-only `.llmDebugHomeButton()` + `LLMDebugSheet`; never shipped in Release |
| LLM Chat | `LLMChatView` history in-memory only; clear on `onDisappear` |
| Project file | pbxproj uses Xcode 16+ `PBXFileSystemSynchronizedRootGroup` (objectVersion 77); new `.swift` files in `StudyPulse/` are picked up automatically; **do not edit `project.pbxproj` by hand** |
| After every non-trivial code change | Run build (Xcode Cmd+B or `./scripts/build.sh`) and ensure no syntax / type errors |

---

## 18. Performance Notes

| Optimization | Details |
|---|---|
| Async startup | `StudyPulseApp` calls `container.asyncInit()` in `.task`; SwiftData `ModelContainer` is built once via `ModelContainerFactory.makeContainer()`; legacy JSON files migrated once on first launch via `ModelContainerFactory.migrateFromJSONIfNeeded` (UserDefaults flag) |
| Repositories load off main | 7 repositories load data on `Task.detached`, then assign `@Published` on `MainActor` |
| Image caching | `ImageCache.shared` — `NSCache` with 50 entries, 300 px max; fully thread-safe (nonisolated) |
| Days-remaining | `ExamRowView`, `ComprehensiveExamRowView`, `UpcomingExamCard` use computed `daysRemaining` rather than `@State + onAppear` to avoid spurious re-renders |
| iPad HomeView | Renders dashboard in a two-column `LazyVGrid` to keep memory low even when many cards are enabled |
| LLM streaming | `LLMClient.stream(...)` parses SSE chunks and feeds `AsyncStream` to `MarkdownView` (no waiting for the full response) |
| LLM debug buffer | `LLMClient.recentCalls` is a 20-entry ring; never unbounded |
| `RecentGradesSection` | Loads only the last 5 grades to keep home view render cheap |

---

## 19. Known Issues / TODO

| Issue | Status | Impact |
|---|---|---|
| Widget Extension target — verify it's wired into `StudyPulse.xcodeproj` | Verify | WidgetKit sources exist in `StudyPulseWidget/`; need to confirm the target is configured with the right App Group + entitlements |
| App Group identifier not enabled on main app target | Open | App Group `group.com.chenkai.gao.studypulse` must be created in Apple Developer portal and enabled on both main app target and widget target |
| No iCloud sync | Open | All data is local to the device sandbox |
| `TestData/__pycache__/` not in `.gitignore` | Open | Python compilation cache files (`*.pyc`) are accidentally generated; should be added to `.gitignore` to avoid polluting `git status` |
| `NewMistakeSheet.swift` / `Views/Sheets/` removed | Closed (historical) | Active flow is `NewMistakeSetView`; do not re-create the old paths |
| `@Equatable` macro in `SwiftStreamingMarkdown` | Resolved | Removed to fix build slowdowns; auto-synthesized `Equatable` works fine for our usage |

---

## 20. Changelog (Agent-Facing)

### v2026.07.12 — HomeAsk + 雷达 LLM 冷却 + LLM DEBUG + 错题语音 + AI 相似题 (commit `3b364a5d`)

- **HomeAsk 主页 AI 问答主卡片**: 新增 `HomeCardType.homeAsk` + `Views/Home/HomeCards/HomeAskCard.swift` + `Views/LLM/HomeAskSheet.swift` + `ViewModels/HomeAskViewModel.swift` + `Managers/LLM/HomeAskDataProvider.swift`(按输入关键词自动选择 4 类上下文 `grade/mistake/trend/readiness`);`HomeView` 集成 + 跳过长按分享菜单(卡片含 Button 不参与导出图片)。
- **雷达 LLM 40 分钟冷却**: `AppPreferences.lastRadarAIRequestTime` 持久化;`HRVStatusCard` 实现 `canRequestNow() / requestAIImmediately()` + 倒计时 UI + 「立刻分析」按钮绕过冷却。`StudyReadinessAlgorithm` 新增 `BodyReadinessContext`;`LLMRequestBuilder.BodyRadarLLM` 按 `## 强度/标题/建议/依据` 4 段解析,**保留本地 `icon/priority/color`**。`buildBodyReadinessContext` 必须在 `@MainActor` 调用。
- **LLM DEBUG 模式**: `LLMCallDebugInfo` (`startTime/endTime/url/model/temperature/systemPrompt/messages/response/error/caller` + `asDebugJSON()`) + `LLMClient.lastCallInfo` + 20 条环形 `recentCalls`;`DebugModifiers` 新增 `.llmDebugHomeButton()` (`caller = nil` 显示全部分组) + `LLMCallIndicator`;`LLMDebugSheet` 按 caller 分组显示历史 + JSON 详情;修复 `LLMChatViewModel` 用 `AppPreferences()` 而非环境注入导致 debug 面板看不到 override 的问题。
- **错题语音备忘录**: 新增 `Managers/Audio/{AudioStorage, VoiceMemoManager}.swift` + `Views/Mistake/Audio/{AudioPlaybackView, VoiceMemoRecordingSheet}.swift`;`MistakeNote` 新增 `audioFileName: String?` 字段;`MistakeDetailEditView` 录音 + 删除;`MistakeSetDetailView` 详情页嵌入 `AudioPlaybackView`;Info.plist 新增 `NSMicrophoneUsageDescription`。
- **AI 相似题组卷**: `Views/Mistake/LLM/AISimilarQuestionFlowView.swift`;`MistakeView` toolbar 改 Menu 整合「AI 解析错因」 + 「AI 相似题组卷」。
- **Chat 组件重构**: 删除 `LLMMessageBubbleView.swift`,拆为 `Views/LLM/ChatBubble.swift` + `ChatInputBar.swift`;`LLMChatView` + `AIDiscussionSheet` 共用。
- **`StudySuggestionsCard` 同样接入 40 分钟冷却**(`AppPreferences.lastStudySuggestionsAIRequestTime` + `canRequestNow()`)。
- 5 语言本地化同步(HomeAsk / 雷达 LLM / DEBUG / 语音 / 相似题 / 立刻分析)。

### v2026.07.05 — BYOK 大模型集成 (commit `5cc4d5b9`)

- 新增 `Managers/LLM/` 7 个文件: `LLMConfig` / `LLMError` / `LLMPrompt` / `LLMRequestBuilder` / `LLMResponseParser` / `LLMClient` / `HomeAskDataProvider`。
- 新增 4 大用户面 AI 功能: 主页 `StudySuggestionsCard`、错题 `MistakeAIAnalysisSheet`、周报 `WeeklyReportView` AI Summary、通用 `LLMChatView`。
- 新增「深入探讨」`AIDiscussionSheet`(错题解析 / 成绩预测 / 雷达建议的二次讨论入口)。
- 5 语言本地化同步。

### v2026.06.20 — Home layout + HRV subsystem

- Added HealthKitManager.swift, HRVOnboardingView.swift, HRVStatusCard.swift for HRV (SDNN) readiness (14-day baseline + Z-score category).
- Added HomeLayoutPreference.swift and HomeLayoutSettingsView.swift for per-card on/off + drag-to-reorder (persisted to UserDefaults).
- Added Views/Admin/DataAdminView.swift for power-user bulk data ops.
- Rewrote ContentView with custom NavigationSplitView sidebar for iPad (replaces `.sidebarAdaptable`); iPhone keeps classic TabView.
- HomeView composes its dashboard from `HomeLayoutPreference.load().enabledTypes` using HomeCardType cases.
- Added "Unregistered Exams Reminder" card (3–7 day window after an exam with no matching grade).
- StudyPulse.entitlements now includes `com.apple.developer.healthkit`.
- Rewrote AGENTS.md / CODE_WIKI.md / CODE_WIKI_CN.md / README.md.

### v2026.06.13 — iPad adaptation

- iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) via iPadLayout.swift helpers (`adaptiveMaxWidth`, `AdaptiveHStack`, `AdaptiveGridColumns`, `adaptiveCardPadding`).

### v2026.06.07 — Full view-layer refactor + design system

- HomeView split into components; gradient + animation polish.
- MistakeView suggested review + card gradient.
- TrendsView "Subjects Needing Attention" smart alerts.
- ExamDetailView related mistakes section.
- SubjectScoreCard gradient border + entrance animation.
- AppStyle design-system skeleton.
- First StudyPulseWidget skeleton.

### v2026.06.06 — Multi-language

- zh-Hant, ja, ko localizations added.

### v2026.06.05 — Mistake module launch

- 4-section mistake editor (Question / Reason / Wrong / Correct).
- Per-section photo + OCR (Vision).
- Markdown preview (swift-markdown-ui).
- Calendar / notification auto-scheduling.
- Zoomable image viewer.

### v2026.06 — Global education systems

- EducationConfig for 15+ systems (CN, UK, IB, AP, SAT, ACT, GRE, GMAT, TOEFL, IELTS, DSE, etc.).
- SubjectConfig factories (`required(...)`, `elective(...)`).
- Avatar system, proportional score-color mapping, expanded profile.
