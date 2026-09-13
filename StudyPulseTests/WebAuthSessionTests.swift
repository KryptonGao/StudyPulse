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

    func testPKCEChallengeIsS256Base64URL() {
        // RFC 7636 verifier alphabet; S256 = BASE64URL(SHA256(ascii(verifier))).
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = OAuthPKCE.challengeS256(for: verifier)
        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        XCTAssertFalse(challenge.contains("="))
        XCTAssertEqual(challenge.count, 43)
    }

    func testLoginURLUsesAuthorizationCodeAndPKCE() throws {
        let loginURL = WebAuthSession.makeLoginURL(
            state: "test-state",
            codeChallenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
        let components = try XCTUnwrap(URLComponents(url: loginURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "auth.chenkai.space")
        XCTAssertEqual(query(components, "return_to"), WebAuthSession.redirectURI)
        XCTAssertEqual(query(components, "response_type"), "code")
        XCTAssertEqual(query(components, "state"), "test-state")
        XCTAssertEqual(query(components, "code_challenge"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(query(components, "code_challenge_method"), "S256")
        XCTAssertNil(query(components, "access_token"))
    }

    func testCallbackAcceptsAuthorizationCodeAfterStateCheck() throws {
        let env = try makeStore()
        defer { env.defaults.removePersistentDomain(forName: env.suiteName) }
        let pending = env.store.begin()
        let url = try XCTUnwrap(URL(string: "studypulse://auth/callback?state=\(pending.state)&code=auth-code-1"))
        let result = try OAuthCallbackPipeline.consumeAuthorizationCode(from: url, store: env.store)
        XCTAssertEqual(result.code, "auth-code-1")
        XCTAssertEqual(result.verifier, pending.codeVerifier)
        XCTAssertEqual(env.store.inspect(), .none)
    }

    func testCallbackRejectsAccessTokensEvenWithValidState() throws {
        let env = try makeStore()
        defer { env.defaults.removePersistentDomain(forName: env.suiteName) }
        let pending = env.store.begin()
        let url = try XCTUnwrap(URL(string: "studypulse://auth/callback?state=\(pending.state)&access_token=stolen&refresh_token=stolen"))
        XCTAssertThrowsError(try OAuthCallbackPipeline.consumeAuthorizationCode(from: url, store: env.store)) { error in
            XCTAssertEqual(error as? WebAuthError, .implicitGrantRejected)
        }
        XCTAssertEqual(env.store.inspect(), .none)
    }

    func testCallbackReportsOAuthFailure() throws {
        let env = try makeStore()
        defer { env.defaults.removePersistentDomain(forName: env.suiteName) }
        let pending = env.store.begin()
        let url = try XCTUnwrap(URL(string: "studypulse://auth/callback?state=\(pending.state)&error=access_denied&error_description=GitHub%20denied"))
        XCTAssertThrowsError(try OAuthCallbackPipeline.consumeAuthorizationCode(from: url, store: env.store)) { error in
            XCTAssertEqual(error as? WebAuthError, .oauthFailed("GitHub denied"))
        }
    }

    func testCallbackRejectsMissingMismatchedReplayAndMissingSession() throws {
        let env = try makeStore()
        defer { env.defaults.removePersistentDomain(forName: env.suiteName) }

        let noSession = try XCTUnwrap(URL(string: "studypulse://auth/callback?state=any&code=code"))
        XCTAssertThrowsError(try OAuthCallbackPipeline.consumeAuthorizationCode(from: noSession, store: env.store)) { error in
            XCTAssertEqual(error as? WebAuthError, .noPendingSession)
        }

        let pending = env.store.begin()
        let missingState = try XCTUnwrap(URL(string: "studypulse://auth/callback?code=code"))
        XCTAssertThrowsError(try OAuthCallbackPipeline.consumeAuthorizationCode(from: missingState, store: env.store)) { error in
            XCTAssertEqual(error as? WebAuthError, .stateMissing)
        }
        guard case .ready = env.store.inspect() else {
            return XCTFail("Missing state must not consume the pending PKCE session.")
        }

        let mismatched = try XCTUnwrap(URL(string: "studypulse://auth/callback?state=other&code=code"))
        XCTAssertThrowsError(try OAuthCallbackPipeline.consumeAuthorizationCode(from: mismatched, store: env.store)) { error in
            XCTAssertEqual(error as? WebAuthError, .stateMismatch)
        }
        guard case .ready = env.store.inspect() else {
            return XCTFail("Mismatched state must not consume the pending PKCE session.")
        }

        let valid = try XCTUnwrap(URL(string: "studypulse://auth/callback?state=\(pending.state)&code=code"))
        _ = try OAuthCallbackPipeline.consumeAuthorizationCode(from: valid, store: env.store)
        XCTAssertThrowsError(try OAuthCallbackPipeline.consumeAuthorizationCode(from: valid, store: env.store)) { error in
            XCTAssertEqual(error as? WebAuthError, .stateReplayed)
        }
    }

    func testPendingSessionExpires() throws {
        let env = try makeStore(lifetime: 60)
        defer { env.defaults.removePersistentDomain(forName: env.suiteName) }
        let start = Date(timeIntervalSince1970: 10_000)
        let pending = env.store.begin(now: start)
        let url = try XCTUnwrap(URL(string: "studypulse://auth/callback?state=\(pending.state)&code=code"))
        XCTAssertThrowsError(
            try OAuthCallbackPipeline.consumeAuthorizationCode(
                from: url,
                store: env.store,
                now: start.addingTimeInterval(61)
            )
        ) { error in
            XCTAssertEqual(error as? WebAuthError, .stateExpired)
        }
        XCTAssertEqual(env.store.inspect(now: start.addingTimeInterval(62)), .none)
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

    private func query(_ components: URLComponents, _ name: String) -> String? {
        components.queryItems?.first(where: { $0.name == name })?.value
    }

    private func makeStore(lifetime: TimeInterval = 600) throws -> (suiteName: String, defaults: UserDefaults, store: OAuthPendingSessionStore) {
        let suiteName = "StudyPulse.OAuthPendingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = OAuthPendingSessionStore(defaults: defaults, keyPrefix: "test", lifetime: lifetime)
        return (suiteName, defaults, store)
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

    func testAuthorizationCodeExchangeUsesPKCEAndDoesNotPersistTokens() async throws {
        let keychain = KeychainStore(service: "StudyPulse.CodeExchangeTests.\(UUID().uuidString)")
        let tokenStore = AuthTokenStore(keychain: keychain)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefreshStubURLProtocol.self]
        RefreshStubURLProtocol.responseData = Data(#"{"access_token":"ex-access","refresh_token":"ex-refresh"}"#.utf8)
        RefreshStubURLProtocol.statusCode = 200
        let client = AuthClient(session: URLSession(configuration: configuration))

        let pair = try await client.exchangeAuthorizationCode(
            code: "auth-code",
            codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
            redirectURI: WebAuthSession.redirectURI
        )
        XCTAssertEqual(pair, AuthTokenPair(accessToken: "ex-access", refreshToken: "ex-refresh"))
        XCTAssertNil(tokenStore.pair)
        let body = try XCTUnwrap(RefreshStubURLProtocol.lastJSON)
        XCTAssertEqual(body["grant_type"] as? String, "authorization_code")
        XCTAssertEqual(body["code"] as? String, "auth-code")
        XCTAssertEqual(body["code_verifier"] as? String, "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(body["redirect_uri"] as? String, WebAuthSession.redirectURI)
        XCTAssertEqual(RefreshStubURLProtocol.lastURL?.path, "/auth/token")
    }

    func testAuthorizationCodeExchangeReportsMissingServerSupport() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefreshStubURLProtocol.self]
        RefreshStubURLProtocol.responseData = Data(#"{"error":"not found"}"#.utf8)
        RefreshStubURLProtocol.statusCode = 404
        let client = AuthClient(session: URLSession(configuration: configuration))
        do {
            _ = try await client.exchangeAuthorizationCode(
                code: "auth-code",
                codeVerifier: "verifier",
                redirectURI: WebAuthSession.redirectURI
            )
            XCTFail("404 must surface the authorization-code server gap.")
        } catch {
            XCTAssertEqual(
                (error as? AuthError)?.localizedDescription,
                AuthError.network("The identity server does not support authorization-code + PKCE token exchange.").localizedDescription
            )
        }
    }
}

private final class RefreshStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var lastBody: String?
    nonisolated(unsafe) static var lastURL: URL?

    static var lastJSON: [String: Any]? {
        guard let lastBody, let data = lastBody.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastURL = request.url
        Self.lastBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            ?? request.httpBodyStream.flatMap { stream in
                let data = Data(reading: stream)
                return String(data: data, encoding: .utf8)
            }
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

private extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                append(buffer, count: read)
            } else {
                break
            }
        }
    }
}
