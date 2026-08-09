# StudyPulse 文档中心

这里是 StudyPulse 的文档入口。文档按“谁来读、解决什么问题”分层；新增文档时请放入对应主题目录，不要直接堆在 `docs/` 根目录。

## 文档地图

### 算法

面向算法规则、输入输出、评分公式和边界条件。

- [学习建议算法](algorithms/AlgorithmIntroduction.md)
- [学习准备度算法](algorithms/StudyReadiness.md)
- [错题保质期](algorithms/MistakeShelfLife.md)
- [错题掌握度 EMA](algorithms/MasteryEMA.md)
- [间隔重复（SM-2）](algorithms/SpacedRepetition.md)
- [今日计划优先级](algorithms/DailyPlan.md)
- [本地成绩预测](algorithms/ScorePrediction.md)
- [成绩预测完整说明](algorithms/ScorePredictionAlgorithm.md)

### 产品

面向产品范围、用户价值和界面设计约束。

- [产品介绍](product/Introduction_Chinese.md)
- [产品规范](product/SPEC.md)
- [设计规范](product/DESIGN.md)

### 架构与工程

面向开发者、维护者和技术评审。

- [代码维基（中文）](architecture/CODE_WIKI_CN.md)
- [Code Wiki（English）](architecture/CODE_WIKI.md)
- [工程质量与架构成熟度评估](architecture/ENGINEERING_QUALITY_ASSESSMENT.md)
- [代码现代化计划](architecture/MODERNIZATION_PLAN.md)
- [Phase 5 持久化性能](architecture/Phase5PersistencePerformance.md)
- [版本化 SwiftData 迁移](architecture/SwiftDataVersionedMigration.md)

### 实施方案与待办

面向已经提出、正在实施或需要后续验证的功能方案。

- [AI Coach 后续工作](plans/AI_COACH_REMAINING_WORK.md)
- [考前状态预测与倦怠检测](plans/ExamReadinessPrediction.md)
- [学习连续剧与成就系统](plans/STREAK_ACHIEVEMENT_PLAN.md)

### 参考资料

面向应用内展示、贡献者和用户协议。

- [常见问题](reference/FAQ.json)
- [贡献指南](reference/CONTRIBUTING.json)
- [用户使用协议](reference/USER_AGREEMENT.md)

## 维护约定

- `docs/` 根目录只保留本索引；图片统一放在 `images/`。
- 纯算法文档放入 `algorithms/`；产品定义放入 `product/`；代码、架构和性能放入 `architecture/`；尚未完全落地的方案放入 `plans/`；应用内或社区参考资料放入 `reference/`。
- 文档中的仓库链接使用相对路径，不要写入个人电脑的绝对路径。
- 修改源码中的算法、持久化、产品或设计规则时，同步检查对应文档和根目录的 `README.md`、`AGENTS.md`。
