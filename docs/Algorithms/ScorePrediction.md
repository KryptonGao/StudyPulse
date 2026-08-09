# 本地成绩预测算法

## 1. 目标

系统根据近期考试成绩和错题复习记录，预测某科目下一次考试的分数，并给出预测区间、趋势斜率、错题复习影响和离群点提示。

当前默认实现是纯 Swift 的 EWMA 二元加权线性回归，不依赖网络。Core ML 预测器目前仅保留接口，尚未启用。

## 2. 数据窗口与权重

只使用最近一次成绩之前最多 60 天的数据：

$$
t_i \geq t_{latest}-60\text{ 天}
$$

越近的成绩权重越高，半衰期为 30 天：

$$
w_i=\exp\left(-\frac{\Delta days_i}{30}\right)
$$

因此：

- 当天数据权重为 `1.0`
- 30 天前约为 `0.5`
- 60 天前约为 `0.25`

## 3. 回归变量

每条成绩包含三个变量：

- (x_i)：距离窗口第一条成绩的天数
- (e_i)：截至该成绩日期的累计错题复习曝光次数
- (y_i)：成绩，限制在 `0～满分`

当错题复习次数达到至少 3 次，且数据矩阵不退化时，使用：

$$
\hat y = \alpha+\beta x+\gamma e
$$

其中：

- (eta)：时间趋势，每天成绩变化
- (gamma)：每次错题复习曝光对应的成绩变化
- (alpha)：回归截距

## 4. 加权最小二乘

通过最小化加权残差平方和拟合参数：

$$
\min_{\alpha,\beta,\gamma}\sum_i w_i\left(y_i-\alpha-\beta x_i-\gamma e_i\right)^2
$$

代码使用 (3\times3) 正规方程，并通过 Cramer 法则闭式求解：

$$
(X^TWX)\theta=X^TWy
$$

$$
\theta=
\begin{bmatrix}
\alpha\\
\beta\\
\gamma
\end{bmatrix}
$$

当样本不足、错题曝光不足或矩阵奇异时，退化为只使用时间变量的二元模型：

$$
\hat y=\alpha+\beta x
$$

## 5. 下一次考试预测

给定考试日期 (x_{new}) 和预计累计曝光 (e_{new})：

$$
\hat y_{new}=\alpha+\beta x_{new}+\gamma e_{new}
$$

如果样本少于 3 条，或预测值撞到分数边界，则使用 EWMA 加权平均作为更保守的点估计。

## 6. 预测区间

系统使用残差估计误差，并结合杠杆值计算 95% 预测区间：

$$
PI_{95\%}=\hat y\pm t_{df,0.975}\cdot s\sqrt{1+h_{new}}
$$

其中：

- (s)：残差标准差
- (h_{new})：预测点的杠杆值
- (t_{df,0.975})：对应自由度的 t 分布临界值

## 7. 掌握度缩窄区间

当错题复习数据充足时，平均掌握度会缩窄预测区间：

$$
HalfWidth_{final}=HalfWidth_{raw}\times(1-0.4\times Mastery)
$$

掌握度为 0 时不缩窄，掌握度为 1 时区间半宽缩小到原来的 60%。

## 8. 离群点检测

对最近一次成绩计算残差：

$$
r_{last}=y_{last}-\hat y_{last}
$$

当满足以下条件时，显示离群点提示：

$$
\left|\frac{r_{last}}{\sigma_r}\right|>3
$$

这用于提示成绩可能受到生病、状态异常或特殊考试环境影响，而不是直接删除该成绩。

## 9. 设计原则

该算法更重视近期数据，但不会只看最近一次成绩；同时将错题复习作为可解释的行为变量。预测结果必须显示数据量和置信度，避免把小样本外推误认为确定结论。

实现位置：

[ScorePredictionEngine.swift](../../StudyPulse/Views/Exam/ScorePredictionEngine.swift:1)
