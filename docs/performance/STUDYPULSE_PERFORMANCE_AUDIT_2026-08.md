# StudyPulse 性能审计报告

审计日期：2026-08-14  
项目：StudyPulse iOS / SwiftUI / SwiftData  
审计类型：静态代码审计 + Release 构建验证尝试  

## 结论先行

StudyPulse 的性能基础是合格的：高频数据已经有 `@ModelActor` 持久化边界、分页读取、索引、图片下采样缓存、signpost 和 DEBUG 性能面板。对于个人学习应用的常规数据量，主页、趋势和计时器没有看到必然严重卡顿的结构性问题。

但当前实现的“扩展性”只有中等。数据量增长后，最可能先暴露的是：

1. 启动阶段仍有多个 Repository 在 `@MainActor` 上做同步 SwiftData fetch 和 JSON 解码。
2. 学习会话、Coach 历史、考试计划等数据以整条 JSON payload 加载，历史越多，启动时间和内存越高。
3. 若干更新操作会先全表 fetch，再逐条保存；批量绑定学习会话时尤其明显。
4. 首页的 dirty flag 能跳过重算，但计算输入签名本身仍会遍历大部分历史数组。

静态评级：

- 常规交互：良好
- 启动性能：中等，受历史数据规模影响
- 持久化扩展性：中等偏弱
- SwiftUI 重绘控制：中等偏良好
- 性能可观测性：良好
- 性能回归测试：偏弱

这不是一次真实设备 benchmark，因此不能从本报告直接得出“启动耗时多少毫秒”或“内存多少 MB”。最终数值需要在 Release 配置、真实 iPhone/iPad 和分层 fixture 数据上测量。

## 审计范围与验证状态

检查了以下路径：

- App 启动和 `RepositoryContainer.asyncInit`
- SwiftData schema、索引和 `PersistenceExecutor`
- 高频 Repository 的读写队列
- Coach、StudySession、TimeInvestment、ExamPlan 等低频 Repository
- Home / Trends / Todo / Mistake 的派生数据和集合重算
- 计时器、图片、日志、FPS/卡顿监测
- Xcode Release/Debug 构建设置与现有测试

已执行的验证：

- Xcode 版本：26.6（Build 17F113）
- 可用 iOS Simulator：26.5；另有一个 iOS 27.0 已启动设备
- 第一次 `xcodebuild -list` 受到用户已有 DerivedData/SourcePackages 缓存目录冲突影响
- 随后使用独立的临时 DerivedData 和 SourcePackages 目录重新执行 Release Simulator build，依赖解析成功，最终 `** BUILD SUCCEEDED **`
- Release 构建只有一个非性能相关 warning：`StudyPulse/Services/TimeInvestmentEngine.swift:91` 的 `calendar` 可以由 `var` 改为 `let`
- `xcodebuild test` 成功启动测试流程并输出 `Testing started`，但在测试收尾阶段长时间阻塞于 `waiting for record to finish saving` / `Blocking finish to clean up test session`；本次主动中止，未得到测试 pass/fail 结果，因此不把它当作代码测试失败
- 仓库中有 47 个测试源文件，其中 33 个包含测试方法；目前只有 `BackupTests.testLargeJSONLPerformance` 使用 `measure {}`

## 做得比较好的地方

### 高频持久化边界清晰

`PersistenceExecutor` 使用 `@ModelActor`，并以 `Sendable` value snapshot 返回数据，避免把 `@Model` 实例或 `ModelContext` 穿过并发边界。见 `StudyPulse/Repositories/Persistence/PersistenceExecutor.swift:12-52`。

它还提供了：

- `fetchLimit` 分页读取
- 批量插入时的取消检查
- 写入队列串行化
- `OSSignposter` 对启动读取和主要 mutation 做区间记录

这是当前性能架构中最值得保留的部分。

### SwiftData 索引覆盖了主要过滤维度

成绩、错题、考试、任务、例程和日记都有日期/phase 等索引；错题额外有 SRS 下次复习日期索引。见 `StudyPulse/Models/SwiftData/StudyPulseModels.swift:94-220`、`438-716`、`1389-1610`。

### 图片路径考虑了解码成本

错题图片使用 `.externalStorage`，列表详情通过 `CGImageSourceCreateThumbnailAtIndex` 做下采样，并由 `ImageCache` 缓存缩略图。见 `StudyPulse/Models/SwiftData/StudyPulseModels.swift:260-278`、`StudyPulse/Managers/Utility/ImageCache.swift:98-129`、`StudyPulse/Views/Mistake/MistakeSetDetailView.swift:278-309`。

### 有实际的性能观测入口

`LagMonitor` 通过 `CADisplayLink` 记录主线程丢帧，DEBUG 性能面板展示 FPS、内存和卡顿事件。见 `StudyPulse/Managers/Logging/LagMonitor.swift:20-102`、`StudyPulse/Views/Debug/PerformancePanelView.swift:20-45`。

### 计时器的系统通信已经节流

计时器 UI 以 1 Hz 更新剩余时间，但 Live Activity 约每 5 秒才推送一次，避免不必要的跨进程通信。见 `StudyPulse/Managers/Study/StudyTimerManager.swift:450-475`。

### Release 构建使用 Whole Module Optimization

Release 配置使用 `SWIFT_COMPILATION_MODE = wholemodule`；Debug 使用 `-Onone`，符合开发与发布用途。见 `StudyPulse.xcodeproj/project.pbxproj:395-521`。

## 需要优先处理的问题

### P1：启动期仍存在 MainActor 同步 fetch

`RepositoryContainer.asyncInit` 本身位于 `@MainActor`，并按顺序加载 phase、profile、subject、routine、routine instance、diary、Coach、session、time investment、autopsy、simulation 和 plan。见 `StudyPulse/Repositories/RepositoryContainer.swift:186-214`。

其中一部分 Repository 的 `loadAll` 虽然声明为 `async`，但实际直接在当前 actor 执行同步的 `context.fetch` 和 JSON 解码：

- `DefaultCoachRepository.loadAll`：一次性 fetch 五类 Coach 历史，见 `StudyPulse/Repositories/Default/DefaultCoachRepository.swift:13-20`
- `DefaultStudySessionRepository.loadAll`：迁移后完整 reload 所有学习会话，见 `StudyPulse/Repositories/Default/DefaultStudySessionRepository.swift:10-14`、`68-73`
- `DefaultTimeInvestmentRepository.loadAll`：完整加载三个实体集合，见 `StudyPulse/Repositories/Default/DefaultTimeInvestmentRepository.swift:16-27`

这意味着 `await` 不等于已经离开主线程。数据少时感觉不到，数据多时会直接延长首屏等待或造成启动卡顿。

建议：

1. 把所有启动读取统一收口到 `PersistenceExecutor` 或独立的 `@ModelActor` snapshot loader。
2. 首屏只加载 Home 必需数据；Coach 历史、考试模拟、Autopsy、完整学习会话改为进入对应页面时再加载。
3. 继续只向 MainActor 发布不可变 snapshot。

### P1：历史数据以 JSON payload 全量解码，增长后会同时放大 CPU 和内存

`StudySessionRecord` 将整个 `StudySession` 编码到 `payload`，包括心率样本和难度标注；启动时 `DefaultStudySessionRepository.reload` 会把全部记录 decode 成数组。见 `StudyPulse/Models/SwiftData/StudyPulseModels.swift:917-929`、`StudyPulse/Repositories/Default/DefaultStudySessionRepository.swift:68-73`。

Coach message/chat、考试模拟、ExamGoal 和 ExamPlan 也采用同类 payload 模式，并在启动时全量 compactMap decode。见 `StudyPulse/Models/SwiftData/StudyPulseModels.swift:842-929`、`1073-1125`。

风险表现：

- 会话越多，启动读取和 JSON decode 线性增长
- 每个 payload 的完整副本会进入内存 snapshot
- 仅需要“最近 30 天”或“最近一条”的页面，也会付出全历史成本

建议：

- 为列表页提供带 `fetchLimit` 的 summary snapshot；详情页再按 id 加载完整 payload
- 学习会话按日期窗口读取，完整心率样本只在详情页读取
- 高频筛选字段保留为独立列，避免为了 phase/date/target 读取并 decode payload
- 对 Coach message 使用按 chat/goal 的 predicate，而不是启动时加载所有 message

### P1：批量写入存在全表扫描和重复 save

`DefaultStudySessionRepository.assign` 对每个 session 调用 `upsert`；而 `upsert` 每次都 fetch 全部 `StudySessionRecord`，再立即 `context.save()`。见 `StudyPulse/Repositories/Default/DefaultStudySessionRepository.swift:38-55`、`16-26`。

类似模式还出现在：

- Coach 的 goal/chat/message 更新：全表 fetch 后 `first(where:)`，每次 mutation 都 save，见 `StudyPulse/Repositories/Default/DefaultCoachRepository.swift:28-39`、`57-79`、`101-128`
- TimeInvestment subject/subTask/reward 更新：全表 fetch 后 `first(where:)`，见 `StudyPulse/Repositories/Default/DefaultTimeInvestmentRepository.swift:29-85`

复杂度和 I/O 影响：

- 单条更新：接近 O(n) 查找，而不是按 id 的索引查询
- 批量更新 k 条：可能变成 O(k×n)，并产生 k 次持久化 save
- 存储层每次 save 都可能触发磁盘写入和事务开销

建议：

1. 用 `FetchDescriptor` + `#Predicate { $0.id == id }` 做单条查找。
2. 提供批量 `upsert` API，在一个 actor operation 中完成全部 insert/update，最后只 save 一次。
3. `assign` 先构造变更后的 session 数组，再交给批量 API。
4. 对需要频繁按 id 访问的 in-memory snapshot 建立 `[UUID: Int]` 或 `[UUID: Snapshot]` 索引，减少 `firstIndex`。

## 中优先级问题

### P2：高频启动读取会重复读取同一实体

`loadHighFrequencySnapshots` 会先读取 grades、mistakes、exams、comprehensive exams、tasks 的完整集合；当存在 active phase 时，又分别再 fetch 一套 phase-filtered 集合。见 `StudyPulse/Repositories/Persistence/PersistenceExecutor.swift:49-89`。

这会造成：

- 额外的 fetch 次数
- 同一 payload 或 record 被转换两次
- full snapshot 与 filtered snapshot 同时驻留内存

如果大多数页面只需要当前 phase，可以考虑只读取一次完整 snapshot 后在 actor 内过滤；如果必须同时保留全量数据，则应让 filtered 结果只保留 id/索引或使用按用途的缓存策略。需要用真实数据量比较“数据库 predicate”与“内存过滤”的实际成本后决定。

### P2：phase 切换会顺序执行六次 filtered reload

`PhaseFilterRefresher.recomputeAll` 依次 await grade、mistake、exam、task、routine、diary 六个 reload。见 `StudyPulse/Repositories/PhaseFilterRefresher.swift:82-100`。

phase 切换不是高频操作，因此这不是首要瓶颈；但在大数据量下会让用户感到切换后页面逐段更新。建议提供一个 actor 内的 grouped read，或用已经加载的 full snapshots 在内存中一次过滤，并在同一 MainActor 更新批量结果。

### P2：首页 dirty flag 仍需遍历大数组

Home 已经用 signature 避免重复完整重算，但 `recomputeSignature` 仍遍历成绩、错题、考试、任务、例程实例、学习会话、日记和健康历史。见 `StudyPulse/ViewModels/HomeViewModel.swift:219-295`。

同时，Home 挂载了多个独立的 `onChange` 触发器。见 `StudyPulse/Views/Home/HomeRecomputeModifier.swift:27-115`。

因此当前优化解决的是“重复计算”，没有完全解决“重复扫描”。建议：

- Repository 提供单调递增的 change token/version，而不是每次对全部元素做 hash
- 将 Home 派生数据拆成按领域的缓存：成绩变更不必重算健康趋势
- 对连续通知做一个 RunLoop/短时间 debounce
- 为每张重型卡片维护独立的输入版本

### P2：Todo 例程聚合存在可避免的 O(instance×routine) 查找

`TodoAggregator.entries` 先构造 `allowedRoutineIds`，但随后对每个 instance 使用 `routineRepo.filteredRoutines.first { ... }` 查找对应 routine。见 `StudyPulse/Repositories/TodoAggregator.swift:100-143`。

应在函数开头构造 `[UUID: Routine]` 字典，随后 O(1) 查找。该改动简单、风险低，适合作为第一批优化。

### P2：聊天附件在 View body 中重复解码 UIImage

`ChatBubble` 在每次 body 计算时对 attachment 执行 `UIImage(data:)`。见 `StudyPulse/Views/LLM/ChatBubble.swift:128-137`。

图片少时影响很小；长对话、滚动或流式输出期间会重复发生。建议复用 `CachedAsyncImage`/`ImageCache`，或将 attachment 解码放入按 id 缓存的 `@StateObject`/专用缩略图 View。

### P3：日志和 DEBUG 浮层有低成本可优化项

`Log.record` 每次创建 `Logger`，再创建一个 Task 把事件交给 `LogStore`；见 `StudyPulse/Managers/Logging/Log.swift:269-280`。`LogStore` 超过 5,000 条时调用 `removeFirst`，会搬移剩余数组元素；见 `StudyPulse/Managers/Logging/Log.swift:101-104`。

DEBUG 浮层每秒读取完整日志数组和内存指标，见 `StudyPulse/Views/Debug/DebugFPSOverlayView.swift:27-37`。这些不属于生产首要瓶颈，但在 verbose logging 或卡顿诊断期间可能放大自身开销。

建议将 LogStore 改为环形缓冲或双端队列，并让 DEBUG 浮层只读取 count/最近卡顿摘要，而不是每秒复制全部 entries。

## 算法和 UI 层面的判断

现有 `SubjectAggregator`、`TimeInvestmentEngine` 等服务已经倾向于单次聚合；这比在 View 中反复过滤整个数组好。趋势页也先按 subject 分组再排序，见 `StudyPulse/ViewModels/TrendsViewModel.swift:61-103`。

计时器的 1 Hz 更新是合理的，因为倒计时文本确实需要更新；真正需要用 Instruments 验证的是活动中的 ring、shadow、gradient、glass 和 numeric transition 组合，而不是先凭代码判断它一定慢。应在低端 iPhone 和 iPad 分别检查滚动/切页时的 hitch rate。

## 建议的修复顺序

### 第一批：低风险、高收益

1. `TodoAggregator` 使用 routine 字典。
2. StudySession `assign` 改成批量 upsert、一次 save。
3. Coach/TimeInvestment 的按 id 更新改为 predicate fetch。
4. Chat attachment 接入缩略图缓存。
5. 为 `RepositoryContainer.asyncInit`、每个 Repository load、Home recompute 增加统一耗时统计。

### 第二批：解决数据规模增长问题

1. 将 Coach、StudySession、ExamSimulation、ExamPlan 的启动读取改为懒加载或 recent-window loading。
2. 在 `PersistenceExecutor` 中增加 summary/detail 两级读取 API。
3. 将低频 Repository 也迁移到 background `@ModelActor` snapshot 读取。
4. 用 change token 替代 Home 对全部数组的 signature 扫描。

### 第三批：基于 Instruments 决定是否做

1. 对计时器动画和 Home 卡片做 SwiftUI body/update 调查。
2. 对图片和 Markdown/LaTeX 页面做 Allocations、Core Animation 和 Time Profiler 检查。
3. 根据真实内存曲线决定是否进一步拆分 payload 或减少全量缓存。

## 建议补充的性能测试矩阵

增加一个独立的性能测试目标或 performance test suite，使用固定 fixture 分别测试 100、1,000、5,000 条成绩/错题/学习会话：

- `asyncInit` 总耗时，以及 `isReady` 前的 MainActor 阻塞时间
- 启动峰值 RSS / `phys_footprint`
- phase 切换到所有 filtered cache 完成的 p50/p95
- 单条 grade/mistake/session 更新耗时
- 批量绑定 10/100/1,000 个 session 的耗时和 save 次数
- Home `recompute` 的耗时及 signature 扫描耗时
- Todo 聚合耗时
- 错题列表和聊天列表滚动期间的 FPS/hitch rate

建议目标值（用于建立回归门槛，不是当前实测值）：

- 常规 fixture 下，首屏数据 ready p95 < 1 秒
- 1,000 条历史数据下，phase 切换 p95 < 250 ms
- 100 条 session 批量绑定不超过一次 durable save
- 生产页面不因 DEBUG 性能浮层或日志采集产生可观测额外卡顿

## 最终判断

当前代码不是“普遍很慢”，而是“常规规模表现有希望，历史规模的持久化路径需要尽快收敛”。最优先的性能收益不会来自微调 SwiftUI modifier，而来自三件事：

1. 把启动期低频数据移出 MainActor 和首屏路径。
2. 把全表扫描/逐条 save 改成按 id、批量、一次事务。
3. 把全历史 JSON payload 解码改成 summary/detail 和按窗口读取。

完成这三类改动后，再用 Instruments 和 fixture benchmark 验证动画与卡片重算，才能把性能从“架构上看起来合理”提升到“有数字保障”。
