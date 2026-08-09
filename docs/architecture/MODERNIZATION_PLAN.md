# StudyPulse 代码现代化需求文档

> 目标：将 StudyPulse 全部代码统一到项目当前最先进的技术基线（Swift 6 严格并发、`@Observable`、结构化并发、Swift Testing、统一部署目标），消除半迁移状态与遗留模式。

- **文档版本**：v1.0
- **创建日期**：2026-07-24
- **适用工具链**：Swift 6.3.3（Xcode / swiftlang-6.3.3）
- **代码规模**：731 个 Swift 文件，约 127,050 行

## 实施状态

- **R1（已完成，2026-07-24）**：状态模型已统一为 `@Observable`；视图注入已统一为 `@State`、`@Bindable` 与类型化 `@Environment`。
- **R2（已完成，2026-07-24）**：已移除 Combine。日志多播改为 `AsyncStream`，通知监听改为 `NotificationCenter.notifications(named:)`，Publisher 定时器改为视图生命周期绑定的异步任务。
- **R3（已完成，2026-07-24）**：采用方案 A。主 App、Widget、测试 target 的部署目标统一为 iOS 26.0，Swift 语言版本统一为 6.0；Widget 已随主 scheme 在 Swift 6 下构建通过。

---

## 1. 背景与现状

StudyPulse 主 App 已经开启现代化配置：

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- 主 App target：`SWIFT_VERSION = 6.0`，`IPHONEOS_DEPLOYMENT_TARGET = 26.0`
- 持久化已采用 **SwiftData**（42 文件），无 CoreData 残留
- 无 `try!`、无弃用的 `NavigationView`、日志基本使用 OSLog `Logger`

但代码库整体处于**半迁移状态**：新旧模式并存，导致维护成本高、性能未完全释放、并发安全检查覆盖不全。本文档定义把所有地方统一到最先进写法的具体需求。

### 现状扫描结果

| 维度 | 现状 | 目标 |
|------|------|------|
| 状态管理 | 30 个文件用 `ObservableObject`，253 处 `@Published`；21 个文件已用 `@Observable`（半迁移） | 全部 `@Observable` |
| 响应式框架 | 47 个文件依赖 Combine（`sink` / `PassthroughSubject` 等） | 以 `@Observable` + `async/await` + `AsyncStream` 替代 |
| 视图状态注入 | 81 处 `@StateObject/@ObservedObject/@EnvironmentObject` | `@State` / `@Bindable` / `@Environment` |
| 异步风格 | 38 处 `DispatchQueue`、30 处 `@escaping` completion handler | 结构化并发（`async/await`、`Task`、`AsyncStream`） |
| 测试框架 | 30 个 XCTest 文件，仅 1 个 Swift Testing | 迁移到 Swift Testing（`@Test` / `#expect`） |
| Widget 扩展 | `SWIFT_VERSION = 5.0`、`IPHONEOS_DEPLOYMENT_TARGET = 17.6` | 与主 App 一致（Swift 6.0，统一部署目标） |
| 部署目标 | 三值并存：26.0 / 18.6 / 17.6 | 统一 |
| 配置存储 | 103 处直接使用 `UserDefaults` | `@AppStorage` / 类型安全 settings store |

---

## 2. 需求项

### R1 — ViewModel 迁移到 `@Observable`（🔴 高优先级）

**问题**：30 个文件仍使用 `ObservableObject` + `@Published`（共 253 处），与已迁移的 21 个 `@Observable` 文件并存。旧模式依赖框架级依赖追踪，粒度粗、性能差、样板多。

**需求**：
- 将所有 `class X: ObservableObject` 改为 `@Observable class X`。
- 移除全部 `@Published` 标注（`@Observable` 自动追踪存储属性）。
- 不希望被追踪的属性标注 `@ObservationIgnored`。
- 视图侧：`@StateObject` → `@State`；`@ObservedObject` → 直接持有或 `@Bindable`（需要绑定时）；`@EnvironmentObject` → `@Environment`。

**涉及文件（30 个）**：

Managers：
- `Managers/Achievement/AchievementManager.swift`
- `Managers/Health/HealthKitManager.swift`
- `Managers/LLM/LLMClient.swift`
- `Managers/Logging/FPSMonitor.swift`
- `Managers/Study/StudyTimerManager.swift`
- `Managers/Utility/SubjectInfo.swift`

ViewModels（22 个）：
- `AddGradeViewModel` `AutoMindMapViewModel` `BackupRestoreViewModel` `CoachConversationViewModel` `CoachViewModel` `ExamAutopsyViewModel` `ExamSimulationViewModel` `ExamViewModel` `FlashcardStudyViewModel` `HomeAskViewModel` `HomeViewModel` `KnowledgeFaultLineViewModel` `LLMChatViewModel` `MistakeDetailEditViewModel` `MistakeViewModel` `NewExamSetViewModel` `NewMistakeSetViewModel` `SubjectMistakesViewModel` `TodoViewModel` `TrendsViewModel`

Views：
- `Views/Debug/DebugBannerView.swift`
- `Views/Flashcard/FlashcardCalculatorView.swift`
- `Views/LLM/AIDiscussionSheet.swift`
- `Views/Mistake/MistakeDebateSheet.swift`

**验收标准**：
- 项目中 `ObservableObject` 匹配数为 0。
- 项目中 `@Published` 匹配数为 0。
- 视图中不再出现 `@StateObject` / `@ObservedObject` / `@EnvironmentObject`。
- 编译通过，功能行为无回归。

**风险**：`@Observable` 要求 iOS 17+，主 App 已满足；注意 timer/health 等 Manager 的可选绑定与生命周期。

**完成状态**：✅ 已完成。

---

### R2 — 移除 Combine 依赖（🔴 高优先级）

**问题**：47 个文件依赖 Combine（`sink` / `AnyCancellable` / `PassthroughSubject` / `CurrentValueSubject`），多集中在 ViewModel 层做响应式串联。

**需求**：
- `@Published` + `sink` 的响应链 → `@Observable` 属性 + `.onChange(of:)` 或 `withObservationTracking`。
- 事件流 / 多播 → `AsyncStream` / `AsyncSequence`。
- 定时器 Publisher → `Timer` + `AsyncStream` 或 `Task` + `Task.sleep`。
- 移除不再需要的 `import Combine` 与 `AnyCancellable` 集合。

**验收标准**：
- `import Combine` 匹配数降为 0（除非有无法替代的特定 API，需在文档中列明例外）。
- 无 `AnyCancellable` / `PassthroughSubject` / `CurrentValueSubject` / `.sink(` 残留。

**依赖**：建议与 R1 合并推进（同一批 ViewModel）。

**完成状态**：✅ 已完成，无例外项。

---

### R3 — 统一 Widget 扩展的技术基线（🔴 高优先级）

**问题**：`StudyPulseWidgetExtension` 停留在 `SWIFT_VERSION = 5.0` / `IPHONEOS_DEPLOYMENT_TARGET = 17.6`，未享受 Swift 6 严格并发检查；主 App 为 6.0 / 26.0。

**需求**：
- Widget target `SWIFT_VERSION` 升到 `6.0`。
- 统一部署目标策略（当前三值 26.0 / 18.6 / 17.6 并存）：
  - 方案 A：全部拉齐到主 App 的 26.0（最激进、最先进）。
  - 方案 B：主 App 26.0，扩展 18.6（若需兼容更广设备），并记录理由。
- 修复升级后暴露的并发 / 可用性告警。

**验收标准**：
- `project.pbxproj` 中不再出现 `SWIFT_VERSION = 5.0`。
- 部署目标取值收敛为文档明确记录的策略。
- Widget target 在 Swift 6 严格并发下编译通过。

**风险**：需回归测试所有 Widget 尺寸与 Live Activity。

**完成状态**：✅ 已完成，采用方案 A（全部 target 统一为 iOS 26.0）。

---

### R4 — 结构化并发替换遗留异步风格（🟡 中优先级）

**问题**：项目已有 103 文件使用 `async/await`，但仍残留 38 处 `DispatchQueue` 与 30 处 `@escaping` completion handler。

**需求**：
- `DispatchQueue.main.async` → `await MainActor.run { }` 或 `@MainActor` 隔离（多数 UI 更新可省略，因默认 MainActor 隔离已开启）。
- `DispatchQueue.global().async` → `Task.detached` / actor / `Task(priority:)`。
- `@escaping` completion handler API → `async` 函数（必要时保留桥接重载）。
- 检查 24 处 `Task.detached` 是否确有脱离隔离的必要，否则改为普通 `Task`。

**验收标准**：
- `DispatchQueue` 使用降到最低（列明保留项及理由，如第三方桥接）。
- 新增公开异步 API 一律 `async`，不新增 `@escaping` completion。

**完成状态**：✅ 已完成。

- 主应用源码中的 `DispatchQueue` 已清零；UI 延迟改为可取消的
  `Task.sleep(for:)`，系统 completion 回到 UI 时使用
  `Task { @MainActor in ... }`。
- `NewExamSetViewModel.saveExam(onSuccess:)` 已改为
  `async -> Bool`，调用方根据返回值决定是否关闭页面。
- 保留的 `Task.detached` 仅用于明确需要离开默认 MainActor 的磁盘 I/O、
  图片解码 / OCR、JSON 编解码、缓存维护、HealthKit 历史计算和 SwiftData
  快照转换；这些工作均不直接修改 UI 状态。
- 保留的 `@escaping` 均属于 SwiftUI 按钮 / ViewBuilder 闭包、Apple
  delegate / framework completion，或用于上报异步进度的
  `@MainActor @Sendable` 闭包，不再存在公开的 completion 风格业务 API。

---

### R5 — 测试迁移到 Swift Testing（🟡 中优先级）

**问题**：30 个测试文件用旧的 XCTest，仅 1 个使用 Swift Testing。

**需求**：
- 新增测试一律使用 Swift Testing（`import Testing`、`@Test`、`#expect` / `#require`）。
- 存量 XCTest 分批迁移，优先迁移改动频繁、断言简单的用例。
- 利用参数化测试（`@Test(arguments:)`）合并重复用例。

**验收标准**：
- Swift Testing 文件占比逐步提升；CI 同时运行两套框架直至迁移完成。
- 迁移后测试覆盖率不下降。

**完成状态**：✅ 第一批迁移已完成，两套框架继续并行。

- Swift Testing 文件由 1 个增加到 9 个，XCTest 文件剩余 22 个。
- 首批迁移覆盖 BrainUsage、CoachAnalysis、CoachTaskEvaluator、
  DateFormatters、LLMResponseCache、MistakeImageRecognition、
  MistakeShelfLife、QuoteProvider，并保留既有 RecoveryLevel 测试。
- DateFormatters 与 RecoveryLevel 的重复边界用例已改为
  `@Test(arguments:)` 参数化测试。
- 指定 iPhone 17 / iOS 26.5 测试中，9 个 Swift Testing suite、
  31 个测试用例全部通过；同一 test target 同时发现并执行 XCTest 与
  Swift Testing。复杂的 SwiftData、Keychain、性能测试继续保留在
  XCTest，后续按批迁移。

---

### R6 — 配置存储收敛（🟢 低优先级）

**问题**：103 处直接使用 `UserDefaults`，key 以字符串散落各处，缺乏类型安全。

**需求**：
- 视图内简单读写 → `@AppStorage`。
- 跨层配置 → 封装类型安全的 `SettingsStore`（集中 key，配 `@Observable` 或 property wrapper）。
- 消除硬编码字符串 key 重复。

**验收标准**：
- 直接裸用 `UserDefaults.standard.xxx` 的分散调用收敛到统一入口。

---

## 3. 优先级与实施顺序

| 阶段 | 需求 | 说明 |
|------|------|------|
| 阶段 1 | R3 | 改动小、风险低，先统一 Widget 构建配置 |
| 阶段 2 | R1 + R2 | 核心收益，按 ViewModel 逐个迁移（先做 1–2 个样板确认风格，再批量） |
| 阶段 3 | R4 | 清理遗留异步风格 |
| 阶段 4 | R5 | 测试框架迁移，可与其它阶段并行 |
| 阶段 5 | R6 | 配置存储收敛，收尾 |

**建议**：R1 与 R2 合并处理（同一批 ViewModel），单个 ViewModel 一个提交，便于回滚与 review。

---

## 4. 全局验收清单

- [x] `grep -rl ": *ObservableObject" --include="*.swift"` 结果为空
- [x] `grep -rn "@Published" --include="*.swift"` 结果为空
- [x] `grep -rn "@StateObject\|@ObservedObject\|@EnvironmentObject" --include="*.swift"` 结果为空
- [x] `grep -rl "import Combine" --include="*.swift"` 结果为空
- [x] `project.pbxproj` 无 `SWIFT_VERSION = 5.0`
- [x] 部署目标采用方案 A，全部 target 统一为 iOS 26.0
- [ ] `DispatchQueue` / `@escaping` 使用降到最低并列明保留项
- [ ] Swift Testing 覆盖存量测试
- [ ] 全部 target 在 Swift 6 严格并发下编译通过，无功能回归

---

## 5. 已达标项（无需改动）

- ✅ 持久化使用 SwiftData（42 文件），无 CoreData 残留
- ✅ 无 `try!`；调试输出基本走 OSLog `Logger`（12 文件）
- ✅ 无弃用的 `NavigationView`
- ✅ `@MainActor` 覆盖 131 文件，并发注解基础到位
- ✅ 主 App 已开启 `SWIFT_APPROACHABLE_CONCURRENCY` 与默认 MainActor 隔离
