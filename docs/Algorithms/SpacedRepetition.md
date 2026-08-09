# SM-2 间隔重复算法

## 1. 目标

系统根据用户对错题的复习评价，动态决定下一次复习时间。算法服务于错题 SRS 队列，核心目标是让已经掌握的内容逐渐拉长复习间隔，让遗忘或困难的内容更快回到复习队列。

输入包括：

- 当前复习状态
- 本次复习评价：Again、Hard、Good、Easy
- 用户自评难度 `1～5`
- 当前时间

输出包括：

- 连续复习次数
- 下一次复习间隔
- 难度系数
- 遗忘次数
- 下一次复习日期

## 2. 状态字段

每道加入 SRS 的错题维护一个 `ReviewState`：

$$
S = (r, EF, I, D, L)
$$

其中：

- (r)：连续复习成功次数 `repetitions`
- (EF)：难度系数 `easeFactor`，初始值为 `2.5`
- (I)：当前复习间隔天数 `intervalDays`
- (D)：下一次复习日期 `nextReviewDate`
- (L)：累计遗忘次数 `lapses`

难度系数的最小值为：

$$
EF_{min} = 1.3
$$

## 3. 四档复习评价

### 3.1 Again

表示用户基本忘记，重新进入学习模式：

$$
r' = 0
$$

$$
I' = 1
$$

$$
L' = L + 1
$$

$$
EF' = \max(1.3, EF - 0.20)
$$

### 3.2 Hard

表示记忆困难，但仍然答对：

$$
r' = r + 1
$$

$$
I' =
\begin{cases}
1, & r'=1 \\
4, & r'=2 \\
\max(1, \operatorname{round}(I \times 1.2)), & r' \geq 3
\end{cases}
$$

$$
EF' = \max(1.3, EF - 0.15)
$$

### 3.3 Good

表示正常掌握，使用标准 SM-2 间隔增长：

$$
r' = r + 1
$$

$$
I' =
\begin{cases}
1, & r'=1 \\
6, & r'=2 \\
\operatorname{round}(I \times EF), & r' \geq 3
\end{cases}
$$

### 3.4 Easy

表示轻松掌握，间隔增长更快：

$$
r' = r + 1
$$

$$
I' =
\begin{cases}
4, & r'=1 \\
7, & r'=2 \\
\operatorname{round}(I \times EF \times 1.3), & r' \geq 3
\end{cases}
$$

$$
EF' = \min(3.0, EF + 0.15)
$$

## 4. 难度后置调权

SM-2 计算出基础间隔后，再根据用户自评难度进行缩放：

$$
I'' = \max(1, \operatorname{round}(I' \times M_d))
$$

| 难度 | 乘数 |
| ---: | ---: |
| 未评或非法值 | 1.00 |
| 1 星 | 0.50 |
| 2 星 | 0.75 |
| 3 星 | 1.00 |
| 4 星 | 1.30 |
| 5 星 | 1.60 |

## 5. 下一次复习日期

下一次复习日期以当天零点为基准，加上最终间隔，并统一安排在上午 9:00：

$$
D' = \operatorname{StartOfDay}(now) + I''\text{ 天} + 09{:}00
$$

这样可以避免用户在深夜完成复习后收到深夜提醒。

## 6. 队列与统计

只有 `nextReviewDate <= now` 且已经加入 SRS 的错题才属于到期错题：

$$
\text{Due} = \{m \mid m.reviewState \neq nil \land m.nextReviewDate \leq now\}
$$

系统同时统计未来 7 天内到期的错题，提供 SRS 总览。

## 7. 设计原则

该实现保留 SM-2 的“掌握越好、间隔越长”思想，同时增加了项目自己的难度后置调权。用户的困难评价不会覆盖 SM-2 状态，而是作为额外修正，因此复习质量和主观难度可以分别影响调度。

实现位置：

[SpacedRepetition.swift](../../StudyPulse/Models/SpacedRepetition.swift:116)
