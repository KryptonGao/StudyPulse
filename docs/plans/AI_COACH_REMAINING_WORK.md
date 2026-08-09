# AI Coach 后续工作清单

更新时间：2026-07-21

## 本轮已补齐

- Coach 使用 `HealthKitManager` 的 HRV z-score、准备度分类、睡眠、深睡 + REM、静息心率、呼吸率和运动分钟数。
- HealthKit 信号进入本地风险、证据和成功率修正，并随结构化分析结果传给 LLM。
- LLM 使用严格 Codable JSON 生成教练结论、学习方案、停止条件和替代方案。
- Proposal 支持过期、拒绝、确认、替代方案和历史查看。
- 目标编辑支持动态增加/删除科目、权重、基准分、目标分和满分。
- 结构化停止条件支持错题复习数量、掌握度、练习数量、知识点手动检查和学习复盘。
- StudySession 已增加 SwiftData Repository，并在启动时从旧 JSON 迁移；Coach 分析优先读取统一 Repository。
- 增加每日 BGAppRefresh 刷新、Coach 任务评估和本地通知调度。
- 增加 Coach 分析、LLM、Repository、停止条件和 ViewModel 测试基础。

## 待完成或建议继续完善

### P0：发布前验证

- 在可用的 Xcode / CoreSimulatorService 环境运行完整 `xcodebuild test`。
- 在真实 iPhone + Apple Watch 环境验证 HealthKit 授权、睡眠样本、HRV 基线和后台刷新。
- 验证 BYOK 服务返回不同 ISO-8601 日期格式时的 JSON 解析兼容性。
- 验证 BGTaskScheduler 真机调度；iOS 不保证精确执行时间，需保留前台刷新兜底。

### P1：数据层完善

- 将 StudyTimerManager、StudySessionDetailView 和 StudyTimerView 的新增/编辑操作直接写入 `StudySessionRepository`，逐步移除运行时对 `study_sessions.json` 的依赖。
- 为学习会话增加科目、目标 ID 和 Coach Task ID 的稳定关联，便于停止条件自动归因。
- 为 CoachGoal、CoachAnalysis 和 CoachProposal 增加显式 schema migration 版本，而不是仅依赖 JSON payload 兼容。
- Proposal 确认时增加真正的 SwiftData transaction / rollback 处理，覆盖批量 Todo 写入失败场景。

### P1：Coach 体验

- 为综合考试增加目标绑定选择器，并在多科目标中显示每科贡献度。
- 为 Proposal 增加“重新生成”“只采纳部分项目”和“编辑后确认”。
- 为知识点停止条件增加知识点实体或标签索引，目前仅支持人工确认。
- 将 Coach 历史中的分析结果以折线图展示，而不只显示目标版本和 Proposal 文本。
- 将 Coach 通知点击接入 AppIntent，直接打开 Coach 页面对应目标。

### P2：测试与本地化

- 增加真实 SwiftData Repository 的 CRUD、迁移和 Proposal 幂等确认测试。
- 增加 SwiftUI Preview / ViewInspector 或 XCUITest，覆盖目标编辑、Proposal 过期、确认入 Todo 和无 HealthKit 状态。
- 为 Coach 新增的所有 key 补齐 English、简体中文、繁體中文、日本語、한국어翻译。
- 增加 LLM 不可用、HealthKit 未授权、样本不足和网络超时的 UI 快照/交互测试。

### P2：产品策略

- 当前 Coach 仍按产品决策要求：未启用 LLM 时整体不可用。建议未来开放“本地预测 + 模板化 Coach”离线模式。
- HealthKit 数值只作为增强信号，不应成为目标达成率的唯一依据；后续应继续校准健康信号对成功率的影响权重。
- 需要增加模型评估数据集，比较本地预测、LLM 计划和真实考试结果，避免仅凭主观体验调整算法。
