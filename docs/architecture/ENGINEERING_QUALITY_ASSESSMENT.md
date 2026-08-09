# StudyPulse iOS

## 工程质量、架构成熟度与技术债务评估报告

### Engineering Quality, Architecture Maturity & Technical Due Diligence Report

| 文档属性 | 内容 |
| --- | --- |
| 文档编号 | `SP-ENG-QA-2026-0802` |
| 文档版本 | `v1.0` |
| 文档状态 | 正式评估稿 |
| 评估类型 | 源码工程质量与架构成熟度评估 |
| 评估对象 | StudyPulse iOS 工程当前源码树 |
| 评估基线 | `e39478af` / `codex/localization-xcstrings` |
| 评估日期 | 2026-08-02 |
| 资料属性 | 内部技术评审资料 |
| 综合等级 | **B+ / 7.0 分（满分 10 分）** |

> **正式评估意见：有条件通过（Conditionally Qualified）。**  
> 该工程已具备持续承载复杂产品能力的架构基础与工程组织能力；在完成中心节点治理、关键持久化路径验证及发布证据补齐之前，本意见不应被解释为生产发布批准或安全性认证。

---

## 1. 管理层摘要（Executive Summary）

StudyPulse 已由单一 SwiftUI 应用演进为具备领域划分、持久化演进能力、系统级集成能力及 AI 扩展能力的**模块化单体应用（Modular Monolith）**。

源码结构显示，项目已形成中大型产品所需的主要工程支柱：MVVM、Repository、Service、SwiftData 版本化迁移、测试替身、Widget/Live Activity、健康数据、备份恢复及 LLM 子系统均已建立可识别的职责边界。当前主要矛盾已由功能实现能力转移至复杂度控制、依赖方向治理及持续验证证据的完整性。

本次评估的核心判断如下：

> **StudyPulse 的架构基础与功能工程化水平达到良好等级；当前主要质量风险源于复杂度集中、中心节点承压及关键运行证据尚未形成闭环，而非基础架构缺失。**

基于现有证据，项目具备继续演进的条件，但后续治理重点应由单纯的功能扩张转向可维护性、可验证性与依赖治理。若持续向中心容器、超大文件及跨层调用叠加职责，系统的认知负担、变更影响面和回归概率将呈累积性上升。

本报告属于基于源码证据的工程评估，不构成发布认证、生产就绪声明或安全合规结论。对于本次未重新执行的完整构建、测试套件、运行时性能、并发安全及真实数据迁移验证，本报告不将其计入正向证据。

---

## 2. 综合评估结论（Assessment Scorecard）

| 评估维度 | 评分 | 判断 |
| --- | ---: | --- |
| 架构分层与领域组织 | 8.0 | 分层清晰，模块覆盖完整，具备持续演进基础 |
| 持久化与数据演进 | 8.0 | SwiftData Schema 版本化和迁移意识较强 |
| 模块化与依赖治理 | 6.5 | 目录划分良好，但中心节点和跨层引用偏多 |
| 可维护性 | 6.5 | 功能完整度高，但超大文件和中心服务增加认知负担 |
| 可测试性 | 7.0 | 测试基础设施完整，但本次未重新验证覆盖率和全套结果 |
| 文档与可理解性 | 7.0 | 核心架构说明充分，代码注释密度中等 |
| 发布证据完整度 | 未定级 | 本次未执行完整 build/test/release 验证 |
| **综合判断** | **7.0** | **工程基础良好，已进入复杂度治理阶段** |

评分为面向工程决策的启发式成熟度评价，不代表 ISO、CMMI、SRE 或商业静态分析工具认证结果。评分的主要用途是识别治理优先级，而非替代发布验收。

### 2.1 评估等级释义

本报告采用 A–E 五级工程成熟度分级：

- **A：卓越**——架构、验证、治理和发布证据均形成稳定闭环。
- **B：良好**——基础能力完整，具备持续演进条件，但仍存在明确治理项。
- **C：受控不足**——核心能力存在，但复杂度或验证缺口已显著影响演进。
- **D：高风险**——关键边界失效，变更和运行风险不可接受。
- **E：不可评估/不可持续**——缺乏必要结构或有效工程证据。

StudyPulse 当前处于 **B+：良好，具备持续演进条件，但必须落实 P1 级治理事项**。

### 2.2 证据等级与结论约束

为避免将静态观察误认为运行时事实，本报告对证据采用以下分级：

| 证据等级 | 定义 | 本报告用途 |
| --- | --- | --- |
| **A 级** | 可由当前源码树直接复核的文件、行数、依赖和目录数据 | 支撑规模、耦合、内聚代理指标 |
| **B 级** | 可由架构文件、协议、测试替身和持久化 Schema 推断的工程能力 | 支撑架构成熟度判断 |
| **C 级** | 需要重新执行构建、测试、真机迁移或运行时分析才能确认的事项 | 仅作为待验证项，不计入正向证据 |

本报告的综合评分主要由 A 级和 B 级证据构成；所有 C 级事项均保留为发布前验证条件。

---

## 3. 规模与代码基线

### 3.1 源码规模

| 范围 | Swift 文件 | 物理行 | 代码行 | 注释行 | 空行 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 主应用 `StudyPulse` | 430 | 95,947 | 73,631 | 14,051 | 8,562 |
| Widget | 14 | 1,499 | 1,167 | 175 | 160 |
| 测试与 TestData | 50 | 7,041 | 5,835 | 396 | 817 |
| 当前全部 Swift 源码 | 495 | 104,842 | 80,894 | 14,661 | 9,596 |

主应用注释密度为：

- 按总物理行计算：14.6%
- 按非空行计算：16.1%

全部 Swift 源码注释密度为：

- 按总物理行计算：14.0%
- 按非空行计算：15.4%

注释密度处于中等水平，已能够支撑一般性代码理解；但对于算法、持久化迁移、跨进程桥接和 AI 请求契约等高认知负担区域，仍应优先补充设计意图、约束条件和失败模式，而非局限于逐行解释。

### 3.2 代码分布

主应用的代码主要集中在以下区域：

- `Views/`：43,804 行代码，占主应用代码约 59.5%
- `Managers/`：13,328 行，占约 18.1%
- `Models/`：5,749 行，占约 7.8%
- `Repositories/`：3,807 行，占约 5.2%
- `ViewModels/`：3,480 行，占约 4.7%
- `Services/`：2,546 行，占约 3.5%

该分布符合 SwiftUI 产品的常见形态，但也提示 UI 层已经是主要复杂度承载区。后续应避免让复杂业务规则继续向 View 的 `body`、sheet 组合和状态转换中沉积。

---

## 4. 架构成熟度评估

### 4.1 架构定位

经本次评估，StudyPulse 的架构定位可表述为：

> **以 MVVM 为表现层组织方式、以 Repository 为数据访问边界、以 SwiftData 为持久化后端、以 Services/Managers 为领域能力承载的模块化单体。**

从能力边界和生命周期覆盖范围判断，该工程已超出单纯的 SwiftUI 页面集合范畴，形成了跨页面、跨进程和跨生命周期的系统能力，包括：

- 版本化 SwiftData Schema 与迁移计划
- RepositoryContainer 统一依赖装配
- Widget、Live Activity 和 AppIntents 桥接
- HealthKit、EventKit、Vision 等系统能力接入
- LLM 配置、缓存、流式响应和结构化输出约束
- 备份、恢复、校验和数据迁移
- 测试 Fixture、Mock Repository 和基础设施工厂

上述能力表明，项目已具备一定的平台化工程特征，整体工程形态已超出单一页面驱动型应用的初级阶段。

### 4.2 架构优势

#### 持久化演进意识较强

SwiftData Schema 采用版本化组织，新增持久化实体通过迁移演进，而不是直接修改历史 Schema。这是移动端数据安全中非常关键的工程习惯。

#### 领域边界已经成形

成绩、错题、考试、任务、日记、学习会话、时间投入、健康、成就、植物和 LLM 等能力已经在目录和类型层面形成了可识别边界。新功能能够找到相对明确的落点，不需要全部堆入单一 View 或单一 Manager。

#### 测试可替换性达到良好水平

Mock Repository、TestModelContainer、TestRepositoryContainer 和算法测试的存在，说明代码并非完全依赖真实 SwiftData 环境。这为后续建立回归测试和架构守护测试提供了基础。

#### 系统能力接入较完整

HealthKit、Widget、Live Activity、AppIntents、备份恢复和 LLM 均涉及复杂的生命周期、权限和失败恢复问题。项目已将这些能力纳入统一工程边界，而非停留在孤立的验证性实现层面。

---

## 5. 耦合度与内聚度诊断

### 5.1 文件级耦合指标

对主应用 430 个 Swift 文件进行源代码定义类型引用扫描，过滤注释、字符串和系统类型扩展后得到：

- 内部有向依赖边：2,244
- 平均文件出度：5.22
- 平均文件入度：5.22
- 文件依赖图密度：1.2%
- 跨顶层目录依赖：60.1%
- 平均每个文件的去重 `import`：1.71 个
- 最大文件出度：56
- 最大文件入度：166

该结果表明，项目尚未形成不可治理的全局耦合网络，但跨目录依赖已占据多数，当前关键问题在于模块间连接密度偏高，而非模块划分缺失。

### 5.2 中心节点

#### 高出度节点

- `Repositories/RepositoryContainer.swift`：56
- `Views/Home/HomeView.swift`：46
- `StudyPulseApp.swift`：32
- `Views/Mistake/MistakeSetDetailView.swift`：23
- `Managers/LLM/CoachLLM.swift`：22
- `Managers/Mistake/KnowledgeFaultLineAIProvider.swift`：21

#### 高入度节点

- `Models/DataModels.swift`：166
- `Repositories/RepositoryContainer.swift`：146
- `Managers/LLM/LLMClient.swift`：94
- `Managers/Logging/Log.swift`：83
- `Managers/Report/WeeklyReportManager.swift`：80
- `Models/SpacedRepetition.swift`：77

其中 `RepositoryContainer` 同时具备高出度和高入度，是当前最显著的架构枢纽。其承担依赖装配和跨域 facade 职责具有合理性；但若继续无边界扩展，将形成典型的中心化上帝对象风险，并进一步放大系统级变更影响面。

### 5.3 顶层目录结构性内聚度

本报告使用以下结构性代理指标：

> 目录内依赖边 ÷ 该目录全部依赖边

| 顶层目录 | 文件数 | 目录内依赖 | 跨目录依赖 | 结构性内聚度 |
| --- | ---: | ---: | ---: | ---: |
| `Intents` | 11 | 17 | 8 | 68.0% |
| `Models` | 31 | 109 | 75 | 59.2% |
| `Managers` | 85 | 242 | 194 | 55.5% |
| `Views` | 210 | 423 | 639 | 39.8% |
| `Repositories` | 39 | 88 | 144 | 37.9% |
| `Services` | 20 | 10 | 65 | 13.3% |
| `ViewModels` | 23 | 4 | 183 | 2.1% |

`ViewModels` 和 `Services` 的数值偏低，主要是因为它们天然承担跨层协调职责。这是需要关注的信号，但不能直接等同于低质量；更准确的解读是：这两个区域需要更明确的输入输出契约和依赖方向约束。

---

## 6. 可维护性风险与技术债务热点

### 6.1 超大文件风险

当前最大的文件包括：

- `Models/SwiftData/StudyPulseModels.swift`：1,683 行
- `Managers/LLM/LLMRequestBuilder.swift`：1,508 行
- `Models/DataModels.swift`：1,188 行
- `Managers/LLM/LLMClient.swift`：961 行
- `Managers/Core/DataExportManager.swift`：952 行
- `Managers/Health/HealthKitManager.swift`：902 行
- `Views/Exam/ScorePredictionEngine.swift`：886 行

文件规模本身不构成缺陷判定依据，但超大文件通常意味着数据定义、转换逻辑、策略判断、请求构造或系统服务协调等职责存在同文件聚集现象。其主要风险包括：

- 修改影响面难以预测
- 测试定位粒度不足
- Review 时难以识别行为变化
- 新功能更容易继续堆叠到现有中心文件

### 6.2 中心容器膨胀风险

`RepositoryContainer` 当前承担 Repository 聚合、跨域 facade、阶段过滤、待办聚合、批量操作、通知与部分启动编排。它已经是系统中最重要的依赖节点之一。

建议保持以下边界：

- Container 只负责依赖装配和稳定 facade
- 跨域聚合继续下沉到独立 Orchestrator/Service
- ViewModel 不直接依赖未使用的全量 Repository
- 新增业务域优先通过窄接口或 feature-scoped container 接入

### 6.3 UI 层复杂度

`Views/` 占主应用代码近六成，且存在多个高出度页面。对 SwiftUI 来说，这通常意味着视图组合、sheet 导航、异步任务、状态同步和展示逻辑容易互相缠绕。

建议将以下内容稳定地移出 View：

- 数据聚合与排序
- 表单校验和错误恢复
- LLM prompt 组装
- 迁移和持久化操作
- 复杂的导航状态机
- 跨页面通知或生命周期协调

---

## 7. 风险登记册（Risk Register）

| 风险项 | 等级 | 影响 | 现状判断 |
| --- | --- | --- | --- |
| `RepositoryContainer` 中心化 | P1 | 高 | 当前已是最高入度/出度节点，应限制继续膨胀 |
| 超大模型、LLM 和系统服务文件 | P1 | 中高 | 修改和 Review 成本持续增加 |
| ViewModel 跨层依赖过密 | P1 | 中高 | 结构性内聚度仅 2.1%，需要依赖方向治理 |
| SwiftData/JSON/备份多路径演进 | P1 | 高 | 数据正确性需要持续迁移和恢复测试保护 |
| 运行时构建与完整测试证据 | P1 | 高 | 本次未重新执行，不能据此宣称发布就绪 |
| 注释和设计意图不足 | P2 | 中 | 总体密度尚可，但复杂边界需要更强契约文档 |
| Widget/AppIntents/Live Activity 跨进程一致性 | P2 | 中高 | 能力完整，仍需持续验证生命周期和数据同步 |

---

## 8. 治理建议与实施路径

### 阶段一：复杂度止增（0–2 周）

1. 暂停向 `RepositoryContainer` 添加大段业务逻辑。
2. 为新增功能规定 feature-owned ViewModel 和 feature-scoped Service。
3. 将 `StudyPulseModels.swift`、`LLMRequestBuilder.swift` 和 `DataModels.swift` 按领域继续拆分。
4. 为关键 SwiftData migration、备份恢复和学习会话建立最小回归集合。
5. 对当前高入度节点建立基线，后续 Review 禁止无理由显著上升。

### 阶段二：依赖方向治理（2–6 周）

1. 明确依赖方向：View → ViewModel → Service/Repository → Persistence。
2. 禁止 View 直接触碰 SwiftData Context 和持久化实体。
3. 将跨域聚合固定在 Orchestrator 或专用 Service 中。
4. 将 LLM caller、请求构造、响应解析和缓存继续维持为独立边界。
5. 增加静态架构守护检查，检测反向依赖和高风险模块穿透。

### 阶段三：工程质量量化（6–12 周）

1. 引入 SwiftSyntax/SourceKitten 级别的 AST 分析。
2. 计算类型级 CBO、LCOM4、RFC、WMC 和依赖方向违规数。
3. 建立 CI 中的构建、单元测试、迁移测试和关键路径测试门禁。
4. 记录代码规模、中心节点入度/出度、超大文件数量的趋势。
5. 对备份恢复、Schema migration、LLM 错误恢复和跨进程同步进行故障注入测试。

---

## 9. 建议纳入的工程质量控制线

后续迭代可以采用以下轻量门禁：

- 新增业务不得直接扩大 `RepositoryContainer` 的跨域职责。
- 新增 View 不直接依赖 SwiftData 实体或持久化 Context。
- 新增单文件超过 800 行时必须说明拆分理由或提交拆分计划。
- 新增持久化实体必须同时提供迁移测试和备份兼容性测试。
- 新增 LLM caller 必须具备固定输出契约、错误路径和缓存策略。
- 关键功能提交必须提供真实 build/test 结果，不以静态分析代替运行验证。
- 所有架构指标应观察趋势，避免把单次数字误用为绝对质量结论。

---

## 10. 最终评估意见

StudyPulse 已具备继续承载复杂产品功能的工程基础。基于本次源码证据，当前工程状态可概括为：

> **Architecture Foundation: Strong**  
> **Feature Engineering Capability: High**  
> **Maintainability Pressure: Rising**  
> **Release Evidence: Requires Continuous Verification**

项目最值得保护的资产是已有的领域边界、Repository 抽象、Schema 迁移意识和测试基础设施；最需要治理的对象是中心容器、超大文件、跨层 ViewModel 依赖以及持久化/备份/跨进程路径的组合复杂度。

因此，本项目不宜被归类为架构失序，也不应被视为已经完成成熟度闭环。更准确的专业判断是：

> **StudyPulse 是一个工程基础良好、产品能力完整、目前正由功能扩张阶段转入架构治理阶段的中大型 Swift 工程。**

在保持功能交付能力的同时，若优先降低中心节点压力、补齐运行验证证据并建立可持续的架构指标基线，项目的长期可维护性、变更可预测性和发布可信度仍可获得显著提升。

---

## 附录 A：评估方法、证据等级与边界

本次统计使用当前源码树进行静态扫描，范围包括：

- `StudyPulse/`
- `StudyPulseWidget/`
- `StudyPulseTests/`
- `TestData/`
- 根目录 Swift 工具文件

排除第三方包、构建产物、DerivedData、缓存和 `.zcode/`。

代码量统计按物理行、代码行、注释行和空行拆分。注释统计支持行注释、嵌套块注释和行内注释分类。

耦合度扫描会移除注释和字符串，识别源代码定义的 `class`、`struct`、`enum`、`protocol`、`actor`、`typealias` 及其有效 extension，并按文件之间的唯一依赖关系计数。

内聚度是目录级结构性代理指标，不是严格的类型级 LCOM。它无法直接表达运行时动态调用、协议派发、闭包捕获、SwiftUI 环境注入或 SwiftData 隐式关系。

本报告未在本次任务中重新执行：

- 完整 Xcode build
- 完整单元测试套件
- 代码覆盖率
- Instruments 性能分析
- 真机数据迁移与恢复
- 运行时并发和生命周期验证

因此，报告中的“工程质量”是基于源码结构、规模、依赖关系、已有架构说明和可见测试组织得出的静态评估，不替代发布前验证。

## 附录 B：重点参考位置

- [RepositoryContainer.swift](../../StudyPulse/Repositories/RepositoryContainer.swift)
- [StudyPulseModels.swift](../../StudyPulse/Models/SwiftData/StudyPulseModels.swift)
- [DataModels.swift](../../StudyPulse/Models/DataModels.swift)
- [LLMClient.swift](../../StudyPulse/Managers/LLM/LLMClient.swift)
- [StudyPulseTests](../../StudyPulseTests)
