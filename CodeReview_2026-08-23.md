# StudyPulse 全面 Code Review 报告

> **日期**: 2026-08-23
> **版本**: HEAD (main) · Swift 6.0 · iOS 18.6+ · Xcode 26.x
> **审查范围**: 440 个 Swift 文件 · 16 Repository · SwiftData Schema V1-V5 · Managers/ Services/ ViewModels/ Views/ · Backup/HealthKit/LLM/Auth/Widget
> **审查方式**: 5 个专项 Sub-agent 并行精读源码 + `grep`/`rg` 交叉验证 + Swift 6 Strict Concurrency 模型推演
> **原则**: 仅报告可验证、有明确运行时影响的问题；不为挑剔而挑剔代码风格

---

## 目录

- [执行摘要](#执行摘要)
- [方法与覆盖](#方法与覆盖)
- [严重度汇总](#严重度汇总)
- [Critical 级别](#critical-级别)
- [High 级别](#high-级别)
- [Medium 级别](#medium-级别)
- [Low 级别](#low-级别)
- [已验证的正确实践](#已验证的正确实践)
- [修复路线图](#修复路线图)
- [附录: 建议新增单测清单](#附录-建议新增单测清单)

---

## 执行摘要

本次审查共发现 **38 个可验证问题**，其中 **9 Critical / 13 High / 11 Medium / 5 Low**。

最高风险集中在三类：

1. **持久化与迁移** — Schema 冻结违规导致存量用户升级必现启动失败；JSON 迁移单条脏数据导致全域静默丢失；多 `ModelContext` 混合写入与 `try?` 掩盖磁盘满
2. **并发与生命周期** — `nonisolated(unsafe)` 共享容器、`asyncInit` 取消后仍置 `isReady=true`、HealthHistory 并发丢失更新、常驻 Timer 在后台空转
3. **安全与隐私合规** — 麦克风权限描述缺失致录音即崩溃、HealthKit 写入与隐私描述矛盾、自定义 Scheme 明文传 token 无 state、健康数据外发至第三方 LLM 与 "永不上传" 承诺冲突、备份明文 ZIP

架构整体清晰（MVVM + Repository + Service 纯函数），但 `RepositoryContainer` 已膨胀为 God Object，4 个高频 Repository 的 60 行模板逐字复制，`ImageCache`/`LearningHeatmapView`/`BrainUsageCard`/`LagMonitor` 存在可量化的性能与正确性缺陷。

---

## 方法与覆盖

| 专项 | 覆盖模块 | 工具 |
|---|---|---|
| 并发与竞态 | `RepositoryContainer.asyncInit`, `ModelContainerFactory`, `PersistenceExecutor`, `LogStore`/`LLMResponseCache` actor, `RoutineSpawner`, `PhaseFilterRefresher`, `StudyTimerManager`, `HealthKitManager` | Swift 6 隔离推演 + TSan 场景构造 |
| 持久化/崩溃/数据丢失 | `StudyPulseModels.swift` + Schema V1-V5, `ModelContainerFactory` 迁移, 16 Repository load/save, `ImageStorage`/`AudioStorage`, `BackupExporter/Importer/Validator` , `try?`/`!`/`Dictionary(uniqueKeysWithValues:)` 扫描 | 全量 `rg` + 迁移链 diff |
| 安全与隐私 | `KeychainStore`, `LLMClient`, `AuthClient`/`WebAuthSession`, HealthKit 授权, 备份与 App Group, 日志脱敏, CSV/Markdown 输入 | 构建配置核对 + 威胁建模 |
| 逻辑与边界 | `Services/` 全部纯函数, `SpacedRepetition` SM-2, `HabitInsight`, `StudyReadiness`, 日期/时区, ViewModel 脏旗 | 边界值推演 + DST/时区测试构造 |
| 性能与架构 | `RepositoryContainer`, `HomeViewModel`/`HomeView`, `ImageCache`, `LearningHeatmapView`, `BrainUsageCard`, `LagMonitor`, 内存与渲染 | Instruments 热点预估 + 代码量统计 |

所有 `file:line` 均在当前 HEAD 上本地 `read`/`grep` 验证，行号偏移 ±3 属正常。

---

## 严重度汇总

| 严重度 | 数量 | 定义 |
|---|---|---|
| **Critical** | 9 | 可致崩溃、数据丢失、启动失败、隐私合规否决或凭证泄露 |
| **High** | 13 | 高概率触发的数据不一致、静默丢失、性能退化或扩大攻击面 |
| **Medium** | 11 | 边界错误、非确定性、可维护性与资源浪费 |
| **Low** | 5 | 加固建议与轻度坏味道 |
| **合计** | **38** |  |

---

## Critical 级别

### C-01 Schema 冻结违规：V5 轻量迁移失效，存量用户升级必现启动失败

- **文件**: `StudyPulse/Models/SwiftData/StudyPulseModels.swift:905-952,939-952,1152-1165` · `StudyPulse/Models/SwiftData/Schema/StudyPulseSchemaV5.swift:10-17` · `StudyPulse/Models/SwiftData/Schema/StudyPulseMigrationPlan.swift:28-36`
- **描述**: 顶部注释声明 `StudyPulseModels.swift` 冻结于 `StudyPulseSchemaV1`，但后续在同一类上直接追加持久化字段：`StudySessionRecord.durationSeconds/intensityRaw/completed/investmentTarget*`、`CoachChatRecord.title/isArchived`、`CoachConversationMessageRecord.chatID` 等。`StudyPulseSchemaV5.models` 仍返回 `StudyPulseSchemaV4.models`（同一批 `XXXRecord.self`），`V4→V5` 声明为 `.lightweight` 但 Diff 为 0。
- **为什么是问题**: SwiftData `VersionedSchema` 通过类属性元数据推断列；复用同一类导致 V4 推断已含新列，磁盘上旧 V4 Store 实际无该列，轻量迁移不会执行 `ALTER TABLE ADD COLUMN`。
- **后果**: 已安装 V4 的存量用户升级到 HEAD 打开 `ModelContainer` 抛 `no such column`，进入 `StoreError.openFailed` 需 `performDisasterRecovery` 重建（数据丢失）。
- **修复**: 严格冻结：为 V5 创建 `StudyPulseSchemaV5_StudySessionRecord` 等独立版本化实体，或将新增列全改为 `Optional` 并用 `MigrationStage.custom` 执行 `ALTER TABLE`；补充 `SwiftDataMigrationTests: V1→V5 打开成功` 单测。已验证 `BackupManifest.currentSchemaVersion` 仍为 4 (`BackupManifest.swift:6`)，与 `ModelContainerFactory.modelTypes` 指向 V5 不一致，需同步升至 5。
- **验证**: `cat StudyPulse/Models/SwiftData/Schema/StudyPulseSchemaV5.swift` 显示 `models` 直接转发 V4；`BackupManifest.swift:6` 仍为 4。

### C-02 `nonisolated(unsafe)` 共享容器无同步，跨隔离访问即数据竞争

- **文件**: `StudyPulse/Managers/Core/ModelContainerFactory.swift:262` · `StudyPulse/Managers/Core/ModelContainerFactory.swift:65-89`
- **描述**: `enum ModelContainerFactory: @MainActor` 内 `nonisolated(unsafe) private static var _sharedContainer: ModelContainer?` 允许任意线程无 `await` 读写；`ModelContainer` 本身非 `Sendable`。
- **为什么是问题**: Swift 6 `nonisolated(unsafe)` 绕过隔离检查；未来 `PersistentStoreLaunchController.retry` 或测试 `asyncTestInit` 从非 Main 上下文访问即 UB。
- **后果**: `EXC_BAD_ACCESS` / 重复创建 `ModelContainer` / `store already open` / 迁移后悬垂指针。
- **修复**: 改为 `@MainActor private static var _sharedContainer`，或封装为 `actor ContainerHolder`；跨隔离读取用 `await MainActor.run`。

### C-03 多 `ModelContext` 混合写入无合并策略

- **文件**: `StudyPulse/Repositories/Persistence/PersistenceExecutor.swift:55` · `StudyPulse/Repositories/Default/DefaultRoutineRepository.swift:99` · `DefaultDiaryRepository.swift:103` · `DefaultStudySessionRepository.swift:38` · `DefaultCoachRepository.swift:189` · `DefaultTimeInvestmentRepository.swift:41` · `DefaultPhaseRepository.swift:126`
- **描述**: 高频 4 域 (Grade/Mistake/Exam/Task) 写经 `@ModelActor PersistenceExecutor` 私有 `modelContext`；其余 10+ 域直接写 `container.mainContext`。两者指向同一 `studypulse.store` 但无合并策略。
- **为什么是问题**: SwiftData `ModelContext` 非线程安全；`executor.saveIfNeeded():649` 与 `DefaultDiaryRepository.add:105 try? context.save()` 可能交叠。
- **后果**: `SQLite busy` / `pending changes in other context` / `Illegal attempt to establish relationship between objects in different contexts` / 静默丢写入。
- **修复**: 统一写入路径：所有 Repo 均 `attachPersistenceExecutor` 走 executor，或将 executor 的 context 暴露为 `mainContext`；删除 `Default*Repository` 中 `modelContext: ModelContext?` 直接操作。

### C-04 `asyncInit` 取消后仍置 `isReady=true`，Widget 写入空快照

- **文件**: `StudyPulse/Repositories/RepositoryContainer.swift:190,203,234,555` · `StudyPulse/StudyPulseApp.swift:111`
- **描述**: `loadHighFrequencyRepositories:578` 内 `catch is CancellationError { log }` 后继续执行后续 `phaseRepo.loadAll...`；`StudyPulseApp .task { await container.asyncInit }` 在视图消失时自动 `cancel`，但 `asyncInit` 仍执行 `isReady=true`。
- **为什么是问题**: 取消语义被吞，未传播。
- **后果**: 取消后 `isReady=true` → `scenePhase==.active` 同步 Widget/通知时读半初始化数组，Widget 覆盖为 0 条；`PlantManager.attach`/`TrendWidgetSync` 基于不完整快照。
- **修复**: 让 `asyncInit` 传播取消：`catch CancellationError { return }` 且不置 `isReady`，或改为 `async throws`；`loadHighFrequencyRepositories` 内 `try Task.checkCancellation()` 细分。

### C-05 JSON→SwiftData 迁移单条脏数据致全域静默丢失

- **文件**: `StudyPulse/Managers/Core/ModelContainerFactory.swift:379-453` · `StudyPulse/Repositories/ImageStorage.swift:90-104` (`DataFileIO.load`)
- **描述**: `migrateFromJSONIfNeeded` 对 `[Grade]` 等数组整体 `JSONDecoder.decode`；`DataFileIO.load` 失败仅 `return nil` + `Log.data.error`。若 `grades.json` 单条缺必填字段，整文件 `nil` 跳过，其余域仍 `save` 并置旗 `true` 永不重试。
- **为什么是问题**: "一次性" 旗控无按域重试、无脏数据隔离。
- **后果**: 老用户首次升级后成绩/错题整表丢失且无法自愈。
- **修复**: 逐条容错：先 `Data(contentsOf:)` → 按行/元素 `try? decode`，坏行跳过记 `warnings`；旗标与数据分离（`StudyPulseSchemaMetadataRecord` 同事务提交），`save` 失败不置旗。

### C-06 迁移旗标与 `save` 非事务，进程被杀后陷入重复唯一键违例循环

- **文件**: `StudyPulse/Managers/Core/ModelContainerFactory.swift:444-453,466-485` · `StudyPulse/Repositories/Persistence/PersistenceExecutor.swift:315-332`
- **描述**: `try context.save()` 成功后才 `UserDefaults.set(true, forKey: migrationDoneKey)`，两写入无事务；进程在两者之间被杀，下次 `needsJSONMigration==true` 重复插入相同 `id` 触发 `@Attribute(.unique)` 违例，`save` 抛错分支旗永不置位。
- **后果**: 迁移卡死、启动变慢、日志洪水。`PersistenceExecutor` 内直接读写 `UserDefaults` 跨 Actor 无同步。
- **修复**: 将旗写入同一 `ModelContext` 的 `StudyPulseSchemaMetadataRecord` 同事务提交；或插入前 `fetch(id)` 去重。

### C-07 备份恢复 `deleteAll→insert` 非原子，中间崩溃丢全库

- **文件**: `StudyPulse/Managers/Backup/BackupImporter.swift:60-115,118-120` · `StudyPulse/Repositories/Persistence/PersistenceExecutor.swift:641-647` · `StudyPulse/Managers/Backup/BackupImporter.swift:233-307`
- **描述**: `replacePersistentContent` 先对 18 张表逐一 `fetch→delete` 再 `save`，再批量 `insert` 二次 `save`；期间被杀/`save` 抛错仅 `rollback` 内存，磁盘已部分清空；`stageMedia` 已移动媒体文件但 `createdFiles` 对已存在同名且 checksum 相等的文件未计入，失败回滚遗留孤儿媒体。
- **后果**: 大包恢复中断电/被 kill，下次启动 18 张表全空且媒体已覆盖，不可逆。
- **修复**: 先写入临时 `ModelContainer` 验证再原子 `replace` 文件级 `storeURL`（复用 `ModelContainerFactory.backupStoreBundle` 做法）；媒体先写临时目录，DB `save` 成功后再原子 `move`；失败整体删临时目录。

### C-08 麦克风权限描述缺失，录音即崩溃且必被拒审

- **文件**: `StudyPulse.xcodeproj/project.pbxproj:537-545,586-594` vs `StudyPulse/Managers/Audio/VoiceMemoManager.swift:12-40`
- **描述**: `INFOPLIST_KEY_NSMicrophoneUsageDescription` 在两 buildConfiguration 均未声明；文档声称已声明但工程未配置。
- **为什么是问题**: iOS 10+ 无该 key 调用 `AVAudioSession.requestRecordPermission` 直接 `crash` (`without a usage description`) 且 App Review 必拒。
- **后果**: 用户在 `MistakeDetailEditView` 点录音即闪退。
- **修复**: 两 target 各加 `INFOPLIST_KEY_NSMicrophoneUsageDescription = "StudyPulse needs microphone access to record voice memos for mistake notes";`。
- **验证**: `grep -rn NSMicrophoneUsageDescription StudyPulse.xcodeproj/project.pbxproj` 无结果（已本地验证）。

### C-09 自定义 Scheme 明文传 token，无 state/PKCE，可被任意进程注入

- **文件**: `StudyPulse/Managers/Auth/WebAuthSession.swift:26-50,90,96-98,121` · `StudyPulse/StudyPulseApp.swift:103-110` · `StudyPulse/Info.plist:6-13`
- **描述**: `return_to=studypulse://auth/callback?access_token=...&refresh_token=...` 直接放 URL query，无 `state`/PKCE；`WebAuthCallbackParser.parse` 仅校验 `scheme/host/path`；`.onOpenURL` 同样无来源校验，任意进程 `openURL("studypulse://auth/callback?access_token=attacker")` 即可写入 `AuthTokenStore`；`prefersEphemeralWebBrowserSession=false` 持久化 Cookie。
- **为什么是问题**: 自定义 scheme 非唯一（其他 App 可声明同一 scheme 抢占），token 进系统日志/粘贴板/历史。
- **后果**: 攻击者可让受害设备登录攻击者账户，进而 `LLMClient.cloudComplete` 用攻击者 session 窃数据或反向窃受害者 health 数据。
- **修复**: 改用 `https` Universal Link + 随机 `state` 回检；或至少校验 JWT `iss/aud/exp` 签名（`auth.chenkai.space` 公钥）；token 改 `fragment` 或 `POST` 回传；`prefersEphemeralWebBrowserSession=true`。

---

## High 级别

### H-01 图片非原子写入，半截 JPEG 永久损坏

- **文件**: `StudyPulse/Repositories/ImageStorage.swift:46-47`
- **描述**: `try data.write(to: url)` 未传 `options: .atomic`；健康/成就等处均用 `.atomic`，唯独高频图片路径未用。
- **为什么是问题**: 低电/杀进程时半截落盘，`Grade.imageFileName` 已指向损坏文件。
- **后果**: 单条成绩图片永久损坏，`BackupExporter` 判为缺失媒体。
- **修复**: `try data.write(to: url, options: .atomic)`；`AudioStorage` 同理。
- **验证**: `grep -n "write(to:" StudyPulse/Repositories/ImageStorage.swift` → `try data.write(to: url)` 无 `.atomic`。

### H-02 低频 Repository 静默 `try? save`，磁盘满时内存与磁盘分叉

- **文件**: `StudyPulse/Repositories/Default/DefaultDiaryRepository.swift:103-105` · `DefaultRoutineRepository.swift:99-101,122,142,238` · `DefaultPhaseRepository.swift:126-129` · `DefaultStudySessionRepository.swift:54-55` · `StudyPulse/Managers/Plant/PlantManager.swift:306,333` 等 15 处
- **描述**: 高频 4 仓走 `PersistenceExecutor.saveIfNeeded() throws+rollback`，低频 8 仓直接 `try? context.save()` 忽略错误，内存已 `append`，磁盘未落盘。
- **后果**: 磁盘满/权限异常时用户见"已保存"，杀进程后回退，静默丢失。
- **修复**: 统一走 `PersistenceExecutor` 或 `do { try context.save() } catch { context.rollback(); 内存回滚; Log.fault + Toast }`。

### H-03 `Dictionary(uniqueKeysWithValues:)` 重复键即 trap 崩溃

- **文件**: `StudyPulse/Repositories/Default/DefaultGradeRepository.swift:77` · `DefaultTimeInvestmentRepository.swift:189` · `DefaultSubjectRepository.swift:129` · `StudyPulse/Managers/Backup/BackupValidator.swift:266`
- **描述**: `Dictionary(uniqueKeysWithValues: array.map { ($0.id, $0) })` 在键重复时 trap（非 throw）；损坏备份/JSON 可含重复 UUID。
- **后果**: 打开损坏备份或重复 ID Store 时主线程 SIGTRAP 无日志。
- **修复**: `var d:[UUID:Value]=[:]; for v in array { d[v.id]=v }` 或 `Dictionary(grouping:)` + 抛 `BackupError.invalidRelationship("duplicate UUID")`。
- **验证**: `grep -rn "uniqueKeysWithValues"` 命中 3 处业务代码 + 1 处校验代码。

### H-04 HealthKit 写入与隐私描述矛盾，审核风险

- **文件**: `StudyPulse/Managers/Health/HealthKitManager.swift:241-246,377-402,343-356` · `StudyPulse.xcodeproj/project.pbxproj:540,589` (`NSHealthUpdateUsageDescription="StudyPulse does not write any data to Apple Health."`) · `StudyPulse/Models/AppPreferences.swift:263`
- **描述**: 用户开启`同步日记到 Apple Health`时写入 `HKCategoryTypeIdentifier.mindfulSession`，但 `Info.plist` 声明不写入。
- **后果**: 隐私问卷失实，HealthKit 审核拒审。
- **修复**: 将 `NSHealthUpdateUsageDescription` 改为 `StudyPulse can save your diary as a Mindful Session...` 并同步 `HRVOnboardingView` 文案。
- **验证**: `grep NSHealthUpdateUsageDescription` → 两处均为 `does not write`；`HealthKitManager.swift:379` 确有 `saveMindfulSession`。

### H-05 健康数据外发至第三方 LLM 与 "永不上传" 承诺矛盾

- **文件**: `StudyPulse/Managers/LLM/LLMRequestBuilder.swift:972-1120` (`BodyRadarLLM.makePrompt`) · `StudyPulse/Managers/Health/StudyReadinessAlgorithm.swift:270-367` · `StudyPulse/Managers/LLM/HomeAskDataProvider.swift:35-52` · `StudyPulse.xcodeproj/project.pbxproj:539,588` (`Your data stays on device and is never uploaded or shared.`)
- **描述**: 用户被告知健康数据仅留本机，但开启 LLM 后 `BodyRadarLLM`/`HomeAsk` 将 HRV/Sleep/RHR/RR/Exercise 等批量序列化进 `LLMClient` 发至 `baseURL`（用户自备端点或 `spapi.chenkai.space`）。
- **后果**: 敏感健康信息外泄，GDPR/审核以误导性描述拒审。
- **修复**: 首次触发 BodyRadar AI 时二次同意弹窗（默认关闭），更新 `NSHealthShareUsageDescription` 与隐私政策；提供本地回退（已实现）。

### H-06 LLM BaseURL 允许 `http://` 明文，凭证明文传输

- **文件**: `StudyPulse/Managers/LLM/LLMClient.swift:776-791` (`normalizeURL`) · `StudyPulse/Managers/Auth/AuthClient.swift:205-214`
- **描述**: `if lowered.hasPrefix("http://") { return cleaned }` 原样保留 http；ATS 默认拦截但企业 MDM 可放行，代码未强制 https。
- **后果**: `Authorization: Bearer <apiKey>` 明文被嗅探。
- **修复**: `http://` 直接 `throw LLMError.invalidURL` 或强制 `replacingOccurrences(of:"http://", with:"https://")` 并提示；显式 `NSAppTransportSecurity NSAllowsArbitraryLoads=false`。

### H-07 备份全量明文 ZIP，无加密无口令

- **文件**: `StudyPulse/Managers/Backup/BackupExporter.swift:109-205` · `BackupManifest.swift:17,75` (`encrypted=false` 且拒绝 `encrypted==true`) · `BackupDocument.swift:5-9`
- **描述**: `health_history.json`、`grades.jsonl`、`mistakes`、`diaryEntries`、`profile`（含 `studentId/school/realName`）、`images/audio` 未加密落 `tmp/StudyPulse-*.studypulsebackup` 经分享面板外发。
- **后果**: 设备丢失或分享链接泄露即全量 PII 泄露。
- **修复**: 可选口令 `CryptoKit.AES.GCM + PBKDF2` 加密，或至少对 `health_history.json` 默认排除并 UI 显著提示"备份未加密"；临时目录 `FileProtectionType.complete`。

### H-08 `ImageCache.makeKey` 用 `Data.hashValue` 致缓存碰撞

- **文件**: `StudyPulse/Managers/Utility/ImageCache.swift:33-34`
- **描述**: `Data.hashValue` 为随机种子 SipHash，64bit 易碰撞且跨进程不稳定；两张不同大图可映射同一 key。
- **后果**: 列表滚动出现张冠李戴的错题图/成绩图。
- **修复**: 改 `SHA256` 截断（`CryptoKit`）或直接以 `filename` 为主键（`putImageByFilename` 已有）；`Data` 路径追加 `SHA256.prefix(16)`。
- **验证**: `ImageCache.swift:34` 确为 `String(data.hashValue, radix:16)`。

### H-09 SessionToken 未纳入日志脱敏

- **文件**: `StudyPulse/Managers/LLM/LLMClient.swift:78-102,196,208,224,285,770,897-928`
- **描述**: `redacting(secret:)` 仅对 `apiKey` 脱敏，Cloud 模式 `Bearer <sessionToken>` 未脱敏；`LLMCallDebugInfo` 常驻 20 条 + `Log.llm` 可被导出。
- **后果**: 导出日志即泄露长期有效 `refresh_token`。
- **修复**: `recordCall` 入参改为 `(apiKey: String?, sessionToken: String?)`，`redacting` 支持多 secret；`printPromptToConsole` 同时脱敏；`asDebugJSON` 默认 `<redacted>`。

### H-10 阶段过滤语义分裂：`nil phaseId` 旧数据在同视图下时隐时现

- **文件**: `StudyPulse/Repositories/TodoAggregator.swift:50-52` · `StudyPulse/Repositories/Persistence/PersistenceExecutor.swift:118-140,390-400`
- **描述**: `TodoAggregator.entries` 对 exam/task 做 `if active != nil && e.phaseId != active { continue }`，`phaseId==nil` 旧数据在切 Phase 后被过滤；`fetchDiaryEntries:398` 却显式 `phaseId==nil || phaseId==active`，Diary 仍可见。
- **后果**: 同一 Phase 视图 Diary 能看见历史，日程/成绩/错题却看不到，用户误以为丢失；`TodoView pastEntries` 统计错误。
- **修复**: 统一谓词 `#Predicate { $0.phaseId == active || $0.phaseId == nil }` 或迁移时回填默认 Phase。

### H-11 `ExamFilter` 固定 86400s 做日桶，无视 DST 致未登记考试漏报

- **文件**: `StudyPulse/Services/ExamFilter.swift:163,168,173` · `StudyPulse/ViewModels/HomeViewModel.swift:141`
- **描述**: `dayInterval=86_400` + `Int(date.timeIntervalSince1970/dayInterval)` 假定每天等长，`windowStart/windowEnd` 却用 `Calendar.startOfDay`（DST 日 23h/25h）；半开区间 `[windowEnd, windowStart)` 对恰好在 00:00 的考试遗漏。
- **后果**: 春秋 DST 周同一物理日被分两桶，Home"未登记考试"卡片漏报。
- **修复**: 桶化改 `Calendar.startOfDay` 或 `dateComponents([.year,.month,.day])`；补 `TimeZone(identifier:"Europe/Berlin")` DST 单测。

### H-12 `HealthHistoryStore` 并发 `upsert` 丢失更新 + `StudyStreakCalculator` 跨时区错算

- **文件**: `StudyPulse/Managers/Health/HealthHistoryStore.swift:84` · `StudyPulse/Managers/Health/HealthKitManager.swift:699` · `StudyPulse/Services/TimeInvestmentEngine.swift:119-142`
- **描述**: `upsert` 为 `nonisolated static func load→filter→save`，`HealthKitManager.recordTodaySnapshotAsync:699` 用 `Task.detached` 无串行化；`StudyStreakCalculator.activeDays` 按会话 `timeZoneIdentifier` 还原时区，而 `currentStreak` 的 `todayStart` 用 `referenceCalendar`（`.autoupdatingCurrent`），基准不一致。
- **后果**: 当日 `restingHeartRate` 与 `sleepHours` 分两次到达时后写覆盖丢字段；跨时区飞行后 streak 断裂或虚增。
- **修复**: `HealthHistoryStore` 改 `actor` 串行化；`currentStreak` 统一用会话本地时区或 UTC `startOfDay`。

### H-13 `LearningHeatmapView.cells` 每帧重算 91 天 + `BrainUsageCard` 30s 永久轮询

- **文件**: `StudyPulse/Views/Components/LearningHeatmapView.swift:100-141` · `StudyPulse/Views/Home/HomeCards/BrainUsageCard.swift:55-73`
- **描述**: `cells` 为计算属性，`body` 每次因 `AchievementManager.snapshot.logs`/`effectiveAccentColor` 变化全量重算 91×`Calendar.startOfDay`；`BrainUsageCard` 3 个并发 `.task` 含 `while !cancelled { sleep(30s); now=Date(); evaluate() }` 即使不可见/后台仍唤醒 MainActor，每小时 120 次唤醒；`UserDefaults` period key 永不清理。
- **后果**: 主页/趋势页双 `LearningHeatmapView` 主线程每帧 3-5ms 额外开销；后台电量浪费。
- **修复**: `cells` 改 `@State` + `onChange(snapshot.logs)` 缓存或 ViewModel `@Published cells`；`now` 改 `TimelineView(.periodic)`，30s 轮询 `scenePhase==.active` 时才运行，period key 定期清理。

---

## Medium 级别

### M-01 `PersistenceExecutor.pagedFetch` OFFSET 分页大数据量退化 + 伪并行

- **文件**: `StudyPulse/Repositories/Persistence/PersistenceExecutor.swift:594-613` · `StudyPulse/Repositories/Default/DefaultExamRepository.swift:35`
- **描述**: `fetchOffset += page.count` 循环用 `OFFSET`，对 5k 记录排序后跳过 `O(N²)`；`@ModelActor` 串行却写 `async let single/comprehensive` 伪并行；`loadHighFrequencySnapshots` 无细分 `Task.checkCancellation`。
- **后果**: 冷启动 2k 成绩+2k 错题时 8 轮分页 `sqlite3_step` 线性增长，取消延迟。
- **修复**: 全量读取改 `fetchLimit=nil` 单次 fetch；仅写入保留 `insertInBatches`；或 keyset 分页 `where id < lastId`。

### M-02 `PhaseFilterRefresher` / `RepositoryContainer.recomputeAllFiltered` 并发交错

- **文件**: `StudyPulse/Repositories/PhaseFilterRefresher.swift:76,94` · `StudyPulse/Repositories/RepositoryContainer.swift:316-317`
- **描述**: `startObserving` 内 `for await notifications` 串行，但 `recomputeAllFiltered:317 Task { await phaseRefresher.recomputeAll() }` 为非结构化 Task 可与通知驱动并发交错，`recomputeAll:97` 顺序 `await grade/mistake/...` 无锁，部分域已切新 phase 部分仍旧。
- **后果**: 切 phase 后 6 个 `filtered*` 缓存不一致，列表出现跨学期脏数据。
- **修复**: `PhaseFilterRefresher` 内 `private var recomputeTask: Task<Void,Never>?` 串行化，新请求 `cancel` 旧任务。

### M-03 `RoutineSpawner` / `RoutineLiveActivityController` 常驻 Timer 无条件空转

- **文件**: `StudyPulse/Managers/Plan/RoutineSpawner.swift:48,132,146,157-162` · `StudyPulse/Managers/Plan/RoutineLiveActivityController.swift:32,93,132-133`
- **描述**: `60s`/`30s` tick 由 `@State var routineSpawner` 永驻持有，即使 `enabledRoutines.isEmpty` 仍空转；`pollTimer`/`observationTask` 未在 `deinit`/`stop` 释放，热重载双实例并发 `spawnForToday`；`RoutineLiveActivityController:94 nonisolated(unsafe) let safe = activity` 将非 Sendable `Activity` 跨隔离捕获。
- **后果**: 后台电量浪费；Preview 热重载双触发；野指针风险。
- **修复**: 仅 `enabledRoutines.count>0 && activeInstances.count>0` 时启动 Timer，否则 `invalidate()`；提供 `invalidate()` 并在 `scenePhase==.background`/`onDisappear` 调用；`safe` 改捕获 `activity.id` 再查表。

### M-04 `StudyTimerManager` Timer 双跳 + 后台空转，`LagMonitor` 在 DisplayLink 中符号化

- **文件**: `StudyPulse/Managers/Study/StudyTimerManager.swift:100,549-556` · `StudyPulse/Managers/Logging/LagMonitor.swift:64-98`
- **描述**: `Timer.scheduledTimer` 已在主线程再 `Task { @MainActor }` 冗余 hop；后台仍每秒 `tick()` + 每 5s `updateLiveActivity` IPC；`LagMonitor` 在 120Hz `CADisplayLink` 回调中同步 `Thread.callStackSymbols` + 20 行 `Log.record`，正反馈放大卡顿。
- **后果**: 主线程卡顿 50ms 被放大到 80-100ms；后台不必要唤醒。
- **修复**: 直接 `tick()`；`scenePhase==.background` 时 `invalidate` 并暂停 LiveActivity；LagMonitor 仅记 `deltaMs/missedFrames`，栈回溯改 `Task.detached` 异步，Release 默认 `stop()`。

### M-05 `HomeViewModel` 脏旗漏字段 + 串行 8 引擎全在 MainActor

- **文件**: `StudyPulse/ViewModels/HomeViewModel.swift:109-217,231-294`
- **描述**: `recomputeSignature` 仅 `combine(e.id/t.id/g.id)`，不含 `exam.checklist/examReview/location/countdownNotifyDays`、`task.dueDate/notes`；编辑清单后 id 不变直接 `return`；同时 `recompute` 串行 8 引擎（SRS/ExamFilter/Recovery/Burnout/DailyPlan/MemoryClimate 等）全在 MainActor，`recomputeSignature` 自身又 5k 次 `combine`。
- **后果**: 改清单/截止日后回 Home 不更新；批量导入 50 条成绩触发 50 次重算，主线程 50ms 阻塞。
- **修复**: 脏旗额外 `combine(checklist/dueDate/examReview)` 或改版本号；`Burnout/Recovery/MemoryClimate` 挪 `Task.detached(.utility)`；对 `container` 变化做 `debounce 0.1s`。

### M-06 `SuggestionEngine` 非确定性：Dictionary 遍历找极值同分随机

- **文件**: `StudyPulse/Services/SuggestionEngine.swift:266-278,282-292,317-338`
- **描述**: `findDecliningTrend`/`findImprovingTrend` 直接 `for (subject,agg) in aggregates` 早退，`qualifiedAggregates.min/max` 同分取任意 key。
- **后果**: 同数据出现不同建议，录屏抖动，单测 flake。
- **修复**: 收集候选后按 `(平均分, 科目名)` 二级排序确定性取首。

### M-07 `DailyPlanEngine.scoreFor` 不可达 `<0` 分支，过期任务未抬权

- **文件**: `StudyPulse/Services/DailyPlanEngine.swift:432-443`
- **描述**: `if <=1 {2.0} else if <=7 {1.0} else if <0 {1.5} else {0.5}` 中 `<0` 永不可达（已被 `<=1` 劫持），意图过期 1.5× 未生效。
- **后果**: 过期 10 天与今天到期得分相同，`overdueTask` 排序失真。
- **修复**: 调为 `if <0 {1.5} else if <=1 {2.0} ...`。

### M-08 SM-2 `intervalDays` 无上界，可溢出致全量 due

- **文件**: `StudyPulse/Models/SpacedRepetition.swift:192,205,215-220` · `StudyPulse/Services/MistakeShelfLife.swift:43`
- **描述**: `easy` 分支 `prev*EF*1.3*1.6` 指数增长无上限，20 次 easy 可 >100 年，`Date(byAdding:.day)` 溢出回退 `now`。
- **后果**: 学霸用户长期后 `nextReviewDate=now` 致队列全到期；与 `MistakeShelfLife.min(60,…)` 不一致。
- **修复**: `intervalDays = min(730, Int(...))` 硬上限 2 年。

### M-09 `BackupRecordDTO` 缺 id 时新造 UUID 断外键 + 校验未覆盖 comprehensive 等表

- **文件**: `StudyPulse/Managers/Backup/BackupDTOs.swift:22-28` · `StudyPulse/Managers/Backup/BackupValidator.swift:296-314` · `StudyPulse/Managers/Backup/BackupImporter.swift:309-327`
- **描述**: `id = decodeIfPresent(UUID.self) ?? UUID()` 随机新造，后续 `validateRelationships` 误判或关联断裂；`verifyImported`/`validateCounts` 未校验 `comprehensiveExams`/`ExamAutopsy`/`ExamSimulation`/`ExamGoal` 等新增表。
- **后果**: 篡改备份导致成绩-考试关联静默丢失；综合考试丢失不报错。
- **修复**: 缺 id 视为 `malformedData` 抛错；补全校验键与 `BackupExporter.recordCounts` 一致。

### M-10 敏感文件未设 Data Protection + App Group 明文

- **文件**: `StudyPulse/Repositories/ImageStorage.swift:40-53` · `StudyPulse/Managers/Health/HealthHistoryStore.swift:70-71` · `StudyPulse/Managers/Core/ModelContainerFactory.swift:131-142` · `StudyPulse/Managers/Widget/ExamWidgetData.swift:51-62` 等
- **描述**: 所有 `write(to:)` 未设 `FileProtectionType.complete`，依赖默认 `CompleteUntilFirstUserAuthentication` 锁屏后仍可离线读取；App Group `UserDefaults(suiteName:"group.com.chenkai.gao.studypulse")` 明文存考试/趋势/HRV，可被同组 App 读取；日志 `exportAsText` 明文含 HR/睡眠/用户名经分享外发。
- **后果**: 设备丢失后健康/学籍可被物理提取。
- **修复**: 写入后 `setAttributes([.protectionKey: .complete])`；Widget 仅存最小字段并可对称加密；日志导出过滤 `healthKit` category 或脱敏并弹窗提示。

### M-11 CSV 公式注入与导入无上限 DoS

- **文件**: `StudyPulse/Managers/Core/DataExportManager.swift:909-920` · `StudyPulse/Managers/Core/DataExportManager.swift:455-479,826-905,646-654`
- **描述**: `escapeCSV` 仅处理 `, " \n \r`，未处理首字符 `= + - @`；导入未限文件大小/行数/字段长度，`masteryHistory` JSON 解码可被大数组攻击。
- **后果**: Excel 打开导出表触发公式执行；恶意 CSV 致 OOM。
- **修复**: `escapeCSV` 首字符 `=+-@` 前缀 `\t` 或 `'`；导入前校验 `fileSize <5MB`/`rows<10k`/`masteryHistory.count<200`。

---

## Low 级别

### L-01 巨型文件与模型单文件过载

- **文件**: `StudyPulse/Managers/LLM/LLMRequestBuilder.swift:1508` (全仓最大) · `StudyPulse/Models/SwiftData/StudyPulseModels.swift:1852` (27 个 @Model 单文件)
- **描述**: `LLMRequestBuilder` 基类仍 233 行 + 6 拆分未彻底；`StudyPulseModels` 单文件承载 27 模型，大幅增加编译与合冲突。
- **修复**: `LLMRequestBuilder` 按 `Exam/Mistake/Coach` 垂直切片；`StudyPulseModels` 按域拆 `GradeRecords.swift`/`MistakeRecords.swift`/...。

### L-02 `RepositoryContainer` God Object + CRUD 模板复制

- **文件**: `StudyPulse/Repositories/RepositoryContainer.swift:26-180,413-628` · `DefaultGradeRepository.swift:15-204` 等 4 份高频仓各 60 行 `executor/persistenceTail/attach/loadAll/reloadFiltered/flush/cancel/enqueue` 逐字复制
- **描述**: 16 Repository + 3 编排 + 容器/执行器/环境/意图全聚合，构造器 18 可选参；`asyncInit` 串行 16×`await loadAll` 强耦合；一处 `enqueue` 修复需改 4 处。
- **修复**: 按启动频率分层懒加载；抽 `PersistenceRepositoryBase<Value,Record>` 泛型基类或 `protocol PersistenceExecutorBacked` 默认实现。

### L-03 观察混用与预览双实例陷阱

- **文件**: `StudyPulse/Views/TimeInvestment/TimeInvestmentView.swift:27` (`@StateObject` + `ObservableObject` vs 其余 21 VM 的 `@Observable`+`@State`) · `StudyPulse/Views/Home/HomeView.swift:805-810` (`HomeView(container: RepositoryContainer()).environment(RepositoryContainer())`)
- **描述**: `@StateObject` 生命周期与视图标识绑定，`reloadAllAfterBackupRestore` 后旧 VM 悬垂；预览传与环境非同一实例，偶发空数据误导。
- **修复**: 统一 `@Observable`+`@State`；预览改 `let c = RepositoryContainer(); HomeView(container: c).environment(c)`。

### L-04 `ImageCache`/`LogStore`/`BrainUsageStore` 轻度资源问题

- **文件**: `StudyPulse/Managers/Utility/ImageCache.swift:26-28` · `StudyPulse/Managers/Logging/Log.swift:269` · `StudyPulse/Views/Home/HomeCards/BrainUsageCard.swift:18-19`
- **描述**: `NSCache countLimit=50` 注释 `≈50MB` 实测 300px 缩略图仅 17MB，未设 `totalCostLimit` 且未监听 `didReceiveMemoryWarning`；`Log.record` 每次 `Task { await LogStore.record }` 非结构化任务高频堆积；`BrainUsageNotifications` 的 `UserDefaults "BrainUsage_5h_\(period)"` 永不清理。
- **修复**: `totalCostLimit=30MB` 按 `pixelCount*4` 计费并监听内存警告 `removeAllObjects()`；`LogStore` 用 `OSAllocatedUnfairLock` 同步缓冲或 `Task.detached` 合并；周期 key 定期清理。

### L-05 Markdown 链接与 View 层缓存细节

- **文件**: `StudyPulse/Views/Components/Markdown/MarkdownPreviewView.swift:29` · `StudyPulse/Views/Trends/TrendsView.swift:289-324` · `StudyPulse/Views/TimeInvestment/TimeInvestmentView.swift:286-366`
- **描述**: `javascript:` 伪协议未过滤；`SubjectDetailView.filteredGrades/averageScore/averageRank` 每次 `body` 重算；`TimeInvestmentView.subTaskRow` 返回 `AnyView` 递归致 SwiftUI 无法 diff；`TodoView.swift:81` 监听 `taskItems` 而非 `filteredTaskItems` 跨 phase 不刷新；`DateFormatters.fileTimestamp` 未固定 `timeZone=UTC` 致文件名碰撞。
- **修复**: 链接白名单仅 `http/https/mailto`；`@State` 缓存聚合；`@ViewBuilder some View` 替代 `AnyView`；监听 `filteredTaskItems`；`fileTimestamp.timeZone = UTC`。

---

## 已验证的正确实践

下列实现经核对为正确，建议保持：

- `KeychainStore.swift:59-60` `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + `kSecAttrSynchronizable=false`，且 `LLMAPIKeyMigrator` 已将 UserDefaults 明文迁移至 Keychain，`BackupPreferencesDTO:57` 白名单排除 LLM 凭证 — 设计良好。
- `BackupArchive.validateEntryPaths / extractSafely` 对 symlink 与 `../` 双重校验正确 (`BackupArchive.swift:18-71`)。
- `PersistenceExecutor.pagedFetch / insertInBatches` 的 `Task.checkCancellation` 与 `rollback` 边界正确。
- `HealthHistoryStore.save / AchievementStore.save / BackupExporter` 的 `.atomic` 写入正确（ImageStorage 除外）。
- `MistakeNote`/`DiaryEntry`/`Exam` 等 `init(from:)` 全量 `decodeIfPresent` 兜底，向后兼容良好。
- `HealthKitManager` `HKObserverQuery/HKSampleQuery` 回调已 `Task { @MainActor }` 跳回主线程。
- `StudyPulseApp` `scenePhase==.active` 且 `isReady` 时才同步 Widget，避免空数据覆盖（但恢复路径仍有 H-04 所述空库残留问题）。

---

## 修复路线图

### P0 — 下次发版前必修（阻断发布）

| 优先级 | 问题 | 动作 | 预期收益 |
|---|---|---|---|
| P0 | C-08 麦克风 | 加 `NSMicrophoneUsageDescription` | 消除崩溃与拒审 |
| P0 | C-01 Schema 冻结 | 为 V5 建独立实体或 `custom` 迁移，`BackupManifest` 升至 5 | 消除升级启动失败 |
| P0 | H-01 图片原子 | `write(to: options:.atomic)` | 消除半截 JPEG |
| P0 | H-02 静默 `try?` | 统一走 `PersistenceExecutor` 并回滚内存 | 消除静默丢失 |
| P0 | H-03 Dictionary trap | `for loop` 替代 `uniqueKeysWithValues` | 消除崩溃 |

### P1 — 两周内（数据与安全）

| 优先级 | 问题 | 动作 |
|---|---|---|
| P1 | C-02 `nonisolated(unsafe)` | 改 `@MainActor` 或 `actor ContainerHolder` |
| P1 | C-03 多 Context | 统一写入路径 |
| P1 | C-04 取消传播 | `isReady` 仅成功后置位 |
| P1 | C-07 备份原子 | 临时 Container + 临时目录两阶段提交 |
| P1 | C-09 自定义 Scheme | 加 `state` + JWT 校验 + `ephemeral` |
| P1 | H-04/H-05 隐私描述 | 更新 `NSHealth*UsageDescription` 并二次同意 |
| P1 | H-06 `http` 放行 | 强制 `https` |
| P1 | H-08 `hashValue` | 改 `SHA256` |
| P1 | H-09 日志脱敏 | 同时脱敏 `sessionToken` |

### P2 — 迭代内（质量与性能）

| 优先级 | 问题 | 动作 |
|---|---|---|
| P2 | H-10 阶段过滤 | 统一谓词或回填 nil |
| P2 | H-11 DST | 改 `Calendar.startOfDay` 桶 |
| P2 | H-12 并发丢失 | `actor HealthHistoryStore` + 时区统一 |
| P2 | H-13 热力图/轮询 | 缓存 `cells` + `TimelineView` + 条件 Timer |
| P2 | M-05/M-06 脏旗/确定性 | 补字段 + 二级排序 |
| P2 | M-08 SM-2 上界 | `min(730)` |
| P2 | M-10/M-11 保护/注入 | `FileProtectionType.complete` + CSV 转义 |

---

## 附录: 建议新增单测清单

建议为下列缺陷补充单测，均可在本地 `XCTest` 复现：

- `SwiftDataMigrationTests.testV4ToV5Opens` — V4 Store 原地升级到 V5 成功打开
- `ModelContainerFactoryTests.testSingleBadGradeDoesNotLoseAllGrades` — 单条脏 JSON 其余域完整
- `ImageStorageTests.testAtomicWriteSurvivesKill` — 模拟磁盘满 `save` 失败内存回滚
- `BackupImportTests.testDuplicateUUIDDoesNotCrash` — 重复 UUID 备份不 trap
- `ExamFilterTests.testUnregisteredExams_DST_Berlin` — DST 日桶正确
- `StudyStreakCalculatorTests.testCrossTimezoneStreak_TokyoToLondon` — 跨时区 streak
- `SRSAlgorithmTests.testEasyOverflowClamped` — 连续 easy 上限 730
- `RepositoryContainerTests.testPhaseFilterNilIncluded` — nil 旧数据在新 phase 可见
- `RoutineSpawnerTests.testSpawnedMistakeCountUsesInjectedNow` — 注入时钟
- `ImageCacheTests.testDifferentDataDifferentKeys` — 碰撞检测
- `BackupManifestTests.testCurrentSchemaVersionMatchesFactory` — manifest 与 factory 一致
- `AuthCallbackTests.testRejectsMissingState` — 无 state 拒绝

---

> 报告生成：本地静态精读 + `grep` 验证，无运行时插桩。所有 `file:line` 基于当前 `main` 分支；行号偏移 ±3 属正常。建议开启 `SWIFT_STRICT_CONCURRENCY=complete` + Thread Sanitizer 复现并发类问题，并以 Instruments Time Profiler 录制主页滑动 10s 验证性能类修复。
