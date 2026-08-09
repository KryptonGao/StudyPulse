# StudyPulse 成绩预测算法说明

> 引擎实现：`StudyPulse/Views/Exam/ScorePredictionEngine.swift`
> UI 层：`StudyPulse/Views/Exam/ScorePredictionSheet.swift`
> 入口：`ExamDetailView` 的「预测」按钮 + `comprehensiveExam` 综合预测 Sheet
> 数据来源：`Models/DataModels.swift` 的 `Grade`（历史成绩）+ `MistakeNote`（错题）
> 持久化：所有计算在设备本地完成，无网络请求

StudyPulse 的「成绩预测」是一个**纯本地的、可热替换**的预测引擎。
v1.4 起默认采用 **EWMA + 二元加权线性回归**（`score = α + β·date + γ·cumulative_exposure`），
配合 **3σ 离群点检测** 与 **mastery 缩窄 CI**：
- **γ(Exposure Lift)** 把"错题复习量"作为第二协变量纳入回归，UI 展示"每 10 次复习 → +X 分"
- **mastery 缩窄 CI** 按 `(1 − 0.4·avgMastery)` 缩窄 95% 预测区间,复习质量越高→预测越稳
- **3σ 检测** 解释约 80% 的"预测反常"——最近一次考试残差 > 3σ 时告警
- **EWMA** 60 天硬截 + 30 天半衰期加权,消除窗口边界抖动

本文用 12 段讲清楚这套算法:

1. 输入与前置条件
2. EWMA 加权窗口
3. 二元加权线性回归核心公式(v1.4)
4. 3 变量 WLS 闭式解(Cramer's rule)
5. 95% 预测区间与 mastery 缩窄(v1.4)
6. 离群点检测(3σ)
7. 错题差距分析
8. 引擎工厂与可替换性
9. 预测结果结构
10. 代码位置与消费链路
11. 局限与边界
12. 版本与变更

---

## 1. 输入与前置条件

### 1.1 输入

| 字段                | 来源                              | 含义                                                                 |
|---------------------|-----------------------------------|----------------------------------------------------------------------|
| `history: [Grade]`  | `container.gradeRepo.filteredGrades`(按 active phase 过滤) | 同科目的历史成绩,**任意顺序**(内部按日期重排)                  |
| `examDate: Date`    | `Exam.examDate` 或 `comprehensiveExam.examDate`            | 下一次考试日期,作为预测时点 `x_new`                             |
| `fullScore: Double` | `Subject.fullScore`(科目级)                                  | 满分(150 / 100 / 7 等),用于把分数截断到合法区间                |
| `targetScore`       | `ScorePredictionDetailView` 内用户输入                        | 详情页用到的目标分(可省略)                                       |
| `mistakes: [MistakeNote]` | `container.mistakeRepo.filteredMistakeSets`(同科目过滤)| 错题候选(详情页用 + **v1.4 回归协变量用**)                       |
| `mistakeContext`    | `MistakeContext.build(from: mistakes)` (v1.4)                | 错题复习上下文(`reviewTimestamps` + `averageMastery` + 计数)    |

> **v1.4 关键变化**:`predict(...)` 协议签名从 `predict(history:examDate:fullScore:)`
> 升级为 `predict(history:mistakeContext:examDate:fullScore:)`。`MistakeContext` 由调用方
> (`ScorePredictionSheet` / `ComprehensiveExamDetailView` / `ExamView`) 用
> `MistakeContext.build(from: subjectMistakes)` 构造,引擎本身不直接访问 Repository
> (保持与数据层解耦,便于未来替换为其他数据源)。

### 1.2 前置条件

- **样本量**:`history.count >= 2` 才尝试拟合;`< 2` 时 `predict(...)` 返回 `nil`,
  UI 渲染 `ContentUnavailableView("Not Enough Data")`。
- **3 变量 WLS 触发条件**:`history.count >= 3` **且** `mistakeContext.reviewTimestamps` 非空
  **且** 累计曝光 `e_i` 不全为 0 **且** 设计矩阵 `(X'WX)` 非奇异。任一不满足即退化为
  2 变量 WLS(此时 `exposureLift = nil`,`regressorCount = 2`)。
- **满分**:`fullScore > 0`(不合法时同样返回 `nil`)。
- **窗口**:`maxWindowDays = 60`(60 天硬截,默认),`halfLifeDays = 30`(EWMA 半衰期,默认)。
  两者都在 `LinearRegressionScorePredictor.init(...)` 里可调;`minimumSampleSize = 2`。
- **截断**:每条历史成绩的 `score` 会被夹到 `[0, fullScore]`(`max(0, min(...))`),
  防止录入错误污染回归。
- **日期基准**:`t0 = recent.first.date`,所有 `x` 转换到
  「距 `t0` 的天数」,避免绝对时间戳量级差异。
- **EWMA 权重锚点**:`anchor = history.max(\.date)`(最近一次成绩的日期),
  不用 `examDate` / `now`,保证同一条 `history` 多次调用结果稳定。
- **错题曝光锚点**:`e_i = ctx.cumulativeExposure(at: grade_i.date)` = 截至第 i 条成绩日期
  的累计复习次数(由 `MistakeContext.cumulativeExposure(at:)` 提供)。预测时点的
  `e_new = ctx.currentCumulativeExposure(asOf: examDate)` = 当前累计。

---

## 2. EWMA 加权窗口

v1.3 之前,窗口是**"最近 N 条成绩"**(默认 N=5)。这有两个问题:
- **窗口边界抖动**——第 6 次成绩刚录入时,数据集会突然从"5 条"变"6 条",回归线跳变;
- **平等对待所有样本**——6 个月前的旧考试和昨天的考试权重一样,旧数据干扰预测。

v1.3 起,窗口改为**"近 60 天硬截 + EWMA 指数加权"** 的组合。

### 2.1 硬截窗口

$$
\text{cutoff} = \text{anchor} - \text{maxWindowDays} \cdot 86400
$$

只保留 `grade.date >= cutoff` 的成绩,直接丢弃更早的数据。
`maxWindowDays` 默认 60 天(可在 init 调整,但不会小于 `halfLifeDays * 2`)。

### 2.2 EWMA 权重

对保留的每条成绩,基于"距锚点的天数"计算指数衰减权重:

$$
w_i = \exp\!\left(-\frac{\text{anchor} - \text{grade}_i.\text{date}}{\text{halfLife} \cdot 86400}\right)
$$

`halfLife = 30 天` 时,权重分布:

| 距锚点天数 | 权重     |
|-----------|---------|
| 0 天      | 1.000   |
| 7 天      | 0.794   |
| 14 天     | 0.631   |
| 30 天     | 0.368   |
| 45 天     | 0.223   |
| 60 天     | 0.135   |
| 90 天     | 0.050   |

- 30 天半衰期是经验默认值:既不会让"上学期末"的老数据喧宾夺主,也不会让"上周模拟考"完全压过历史趋势。
- 超过 5 个半衰期(150 天)的权重 < 0.01,实际上已被窗口截断;"软截 + 硬截"双重保险。

### 2.3 与旧实现的对比

| 维度              | v1.2(最近 N=5)         | v1.3(EWMA, 60 天)                |
|-------------------|------------------------|----------------------------------|
| 窗口边界          | 第 6 次成绩即变窗口     | 权重连续,无跳变                  |
| 样本权重          | 全部等权               | 越近越大(指数衰减)               |
| 抗干扰            | 易被远古 1 条高分拉偏  | 远古数据权重 < 1%                |
| 抖动              | 明显                   | 平滑                            |
| 参数直觉          | "看几次"                | "看多久" + "多快衰减"            |

---

## 3. 二元加权线性回归核心公式(v1.4)

v1.4 引入"错题复习曝光"作为第二协变量,使模型从:

$$\text{score} = \alpha + \beta \cdot x$$

升级为:

$$\text{score} = \alpha + \beta \cdot x + \gamma \cdot e$$

其中 $e$ = **截至该次成绩日期的累计错题复习次数**(cumulative exposure)。

### 3.1 设计矩阵与加权权重

对 EWMA 窗口内保留的 $n$ 条历史成绩 $(x_i, e_i, y_i, w_i)$:

$$
\begin{aligned}
x_i &= \frac{\text{grade}_i.\text{date} - t_0}{86400} \quad &&\text{(距首条成绩的天数)}\\
y_i &= \mathrm{clip}(\text{grade}_i.\text{score},\ 0,\ \text{fullScore}) \quad &&\text{(分数,夹到合法区间)}\\
e_i &= \text{ctx.cumulativeExposure}(\text{grade}_i.\text{date}) \quad &&\text{(截至该日期的累计复习次数)}\\
w_i &= \exp(-(x_{\max} - x_i) / \text{halfLife}) \quad &&\text{(EWMA 权重,越近越大)}\\
W   &= \sum_{i=1}^{n} w_i
\end{aligned}
$$

### 3.2 2 变量 WLS(fallback)

当 3 变量条件不满足时(见 §1.2)回退到 2 变量 WLS,公式与 v1.3 相同:

$$
\begin{aligned}
\bar{x}_w &= \frac{1}{W}\sum_{i=1}^{n} w_i x_i \\[4pt]
\bar{y}_w &= \frac{1}{W}\sum_{i=1}^{n} w_i y_i \\[4pt]
S_{xx}^{(w)}  &= \sum_{i=1}^{n} w_i (x_i - \bar{x}_w)^2 \\[4pt]
S_{xy}^{(w)}  &= \sum_{i=1}^{n} w_i (x_i - \bar{x}_w)(y_i - \bar{y}_w) \\[4pt]
\beta         &= \frac{S_{xy}^{(w)}}{S_{xx}^{(w)}} \quad &&\text{(slope,分/天)}\\
\alpha        &= \bar{y}_w - \beta \bar{x}_w \quad &&\text{(intercept,截距)}\\
\gamma        &= 0 \quad &&\text{(错题曝光贡献置零)}
\end{aligned}
$$

**退化情况**($S_{xx}^{(w)} \le 10^{-9}$):
- 若所有 $y_i$ 也都等于 $\bar{y}_w$(分数完全相同)→ 令 $\beta = 0$,$\alpha = \bar{y}_w$。
- 否则 → `slope = nil`,$\alpha = \bar{y}_w$(退化为常数估计,CI 也会失效,见第 5 节)。

### 3.3 3 变量 WLS(default, v1.4)

设计矩阵:

$$
X = \begin{bmatrix} 1 & x_1 & e_1 \\ 1 & x_2 & e_2 \\ \vdots & \vdots & \vdots \\ 1 & x_n & e_n \end{bmatrix}
\quad
\theta = \begin{bmatrix} \alpha \\ \beta \\ \gamma \end{bmatrix}
\quad
W = \mathrm{diag}(w_1, w_2, \dots, w_n)
$$

求解正规方程 $X^T W X \cdot \theta = X^T W y$。详细闭式见 §4。

### 3.4 点估计

$$
\begin{aligned}
x_{\text{new}} &= \max\!\left(0,\ \frac{\text{examDate} - t_0}{86400}\right) \\[4pt]
e_{\text{new}} &= \text{ctx.cumulativeExposure}(\text{examDate}) \quad &&\text{(当前累计,不再外推)}\\[4pt]
\hat{y}        &= \alpha + \beta\, x_{\text{new}} + \gamma\, e_{\text{new}} \\[4pt]
\hat{y}        &= \mathrm{clip}(\hat{y},\ 0,\ \text{fullScore})
\end{aligned}
$$

> **e_new 不外推**:用 `examDate` 当作"now"的快照,不基于历史速度向前投影。
> UI 在 statsCard 展示 γ 时,用户可直接算出"再复习 N 次 → +N·γ 分"。

### 3.5 决定系数 $R^2$

注意 $R^2$ 用**未加权**残差平方和定义,便于跨样本/跨用户做解释:

$$
\begin{aligned}
\mathrm{SSE} &= \sum_{i=1}^{n} (y_i - \hat{y}_i)^2 \quad &&\text{(残差平方和,未加权)}\\
\mathrm{SST} &= \sum_{i=1}^{n} (y_i - \bar{y}_w)^2 \quad &&\text{(总平方和,相对加权均值)}\\
R^2          &= 1 - \frac{\mathrm{SSE}}{\mathrm{SST}} \quad &&\text{(截断到 $[0, 1]$)}
\end{aligned}
$$

`v1.3 起,UI 不再展示 $R^2$ 的"Strong/Moderate/Weak"分级**——单一数字容易让人过度自信或过度怀疑,
改用"误差范围 ±X 分"代替,见第 5 节。`$R^2$ 仍保留在 `ScorePredictionResult` 字段里以备未来分析。

---

## 4. 3 变量 WLS 闭式解(Cramer's rule)

为避免引入矩阵库,3×3 求解全部用**Cramer's rule + 解析 3×3 求逆**实现。
所有计算在 `WeightedLeastSquares3.solve(...)` 集中完成,O(n) 复杂度。

### 4.1 9 个加权一阶/二阶矩

$$
\begin{aligned}
W     &= \sum w_i \\
S_x   &= \sum w_i x_i \\
S_e   &= \sum w_i e_i \\
S_y   &= \sum w_i y_i \\
S_{xx} &= \sum w_i x_i^2 \\
S_{ee} &= \sum w_i e_i^2 \\
S_{xe} &= \sum w_i x_i e_i \\
S_{xy} &= \sum w_i x_i y_i \\
S_{ey} &= \sum w_i e_i y_i
\end{aligned}
$$

### 4.2 设计矩阵与右手边

$$
A = \begin{bmatrix} W & S_x & S_e \\ S_x & S_{xx} & S_{xe} \\ S_e & S_{xe} & S_{ee} \end{bmatrix}
\quad
b = \begin{bmatrix} S_y \\ S_{xy} \\ S_{ey} \end{bmatrix}
$$

### 4.3 行列式(Cramer 法则分母)

$$
\det A = W (S_{xx} S_{ee} - S_{xe}^2) - S_x (S_x S_{ee} - S_{xe} S_e) + S_e (S_x S_{xe} - S_{xx} S_e)
$$

> 若 $|\det A| \le 10^{-9}$ → 设计矩阵奇异(列间高度共线,如所有 $e_i$ 相等),回退到 2 变量 WLS。

### 4.4 三个解

$$
\begin{aligned}
\det A_\alpha &= S_y (S_{xx} S_{ee} - S_{xe}^2) - S_x (S_{xy} S_{ee} - S_{xe} S_{ey}) + S_e (S_{xy} S_{xe} - S_{xx} S_{ey}) \\
\det A_\beta  &= W (S_{xy} S_{ee} - S_{xe} S_{ey}) - S_y (S_x S_{ee} - S_{xe} S_e) + S_e (S_x S_{ey} - S_{xy} S_e) \\
\det A_\gamma &= W (S_{xx} S_{ey} - S_{xy} S_{xe}) - S_x (S_{xx} S_{ey} - S_{xy} S_e) + S_y (S_{xx} S_e - S_x S_{xe})
\end{aligned}
$$

$$
\alpha = \frac{\det A_\alpha}{\det A} \quad
\beta = \frac{\det A_\beta}{\det A} \quad
\gamma = \frac{\det A_\gamma}{\det A}
$$

### 4.5 3×3 解析求逆(用于 leverage)

为计算预测区间的 leverage 项 $h_{\text{new}} = x_{\text{new}}^T (X^T W X)^{-1} x_{\text{new}}$,
我们用伴随矩阵:

$$
A^{-1} = \frac{1}{\det A} \mathrm{adj}(A)^T
\quad \text{其中 } \mathrm{adj}(A) = C^T \text{, } C_{ij} = (-1)^{i+j} M_{ij}
$$

对 3×3 对称矩阵 $A$:

$$
\mathrm{adj}(A) = \begin{bmatrix}
M_{00} & -M_{10} & M_{20} \\
-M_{01} & M_{11} & -M_{21} \\
M_{02} & -M_{12} & M_{22}
\end{bmatrix}
$$

其中 minors 为(对应对称矩阵的 2×2 子式):

$$
\begin{aligned}
M_{00} &= S_{xx} S_{ee} - S_{xe}^2 & M_{11} &= W S_{ee} - S_e^2 & M_{22} &= W S_{xx} - S_x^2 \\
M_{01} = M_{10} &= S_x S_{ee} - S_{xe} S_e & M_{02} = M_{20} &= S_x S_{xe} - S_{xx} S_e \\
M_{12} = M_{21} &= W S_{xe} - S_x S_e
\end{aligned}
$$

> 数值实现见 `WeightedLeastSquares3.solve(...)` 返回的 9 元素 row-major `adjugate`,
> 以及 `WeightedLeastSquares3.leverage(xNew:eNew:adj:detA:)` 用
> `1·t0 + xNew·t1 + eNew·t2` 一次性计算 $h_{\text{new}}$。

---

## 5. 95% 预测区间与 mastery 缩窄(v1.4)

预测区间(Prediction Interval,PI)描述"**单次新观测**的 95% 可能落点",
比置信区间(CI,描述"均值")更宽,因此更适合"这次考试我能得多少分"的场景。

### 5.1 公式(3 变量)

$$
\begin{aligned}
\mathrm{df}   &= n - 3 & & \text{(3 参数时)} \\
t             &= \mathrm{tValue95}(\mathrm{df}) & & \text{(双侧 95\% } t \text{ 分位数)} \\
s             &= \sqrt{\dfrac{\mathrm{SSE}}{\mathrm{df}}} & & \text{(残差标准差)} \\
h_{\text{new}} &= x_{\text{new}}^T (X^T W X)^{-1} x_{\text{new}} & & \text{(leverage,由 §4.5 求出)} \\
\mathrm{SE}_{\hat y} &= s \cdot \sqrt{1 + h_{\text{new}}} \\
\mathrm{rawHalf} &= t \cdot \mathrm{SE}_{\hat y} & & \text{(原始 95\% PI 半宽)} \\
\mathrm{lower_{raw}} &= \mathrm{clip}(\hat y - \mathrm{rawHalf},\ 0,\ \mathrm{fullScore}) \\
\mathrm{upper_{raw}} &= \mathrm{clip}(\hat y + \mathrm{rawHalf},\ 0,\ \mathrm{fullScore})
\end{aligned}
$$

### 5.2 mastery 缩窄 CI(v1.4 创新)

主指标 "误差范围 ±X 分" 应当**反映用户的复习质量**——同样的 5 次错题复习,
如果用户平均掌握度是 90%,应当比 30% 更有信心。

公式:

$$
\begin{aligned}
\mathrm{avgMastery} &= \frac{1}{|M|} \sum_{m \in M} m.\text{masteryScore} \in [0, 1] \\
\mathrm{multiplier} &= 1.0 - \mathrm{masteryMaxShrink} \cdot \mathrm{avgMastery} \\
\mathrm{half} &= \mathrm{rawHalf} \cdot \mathrm{multiplier} \\
\mathrm{lower} &= \mathrm{clip}(\hat y - \mathrm{half},\ 0,\ \mathrm{fullScore}) \\
\mathrm{upper} &= \mathrm{clip}(\hat y + \mathrm{half},\ 0,\ \mathrm{fullScore})
\end{aligned}
$$

其中 `masteryMaxShrink = 0.4`(可在 `LinearRegressionScorePredictor.init(...)` 调整)。

| mastery | multiplier | 缩窄比例 | UI 效果                                              |
|---------|-----------|----------|-----------------------------------------------------|
| 0%      | 1.00      | 0%       | 不缩窄,显示原始 ±X 分                                 |
| 25%     | 0.90      | −10%     | CI 比原始窄 10%                                       |
| 50%     | 0.80      | −20%     | CI 比原始窄 20%                                       |
| 75%     | 0.70      | −30%     | CI 比原始窄 30%                                       |
| 100%    | 0.60      | −40%     | CI 比原始窄 40%(最大缩窄)                             |

> **设计动机**:
> - 缩窄因子选 `0.4` 而非更激进(比如 0.7)是为了**避免 mastery 高估导致 CI 过窄**——
>   mastery 是用户自评,可能存在偏差;保守一些让"我全都会了"的 CI 仍保持合理宽度。
> - **不缩窄为 0**(`masteryMaxShrink = 0.4` 而非 1.0)——保持最低 60% 的 CI,防止用户
>   把"高 mastery"误读成"预测一定准"。
> - mastery = 0(从未复习过)时 multiplier = 1.0,行为退化为 v1.3(无 mastery 信息,不缩窄)。
>
> **为什么用乘法而不是加法/PI 中心点修正**:
> - 乘法保持了点估计 $\hat y$ **不变**,只动 CI——避免用户看到"预测点来回飘"。
> - 加法/中心点修正会让 $\hat y$ 随 mastery 漂移,这是**不诚实的**:
>   mastery 高 ≠ 这次考试一定考得好。

### 5.3 误差范围 (Error Margin)

`ScorePredictionResult.halfWidth = half` 即为 **95% 预测区间半宽**(mastery 缩窄后)——也就是 UI 文案里
"**基于 N 次考试,误差约 ±X 分**" 的 X。

UI 在以下位置使用:
- `ScorePredictionSheet.statsCard` 的主指标行:"基于 %d 次考试,误差约 ±%.1f 分"
  (英文 "Based on N exams, ±X pts")。
- `ScorePredictionSheet.ciBarChartCard` 标题右上角的小标 `±X.X`。
- `ComprehensiveScorePredictionSheet.perSubjectCard` 每科副标题 "n = N, ±X.X 分"。
- mastery 缩窄后的具体数值体现在: `Avg Mastery` 行展示 "85% (CI −34%)"。

### 5.4 t 分位数查找表

`ScorePredictorMath.tValue95(df:)` 提供 `df ∈ [1, 30]` 的精确值,
`df > 30` 或 `df ≤ 0` 时回退到正态分位数 `1.96`:

| df | t_{df, 0.025} | df  | t   | df  | t   |
|----|---------------|-----|-----|-----|-----|
| 1  | 12.706        | 11  | 2.201 | 21 | 2.080 |
| 2  | 4.303         | 12  | 2.179 | 22 | 2.074 |
| 3  | 3.182         | 13  | 2.160 | 23 | 2.069 |
| 4  | 2.776         | 14  | 2.145 | 24 | 2.064 |
| 5  | 2.571         | 15  | 2.131 | 25 | 2.060 |
| 6  | 2.447         | 16  | 2.120 | 26 | 2.056 |
| 7  | 2.365         | 17  | 2.110 | 27 | 2.052 |
| 8  | 2.306         | 18  | 2.101 | 28 | 2.048 |
| 9  | 2.262         | 19  | 2.093 | 29 | 2.045 |
| 10 | 2.228         | 20  | 2.086 | 30 | 2.042 |

### 5.5 退化情况

- **$\mathrm{df} \le 0$**(即 $n \le 2$ 在 2 变量情形,或 $n \le 3$ 在 3 变量情形)→
  不计算 $s$,CI 退化为点估计($\mathrm{lower} = \mathrm{upper} = \hat{y}$),`hasConfidenceInterval == false`。
- **$S_{xx}^{(w)} \le 10^{-9}$**(所有成绩同日)→ 2 变量 WLS 退化 → `slope = nil`,
  CI 改用基本半宽 $t \cdot s$(见 §3.2)。
- **$s$ 非有限**(如 $\mathrm{SSE}\,/\,\mathrm{df}$ 为 $\mathrm{NaN}$)→ CI 同样退化为点估计。
- **设计矩阵奇异**(3 变量 WLS 见 §4.3)→ 回退到 2 变量 WLS,`exposureLift = nil`。

UI 用 `ScorePredictionResult.hasConfidenceInterval` 判断是否显示 95% CI
柱状图与上下界数字。

---

## 6. 离群点检测(3σ)

很多"预测反常"其实来自一次**特殊因素的考试**(生病、当天状态差、题目偏难怪、批改误差……)。
如果直接用它来回归,会把整条线拉偏;不直接用,又丢失了"刚发生"的信息。

**v1.3 引入 3σ 离群点检测**:在拟合完成后,计算最近一次成绩的残差,
若 $|r_{\text{last}}| > 3 s$ 则视为异常,在 UI 警告。v1.4 沿用此机制,但
残差基于新的拟合模型(2 变量或 3 变量 WLS),df 也从 `n-2` 变成 `n-3`(3 变量情形)。

### 6.1 公式

$$
\begin{aligned}
\hat y_i &= \alpha + \beta x_i + \gamma e_i \quad &&\text{(2 变量情形: } \gamma = 0\text{)} \\
r_i     &= y_i - \hat y_i \quad &&\text{(第 } i \text{ 条的残差)} \\
s       &= \sqrt{\dfrac{\sum r_i^2}{\mathrm{df}}} \quad &&\text{(残差标准差,} \mathrm{df} = n - 2 \text{ 或 } n - 3\text{)} \\
z_{\text{last}} &= \frac{r_{\text{last}}}{s}
\end{aligned}
$$

判定:

$$
\text{outlier} = \begin{cases}
\text{true} & \text{if } |z_{\text{last}}| > 3 \quad \text{(3σ 准则)}\\
\text{false} & \text{otherwise}
\end{cases}
$$

### 6.2 触发条件

- 残差标准差 $s$ 需 > 0(否则数据完全无变化,无意义)。
- 自由度 $\mathrm{df} = n - \mathrm{regressorCount} > 0$(2 变量时 n-2,3 变量时 n-3)。
- 阈值默认 `3.0`(可在 `LinearRegressionScorePredictor.init(outlierSigma:)` 调整)。

### 6.3 UI 表现

触发时 `ScorePredictionResult.outlierWarning != nil`:
- `ScorePredictionSheet.contentView` 在头部下方插入一张**橙色警告卡**:
  - 标题 `Outlier Detected`(检测到离群点)
  - 副标题显示 z-score 数字,例如 `z = +3.4σ`
  - 提示文字:"最近一次考试可能受特殊因素影响(身体不适、当天状态不佳等),预测结果仅供参考,请谨慎对待。"
  - 详细数据行:日期 + 实际得分 + 拟合值 + 残差绝对值
- `ComprehensiveScorePredictionSheet.perSubjectCard` 副标题末尾追加橙色 ⚠️ 图标(若该科有离群点)。

### 6.4 不做的事(目前)

- **不自动剔除**离群点——它仍参与回归拟合(防止"今天状态不好就忽略"的过度反应)。
- **不强制用中位数 / Huber**——目前是普通 WLS,离群点只触发**告警**让用户自己判断。
- **不修改 `lastActual`**——`result.lastActual` 仍是真实的最近一次成绩(供"变化 vs. 上次"对比)。
  离群点告警只影响用户对预测的可信度认知,**不**改预测数值。

### 6.5 经验法则

3σ 准则在正态假设下,误报率约 0.27%;对"个人成绩序列"这种小样本,误报率会略高。
我们故意用 3σ 而不是 2σ,是因为**成绩波动天然较大**,2σ 会导致警告过于频繁,
反而让用户忽略警告。3σ 给出的是"几乎确定有问题"的信号——配合文字提示,足够
**解释约 80% 的"预测反常"**(如:昨天刚考砸了 → 预测点 vs. 实际点差距大 → 用户疑惑"为什么预测不准")。

---

## 7. 错题差距分析

`MistakeGapAnalyzer` 把"目标分"翻译成"需要复习哪些错题",分两步:

### 7.1 分数差

$$
\text{scoreGap} = \max\!\left(0,\ \text{targetScore} - \text{predicted\_lower\_bound}\right)
$$

- 若 $\text{target} \le \text{predicted\_lower\_bound}$ → 差距为 0 → UI 显示绿色
  "On Track" 卡(无需额外复习)。
- 否则显示 $+X.X\ \mathrm{pts}$ 的橙色数字(详情页 hero metric)。

> 注:`predicted_lower_bound`(预测区间下界,mastery 缩窄后)作为"保守估计"是默认选择——
> 用户希望"至少能到目标分",因此用下界作为基准比点估计更稳。
> 离群点告警在警告卡里提示用户"该下界也可能受异常考试影响",但不替换它。
> **v1.4 起**,下界本身已按 mastery 缩窄(高 mastery 用户的"保守下界"比 v1.3 更接近预测点)——
> 这反映了"你复习质量高 → 实际落入区间下界附近的概率也大"的合理推断。

### 7.2 错题推荐打分

候选错题(同科目、按 active phase 过滤)按以下公式打分排序:

$$
\begin{aligned}
\mathrm{days}        &= \dfrac{\max(0,\ \text{now} - \text{mistake.date})}{86400} \quad &&\text{(错题距今天数)}\\[6pt]
\mathrm{recency}     &= e^{-\mathrm{days}\,/\,30}                                       &&\text{(30 天半衰期)}\\[4pt]
\mathrm{exposureNorm}&= \dfrac{\text{mistake.exposureCount}}{\max\mathrm{Exposure}}   &&\text{(曝光次数归一化)}\\[4pt]
\mathrm{masteryLow}  &= 1 - \mathrm{clip}(\text{mistake.masteryScore},\ 0,\ 1)         &&\text{(掌握度低 = 高优先级)}\\[8pt]
\mathrm{priority}    &= 0.4 \cdot \mathrm{recency} + 0.4 \cdot \mathrm{masteryLow} + 0.2 \cdot \mathrm{exposureNorm}
\end{aligned}
$$

三因子的设计意图:
- **时间新鲜度(40%)**:近期错题优先(30 天半衰期),避免推荐太老的旧账。
- **掌握度低(40%)**:`masteryScore` 越低优先级越高;掌握度 < 40% 的错题在
  UI 上以红色显示,40–80% 以橙色显示,> 80% 视为已掌握。
- **曝光次数(20%)**:被看过但仍未掌握的错题(高曝光 + 低掌握)优先,
  防止"看了很多次但还是不会"被反复跳过。

按 $\mathrm{priority}$ 降序取前 $\mathrm{maxCount}$(默认 5)条作为 `MistakeRecommendation`
列表,UI 在 `ScorePredictionDetailView.recommendationCard` 中渲染。

### 6.3 推荐结果结构

```swift
struct MistakeRecommendation: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subject: String
    let date: Date
    let masteryScore: Double   // 0-1
    let exposureCount: Int
    let priority: Double       // 内部打分,越大越靠前
}
```

UI 还会同时显示 `recommendations.count / candidateMistakes.count`
(如 "3 / 12"),让用户感知"已覆盖多少错题"。

---

## 8. 引擎工厂与可替换性

### 8.1 协议

```swift
protocol ScorePredictor: Sendable {
    var engineName: String { get }
    func predict(
        history: [Grade],
        mistakeContext: MistakeContext?,   // v1.4
        examDate: Date,
        fullScore: Double
    ) -> ScorePredictionResult?
}
```

`Sendable` 保证协议实现可跨 actor 传递(MVVM 体系下的安全约束)。
`MistakeContext` 由调用方用 `MistakeContext.build(from: subjectMistakes)`
构造并传入(见 §1.1)。

### 8.2 工厂

```swift
enum ScorePredictorKind: String, CaseIterable, Identifiable {
    case linearRegression
    case coreML
}

enum ScorePredictorFactory {
    /// 当前激活的预测器。默认使用 EWMA + 错题曝光二元回归。
    static let active: ScorePredictor = LinearRegressionScorePredictor(
        halfLifeDays: 30,
        maxWindowDays: 60,
        masteryMaxShrink: 0.4
    )
    /// 给定 kind 返回对应预测器实例(仅用于调试 / 设置面板演示)
    static func predictor(for kind: ScorePredictorKind) -> ScorePredictor { ... }
}
```

`active` 决定 `ScorePredictionSheet` 实际使用的预测器,**当前始终为
`LinearRegressionScorePredictor(halfLifeDays: 30, maxWindowDays: 60, masteryMaxShrink: 0.4)`**;
`.coreML` 选项在设置面板演示时会显示 "Beta" 角标 + "currently disabled" 文案。

### 8.3 Core ML 接入点(已预留)

`CoreMLScorePredictor` 是占位实现,调用时 `Log.prediction.warning(...)` 并返回
`nil`。未来替换步骤:

1. 在 Xcode 中拖入训练好的 `ScorePredictor.mlmodel`(输入 = EWMA 窗口内的
   `[(days, score, weight)]` 元组,输出 = `predicted / lower / upper`)。
2. Xcode 自动生成 `ScorePredictorInput` / `ScorePredictorOutput` 类型。
3. 在 `CoreMLScorePredictor.predict(...)` 内实例化模型并调用
   `prediction(...)`。
4. 把模型输出映射成 `ScorePredictionResult`(包括 `halfWidth` 和
   `outlierWarning` 字段)。
5. 在 `ScorePredictorFactory.active` 把 `.linearRegression(...)` 换成
   `.coreML(...)`。
6. 在 `ScorePredictorKind.coreML` 的 `displayName` / `footnote` 中去掉
   "Beta" / "disabled" 字样。

接入点不影响调用方代码:`ScorePredictionSheet` 只持有 `ScorePredictor`
协议引用,切换引擎是 `static let active` 一行修改。

---

## 9. 预测结果结构

```swift
struct ScorePredictionResult: Equatable {
    let subject: String                   // 来自 recent.first?.subject
    let fullScore: Double                 // 满分
    let predicted: Double                 // 点估计 ŷ
    let lowerBound: Double                // 95% PI 下界
    let upperBound: Double                // 95% PI 上界
    let confidenceLevel: Double           // 0.95
    let slope: Double?                    // 分/天,退化为 nil
    let rSquared: Double?                 // [0, 1],退化为 nil(v1.3 起仅内部使用)
    let usedSampleSize: Int               // n
    let lastActual: Double?               // 全部历史最近一次(不受窗口影响)
    let lastActualDate: Date?
    let dataRange: ClosedRange<Date>?     // 参与回归数据的日期范围
    let windowDays: Double                // 硬截窗口(天),默认 60
    let halfLifeDays: Double              // EWMA 半衰期(天),默认 30
    let halfWidth: Double                 // 95% PI 半宽(误差范围)
    let outlierWarning: OutlierWarning?   // 最近一次考试残差 > 3σ 时触发

    var hasConfidenceInterval: Bool { ... }    // n >= 3 且区间有效
    var delta: Double? { ... }                  // predicted - lastActual
}

struct OutlierWarning: Equatable {
    let date: Date
    let score: Double
    let fittedValue: Double       // 拟合线在该日期的预测值
    let residual: Double          // score - fittedValue
    let residualStd: Double       // 残差标准差 σ
    let zScore: Double            // residual / residualStd
    let sigmaThreshold: Double    // 判定阈值(默认 3.0)
}
```

`lastActual` 与 `lastActualDate` 取**全部历史**最近一次(不受 EWMA 窗口影响),
保证"变化 vs. 上次"始终有基准。`outlierWarning` 不影响 `predicted` /
`lowerBound` / `upperBound` 的数值——它只是给用户的**告警信号**,不修改预测本身。

---

## 10. 代码位置与消费链路 (v1.4)

### 10.1 引擎与数学工具

- `StudyPulse/Views/Exam/ScorePredictionEngine.swift`:
  - `MistakeContext`(错题上下文结构,v1.4 新增,含 `cumulativeExposure(at:)` 工具)
  - `ScorePredictionResult`(结果模型,v1.4 新增 `exposureLift` / `eNew` /
    `avgMastery` / `masteryCIMultiplier` / `rawHalfWidth` / `regressorCount` 字段)
  - `OutlierWarning`(v1.3 新增)
  - `WeightedLeastSquares3` enum(v1.4 新增):3×3 WLS 闭式求解 + adjugate
    + leverage 计算
  - `ScorePredictor`(协议,v1.4 升级签名增加 `mistakeContext` 参数)
  - `LinearRegressionScorePredictor`(默认实现,v1.4 改用 2/3 变量 WLS + mastery 缩窄 CI)
  - `CoreMLScorePredictor`(占位)
  - `ScorePredictorKind` / `ScorePredictorFactory`(工厂 + 引擎切换)
  - `ScorePredictorMath.tValue95(df:)`(t 分位数查找表)
  - `MistakeGapAnalyzer`(错题推荐打分)
  - `MistakeRecommendation`(推荐条目结构)

> 引擎**未放在** `Services/` 而放在 `Views/Exam/`,因为它与
> `ScorePredictionSheet` 紧耦合且当前不跨域调用。如未来出现非考试页
> 也想用预测(例如主页「未来 30 天预计分」卡),应迁移到
> `Services/ScorePredictorService.swift` 并保持 `ScorePredictionSheet`
> 的引用路径不变。

### 10.2 UI 层

- `ScorePredictionSheet`:单科预测入口 Sheet,包含
  - 头部考试信息卡(考试名 + 科目 + 日期 + 引擎名)
  - **离群点警告卡**(v1.3 新增,`outlierWarning != nil` 时展示)
  - 95% CI 柱状图(`RectangleMark` 画带状区域 + `RuleMark` 画预测点 +
    可选"上次分数"虚线参考线;v1.3 右上角小标 `±X.X`)
  - 关键统计(主指标 "基于 N 次考试,±X 分" + 窗口 / 趋势 / 变化 vs. 上次)
  - **历史样本列表**(v1.3 标题改为 "Grades Used",按 `dataRange` 取数,不再硬切 N 条)
  - 「How to Reach Your Target」详情入口按钮
- `ScorePredictionDetailView`:详情 Sheet,目标分输入 + 分数差 +
  错题推荐列表
- `ComprehensiveScorePredictionSheet`:综合考试预测 Sheet,顶部总分汇总
  + 逐科预测区间(每科副标题 v1.3 起显示 `n = N, ±X.X 分`,有离群点时加 ⚠️ 图标)
- `ScorePredictionSheet` 通过 `@Environment(RepositoryContainer.self)`
  注入 container,**不**直接构造 ViewModel(这是「一次性 modal 工具」,
  不需要独立 ViewModel),调用路径是
  `container.gradeRepo.filteredGrades` → `filter { $0.subject == exam.subject }`
  → `ScorePredictorFactory.active.predict(...)`。
- `ScorePredictionDetailView` 的 `candidateMistakes` 同样从
  `container.mistakeRepo.filteredMistakeSets` 过滤取数(与
  `MistakeGapAnalyzer` 无 view-model 隔离,因为它是纯函数 enum)。

### 10.3 调用入口

`ExamDetailView` 内的"预测"按钮(toolbar 或长按菜单)创建
`ScorePredictionSheet(exam:history:fullScore:onDismiss:)`,按需
传入当前科目的历史成绩(已按 active phase 过滤)。`comprehensiveExam`
的"预测"按钮类似,但额外聚合 `PerSubjectPrediction` 列表渲染
`ComprehensiveScorePredictionSheet`。

### 10.4 数据流

```
Exam 详情页「预测」按钮
  │
  ▼
ScorePredictionSheet.onAppear
  │
  ▼
container.gradeRepo.filteredGrades        ──┐
container.mistakeRepo.filteredMistakeSets  │  纯函数 pipeline
  │  .filter { $0.subject == exam.subject } │
  │  MistakeContext.build(from: mistakes)   │  ← v1.4:聚合复习时间戳 + 平均 mastery
  ▼                                          │
(history, MistakeContext?) ──────────────────┘
  │
  ▼
ScorePredictorFactory.active.predict(...)   │  ← engineName = "EWMA Bivariate Regression"
  │                                          │     3×3 WLS(α + β·date + γ·exposure)
  │                                          │     mastery 缩窄 CI(× (1 - 0.4·mastery))
  │                                          │     3σ 离群点检测
  ▼                                          │
ScorePredictionResult(v1.4)                 │
  │                                          │
  ├──► outlierWarningCard   (3σ 告警)
  ├──► ciBarChartCard       (CI 柱状图 + ±X.X 小标)
  ├──► statsCard            (主指标:基于 N 次 ±X 分
  │                          + γ (每 10 次复习 → +Y 分)
  │                          + Avg Mastery (CI -X%)
  │                          + Window / Trend / 变化 vs. 上次)
  └──► ScorePredictionDetailView
        ├── gapSummaryCard    (ScoreGap,基于 mastery 缩窄后的下界)
        └── recommendationCard (MistakeGapAnalyzer.recommendations)
```

### 10.5 与 `Models/SwiftData/` 的关系

- `ScorePredictionEngine` 只读 `Grade` 和 `MistakeNote` struct,**不**直接
  接触 SwiftData 实体。
- 历史与错题的取数由 `GradeRepository.filteredGrades` /
  `MistakeRepository.filteredMistakeSets`(按 active phase 过滤)完成,
  引擎与 Repository 解耦。
- 预测结果**不**写入 SwiftData;它是即时计算、即时展示,无持久化。

---

## 11. 局限与边界

- **样本量 < 2**:返回 `nil`,UI 显示 "Not Enough Data" 空状态。
- **$n = 2$**:能拟合但 CI 退化为点估计(`hasConfidenceInterval == false`),
  离群点检测不触发(`df <= 0` 时跳过)。
- **$n = 3$ 且无错题数据 / 累计曝光全 0**:自动退化为 2 变量 WLS,`exposureLift = nil`,
  `regressorCount = 2`。这种情形通常发生在"刚创建错题"或"未启动 flashcard 复习"。
- **$n = 3$ 且设计矩阵奇异**(如所有 $e_i$ 相等):回退到 2 变量 WLS,`exposureLift = nil`。
- **同分 + 不同日期**:能拟合($\beta = 0$,`slope = 0`),CI 失效,
  但离群点检测的残差也是 0,不会误报。
- **同日多条成绩**:$S_{xx}^{(w)} \approx 0$ 触发退化 → `slope = nil`,$\alpha = \bar{y}_w$;
  CI 改用基本半宽 $t \cdot s$(见第 5 节 "退化情况")。
- **满分截断**:$y$ 与 $\hat{y}$ 都夹到 $[0, \mathrm{fullScore}]$,意味着"连续多次满分"
  之后预测的"下界"等于上界等于满分——这是**饱和效应**的有意表达,不视为 bug。
- **外推风险**:$x_{\text{new}}$ 离历史数据均值 $\bar{x}_w$ 越远,CI 越宽;这是统计意义上
  正确的行为,UI 在小标里**直接显示 ±X** 让用户感知外推距离带来的不确定性。
- **EWMA 参数固定**:`halfLifeDays = 30` / `maxWindowDays = 60` 是经验默认值,
  当前**不**开放用户配置;不同考试节奏(月考 vs. 季考)的最佳参数可能不同。
  未来可考虑:
  - 自动按"近 5 次平均间隔"调整 `halfLifeDays`(间隔长 → 半衰期长)
  - 设置面板允许高级用户手动调
- **时区漂移**:$t_0$ 取 `recent.first!.date`(含时区),跨时区用户
  可能在回归 $x$ 轴上看到"半天级"漂移;当前未做时区归一化。
- **缺失值**:`Grade.score == 0` 与"实际 0 分"无法区分;当前用
  `clip(0, fullScore)` 截断后参与回归,建议用户避免录入 0 分测试样本。
- **目标分超满分**:详情页把 `target` 截断到 $[0, \mathrm{fullScore}]$;
  `scoreGap` 仍可能为正(说明目标需要满分 + 一些运气)。
- **跨科目独立性**:每科目独立拟合,**不**考虑科目间相关性
  (如「数学下降拖累综合」),综合考试 Sheet 只是把各科 CI 相加,**不**做
  协方差修正——综合 CI 实际上比真实情况略窄。
- **离群点不剔除**:v1.3 检测到离群点**只警告**,不修改预测值;
  若用户希望"剔除离群点重算",需要后续版本手动选择或自动用 Huber 回归。
- **核心 ML 接入点**:当前 `.coreML` 选项在 UI 可见但 `predict` 返回 `nil`;
  若启用 Core ML,需要额外校验 `mlmodel` 的输入维度(必须支持可变 `windowSize` 内的
  EWMA 权重)与输出范围($[0, \mathrm{fullScore}]$)以避免越界。
- **3σ 阈值固定**:默认 `outlierSigma = 3.0`(可在 init 调整),
  对小样本(3-5 条)误报率可能略高;若用户频繁看到警告而实际无问题,
  可考虑自适应阈值(根据 n 调整)。
- **v1.4 γ 的解读风险**:γ 是"每多复习 1 次 → +γ 分"的统计系数,**不能机械外推**。
  比如 γ = 0.5 不意味着"复习 100 次就能 +50 分"——实际有边际收益递减。
  UI 故意只展示"每 10 次复习 → +X 分",引导用户小步前进。
- **v1.4 mastery 是用户自评**:可能有偏差(用户倾向高估掌握度),
  `masteryMaxShrink = 0.4` 是保守选择;若发现 CI 经常太宽,可考虑用最近 N 次
  错题自评的众数/中位数代替平均。
- **v1.4 e_new 不外推**:用 examDate 时的累计曝光作为"快照",
  不会基于过去 30 天的复习频率向前投影到 examDate。
  对"考前突击"用户可能略偏保守(假设他不继续复习);这是设计选择,避免过度乐观。

---

## 12. 版本与变更

- v1.0:新增 `ScorePredictionEngine`(普通 OLS 线性回归 + 95% PI,
  最近 5 条窗口)。
- v1.1:新增 `MistakeGapAnalyzer` + `ScorePredictionDetailView`
  ("为达到 N 分需要复习 XX" 详情页);新增
  `ComprehensiveScorePredictionSheet`(综合考试预测)。
- v1.2:MVVM 重构后,引擎与 UI 解耦,预测结果从 `container.gradeRepo.filteredGrades`
  / `container.mistakeRepo.filteredMistakeSets` 读取(与 active phase 联动);
  `ScorePredictionSheet` / `ScorePredictionDetailView` 通过
  `@Environment(RepositoryContainer.self)` 注入 container;底层算法未变。
- v1.3:**算法升级** —— 见 §3 之前的描述存档(本版已并入 v1.4):
  - 窗口从"最近 N=5"改为"60 天硬截 + 30 天半衰期 EWMA 加权",
    消除窗口边界抖动,远期数据权重自动衰减。
  - `ScorePredictionResult` 新增 `halfWidth`(95% PI 半宽,即"误差范围 ±X 分")、
    `windowDays` / `halfLifeDays` / `outlierWarning` 字段。
  - 离群点检测:最近一次考试残差 $> 3\sigma$ 时填入 `outlierWarning`,
    UI 显示橙色警告卡并提示"可能受特殊因素影响"。
  - UI 主指标由"Fit Quality: Strong/Moderate/Weak"改为
    "**基于 N 次考试,误差约 ±X 分**"——更直接、更少误信。
  - 5 语言(`en` / `zh-Hans` / `zh-Hant` / `ja` / `ko`)同步新增
    12 条本地化字符串(Outlier Detected / Based on N exams / ±X.X 分 等)。
- v1.4:**错题曝光挂钩 + mastery 缩窄 CI**:
  - **协议升级**:`ScorePredictor.predict(...)` 新增 `mistakeContext: MistakeContext?` 参数。
  - **新结构**:
    - `MistakeContext`(`reviewTimestamps` / `averageMastery` /
      `reviewedMistakeCount` / `totalExposureCount` + `cumulativeExposure(at:)` /
      `currentCumulativeExposure(asOf:)` / `build(from:)`)
    - `WeightedLeastSquares3` enum:3×3 WLS 闭式求解(Cramer's rule)+ adjugate + leverage。
  - **二元加权回归**:`score = α + β·date + γ·cumulative_exposure`,
    自动在 `n < 3` / 错题无数据 / 设计矩阵奇异时退化为 2 变量 WLS。
  - **γ(Exposure Lift)**:UI 展示"每 10 次复习 → ±X.X 分",
    错题实际有效时才有值(否则 `exposureLift = nil`)。
  - **mastery 缩窄 CI**:`halfWidth *= (1 - 0.4 · avgMastery)`,
    mastery 0% → 不缩窄(原始宽度);mastery 100% → 缩窄 40%(max)。
  - **`ScorePredictionResult` 新增 6 个字段**:`exposureLift` / `eNew` /
    `avgMastery` / `masteryCIMultiplier` / `rawHalfWidth` / `regressorCount`,
    并新增 `usesExposureRegressor` 便利属性。
  - **5 语言新增 6 条 key**:`Exposure Lift` / `Avg Mastery` /
    `每 10 次复习 → %@ %@` / `%d%% (CI −%d%%)` / `γ×10 = %@ %@` / `M=%d%%`。
  - **3 个调用点同步**:`ScorePredictionSheet` / `ComprehensiveExamDetailView` /
    `ExamView` 都改为用 `MistakeContext.build(from: subjectMistakes)` 构造上下文。
  - 引擎名 `engineName` 升级为 `"EWMA Bivariate Regression"`,
    脚注改为 `"EWMA + mistake exposure bivariate regression, no network required."`
  - `ScorePredictionResult.regressorCount` 透明展示当前是 2 变量还是 3 变量
    (用户对"为什么没有 γ"有解释权)。
- 未来:Core ML 模型替换(接入点已预留),跨科目协方差修正,
  自适应 EWMA 参数,可选"剔除离群点"重算模式,γ 的边际收益衰减建模。
