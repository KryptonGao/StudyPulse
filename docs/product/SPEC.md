# StudyPulse — Product Specification

> Functional and non-functional specification for the **StudyPulse** iOS app.
> Authoritative source for product scope, features, requirements, and
> release planning. For architecture and code structure, see
> [AGENTS.md](../../AGENTS.md). For design language, see [DESIGN.md](DESIGN.md).

---

## 1. Product Summary

**StudyPulse** is a personal study-management app for iPhone and iPad that
helps students track academic grades, manage a mistake notebook, schedule
exams, sync with HealthKit for HRV-based study-readiness, and visualise
learning trends across many global education systems.

- **Bundle ID:** `Gao.Chenkai.StudyPulse`
- **Platforms:** iOS 18.6+, iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`)
- **Languages:** English, Simplified Chinese, Traditional Chinese, Japanese, Korean
- **License:** CC BY-NC-SA 4.0
- **Distribution:** App Store (developer `Gao-Chenkai` / `Ken8891837`)

---

## 2. Target Users

| Persona          | Age  | Profile                                  | Primary need                          |
|------------------|------|------------------------------------------|---------------------------------------|
| High-schooler    | 15–18| Daily multi-subject study load           | Track grades, see weak subjects       |
| Gaokao / DSE / AP student | 16–19 | High-stakes exam prep, fixed score scales | Subject-level trends, exam countdowns |
| IGCSE / A-Level student | 14–18 | UK / international curriculum           | Match subject names to local system   |
| IB / AP student  | 16–19| Crossover (CN + international subjects)  | Custom full scores per subject        |
| Health-aware student | 16–22 | Wears Apple Watch overnight         | HRV-based "should I push today?" cue  |
| Multi-year / multi-semester | 14–22 | Multi-year prep with mixed exams | Study phase scoping + goals tracking  |

The product is **not** aimed at primary-schoolers, university research
students, or non-students. Tone is calm, technical, neutral.

---

## 3. In-Scope Features

### 3.1 Grade tracking
- Add a single grade with subject, score, raw score, ranking, importance
  (1–5), date, exam name, and a full-score override.
- Optional photo of the original paper (saved as `images/grade_{uuid}.jpg`).
- Subject list is **derived from the user's education system** (see §3.6);
  full score per subject is customisable.
- List / edit / delete.
- Per-grade phase attribution (see §3.15 Study Phase).
- See Trends (§3.4) for visualisation.

### 3.2 Mistake notebook
- Four-section entry: **Question / Reason / Wrong / Correct**.
- Per-section photos (camera or library).
- OCR (Vision, `zh-Hans` + `en`, `.accurate`) one-tap into the active
  text field.
- Markdown preview per text field; the `MistakeSetDetailView` displays the
  **rendered** output (not the raw Markdown source).
- Searchable by title, question, source, subject.
- "Suggested for Review" surfaced on the Mistakes tab based on age +
  subject priority.
- Pinch-to-zoom image viewer.
- **PDF export**: a `square.and.arrow.up` button on the
  Mistakes toolbar opens an export sheet with three selection modes
  (subjects / date range / individual mistakes), an "Include Images"
  toggle (on by default), and a live preview of the mistake count.
  Generation runs on `MainActor` via **Core Text + `NSAttributedString`**
  drawn into a `UIGraphicsPDFRenderer` context, producing an A4
  (595×842 pt) PDF with a cover page, a table of contents, and one or
  more pages per mistake (`CTFramesetter` auto-paginates text;
  overflow is rendered on the next page; long sections span
  multiple pages automatically). Text is embedded as **vector PDF
  fonts** so it remains selectable / copyable / searchable in any
  PDF reader. The output is exposed via `FileDocument` and the
  standard share sheet (`.fileExporter`).
- Per-mistake phase attribution (see §3.15).

### 3.3 Exam scheduling
- Single-subject exam (`Exam`) and multi-subject comprehensive exam
  (`comprehensiveExam`).
- "Add to Calendar" toggle (EventKit, all-day event or a specific
  `ExamTimeSlot` for start/end times, 1-day reminder).
- Local notifications at user-configurable countdown days
  (`countdownNotifyDays`, default `[1, 3, 5, 10, 30]`); an empty
  list disables notifications.
- "Related Mistakes" section on `ExamDetailView` for the same subject.
- "Unregistered-exam reminder" card on Home for exams from 3–7 days
  ago with no matching grade.
- Per-exam phase attribution (see §3.15).

### 3.3a Exam pre-exam checklist & location
Each `Exam` carries:

- **`checklist: [ExamChecklistItem]`** — pre-exam to-do items
  (id / title / isChecked / sortOrder). Editable in `ExamDetailView`; the
  detail view also lets the user re-order or add new items. Toggling an
  item is persisted via `RepositoryContainer.toggleExamChecklistItem`.
- **`locationSchool` / `locationClassroom` / `locationSeat: String`**
  — exam venue info displayed in the detail view.
- **`countdownNotifyDays: [Int]?`** — replaces the legacy fixed
  `[1, 3, 5, 10, 30]`; `nil` means "use default", `[]` means "no
  notifications". `ExamPrepareNotifications.scheduleNotifications(for:date:days:)`
  cancels the previous schedule (by `identifier` prefix
  `Exam_<name>_`) before re-arming, so editing the list is idempotent.
  Past dates are skipped automatically.
- **`examReview: ExamReview?`** — post-exam review (free-form notes,
  reflection, follow-up actions). Editable via `ExamReviewView`.
- **"Share with family" button** in `ExamDetailView` (uses SwiftUI
  `ShareLink`, iOS 16+) that exports the exam + checklist + location
  to a Markdown file for messaging apps.

### 3.3b Todo / Task tracker
- Two task types in addition to exams: **Homework** (日常作业)
  and **Reading Material** (阅读材料), each with:
  - Title, type, related subject, importance (1–5), notes.
  - **Due date** (截止日期) and **reminder time** (提醒时间), set
    independently by the user.
  - Completion toggle (`isCompleted`), surfaced via strikethrough and
    a half-opacity card.
- Unified **Todo** page (replaces the former "Exams" tab) with:
  - All three types rendered as `TodoEntry` rows with a coloured type
    tag (Exam / Compre. / Homework / Reading).
  - Filter chips (All / Exams / Homework / Reading) and a "Show
    Completed" toggle.
  - Time-based grouping (Within 1 Week / Within 1 Month / Later) and a
    "Past Items" sheet.
  - List mode and Calendar mode (calendar mode is exam-only).
- Reminders / Calendar split:
  - **Exams** continue to sync to the system Calendar via
    `EKEventStore` (existing `CalendarManager.addExamToCalendar`).
  - **Homework / Reading** sync to the system Reminders app via
    `EKReminder`, with `dueDateComponents` driven by the task's due
    date and an `EKAlarm(absoluteDate:)` driven by the reminder time.
- Reminder edit behaviour:
  - Toggling the completion flag mirrors to the linked Reminder.
  - Editing a synced task calls `updateTaskInReminders`; if the
    Reminder has been deleted externally, a new one is created.
  - Deleting a task removes its linked Reminder.
  - The user may opt out of Reminders sync per task; opt-out deletes
    any existing linked Reminder.
- Per-task phase attribution (see §3.15).

### 3.4 Trends
- Per-subject line / bar / pie / scatter / heatmap / histogram chart
  of score rate over time (chart type selected in §3.10).
- "Subjects Needing Attention" alerts:
  - Average rate < 70 %, **or**
  - Recent decline > 15 points.
- Score / ranking mode toggle.
- Optional **90-day learning heatmap** at the top of the page
  (controlled by `AppPreferences.learningHeatmapOnTrends`, on by
  default; toggle lives in the Trends toolbar Menu).

### 3.5 HRV-based study readiness
- Reads `HKQuantityTypeIdentifier.heartRateVariabilitySDNN` from
  HealthKit, last 14 days.
- Baseline: mean + std-dev of days **after today**, requires ≥ 7 distinct
  days.
- Z-score → category:
  - `excellent` (z > 1.0)
  - `normal`   (-1.0 ≤ z ≤ 1.0)
  - `low`      (z < -1.0)
  - `insufficient` (< 7 days)
  - `noAuthorization` / `queryFailed` for non-data states
- Three detail levels: suggestion only / data + suggestion / chart + data.
- Onboarding flow explains HRV, privacy, and requests consent before
  the first `requestAuthorization` call.

### 3.6 Global education systems
15+ systems supported, configured in `EducationConfig`:

| Family   | Codes                                                              |
|----------|--------------------------------------------------------------------|
| CN       | CN-MID, CN-HS, CN-ZJ-MID, CN-ZJ-3+3, CN-SH-MID, CN-SH-3+3         |
| TW       | TW-MID, TW-GSAT                                                    |
| HK       | HK-DSE                                                             |
| SG       | SG-OLEVEL                                                          |
| UK       | UK-IGCSE, UK-ALEVEL                                               |
| IB       | IB-DP                                                              |
| US       | US-AP, US-SAT, US-ACT                                             |
| GRAD     | GRE, GMAT, TOEFL, IELTS                                            |

The system list is the source of truth for default subject names and
default full scores per subject.

### 3.7 Home dashboard
- Customisable card order (drag to reorder) and visibility (on / off).
- Default cards: HRV, Unregistered-exam reminder, Quick Actions, Study
  Suggestions, Trend Chart, Upcoming Exams, Daily Quote, Recent Grades,
  **90-day Learning Heatmap** (full-width by default at the top),
  **Streak Progress**.
- Daily motivational quote rotated by day-of-year.
- Daily activity summary (`StreakHomeCard`): three goals
  (mistake review / grade record / focus minutes) and the current
  streak; tap opens `AchievementsView`.
- iPad: 2-column `LazyVGrid`; full-width cards (e.g. learning heatmap)
  span the entire row.

### 3.8 Data admin
- `Views/Admin/DataAdminView.swift` lists every grade, exam, and mistake
  with bulk actions for power users.
- CSV export for grades / mistakes / exams / comprehensive exams
  (`DataExportManager`, share sheet via `UIActivityViewController`).
- CSV import path covered in the data layer (TBD via UI).

### 3.9 Customisable Home layout
- `HomeLayoutPreference` is persisted in `UserDefaults` and read by
  `HomeView` on every render. Future card types merge into the existing
  user choices via `mergeWithDefault`.
- `HomeCardType.isFullWidth` flags cards that should span the full iPad
  grid width.

### 3.10 Settings
- **Profile**: name, school, grade, class, student ID, enrollment year,
  exam year, target school, target score, avatar.
- **Subject selection + full score override.**
- **Appearance**: Light / Dark / Follow System; **accent colour** (11
  presets, see §3.16); **glass effect** (iOS 26, opt-in per card,
  default off); **Trends heatmap** toggle.
- **Home Layout**: card order + visibility; chart type
  (line / bar / pie / scatter / heatmap / histogram); contribution
  graph configuration.
- **HRV toggle, HRV detail level**.
- **Achievements & Daily Goals**: streak / achievement catalogue +
  per-day target configuration + 20:00 reminder time.
- **Data Management**: **Phase Management** (top of the section;
  active list / archived disclosure / overview / edit / archive /
  delete) + CSV export / import + Developer Admin + **Export Log**.
- **About**: version / copyright / test notifications /
  `UserAgreementView` (full v1.0 text).

### 3.11 Onboarding
- Version-aware welcome page (`VersionedWelcomeModifier`):
  first launch shows the welcome page; version bump shows the
  "what's new" page; same version suppresses it.
- Native iOS 26 welcome UI (TabView pagination + gradient
  background + glass cards); older OS falls back to
  `.regularMaterial`.
- **HRV consent flow** (`HRVOnboardingView`) shown before the first
  HealthKit authorization request.
- 6-page **basic-info form** (`OnboardingProfileFormView`) for
  collecting username, school, education stage, region, subjects,
  etc. Draft state is auto-saved and can be recovered after a crash.

### 3.12 iPad adaptation
- `NavigationSplitView` sidebar with 5 destinations, column width
  220–280 pt.
- `iPadLayout.swift` provides `adaptiveMaxWidth`,
  `AdaptiveHStack`, `AdaptiveGridColumns`, `adaptiveCardPadding`.
- Max content widths per view (640 / 720 / 800 / 900 / 1100 pt).
- Home dashboard on iPad is a 2-column `LazyVGrid` with full-width
  card support.
- Keyboard navigation: `Tab` cycles, `1`–`5` jumps to a tab.
- Medium haptic on tab change.

### 3.13 Localisation
- Five locales (en, zh-Hans, zh-Hant, ja, ko) — all keys covered in
  every `Localizable.strings`.
- Language switcher in Preferences mutates the `AppleLanguages` key in
  `UserDefaults` and is applied at next launch.

### 3.14 Widget (Live)
- `StudyPulseWidgetExtension` target is wired into the Xcode project.
- Four widgets:
  1. **ExamWidget** (S / M / L) — next upcoming exam.
  2. **TrendWidget** — subject grade trend line.
  3. **HRVWidget** — HRV readiness card.
  4. **StudyTimerLiveActivity** — Lock Screen + Dynamic Island
     (compact / minimal / expanded).
- Reads from App Group `group.com.chenkai.gao.studypulse`.
- All five locales localised in `StudyPulseWidget/{lang}.lproj/Localizable.strings`.

### 3.15 Study Phase (学期 / 假期阶段)
A **phase** is a user-defined time window (e.g. "2026 春季学期",
"2026 暑假", "高考冲刺") that scopes grades / mistakes / exams / tasks
so historical data stays bounded. Phases prevent, for example, three
years of mistake questions from mixing in a single timeline.

- A phase is a `StudyPhase` struct: `id` / `name` / `startDate` /
  `endDate` / `isArchived` / `archivedAt` / `goals: [PhaseGoal]` /
  `createdAt`.
- `PhaseGoal` is a per-phase target (`subject` / `targetScore` /
  `notes`); for example "期末数学 ≥ 120".
- `AppPreferences.activePhaseId: UUID?` selects the active phase.
  `nil` = "All Data" (no filtering).
- The five main pages (Home / Trends / Mistake / Todo / Exam) all
  expose a **`PhaseSelectorView`** pill in their toolbar
  `.principal` position; switching the phase triggers
  `RepositoryContainer.recomputeAllFiltered()` which refreshes
  per-repository `filtered*` caches.
- All five domain entities (`Grade` / `MistakeNote` / `Exam` /
  `comprehensiveExam` / `TaskItem`) carry an optional `phaseId`
  field. New entries auto-inherit the active phase; archived /
  deleted phases have their `phaseId` references cleared from all
  entities.
- **`PhaseManagementView`** (Settings → Data Management) provides:
  - **Active list** — switchable; each row links to `PhaseEditView`.
  - **Archived disclosure** — collapsed by default; per-archived-phase
    unarchive / delete actions.
  - **Overview** — counts of grades / mistakes / exams / tasks per phase.
- **`PhaseEditView`** — name / start / end / `goals` editor
  (CRUD for `PhaseGoal`).
- Phase filtering is `nil`-aware: "All Data" is always present in
  the selector and is the default for new users.

### 3.16 Customisation
- **Accent colour** — 11 presets (`system` / `blue` / `cyan` / `teal`
  / `green` / `mint` / `orange` / `red` / `pink` / `purple` /
  `indigo`); persisted as `AppPreferences.accentPaletteId`. The
  selected accent drives `ContentView.tint()`, the
  `TrendChartView` line / bar colour, and the
  `FlashcardStudyView` progress bar. State-coloured ProgressViews
  (Todo time-left, Exam mastery) intentionally stay colour-coded by
  state.
- **Liquid Glass effect** — iOS 26 `glassEffect` opt-in per card via
  the `.glassCard(enabled:cornerRadius:)` modifier. Global toggle in
  `AppPreferences.glassEffectEnabled`; on older OS the modifier
  falls back to `.regularMaterial`. Implementations must use
  `Color.clear` + `glassEffect(in: Capsule())`; applying
  `glassEffect` directly to a `Capsule()` produces an opaque result.
- **Custom background image** — user picks a photo; the app
  centre-crops it to a 9:19.5 iPhone aspect ratio and stores it in
  `Application Support/Backgrounds/bg_<uuid}.jpg`. `BackgroundImageView`
  renders the image full-bleed (`aspectRatio(.fill)` +
  `ignoresSafeArea()` + blur + dim overlay) at the bottom of
  `ContentView`'s ZStack.
  - For the image to actually show through, the five main page
    roots use `Color(.systemGroupedBackground).opacity(0.4)`.
  - `List` (Settings) and `Form` (Preferences) views additionally
    apply `.scrollContentBackground(.hidden)` so their default
    opaque backgrounds don't block the image.
  - iOS 26 `NavigationStack` has an opaque default
    `containerBackground`; each NavigationStack root content needs
    `.containerBackground(.clear, for: .navigation)`.
  - `TabView` needs `.toolbarBackground(.hidden, for: .tabBar)` to
    keep the tab bar transparent.

### 3.17 90-day Learning Heatmap
- A GitHub-style 7 × 13 grid (`LearningHeatmapView`).
- 90-day rolling window sourced from
  `AchievementManager.shared.snapshot.logs`; intensity per cell is
  `DailyActivityLog.totalActivityPoints` (mistake reviews + 5 ×
  grades recorded + focus minutes).
- Five intensity buckets (`none` / `light` / `medium` / `strong` /
  `intense`) coloured with the active accent at different opacities.
- Tap on a cell opens a detail sheet for that day (mistake reviews /
  grades / focus minutes / total activity points).
- Top of the view shows the 90-day active-day count and current
  streak; bottom shows the colour legend including the best day.
- Two integration points:
  - **HomeView** — top, full-width card (`HomeCardType.learningHeatmap`,
    `isFullWidth = true`); participates in `HomeLayoutPreference`.
  - **TrendsView** — top, controlled by
    `AppPreferences.learningHeatmapOnTrends`; the toggle lives in
    the Trends toolbar Menu below a `Divider`.
- Localisation: 5 locales carry `heatmap.*` keys; the
  `heatmap.bestDay` format string's placeholders are
  `%d` (Int) followed by `%@` (String).

### 3.18 Study Timer + Live Activity
- 5 intensities (peak / deepFocus / steady / light / recovery)
  matched to `StudyReadinessAlgorithm`'s suggested intensity.
- Sessions are persisted to `~/Documents/study_sessions.json` on
  completion and contribute to `AchievementManager.recordFocusMinutes`.
- `StudyTimerLiveActivity` provides Lock Screen + Dynamic Island
  (compact leading / compact trailing / minimal / expanded) UIs.
- A single device can host at most 8 Live Activities; the timer
  manager checks `Activity<StudyTimerActivityAttributes>.activities`
  before starting to avoid duplicates.

### 3.19 Achievements & Streak
- 3 daily goals: mistake reviews, grade records, focus minutes.
- Streak counter; cumulative progress; achievement catalogue
  (compile-time constants in `AchievementCatalog.swift`).
- `DailyGoalReminder` schedules a 20:00 local notification when
  any goal is still unmet.
- `AchievementStore` JSON-persists the snapshot (NSLock thread-safe)
  and reverse-engineers 30 days of history from `grades.json` /
  `study_sessions.json` on first launch.

### 3.20 Study Report
- `ReportContentView` (no `@EnvironmentObject` dependency) renders
  the user's grades / mistakes / exams / HRV into a single SwiftUI
  view.
- `ReportRenderer` uses `ImageRenderer` + Core Graphics to export
  PNG / JPEG; `ReportImageDocument` wraps the image for
  `.fileExporter`.
- `ReportOptionsSheet` collects the report range + module toggles;
  `ReportShareSheet` triggers the share.

### 3.21 Flashcard SRS (SM-2)
- Mistake notes can be enqueued for spaced-repetition review.
- `ReviewState` is embedded in `MistakeNote` and tracks SM-2 fields
  (repetitions / easeFactor / intervalDays / nextReviewDate /
  lastReviewDate / lapses).
- `FlashcardStudyView` drives the review session;
  `FlashcardCalculatorView` debugs SM-2 parameters.
- `SRSReviewNotifications` reschedules local notifications based
  on `nextReviewDate`.

### 3.22 Siri Shortcuts (App Intents)
- Six App Intents exposed via `StudyPulseShortcuts`:
  1. `AddGradeIntent` — add a grade.
  2. `RecordMistakeIntent` — record a mistake.
  3. `CheckUpcomingExamsIntent` — query upcoming exams.
  4. `CheckBodyStatusIntent` — query today's body readiness.
  5. `CheckReadinessIntent` — query today's HRV readiness.
  6. `CheckSubjectAverageIntent` — query a subject's average.
- Cross-process handoff via `IntentActionStore` /
  `IntentAction.pendingIntentAction`. `ContentView` observes the
  store and routes the action to the corresponding view / sheet;
  the action is cleared after handling.
- `SubjectEntity` is a typed `AppEntity` so subjects can be passed
  as parameters to the intents.

### 3.23 Architecture
- **MVVM + Repository**.
  - Views are pure SwiftUI; they read data from
    `RepositoryContainer` via `@Environment(RepositoryContainer.self)`.
  - Each main page has a `@MainActor final class XxxViewModel: ObservableObject`
    with `@Published private(set)` state and a
    `static func makeDefault(container:)` factory. Child views take
    the view model as `let viewModel: XxxViewModel` + `@ObservedObject`.
  - **Seven repositories** (`GradeRepository` /
    `MistakeRepository` / `ExamRepository` / `TaskRepository` /
    `PhaseRepository` / `ProfileRepository` / `SubjectRepository`)
    each implement a `@MainActor` protocol; they expose `xxx` (all
    data) and `filteredXxx` (active-phase-filtered) arrays.
  - `RepositoryContainer` is the entry point — it aggregates the
    7 repositories, holds the `ModelContainer`, exposes `isReady`,
    and orchestrates cross-domain side effects
    (`addGrade` / `addMistake` / `addExams` / `addTask` /
    `deleteXxx` / `activatePhase`).
  - **Six pure-function services** in `Services/`:
    `DateFormatters` / `SubjectAggregator` /
    `SuggestionEngine` / `ExamFilter` / `MistakeFilter` /
    `QuoteProvider` (the last is the only one that imports
    SwiftUI, because `StudySuggestion.color: Color`).
- **Persistence**
  - SwiftData is the active persistence layer
    (`Models/SwiftData/StudyPulseModels.swift`,
    `Managers/Core/ModelContainerFactory.swift`).
  - The factory is a process-singleton; the same `ModelContainer`
    is shared with the Scene's `.modelContainer(...)` modifier.
  - `ModelContainerFactory.migrateFromJSONIfNeeded(context:)`
    runs once on first launch (UserDefaults flag) to import any
    pre-existing `~/Documents/*.json` data.
  - 9 entities are listed in `ModelContainerFactory.modelTypes`
    (including `StudyPhaseRecord`); adding a new `@Model` requires
    updating this array AND the corresponding `toSnapshot()` /
    `init(from:)`.
  - Lightweight migrations handle the addition of optional
    `phaseId` fields and new `@Model` entities automatically.
  - View layer still uses `nonisolated value type` structs; the
    repository converts to/from SwiftData entities on read / write.
- **Concurrency** — Swift 6 strict concurrency,
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- **Logging** — `os.Logger` + `LogStore` (5000-entry NSLock-bounded
  in-memory buffer) + `LogDocument` export. `LagMonitor` watches
  the main thread via `CADisplayLink` and writes frame drops to
  `LogStore`.

---

## 4. Out-of-Scope

- iCloud sync (data is local to the device sandbox only; the
  SwiftData layer is the future carrier for sync).
- Real-time shared study sessions / social features.
- Cloud backup of images.
- Web companion.
- Apple Pencil-first mistake editing.
- macOS / Mac Catalyst first-class experience (iPad layout is
  Catalyst-friendly but not optimised for menu bar / multi-window).
- Per-user subject colour override (colours come from the
  education config; future enhancement).
- iPad Stage Manager multi-window behaviour.

---

## 5. Functional Requirements

| ID    | Requirement                                                                                       |
|-------|---------------------------------------------------------------------------------------------------|
| F-01  | All persistent state must survive app relaunch and device reboot.                                 |
| F-02  | SwiftData entities (with the original JSON import) are the source of truth. UserDefaults holds small prefs only. |
| F-03  | Image bytes are written to `~/Documents/images/`, never inlined in JSON.                          |
| F-04  | Inline `Grade.image` data from old installs is migrated on first launch to file-based storage.    |
| F-05  | All views read shared state via `@Environment(RepositoryContainer.self)`; data updates flow through repository `@Published` arrays. |
| F-06  | Adding / editing an exam with the calendar toggle on must create an EventKit event (all-day or with `ExamTimeSlot`) + 1-day reminder. |
| F-07  | Adding / editing an exam must schedule local notifications at the days configured in `countdownNotifyDays` (default `[1, 3, 5, 10, 30]`). |
| F-08  | HRV data must be refreshed on app launch, on `hrvEnabled` toggle on, and on manual pull-to-refresh. |
| F-09  | HRV data must NOT be requested until the user has finished `HRVOnboardingView` and granted consent. |
| F-10  | The Home dashboard must reflect `HomeLayoutPreference` exactly: ordered, filtered by `enabled`.  |
| F-11  | Home cards with no data (recent grades, upcoming exams, unregistered exams) must hide themselves. |
| F-12  | Score-rate colour thresholds (90 / 75 / 60 %) must apply to every education system, including IB (7 pts) and SAT (800 pts). |
| F-13  | iPad must use `NavigationSplitView` for top-level navigation. iPhone must use `TabView`.         |
| F-14  | iPad content must be centered with the per-view max-width; iPhone must remain full-bleed.        |
| F-15  | Every user-facing string must come from `Localizable.strings` via `"…".localized()`.              |
| F-16  | CSV export must escape commas, quotes, and newlines correctly.                                   |
| F-17  | All app-internal model types must be `nonisolated`, `Codable`, `Sendable`, and value types.       |
| F-18  | `RepositoryContainer.asyncInit` must finish (`isReady = true`) before the first widget sync / `HealthKitManager.bootstrap` / `AchievementManager.bootstrap`. |
| F-19  | iPhone hardware keyboard `Tab` cycles tabs; `1`–`5` jumps to a tab.                              |
| F-20  | Tab change must trigger a single medium haptic.                                                  |
| F-21  | Switching the active `StudyPhase` must refresh all 5 `filtered*` repository caches atomically; the active phase pill must appear in the toolbar of Home / Trends / Mistake / Todo / Exam. |
| F-22  | New grade / mistake / exam / task entries must inherit the active `phaseId` automatically.       |
| F-23  | Deleting a phase must clear its `phaseId` reference from every grade / mistake / exam / task.    |
| F-24  | The 90-day learning heatmap must appear at the top of the Home dashboard by default and respect the Trends-page toggle in `AppPreferences.learningHeatmapOnTrends`. |
| F-25  | The exam detail view must support `checklist` toggling, location fields, `countdownNotifyDays` editing, `ExamReview` entry, and "Share with family" Markdown export. |
| F-26  | Custom background image must be centre-cropped to 9:19.5 and rendered full-bleed with blur + dim; the main page roots must use 0.4-opacity `systemGroupedBackground` and `List` / `Form` views must hide their opaque backgrounds. |
| F-27  | iOS 26 `glassEffect` opt-in cards must use `Color.clear` + `glassEffect(in: Capsule())`; older OS falls back to `.regularMaterial`. |
| F-28  | The 6 Siri Shortcut App Intents must handoff to the main app via `IntentActionStore`; the action must be cleared after handling. |

---

## 6. Non-Functional Requirements

| ID    | Requirement                                                                              |
|-------|------------------------------------------------------------------------------------------|
| N-01  | Cold launch → first Home render ≤ 1.5 s on iPhone 15 simulator with seeded data.         |
| N-02  | No main-thread JSON / SwiftData decoding during the visible launch. All `~/Documents` reads use `DataFileIO` (nonisolated). |
| N-03  | Thumbnail cache must cap at 50 entries / 300 px max dimension, evict under pressure.   |
| N-04  | All async work uses `Task.detached` or `withCheckedContinuation`; no `DispatchQueue.global().async` for app data. |
| N-05  | Minimum iOS 18.6, deployment target reflects Xcode 26 toolchain.                        |
| N-06  | Swift 6 strict concurrency; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.                 |
| N-07  | No third-party analytics, no crash reporting, no remote configuration.                  |
| N-08  | App size on disk ≤ 80 MB (excluding user data and images).                              |
| N-09  | Battery: HRV refresh ≤ 1x per app foreground. No background HealthKit queries in v1.    |
| N-10  | Localisation coverage: 100 % of keys present in every `Localizable.strings`.            |
| N-11  | Xcode IDE and xcodebuild CLI must not run concurrently on the same `DerivedData` (causes `build.db` SQLite lock); use `DerivedDataBuild/` to isolate. |
| N-12  | `RepositoryContainer.observeActivePhaseChanges()` polls `activePhaseId` every 0.5 s; no Combine bridge is required. |

---

## 7. Data Model

```
Subject { id, name, displayName, enabled, fullScore }
Grade   { id, subject, score, rawScore?, ranking?, importance (1..5),
          image? (legacy), imageFileName?, date, examName, fullScore?,
          phaseId? }
MistakeNote { id, title, subject, originalQuestion, source, date,
              errorReason, wrongSolution, correctSolution,
              questionImages, reasonImages, wrongSolutionImages, correctSolutionImages,
              reviewState?, phaseId? }
Exam   { id, name, examDate, examEndDate?, importance, subject, examName,
          masteryDegree, timeSlot?,
          checklist: [ExamChecklistItem],
          locationSchool, locationClassroom, locationSeat,
          countdownNotifyDays: [Int]?,
          examReview: ExamReview?,
          phaseId? }
comprehensiveExam { id, name, examDate, examEndDate?, importance,
                     subject: [String], examName, masteryDegree, timeSlot?, phaseId? }
ExamChecklistItem { id, title, isChecked, sortOrder }
ExamReview { id, ..., free-form reflection / follow-up }
ExamTimeSlot { startTime, endTime }
TaskItem { id, title, type: TaskType, dueDate, reminderDate, subject,
           importance (1..5), notes, isCompleted,
           reminderEventId?, reminderCalendarId?, createdAt, phaseId? }
TaskType { homework | reading }
TodoEntry { id, kind: TodoEntryKind, title, subject, date, endDate?,
            importance, isCompleted, exam?, comprehensiveExam?, taskItem? }
TodoEntryKind { exam | comprehensiveExam | homework | reading }
UserProfile { username, realName, age, gender, schoolName, grade, className,
              studentId, enrollmentYear, examYear,
              educationStage, regionCode, theme, avatarFileName,
              targetSchool, targetScore, selectedSubjects,
              // legacy: educationLevel, educationSystem, region }
AppPreferences { appLanguage?, colorScheme, chartType,
                 accentPaletteId?, glassEffectEnabled, learningHeatmapOnTrends,
                 activePhaseId? }
HomeLayoutPreference { items: [HomeCardItem] }
HomeCardItem { type: HomeCardType, enabled: Bool, isFullWidth: Bool }
HomeCardType { hrvStatus | unregisteredExamsReminder | quickActions
             | studySuggestions | trendChart | upcomingExams
             | dailyQuote | recentGrades
             | streakProgress | learningHeatmap }
StudyPhase { id, name, startDate, endDate, isArchived, archivedAt?,
             goals: [PhaseGoal], createdAt }
PhaseGoal { id, subject, targetScore, notes }
```

Persistence:

| What                      | Where                                           |
|---------------------------|-------------------------------------------------|
| Business data (grade / exam / mistake / profile / subjects / tasks / phases) | SwiftData entities in the on-disk SQLite store |
| Grade images              | `~/Documents/images/grade_{uuid}.jpg`           |
| Avatar                    | `~/Documents/images/avatar_{uuid}.jpg`          |
| Custom background image   | `Application Support/Backgrounds/bg_{uuid}.jpg` |
| Health history            | `~/Documents/health_history.json`               |
| Study sessions            | `~/Documents/study_sessions.json`               |
| Achievements snapshot     | `~/Documents/achievements.json`                 |
| App preferences           | `UserDefaults` key `appPreferences`             |
| Home layout               | `UserDefaults` key `homeLayoutPreference`       |
| HRV feature flags         | `UserDefaults` keys `hrv_enabled`, `hrv_onboarding_completed`, `hrv_detail_level` |
| Widget exam snapshot      | App Group `group.com.chenkai.gao.studypulse` → `widgetUpcomingExams` |
| Widget trend snapshot     | App Group `group.com.chenkai.gao.studypulse` → `TrendWidgetData` |
| Widget HRV snapshot       | App Group `group.com.chenkai.gao.studypulse` → `HRVWidgetData` |

---

## 8. Permissions

| Key                              | Value                              |
|----------------------------------|------------------------------------|
| `NSCameraUsageDescription`       | "Take photos of mistakes"          |
| `NSPhotoLibraryUsageDescription` | "Select photos from photo library" (also used for the custom background image) |
| `NSCalendarsUsageDescription`    | "Add exams to calendar"            |
| `NSRemindersFullAccessUsageDescription` (iOS 17+) / `NSRemindersUsageDescription` (legacy) | "Add homework / reading tasks to the system Reminders app" |
| `NSHealthShareUsageDescription`  | "Read HRV data from Health"        |
| `NSSupportsLiveActivities`       | true (Info.plist)                  |
| `com.apple.developer.healthkit`  | true (entitlement)                 |
| `com.apple.security.application-groups` | true (entitlement, group `group.com.chenkai.gao.studypulse`) |

The app never writes to Health; it only reads. The app never writes to
the calendar's *other* calendars, only the one chosen by the user via
the EventKit picker. Homework and reading tasks write only to the
Reminders list chosen by EventKit (`defaultCalendarForNewReminders()`)
and never to other lists.

---

## 9. Architecture Snapshot

```
+-------------------------------+
|  StudyPulseApp  (@main)       |
|  - RepositoryContainer (7 Repos)|
|  - 3 @StateObject singletons  |
|  - .task { container.asyncInit }|
+-------------------------------+
                |
                v
+-------------------------------+
|  ContentView                  |
|  iPhone: TabView               |
|  iPad: NavigationSplitView     |
|  + IntentActionStore observer  |
+-------------------------------+
                |
                v
+-----------------------------------------------+
|  XxxView -> XxxViewModel -> RepositoryContainer|
|     |               |                |         |
|     |               |                v         |
|     |               |        7 Repositories   |
|     |               v        (Grade / Mistake  |
|     |       Services (pure)  / Exam / Task /   |
|     |       (SubjectAggregator / Phase /      |
|     |        ExamFilter / etc.)  Profile /    |
|     |                           Subject)     |
|     v                                         |
|  Components / Views (rendering)               v
|                                  SwiftData ModelContainer
+-----------------------------------------------+
       |              |
       v              v
+-------------+  +----------------------+
| AppEnvironment| HealthKitManager     |
| Manager       | AchievementManager   |
| (AppPreferences) (StudyTimerManager) |
+-------------+  +----------------------+
       |              |
       v              v
+-------------------------------+
|  DataFileIO  (nonisolated enum)|
|  ImageCache  (nonisolated)     |
|  WidgetDataSync* (App Group)   |
+-------------------------------+
       |
       v
+-------------------------------+
|  SwiftData SQLite store        |
|  ~/Documents/*.json (legacy)   |
|  ~/Documents/images/*.jpg      |
|  ~/Documents/health_history.json|
|  ~/Documents/study_sessions.json|
|  ~/Documents/achievements.json |
|  UserDefaults                  |
|  App Group UserDefaults        |
+-------------------------------+
```

See [AGENTS.md §4–6](../../AGENTS.md) for the full architecture guide.

---

## 10. Roadmap

### v1.0 (shipped)
Grade, mistake, exam, trend, settings, multi-language, iPad layout,
customisable Home, HRV readiness, CSV export, widget target wired up,
`StudyPulseWidgetExtension` with three static widgets + a Live
Activity for the study timer.

### v1.1 (shipped)
- Study Timer with `StudyTimerLiveActivity` (Lock Screen + Dynamic
  Island).
- Mistake PDF export (Core Text + `NSAttributedString`, A4, vector
  fonts, cover + TOC).
- Learning Report (image export via `ImageRenderer`).
- Flashcard SRS (SM-2) with `SRSReviewNotifications`.
- Onboarding profile form.
- Settings refactor (6-section navigation, 11 child views).
- Achievements & daily goals + 90-day contribution graph.
- Liquid Glass effect (iOS 26) + 11-preset accent colour + custom
  background image.
- Study phases (semester / break / sprint scoping).

### v1.2 (shipped)
- MVVM + Repository refactor.
- Exam pre-exam checklist + location + countdown notification
  configuration + exam review + share-with-family.
- 90-day learning heatmap (Home + Trends).
- Siri Shortcuts (six App Intents).
- 6-chart-type Trend (line / bar / pie / scatter / heatmap / histogram).
- SwiftData entity layer wired into the Xcode project (alongside
  the legacy JSON import path).

### v1.3 (next)
- CSV import via UI.
- Subject colour override per user.
- iCloud sync (CloudKit private database) for the SwiftData store
  (data only; images remain local for now).
- Charts colour-blind mode.

### v2.0 (longer term)
- Family Sharing (different students on the same device).
- macOS / Mac Catalyst first-class app (multi-window, menu bar).
- Real-time shared study sessions.
- Apple Pencil-first mistake editing.

---

## 11. Acceptance Criteria (current release)

A build is shippable when all of the following hold:

- [ ] `./scripts/build.sh release` produces a clean release archive.
- [ ] The app launches on iPhone 17 simulator and reaches Home within 1.5 s.
- [ ] The app launches on iPad Pro 11-inch simulator and shows a sidebar.
- [ ] Adding a grade, mistake, exam, and task each persist across a relaunch.
- [ ] HRV card stays hidden until the user finishes `HRVOnboardingView`.
- [ ] Home layout changes in `HomeLayoutSettingsView` persist across a relaunch.
- [ ] Switching language in Preferences to any of the five locales updates
      the UI on next launch.
- [ ] Score rate colours match §3.12 of [DESIGN.md](DESIGN.md) at 90 / 75 / 60 %.
- [ ] CSV export of grades / mistakes / exams opens cleanly in Numbers
      and Excel without quoting errors.
- [ ] No new `// TODO` or `print` left in `Managers/` or `Models/`.
- [ ] No `swiftc` / `xcodebuild` warnings in `release` build.
- [ ] All 100 % of `Localizable.strings` keys present in every locale.
- [ ] The 90-day learning heatmap shows correct intensity buckets and
      tap-detail sheet.
- [ ] The Study Phase selector switches the active phase across Home /
      Trends / Mistake / Todo / Exam; new entries inherit the active
      phase; deleting a phase clears its references.
- [ ] The Liquid Glass toggle visibly changes cards on iOS 26, and the
      custom background image shows through the main page roots.
- [ ] The six Siri Shortcut App Intents appear in the Shortcuts app and
      handoff to the main app successfully.

---

## 12. Open Questions

1. **Cloud sync.** CloudKit private database vs iCloud Drive JSON
   round-trip — needs product decision before v1.3.
2. **Subject colour override.** UX question: per-subject colour or per-
   subject palette? (Affects `SubjectInfo` model.)
3. **HRV detail level default.** Is `dataAndSuggestion` the right
   default, or should it be `suggestionOnly` to be less overwhelming?
4. **Daily quote copy.** Do we ship a built-in list (current behaviour)
   or pull from a remote source?
5. **Phase archive semantics.** Archived phases are filtered out of
   `filtered*` by default; do we need an "Include archived" toggle?

---

## 13. Glossary

- **HRV** — Heart Rate Variability. Here, specifically the SDNN
  (standard deviation of NN intervals) recorded by Apple Watch overnight.
- **Z-score** — `(today − mean) / stdDev`, where mean and stdDev are
  computed over the user's own recent days. Personalized, not a
  population reference.
- **Rate** — `score / fullScore` for the relevant subject. Score colours
  and chart Y-axes are rate-based, not absolute.
- **Comprehensive exam** — A single dated event covering several
  subjects (e.g. a mock Gaokao). Distinct from `Exam` which is single-
  subject.
- **Raw score** — Optional, used in scored-ranking systems (e.g. Zhejiang
  3+3) where the displayed score is a converted value.
- **Education stage** — `primarySchool` / `middleSchool` / `highSchool` /
  `internationalHighSchool` / `university` / `graduate`.
- **Region** — A specific education-system code within a stage (e.g.
  `CN-ZJ-3+3`, `IB-DP`, `US-SAT`).
- **Study Phase** — A user-defined time window (e.g. "2026 春季学期")
  that scopes grades / mistakes / exams / tasks so historical data
  stays bounded.
- **Phase Goal** — A per-phase target on a subject (e.g. "期末数学 ≥ 120").
- **MVVM + Repository** — The app's architectural pattern: views own
  view models; view models read from a `RepositoryContainer` that
  aggregates seven per-domain repositories; pure-function services
  in `Services/` are called by both view models and views.
