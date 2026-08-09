# 从旧 JSON 到版本化 SwiftData：让持久化升级对用户无感

> 摘要：将已上线 iOS 应用从本地 JSON 迁移到 SwiftData，不能只依赖一次模型替换。本文以 StudyPulse 为例，拆解 `VersionedSchema + SchemaMigrationPlan` 如何维护 V1→V4 的持久化版本链，以及如何通过一次性 legacy importer 将旧 JSON 安全导入 SwiftData。文章同时介绍稳定 ID、快照映射、启动时序、失败重试、源文件保留、store bundle 恢复和迁移测试，给出一套兼顾演进能力与数据安全的无感迁移方案。

在一个已经发布过的 iOS 应用里，把 JSON 文件换成 SwiftData，真正困难的部分不是把 `Codable` 改成 `@Model`，而是回答三个问题：

1. 老用户已经存在的 JSON 数据，第一次升级时如何完整导入？
2. 新版本继续增加字段或实体时，如何让已经安装过的版本逐步迁移？
3. 迁移失败时，如何保证用户原来的数据仍然可恢复？

StudyPulse 的做法是把迁移拆成两条明确的链路：

- `VersionedSchema + SchemaMigrationPlan`：负责 SwiftData 自己的持久化格式从 V1 演进到当前版本。
- 一次性 legacy importer：负责读取旧版 `~/Documents/*.json`，把值类型转换成 SwiftData 实体。

这两条链路分别解决不同的问题。前者是“数据库 schema 版本升级”，后者是“外部文件导入”。把它们混成一个大迁移函数，往往会让重试、回滚和问题定位都变得困难。

## 1. 先保留领域模型，再增加持久化实体

StudyPulse 没有让 SwiftUI 直接依赖 `@Model` 对象，而是保留了原来的值类型，例如 `Grade`、`MistakeNote` 和 `Exam`。SwiftData 层使用对应的 `GradeRecord`、`MistakeNoteRecord` 和 `ExamRecord`。

```swift
@Model
final class GradeRecord {
    @Attribute(.unique) var id: UUID

    var subject: String
    var score: Double
    var rawScore: Double?
    var ranking: Int?
    var importance: Int
    @Attribute(.externalStorage) var image: Data?
    var imageFileName: String?
    var date: Date
    var examName: String
    var examId: UUID?
    var fullScore: Double?
    var phaseId: UUID?

    init(from grade: Grade) {
        id = grade.id
        subject = grade.subject
        score = grade.score
        rawScore = grade.rawScore
        ranking = grade.ranking
        importance = grade.importance
        image = grade.image
        imageFileName = grade.imageFileName
        date = grade.date
        examName = grade.examName
        examId = grade.examId
        fullScore = grade.fullScore
        phaseId = grade.phaseId
    }

    func toSnapshot() -> Grade {
        Grade(
            id: id,
            subject: subject,
            score: score,
            rawScore: rawScore,
            ranking: ranking,
            importance: importance,
            image: image,
            imageFileName: imageFileName,
            date: date,
            examName: examName,
            examId: examId,
            fullScore: fullScore,
            phaseId: phaseId
        )
    }
}
```

这个边界有几个好处：

- ViewModel 和 View 继续消费 `struct`，不需要把 SwiftData 的生命周期带进 UI。
- JSON 导入、SwiftData 查询和测试都可以复用同一组领域值类型。
- 实体字段可以针对持久化查询做优化，例如将嵌套结构拍平为 `Date`、`String`、`[Data]` 等基础字段。
- `toSnapshot()` 与 `init(from:)` 形成明确的双向转换点，迁移时更容易检查字段是否丢失。

稳定的 `UUID` 也很重要。迁移时必须复用旧记录的 ID，而不是为每条 JSON 数据重新生成 ID，否则关联的考试、阶段、错题和复习状态可能失效。

## 2. V1 一旦发布，就把它当成冻结的历史记录

SwiftData 的版本化 schema 不是“当前模型的另一个写法”，而是应用曾经发布过的持久化契约。StudyPulse 的 V1 明确列出首个版本的实体：

```swift
enum StudyPulseSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SubjectRecord.self,
            GradeRecord.self,
            MistakeNoteRecord.self,
            ExamRecord.self,
            ComprehensiveExamRecord.self,
            TaskItemRecord.self,
            UserProfileRecord.self,
            StudyPhaseRecord.self,
            PlantStateRecord.self,
            RoutineRecord.self,
            RoutineInstanceRecord.self,
            DiaryEntryRecord.self,
            CoachGoalRecord.self,
            CoachAnalysisRecord.self,
            CoachProposalRecord.self,
            CoachConversationMessageRecord.self,
            CoachChatRecord.self,
            StudySessionRecord.self,
            ExamAutopsyRecord.self,
            ExamSimulationRecord.self
        ]
    }
}
```

关键规则是：V1 的实体定义不能因为“现在需要一个字段”就直接修改。已有设备上的 store 是按照旧字段形状创建的；如果源码中的 V1 被悄悄改成新形状，应用就可能无法识别旧 store，甚至在打开数据库时失败。

正确做法是追加新版本：

```swift
enum StudyPulseSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        StudyPulseSchemaV1.models + [
            StudyPulseSchemaMetadataRecord.self
        ]
    }
}

enum StudyPulseSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        StudyPulseSchemaV2.models + [
            ExamGoalRecord.self,
            ExamPlanRecord.self
        ]
    }
}

enum StudyPulseSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        StudyPulseSchemaV3.models + [
            TimeInvestmentSubjectRecord.self,
            SubTaskRecord.self,
            GoalRewardRecord.self
        ]
    }
}
```

V2 里的 `StudyPulseSchemaMetadataRecord` 是一个内部元数据实体。它不承载用户业务数据，但让第一次显式迁移成为真实的 schema transition，同时不需要修改原有用户实体。

## 3. 用迁移计划连接每一个版本

当前版本不是只声明 V4 就结束了。迁移计划必须保留完整的历史链路：

```swift
enum StudyPulseMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            StudyPulseSchemaV1.self,
            StudyPulseSchemaV2.self,
            StudyPulseSchemaV3.self,
            StudyPulseSchemaV4.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: StudyPulseSchemaV1.self,
                toVersion: StudyPulseSchemaV2.self
            ),
            .lightweight(
                fromVersion: StudyPulseSchemaV2.self,
                toVersion: StudyPulseSchemaV3.self
            ),
            .lightweight(
                fromVersion: StudyPulseSchemaV3.self,
                toVersion: StudyPulseSchemaV4.self
            )
        ]
    }
}
```

这样，一个仍然停留在 V1 的 store 可以沿着 V1→V2→V3→V4 迁移到当前版本；从 V3 升级的用户则只执行 V3→V4。每次增加新实体时，通常只需要新增一个版本和一个迁移 stage，旧版本继续保持不变。

如果字段重命名、类型变化或数据需要重新计算已经超出 lightweight migration 的能力，就应该使用 `custom` stage，并把转换逻辑限制在该版本边界内。不要为了省一个版本，直接在当前模型里兼容所有历史形状。

## 4. 打开 ModelContainer 时必须同时提供当前 schema 和迁移计划

生产容器使用当前版本的 schema，并把迁移计划传给 `ModelContainer`：

```swift
let schema = Schema(versionedSchema: StudyPulseSchemaV4.self)
let configuration = ModelConfiguration(
    "StudyPulse",
    schema: schema,
    url: storeURL,
    cloudKitDatabase: .none
)

let container = try ModelContainer(
    for: schema,
    migrationPlan: StudyPulseMigrationPlan.self,
    configurations: [configuration]
)
```

在 StudyPulse 中，store 位于 Application Support 下的 `studypulse.store`。容器由 `ModelContainerFactory` 创建并缓存，随后注入 SwiftUI 和 RepositoryContainer。这样应用的所有 Repository 使用的是同一个 `ModelContext` 来源，而不是每个模块各自打开一份数据库。

启动顺序也很关键：

1. 先打开或迁移 SwiftData store。
2. 容器打开成功后，再执行旧 JSON 导入。
3. 导入完成后，Repository 才从 `ModelContext` 加载快照。
4. 所有主数据准备完成后，才将 `isReady` 设为 `true`，再启动通知、Widget、HealthKit 等依赖数据的功能。

如果容器打不开，应用显示持久化恢复页面，而不是让部分 View 先启动、再在后台尝试替换数据库。这能避免 UI 读到半初始化状态。

## 5. 老 JSON 导入是独立的一次性迁移

`SchemaMigrationPlan` 不会自动读取 `~/Documents/grades.json`。旧文件导入必须由应用显式编排。StudyPulse 在 `RepositoryContainer.asyncInit(using:)` 中，先拿到容器的 `mainContext`，再调用：

```swift
ModelContainerFactory.migrateFromJSONIfNeeded(context: context)
```

核心逻辑可以抽象成下面这样：

```swift
static let migrationDoneKey = "didMigrateToSwiftData_v1"

static var needsJSONMigration: Bool {
    !UserDefaults.standard.bool(forKey: migrationDoneKey)
}

@MainActor
static func migrateFromJSONIfNeeded(context: ModelContext) {
    guard needsJSONMigration else { return }
    guard let documents = DataFileIO.getDocsDir() else { return }

    if let subjects: [Subject] = DataFileIO.load(
        url: documents.appendingPathComponent("subjects.json")
    ) {
        subjects.forEach { context.insert(SubjectRecord(from: $0)) }
    }

    if let grades: [Grade] = DataFileIO.load(
        url: documents.appendingPathComponent("grades.json")
    ) {
        grades.forEach { context.insert(GradeRecord(from: $0)) }
    }

    // mistakes / exams / tasks / profile 等领域按相同方式导入

    do {
        try context.save()
        UserDefaults.standard.set(true, forKey: migrationDoneKey)
    } catch {
        // 不设置完成标记，下一次启动仍可重试
        Log.data.error("JSON → SwiftData migration failed: \(error.localizedDescription)")
    }
}
```

这里有三个重要的顺序：

- 先 `insert`，成功 `save` 后再写完成标记。
- 旧 JSON 文件保留在原位置，不在首次导入后立即删除。
- 每个领域记录导入数量并写入日志，便于发现“文件存在但解析为空”这类问题。

“无感”不是指迁移永远不会失败，而是指正常用户不需要手动导出、选择文件或重新录入数据。首次启动完成后，Repository 继续向 View 暴露原来的值类型，页面不需要知道底层刚刚经历了存储切换。

## 6. 不同历史来源可以使用独立的 importer

StudyPulse 的学习会话是一个值得单独说明的例子。长期时间投入功能加入后，`DefaultStudySessionRepository` 负责把旧 `study_sessions.json` 合并到 `StudySessionRecord`，并使用独立的迁移 key：

```swift
let key = "studyPulse.studySessionsLegacyMigrationV2"
guard force || !UserDefaults.standard.bool(forKey: key) else { return }

let existing = (try? context.fetch(
    FetchDescriptor<StudySessionRecord>()
)) ?? []
let existingIDs = Set(existing.map(\.id))

for session in StudySessionStore.load()
where !existingIDs.contains(session.id) {
    context.insert(StudySessionRecord(from: session))
}

try context.save()
UserDefaults.standard.set(true, forKey: key)
```

这个 importer 通过 ID 去重，因此后续需要“从旧文件刷新”时可以显式 force merge，而不会把相同会话插入两次。它也说明了一个实践原则：当某个领域的迁移拥有独立的生命周期、数据量或重试策略时，可以放在对应 Repository 中；但它仍然应该遵守相同的保存顺序、去重和保留源文件规则。

## 7. 失败安全比迁移成功路径更重要

持久化升级最危险的代码，通常不是 `context.insert`，而是失败时的清理和替换。

StudyPulse 的正常启动路径不会移动、删除或覆盖原有 store。`ModelContainerFactory.makeContainer()` 打开或迁移失败时，会把错误交给 `PersistentStoreLaunchController`，由启动页面展示恢复选项。

只有用户明确确认灾难恢复后，应用才会：

1. 将当前 store bundle，包括 `store`、`-wal`、`-shm` 等相关文件，移动到带时间戳的备份目录。
2. 尝试在原位置创建新的容器。
3. 如果新容器创建失败，恢复原始 bundle。
4. 保留失败替换产生的文件，便于后续诊断。

这和“启动失败就删除数据库重建”有本质区别。后者可能让应用暂时打开，但用户的数据恢复成本极高；前者把恢复动作变成可追踪、可回滚的显式操作。

旧 JSON 的处理同样保守：即使导入成功，也保留源文件。源文件不是日常查询的主存储，但它是迁移问题排查和人工恢复的重要保险。

## 8. 测试要验证数据，不只是验证容器能打开

迁移测试至少要覆盖四类场景。

### V1 → V2 的历史数据保真

测试先用 V1 的实体列表创建真实临时 store，再用 V2 schema 和 migration plan 打开它，检查：

- 各类实体数量没有变化。
- 原有 UUID 保持不变。
- 关键业务字段，例如成绩、错因、考试地点、用户资料和植物阶段，仍然保持原值。

### V3 → V4 的新增实体可用

测试先创建 V3 store，再使用当前迁移计划打开，确认旧实体仍然存在，并能插入 `TimeInvestmentSubjectRecord`、`SubTaskRecord` 和 `GoalRewardRecord`。这能验证“迁移完成”不等于“新实体注册正确”。

### store bundle 恢复

测试模拟替换失败，确认原始 `store`、`-wal` 和 `-shm` 文件可以恢复到原内容，同时失败替换文件被移入诊断目录。

### JSON importer 的重试和去重

测试应模拟解析失败、保存失败、重复启动和旧文件保留，确认：

- 保存失败不会写入完成标记。
- 正常重启不会重复导入。
- ID 相同的记录不会重复创建。
- 源 JSON 仍然存在。

在 StudyPulse 中，`SwiftDataMigrationTests` 已覆盖 V1 store 保真、V3→V4 迁移以及 store bundle 恢复；Repository 和领域测试继续覆盖 JSON 解码、快照转换和会话导入行为。

## 9. 最容易踩的坑

### 直接修改冻结的 V1 实体

这会让历史 store 与源码 schema 不匹配。新增字段时，先判断是否能做 lightweight migration；不能的话创建新版本并增加 custom stage。

### 只声明当前 schema，不提供历史版本

这样新安装可能正常，老安装却无法沿历史路径迁移。版本化迁移必须保留完整的 `schemas` 数组。

### 在 `save()` 前写完成标记

一旦保存失败，应用会误以为迁移已经完成，用户数据可能永远没有再次导入机会。完成标记只能在保存成功之后写入。

### 迁移成功后立即删除旧文件

迁移问题通常发生在少数历史数据、特殊日期或异常文件上。保留源文件能显著降低排查和恢复成本。

### 让 View 自己触发迁移

View 的生命周期和重绘并不适合承担一次性数据迁移。迁移应发生在容器打开之后、Repository 加载之前，并由启动编排层统一控制。

### 用“能打开数据库”代替“数据正确”

容器成功打开只能证明 schema 层面没有立即报错。必须进一步检查数量、ID、关键字段、关联关系和新增实体的读写能力。

## 10. 一份可执行的迁移清单

每次准备修改持久化模型时，可以按下面的顺序检查：

1. 记录当前生产 schema 版本，并确认旧版本文件没有未提交的改动。
2. 明确这是 SwiftData store migration，还是外部 JSON/file import，必要时拆成两个步骤。
3. 新建 `VersionedSchema`，通过旧版本的 `models` 追加实体或新结构。
4. 在 `SchemaMigrationPlan` 中加入完整 schema 和 migration stage。
5. 保持稳定 ID，补齐 `init(from:)` 与 `toSnapshot()`。
6. 在临时目录创建旧版本真实 store，执行升级测试。
7. 验证记录数量、ID、关键字段、关联关系和新实体读写。
8. 迁移成功后再更新 UserDefaults 的完成标记。
9. 正常启动不删除或替换原 store；恢复动作必须显式确认并可回滚。
10. 在日志中记录版本、来源、记录数量和失败原因，但不要记录用户隐私字段。

## 文中对应的 StudyPulse 实现

如果需要把文章中的示例对照到项目代码，可以从以下文件开始阅读：

- `StudyPulse/Models/SwiftData/StudyPulseModels.swift`：`@Model` 实体、索引和 struct 快照转换。
- `StudyPulse/Models/SwiftData/Schema/StudyPulseSchemaV1.swift` 到 `StudyPulseSchemaV4.swift`：冻结的版本化 schema。
- `StudyPulse/Models/SwiftData/Schema/StudyPulseMigrationPlan.swift`：V1→V2→V3→V4 迁移链。
- `StudyPulse/Managers/Core/ModelContainerFactory.swift`：生产容器、旧 JSON 导入和 store bundle 备份恢复。
- `StudyPulse/Repositories/RepositoryContainer.swift`：启动时序与 Repository 加载。
- `StudyPulse/Repositories/Default/DefaultStudySessionRepository.swift`：学习会话的独立 legacy JSON 合并。
- `StudyPulseTests/SwiftDataMigrationTests.swift`：版本迁移、字段保真和 store 恢复测试。

## 结语

版本化 SwiftData 解决的是“未来的 schema 如何演进”，老 JSON importer 解决的是“过去的数据如何进入新存储”。前者需要冻结历史、保留迁移链；后者需要一次性、可重试、可观测且不删除源文件。

当领域模型、持久化实体、迁移计划、启动编排和恢复机制各自承担清晰职责时，用户看到的就只是一次正常的应用升级：原来的成绩、错题、考试和学习记录仍然在，新的功能也可以继续使用。这才是持久化迁移真正意义上的“无感”。
