//
//  SpacedRepetitionTests.swift
//  StudyPulseTests
//
//  Unit tests for SRSAlgorithm (Models/SpacedRepetition.swift).
//  Focus: intervalDays hard cap (M-08) across good/easy/difficulty paths.
//

import XCTest
@testable import StudyPulse

final class SpacedRepetitionTests: XCTestCase {

    // Fixed reference: 2026-06-15 12:00:00 UTC
    private let now: Date = {
        var c = DateComponents()
        c.year = 2026
        c.month = 6
        c.day = 15
        c.hour = 12
        c.minute = 0
        c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }()

    private func makeState(
        repetitions: Int = 5,
        easeFactor: Double = 2.5,
        intervalDays: Int
    ) -> ReviewState {
        ReviewState(
            repetitions: repetitions,
            easeFactor: easeFactor,
            intervalDays: intervalDays,
            nextReviewDate: now
        )
    }

    // MARK: - M-08 intervalDays hard cap (730)

    func test_easyOverflow_isClampedTo730() {
        // 连续 easy + 最高难度乘子:指数增长路径,逐步断言封顶
        // Repeated `easy` reviews with the max difficulty multiplier:
        // the exponential path must stay capped at every step.
        var state = ReviewState.initial(now: now)
        for _ in 0..<30 {
            state = SRSAlgorithm.apply(
                quality: .easy, to: state, difficulty: 5, now: now
            )
            XCTAssertLessThanOrEqual(
                state.intervalDays, SRSAlgorithm.maxIntervalDays,
                "intervalDays must never exceed the hard cap"
            )
            XCTAssertGreaterThanOrEqual(state.intervalDays, 1)
            // 日期加法不得溢出回退到 now
            // date(byAdding:) must not overflow back to now.
            XCTAssertGreaterThan(state.nextReviewDate, now)
        }
        // 30 次 easy 后必然到达上限
        // 30 easy reviews must reach the cap.
        XCTAssertEqual(state.intervalDays, SRSAlgorithm.maxIntervalDays)
    }

    func test_goodBranch_isClampedTo730() {
        // 700 × easeFactor 2.5 = 1750 → clamp 730
        let state = makeState(intervalDays: 700)
        let next = SRSAlgorithm.apply(quality: .good, to: state, now: now)
        XCTAssertLessThanOrEqual(next.intervalDays, SRSAlgorithm.maxIntervalDays)
        XCTAssertEqual(next.intervalDays, 730)
        XCTAssertGreaterThan(next.nextReviewDate, now)
    }

    func test_difficultyMultiplier_respectsCap() {
        // good 分支 clamp 到 730 后再乘 5 星乘子 1.6,仍不得超限
        // Even after the good-branch clamp, the 5-star multiplier (1.6×)
        // must not push the interval past the cap.
        let state = makeState(intervalDays: 690)
        let next = SRSAlgorithm.apply(
            quality: .good, to: state, difficulty: 5, now: now
        )
        XCTAssertLessThanOrEqual(next.intervalDays, SRSAlgorithm.maxIntervalDays)
        XCTAssertEqual(next.intervalDays, 730)
    }

    func test_normalPath_isUnaffectedByCap() {
        // 低间隔不受 clamp 影响
        // Low intervals pass through untouched.
        let state = makeState(repetitions: 2, intervalDays: 6)
        let next = SRSAlgorithm.apply(quality: .good, to: state, now: now)
        // rep=3 → default 分支: 6 × 2.5 = 15
        XCTAssertEqual(next.intervalDays, 15)
    }
}
