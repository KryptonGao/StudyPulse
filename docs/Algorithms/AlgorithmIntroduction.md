# StudyPulse 学习建议算法说明

> 文件位置: `StudyPulse/Managers/StudyReadinessAlgorithm.swift`
> 雷达图组件: `StudyPulse/Views/Components/HRVStatusCard.swift`
> 数据来源: `StudyPulse/Managers/HealthKitManager.swift` (Apple HealthKit)

StudyPulse 的「学习建议」不是凭直觉给出的。它会先从 **Apple Health** 读入五项身体信号,
对每个信号打分,合成一个 0~1 之间的**恢复评分**,再把评分映射到 5 档**学习强度**和 5 类
**学习重点**,最终给出一条「该做什么 + 为什么」的综合建议,所有数据都可视化在主页的
「恢复雷达」卡片上。本文用三段讲清楚这套算法:

1. 输入 —— 算法读了哪 5 项身体信号
2. 评分 —— 每个信号怎么转成 0~1 的归一化分数
3. 决策 —— 怎么把分数组合成最终建议

---

## 1. 输入:五个维度的身体信号

| # | 维度 (雷达轴) | 数据源 | 含义 |
|---|---|---|---|
| 1 | **HRV** 心率变异性 | `HKQuantityTypeIdentifier.heartRateVariabilitySDNN` | 自主神经系统对压力的恢复能力,过去 14 天基线的 Z-score |
| 2 | **Heart Rate** 静息心率 | `HKQuantityTypeIdentifier.restingHeartRate` | 近 7 天最新读数,反映心血管压力 |
| 3 | **Recovery Sleep** 恢复性睡眠 | `HKCategoryTypeIdentifier.sleepAnalysis` | 最近一次睡眠中 **深睡 (N3/SWS) + REM** 的总时长 —— 这两段才是大脑和身体真正"恢复"的阶段;Core/Asleep 不计入 |
| 4 | **Workout** 今日锻炼 | `HKQuantityTypeIdentifier.appleExerciseTime` | 今日累计 Apple 锻炼时间 (健身记录中的绿色圆环) |
| 5 | **Respiratory** 呼吸频率 | `HKQuantityTypeIdentifier.respiratoryRate` | 近 24h 最新读数,反映压力 / 疾病 |

> **为什么是深睡 + REM,不是总睡眠?**
> 一次 8 小时、总深睡+REM 只有 1h 的"假长睡",比一次 6 小时、深睡+REM 占了 3h 的"实短睡"恢复效果更差。总睡眠时长仍会在卡片上以"·7.3h"形式附在深睡+REM 数字之后,作为背景信息。

所有数据都通过 `requestAuthorization(toShare: [], read: ...)` 一次性向用户申请,读权限不写入。
数据仅保存在设备本地 (~/Documents 与 UserDefaults),不向任何服务端上传。

---

## 2. 评分:信号 → 0~1

每个维度独立归一化到 `[0, 1]`,越大代表越有利于高强度学习。

### 2.1 雷达图的归一化 (用于五边形可视化)

每个信号都通过 `StudyReadinessAlgorithm.calibrated(value:baseline:range:)` 校准成 0-1 分数,
校准遵循**双层参考**:

1. **个人 30 天基线优先** —— 当 `baselines.<signal>.sampleCount >= 7` 时,使用 Z-score:
   `z = (value - mean) / stddev`,截断到 `[-2, +2]`,映射到 `[0, 1]`。
   这意味着:即使 60 bpm 对一个运动员来说"正常偏高",只要他自己的 30 天均值是 55,60 bpm 仍然能拿到 0.6+ 的分数。
2. **年龄段参考回退** —— 历史样本不足 7 天时,使用 `AgeReference` 中的分年龄段 `Range(low, mid, high)`,
   `mid` 是"理想点" (score=1.0),`low`/`high` 之外为 0,中间走折线。
   `mid` 的设定对"越低越好"的信号 (如静息心率) 放在低端,对"越高越好"的信号 (如 HRV) 放在上端。

| 维度 | 个人路径 | 年龄参考路径(回退) |
|---|---|---|
| **HRV** | 14 天 Z-score,已存在于 `HRVReadiness.zScore`,沿用其分类 | — |
| **Heart Rate** | 30 天 Z-score | 13-17 岁: `low 45 / mid 60 / high 100`;成人: `low 45 / mid 60 / high 90` |
| **Recovery Sleep** (深睡+REM 小时) | 30 天 Z-score | 13-17 岁: `low 1.5 / mid 3.0 / high 4.5`;成人: `low 1.0 / mid 2.5 / high 4.0` |
| **Workout** (今日锻炼 min) | 30 天 Z-score | `low 0 / mid 30 / high 90` (WHO 每日 30 min 推荐) |
| **Respiratory** (brpm) | 30 天 Z-score | `low 10 / mid 14 / high 20` (接近 14 brpm 为最佳) |

缺失数据用 **0.5 (中性)** 兜底,避免雷达图塌缩成一个点。

每个分轴按 4 档配色: `<0.34 红`、`<0.5 橙`、`<0.75 蓝`、`≥0.75 绿`,
便于一眼看出哪一维偏弱。

### 2.2 算法建议的"压力分" (用于决策)

雷达归一化分只用于**展示**。在算法内部,每个信号被映射成一个 **stress score**:
`-1 (恢复)`、`0 (中性)`、`+1 (压力)`,然后求和得到 `totalStress`。
当数据缺失时,该项贡献 `0` —— 缺失不会拖累评分,也不会假性拔高。

校准后的 0-1 score 通过 `scoreToStress(score, lowScore:+1, highScore:-1)` 转 stress:
`score < 0.34 → +1`、`0.34 ≤ score < 0.7 → 0`、`score ≥ 0.7 → -1`。

| 信号 | 评分规则 (stress) |
|---|---|
| **HRV** | excellent → -1; normal → 0; low → +1; 缺失 → 0 |
| **Recovery Sleep (深睡+REM)** | score ≥ 0.7 → -1; 0.34–0.7 → 0; < 0.34 → +1; 缺失 → 0 |
| **Heart Rate** | score ≥ 0.7 → -1; 0.34–0.7 → 0; < 0.34 → +1; 缺失 → 0 |
| **Respiratory** | score ≥ 0.5 → 0; < 0.5 → +1; 缺失 → 0 |
| **Recent Activity** | 瞬时 HR - 静息 HR ≥ 25 → +1; 否则 → 0 |
| **Workout** | 30-120 min → -1 (减压); >120 min → +1 (过度训练); 其他 → 0; 缺失 → 0 |

---

## 3. 决策:5 档强度 × 5 类重点 = 9 种建议

### 3.1 强度判定 (HRV 是硬覆盖)

```
if hrvStress >= 1:
    intensity = (totalStress >= 3) ? recovery : light
elif totalStress <= -3:   intensity = peak            # 需 3+ 个积极信号
elif totalStress <= -1:   intensity = deepFocus
elif totalStress ==  0:   intensity = steady
elif totalStress <=  2:   intensity = light
else:                     intensity = recovery
```

> **为什么 HRV 是硬覆盖?**
> HRV 是 14 天基线 Z-score,是 5 个信号里**唯一**经过统计校准的恢复指标;
> 当 HRV 已经提示"低于基线"时,任何其他信号都不能把它"抵消"成正常日。
> 反之,当 HRV 显示"高于基线"时,即便其他指标也紧张,也会被拉回到 `deepFocus` 至少,
> 避免"明明恢复得很好,却建议用户休息"。
>
> **为什么 peak 门槛是 -3?**
> 把单一信号 -1 视为"恢复中",需要至少 3 个不同维度的信号同时积极 (HRV + 2 个其他)
> 才推荐"巅峰发挥日",防止"HRV 正常 + 睡眠糟糕"被误判为"最佳状态"。

### 3.2 重点判定

| 强度 | 选择重点 | 触发条件 |
|---|---|---|
| peak | hardestSubjectFirst | 全维积极 → 先攻克最难的科目或完整模拟 |
| deepFocus | hardestSubjectFirst | HRV / 睡眠 / 静息心率 三个主要恢复信号都未提示压力 → 仍然先难后易 |
| deepFocus | balancedCurriculum | 上述任一主要信号提示压力 → 2-3h 深度学习块、学科均匀分配 |
| steady | balancedCurriculum | 1-2h 专注块、学科均衡推进 |
| light | mistakesAndBasics | HRV 是主因 → 错题 + 基础,等身体跟上 |
| light | reviewFamiliar | 压力来自其他维度 → 复习熟悉内容、避免新题 |
| recovery | restAndBreathe | HRV 低 + 睡眠差 + 呼吸/心率异常 → 呼吸练习或散步 |
| recovery | mistakesAndBasics | 多维压力但尚未到 "需要完全休息" → 轻量错题 + 笔记整理 |

> (intensity, focus) 的 25 种组合里,只有这 8 种是评分规则真正可达的;其余通过
> `default` 分支兜底为 steady/balanced,作为安全网。

### 3.3 输出

每条建议包含 5 个字段:

- `title` — 标题,例:「巅峰发挥日」
- `description` — 说明 + 依据(逐条列出触发该建议的具体信号事实)
- `priority` — `high / medium / low`
- `color` — 与建议的紧迫度匹配 (绿 → 蓝 → 橙 → 红)
- `icon` — SF Symbol,例:`bolt.heart.fill`、`wind`

`依据` 段落使用 bullet 形式自动拼出,例:

```
依据:
• HRV 高于基线 +2.6σ
• 恢复性睡眠 2.1h (深 1.0h · REM 1.1h) — 暂用年龄段参考
• 静息心率 61 bpm — 暂用年龄段参考
• 呼吸 17 次/分 — 暂用年龄段参考
• 今日锻炼 2 min — 暂用年龄段参考
• 尚无 30 天数据,使用年龄参考 · 年龄 13
```

---

## 4. 雷达图与健身圆环的渲染

### 4.1 五边形雷达 (5 维)

- 顺时针顺序(从 12 点方向开始):HRV → Heart Rate → Recovery Sleep → Workout → Respiratory
- 同心四边形栅格(25% / 50% / 75% / 100%)
- 5 个数据点用各轴独立颜色,白色描边
- 缺失数据点位于 0.5 半径(中性位置),形状保持平衡

### 4.2 健身圆环 (Workout 维度)

复刻 iOS Activity 圆环的视觉:
- 单环进度条,`progress = min(1, exerciseMinutes / 30)`
- 角度渐变 (AngularGradient) 反映当前完成度
  - `< 34%`:红 → 橙
  - `34%-70%`:橙 → 黄
  - `70%-99%`:绿 → 薄荷
  - `≥ 100%`:薄荷 → 绿
- `easeOut 0.6s` 动画,值变化时平滑过渡
- 在雷达卡片的「轴值行」里占据 Workout 槽位,与其它四维并列

---

## 5. 调参与扩展

所有阈值都在 `StudyReadinessAlgorithm.swift` 顶部以常量 / 静态表形式集中:

```swift
// 如需调整,在源文件搜索下列注释即可
- HRV 分类阈值 (Z-score 边界, 位于 HealthKitManager.refreshReadiness)
- 静息心率年龄分档 (AgeReference.compute, 各 case 的 low/mid/high)
- 呼吸频率阈值 (> 0.5 score, 即 ageRef 折线 < 14 brpm)
- 恢复性睡眠年龄分档 (AgeReference.compute 中 restorative Range)
- 锻炼时长分档 (30-120 min sweet spot, 120+ 过度训练)
- 30 天基线最少样本数 (StudyReadinessAlgorithm.minPersonalSamples, 默认 7)
- Peak 门槛 (recommend() 中的 totalStress <= -3)
```

增加新维度只需要:

1. 在 `BodyStatus` 加一个 `Double?` 字段
2. 在 `HealthKitManager` 添加对应的 `fetch*` 方法并加进 `readTypes`
3. 在 `PersonalBaselines` 与 `AgeReference` 加对应字段
4. 在 `BodyRadarValues.compute` 里加归一化逻辑
5. 在 `StudyReadinessAlgorithm.recommend` 里加 stress 计算
6. 在 `BodyRadarChart` 调整 `dimensionCount` / `axisLabels` / `axisColors`
7. 在 5 份 `Localizable.strings` 添加新轴标签的翻译

---

## 6. 局限

- iPhone-only 用户缺少 HRV 与睡眠的连续数据,算法会自动降级为
  「数据不足 → 跳过身体建议」,仍会输出纯成绩 / 错题建议。
- 睡眠阶段的细分 (深睡/REM) 来自 Apple Watch 用户的 `HKCategoryValueSleepAnalysis`。
  没有手表、或未开启"睡眠跟踪"权限的用户,深睡/REM 字段为 `nil`,
  算法会回退到个人均值路径 (若 30 天数据不足则该项不参与评分)。
- 阈值参考的是普通人群体均值,运动员、青少年、孕期等人群可能需要单独校准。
- 算法只为建议,不能替代医生。如果持续感到异常,请优先就医。

---

## 7. 代码位置与消费链路 (v1.2)

`StudyPulse/Managers/Health/StudyReadinessAlgorithm.swift` 提供顶层
`recommend(...)` 静态实现,纯函数 `nonisolated` enum,可被任意 actor
调用。**视图层不直接调用算法**,消费链路如下:

1. **`HealthKitManager.shared`**(`StudyPulse/Managers/Health/HealthKitManager.swift`)
   提供三类运行时数据:`BodyStatus`(5 维身体信号,心率 / 呼吸率 / 深睡+REM / 锻炼)、
   `PersonalBaselines`(30 天个人基线,持久化于
   `~/Documents/health_history.json`,由 `HealthHistoryStore` 管理)、
   `HRVReadiness`(14 天 SDNN Z-score 分类)。
2. **`StudyReadinessAlgorithm.recommend(hrvEnabled:bodyStatus:baselines:hrvReadiness:)`**
   输入上述数据,输出 `StudyRecommendation { intensity, focus }` (5 档 × 5 重点 → 25 种
   组合;未覆盖组合回退到 `steady / balanced`)。
3. **`HomeViewModel`**(`StudyPulse/ViewModels/HomeViewModel.swift`)
   把 `StudyRecommendation` 与今日具体上下文 (错题 SRS 队列、即将到来的考试、
   未登记考试等) 打包成 `StudySuggestionsContext`,再调用
   `Services/SuggestionEngine.swift` 的 `generate(from:max:)`
   把 `StudyRecommendation` 翻译为用户可见的 `StudySuggestion` 列表
   (最多 5 条,每条带本地化文案与 `Color`)。
4. **`HomeView`** + 主页「Study Suggestions」卡片按 ViewModel 暴露的
   `suggestions` 渲染;`HRVStatusCard` 同时显示 `StudyRecommendation`
   的 radar。

涉及类型:
- `HealthKitManager.BodyStatus`(`HealthKitManager` 内定义,非 SwiftData)。
- `HealthKitManager.PersonalBaselines`(`HealthKitManager` 内定义)。
- `HealthKitManager.HRVReadiness`(`HealthKitManager` 内定义)。
- `StudyReadinessAlgorithm.StudyRecommendation` / `StudyIntensity` / `StudyFocus`。
- `StudySuggestion`(`Services/SuggestionEngine.swift` 产出,
  **唯一**引用 `SwiftUI` 的纯函数服务,因 `color: Color`)。

注意:
- `Models/SwiftData/StudyPulseModels.swift` 不涉及算法;`HealthHistory`
  单独持久化为 `~/Documents/health_history.json`(NSLock 线程安全),
  **不**写入 SwiftData。
- `StudyReadinessAlgorithm` 自身是 `nonisolated` enum,
  `HomeViewModel` 是 `@MainActor ObservableObject`;ViewModel 在主线程调用
  `recommend(...)` 不会触发 actor hop,结果赋给 `@Published` 即触发
  SwiftUI 重渲染。
- MVVM 重构前,`HomeView` 直接调用算法;v1.2 之后 View 层只读
  `HomeViewModel` 暴露的状态,保证 5 个主页面 + ViewModel + Service
  架构一致。

---

## 8. 版本与变更

- v1.0:HRV 单独 5 档(`excellent` / `normal` / `low` / `insufficient` / `noAuthorization`),
  视图层直接读 `HealthKitManager.readiness`。
- v1.1:引入 `BodyStatus`(5 维身体信号)与 `PersonalBaselines`(30 天个人基线),
  算法升级为 5 档 × 5 重点 → 25 种组合,HRV 仍为硬覆盖;
  新增 `StudyReadinessAlgorithm` 与 `SuggestionEngine` 拆分。
- v1.2:MVVM + Repository 重构后,`StudyReadinessAlgorithm` 与
  `SuggestionEngine` 进一步解耦,`StudySuggestion` 由 `HomeViewModel` 协调
  产出;底层评分函数未变,但消费路径由 `HomeView → algorithm` 变为
  `HomeView → HomeViewModel → algorithm + SuggestionEngine`。
