
@preconcurrency import ActivityKit
import Foundation
import HealthKit
import os

// MARK: - Study Timer Palette

/// Centralised colour & icon palette used by the StudyTimer Live Activity
/// (Lock Screen + Dynamic Island). The widget extension shares these
/// values via `StudyTimerActivityAttributes`; the main app also uses them
/// to keep in-app UI and the Live Activity in lockstep.
enum StudyTimerPalette {
    static let peakHex        = "34C759"   // green
    static let deepFocusHex   = "0A84FF"   // blue
    static let steadyHex      = "5856D6"   // indigo
    static let lightHex       = "FF9500"   // orange
    static let recoveryHex    = "FF3B30"   // red

    static let pausedHex      = "FF9500"   // orange (matches pause UI)
    static let completeHex    = "34C759"   // green
    static let endedHex       = "FF3B30"   // red

    /// Brand gradient used for the StudyPulse mark on the Lock Screen.
    static let brandGradient: [String] = [
        "0A84FF", // blue
        "5856D6"  // indigo
    ]
}

// MARK: - Timer State

enum TimerState: Equatable {
    case idle
    case running
    case paused
    case completed
}

// MARK: - Study Timer Manager

/// Manages the Pomodoro-style countdown timer, the Live Activity on
/// Dynamic Island / Lock Screen, and persistence of completed
/// sessions to `StudySessionStore`.
///
/// Session durations are adapted from the current
/// `StudyReadinessAlgorithm` intensity:
///   peak → 50 min, deepFocus → 45 min, steady → 35 min,
///   light → 25 min, recovery → 20 min.
@MainActor
@Observable
final class StudyTimerManager {
    static let shared = StudyTimerManager()

    // MARK: - Published state

    var timerState: TimerState = .idle
    var remainingSeconds: Int = 0
    var totalSeconds: Int = 0
    var currentIntensity: StudySession.SessionIntensity?
    var sessions: [StudySession] = []
    var sessionSummaries: [StudySessionSummary] = []
    var totalSessionCount: Int = 0
    var selectedInvestmentTarget: InvestmentTarget?
    private(set) var activeInvestmentTarget: InvestmentTarget?
    private(set) var lastUnlockedRewards: [GoalReward] = []

    /// The current algorithm recommendation — read by the View layer
    /// to show the suggested intensity before the user starts.
    var recommendedIntensity: StudyIntensity = .steady

    // MARK: - Heart-rate streaming state (Apple Watch real-time HR)

    /// 最新心率(Apple Watch 通过 HealthKit 写入,UI 实时显示)
    /// Latest heart rate from Apple Watch via HealthKit (for live UI).
    var currentHeartRate: Double?
    /// 已采集心率样本数(UI 提示稀疏度)
    /// Number of HR samples collected so far (UI density hint).
    var heartRateSampleCount: Int = 0
    /// 心率采集是否已启动(observer 已挂载)。UI 据此区分「未授权」vs「等待数据」。
    /// Whether HR streaming is actually active (observer mounted). UI uses this
    /// to distinguish "not authorized / disabled" from "waiting for first sample".
    var hrStreamingActive: Bool = false

    /// 会话期间内存缓存的心率样本,complete() 时写入 StudySession
    /// In-memory HR sample buffer; flushed into StudySession on complete().
    private var heartRateSamples: [HeartRateSample] = []
    private var hrObserverQuery: HKObserverQuery?
    private var hrAnchor: HKQueryAnchor?

    // MARK: - Live Activity handle

    private var currentActivity: Activity<StudyTimerActivityAttributes>?  // 当前 Live Activity 句柄(nil = 无)

    // MARK: - 内部定时器 / Internal timer

    private var internalTimer: Timer?        // 1Hz 倒计时心跳
    private var targetEndDate: Date?         // 倒计时目标结束时间(暂停时为 nil,resume 时重算)
    private var sessionRepository: (any StudySessionRepository)?
    private var timeInvestmentRepository: (any TimeInvestmentRepository)?

    private init() {
        sessions = []
    }

    func attach(
        sessionRepository: any StudySessionRepository,
        timeInvestmentRepository: any TimeInvestmentRepository
    ) {
        self.sessionRepository = sessionRepository
        self.timeInvestmentRepository = timeInvestmentRepository
        sessions = sessionRepository.sessions
        sessionSummaries = sessionRepository.sessionSummaries
        totalSessionCount = sessionRepository.totalSessionCount
        restoreLastInvestmentTarget()
    }

    func selectInvestmentTarget(_ target: InvestmentTarget?) {
        guard timerState == .idle || timerState == .completed else { return }
        guard target == nil || isSelectable(target!) else { return }
        selectedInvestmentTarget = target
        guard let target else {
            UserDefaults.standard.removeObject(forKey: "studyPulse.lastInvestmentTargetKind")
            UserDefaults.standard.removeObject(forKey: "studyPulse.lastInvestmentTargetID")
            return
        }
        UserDefaults.standard.set(target.kindRawValue, forKey: "studyPulse.lastInvestmentTargetKind")
        UserDefaults.standard.set(target.rawID.uuidString, forKey: "studyPulse.lastInvestmentTargetID")
    }

    // MARK: - Duration calculation

    /// Recommended duration in seconds for the current algorithm intensity.
    var recommendedDurationSeconds: Int {
        let sessionIntensity = StudySession.fromAlgorithmIntensity(recommendedIntensity)
        return sessionIntensity.recommendedDurationSeconds
    }

    /// Recommended duration as a human-readable string.
    var recommendedDurationLabel: String {
        let mins = recommendedDurationSeconds / 60
        return "\(mins) min"
    }

    // MARK: - Timer controls

    /// Start a countdown timer for the given number of seconds.
    /// If `seconds` is nil, the recommended duration is used.
    func start(seconds: Int? = nil) {
        let duration = seconds ?? recommendedDurationSeconds
        guard duration > 0,
              let selectedInvestmentTarget,
              isSelectable(selectedInvestmentTarget) else {
            self.selectedInvestmentTarget = nil
            return
        }

        let intensity = StudySession.fromAlgorithmIntensity(recommendedIntensity)
        currentIntensity = intensity
        activeInvestmentTarget = selectedInvestmentTarget
        totalSeconds = duration
        remainingSeconds = duration
        targetEndDate = Date().addingTimeInterval(TimeInterval(duration))
        timerState = .running

        startLiveActivity(intensity: intensity, totalSeconds: duration)
        startInternalTimer()
        startHeartRateStreaming()

        Log.app.info("StudyTimer started: intensity=\(intensity.rawValue) duration=\(duration)s")
    }

    /// Pause the timer; keeps the Live Activity but shows "Paused".
    func pause() {
        guard timerState == .running else { return }
        internalTimer?.invalidate()
        internalTimer = nil
        timerState = .paused
        updateLiveActivity()
        Log.app.info("StudyTimer paused at remaining=\(self.remainingSeconds)s")
    }

    /// Resume from paused state.
    func resume() {
        guard timerState == .paused else { return }
        targetEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        timerState = .running
        startInternalTimer()
        updateLiveActivity()
        Log.app.info("StudyTimer resumed at remaining=\(self.remainingSeconds)s")
    }

    /// Cancel the timer and discard the session.
    func cancel() {
        internalTimer?.invalidate()
        internalTimer = nil
        let wasRunning = timerState == .running || timerState == .paused
        timerState = .idle
        remainingSeconds = 0
        totalSeconds = 0
        targetEndDate = nil

        stopHeartRateStreaming()

        if wasRunning, let intensity = currentIntensity {
            let session = StudySession(
                id: UUID(),
                startDate: Date(),
                durationSeconds: 0,
                intensity: intensity,
                completed: false,
                investmentTarget: activeInvestmentTarget
            )
            persist(session)
            Log.app.info("StudyTimer cancelled (recorded as incomplete)")
        }
        endLiveActivity()
        currentIntensity = nil
        activeInvestmentTarget = nil
        resetHeartRateBuffer()
    }

    /// Called when the timer reaches 0 naturally.
    private func complete() {
        internalTimer?.invalidate()
        internalTimer = nil
        timerState = .completed
        remainingSeconds = 0

        stopHeartRateStreaming()

        if let intensity = currentIntensity {
            let session = StudySession(
                id: UUID(),
                startDate: Date().addingTimeInterval(-TimeInterval(totalSeconds)),
                durationSeconds: totalSeconds,
                intensity: intensity,
                completed: true,
                heartRateSamples: heartRateSamples.isEmpty ? nil : heartRateSamples,
                difficultyAnnotations: nil,
                investmentTarget: activeInvestmentTarget
            )
            persist(session)
            lastUnlockedRewards = timeInvestmentRepository?.evaluateRewards(
                sessions: sessions,
                now: .now
            ) ?? []
            AchievementManager.shared.recordFocusMinutes(totalSeconds / 60)
            Log.app.info("StudyTimer completed: intensity=\(intensity.rawValue) duration=\(self.totalSeconds)s hrSamples=\(self.heartRateSamples.count)")
        }
        endLiveActivity()
        // 注意:complete 后不立即清空 heartRateSamples,留给回顾 sheet 读取;
        // reset() 时再清空。
    }

    /// Reset from completed state back to idle.
    func reset() {
        timerState = .idle
        remainingSeconds = 0
        totalSeconds = 0
        targetEndDate = nil
        currentIntensity = nil
        activeInvestmentTarget = nil
        resetHeartRateBuffer()
    }

    func clearUnlockedRewards() {
        lastUnlockedRewards = []
    }

    /// 重新从磁盘加载会话列表(标注更新后同步 observable)
    /// Reload sessions from disk (sync observable after annotation updates).
    func refreshSessions() {
        if let sessionRepository {
            sessions = sessionRepository.sessions
            sessionSummaries = sessionRepository.sessionSummaries
            totalSessionCount = sessionRepository.totalSessionCount
        }
    }

    private func persist(_ session: StudySession) {
        if let sessionRepository {
            sessionRepository.upsert(session)
            sessions = sessionRepository.sessions
            sessionSummaries = sessionRepository.sessionSummaries
            totalSessionCount = sessionRepository.totalSessionCount
        } else {
            Log.data.error("StudyTimer session ignored because repository is not attached")
        }
    }

    private func restoreLastInvestmentTarget() {
        guard let kind = UserDefaults.standard.string(forKey: "studyPulse.lastInvestmentTargetKind"),
              let idString = UserDefaults.standard.string(forKey: "studyPulse.lastInvestmentTargetID"),
              let id = UUID(uuidString: idString),
              let target = InvestmentTarget(kindRawValue: kind, id: id),
              isSelectable(target) else {
            selectedInvestmentTarget = nil
            return
        }
        selectedInvestmentTarget = target
    }

    private func isSelectable(_ target: InvestmentTarget) -> Bool {
        guard let repository = timeInvestmentRepository else { return false }
        switch target {
        case .subject(let id):
            return repository.subjects.contains { $0.id == id && !$0.isArchived }
        case .subTask(let id):
            return repository.subTasks.contains { $0.id == id && !$0.isArchived }
        }
    }

    // MARK: - Heart-rate streaming (Apple Watch via HealthKit)

    /// 开始实时心率采集:挂载 HKObserverQuery + HKAnchoredObjectQuery。
    /// Apple Watch 被动写入心率样本时,观察者触发 → 锚点查询拉取增量。
    /// Start real-time HR streaming via HKObserverQuery + HKAnchoredObjectQuery.
    private func startHeartRateStreaming() {
        // 全局开关(单例只读 AppEnvironmentManager.shared.preferences,符合白名单)
        guard AppEnvironmentManager.shared.preferences.heartRateStreamingEnabled else {
            Log.app.info("StudyTimer HR streaming skipped: disabled by user preference")
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            Log.app.info("StudyTimer HR streaming skipped: HealthKit unavailable")
            return
        }

        // 检查心率类型是否已授权(不再用 isAuthorized 伞形标志,避免
        // 用户只拒绝了呼吸率/锻炼时间等无关类型就整体跳过心率采集)
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let hrAuthStatus = HealthKitManager.shared.healthStore.authorizationStatus(for: hrType)
        if hrAuthStatus != .sharingAuthorized {
            // 授权状态可能 stale,仍尝试启动(查询本身不报错,只是不返回数据)
            Log.app.warning("StudyTimer HR streaming: HR auth status=\(hrAuthStatus.rawValue), starting anyway (status may be stale)")
        }

        // 重置缓冲
        heartRateSamples = []
        heartRateSampleCount = 0
        currentHeartRate = nil
        hrAnchor = nil
        hrStreamingActive = true

        // 先做一次锚点查询拉取已有样本(会话开始时刻之前的最近样本不取,
        // 因为锚点初始 nil 会拉取所有历史。改用 predicate 限定到会话开始之后)
        let startDate = Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)

        let observer = HKObserverQuery(sampleType: hrType, predicate: predicate) { [weak self] _, _, _ in
            Task { @MainActor [weak self] in
                self?.fetchNewHeartRateSamples(since: startDate)
            }
        }
        HealthKitManager.shared.healthStore.execute(observer)
        hrObserverQuery = observer

        // 立即拉一次当前可用样本(会话开始后的新样本)
        fetchNewHeartRateSamples(since: startDate)

        // 立即查最近 15 分钟内的最新心率样本,让用户马上看到数据而非干等
        // (Apple Watch 被动采样间隔 5-10 分钟,若刚测过就先显示出来)
        fetchMostRecentHeartRate(withinMinutes: 15, sessionStart: startDate)

        Log.app.info("StudyTimer HR streaming started at \(startDate.timeIntervalSince1970)")
    }

    /// 查询最近 N 分钟内的心率样本(用于会话启动时快速回显最近一次心率)。
    /// 这些样本的时间戳在会话开始之前,不计入 heartRateSamples,
    /// 只更新 currentHeartRate 让 UI 不至于一直显示 "Waiting"。
    /// Fetch the most recent HR sample within the last N minutes (for quick
    /// display at session start). These pre-session samples are NOT added to
    /// the session buffer; only currentHeartRate is updated so the UI shows
    /// something instead of "Waiting" for the next passive sample.
    private func fetchMostRecentHeartRate(withinMinutes minutes: Int, sessionStart: Date) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let lookbackStart = sessionStart.addingTimeInterval(-Double(minutes) * 60)
        let predicate = HKQuery.predicateForSamples(withStart: lookbackStart, end: sessionStart, options: .strictStartDate)

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let sample = samples?.first as? HKQuantitySample else {
                    Log.app.debug("StudyTimer: no recent HR sample in last \(minutes) min before session")
                    return
                }
                let unit = HKUnit(from: "count/min")
                let bpm = sample.quantity.doubleValue(for: unit)
                // 仅在尚未收到会话内样本时更新(避免覆盖更新的数据)
                if self.currentHeartRate == nil {
                    self.currentHeartRate = bpm
                    Log.app.info("StudyTimer: recent HR \(Int(bpm)) bpm (sampled \(sample.startDate, privacy: .public)) shown as initial")
                }
            }
        }
        HealthKitManager.shared.healthStore.execute(query)
    }

    /// 用 HKAnchoredObjectQuery 增量拉取新样本
    /// Fetch new HR samples since anchor using HKAnchoredObjectQuery.
    private func fetchNewHeartRateSamples(since startDate: Date) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)

        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: hrAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, newSamples, deletedSamples, newAnchor, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hrAnchor = newAnchor
                let quantitySamples = newSamples as? [HKQuantitySample] ?? []
                guard !quantitySamples.isEmpty else { return }
                let unit = HKUnit(from: "count/min")
                let mapped: [HeartRateSample] = quantitySamples.map {
                    HeartRateSample(
                        id: UUID(),
                        timestamp: $0.startDate,
                        bpm: $0.quantity.doubleValue(for: unit)
                    )
                }
                self.heartRateSamples.append(contentsOf: mapped)
                self.heartRateSamples.sort { $0.timestamp < $1.timestamp }
                self.heartRateSampleCount = self.heartRateSamples.count
                if let last = self.heartRateSamples.last {
                    self.currentHeartRate = last.bpm
                }
                Log.app.debug("StudyTimer HR samples: +\(mapped.count) total=\(self.heartRateSamples.count)")
            }
        }
        HealthKitManager.shared.healthStore.execute(query)
    }

    /// 停止心率采集
    /// Stop HR streaming.
    private func stopHeartRateStreaming() {
        if let observer = hrObserverQuery {
            HealthKitManager.shared.healthStore.stop(observer)
        }
        hrObserverQuery = nil
        hrAnchor = nil
        hrStreamingActive = false
    }

    /// 清空心率缓冲(用于 cancel / reset)
    /// Clear HR buffer (used by cancel / reset).
    private func resetHeartRateBuffer() {
        heartRateSamples = []
        heartRateSampleCount = 0
        currentHeartRate = nil
        hrStreamingActive = false
    }

    // MARK: - Internal timer tick

    private func startInternalTimer() {
        internalTimer?.invalidate()
        internalTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let target = targetEndDate else { return }
        let remaining = max(0, Int(target.timeIntervalSinceNow))
        remainingSeconds = remaining

        // 每 5 帧(≈5s)推一次 Live Activity,降低系统 IPC 开销
        // Push the Live Activity every ~5 ticks (≈5s) to reduce IPC overhead.
        if remaining % 5 == 0 {
            updateLiveActivity()
        }

        if remaining <= 0 {
            complete()
        }
    }

    // MARK: - Live Activity lifecycle

    private func startLiveActivity(intensity: StudySession.SessionIntensity, totalSeconds: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Log.app.warning("StudyTimer: Live Activities not authorized, skipping activity start")
            return
        }

        let formatter = ISO8601DateFormatter()
        let attrs = StudyTimerActivityAttributes(
            intensityLabel: intensity.displayName,
            intensityIcon: intensity.icon,
            colorHex: intensity.colorHex,
            tier: intensity.rawValue,
            totalMinutes: totalSeconds / 60
        )
        let content = ActivityContent(
            state: StudyTimerActivityAttributes.ContentState(
                remainingSeconds: totalSeconds,
                totalSeconds: totalSeconds,
                intensityLabel: intensity.displayName,
                intensityIcon: intensity.icon,
                colorHex: intensity.colorHex,
                tier: intensity.rawValue,
                targetEndISO: formatter.string(from: Date().addingTimeInterval(TimeInterval(totalSeconds)))
            ),
            staleDate: Date().addingTimeInterval(TimeInterval(totalSeconds + 60))
        )

        do {
            let activity = try Activity.request(
                attributes: attrs,
                content: content,
                pushType: nil
            )
            currentActivity = activity
            Log.app.info("StudyTimer Live Activity started: id=\(activity.id)")
        } catch {
            Log.app.error("StudyTimer Live Activity failed to start: \(error.localizedDescription)")
        }
    }

    private func updateLiveActivity() {
        guard currentActivity != nil else { return }
        let formatter = ISO8601DateFormatter()
        let targetISO = timerState == .paused
            ? formatter.string(from: Date().addingTimeInterval(TimeInterval(remainingSeconds)))
            : formatter.string(from: targetEndDate ?? Date())
        let isPaused = timerState == .paused
        let label = isPaused ? "Paused".localized() : (currentIntensity?.displayName ?? "")
        let icon = isPaused ? "pause.circle.fill" : (currentIntensity?.icon ?? "timer")
        let hex = isPaused ? StudyTimerPalette.pausedHex : (currentIntensity?.colorHex ?? StudyTimerPalette.steadyHex)
        let tier = isPaused ? "paused" : (currentIntensity?.rawValue ?? "steady")

        let content = ActivityContent(
            state: StudyTimerActivityAttributes.ContentState(
                remainingSeconds: remainingSeconds,
                totalSeconds: totalSeconds,
                intensityLabel: label,
                intensityIcon: icon,
                colorHex: hex,
                tier: tier,
                targetEndISO: targetISO
            ),
            staleDate: Date().addingTimeInterval(TimeInterval(remainingSeconds + 120))
        )

        Task { @MainActor in
            if let activity = currentActivity {
                await activity.update(content)
            }
        }
    }

    private func endLiveActivity() {
        guard currentActivity != nil else { return }
        let formatter = ISO8601DateFormatter()
        let isCompleted = timerState == .completed
        let finalLabel = isCompleted
            ? "Session Complete".localized()
            : "Session Ended".localized()
        let finalIcon = isCompleted
            ? "checkmark.circle.fill"
            : "xmark.circle.fill"
        let finalHex = isCompleted
            ? StudyTimerPalette.completeHex
            : StudyTimerPalette.endedHex
        let finalTier = isCompleted ? "completed" : "ended"
        let finalContent = ActivityContent(
            state: StudyTimerActivityAttributes.ContentState(
                remainingSeconds: 0,
                totalSeconds: totalSeconds,
                intensityLabel: finalLabel,
                intensityIcon: finalIcon,
                colorHex: finalHex,
                tier: finalTier,
                targetEndISO: formatter.string(from: Date())
            ),
            staleDate: Date().addingTimeInterval(60)
        )

        Task { @MainActor in
            if let activity = currentActivity {
                await activity.end(finalContent, dismissalPolicy: .immediate)
                Log.app.info("StudyTimer Live Activity ended")
            }
            currentActivity = nil
        }
    }

    /// Clean up stale live activities on app foreground. We only end
    /// activities that are already in a terminal state (completed /
    /// ended). Activities for a still-running timer are left alone so
    /// the Dynamic Island keeps showing the countdown.
    func cleanupStaleActivities() {
        Task { @MainActor in
            for activity in Activity<StudyTimerActivityAttributes>.activities {
                let tier = activity.content.state.tier
                if tier == "completed" || tier == "ended" {
                    await activity.end(nil, dismissalPolicy: .immediate)
                    Log.app.info("StudyTimer: cleaned up stale terminal activity id=\(activity.id)")
                }
            }
        }
    }
}
