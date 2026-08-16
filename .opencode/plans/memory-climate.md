# Memory Climate 执行计划（阶段一 + 阶段二）

> 依据：docs/product/MEMORY_CLIMATE_SPEC_CN.md
> 范围（用户已确认）：阶段一（规格对齐）+ 阶段二（15 分钟补救任务），不含阶段三趋势洞察
> 分支：feature/memory-climate（已创建）

## 0. 现状盘点（P0 已完成约 90%）

已存在且符合规格：
- `StudyPulse/Services/MemoryClimateEngine.swift`：纯函数、无 SwiftUI/I/O，5.3 全部阈值集中定义（negativeWindowDays=30 / humidWindowHours=48 / frozenDays=21 / overdueGraceDays=7）
- `StudyPulse/Models/MemoryClimate.swift`：`MemoryWeather` / `ConceptInterference` / `SubjectMemoryClimate` / `MemoryClimateSnapshot`，nonisolated value type
- `StudyPulse/Managers/Study/MemoryClimateHistoryStore.swift`：版本化 JSON（Envelope v1）、同日同阶段 upsert 覆盖、90 天裁剪、损坏静默降级
- `StudyPulse/Views/Home/HomeCards/MemoryClimateCard.swift`：主页卡片（空态隐藏、Top-4 chips、主科目+图标+摘要）+ 详情 sheet（今日状态 / 90 天热力图（含 a11y label）/ 证据热点 / 开始复习 / 无数据说明）
- `StudyPulse/Services/ClimateInterleavingEngine.swift`：到期卡优先 + ≤25% 且 ≤3 张对照卡 + `earlyContrast` 来源标记 + 退化回退
- `StudyPulse/ViewModels/FlashcardStudyViewModel.swift`：earlyContrast 评分不动 SRS 日期、正常卡走 SM-2、评分后刷新气候历史
- 接线：`HomeViewModel`（生成快照 + upsert 历史 + 按 phase 过滤）、`StudyPulseApp.refreshMemoryClimate()`、`HomeView` 卡片渲染、`HomeCardType.memoryClimate` 默认启用
- 本地化：`StudyPulse/Localizable.xcstrings` 中 23 个 `memory.climate.*` key × 5 语言齐全
- 已有测试：`StudyPulseTests/MemoryClimateTests.swift`（五类天气、雷暴双侧证据、近期成功不覆盖雷暴、新题忽略、阶段隔离、upsert/裁剪、损坏兜底、交错插入、earlyContrast VM 行为）

## 1. 阶段一：规格对齐

### 1.1 风险排序修复（已完成，随分支保留）

`MemoryClimateEngine.classify` 原判定顺序：thunderstorm → southHumid → frozen → fog/clear。
规格 4.1 风险序为 thunderstorm(5) > frozen(4) > fog(3) > southHumid(2) > clear(1)。
若科目中位未调用 ≥21 天（冻结证据）又恰在 48h 内刚答对，原逻辑会误判为 southHumid。

已应用 diff（保留在分支工作区）：
```
- } else if recentlySucceeded && (averageMastery < 0.7 || medianRepetitions < 2 || hadRecentLapse) {
-     weather = .southHumid ...
  } else if isFrozen {
+     // 冻结优先于湿热：按规格 4.1 的风险序
      weather = .frozen ...
+ } else if recentlySucceeded && (... ) {
+     weather = .southHumid ...
```

### 1.2 补 §13 边界测试（MemoryClimateTests.swift 追加）

新增 5 个测试方法：
1. `testClearBoundaryAtMasterySeventy`：掌握度恰 0.70 + 最近两次稳定 + 逾期 <0.2 → `.clear`；0.69 → `.fog`
2. `testThunderstormBoundaryAtExactlyThreeNegativeRetrievals`：双侧各 ≥1、总数恰 3 → `.thunderstorm`（count==3）；仅 bridge（总 2）→ 否
3. `testFrozenBoundaryAtTwentyOneDays`：daysOld=21 → `.frozen`；20.999 → 被忽略（无状态）
4. `testSouthHumidBoundaryAtFortyEightHours`：成功恰在 48h（daysAgo=2.0）→ `.southHumid`；2.0001 → `.fog`
5. `testInterleavingFallsBackToPlainQueueWhenNoContrast`：空 due → 空；无雷暴 → 全 scheduled；雷暴但无非到期/概念匹配卡 → 全 scheduled

## 2. 阶段二：15 分钟补救任务

### 2.1 模型：Models/MemoryClimate.swift 新增

```swift
nonisolated enum RemediationStrategy: String, Codable, Hashable, Sendable {
    case interference   // 雷暴：概念交错
    case overdue        // 冻结：最早逾期/最长未调用
    case weakSpot       // 雾：最近答错/最低掌握度
}

nonisolated struct RemediationTask: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let subject: String
    let weather: MemoryWeather        // 触发任务的天气（thunderstorm/frozen/fog）
    let strategy: RemediationStrategy
    let mistakes: [MistakeNote]       // 任务卡片
    let estimatedMinutes: Int         // 上限 15
}
```
说明：MistakeNote 已是 value type 可持有；任务仅内存使用，不持久化（但保持 Codable 规范）。

### 2.2 生成器：新增 StudyPulse/Services/RemediationTaskEngine.swift

纯函数 enum，常量集中定义：
- `maxDurationMinutes = 15`
- `estimatedMinutesPerCard = 2.0` → 卡片上限 `maxCards = 7`（15/2 向下取整）

`static func generate(snapshot: MemoryClimateSnapshot, mistakes: [MistakeNote], now: Date, calendar: Calendar) -> RemediationTask?`

规则：
- 取 `snapshot.dominantSubject`；weather 仅限 thunderstorm/frozen/fog，否则返回 nil
- 雷暴（.interference）：取最强干扰对（interferences.first），候选 = 该科目下含两概念任一的错题，优先近期负向证据（30 天内 again/hard），两概念卡片交错排列，最多 maxCards 张
- 冻结（.overdue）：候选 = 最早逾期（reviewState.nextReviewDate ≤ now）优先，其次最长未调用（date 最早/掌握历史最后时间最旧），最多 maxCards 张
- 雾（.weakSpot）：候选 = 最近一次答错（masteryHistory 最近 again/hard 时间最新）或掌握度最低（masteryScore 升序），最多 maxCards 张
- 排序确定：主排序键稳定、次键 mistake.id.uuidString（防重复键/不稳定排序）
- 无候选或全部卡数 0 → 返回 nil（入口隐藏，保留普通复习按钮）
- 不触碰 SRS/成绩/成就：纯选择，副作用由闪卡流程承担

### 2.3 闪卡接入：FlashcardFilter 新增分支

`Views/Flashcard/FlashcardStudyView.swift` 的 `enum FlashcardFilter`：
- 新增 `case remediation([MistakeNote])`
- `==`、`shortLabel`（"15min".localized()）、`isSingleMode`（false）同步扩展
- `FlashcardStudyViewModel.loadQueue()`：`.remediation(let notes)` → `queue = notes.map(FlashcardQueueItem.scheduled)`，保持正常 SM-2（handleRating 的 `.dueQueue, .tag` 分支已走 SRS，remediation 并入该分支）
- `again` 重抽沿用队列模式逻辑（reinsertQueue）
- `MistakeViewModel.flashcardFilter` / `MistakeToolbar` 无需改动（仅新增 case，switch 无遗漏点需逐一核对）

### 2.4 详情页入口：MemoryClimateCard.swift 的 MemoryClimateDetailView

- 在 reviewButton 上方新增补救入口区（仅 `RemediationTaskEngine.generate(...) != nil` 时显示）：
  - Button「15 分钟补救」→ `FlashcardStudyView(container:, filter: .remediation(task.mistakes))` 全屏 push（NavigationStack 内已有，用 `.navigationDestination` 或 sheet 打开，与现有 onStartReview 模式一致）
  - 副文案：预计时长 + 策略说明（"优先覆盖：概念对照/最早逾期/薄弱点"）
- 传入数据：详情页已有 `snapshot` + `history`，还需错题列表——由 HomeView 调用处追加传参 `mistakes: viewModel 的 filteredMistakeSets`（HomeView.swift:311 与 526 两处调用点同步）

### 2.5 本地化：Localizable.xcstrings 新增 ~6 key × 5 语言

- `memory.climate.remediation.button`（15 分钟补救）
- `memory.climate.remediation.estimatedMinutes`（预计约 %d 分钟）
- `memory.climate.remediation.strategy.interference`（优先覆盖：概念对照）
- `memory.climate.remediation.strategy.overdue`（优先覆盖：最早逾期内容）
- `memory.climate.remediation.strategy.weakSpot`（优先覆盖：薄弱知识点）
- `memory.climate.remediation.cancel`（跳过/取消，不跳成就——文案"不记录成就"可选）

### 2.6 单元测试：MemoryClimateTests.swift 追加 RemediationTaskEngineTests

- 科目选择：最高风险 ∈ {thunderstorm/frozen/fog} 才生成；clear 最高 → nil
- 时长上限：卡数 ≤ 7；候选超过 7 时截断且取最优先
- 雷暴策略：选中的卡片覆盖干扰对两概念；优先近期负向证据卡
- 冻结策略：最早逾期卡在列；无逾期时取最长未调用
- 雾策略：最近答错/最低掌握度卡在列
- 空结果：候选为空 → nil
- 确定性：相同输入两次生成结果相同
- 阶段隔离：仅使用 snapshot 内当前阶段科目（引擎只消费传入 snapshot + mistakes，天然隔离）

## 3. 验证

1. `./scripts/build.sh`（Debug，iPhone 17 模拟器）构建通过
2. 单元测试：`xcodebuild test -scheme StudyPulse`（仅跑 MemoryClimateTests 相关亦可，见 AGENTS.md「不需要运行 Test」——此处以构建为准，测试用 Xcode 或 CLI 按需）
3. 更新 `AGENTS.md`：
   - Services 目录新增 `RemediationTaskEngine.swift`
   - 7.x 记忆气候子系统段落补充补救任务说明（模型/引擎/入口/本地化 key 命名空间）
   - HomeCard 段落提及详情页补救入口
4. 本地化自查：新增 key 在 5 语言均存在，`Text("...".localized())` 带括号

## 4. 不在本次范围

- 阶段三：趋势洞察（连续 N 天降温、与考试/成绩融合、本地通知）—— 后续迭代
- 成就系统改动（补救任务完成/取消不计数，零侵入）
- 新增 SwiftData 实体或通知权限

## 5. 已知风险

- FlashcardFilter 新增 case 需核对所有 switch/模式匹配点（VM loadQueue、handleRating、==、shortLabel、isSingleMode），避免编译期漏判
- HomeView 两处 MemoryClimateCard 调用点需同步追加 mistakes 参数
- 详情页补救入口的导航方式需与现有 sheet/push 结构兼容（MemoryClimateCard 内 sheet → push FlashcardStudyView）
