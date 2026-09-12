import XCTest
@testable import StudyPulse

final class CloudAIQuotaTests: XCTestCase {
    func testRemainingSubtractsUsedFromLimits() {
        let snapshot = CloudAIQuotaSnapshot(
            planName: "FREE",
            membershipType: "free",
            membershipStatus: "active",
            dailyRequestLimit: 5,
            monthlyPointLimit: 10_000,
            usedDayRequests: 2,
            usedMonthPoints: 6_200,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(snapshot.remainingDayRequests, 3)
        XCTAssertEqual(snapshot.remainingMonthPoints, 3_800)
        XCTAssertFalse(snapshot.isDailyUnlimited)
        XCTAssertEqual(snapshot.dayProgress, 0.4, accuracy: 0.0001)
    }

    func testRemainingDoesNotGoNegative() {
        let snapshot = CloudAIQuotaSnapshot(
            dailyRequestLimit: 5,
            monthlyPointLimit: 100,
            usedDayRequests: 9,
            usedMonthPoints: 250,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(snapshot.remainingDayRequests, 0)
        XCTAssertEqual(snapshot.remainingMonthPoints, 0)
        XCTAssertEqual(snapshot.dayProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(snapshot.monthProgress, 1, accuracy: 0.0001)
    }

    func testNilLimitsAreUnlimited() {
        let snapshot = CloudAIQuotaSnapshot(
            usedDayRequests: 12,
            usedMonthPoints: 50_000,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertNil(snapshot.remainingDayRequests)
        XCTAssertNil(snapshot.remainingMonthPoints)
        XCTAssertTrue(snapshot.isDailyUnlimited)
        XCTAssertTrue(snapshot.isMonthlyUnlimited)
        XCTAssertEqual(snapshot.dayProgress, 0)
    }

    func testDashboardJSONMapsToSnapshot() throws {
        let json = """
        {
          "success": true,
          "data": {
            "user": { "email": "user@example.com" },
            "subscription": {
              "plan": "PLUS",
              "type": "plus",
              "effective_type": "plus",
              "status": "active",
              "expire_time": null,
              "daily_request_limit": 50,
              "monthly_point_limit": 200000
            },
            "usage": {
              "quota": {
                "day": { "requests": 7, "starts_at": "2026-08-27T00:00:00.000Z" },
                "month": { "points": 1200, "starts_at": "2026-08-01T00:00:00.000Z" }
              }
            }
          }
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UserDashboardResponse.self, from: json)
        let snapshot = try XCTUnwrap(decoded.data?.makeQuotaSnapshot(fetchedAt: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(snapshot.membershipType, "plus")
        XCTAssertEqual(snapshot.dailyRequestLimit, 50)
        XCTAssertEqual(snapshot.monthlyPointLimit, 200_000)
        XCTAssertEqual(snapshot.usedDayRequests, 7)
        XCTAssertEqual(snapshot.usedMonthPoints, 1_200)
        XCTAssertEqual(snapshot.remainingDayRequests, 43)
        XCTAssertEqual(snapshot.remainingMonthPoints, 198_800)
    }

    func testOldPreferencesDecodeWithoutQuotaSnapshot() throws {
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
        XCTAssertNil(decoded.cloudQuotaSnapshot)
        XCTAssertEqual(decoded.cloudThinkingMode, .auto)
    }
}

@MainActor
final class CloudDashboardEndpointTests: XCTestCase {
    func testDashboardRejectsHTTPHostBeforeNetwork() async {
        let client = AuthClient(session: URLSession(configuration: .ephemeral))
        do {
            _ = try await client.getDashboard(sessionToken: "session", dashboardURL: "http://dash.example.com")
            XCTFail("Expected HTTP dashboard URL to be rejected")
        } catch let error as AuthError {
            guard case .missingWorkerURL = error else {
                XCTFail("Unexpected auth error: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
