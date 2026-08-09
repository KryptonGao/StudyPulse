# 学习准备度算法

## 1. 目标

学习准备度算法把当天的 HRV 和身体状态转换为可执行的学习建议：

- 今日学习强度：Peak、Deep Focus、Steady、Light、Recovery
- 今日学习重点：优先难科、均衡学习、复习熟悉内容、错题基础或休息恢复
- 可展示给用户的解释文本

算法只在健康功能已启用、完成引导并获得授权时运行。

## 2. 输入信号

系统最多使用六个信号：

- HRV 类别
- 恢复性睡眠（深睡 + REM）
- 静息心率
- 呼吸率
- 今日运动时长
- 最近一次心率与静息心率的差值

其中 HRV 是主要信号，其余信号用于补充判断。

## 3. 信号校准

个人基线样本达到至少 7 天时，优先使用个人 30 天均值和标准差：

$$
z = \frac{x-\mu}{\max(\sigma, 0.0001)}
$$

为限制极端值影响，将 z-score 限制在 `-2～2`：

$$
z_c = \operatorname{clamp}(z,-2,2)
$$

再映射为 `0～1` 分数：

$$
s = \frac{z_c+2}{4}
$$

当个人样本不足时，使用年龄参考区间 `(low, mid, high)`：

$$
s(x)=
\begin{cases}
0, & x\leq low\ \text{或}\ x\geq high \\
\frac{x-low}{mid-low}, & low < x\leq mid \\
\frac{high-x}{high-mid}, & mid < x < high
\end{cases}
$$

缺失数据使用中性分数：

$$
s=0.5
$$

## 4. 压力值

除 HRV 外，归一化分数按照阈值转换为压力值：

$$
stress(s)=
\begin{cases}
+1, & s<0.34 \\
0, & 0.34\leq s<0.70 \\
-1, & s\geq0.70
\end{cases}
$$

含义是：

- `+1`：增加压力
- `0`：中性
- `-1`：恢复或表现良好

HRV 直接按类别映射：

$$
stress_{HRV}=
\begin{cases}
-1, & \text{excellent} \\
0, & \text{normal} \\
+1, & \text{low}
\end{cases}
$$

运动额外采用规则：30～120 分钟视为减压，超过 120 分钟视为过度运动，低于 30 分钟保持中性。

## 5. 总压力

六个信号相加：

$$
Stress_{total}=Stress_{HRV}+Stress_{sleep}+Stress_{RHR}+Stress_{RR}+Stress_{activity}+Stress_{exercise}
$$

理论范围为 `-6～+6`。

## 6. 学习强度决策

HRV 较低时，最低只能安排轻量学习：

$$
Intensity=
\begin{cases}
Recovery, & Stress_{HRV}\geq1 \land Stress_{total}\geq3 \\
Light, & Stress_{HRV}\geq1 \land Stress_{total}<3 \\
Peak, & Stress_{HRV}\leq0 \land Stress_{total}\leq-3 \\
DeepFocus, & Stress_{total}\leq-1 \\
Steady, & Stress_{total}=0 \\
Light, & 1\leq Stress_{total}\leq2 \\
Recovery, & Stress_{total}>2
\end{cases}
$$

## 7. 学习重点映射

| 学习强度 | 推荐重点 |
| --- | --- |
| Peak | 最难科目优先 |
| Deep Focus | 难科或均衡课程 |
| Steady | 均衡学习 |
| Light | 熟悉内容复习或错题基础 |
| Recovery | 休息恢复或低负担基础复习 |

## 8. 设计原则

算法不把单个指标直接等同于“今天不能学习”。它使用 HRV 作为重要约束，再用多个身体信号共同决定强度，并保留可解释的推理文本。

实现位置：

[StudyReadinessAlgorithm.swift](../../StudyPulse/Managers/Health/StudyReadinessAlgorithm.swift:377)
