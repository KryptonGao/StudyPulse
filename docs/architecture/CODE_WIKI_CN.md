# StudyPulse — 代码维基（中文）

> StudyPulse iOS 应用的完整中文代码参考。本文件使用表格、ASCII 流程图与结构图说明各个模块。

---

## 目录

1. 快速开始
2. 架构概览
3. 仓库布局
4. 数据模型参考
5. 管理器参考
6. 视图参考
7. 主页卡片系统
8. 教育体系
9. HRV / HealthKit 子系统
10. 图像、OCR 与 CSV 管线
11. iPad 适配
12. 本地化
13. 隐私权限
14. 小组件扩展
15. 依赖（SPM）
16. 构建与运行
17. 编码规范
18. 性能说明
19. 已知问题 / 待办

---

## 1. 快速开始

### 1.1 前置要求

| 项目 | 要求 |
|---|---|
| macOS | 15.0 或更高 |
| Xcode | 26.x（推荐 26.3） |
| iOS 部署目标 | 18.6+ |
| Swift | 6.0 |
| 支持设备 | iPhone 与 iPad（`TARGETED_DEVICE_FAMILY = "1,2"`） |

### 1.2 快速开始步骤

```bash
# 1. 打开 Xcode 工程
open StudyPulse.xcodeproj

# 2. 解析 Swift 包
#    Xcode → File → Packages → Resolve Package Versions

# 3. Cmd+R 运行
```

命令行构建：

```bash
./scripts/build.sh              # Debug，iPhone 17 模拟器
./scripts/build.sh release      # Release
./scripts/build.sh clean        # 清理构建目录
./scripts/build.sh list         # 列出可用模拟器
```

### 1.3 核心概念

| 概念 | 说明 |
|---|---|
| 架构模式 | MVVM，通过 `@EnvironmentObject` 注入 DataManager |
| 持久化 | 业务模型以 JSON 存储在 `~/Documents/`；图片以文件存储在 `~/Documents/images/`；偏好设置写入 UserDefaults |
| 启动流程 | `StudyPulseApp` 在 `.task` 中调用 `dataManager.asyncInit()`，后台线程加载 JSON |
| 全球教育 | 预置 15+ 体系（中国大陆、浙江、上海、台湾、香港、新加坡、UK IGCSE/A-Level、IB DP、US AP/SAT/ACT、GRE、GMAT、TOEFL、IELTS） |
| 通用设备布局 | iPhone TabView + iPad NavigationSplitView + iPadLayout 辅助组件 |
| HRV 准备度 | Apple Watch SDNN、14 天基线、Z-score 分类 |
| 可定制主页 | 8 种卡片、拖动重新排序、逐项开关 |

---

## 2. 架构概览

### 2.1 分层结构图

```
+-------------------------------------------------------------------------+
|                         StudyPulse iOS 应用                               |
+-------------------------------------------------------------------------+
|                                                                         |
|  +----------------- 表现层（SwiftUI、@MainActor） --------------------+ |
|  |  ContentView                                                       | |
|  |   |- iPhone: TabView（5 标签）                                      | |
|  |   '- iPad:   NavigationSplitView（侧栏 + 详情）                       | |
|  |                                                                    | |
|  |  HomeView（欢迎头、统计卡、动态卡片、每日金句、图表、即将考试、成绩）    | |
|  |  TrendsView（科目趋势 + 需要关注科目告警）                            | |
|  |  MistakeView（错题列表 + 建议复习 + 搜索 + 卡片布局）                | |
|  |  ExamView（单科考试 + 综合考试列表、日历集成、倒计时）                 | |
|  |  SettingsView（资料、偏好、教育信息、数据管理、关于）                  | |
|  |                                                                    | |
|  |  模态面板：AddGradeView、NewExamSetView、NewMistakeSetView、         | |
|  |           MistakeDetailEditView、ExamDetailEditView、               | |
|  |           HRVOnboardingView、HomeLayoutSettingsView、               | |
|  |           DataAdminView                                             | |
|  +--------------------------------------------------------------------+ |
|                               |                                          |
|                               v  @EnvironmentObject 注入                  |
|  +------------------ 业务 / 管理层 -----------------------------------+ |
|  |                                                                    | |
|  |  DataManager（@MainActor ObservableObject）                        | |
|  |   - @Published: grades、subjects、mistakeSets、examSets、           | |
|  |                comprehensiveExamSets、profile                       | |
|  |   - 方法: asyncInit()、save*()、load*Async()、saveGradeImage()、   | |
|  |          loadGradeImage()、deleteGradeImage()、saveAvatar()、      | |
|  |          loadAvatar()、deleteAvatar()、fullScore(for:)、            | |
|  |          displayName(for:)、                                        | |
|  |          applySmartSubjectRecommendation(stage:regionCode:)        | |
|  |                                                                    | |
|  |  AppEnvironmentManager（@MainActor ObservableObject、单例）         | |
|  |   - preferences: AppPreferences                                    | |
|  |   - effectiveColorScheme、setLanguage()、setColorScheme()          | |
|  |                                                                    | |
|  |  HealthKitManager（@MainActor ObservableObject、单例）             | |
|  |   - hrvEnabled、hrvOnboardingCompleted、isAuthorized               | |
|  |   - readiness: HRVReadiness（z-score + category + suggestion）     | |
|  |   - dailyHRVHistory、lastSampleCount、hrvDetailLevel                | |
|  |   - enable() / disable() / refreshReadiness()                      | |
|  |                                                                    | |
|  |  CalendarManager（单例、EventKit）                                   | |
|  |  DataExportManager（CSV、@MainActor enum）                          | |
|  |  OCRManager（Vision 文字识别）                                       | |
|  |  ImageCache（nonisolated class、NSCache、50 项、300 px 缩略图）     | |
|  |  EducationConfig（nonisolated enum、全球教育体系）                  | |
|  |  SubjectInfo（展示名 + 颜色 + 满分回退）                             | |
|  |  WidgetDataSyncManager（同步考试到 App Group）                      | |
|  +--------------------------------------------------------------------+ |
|                               |                                          |
|                               v                                          |
|  +------------------ 数据层 ------------------------------------------+ |
|  |                                                                    | |
|  |  模型（Codable、nonisolated、Sendable 值类型）                      | |
|  |   Subject、Grade、MistakeNote、Exam、comprehensiveExam、            | |
|  |   UserProfile、AppPreferences、HomeLayoutPreference                | |
|  |                                                                    | |
|  |  持久化                                                            | |
|  |   ~/Documents/ profile.json、grades.json、mistakes.json、           | |
|  |                 exams.json、comprehensiveExams.json、subjects.json  | |
|  |   ~/Documents/images/  (grade_UUID.jpg、avatar_UUID.jpg)           | |
|  |   UserDefaults（AppPreferences、HomeLayoutPreference、HRV 偏好）    | |
|  |   App Group（widgetUpcomingExams）                                 | |
|  +--------------------------------------------------------------------+ |
|                               |                                          |
|                               v                                          |
|  +------------------ 扩展 / 通知 -------------------------------------+ |
|  |                                                                    | |
|  |  ColorExtensions、DateExtensions、StringsLocalized                  | |
|  |  ExamPrepareNotifications（UNUserNotificationCenter、[1,3,5,10,30]）| |
|  +--------------------------------------------------------------------+ |
|                                                                         |
+-------------------------------------------------------------------------+
```

### 2.2 模块依赖关系图

```
+--------------------------+
|  Views（SwiftUI）        |
|  HomeView / TrendsView   |
|  MistakeView / ExamView  |
|  SettingsView + 模态面板 |
+-------------+------------+
              |
              |  @EnvironmentObject 注入
              v
+--------------------------+
|  Managers                |
|  +-------------------+   |
|  | DataManager (@MainActor)  |---+
|  +-------------------+       |
|  AppEnvironmentManager        |
|  HealthKitManager             |
|  CalendarManager              |     辅助管理器
|  OCRManager                   |     ← NSCache / Vision /
|  ImageCache                   |       EventKit / WidgetKit /
|  EducationConfig              |       EducationConfig /
|  SubjectInfo                  |       DataExportManager /
|  DataExportManager            |       WidgetDataSyncManager
|  WidgetDataSyncManager        |
+-------------+----------------+
              |
              v
+--------------------------+
|  Models（Codable 结构体） |
|  Subject、Grade、Exam、    |
|  comprehensiveExam、       |
|  MistakeNote、UserProfile、|
|  AppPreferences、           |
|  HomeLayoutPreference      |
+--------------------------+
              |
              v
+--------------------------+
|  持久化                   |
|  ~/Documents/*.json       |
|  ~/Documents/images/      |
|  UserDefaults             |
|  App Group（Widget）      |
+--------------------------+

小组件依赖链（与主应用解耦）：
+---------------------------+     +------------------------+
| StudyPulseWidget          |---->| WidgetDataStore（App Group）|
|  ExamWidget、Entry、Views  |     +------------------------+
|  ExamWidgetProvider         |
+---------------------------+
```

### 2.3 数据流（持久化）

```
[应用启动]
StudyPulseApp
  └─ .task { dataManager.asyncInit() }
       └─ Task.detached(priority: .userInitiated)
            ├─ 加载 profile.json
            ├─ 加载 grades.json（迁移 Grade.image 内联数据到文件）
            ├─ 加载 mistakes.json
            ├─ 加载 exams.json（ISO8601 日期）
            ├─ 加载 comprehensiveExams.json
            └─ 加载 subjects.json
       └─ MainActor.run { 赋值给 @Published; initializeDefaultSubjects() }

[用户编辑]
View → DataManager.save*() → JSONEncoder → ~/Documents/{file}.json
                                     ↓
                           WidgetDataSyncManager.syncExamsToWidget()
                                     ↓
                           App Group UserDefaults
                           └─ WidgetCenter.reloadTimelines()
```

---

## 3. 仓库布局

```
StudyPulse/
├── StudyPulse.xcodeproj/                 # Xcode 工程（单目标 StudyPulse）
│
├── StudyPulse/                            # 主目标源代码
│   ├── StudyPulseApp.swift                # @main 入口、通知授权、.task 启动
│   ├── StudyPulse.entitlements            # HealthKit 权限
│   ├── Assets.xcassets/                   # AccentColor、AppIcon、StudyPulseIcon
│   │
│   ├── Models/                            # 数据模型
│   │   ├── DataModels.swift               # Subject、Grade、MistakeNote、Exam、
│   │   │                                 # comprehensiveExam、UserProfile、
│   │   │                                 # EducationStage、EducationCategory、
│   │   │                                 # SubjectConfig、EducationRegion
│   │   ├── AppPreferences.swift           # 应用偏好：语言 + 色彩方案
│   │   └── HomeLayoutPreference.swift     # 主页卡片顺序与启用标记（UserDefaults）
│   │
│   ├── Managers/                          # 业务 / 管理层
│   │   ├── DataManager.swift              # @MainActor ObservableObject
│   │   ├── AppEnvironmentManager.swift    # 全局语言 + 主题管理（单例）
│   │   ├── AppStyle.swift                 # 设计系统骨架
│   │   ├── CalendarManager.swift          # EventKit 集成
│   │   ├── DataExportManager.swift        # CSV 导出（@MainActor enum）
│   │   ├── EducationConfig.swift          # 全球教育系统（nonisolated enum）
│   │   ├── ExamWidgetData.swift           # Widget 数据模型 + AppGroupConfig + WidgetDataStore
│   │   ├── HealthKitManager.swift         # HRV（SDNN）准备度、基线、日级历史
│   │   ├── ImageCache.swift               # NSCache 缩略图缓存（nonisolated）
│   │   ├── OCRManager.swift               # Vision 文本识别
│   │   ├── StringsLocalized.swift         # String.localized() 辅助
│   │   ├── SubjectInfo.swift              # 展示名 + 颜色 + 满分回退
│   │   └── WidgetDataSyncManager.swift    # App Group 同步（编码 + 写入）
│   │
│   ├── Views/                             # SwiftUI 视图
│   │   ├── ContentView.swift              # 根视图：iPhone TabView / iPad NavigationSplitView
│   │   ├── HomeView.swift                 # 主页仪表盘
│   │   ├── TrendsView.swift               # 科目趋势分析
│   │   ├── MistakeView.swift              # 错题列表 + 建议复习 + 搜索
│   │   ├── ExamView.swift                 # 考试列表（单科 + 综合）
│   │   ├── SettingsView.swift             # 设置：资料 / 偏好 / 教育信息 / 数据 / 关于
│   │   ├── PreferencesView.swift          # 语言 + 外观偏好
│   │   ├── HomeLayoutSettingsView.swift   # 主页卡片重排序与开关
│   │   ├── HRVOnboardingView.swift        # HRV 3 页引导：是什么 / 隐私 / 授权
│   │   ├── AddGradeView.swift             # 模态：添加成绩
│   │   ├── NewExamSetView.swift           # 模态：新增 / 编辑考试
│   │   ├── NewMistakeSetView.swift        # 模态：新增错题（照片 + OCR）
│   │   ├── ExamDetailView.swift           # 考试详情 + 关联错题
│   │   ├── ExamDetailEditView.swift       # 编辑考试
│   │   ├── MistakeDetailEditView.swift    # 四块错题编辑器（每块独立照片 + OCR）
│   │   ├── SubjectScoreCard.swift         # 可复用科目成绩卡
│   │   │
│   │   ├── Components/                    # 可复用组件
│   │   │   ├── GradeChartView.swift
│   │   │   ├── HRVStatusCard.swift        # 主页 HRV 卡（3 级详情）
│   │   │   └── SubjectPickerView.swift
│   │   │
│   │   ├── Helpers/                       # 视图辅助
│   │   │   ├── AvatarView.swift           # 头像（首字母回退）
│   │   │   ├── ImagePicker.swift          # 照片库选择
│   │   │   ├── PhotoCaptureView.swift     # 相机拍摄
│   │   │   ├── ScoreColor.swift           # 按比例映射分数 → 颜色
│   │   │   ├── ZoomableImageView.swift    # 双指 / 双击缩放
│   │   │   └── iPadLayout.swift           # adaptiveMaxWidth / AdaptiveHStack /
│   │   │                                 # AdaptiveGridColumns / adaptiveCardPadding
│   │   │
│   │   ├── Admin/                         # 开发者工具
│   │   │   └── DataAdminView.swift        # 批量数据操作
│   │   │
│   │   └── OnBoarding/                    # 启动引导
│   │       └── WelcomeConfig.swift        # WSOnBoarding 欢迎配置
│   │
│   ├── Extensions/
│   │   ├── ColorExtensions.swift
│   │   └── DateExtensions.swift
│   │
│   └── NotificationsControl/
│       └── ExamPrepareNotifications.swift # 本地通知调度（[1,3,5,10,30]）
│
├── StudyPulseWidget/                       # WidgetKit 小组件源（目标暂未接入）
│   ├── ExamWidget.swift                    # Widget 定义
│   ├── ExamWidgetData.swift                # 共享数据模型
│   ├── ExamWidgetEntry.swift               # 时间轴条目
│   ├── ExamWidgetProvider.swift            # 时间轴提供者
│   ├── ExamWidgetViews.swift               # S / M / L 三种尺寸视图
│   ├── StudyPulseWidgetBundle.swift        # @main bundle
│   ├── Info.plist
│   └── Assets.xcassets/                    # AccentColor、AppIcon、WidgetBackground
│
├── TestData/                               # 示例 CSV 与生成脚本
│   ├── README.md
│   ├── grades_sample.csv、mistakes_sample.csv
│   ├── single_exams_sample.csv、comprehensive_exams_sample.csv
│   ├── exams_sample.csv、simple_test.csv
│   ├── generate_test_data.py、check_csv.py
│   ├── TestDataGenerator.swift、TestParser.swift、test_import.swift
│
├── en.lproj、zh-Hans.lproj、zh-Hant.lproj、ja.lproj、ko.lproj
│       └── Localizable.strings
│
├── README.md、AGENTS.md、CODE_WIKI.md、CODE_WIKI_CN.md、LICENSE
│
└── scripts/
    └── build.sh                            # Bash 构建辅助（xcodebuild 包装）
```

---

## 4. 数据模型参考

### 4.1 模型汇总表

| 模型 | 文件 | 类型 | ID 源 | Codable | Sendable | 用途 |
|---|---|---|---|---|---|---|
| Subject | DataModels.swift | struct | UUID | 是 | 是 | 用户科目列表，支持自定义满分 |
| Grade | DataModels.swift | struct | UUID | 是 | 是 | 单条成绩记录，含 imageFileName 指向图片文件 |
| MistakeNote | DataModels.swift | struct | UUID | 是 | 是 | 四块错题编辑，每块独立图片文件名数组 |
| Exam | DataModels.swift | struct | UUID | 是 | 是 | 单科考试 |
| comprehensiveExam | DataModels.swift | struct | UUID | 是 | 是 | 综合考试（多科目） |
| UserProfile | DataModels.swift | struct | 无 | 是 | 是 | 用户资料：学校、年级、班级、学号、入学年、考试年、目标学校/分数、avatarFileName、educationStage、regionCode、selectedSubjects |
| AppPreferences | AppPreferences.swift | struct | 无 | 是 | 是 | appLanguage、colorScheme（持久化到 UserDefaults） |
| HomeLayoutPreference | HomeLayoutPreference.swift | struct | 无 | 是 | 是 | 有序 items（HomeCardItem 数组，每项带 enabled flag，持久化到 UserDefaults） |
| EducationStage | DataModels.swift | enum | rawValue | 是 | 是 | primary / middle / high / internationalHigh / university / graduate |
| EducationCategory | DataModels.swift | enum | rawValue | 是 | 是 | domestic / international |
| SubjectConfig | DataModels.swift | struct | name | 是 | 是 | 教育区域内的科目配置（required / elective 工厂方法） |
| EducationRegion | DataModels.swift | struct | name | 是 | 是 | 区域教育系统（subjects、notes、systemCode） |

### 4.2 Subject 模型

```swift
nonisolated struct Subject: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var displayName: String
    var enabled: Bool
    var fullScore: Double
}
```

### 4.3 Grade 模型

```swift
nonisolated struct Grade: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var subject: String
    var score: Double
    var rawScore: Double?
    var ranking: Int?
    var importance: Int           // 1 ... 5
    var image: Data?              // 旧字段；legacy，已迁移到文件
    var imageFileName: String?    // 新字段：~/Documents/images/{imageFileName}
    var date: Date
    var examName: String
    var fullScore: Double?        // 本次考试自定义满分

    func scoreRate(subjectFullScore: Double = 100) -> Double
}
```

### 4.4 MistakeNote 模型

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

    // 每块的图片文件名数组（保存在 ~/Documents/images/）
    var questionImages: [String]
    var reasonImages: [String]
    var wrongSolutionImages: [String]
    var correctSolutionImages: [String]
}
```

### 4.5 Exam / comprehensiveExam

```swift
nonisolated struct Exam: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var subject: String                 // 单科
    var examDate: Date
    var importance: Int
    var masteryDegree: Int               // 0 ... 100
    var notes: String
}

nonisolated struct comprehensiveExam: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var subject: [String]                // 多科目
    var examDate: Date
    var importance: Int
    var masteryDegree: Int
    var notes: String
}
```

### 4.6 UserProfile

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
    var educationStage: String            // EducationStage rawValue
    var regionCode: String                 // EducationRegion.name
    var selectedSubjects: [Subject] = []
    var theme: String = "Auto"
    var avatarFileName: String?
}
```

### 4.7 AppPreferences 与 HomeLayoutPreference

```swift
struct AppPreferences: Codable {
    var appLanguage: String?              // "en"、"zh-Hans" …；nil = 跟随系统
    var colorScheme: ColorSchemeOption
}

enum ColorSchemeOption: String, CaseIterable, Codable {
    case system, light, dark
}

struct HomeLayoutPreference: Codable {
    var items: [HomeCardItem]             // 有序；每块带 enabled 开关
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
}
```

---

## 5. 管理器参考

### 5.1 管理器汇总表

| 管理器 | 文件 | Actor / 范围 | 关键协作者 | 用途 |
|---|---|---|---|---|
| DataManager | DataManager.swift | @MainActor ObservableObject | 全部模型、ImageCache、WidgetDataSyncManager | 中央状态与持久化 |
| AppEnvironmentManager | AppEnvironmentManager.swift | @MainActor ObservableObject（单例） | AppPreferences、UserDefaults | 语言 + 主题管理 |
| HealthKitManager | HealthKitManager.swift | @MainActor ObservableObject（单例） | HKHealthStore、HRVReadiness、HRVStatusCard | HRV（SDNN）准备度 |
| CalendarManager | CalendarManager.swift | class 单例 | EventKit | 添加考试到系统日历 |
| OCRManager | OCRManager.swift | class | Vision 框架 | 图像 → 文本识别（zh-Hans + en） |
| ImageCache | ImageCache.swift | nonisolated class 单例 | NSCache | 缩略图缓存（最多 50 项，300 px） |
| EducationConfig | EducationConfig.swift | nonisolated enum | EducationRegion、SubjectConfig | 全球教育系统静态注册 |
| SubjectInfo | SubjectInfo.swift | class | SubjectConfig、Subject | 展示名、颜色、满分回退 |
| WidgetDataSyncManager | WidgetDataSyncManager.swift | class 单例 | App Group 容器、WidgetCenter | 同步考试到小组件 |
| DataExportManager | DataExportManager.swift | @MainActor enum | CSVDocument、FileDocument、UIActivityViewController | CSV 导出 |

### 5.2 DataManager 数据流

```
[视图] 用户点击保存
   |
   v
DataManager.save{实体}()（@MainActor）
   |
   +-- 更新 @Published 属性 → SwiftUI 重新渲染
   +-- JSONEncoder.encode(实体) → JSON Data
   +-- DataFileIO.write(data, to: ~/Documents/{file}.json)
   |
   +-- 若实体属于考试 → WidgetDataSyncManager.syncExamsToWidget()
   |                                     |
   |                                     v
   |                           App Group 容器
   |                           (group.com.chenkai.gao.studypulse)
   |                                     |
   |                                     v
   |                           WidgetCenter.reloadTimelines()
   |
[视图] 请求图片
   |
   +-- ImageCache.thumbnail(for: 文件名)
   |        +-- 命中缓存 → 返回 UIImage
   |        +-- 未命中 → 从磁盘加载 → 缓存 → 返回 UIImage
   |
   +-- 全屏查看：ZoomableImageView（双指缩放 + 双击缩放）
```

### 5.3 EducationConfig → DataManager 智能推荐流程

```
用户在 ProfileEditView 选择 EducationStage + EducationRegion
       |
       v
EducationConfig.availableRegions(for: stage) 返回可选区域列表
       |
       v
用户选择区域 → region.name 写入 UserProfile.regionCode
       |
       v
"应用智能推荐" 按钮 → DataManager.applySmartSubjectRecommendation(stage, regionCode)
       |
       +-- 通过 EducationConfig.region(name) 查找 EducationRegion
       +-- 遍历 region.subjects（SubjectConfig[]）
       +-- 映射每个 SubjectConfig → Subject（name、displayName、fullScore、enabled）
       +-- 替换 UserProfile.selectedSubjects
       +-- saveProfile() / saveSubjects()
       |
       v
SwiftUI 刷新 → 新科目出现在 TrendsView / AddGradeView
```

---

## 6. 视图参考

### 6.1 根视图与导航流程

```
ContentView
  |
  +-- iPhone（horizontalSizeClass == .compact）→ TabView {
  |       HomeView / TrendsView / MistakeView / ExamView / SettingsView
  |    }
  |
  +-- iPad（regular） → NavigationSplitView
             |
             +-- sidebar: List + NavigationLink(value: tab)
             |        [主页] [趋势] [错题] [考试] [设置]
             |
             +-- detail: 当前标签视图（adaptiveMaxWidth 居中）

HomeView ────────────────────────┬──→ AddGradeView（.sheet）
  |                              ├──→ NewExamSetView（.sheet）
  |                              ├──→ NewMistakeSetView（.sheet）
  |                              ├──→ HomeLayoutSettingsView（.sheet）
  |                              ├──→ HRVOnboardingView（首次启用 .sheet）
  |                              └──→ ExamDetailView（navigationDestination）
  |
TrendsView ────────────────────→ per-subject 详情
  |
MistakeView ───────────────────→ MistakeDetailEditView（sheet 或 nav destination）
                                        |
                                        +-- OCRManager.recognizeText(in:)
                                        +-- PhotosPicker / UIImagePicker
                                        +-- swift-markdown-ui 预览
  |
ExamView ────────────────────┬──→ NewExamSetView（+ 按钮）
  |                          └──→ ExamDetailView（点击考试）
  |                                   |
  |                                   +--→ ExamDetailEditView（编辑按钮）
  |                                   +--→ MistakeDetailEditView（关联错题）
  |
SettingsView ─────────────────┬──→ PreferencesView
                               ├──→ ProfileEditView
                               ├──→ EditSubjectsView
                               ├──→ DataAdminView
                               ├──→ AboutView
                               └──→ CopyrightView
```

### 6.2 视图汇总表

| 视图 | 文件 | 角色 | 关键特性 |
|---|---|---|---|
| ContentView | ContentView.swift | 根容器 | iPhone TabView / iPad NavigationSplitView + 侧栏 |
| HomeView | HomeView.swift | 仪表盘 | 欢迎头、统计卡、动态卡片（按 HomeLayoutPreference）、双栏 LazyVGrid in iPad |
| TrendsView | TrendsView.swift | 趋势分析 | 每科成绩卡、需要关注告警、iPad `.adaptiveMaxWidth(900)` |
| MistakeView | MistakeView.swift | 错题列表 | 建议复习、搜索、卡片布局、`.adaptiveMaxWidth(900)` |
| ExamView | ExamView.swift | 考试列表 | 日历集成、daysRemaining 计算属性倒计时、`.adaptiveMaxWidth(800)` |
| ExamDetailView | ExamDetailView.swift | 考试详情 | 关联错题、掌握度、备注 |
| NewExamSetView | NewExamSetView.swift | 考试编辑器 | 创建 / 编辑、日历与通知开关 |
| NewMistakeSetView | NewMistakeSetView.swift | 新增错题 | 四块编辑、每块图片 + OCR、Markdown 预览 |
| MistakeDetailEditView | MistakeDetailEditView.swift | 错题编辑 | 同 NewMistakeSetView、EditSection enum 驱动 |
| AddGradeView | AddGradeView.swift | 成绩录入 | 单 / 多科目输入、自定义满分、原始分 + 排名 |
| SettingsView | SettingsView.swift | 设置枢纽 | 资料卡、编辑资料 / 科目、偏好、教育信息、CSV 导入导出、关于、`.adaptiveMaxWidth(720)` |
| ProfileEditView | ProfileEditView.swift | 资料编辑 | 12+ 字段：学校、年级、班级、学号、入学年、考试年、目标学校 / 分数 |
| EditSubjectsView | EditSubjectsView.swift | 科目编辑 | 每科满分自定义 |
| PreferencesView | PreferencesView.swift | 偏好 | 主题（system/light/dark）、语言（en/zh-Hans/zh-Hant/ja/ko/跟随系统）、`.adaptiveMaxWidth(640)` |
| HomeLayoutSettingsView | HomeLayoutSettingsView.swift | 主页布局 | 拖动重新排序 + 逐项启用/禁用、写入 UserDefaults |
| HRVOnboardingView | HRVOnboardingView.swift | HRV 引导 | 3 页：什么是 HRV / 隐私说明 / HealthKit 授权 |
| DataAdminView | Views/Admin/DataAdminView.swift | 开发者工具 | 批量数据操作 |
| AvatarView | Views/Helpers/AvatarView.swift | 可复用 | 头像显示 + 首字母回退 |
| SubjectScoreCard | Views/Helpers/SubjectScoreCard.swift | 可复用 | 渐变色边框 + 入场动画 + mini 趋势图 |
| HRVStatusCard | Views/Components/HRVStatusCard.swift | 可复用 | 3 级详情（suggestionOnly / dataAndSuggestion / chartAndData） |
| iPadLayout 辅助 | Views/Helpers/iPadLayout.swift | 可复用 | adaptiveMaxWidth、AdaptiveHStack、AdaptiveGridColumns、adaptiveCardPadding |

### 6.3 主页卡片槽位

| 卡片类型 | 文件 | 默认启用 | 空时隐藏 | 用途 |
|---|---|---|---|---|
| hrvStatus | HRVStatusCard.swift | 是（HRV 未启用时不显示） | 否 | 显示 HRV 准备度 |
| unregisteredExamsReminder | HomeView.swift（内联） | 是 | 是 | 提醒最近 3–7 天未录入成绩的考试 |
| quickActions | HomeView.swift（内联） | 是 | 否 | 快捷跳转到 AddGradeView / NewExamSetView / NewMistakeSetView |
| studySuggestions | HomeView.swift（内联） | 是 | 否 | 每日 AI 风格提示 |
| trendChart | GradeChartView.swift | 是 | 是 | 学科趋势图表（无近期数据时隐藏） |
| upcomingExams | HomeView.swift（内联） | 是 | 是 | 即将到来的考试（点击 → ExamDetailView） |
| dailyQuote | HomeView.swift（内联） | 是 | 否 | 每日励志金句 |
| recentGrades | HomeView.swift（内联） | 是 | 是 | 最近 5 条成绩 |

HomeView 渲染顺序由 `HomeLayoutPreference.load().enabledTypes` 决定。

---

## 7. 主页卡片系统

### 7.1 卡片类型清单

| HomeCardType | UI 组件 | 控制者 | 持久化 |
|---|---|---|---|
| hrvStatus | HRVStatusCard | HealthKitManager.hrvEnabled + HomeLayoutPreference | UserDefaults（HomeLayoutPreference） |
| unregisteredExamsReminder | HomeView 内联 | DataManager 考试 / 成绩对比（3–7 天窗口） | UserDefaults（HomeLayoutPreference） |
| quickActions | HomeView 内联 | 静态 | UserDefaults（HomeLayoutPreference） |
| studySuggestions | HomeView 内联 | 静态 + 数据派生 | UserDefaults（HomeLayoutPreference） |
| trendChart | GradeChartView | DataManager.grades（无近期数据隐藏） | UserDefaults（HomeLayoutPreference） |
| upcomingExams | HomeView 内联 | DataManager.examSets + comprehensiveExamSets | UserDefaults（HomeLayoutPreference） |
| dailyQuote | HomeView 内联 | 静态 | UserDefaults（HomeLayoutPreference） |
| recentGrades | HomeView 内联 | DataManager.grades | UserDefaults（HomeLayoutPreference） |

### 7.2 持久化与渲染流程

```
用户打开 HomeLayoutSettingsView
       |
       v
HomeLayoutPreference.load()  ←  从 UserDefaults 读取
       |
       v
用户拖动重新排序、切换开关
       |
       v
HomeLayoutPreference.save() →  写入 UserDefaults
       |
       v
HomeView.body 读取 enabledTypes
       |
       v
按启用顺序渲染卡片
   ├ iPhone: VStack（单列）
   └ iPad:   LazyVGrid（两栏，低内存开销）
```

### 7.3 新增卡片类型时的 mergeWithDefault 流程

```
应用更新发布新的 HomeCardType
       |
       v
HomeLayoutPreference.load() 时调用 mergeWithDefault
       |
       +-- 现有 items（来自 UserDefaults）按原顺序保留
       +-- 尚未出现的新卡片类型追加到末尾、enabled = true
       +-- 不再使用的旧卡片类型移除
       |
       v
用户看到保留原顺序 + 新卡片默认启用
```

---

## 8. 教育体系

### 8.1 体系树

```
教育体系（EducationConfig）
|
+-- 国内（Domestic）
|   +-- 中国大陆标准版
|   |   +-- 小学
|   |   +-- 初中
|   |   +-- 高中
|   |
|   +-- 浙江
|   |   +-- 初中
|   |   +-- 高中 3+3
|   |
|   +-- 上海
|   |   +-- 初中
|   |   +-- 高中 3+3
|   |
|   +-- 台湾
|   |   +-- 初中
|   |   +-- 学测（GSAT）
|   |
|   +-- 香港
|       +-- DSE
|
|   +-- 新加坡
|       +-- O-Level
|
+-- 国际（International）
    +-- UK
    |   +-- IGCSE
    |   +-- A-Level
    |
    +-- IB
    |   +-- Diploma Programme（DP）
    |
    +-- US
    |   +-- AP（Advanced Placement）
    |   +-- SAT（Scholastic Assessment Test）
    |   +-- ACT（American College Testing）
    |
    +-- 研究生与语言
        +-- GRE
        +-- GMAT
        +-- TOEFL
        +-- IELTS
```

### 8.2 覆盖矩阵

| 区域 | 小学 | 初中 | 高中 | 国际高中 | 大学 | 研究生 |
|---|---|---|---|---|---|---|
| 中国大陆标准版 | 是 | 是 | 是 | - | - | - |
| 浙江 | - | 是 | 是（3+3） | - | - | - |
| 上海 | - | 是 | 是（3+3） | - | - | - |
| 台湾 | - | 是 | 是（学测） | - | - | - |
| 香港 DSE | - | - | 是 | - | - | - |
| 新加坡 O-Level | - | 是 | 是 | 是 | - | - |
| UK IGCSE | - | 是 | - | 是 | - | - |
| UK A-Level | - | - | 是 | 是 | - | - |
| IB Diploma | - | - | 是 | 是 | - | - |
| US AP | - | - | 是 | 是 | - | - |
| US SAT | - | - | - | - | 是 | - |
| US ACT | - | - | - | - | 是 | - |
| GRE / GMAT | - | - | - | - | - | 是 |
| TOEFL / IELTS | - | - | - | - | - | 是 |

### 8.3 满分参考

| 系统 | 典型满分范围 | 例子 |
|---|---|---|
| 中国大陆高中 | 100 / 150 | 语文 150、物理 100 |
| 浙江高中（赋分） | 100 | 所有科目 100 满 |
| 香港 DSE | 1-7（5** = 7） | 所有科目 7 满 |
| 台湾学测 | 100 | 数学 A / 数学 B 各 100 |
| UK A-Level | 100 | A* = 90+ |
| IB DP | 1-7 | 6 科 + TOK + EE = 45 满 |
| US AP | 1-5 | 5 满 |
| US SAT | 200-800 | 1600 总 |
| US ACT | 1-36 | 36 满 |
| GRE | 130-170 | 340 总 |
| TOEFL | 0-120 | - |
| IELTS | 0-9 | - |

### 8.4 SubjectConfig 工厂方法

```swift
// 必修科目
SubjectConfig.required(name, displayName, fullScore, category)
// 选修科目
SubjectConfig.elective(name, displayName, fullScore, category)
```

EducationRegion.subjects 为 SubjectConfig 数组，DataManager 将其映射到 Subject（name、displayName、fullScore、enabled）。

---

## 9. HRV / HealthKit 子系统

### 9.1 架构图

```
+---------------------------------------+
|  HealthKitManager                     |
|  (@MainActor ObservableObject 单例)    |
|   - hrvEnabled: Bool                  |
|   - hrvOnboardingCompleted: Bool      |
|   - isAuthorized: Bool                |
|   - readiness: HRVReadiness            |
|     (z-score、category、suggestion)    |
|   - dailyHRVHistory: [HRVSample]      |
|   - lastSampleCount: Int              |
|   - hrvDetailLevel: HRVDetailLevel     |
|     (suggestionOnly / dataAndSuggestion|
|      / chartAndData)                   |
+---------------+-----------------------+
                | 读取 HRV 样本
                v
+---------------------------------------+
|  HKHealthStore                         |
|  heartRateVariabilitySDNN             |
|  14 天窗口样本                         |
+---------------+-----------------------+
                |
                v
+---------------------------------------+         +----------------------------------+
|  HRVStatusCard（HomeView 渲染）        |         |  HRVOnboardingView（首次启用）    |
|  根据 hrvDetailLevel 渲染 3 级详情之一  |         |  3 页：什么是 HRV / 隐私 / 授权      |
+---------------------------------------+         +----------------------------------+
```

### 9.2 准备度计算流程

```
用户打开 HomeView（或点击刷新）
       |
       v
HealthKitManager.refreshReadiness()
       |
       +-- 请求 HKHealthStore.requestAuthorization（如需要）
       +-- HKSampleQuery 查询 heartRateVariabilitySDNN、最近 14 天
       |
       +-- 按日历日聚合：取每日第一个样本、降序排列
       |
       +-- 基线：取最近 ≥ 7 天均值 mean 与标准差 stdDev
       |
       +-- z-score = (今日 SDNN − mean) / stdDev
       |
       +-- 分类：
       |       excellent（z > 1）
       |       normal（-1 ≤ z ≤ 1）
       |       low（z < -1）
       |       insufficient（< 7 天）
       |       noAuthorization（未授权）
       |       queryFailed（查询失败）
       |
       +-- 生成建议字符串（本地化）
       |
       v
@Published readiness 更新 → SwiftUI 重新渲染 HRVStatusCard
```

### 9.3 分类表

| category | z-score 范围 | 建议方向 |
|---|---|---|
| excellent | z > 1 | 高恢复度 — 可挑战高难度学习 |
| normal | -1 ≤ z ≤ 1 | 稳定 — 按计划进行 |
| low | z < -1 | 低恢复度 — 建议减轻任务 |
| insufficient | < 7 天数据 | 戴 Apple Watch 以建立基线 |
| noAuthorization | HealthKit 未授权 | 授权 HealthKit 以查看 HRV 准备度 |
| queryFailed | 查询失败 | 出问题了 — 稍后重试 |

---

## 10. 图像、OCR 与 CSV 管线

### 10.1 图像管线

```
拍摄 / 选择流程：
 PhotoCaptureView（相机）或 ImagePicker（照片库）
          |
          v
     原始图像（UIImage）
          |
          v
     JPEG 压缩 → Data
          |
          v
     DataManager.saveGradeImage(data) 或 saveAvatar(data)
          |
          v
     生成文件名（grade_UUID.jpg 或 avatar_UUID.jpg）
          |
          v
     DataFileIO.write 到 ~/Documents/images/
          |
          v
     文件名写回 Grade.imageFileName 或 UserProfile.avatarFileName

显示流程：
 SwiftUI 视图（HomeView、ExamDetailView、ProfileEditView …）
          |
          v
     ImageCache.thumbnail(for: 文件名) — nonisolated、线程安全
          |
          +-- 缓存命中 → 返回 UIImage
          +-- 缓存未命中 → 从磁盘加载 → 缓存 → 返回 UIImage
          |
          v
     全屏查看 → ZoomableImageView（双指 + 双击缩放）
```

### 10.2 OCR 管线

```
用户在 MistakeDetailEditView 选择图片（Question / Reason / Wrong / Correct）
          |
          v
     OCRManager.shared.recognizeText(in: imageData, completion: { recognizedText in ... })
          |
          +-- VNRecognizeTextRequest
          |       recognitionLevel = .accurate
          |       recognitionLanguages = ["zh-Hans", "en"]
          |
          +-- completion 按文本观察对象返回 top candidate 字符串拼接
          |
          v
     识别出的文本写回对应的文本字段
```

### 10.3 CSV 管线

```
用户在 SettingsView 点击"导出"
          |
          v
     DataExportManager.build{Kind}CSV()（@MainActor enum）
          |
          +-- headers（标题行）
          +-- rows（转义逗号/引号/换行）
          |
          v
     CSV 字符串 → CSVDocument（FileDocument）→ UIActivityViewController → 分享 / 保存
```

### 10.4 ImageCache 规格

| 属性 | 值 |
|---|---|
| 范围 | nonisolated class（Sendable 安全） |
| 单例 | `ImageCache.shared` |
| 最大条目 | 50 |
| 最大尺寸 | 300 px（缩略图） |
| Key 来源 | 文件名（在 `~/Documents/images/` 下） |
| 底层存储 | NSCache（成本驱动回收） |

---

## 11. iPad 适配

### 11.1 iPadLayout 辅助组件

| 组件 | 文件 | 用途 |
|---|---|---|
| adaptiveMaxWidth(_:) | iPadLayout.swift | iPad 上居中内容，默认 720 |
| AdaptiveHStack | iPadLayout.swift | iPad 横向 HStack，iPhone 纵向 VStack |
| AdaptiveGridColumns(compact:regular:spacing:) | iPadLayout.swift | 分 compact / regular 给出不同栏数 |
| adaptiveCardPadding() | iPadLayout.swift | iPhone 20 pt 外间距，iPad 不加 |

### 11.2 各视图 iPad 最大宽度

| 视图 | iPad 最大宽度 | 备注 |
|---|---|---|
| PreferencesView | 640 | 语言 + 主题 |
| SettingsView | 720 | 设置枢纽 |
| ExamView | 800 | 考试列表 |
| TrendsView | 900 | 趋势分析 |
| MistakeView | 900 | 错题卡片 |
| HomeView | 1100 | 两栏 LazyVGrid 动态卡片；单栏统计头 |

### 11.3 ContentView 布局切换

```
ContentView
   ┌─ horizontalSizeClass
   │
   ├─ .compact → TabView { HomeView / TrendsView / MistakeView / ExamView / SettingsView }
   │
   └─ .regular → NavigationSplitView
                    ┌ sidebar: List { NavigationLink(value: tab) }
                    │        [主页] [趋势] [错题] [考试] [设置]
                    │
                    └ detail: 当前标签视图，外层 adaptiveMaxWidth 居中
```

### 11.4 适配原则

1. iPhone 布局保持不变；所有 iPad 分支以 `horizontalSizeClass == .regular` 或 `UIDevice.current.userInterfaceIdiom == .pad` 判断。
2. 内容居中而非拉伸到屏幕边缘。
3. 使用 iPadLayout.swift 中的辅助组件代替在内联写 size class 分支。
4. 侧栏使用 `.listStyle(.sidebar)` + `NavigationLink(value: tab)`。

---

## 12. 本地化

### 12.1 支持语言

| 语言 | Key | 文件夹 |
|---|---|---|
| English | en | en.lproj/Localizable.strings |
| 简体中文 | zh-Hans | zh-Hans.lproj/Localizable.strings |
| 繁體中文 | zh-Hant | zh-Hant.lproj/Localizable.strings |
| 日本語 | ja | ja.lproj/Localizable.strings |
| 한국어 | ko | ko.lproj/Localizable.strings |

### 12.2 String.localized() 扩展

```swift
// StringsLocalized.swift
extension String {
    var localized: String { NSLocalizedString(self, comment: "") }
}
```

使用示例：

```swift
Text("home.welcome.title".localized)
```

### 12.3 语言切换流程

```
用户打开 PreferencesView → 选择语言
         |
         v
AppEnvironmentManager.shared.setLanguage("zh-Hans")
         |
         +-- 更新 preferences.appLanguage
         +-- 写入 UserDefaults
         +-- 修改 AppleLanguages（强制系统按此语言呈现 UIKit 组件）
         |
         v
根视图重新渲染 → 所有 .localized 文本使用新语言

启动时：
StudyPulseApp.init 调用
   AppEnvironmentManager.shared.applyLanguageOnLaunch()
→ 从 UserDefaults 恢复偏好语言
```

---

## 13. 隐私权限

| Info.plist Key | 用途 | 说明 |
|---|---|---|
| NSCameraUsageDescription | 相机访问 | 拍摄错题照片以附加到 MistakeNote |
| NSPhotoLibraryUsageDescription | 照片库访问 | 从照片库选择图片附加 |
| NSCalendarsUsageDescription | 日历访问 | 添加考试到系统日历 |
| NSHealthShareUsageDescription | HealthKit 读取 | 读取 HRV（SDNN）样本以计算准备度；应用从不写入 |

Entitlements：

| Entitlement | 值 | 用途 |
|---|---|---|
| com.apple.developer.healthkit | true | 启用 HealthKit API |

注意：未声明 `NSHealthUpdateUsageDescription`，因为应用从不向 HealthKit 写入数据。

---

## 14. 小组件扩展

### 14.1 架构图

```
+-----------------------------------------+
|          主应用（StudyPulse）            |
|                                          |
|  DataManager.saveExams() /              |
|    saveComprehensiveExams()              |
|            |                             |
|            v                             |
|  WidgetDataSyncManager                   |
|   .syncExamsToWidget(exams)              |
|            |                             |
|            v                             |
|  App Group 容器                          |
|  (group.com.chenkai.gao.studypulse)      |
|                                          |
+------------+-----------------------------+
             |
             v
+------------+-----------------------------+
|       StudyPulseWidget 扩展              |
|                                          |
|  ExamWidgetProvider.getTimeline(in:for:after:) |
|            |                             |
|            +-- 从 App Group 加载 ExamWidgetData |
|            +-- 构造 TimelineEntry          |
|            +-- 返回给系统                 |
|                                          |
|  ExamWidgetViews（S / M / L）            |
|  由 WidgetKit 渲染                       |
+------------------------------------------+
```

### 14.2 组件表

| 组件 | 文件 | 用途 |
|---|---|---|
| ExamWidget | StudyPulseWidget/ExamWidget.swift | Widget 定义 |
| ExamWidgetData | StudyPulseWidget/ExamWidgetData.swift | 共享数据模型（name、subject、examDate、daysRemaining） |
| ExamWidgetEntry | StudyPulseWidget/ExamWidgetEntry.swift | 时间轴条目 |
| ExamWidgetProvider | StudyPulseWidget/ExamWidgetProvider.swift | 时间轴提供者 |
| ExamWidgetViews | StudyPulseWidget/ExamWidgetViews.swift | Small / Medium / Large 视图 |
| StudyPulseWidgetBundle | StudyPulseWidget/StudyPulseWidgetBundle.swift | @main bundle |

### 14.3 启用步骤

1. 在 Xcode 中新增 Widget Extension 目标，Bundle ID 设为 `Gao.Chenkai.StudyPulse.Widget`、部署目标 iOS 18.6。
2. 在主应用目标 **与** 小组件目标上同时启用 App Group `group.com.chenkai.gao.studypulse`。
3. 如果修改 App Group 标识符，请同步更新 `AppGroupConfig.identifier`。
4. 在主应用的考试 add / edit 后调用 `WidgetDataSyncManager.syncExamsToWidget()`；应用从后台进入活跃时也调用一次。
5. 写入后调用 `WidgetCenter.shared.reloadAllTimelines()` 触发刷新。

---

## 15. 依赖（SPM）

| 包 | 来源 | 用途 |
|---|---|---|
| WSOnBoarding | 本地包（Swift/Packages/WSOnBoarding） | 首次启动欢迎流程 |
| swift-markdown-ui | 本地包（Swift/Packages/swift-markdown-ui） | MistakeView Markdown 预览 |
| NetworkImage | https://github.com/gonzalezreal/NetworkImage @ 6.0.1 | 异步图片加载 |
| cmark-gfm | （内部依赖） | Markdown 解析核心 |

Apple 框架使用：

- SwiftUI
- Charts
- Vision
- EventKit
- UserNotifications
- HealthKit
- WidgetKit
- UniformTypeIdentifiers
- PhotosUI

---

## 16. 构建与运行

### 16.1 scripts/build.sh 选项

| 命令 | 效果 |
|---|---|
| `./scripts/build.sh` | Debug 构建，iPhone 17 模拟器 |
| `./scripts/build.sh release` | Release 构建 |
| `./scripts/build.sh clean` | 清理构建目录 |
| `./scripts/build.sh list` | 列出可用模拟器 |
| `./scripts/build.sh help` | 显示所有选项 |

### 16.2 直接使用 xcodebuild

```bash
xcodebuild \
  -project StudyPulse.xcodeproj \
  -scheme StudyPulse \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

### 16.3 可用 Scheme 与配置

| 种类 | 可选值 |
|---|---|
| Schemes | StudyPulse、MarkdownUI、WSOnBoarding |
| Configurations | Debug、Release |

### 16.4 解析 SPM 包

在 Xcode 中：File → Packages → Resolve Package Versions

命令行：

```bash
xcodebuild -resolvePackageDependencies -project StudyPulse.xcodeproj
```

---

## 17. 编码规范

| 领域 | 规则 |
|---|---|
| 并发 | Swift 6 Strict Concurrency；`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`；持有 `@Published` 状态的管理器使用 `@MainActor`；纯辅助与 I/O 使用 nonisolated |
| 模型 | 使用 Codable、nonisolated、Sendable 值类型；不要写 class-based 模型 |
| 视图 | 放在 `Views/` 下，子目录：`Components/`、`Helpers/`、`Admin/`、`OnBoarding/` |
| 管理器 | 放在 `Managers/`；如果持有 `@Published` 状态 → 标记 `@MainActor` |
| 字符串 | 永远使用 `"key".localized`；**不要**写内联英文 / 中文 |
| 颜色与日期 | 通过 ColorExtensions / DateExtensions 包装使用 |
| 图片 | 以文件形式保存在 `~/Documents/images/`，通过 `DataManager.saveGradeImage() / saveAvatar()` 保存；**不要**内联到 JSON（Grade.image 已迁移为 legacy） |
| 错题编辑 | 使用 `EditSection` enum 驱动四块（Question / Reason / Wrong / Correct） |
| 教育系统 | 使用 `EducationConfig`（nonisolated enum）配合 `SubjectConfig` 工厂（`required(...)` / `elective(...)`） |
| iPad 适配 | 优先使用 iPadLayout.swift 中的辅助组件；不要在视图内联写 size-class 分支 |
| 工程文件 | 不要手工修改 `StudyPulse.xcodeproj/project.pbxproj`；交给 Xcode 管理 |
| 修改后 | 每次非 trivial 代码改动后，执行 Xcode Cmd+B 或 `./scripts/build.sh` 确认无语法 / 类型错误 |

---

## 18. 性能说明

| 优化 | 细节 |
|---|---|
| 异步启动 | `StudyPulseApp` 在 `.task` 中调用 `dataManager.asyncInit()`；JSON 在后台线程加载；同步 `load*()` 方法保留以向后兼容 |
| 图片缓存 | `ImageCache.shared`：NSCache 50 项、最大 300 px；完全线程安全（nonisolated） |
| 倒计时 | `ExamRowView` / `ComprehensiveExamRowView` / `UpcomingExamCard` 使用计算属性 `daysRemaining` 而不是 `@State + onAppear`，避免不必要的重渲染 |
| iPad HomeView | 仪表盘使用两栏 `LazyVGrid` 渲染，即便启用大量卡片也保持低内存 |

---

## 19. 已知问题 / 待办

| 问题 | 状态 | 影响 |
|---|---|---|
| Widget Extension 目标未加入 `StudyPulse.xcodeproj` | 打开 | WidgetKit 源码已存在但未构建；需要在 Xcode 中手工新增目标 |
| App Group 标识符未在主应用目标启用 | 打开 | 需要在 Apple Developer 门户创建 App Group，并在主应用目标与 widget 目标同时启用 |
| 未做 iCloud 同步 | 打开 | 所有数据仅本地沙盒存储 |
| `NewMistakeSheet.swift` / `Views/Sheets/` 已移除 | 已关闭（历史） | 当前流程使用 `NewMistakeSetView`；不要重建旧路径 |

---

## 20. 变更记录（面向 Agent）

### v2026.06.20 — 主页布局 + HRV 子系统

- 新增 HealthKitManager.swift、HRVOnboardingView.swift、HRVStatusCard.swift，基于 Apple Watch SDNN 计算准备度（14 天基线 + Z-score 分类）。
- 新增 HomeLayoutPreference.swift 与 HomeLayoutSettingsView.swift，实现卡片 on/off + 拖动重新排序，持久化到 UserDefaults。
- 新增 Views/Admin/DataAdminView.swift，提供开发者批量数据操作。
- ContentView 重写为自定义 NavigationSplitView（iPad），取代 `.sidebarAdaptable`；iPhone 保留经典 TabView。
- HomeView 改为 `HomeLayoutPreference.load().enabledTypes` 驱动的动态卡片组合（HomeCardType 枚举）。
- 新增"未注册考试提醒"卡片（3–7 天窗口内未录入对应成绩）。
- StudyPulse.entitlements 新增 `com.apple.developer.healthkit`。
- 重写 AGENTS.md / CODE_WIKI.md / CODE_WIKI_CN.md / README.md。

### v2026.06.13 — iPad 适配

- iPad（`TARGETED_DEVICE_FAMILY = "1,2"`）通过 iPadLayout.swift 辅助组件：adaptiveMaxWidth、AdaptiveHStack、AdaptiveGridColumns、adaptiveCardPadding。

### v2026.06.07 — 视图层重构与设计系统

- HomeView 拆分为组件；渐变 + 动画打磨。
- MistakeView 建议复习 + 卡片渐变。
- TrendsView "需要关注科目"智能告警。
- ExamDetailView 关联错题区块。
- SubjectScoreCard 渐变边框 + 入场动画。
- AppStyle 设计系统骨架。
- 第一个 StudyPulseWidget 骨架。

### v2026.06.06 — 多语言

- 新增 zh-Hant、ja、ko 本地化。

### v2026.06.05 — 错题模块上线

- 四块错题编辑器（Question / Reason / Wrong / Correct）。
- 每块照片 + OCR（Vision）。
- Markdown 预览（swift-markdown-ui）。
- 日历 / 通知自动调度。
- 可缩放图片查看器。

### v2026.06 — 全球教育系统

- EducationConfig 预置 15+ 种系统（CN、UK、IB、AP、SAT、ACT、GRE、GMAT、TOEFL、IELTS、DSE 等）。
- SubjectConfig 工厂（`required(...)`、`elective(...)`）。
- 头像系统；分数 → 颜色比例映射；扩展 UserProfile 字段。
