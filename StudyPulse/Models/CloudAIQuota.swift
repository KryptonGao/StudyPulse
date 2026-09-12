//
//  CloudAIQuota.swift
//  StudyPulse
//
//  Snapshot of Cloud AI membership quota from GET /api/user/dashboard.
//

import Foundation

/// Cached Cloud AI usage vs plan limits. Limits are `nil` when the account is unlimited (e.g. admin).
nonisolated struct CloudAIQuotaSnapshot: Codable, Hashable, Sendable {
    var planName: String?
    var membershipType: String?
    var membershipStatus: String?
    var dailyRequestLimit: Int?
    var monthlyPointLimit: Int?
    var usedDayRequests: Int
    var usedMonthPoints: Int
    var fetchedAt: Date

    var remainingDayRequests: Int? {
        guard let dailyRequestLimit else { return nil }
        return max(0, dailyRequestLimit - usedDayRequests)
    }

    var remainingMonthPoints: Int? {
        guard let monthlyPointLimit else { return nil }
        return max(0, monthlyPointLimit - usedMonthPoints)
    }

    var isDailyUnlimited: Bool { dailyRequestLimit == nil }
    var isMonthlyUnlimited: Bool { monthlyPointLimit == nil }

    var dayProgress: Double {
        guard let dailyRequestLimit, dailyRequestLimit > 0 else { return 0 }
        return min(1, Double(usedDayRequests) / Double(dailyRequestLimit))
    }

    var monthProgress: Double {
        guard let monthlyPointLimit, monthlyPointLimit > 0 else { return 0 }
        return min(1, Double(usedMonthPoints) / Double(monthlyPointLimit))
    }
}
