# 学习连续剧 & 成就系统 — 实施方案

> 状态：草案 v1
> 目的：在 StudyPulse 现有基础设施上叠加「每日目标 / 连续打卡 / 里程碑徽章」三层激励，让学习进度可见、可量化、可积累。

---

## 1. 背景与目标

学生打开 StudyPulse 时，期望看到的是「我今天还要做什么 / 我坚持了多久 / 我拿到了哪些成就」。但目前：
- `StudyTimerManager`、`Flashcard/SRS`、`Grade` 三条线各自孤立，没有统一的"日活跃"概念。
- 用户录入数据后，没有任何即时反馈告诉 ta「这一步算进了今天的进度」。
- 没有"连续打卡"这种轻度游戏化抓手。

**目标**：把分散的事件源统一成一条「每日进度 → 连续天数 → 徽章」的激励链条。轻量、不打扰，但要"看得见"。

---

## 2. 已锁定的方向（用户已确认）

| 决策 | 选择 | 备注 |
|---|---|---|
| 入口位置 | **主页卡片 + 设置独立页** | TabView 保持 5 个不动；主页新增 `StreakHomeCard`，设置里新增 `AchievementsView` 与 `DailyGoalsConfigView` |
| 连续判定 | **中等：满足任一目标** | 三个目标（复习 / 成绩 / 专注）任一达成即视为当日活跃 |
| 晚间提醒 | **做，简单版** | 每天 20:00 检查；未完成今日任一目标则发一条本地通知；设置可关 |
| 历史回填 | **做** | 首次启动时从 `grades.json` 与 `study_sessions.json` 反推过去 30 天的活动日志 |

---

## 3. 关键架构判断

> **核心思路**：不重新搭一套并行系统，而是**编排现有原语**。

仓库里已有的、可以直接驱动这套系统的东西：

| 已有原语 | 位置 | 这次怎么用 |
|---|---|---|
| `StudyTimerManager` + `StudySessionStore` | `Managers/StudyTimerManager.swift`, `Models/StudySession.swift` | 监听 `sessions.append`（已完成的）→ 累加今日专注分钟 |
| `MistakeNote.reviewState` + `FlashcardStudyView` | `Views/Flashcard/` | 在 flashcard 会话结束时调 `recordMistakeReviewed(count:)` |
| `Grade` + `DataManager.saveGrade` | `Managers/DataManager.swift`, `Models/DataModels.swift` | 保存后调 `recordGradeRecorded()` |
| `DailyHealthSnapshot` + `HealthHistoryStore` | `Models/HealthHistory.swift`, `Managers/HealthHistoryStore.swift` | **持久化模式的最近模板**：JSON 文件 + NSLock + 回填逻辑 |
| `HomeLayoutPreference` + `HomeCardType` | `Models/HomeLayoutPreference.swift` | 新增 `case streakProgress`，沿用现有渲染管线 |
| `SRSReviewNotifications` + `ExamPrepareNotifications` | `Managers/NotificationsControl/` | 复用调度风格，新增 `DailyGoalReminder` |

设计原则：
- **单一写入路径**：所有"事件"都通过 `AchievementManager.record*()` 入口，避免在多个 Manager 里各自维护状态。
- **当日数据派生**：不持久化"当日累计"，每次 `record*()` 时按 `Calendar.current.startOfDay` 命中 `DailyActivityLog` 累加；日期滚动时新建条目。
- **跨进程无关**：achievement 系统只关心主应用内的事件，Widget 端只读快照（v1 不做 widget）。

---

## 4. 数据模型

### 4.1 新增 `Models/Achievements.swift`

```swift
// MARK: - 用户每日目标配置
nonisolated struct DailyGoalConfig: Codable, Equatable {
    var mistakeReviewTarget: Int      // 默认 5
    var gradeRecordTarget: Int        // 默认 1
    var focusMinutesTarget: Int       // 默认 25
    var reminderEnabled: Bool         // 默认 true
    var reminderHour: Int             // 默认 20
    var reminderMinute: Int           // 默认 0

    static let `default` = DailyGoalConfig(
        mistakeReviewTarget: 5,
        gradeRecordTarget: 1,
        focusMinutesTarget: 25,
        reminderEnabled: true,
        reminderHour: 20,
        reminderMinute: 0
    )

    /// 任一目标达成 = 当日活跃
    func isActiveDay(_ log: DailyActivityLog) -> Bool {
        log.mistakeReviews >= mistakeReviewTarget
        || log.gradesRecorded >= gradeRecordTarget
        || log.focusMinutes >= focusMinutesTarget
    }
}

// MARK: - 单日活动日志
nonisolated struct DailyActivityLog: Codable, Equatable, Identifiable {
    var date: Date                       // startOfDay 本地时区
    var mistakeReviews: Int = 0
    var gradesRecorded: Int = 0
    var focusMinutes: Int = 0

    var id: Date { date }
}

// MARK: - 连续状态
nonisolated struct StreakState: Codable, Equatable {
    var current: Int = 0
    var longest: Int = 0
    var lastActiveDate: Date?       // 上一次"达标"的日子（startOfDay）
    var totalActiveDays: Int = 0
}

// MARK: - 徽章定义（catalog，编译期常量）
nonisolated struct AchievementDefinition: Identifiable, Equatable {
    let id: String
    let titleKey: String           // 本地化 key
    let descriptionKey: String
    let icon: String               // SF Symbol
    let tier: Tier
    let criteria: Criteria         // 用于增量检查

    enum Tier: String, Codable {
        case onboarding, streak, volume, mastery, special
    }

    enum Criteria: Equatable {
        case totalActiveDays(Int)               // 累计活跃 N 天
        case currentStreak(Int)                 // 连续 N 天
        case mistakeReviewsTotal(Int)           // 累计复习 N 道
        case gradesRecordedTotal(Int)           // 累计记录 N 个成绩
        case focusMinutesTotal(Int)             // 累计专注 N 分钟
        case firstActivity                      // 任意一项 ≥1
        case goalConfigured                     // 用户改过 daily goal
    }
}

// MARK: - 单个徽章进度
nonisolated struct AchievementProgress: Codable, Equatable, Identifiable {
    var id: String { definition.id }
    var definitionId: String
    var currentValue: Int = 0          // 用于显示"5 / 7"
    var unlockedAt: Date?              // nil = 未解锁
    var isNewlyUnlocked: Bool = false  // 用于展示解锁 toast，重启后置 false

    var definition: AchievementDefinition {
        AchievementCatalog.all.first(where: { $0.id == definitionId })!
    }

    var isUnlocked: Bool { unlockedAt != nil }
}

// MARK: - 总快照（单文件持久化）
nonisolated struct AchievementsSnapshot: Codable, Equatable {
    var version: Int = 1
    var config: DailyGoalConfig
    var logs: [DailyActivityLog]            // 至少 90 天滚动窗口
    var streak: StreakState
    var achievements: [AchievementProgress] // 与 catalog 一一对应

    static let empty = AchievementsSnapshot(
        config: .default,
        logs: [],
        streak: StreakState(),
        achievements: AchievementCatalog.all.map {
            AchievementProgress(definitionId: $0.id)
        }
    )
}
```

### 4.2 新增 `Models/AchievementCatalog.swift`

```swift
/// 编译期常量目录。所有 i18n 文案走 .localized()，不内联英文。
enum AchievementCatalog {
    static let all: [AchievementDefinition] = [
        // Tier 1 — onboarding
        .init(id: "first_step", ..., criteria: .firstActivity),
        .init(id: "goal_setter", ..., criteria: .goalConfigured),

        // Tier 2 — streak
        .init(id: "streak_3",   ..., criteria: .currentStreak(3)),
        .init(id: "streak_7",   ..., criteria: .currentStreak(7)),
        .init(id: "streak_14",  ..., criteria: .currentStreak(14)),
        .init(id: "streak_30",  ..., criteria: .currentStreak(30)),
        .init(id: "streak_100", ..., criteria: .currentStreak(100)),
        .init(id: "streak_365", ..., criteria: .currentStreak(365)),

        // Tier 3 — volume
        .init(id: "reviews_10",   ..., criteria: .mistakeReviewsTotal(10)),
        .init(id: "reviews_50",   ..., criteria: .mistakeReviewsTotal(50)),
        .init(id: "reviews_200",  ..., criteria: .mistakeReviewsTotal(200)),
        .init(id: "reviews_1000", ..., criteria: .mistakeReviewsTotal(1000)),
        .init(id: "grades_10",    ..., criteria: .gradesRecordedTotal(10)),
        .init(id: "grades_50",    ..., criteria: .gradesRecordedTotal(50)),
        .init(id: "grades_200",   ..., criteria: .gradesRecordedTotal(200)),
        .init(id: "focus_100",    ..., criteria: .focusMinutesTotal(100)),     // ~2 sessions
        .init(id: "focus_600",    ..., criteria: .focusMinutesTotal(600)),    // 10h
        .init(id: "focus_3000",   ..., criteria: .focusMinutesTotal(3000)),   // 50h

        // Tier 5 — special (MVP 不做 subject-specific / 时段类，先留位置)
        // ...
    ]
}
```

> **v1 不做 subject-specific 与时段类成就**（`subject_streak_7` / `early_bird` / `night_owl`）。原因：subject-specific 需要把 review/grade 按 subject 聚合，schema 多一层；时段类需要事件时间戳数据，目前 `StudySession` 与 `FlashcardSession` 都有，但 v1 先保持简单。

---

## 5. AchievementManager

新增 `Managers/AchievementManager.swift`：

```swift
@MainActor
final class AchievementManager: ObservableObject {
    static let shared = AchievementManager()

    @Published var snapshot: AchievementsSnapshot = .empty
    @Published var todayLog: DailyActivityLog
    @Published var currentStreak: Int = 0
    @Published var newlyUnlocked: [AchievementProgress] = []   // 用于 toast 队列

    private init() {
        let today = Calendar.current.startOfDay(for: Date())
        self.todayLog = DailyActivityLog(date: today)
    }

    // MARK: - Lifecycle
    func bootstrap()                       // StudyPulseApp .task 中 dataManager.isReady 后调用
    func handleDayRolloverIfNeeded()       // 监听 scenePhase .active 时调用

    // MARK: - Event sinks（所有事件统一入口）
    func recordGradeRecorded()
    func recordMistakeReviewed(count: Int = 1)
    func recordFocusMinutes(_ minutes: Int)
    func updateConfig(_ config: DailyGoalConfig)

    // MARK: - Computed
    var todayProgress: TodayGoalProgress   // 给 HomeCard 用
    var streakState: StreakState           // 给 HomeCard 用
    var recentAchievements: [AchievementProgress]   // 给 AchievementsView 用
}
```

### 5.1 事件接入点

| 事件 | 接入位置 | 调用 |
|---|---|---|
| 录入成绩 | `DataManager.saveGrade()` 末尾（仅新增路径，不动编辑） | `AchievementManager.shared.recordGradeRecorded()` |
| 完成 flashcard 会话 | `FlashcardSessionSummaryView` 出现时 | `recordMistakeReviewed(count: reviewedCount)` |
| 完成专注会话 | `StudyTimerManager.complete()` 末尾 | `recordFocusMinutes(totalSeconds / 60)` |
| 用户调整目标 | `DailyGoalsConfigView` 保存 | `updateConfig(...)` |

注意：
- `DataManager.saveGrade` 既有新增也有编辑。**只对新增计数**——通过对比变更前后 `grades.count` 或在调用点明确区分。
- `StudyTimerManager.complete()` 调用 `StudySessionStore.append`；AchieveManager 监听同一个 append 也可以，但更稳的做法是直接在 `complete()` 里调一行 `recordFocusMinutes`。

### 5.2 持久化与回填

`AchievementStore`（仿 `HealthHistoryStore`）：

- 文件：`~/Documents/achievements.json`
- 写入：每次事件后 `save()`，加 NSLock（参考 `HealthHistoryStore`）
- 读取：`bootstrap()` 时一次性加载；加载失败 → `.empty`
- 滚动窗口：`logs` 保留 ≥ 90 天；`save()` 时按 `date >= today - 90d` 过滤

**回填逻辑**（仅在 `snapshot.logs.isEmpty && snapshot.streak.totalActiveDays == 0` 时触发，避免重复回填）：

```swift
private func backfillFromHistory() {
    // 1. 拉过去 30 天的 study sessions
    let sessions = StudySessionStore.load()
        .filter { $0.completed && $0.startDate >= thirtyDaysAgo }

    // 2. 拉过去 30 天的 grades
    let grades = DataManager.shared.grades
        .filter { $0.date >= thirtyDaysAgo }

    // 3. 按 startOfDay 聚合
    var logsByDay: [Date: DailyActivityLog] = [:]
    for s in sessions {
        let day = Calendar.current.startOfDay(for: s.startDate)
        logsByDay[day, default: DailyActivityLog(date: day)].focusMinutes
            += s.durationSeconds / 60
    }
    for g in grades {
        let day = Calendar.current.startOfDay(for: g.date)
        logsByDay[day, default: DailyActivityLog(date: day)].gradesRecorded += 1
    }
    // 注：mistakeReviews 没有等价历史数据，v1 回填时该字段为 0

    // 4. 倒序遍历，每天检查 isActiveDay，更新 streak
    let config = snapshot.config
    var streak = StreakState()
    for day in logsByDay.keys.sorted().reversed() {
        if config.isActiveDay(logsByDay[day]!) {
            streak.current += 1
            streak.longest = max(streak.longest, streak.current)
            streak.totalActiveDays += 1
            streak.lastActiveDate = day
        } else {
            break   // 不连续
        }
    }

    snapshot.logs = Array(logsByDay.values).sorted { $0.date < $1.date }
    snapshot.streak = streak
    snapshot.achievements = AchievementCatalog.all.map { def in
        AchievementProgress(
            definitionId: def.id,
            currentValue: computeCurrentValue(def, from: logsByDay.values),
            unlockedAt: def.criteria.evaluate(snapshot) ? Date() : nil
        )
    }
    save()
}
```

> **设计要点**：回填不能伪造 `mistakeReviews` 历史（仓库里 flashcard session 历史未持久化），所以成就里的 `reviews_10/50/...` 在首次启动时可能直接满足也可能不满足——不强求。

### 5.3 日期滚动处理

`scenePhase == .active` 时调用 `handleDayRolloverIfNeeded()`：
- 若 `todayLog.date` 不是今日 → 把 `todayLog` 推入 `logs`，重置 `todayLog = DailyActivityLog(date: today)`
- 用昨日 `todayLog` 检查 `config.isActiveDay(yesterday)`：是 → streak.current++；否 → streak.current = 0
- 重新跑一遍成就检查

---

## 6. UI 表面

### 6.1 主页新增卡片：`StreakHomeCard`

位置：`Views/Components/StreakHomeCard.swift`，注册到 `HomeLayoutPreference`：

```swift
// Models/HomeLayoutPreference.swift
enum HomeCardType {
    ...
    case streakProgress = "streakProgress"
}

// 默认顺序：放在 studyTimer 之后
HomeCardItem(type: .streakProgress, enabled: true)
```

视图结构（iPhone 单列；iPad 进 `dynamicCards` 的 LazyVGrid）：

```
┌──────────────────────────────────────────┐
│ 🔥 7-day streak          Longest 12      │
│ ███████████████░░░░░░  3/3 goals today   │
│ • 复习 5/5    • 成绩 1/1                 │
│ • 专注 28/25  ✓                         │
└──────────────────────────────────────────┘
```

- 三项目标用 SF Symbol + 进度数字；目标全部完成 → 整张卡换 `checkmark.seal.fill` 配色（绿）
- 进度条用 `Capsule` + `linearGradient`，参考 `HRVStatusCard` 的视觉语言
- 点击 → push `AchievementsView`
- 没有达成任何目标但有 progress：状态色灰；今日空白 → 显示一句鼓励语（取 `dailyQuotes` 风格）
- 长按 → 复用现有 `shareCardMenu` 链路（单卡分享走 `ReportRenderer`）

iPad：用现有 `dynamicCards` 网格，不做特殊布局。

### 6.2 设置页新增子页：`AchievementsView` & `DailyGoalsConfigView`

`Views/Settings/AchievementsView.swift`：
- 顶部：当前 streak + longest + total active days
- 中部：徽章墙，按 `tier` 分组（onboarding / streak / volume）
- 已解锁徽章：彩色 icon + 解锁日期
- 未解锁徽章：灰度 icon + `currentValue / target` 进度（"3 / 7 days"）

`Views/Settings/DailyGoalsConfigView.swift`：
- 三个 `Stepper`（或 Slider）：复习 / 成绩 / 专注
- `Toggle`：每日提醒
- `DatePicker`：提醒时间
- 保存 → `AchievementManager.shared.updateConfig(...)` → 触发成就 `goal_setter` 检查

### 6.3 解锁 toast

`Views/Components/AchievementUnlockToast.swift`：
- 监听 `AchievementManager.shared.$newlyUnlocked`
- 用 `.overlay` 挂到 `ContentView` 根（或 `StudyPulseApp` 的 WindowGroup 上）
- SwiftUI 动画：顶部滑入 + 弹簧 + 2.5s 后自动滑出；多枚徽章同时解锁 → 队列逐个展示
- 用户可点击立即关闭
- 同 `Log.record(.info, category: "Achievement", message: ...)` 写入 LogStore

### 6.4 设置入口

`Views/Settings/SettingsCategory.swift` 加一项：

```swift
enum SettingsCategory: String, CaseIterable, Identifiable {
    ...
    case achievements = "achievements"
}

// ProfileSettingsView 末尾或独立段：NavigationLink → AchievementsView
// AppearanceSettingsView 末尾：NavigationLink → DailyGoalsConfigView
```

> 放在 Profile 而不是独立段的理由：Profile 已经聚合了"个人化"的设置，目标配置天然属于这里。成就详情页虽然独立，但也放在 Profile 段下的入口里，不污染 NavigationSplitView 的侧栏层级。

---

## 7. 本地通知

新增 `Managers/NotificationsControl/DailyGoalReminder.swift`，仿 `SRSReviewNotifications`：

```swift
final class DailyGoalReminder {
    static let shared = DailyGoalReminder()
    private static let identifierPrefix = "DailyGoal_"

    /// 重建当天的提醒通知（每天首次进入前台时调）
    nonisolated func reschedule(for date: Date, config: DailyGoalConfig) {
        guard config.reminderEnabled else { return cancel() }
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        var comps = cal.dateComponents([.year, .month, .day], from: today)
        comps.hour = config.reminderHour
        comps.minute = config.reminderMinute
        guard let fireDate = cal.date(from: comps), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Daily Goals Reminder".localized()
        content.body = "Don't break your streak — finish one of today's goals.".localized()
        content.sound = .default
        content.userInfo = ["type": "dailyGoal"]

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(Self.identifierPrefix)\(today.timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    nonisolated func cancel() {
        // 清空所有 DailyGoal_ 前缀
    }
}
```

调用时机：
- `StudyPulseApp.scenePhase == .active` → 在 `dataManager.isReady` 分支里调 `DailyGoalReminder.shared.reschedule(for: Date(), config: AchievementManager.shared.snapshot.config)`
- 用户在 `DailyGoalsConfigView` 改配置后立即调一次
- `AchievementManager` 当日首次达成任一目标 → `cancel()`（避免无效打扰）

---

## 8. 本地化

需要新增的本地化 key（5 份 `Localizable.strings` 同步：en / zh-Hans / zh-Hant / ja / ko）：

```
// Home card
streak.card.title          = "🔥 %d-day streak" / "🔥 已连续 %d 天" / ...
streak.card.longest        = "Longest %d" / "历史最长 %d"
streak.card.goalsToday     = "%d/%d goals today" / "今日 %d/%d 目标"
streak.card.noActivity     = "Start your first session today" / ...

// Achievements
achievement.first_step.title       = "First Step"
achievement.first_step.description = "Record your first learning activity"
achievement.streak_3.title         = "3-Day Spark"
... (其余照 catalog 写)

// Config
goals.title           = "Daily Goals"
goals.review          = "Mistake Reviews"
goals.grade           = "Grades Recorded"
goals.focus           = "Focus Minutes"
goals.reminder        = "Daily Reminder"
goals.reminderTime    = "Reminder Time"

// Toast
toast.unlocked        = "Achievement Unlocked!"
```

实现方式：把 `AchievementDefinition.titleKey` 设计成 Localizable.strings 里的 key，view 渲染时统一走 `"achievement.\(id).title".localized()`。

---

## 9. 实施顺序

每个阶段都要 `./scripts/build.sh`（或 Xcode Cmd+B）通过再进入下一阶段。

| # | 阶段 | 涉及文件 | 验收 |
|---|---|---|---|
| 1 | 模型 + 持久化 | `Models/Achievements.swift`, `Models/AchievementCatalog.swift`, `Managers/AchievementStore.swift` | 单元测试：写入读取 round-trip；JSON 兼容旧 schema |
| 2 | AchievementManager 骨架 | `Managers/AchievementManager.swift` | bootstrap 不 crash；snapshot 是空的 |
| 3 | 事件接入 | `Managers/DataManager.swift`, `Managers/StudyTimerManager.swift`, `Views/Flashcard/FlashcardSessionSummaryView.swift` | 手动加 grade → todayLog.gradesRecorded+1；完成 timer → focusMinutes+1 |
| 4 | 回填逻辑 | `AchievementManager.backfillFromHistory()` | 删 achievements.json 重启 → 30 天活跃日被还原，streak 准确 |
| 5 | 日期滚动 | `handleDayRolloverIfNeeded()` | 修改设备时间 → 重新进入前台 → streak 正确更新 |
| 6 | StreakHomeCard | `Views/Components/StreakHomeCard.swift`, `Models/HomeLayoutPreference.swift`, `Views/HomeView.swift` | 主页能看到卡；3 目标全满时变绿 |
| 7 | AchievementsView + GoalsConfig | `Views/Settings/AchievementsView.swift`, `Views/Settings/DailyGoalsConfigView.swift`, `Views/Settings/SettingsCategory.swift`, `Views/Settings/ProfileSettingsView.swift` | 设置→Profile 能进入；配置保存后今日判定即时刷新 |
| 8 | 解锁 toast | `Views/Components/AchievementUnlockToast.swift`, `StudyPulseApp.swift` 或 `ContentView.swift` | 触发 `firstActivity` → 顶部滑入 toast |
| 9 | 晚间通知 | `Managers/NotificationsControl/DailyGoalReminder.swift`, `StudyPulseApp.swift` | 改设备时间到 19:58 → 等到 20:00 → 收到通知；当日达标后通知被取消 |
| 10 | 本地化 5 语言 | `en.lproj/`, `zh-Hans.lproj/`, `zh-Hant.lproj/`, `ja.lproj/`, `ko.lproj/` | 切换语言后文案正确；catalog 所有条目都有对应 key |
| 11 | 自检 | 全部手工验证 + `./scripts/build.sh` | 通过 |

预计人工：阶段 1-2 各半天，3-5 共一天，6-8 共一天半，9 半天，10-11 一天。**总计约 5 个工作日**。

---

## 10. 不在 v1 范围

明确延后到 v2 的项：

- **Streak freeze**（每周自动给 1 次"免疫卡"）：需要 UX 设计 + 状态机，先不做
- **Subject-specific 成就**（如 `subject_streak_7`）：schema 多一层（日志按 subject 拆分）
- **时段类成就**（`early_bird` / `night_owl`）：需要事件时间戳聚合，目前 session 有，但 v1 不暴露
- **XP / 等级系统**：连续剧 + 徽章已经够"游戏化"，再加一层容易稀释
- **Widget**：成就 widget 可放 v1.1；本期不动 `StudyPulseWidgetExtension`
- **分享卡片（带个人数据）**：当前 `ReportRenderer` 是月度报告，不适合成就墙；v1 只复用单卡分享
- **回填 mistakeReviews**：没有等价历史数据源（`MistakeNote` 没有 `lastReviewedAt` 字段），强行估算会失真

---

## 11. 风险与权衡

1. **写放大**：`record*()` 每次都会触发 `save()`。如果用户一次录入 50 个错题，会写 50 次 JSON。
   - 缓解：批量场景（flashcard session）走 `recordMistakeReviewed(count:)` 一次写一次；未来可加 `Task` debounce。
2. **时区变化**：用户跨国旅行，`Calendar.current` 时区会变，`startOfDay` 会跳。
   - 缓解：在 `handleDayRolloverIfNeeded()` 里比较日期；如果发生跨日，按新时区重算（容忍 1 天误差，不强求精确）。
3. **回填误判**：用户首次启动时如果 `grades` 已经 200 条，会立刻解锁 `grades_200`，导致首日"满屏 toast"。
   - 缓解：回填时把 `unlockedAt` 设为 `nil`，但 `currentValue` 直接给满；用一条一次性"Welcome" toast 一次性说明，而不是逐个 toast（v1.1）。
4. **DataManager 与 AchievementManager 循环依赖**：`DataManager.saveGrade` 调 AchievementManager，但 AchievementManager 在 `bootstrap` 阶段读 DataManager 数据。
   - 缓解：`bootstrap()` 只在 `dataManager.isReady == true` 之后调（沿用现有 HealthKit 模式）；事件路径不读 DataManager 状态。
5. **iPad 上的 StreakHomeCard**：放进 LazyVGrid 一格就行，不做特殊布局；如果发现 grid 里信息密度太大再做收紧。

---

## 12. 验收清单

完成 v1 的最低标准：

- [ ] 新用户首次启动 → 主页出现 Streak 卡，初始 streak = 0；触发 `first_step` 成就，顶部 toast 出现一次
- [ ] 录入一个 grade → 主页卡上"成绩 1/1"立即变绿；保存数据库
- [ ] 完成一个 25 分钟专注 → 主页"专注 25/25"变绿；streak.current = 1
- [ ] 修改设备时间到次日 → 重新进入前台 → streak.current 变为 2（前提昨日达标）
- [ ] 改回昨日时间 → 昨日未达标 → streak.current 归零
- [ ] 设置 → Profile → 看到成就墙 + 每日目标配置；改目标保存后立即生效
- [ ] 关闭每日提醒 → 20:00 不再发通知
- [ ] 切换 5 种语言 → 所有新文案正确显示
- [ ] `./scripts/build.sh` 通过；所有现有功能（HRV、闪卡、定时器、考试、CSV 导出、日志导出）不受影响
- [ ] 删 achievements.json 重启 → 过去 30 天的 grade/session 数据被回填为活跃日；streak 数字合理

---

## 13. 后续路径（v1.1+）

- `StreakWidget`：复用 `HRVWidget` 的模式，做一个 `StreakWidgetData` 写入 App Group
- `SubjectStreak` 类成就：把 `DailyActivityLog` 扩展为按 subject 聚合
- Streak freeze：一周一卡，用户长按 streak 数字手动"冻"一次
- "Welcome 成就墙"：首次启动时不刷屏，而是用单页 Welcome 介绍所有即将解锁的徽章
- 数据导出：成就进度作为 CSV 一并导出（用户备份场景）

---

## 14. 文件清单（实现时最终要新增/改动）

**新增（10 个）**

```
StudyPulse/Models/Achievements.swift
StudyPulse/Models/AchievementCatalog.swift
StudyPulse/Managers/AchievementManager.swift
StudyPulse/Managers/AchievementStore.swift
StudyPulse/Managers/NotificationsControl/DailyGoalReminder.swift
StudyPulse/Views/Components/StreakHomeCard.swift
StudyPulse/Views/Components/AchievementUnlockToast.swift
StudyPulse/Views/Settings/AchievementsView.swift
StudyPulse/Views/Settings/DailyGoalsConfigView.swift
STREAK_ACHIEVEMENT_PLAN.md (本文件)
```

**改动（≤10 个）**

```
StudyPulse/Models/HomeLayoutPreference.swift     # 新增 case streakProgress
StudyPulse/Views/HomeView.swift                  # 注册卡片到 dynamicCards + share 链路
StudyPulse/Views/ContentView.swift               # 挂 unlock toast overlay
StudyPulse/Views/Settings/SettingsCategory.swift # 新增 case achievements
StudyPulse/Views/Settings/ProfileSettingsView.swift  # 新增 NavigationLink
StudyPulse/Managers/DataManager.swift            # saveGrade 新增路径调 recordGradeRecorded
StudyPulse/Managers/StudyTimerManager.swift      # complete() 调 recordFocusMinutes
StudyPulse/Views/Flashcard/FlashcardSessionSummaryView.swift  # 调 recordMistakeReviewed
StudyPulse/StudyPulseApp.swift                   # bootstrap / scenePhase 接 AchievementManager
en.lproj/Localizable.strings + 4 份其他语言    # 新增文案 key
```

> 涉及 `project.pbxproj` 的改动只发生在新增文件——按 AGENTS.md 规则不手工编辑，让 Xcode Add Files 处理。