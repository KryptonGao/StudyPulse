# 考前状态预测 & 倦怠检测 — 实施方案

> 状态：草案 v1
> 目的：在 StudyPulse 现有的健康信号（HRV / 睡眠 / 心率）+ 学习数据（StudySession / Diary）之上，叠加两层能力：
> 1. **考前状态预测**：把「今天该学什么强度」的日级建议，升级为「X 天后你将以什么状态进考场」的可量化预测。
> 2. **倦怠 / 过度学习检测**：连续监测「负荷 vs 恢复」失衡，在真正崩盘前给出休息建议。
>
> 核心约束：**不新增任何持久化**，全部从现有数据派生；纯函数引擎与 View / ViewModel 解耦，便于单测与未来 Widget / Shortcuts 复用。

---

## 1. 背景与目标

现状：`StudyReadinessAlgorithm`（`Managers/Health/StudyReadinessAlgorithm.swift`）已经能把 HRV + 身体信号合成当日的 `(intensity, focus)` 建议，覆盖「今天怎么学」。但缺少两个时间维度的能力：

- **面向未来**：考试临近，学生想知道「我现在的恢复趋势，到考试那天能保持住吗？」——现有建议只有今日快照，没有预测。
- **面向连续**：连续 3 天高强度学习 + 睡眠不足 + HRV 走低，现有算法每天单独看都可能给出「可继续学」的建议，缺少「你已经连续透支」的累计视图。

**目标**：
- 对每个临近考试给出 `predictedScore（0-1 预计状态）+ riskCategory + advice` 与可读的 `reasoningLines`。
- 对最近 14 天给出 `BurnoutAssessment`（low / watch / high 三档），命中即作为高优建议插入现有建议卡。
- 全程 **静默降级**：无 HealthKit 授权 / 样本不足时显示引导文案，绝不弹警告。

---

## 2. 已锁定的方向

| 决策 | 选择 | 备注 |
|---|---|---|
| 实现形态 | **纯函数引擎（`Services/`）** | 与 `StudyReadinessAlgorithm` 同风格：`nonisolated enum`，无 SwiftUI 依赖，可单测 |
| 数据来源 | **全部派生，零新增持久化** | 复用 `HealthHistoryStore` 60 天快照 + `studySessionRepo.sessions` + `diaryRepo.diaryEntries` + `examRepo` |
| 入口位置 | **主页新卡片 `examDayReadiness`（默认关闭）+ `StudySuggestionsCard` 倦怠行** | 卡片可订阅；倦怠建议复用现有 `StudySuggestion` 渲染 |
| 考试详情联动 | `ExamDetailView` 复盘区上方加「考前状态预测」行 | 以该 exam 为参数单点调用引擎 |
| 预测窗口 | **≤ 14 天** | 更长窗口预测无意义；`daysRemaining > 14` 只显示趋势不给数值分 |
| 倦怠阈值 | low / watch / high 三档 | 6 类规则加权；冷启动一律 `low` |
| LLM 增强 | Phase 3 可选 | 复用 `BodyRadarLLM` 模式：构造上下文快照 + 失败静默回退 |

---

## 3. 关键架构判断

> **核心思路**：不重搭数据系统，**编排现有原语**。

| 已有原语 | 位置 | 这次怎么用 |
|---|---|---|
| `DailyHealthSnapshot` + `HealthHistoryStore` | `Models/HealthHistory.swift`, `Managers/Health/HealthHistoryStore.swift` | 60 天滚动窗口 → 恢复趋势回归 + 个人基线 |
| `PersonalBaselines`（30 天 μ/σ，≥7 样本采信） | `Managers/Health/StudyReadinessAlgorithm.swift` | 与算法**共用同一套校准口径**，避免口径漂移 |
| `StudyReadinessAlgorithm.calibrated` | 同上 | 直接复用把单信号压成 0-1 恢复分 |
| `container.studySessionRepo.sessions` | `Repositories/Protocols/StudySessionRepository.swift` | 按日聚合 → 强度加权负荷 |
| `SessionIntensity`（5 档，含 `colorHex`） | `Models/StudySession.swift` | 负荷权重基准 |
| `DiaryEntry`（moodScore / energyScore） | `container.diaryRepo.diaryEntries` | 主观恢复信号（倦怠规则 #5） |
| `container.examRepo.filteredExamSets` | `Repositories/Protocols/ExamRepository.swift` | 预测目标（examDate / examName） |
| `StudySuggestion`（icon/title/description/priority/color） | `Managers/Health/StudyReadinessAlgorithm.swift` | 倦怠评估转成一条 `.high` 红卡建议，View 零新组件 |
| `HomeViewModel.recompute()` + dirty-flag 签名 | `ViewModels/HomeViewModel.swift` | 新状态接入现有重算管线（把 sessions / diary 加进输入签名） |
| `HomeCardType` + 渲染管线 | `Models/HomeLayoutPreference.swift`, `Views/Home/` | 新增 `case examDayReadiness`，沿用启用/排序逻辑 |

设计原则：
- **单一口径**：恢复分一律走 `StudyReadinessAlgorithm.calibrated`（个人基线优先，年龄参考兜底），预测 / 倦怠 / 雷达 / 建议看到的是同一个「恢复分」。
- **只读跨域聚合在 ViewModel 层**：引擎是纯函数，输入由 `HomeViewModel.recompute()` 一次性搜集；Repository 之间保持零耦合（符合 AGENTS.md §4）。
- **置信度显式化**：每个输出带 `confidence` / `dataCoverage`，UI 据此弱化低置信区间的措辞。

---

## 4. 数据模型（纯函数输出，无需新实体）

新增 `Services/ExamReadinessPrediction.swift`，内含 4 个引擎 + 2 个输出类型。**不触碰 SwiftData schema，无迁移。**

### 4.1 `ExamDayReadiness` — 单科考试预测

```swift
nonisolated struct ExamDayReadiness: Identifiable, Equatable {
    let examID: UUID
    let examName: String
    let examDate: Date
    let daysRemaining: Int
    /// 预计状态 0-1。窗口 > 14 天时为 nil（只显示趋势）。
    let predictedScore: Double?
    /// 恢复趋势（每天变化量，0-1 分 / 天）。
    let trendSlope: Double
    /// 数据覆盖度 0-1：近 7 天有健康样本的天数占比。
    let confidence: Double
    let riskCategory: RiskCategory
    let advice: String
    let reasoningLines: [String]
}
```

### 4.2 `RiskCategory`

```swift
nonisolated enum RiskCategory: String, Equatable {
    case strong     // predictedScore ≥ 0.7 且斜率为正
    case steady     // 0.4 ≤ predictedScore < 0.7
    case atRisk     // 0.25 ≤ predictedScore < 0.4
    case critical   // predictedScore < 0.25 或 斜率显著为负 + 高负荷
}
```

### 4.3 `BurnoutAssessment` — 倦怠评估

```swift
nonisolated struct BurnoutAssessment: Equatable {
    let riskLevel: RiskLevel          // low / watch / high
    let loadScore: Double             // 近 7 天强度加权负荷
    let recoveryScore: Double         // 今日恢复分 0-1
    let trendSlope: Double            // 14 天恢复斜率
    let triggers: [Trigger]           // 命中的规则条目（驱动 UI 文案）
    let advice: String

    nonisolated enum RiskLevel: String, Equatable {
        case low, watch, high
    }
    /// 与 `RiskCategory` 同粒度，但用 `Trigger.kind` 区分来源。
    nonisolated struct Trigger: Identifiable, Equatable {
        let id: TriggerKind
        let severity: Int             // 1..3，参与加权
        let detail: String            // 本地化文本，如 "连续 3 天高强度"
    }
    nonisolated enum TriggerKind: String, CaseIterable, Equatable {
        case loadSpike      // 规则 1：负荷尖峰
        case hrvDecline     // 规则 2：HRV 走低
        case rhrElevation   // 规则 3：静息心率抬升
        case sleepDebt      // 规则 4：睡眠债
        case moodDecline    // 规则 5：情绪下滑
        case overtraining   // 规则 6：过度运动
    }
}
```

### 4.4 内部中间类型

```swift
/// 单日恢复分（引擎内部与输出共用，避免重复计算）。
struct DailyRecoveryPoint {
    let date: Date
    let score: Double        // 0-1，口径同 StudyReadinessAlgorithm
    let isValid: Bool        // 当天是否有 ≥1 个可用信号
}

/// 单日学习负荷（强度加权分钟数）。
struct DailyLoadPoint {
    let date: Date
    let weightedMinutes: Double
    let intensity: SessionIntensity?   // 当日最重档位，用于连续高强度判定
}
```

---

## 5. 引擎设计

### 5.1 `RecoveryTrendEngine` — 恢复趋势

- 输入：`[DailyHealthSnapshot]`（降序）+ `baselines` + `age` + `now`。
- 对每一天算 `DailyRecoveryPoint`：优先复用 `StudyReadinessAlgorithm.calibrated`，把 4 项信号（恢复性睡眠 / 静息心率 / 呼吸 / HRV 类别映射）合成单日恢复分。
  - HRV 走 `hrv.category → excellent=1.0 / normal=0.6 / low=0.3`，其余信号取 `calibrated` 均分。
  - `isValid` = 当日至少 1 项信号非 nil。
- 取最近 N（默认 14）天有效点做**简单线性回归**：
  - `trendSlope = cov(x, y) / var(x)`（x = 天数索引，y = 恢复分）。
  - 有效点 < 3 时 `trendSlope = 0`，`confidence = 0`。

### 5.2 `StudyLoadEngine` — 学习负荷

- 输入：`[StudySession]`。
- 按日聚合 `weightedMinutes = Σ (durationSeconds/60) × weight`：

| SessionIntensity | 权重 |
|---|---|
| peak | 1.5 |
| deepFocus | 1.2 |
| steady | 1.0 |
| light | 0.7 |
| recovery | 0.5 |

- 输出：7 天滚动均值 `loadScore` + 连续高强度天数（连续 `peak/deepFocus` ≥ 45 min 的天数）+ 近 7 天有效学习天数。

### 5.3 `ExamDayReadinessEngine` — 预测

核心公式（纯函数，可单测）：

```
predictedScore = clamp(todayRecovery + trendSlope × daysRemaining − overloadPenalty, 0, 1)
```

- `overloadPenalty`：仅当「近 7 天负荷 > 1.5 × 个人负荷基线」且「trendSlope < 0」时生效，按剩余天数线性放大：
  ```
  overloadPenalty = 0.05 × min(daysRemaining, 14) × (loadRatio − 1.5)
  ```
  个人负荷基线 = 更早 21 天窗口的平均 `loadScore`；无历史时 penalty = 0。
- 窗口规则：
  - `daysRemaining ≤ 0`（今天/明天考）：`predictedScore = todayRecovery`，`trendSlope` 仍显示。
  - `0 < daysRemaining ≤ 14`：按公式给数值分。
  - `daysRemaining > 14`：`predictedScore = nil`，只给趋势 + 建议。
- `confidence = 近 7 天 isValid 天数 / 7`。
- `riskCategory` 映射见 §4.2；`advice` 按 (category, 是否有临近考试 < 3 天) 组合生成 3-5 条 `reasoningLines`（复用 `calibratedLine` 风格：信号 + 对比参考来源）。

### 5.4 `BurnoutDetectionEngine` — 倦怠检测

14 天窗口，6 类规则加权求和（`severity` 累计）→ `riskLevel`：

| 阈值 | riskLevel |
|---|---|
| 总分 ≥ 5 | high |
| 总分 ≥ 2 | watch |
| 其他 | low |

| # | 规则 | 判定 | severity |
|---|---|---|---|
| 1 | 负荷尖峰 | 7 天滚动负荷 > 1.5× 基线 且 连续 ≥ 3 天高强度 | 2 |
| 2 | HRV 走低 | 14 天恢复斜率 < −0.02/天 | 2 |
| 3 | 静息心率抬升 | 今日 RHR > 14 天均值 + 3 bpm | 1 |
| 4 | 睡眠债 | 近 5 晚 ≥ 2 晚恢复性睡眠 < 个人基线（或 < 年龄参考 mid） | 1 |
| 5 | 情绪下滑 | 近 7 天 diary 的 mood/energy 均值 < 前 7 天均值，且斜率为负 | 1 |
| 6 | 过度运动 | 近 3 天任一天 exerciseMinutes > 120 且当日负荷 ≥ 均值 | 2 |

- **冷启动**：无 HealthKit 授权 或 有效快照 < 7 天 → 直接 `low`，`triggers = []`，`advice` 用引导文案。
- `riskLevel == .high` 时建议文本提示「今晚提早就寝 + 明天降负荷」；`.watch` 时提示「注意观察，考虑插入休息日」。

---

## 6. 集成点（严格按 AGENTS.md 分层）

### 6.1 ViewModel 层 — `HomeViewModel`

- 新增状态：
  ```swift
  private(set) var examReadiness: [ExamDayReadiness] = []
  private(set) var burnoutAssessment: BurnoutAssessment?
  private(set) var burnoutSuggestion: StudySuggestion?   // 由评估派生，供建议卡注入
  ```
- `recompute()` 扩展：
  1. 输入追加 `container.studySessionRepo.sessions` 与 `container.diaryRepo.diaryEntries`。
  2. `recomputeSignature` 追加 sessions / diary 的 id + count 参与签名比对（沿用现有 dirty-flag 机制）。
  3. 调 `ExamDayReadinessEngine.predict(...)` 生成 `examReadiness`（对 `filteredExamSets` 全部考试排序，窗口 ≤ 14 天优先）。
  4. 调 `BurnoutDetectionEngine.assess(...)`；`riskLevel != .low` 时转成一条 `StudySuggestion`：
     - `icon = "exclamationmark.triangle.fill"`、`priority = .high`、`color = .red`，title = 「倦怠预警」，插入 `generateSuggestions(limit:)` 结果顶部。
- **零 UI 改动即可生效**：`StudySuggestionsCard` 已消费 `generateSuggestions` 返回的 `StudySuggestion` 数组。

### 6.2 视图层 — 新主页卡片 `ExamDayReadinessCard`

- 新 `HomeCardType.examDayReadiness`（默认 `enabled = false`，放 `upcomingExams` 之后）。
- 卡片内容：最近一场考试的倒计时 + 预测仪表盘（`predictedScore` 大数字 + `RiskCategory` 色块）+ 近 14 天恢复分迷你折线（复用 `Charts`）。
- 点击弹 `ExamDayReadinessSheet`：列出 `examReadiness` 全部条目（每行：考试名 / 日期 / 预计状态 / 趋势 / 依据行）。
- 无数据态：显示「连续记录健康数据后，这里会预测你考试当天的状态」引导，不显示空仪表。

### 6.3 视图层 — `ExamDetailView` 预测行

- 复盘区上方加一行「考前状态预测」：以该 exam 的 `examID` 在 `examReadiness` 中查找，命中则显示 category + 一句话建议；未命中（>14 天或无数据）显示弱化文案。

### 6.4 视图层 — `StudySuggestionsCard` 倦怠行

- 无需改 `StudySuggestionsCard`：`HomeViewModel.generateSuggestions` 已注入倦怠 `StudySuggestion`（见 §6.1）。
- 若需要独立入口（Phase 2 追加）：在卡片底部加「查看详情」跳 `ExamDayReadinessSheet`。

---

## 7. 数据层

**零改动**。全部从现有 `DailyHealthSnapshot` / `StudySession` / `DiaryEntry` / `Exam` 派生；无新实体、无 schema 迁移（schema 仍为 V4）、无新 JSON 文件。

---

## 8. 本地化

5 份 `Localizable.strings`（en / zh-Hans / zh-Hant / ja / ko）同步新增键，命名沿用现有前缀风格：

- `examReadiness.*`：`title` / `predictedScoreLabel` / `daysRemaining`（格式串，`%d` 在前）/ `trendLabel` / `confidenceLabel` / `emptyHint` / `sheetTitle`。
- `burnout.*`：`title` / `adviceHigh` / `adviceWatch` / `adviceLow` / `trigger.loadSpike` / `trigger.hrvDecline` / `trigger.rhrElevation` / `trigger.sleepDebt` / `trigger.moodDecline` / `trigger.overtraining`。
- `riskCategory.*`：`strong` / `steady` / `atRisk` / `critical`。

格式串占位符规则沿用 AGENTS.md §11 的约定（`%d` 在前、`%@` 在后，Swift 端按相同顺序传参）。

---

## 9. 测试要点

新增 `StudyPulseTests/ExamReadinessPredictionTests.swift`（沿用 XCTest 风格）：

1. **趋势引擎**：合成上升 / 下降 / 平序列 → 断言斜率符号与量级；< 3 有效点 → 斜率 0。
2. **预测公式**：`clamp` 上下界；`daysRemaining > 14` → `predictedScore == nil`；`daysRemaining ≤ 0` → 等于今日恢复分；超负荷惩罚在 (高负荷 + 负斜率) 时生效、否则为 0。
3. **风险映射**：4 类 category 的边界值。
4. **倦怠规则**：6 类触发各自独立命中（构造只满足单条的输入）；阈值 2 / 5 边界；冷启动（无授权 / <7 样本）→ 恒 `low` 且不崩溃。
5. **口径一致**：`RecoveryTrendEngine` 单日分与 `StudyReadinessAlgorithm.calibrated` 对同一输入输出一致（防口径漂移回归）。
6. **回归**：`recomputeSignature` 新增输入后 `RepositoryContainerTests` / 现有 Home 相关测试不回归。

---

## 10. 实施顺序

| Phase | 内容 | 交付 |
|---|---|---|
| P1 | `Services/ExamReadinessPrediction.swift` 引擎 + 单测 | 纯函数，可独立评审，无 UI |
| P2 | `HomeViewModel` 接入 + `examDayReadiness` 主页卡片 + `ExamDayReadinessSheet` | 本地计算，无网络依赖 |
| P3 | `ExamDetailView` 预测行 + 可选的 LLM 增强建议（复用 `BodyRadarLLM` 模式：构造 `ExamReadinessContext` 快照，失败静默回退本地文本） | 全功能 |
| P4（stretch） | 考前 ≤3 天且预测 `atRisk`/`critical` 时，`ExamReviewNotifications` 追加「今晚建议早睡」提醒 | 主动关怀 |

---

## 11. 不在 v1 范围

- 预测接入 Widget / AppIntents（引擎已具备纯函数条件，但 UI 面先做主 App）。
- 基于预测的自动调课（改 `DailyPlanEngine` 权重）——先做「看得到」，再谈「自动改计划」。
- 健康数据写入 HealthKit（`NSHealthUpdateUsageDescription` 未使用，保持现状）。
- 跨设备同步预测历史（v1 仅内存派生，随快照窗口自然过期）。

---

## 12. 风险与权衡

| 风险 | 缓解 |
|---|---|
| 预测被过度当真（学生据此考前突击/放弃） | 所有输出带 `confidence` 弱化措辞；UI 用「趋势参考」而非「确定结论」语气；窗口 >14 天不给数值分 |
| 样本稀疏导致回归失真 | 有效点 < 3 → 斜率归零 + `confidence = 0`；UI 弱化显示 |
| 与 `StudyReadinessAlgorithm` 口径漂移 | 单日恢复分直接复用 `calibrated`，并加 §9-5 口径一致性测试 |
| recompute 变重（sessions / diary 加入签名） | 沿用 dirty-flag：输入未变直接跳过；sessions 数组按 id+count 参与签名，量级可控 |
| 倦怠误报打扰用户 | 三档阈值保守；冷启动恒 low；`.watch` 只做弱提示，`.high` 才插入建议卡顶部 |

---

## 13. 验收清单

- [ ] `./scripts/build.sh` 编译通过，无新增 warning。
- [ ] 连续 3 天高强度学习 + 低 HRV 场景 → 倦怠卡显示 `high` 预警，且 `StudySuggestionsCard` 顶部出现红色「倦怠预警」。
- [ ] 恢复为正斜率 + 临近考试（≤14 天）→ 预测 `strong`/`steady`，显示数值分与依据。
- [ ] 考试 >14 天 → 只显示趋势，无数值分。
- [ ] 无 HealthKit 授权 / 新用户 → 卡片显示引导文案，无警告、无崩溃。
- [ ] 5 份 `Localizable.strings` 键齐全；格式串占位符顺序正确。
- [ ] 引擎单测全绿（§9 全部条目）。
- [ ] `recompute()` 输入未变时不触发重复重算（dirty-flag 生效）。

---

## 14. 文件清单（实现时最终要新增/改动）

| 文件 | 动作 |
|---|---|
| `Services/ExamReadinessPrediction.swift` | 新增（4 引擎 + 2 输出类型） |
| `Models/HomeLayoutPreference.swift` | 加 `HomeCardType.examDayReadiness` case + 默认顺序 |
| `ViewModels/HomeViewModel.swift` | 加 3 个状态 + `recompute()` / 签名扩展 |
| `Views/Home/HomeCards/ExamDayReadinessCard.swift` | 新增卡片 |
| `Views/Home/HomeCards/ExamDayReadinessSheet.swift` | 新增详情 sheet |
| `Views/Exam/ExamDetailView.swift` | 加预测行 |
| `StudyPulseTests/ExamReadinessPredictionTests.swift` | 新增单测 |
| `en/zh-Hans/zh-Hant/ja/ko .lproj/Localizable.strings` | 新增 §8 键 |
