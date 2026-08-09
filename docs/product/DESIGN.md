# StudyPulse — Design Document

> Visual & interaction design reference for the **StudyPulse** iOS app.
> Authoritative source for the design system, theming, and platform-specific
> UX rules. For architecture and code structure, see [AGENTS.md](../../AGENTS.md).

---

## 1. Design Goals

1. **Calm by default.** StudyPulse is used between classes and during long
   study sessions; visual noise should be low. The default style is `minimal`.
2. **One-screen-at-a-time mental model.** Each tab owns one decision area
   (Home, Trends, Mistakes, Exams, Settings) and never bleeds content into
   another tab.
3. **Customizable without config fatigue.** All Home cards are visible by
   default; users only opt in to *hiding* cards, never to a layout editor.
4. **Native on iPad.** The app is not a stretched-out iPhone UI. iPad uses
   a real sidebar + multi-column layout.
5. **Numbers carry meaning.** Score colours and chart scales communicate
   performance at a glance, not just on tap.

---

## 2. Design System (`AppStyle`)

`Managers/AppStyle.swift` defines a single enum with three style variants.
The variant is a static, compile-time constant (not a user setting today)
that drives corner radii, spacing, background gradients, borders, and the
`isDark` flag for text colour resolution.

| Style        | Corner radius | Spacing | Border width | Background         | Mood              |
|--------------|---------------|---------|--------------|--------------------|-------------------|
| `minimal`    | 12 pt         | 16 pt   | 0 pt         | System grouped bg  | Quiet, default    |
| `literature` | 16 pt         | 20 pt   | 0 pt         | System grouped bg  | Soft, paper-like  |
| `tech`       | 10 pt         | 14 pt   | 1.5 pt       | Indigo→purple gradient | Neon dashboard |

Tokens driven by `AppStyle`:

```swift
cardCornerRadius        // 12 | 16 | 10
cardBorderWidth         // 0  | 0  | 1.5
sectionSpacing          // 16 | 20 | 14
buttonCornerRadius      // 12 | 16 | 10
statCardCornerRadius    // 10 | 14 | 8
isDark                  // false | false | true
```

Helper views in the same file (`accentButtonBackground`, `cardBorder`,
`neonBorder`, `statCardBorder`, `cyanBorder`) collapse "if isDark, render
a neon stroke, else render an invisible clear stroke" into a single call
site. Feature views should not branch on style — they call these helpers.

---

## 3. Colour Palette

### 3.1 System palette (default, light + dark)
Driven by `UIColor` semantic colours via `ColorExtensions.swift`:

- `systemBackground`, `secondarySystemGroupedBackground`
- `.secondary`, `.tertiaryLabel`
- `Color.accentColor` (tint comes from `Assets.xcassets/AccentColor`)

### 3.2 Tech-style palette
Hard-coded `Color(red:green:blue:)` values; intentionally not theme-aware
because the tech style IS the theme.

| Token                | RGB                       | Used for            |
|----------------------|---------------------------|---------------------|
| Deep indigo          | `(0.05, 0.05, 0.15)`      | Root background start |
| Deep violet          | `(0.10, 0.05, 0.20)`      | Root background mid  |
| Indigo blue          | `(0.05, 0.08, 0.18)`      | Root background end  |
| Card gradient A      | `(0.08, 0.06, 0.20)`      | Card surface         |
| Card gradient B      | `(0.12, 0.06, 0.25)`      | Card surface         |
| Stat gradient A      | `(0.10, 0.06, 0.22)`      | Stat card surface    |
| Stat gradient B      | `(0.08, 0.05, 0.18)`      | Stat card surface    |
| Quote gradient A     | `(0.08, 0.04, 0.20)`      | Daily quote surface  |
| Quote gradient B     | `(0.15, 0.05, 0.25)`      | Daily quote surface  |
| Exam gradient A      | `(0.06, 0.04, 0.15)`      | Exam card surface    |
| Exam gradient B      | `(0.10, 0.05, 0.20)`      | Exam card surface    |

Accent gradients (tech only):
- **Accent button**: `Color.cyan → Color.purple` (horizontal)
- **Card border**: `Color.cyan.opacity(0.5) → Color.purple.opacity(0.5)`
- **Neon border**: `Color.cyan.opacity(0.3) → Color.purple.opacity(0.3)`
- **Stat border**: `Color.cyan.opacity(0.25)` 1 pt
- **Cyan border**: `Color.cyan.opacity(0.2)` 0.5 pt

### 3.3 Score colour mapping (`ScoreColor.swift`)
Proportional to `score / fullScore` — **not** absolute:

| Score rate | Colour    | Rationale                       |
|------------|-----------|---------------------------------|
| ≥ 90 %     | `.green`  | Comfortable mastery             |
| ≥ 75 %     | `.blue`   | On track                        |
| ≥ 60 %     | `.orange` | Needs attention                 |
| < 60 %     | `.red`    | At risk, show in attention list |

These thresholds apply across all education systems. They are *rate*
thresholds so they stay meaningful for IB (7 pts), SAT (800 pts), and
domestic 150-pt exams alike.

---

## 4. Typography

We rely on SwiftUI text styles, never raw point sizes. Mapping:

| Role               | Style          | Notes                              |
|--------------------|----------------|------------------------------------|
| Greeting           | `.largeTitle`  | Bold weight on Home                |
| Section title      | `.headline`    | Bold, used in card headers         |
| Body               | `.body`        | Standard content                    |
| Subhead            | `.subheadline` | List rows, card metadata            |
| Caption            | `.caption`     | Hints, timestamps, unit labels      |
| Stat number        | `.system(size:weight:)` | Override only for hero numbers; e.g. `.system(size: 28, weight: .bold, design: .rounded)` for the four main stats |

All copy goes through `"…".localized()` — never ship an inline string.

---

## 5. Spacing & Layout

| Token            | Value | Use                                |
|------------------|-------|------------------------------------|
| `sectionSpacing` | 14–20 pt (per style) | Between cards on Home / Trends |
| Card padding     | 16 pt  | Internal padding inside cards      |
| Inter-card gap   | 16 pt  | `LazyVGrid` spacing on iPad        |
| Screen edge      | 20 pt iPhone, 24 pt iPad (regular width) | Outer page padding  |
| Max content width | per view (640 / 720 / 800 / 900 / 1100) | Centered on iPad  |

iPhone is always full-bleed. iPad always applies `adaptiveMaxWidth(_:)` and
`adaptiveCardPadding()`. Feature views must not duplicate these rules.

---

## 6. Iconography

- **SF Symbols** for all in-app icons. No raster icons inside SwiftUI.
- Style names mapped to symbols:
  - `AppTab.home` → `house.fill`
  - `AppTab.trends` → `chart.bar.fill`
  - `AppTab.mistake` → `exclamationmark.triangle.fill`
  - `AppTab.todo` → `checklist` (renamed from `AppTab.exam` / `list.bullet.clipboard`; the page now unifies exams, homework, and reading)
  - `AppTab.settings` → `gearshape.fill`
  - `HomeCardType.hrvStatus` → `heart.text.square`
  - `HomeCardType.unregisteredExamsReminder` → `exclamationmark.bubble.fill`
  - `HomeCardType.quickActions` → `bolt.fill`
  - `HomeCardType.studySuggestions` → `lightbulb.fill`
  - `HomeCardType.trendChart` → `chart.line.uptrend.xyaxis`
  - `HomeCardType.upcomingExams` → `calendar.badge.exclamationmark`
  - `HomeCardType.dailyQuote` → `quote.bubble.fill`
  - `HomeCardType.recentGrades` → `list.bullet.rectangle`
- **App icon** lives in `Assets.xcassets/StudyPulseIcon` (custom SVG + icon
  dataset). Accent color is `Assets.xcassets/AccentColor.colorset`.
- **Widget icon** (when target is added) will share the same asset.

---

## 7. Navigation

### 7.1 Top-level
- **iPhone** uses `TabView` (5 tabs). Tab order is fixed:
  Home → Trends → Mistakes → Exams → Settings.
- **iPad** uses `NavigationSplitView` with the same five destinations
  rendered in a `List(selection:)`. The sidebar column is clamped to
  220–280 pt to leave room for detail.

Switching happens on `horizontalSizeClass == .regular` inside `ContentView`.
Both layouts share the same `AppTab` enum.

### 7.2 In-tab
Each tab uses `NavigationStack` rooted in its top-level view. Sub-flows:

- **Home** → sheets: `AddGradeView`, `NewExamSetView`, `NewMistakeSetView`,
  `HRVOnboardingView`, `HomeLayoutSettingsView`. Tap on an exam card →
  `ExamDetailView`. Tap on an unregistered-exam reminder → `AddGradeView`.
- **Trends** → per-subject detail; no further drill-down today.
- **Mistakes** → `MistakeDetailEditView` (4 sections + OCR + markdown).
- **Exams** → `ExamDetailView` → `ExamDetailEditView`. Comprehensive exams
  share the same detail/edit pair.
- **Settings** → sub-screens for profile edit, subjects, preferences, HRV
  onboarding, academic info, data admin, about, copyright.

### 7.3 Keyboard
Hardware keyboard is supported on iPad / Mac Catalyst:
- `Tab` cycles to the next tab.
- `1`–`5` jump directly to a tab.
- A medium `UIImpactFeedbackGenerator` fires on tab change.

### 7.4 Haptics
Single medium impact on tab change, fired off the main run loop to keep
the gesture responsive (`DispatchQueue.main.asyncAfter(deadline: .now() + 0.05)`).

---

## 8. Home Dashboard

The Home tab is the only place in the app with a non-fixed layout. The
order and visibility of its cards come from `HomeLayoutPreference`
(UserDefaults-persisted).

### 8.1 Default card order
1. **HRV Readiness** — `HRVStatusCard`
2. **Exam Grade Reminder** — `UnregisteredExamsReminderCard` (3–7 day
   window after an exam with no grade; auto-hides if no matches)
3. **Quick Actions** — `QuickActionsCard`
4. **Study Suggestions** — `StudySuggestionsCard`
5. **Trend Chart** — `ChartSectionView` (auto-hides when no recent grades)
6. **Upcoming Exams** — `UpcomingExamsSection` (auto-hides when empty)
7. **Daily Quote** — `DailyQuoteCard` (date-of-year rotation)
8. **Recent Grades** — `RecentGradesSection` (auto-hides when empty)

### 8.2 Layout rules
- iPhone: single-column `VStack`.
- iPad: 2-column `LazyVGrid` with 16 pt spacing.
- `HomeLayoutSettingsView` provides drag-to-reorder and toggle switches;
  empty toggles hide the card on next render.
- `mergeWithDefault` keeps the user's choices when a new card type is
  added in a future version.

### 8.3 HRV card detail levels
User-controllable via `HRVDetailLevel` (UserDefaults `hrv_detail_level`):

| Level               | Renders                                      |
|---------------------|----------------------------------------------|
| `suggestionOnly`    | Title + suggestion string                    |
| `dataAndSuggestion` | + Z-score, today's HRV, baseline mean, n     |
| `chartAndData`      | + 14-day HRV trend chart (`Charts` framework)|

The card is hidden entirely until `hrvEnabled && hrvOnboardingCompleted`.

---

## 9. Forms & Sheets

- Forms use `Form { Section { ... } }` with grouped section styling.
- All sheets use the system default modal presentation; nothing custom
  is layered on top.
- Date pickers use `.date` style; ratings use a 5-star `Image(systemName:)`
  HStack bound to `Int` (clamped 1–5).
- Multi-line text uses `TextEditor`; markdown preview uses
  `MarkdownUI` (`swift-markdown-ui`) inside a `TabView` switch
  (Edit / Preview) inside `MistakeDetailEditView`.

### 9.1 Image capture / selection
- `PhotoCaptureView` (camera) — full-screen `UIViewControllerRepresentable`.
- `ImagePicker` (photo library) — `PHPickerViewController` wrapper.
- `ZoomableImageView` for full-screen pinch + double-tap.

All bytes go through `DataManager.saveGradeImage` / `saveAvatar` and are
never re-inlined into JSON.

---

## 10. Charts

Built on the `Charts` framework (`import Charts`). Three reusable patterns:

| Component                | Used in                | Encodes                     |
|--------------------------|------------------------|-----------------------------|
| `GradeChartView`         | `TrendsView`           | Score rate over time        |
| `ChartSectionView`       | `HomeView`             | Subject trend w/ strategy   |
| HRV line in `HRVStatusCard` | Home HRV card (level 3) | Daily HRV (ms)            |

Conventions:
- X axis is time, always chronological (oldest left → newest right).
- Y axis on score charts is *rate*, not raw points.
- Mark lines at 60 % (orange) and 90 % (green) when scale allows.

---

## 11. Theme / Appearance

`AppEnvironmentManager.preferences.colorScheme` is the single source of
truth. Three values:

- `.system` (default) — follows OS setting
- `.light`
- `.dark`

`AppStyle.tech` is a **separate, manual** visual variant and is **not**
the same as iOS Dark Mode. A `tech` build is dark regardless of system
theme. (A future task may unify these — see [SPEC.md §10](SPEC.md).)

---

## 12. Localisation & Typography by Language

- `Localizable.strings` in `en`, `zh-Hans`, `zh-Hant`, `ja`, `ko`.
- All user-facing strings via `"…".localized()`.
- Chinese / Japanese / Korean copy uses system fonts (`.body` etc.);
  the app does not pin a custom font, so platform font fallback works.
- Date formatting: `DateExtensions` (`yyyy-MM-dd` for CSV, `EEEE, MMM d`
  for headers, etc.).

---

## 13. Accessibility

- Minimum tap target 44 × 44 pt (all cards and buttons use `Spacer` and
  `padding(.vertical, …)` to stay above this).
- `Image(systemName:)` icons paired with `Label { Text }` so VoiceOver
  reads both.
- Charts should expose accessibility labels in future iterations
  (current: trailing status badge with the rate as text).
- Dynamic Type: all text uses SwiftUI text styles; nothing uses a fixed
  point size that wouldn't scale.
- Light / Dark / Follow System respected in `minimal` and `literature`
  styles; `tech` always renders dark.

---

## 14. Empty States

Every list view must handle the empty case explicitly. Patterns:

| View                  | Empty state                                      |
|-----------------------|--------------------------------------------------|
| `HomeView` recent grades | Card hidden entirely                          |
| `HomeView` upcoming exams | Card hidden entirely                          |
| `HomeView` unregistered exams | Card hidden entirely                     |
| `TrendsView`          | "No data yet" message with CTA                   |
| `MistakeView`         | "No mistakes recorded" + add CTA                 |
| `ExamView`            | "No exams scheduled" + add CTA                   |
| `SettingsView` data admin | Sub-screen with empty placeholder            |

Home cards prefer **hiding** over showing empty placeholders, because
the Home tab is dashboard-shaped. Other tabs prefer **a short message
plus a primary CTA**, because the user is actively seeking that list.

---

## 15. Performance UX

- All `~/Documents` JSON loads happen off the main thread
  (`DataManager.asyncInit`); the app shows a skeleton Home immediately
  and re-renders when `@Published` updates.
- Image thumbnails are 300 px max dimension, cached in NSCache (max 50),
  served from `nonisolated ImageCache` so any thread can read.
- Calendar icons, exam countdowns, and HRV charts use computed
  properties instead of `@State` + `onAppear` to avoid spurious
  re-renders.

---

## 16. Anti-Patterns (do not introduce)

- ❌ Custom bottom-tab bar on iPhone. Always use `TabView`.
- ❌ Hard-coded `Color.white` / `Color.black` outside `AppStyle`.
- ❌ Inline English strings — always go through `localized()`.
- ❌ `if sizeClass == .regular` branches in feature views — use the
  `iPadLayout` helpers instead.
- ❌ Putting image `Data` inside Codable models — use file-based
  storage and `imageFileName`.
- ❌ Re-fetching HealthKit on every view body — call `refreshReadiness()`
  only on app launch, manual pull-to-refresh, or when the user toggles
  the feature on.

---

## 17. Open Design Questions

1. Should the `tech` style be moved from a build-time constant to a
   user-selectable setting in Preferences?
2. Should we add a 3rd icon style per `HomeCardType` (e.g. for
   `literature`)?
3. Should the Home dashboard on iPad get a 3-column grid for very wide
   layouts (≥ 1200 pt)?
4. Should we expose chart colour palette to the user (colour-blind
   friendly mode)?
