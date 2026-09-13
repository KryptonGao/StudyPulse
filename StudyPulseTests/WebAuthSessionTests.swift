import AuthenticationServices
import UIKit
import XCTest
@testable import StudyPulse

@MainActor
final class WebAuthSessionTests: XCTestCase {
    func testAuthenticationWithoutAnchorFailsBeforePresenting() async {
        let auth = WebAuthSession(anchorProvider: { nil })
        do {
            _ = try await auth.authenticate()
            XCTFail("Authentication must fail when no foreground window is available.")
        } catch {
            XCTAssertEqual(
                error as? WebAuthError,
                .oauthFailed("Unable to start the secure login session.")
            )
        }
    }

    func testPresentationContextReturnsExistingWindow() {
        let window = UIWindow()
        let context = WebAuthPresentationContext(anchor: window)
        let session = ASWebAuthenticationSession(
            url: WebAuthSession.loginURL, callbackURLScheme: "studypulse"
        ) { _, _ in }
        XCTAssertTrue(context.presentationAnchor(for: session) === window)
    }

    func testLoginURLUsesEncodedReturnToCallback() throws {
        let state = "test-state"
        let loginURL = WebAuthSession.makeLoginURL(state: state)
        let components = try XCTUnwrap(URLComponents(url: loginURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "auth.chenkai.space")
        let returnTo = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "return_to" })?.value)
        let callback = try XCTUnwrap(URLComponents(string: returnTo))
        XCTAssertEqual(callback.scheme, "studypulse")
        XCTAssertEqual(callback.host, "auth")
        XCTAssertEqual(callback.path, "/callback")
        XCTAssertEqual(callback.queryItems?.first(where: { $0.name == "state" })?.value, state)
    }

    func testCallbackParsesBothTokens() throws {
        let url = try XCTUnwrap(URL(string: "studypulse://auth/callback?state=state-1&access_token=access%201&refresh_token=refresh%2B1"))
        XCTAssertEqual(
            try WebAuthCallbackParser.parse(url, expectedState: "state-1"),
            AuthTokenPair(accessToken: "access 1", refreshToken: "refresh+1")
        )
    }

    func testCallbackRejectsMissingRefreshToken() throws {
        let url = try XCTUnwrap(URL(string: "studypulse://auth/callback?state=state-1&access_token=access"))
        XCTAssertThrowsError(try WebAuthCallbackParser.parse(url, expectedState: "state-1")) { error in
            XCTAssertEqual(error as? WebAuthError, .refreshTokenMissing)
        }
    }

    func testCallbackReportsOAuthFailure() throws {
        let url = try XCTUnwrap(URL(string: "studypulse://auth/callback?state=state-1&error=access_denied&error_description=GitHub%20denied"))
        XCTAssertThrowsError(try WebAuthCallbackParser.parse(url, expectedState: "state-1")) { error in
            XCTAssertEqual(error as? WebAuthError, .oauthFailed("GitHub denied"))
        }
    }

    func testCallbackRejectsMissingAndMismatchedState() throws {
        let missing = try XCTUnwrap(URL(string: "studypulse://auth/callback?access_token=a&refresh_token=r"))
        XCTAssertThrowsError(try WebAuthCallbackParser.parse(missing, expectedState: "expected")) { error in
            XCTAssertEqual(error as? WebAuthError, .stateMissing)
        }

        let mismatched = try XCTUnwrap(URL(string: "studypulse://auth/callback?state=other&access_token=a&refresh_token=r"))
        XCTAssertThrowsError(try WebAuthCallbackParser.parse(mismatched, expectedState: "expected")) { error in
            XCTAssertEqual(error as? WebAuthError, .stateMismatch)
        }
    }

    func testCallbackStateIsConsumedOnceAndExpires() throws {
        let suiteName = "StudyPulse.AuthStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = AuthCallbackStateStore(defaults: defaults, keyPrefix: "test", lifetime: 60)
        let start = Date(timeIntervalSince1970: 10_000)
        let state = store.begin(now: start)
        XCTAssertTrue(store.consumeIfMatches(state, now: start.addingTimeInterval(1)))
        XCTAssertFalse(store.consumeIfMatches(state, now: start.addingTimeInterval(2)))

        let expiredState = store.begin(now: start)
        XCTAssertFalse(store.consumeIfMatches(expiredState, now: start.addingTimeInterval(61)))
        XCTAssertNil(store.pendingState)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testTokenPairIsStoredAndClearedOnlyInKeychain() throws {
        let keychain = KeychainStore(service: "StudyPulse.AuthTests.\(UUID().uuidString)")
        let store = AuthTokenStore(keychain: keychain)
        let pair = AuthTokenPair(accessToken: "access", refreshToken: "refresh")
        do {
            try store.save(pair)
        } catch KeychainStore.StoreError.unexpectedStatus(-34018) {
            throw XCTSkip("The simulator test process has no Keychain access entitlement.")
        }
        XCTAssertEqual(store.pair, pair)
        XCTAssertNil(UserDefaults.standard.string(forKey: "access_token"))
        try store.clear()
        XCTAssertNil(store.pair)
    }
}

@MainActor
final class AuthRefreshTests: XCTestCase {
    func testRefreshSavesRotatedTokenPair() async throws {
        let keychain = KeychainStore(service: "StudyPulse.RefreshTests.\(UUID().uuidString)")
        let tokenStore = AuthTokenStore(keychain: keychain)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefreshStubURLProtocol.self]
        RefreshStubURLProtocol.responseData = Data(#"{"access_token":"new-access","refresh_token":"new-refresh"}"#.utf8)
        RefreshStubURLProtocol.statusCode = 200
        let client = AuthClient(session: URLSession(configuration: configuration))

        let pair: AuthTokenPair
        do {
            pair = try await client.refreshAccessToken(refreshToken: "old-refresh", tokenStore: tokenStore)
        } catch KeychainStore.StoreError.unexpectedStatus(-34018) {
            throw XCTSkip("The simulator test process has no Keychain access entitlement.")
        }
        XCTAssertEqual(pair, AuthTokenPair(accessToken: "new-access", refreshToken: "new-refresh"))
        XCTAssertEqual(tokenStore.pair, pair)
        XCTAssertEqual(RefreshStubURLProtocol.lastBody, #"{"refresh_token":"old-refresh"}"#)
    }
}

private final class RefreshStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var lastBody: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.statusCode, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
