import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit
import os

enum WebAuthError: Error, LocalizedError, Equatable {
    case cancelled
    case oauthFailed(String)
    case callbackMissing
    case authorizationCodeMissing
    case noPendingSession
    case stateMissing
    case stateMismatch
    case stateExpired
    case stateReplayed
    case implicitGrantRejected
    case invalidCallback

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Login was cancelled."
        case .oauthFailed(let message): return message
        case .callbackMissing: return "The login callback was not received."
        case .authorizationCodeMissing: return "The login callback did not contain an authorization code."
        case .noPendingSession: return "No login session is waiting for a callback."
        case .stateMissing: return "The login callback did not contain a security state."
        case .stateMismatch: return "The login callback could not be verified. Please try again."
        case .stateExpired: return "The login callback expired. Please try again."
        case .stateReplayed: return "The login callback was already used."
        case .implicitGrantRejected: return "The login callback contained tokens instead of an authorization code."
        case .invalidCallback: return "The login callback is invalid."
        }
    }
}

struct OAuthPendingSession: Equatable, Sendable {
    let state: String
    let codeVerifier: String
    let createdAt: Date
}

struct OAuthCallbackPayload: Equatable, Sendable {
    let state: String?
    let code: String?
    let error: String?
    let errorDescription: String?
    let containsTokens: Bool
}

enum OAuthPendingLookup: Equatable {
    case none
    case expired
    case ready(OAuthPendingSession)
}

enum OAuthPKCE {
    static func randomBase64URL(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<byteCount).map { _ in UInt8.random(in: 0...255, using: &generator) }
        }
        return Data(bytes).base64URLEncodedString()
    }

    static func challengeS256(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    static func timingSafeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }
}

/// One-time PKCE session for the custom URL-scheme callback.
/// Values are kept in UserDefaults so a cold-launch callback can still complete
/// the code exchange; they are never treated as authentication credentials.
@MainActor
final class OAuthPendingSessionStore {
    static let shared = OAuthPendingSessionStore()

    private let defaults: UserDefaults
    private let stateKey: String
    private let verifierKey: String
    private let createdAtKey: String
    private let lastStateKey: String
    private let lastConsumedAtKey: String
    let lifetime: TimeInterval

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "StudyPulse.OAuthPendingSession",
        lifetime: TimeInterval = 10 * 60
    ) {
        self.defaults = defaults
        self.stateKey = "\(keyPrefix).state"
        self.verifierKey = "\(keyPrefix).codeVerifier"
        self.createdAtKey = "\(keyPrefix).createdAt"
        self.lastStateKey = "\(keyPrefix).lastState"
        self.lastConsumedAtKey = "\(keyPrefix).lastConsumedAt"
        self.lifetime = lifetime
    }

    @discardableResult
    func begin(now: Date = Date()) -> OAuthPendingSession {
        clearPending()
        let session = OAuthPendingSession(
            state: OAuthPKCE.randomBase64URL(),
            codeVerifier: OAuthPKCE.randomBase64URL(),
            createdAt: now
        )
        defaults.set(session.state, forKey: stateKey)
        defaults.set(session.codeVerifier, forKey: verifierKey)
        defaults.set(session.createdAt, forKey: createdAtKey)
        return session
    }

    func inspect(now: Date = Date()) -> OAuthPendingLookup {
        guard let session = loadedSession() else { return .none }
        let age = now.timeIntervalSince(session.createdAt)
        guard age >= 0, age <= lifetime else {
            clearPending()
            return .expired
        }
        return .ready(session)
    }

    func isReplay(_ callbackState: String?, now: Date = Date()) -> Bool {
        guard let callbackState, !callbackState.isEmpty,
              let lastState = defaults.string(forKey: lastStateKey),
              let consumedAt = defaults.object(forKey: lastConsumedAtKey) as? Date else {
            return false
        }
        let age = now.timeIntervalSince(consumedAt)
        guard age >= 0, age <= lifetime else { return false }
        return OAuthPKCE.timingSafeEqual(callbackState, lastState)
    }

    func consumeMatchingState(_ callbackState: String, now: Date = Date()) -> OAuthPendingSession? {
        guard case .ready(let session) = inspect(now: now) else { return nil }
        guard OAuthPKCE.timingSafeEqual(callbackState, session.state) else { return nil }
        defaults.set(session.state, forKey: lastStateKey)
        defaults.set(now, forKey: lastConsumedAtKey)
        clearPending()
        return session
    }

    func clear() {
        clearPending()
        defaults.removeObject(forKey: lastStateKey)
        defaults.removeObject(forKey: lastConsumedAtKey)
    }

    private func loadedSession() -> OAuthPendingSession? {
        guard let state = defaults.string(forKey: stateKey), !state.isEmpty,
              let verifier = defaults.string(forKey: verifierKey), !verifier.isEmpty,
              let createdAt = defaults.object(forKey: createdAtKey) as? Date else {
            return nil
        }
        return OAuthPendingSession(state: state, codeVerifier: verifier, createdAt: createdAt)
    }

    private func clearPending() {
        defaults.removeObject(forKey: stateKey)
        defaults.removeObject(forKey: verifierKey)
        defaults.removeObject(forKey: createdAtKey)
    }
}

enum WebAuthCallbackParser {
    static func payload(from url: URL) throws -> OAuthCallbackPayload {
        guard url.scheme == "studypulse", url.host == "auth", url.path == "/callback" else {
            throw WebAuthError.invalidCallback
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw WebAuthError.invalidCallback
        }
        var values: [String: String] = [:]
        ingest(components.queryItems, into: &values)
        if let fragment = components.fragment, !fragment.isEmpty {
            ingest(URLComponents(string: "dummy://host?\(fragment)")?.queryItems, into: &values)
        }
        return OAuthCallbackPayload(
            state: values["state"],
            code: values["code"],
            error: values["error"],
            errorDescription: values["error_description"],
            containsTokens: values["access_token"] != nil || values["refresh_token"] != nil
        )
    }

    private static func ingest(_ items: [URLQueryItem]?, into values: inout [String: String]) {
        for item in items ?? [] {
            guard values[item.name] == nil, let value = item.value, !value.isEmpty else { continue }
            values[item.name] = value
        }
    }
}

enum OAuthCallbackPipeline {
    static func consumeAuthorizationCode(
        from url: URL,
        store: OAuthPendingSessionStore,
        now: Date = Date()
    ) throws -> (code: String, verifier: String) {
        let payload = try WebAuthCallbackParser.payload(from: url)
        switch store.inspect(now: now) {
        case .none:
            throw store.isReplay(payload.state, now: now) ? WebAuthError.stateReplayed : WebAuthError.noPendingSession
        case .expired:
            throw WebAuthError.stateExpired
        case .ready:
            break
        }
        guard let state = payload.state, !state.isEmpty else {
            throw WebAuthError.stateMissing
        }
        guard let session = store.consumeMatchingState(state, now: now) else {
            throw WebAuthError.stateMismatch
        }
        if let error = payload.error {
            throw WebAuthError.oauthFailed(payload.errorDescription ?? error)
        }
        if payload.containsTokens {
            throw WebAuthError.implicitGrantRejected
        }
        guard let code = payload.code, !code.isEmpty else {
            throw WebAuthError.authorizationCodeMissing
        }
        return (code, session.codeVerifier)
    }
}

extension Notification.Name {
    static let studyPulseAuthCallbackHandled = Notification.Name("StudyPulse.authCallbackHandled")
}

/// Handles URL-scheme callbacks delivered directly to the application.
///
/// `ASWebAuthenticationSession` normally receives the callback itself, but
/// iOS can also deliver the custom-scheme URL through the scene lifecycle
/// (notably when the app is backgrounded or cold-launched). Both paths require
/// a pending PKCE session and an authorization `code`; tokens in the URL are
/// rejected.
@MainActor
enum AuthCallbackHandler {
    static func handle(
        _ url: URL,
        container: RepositoryContainer,
        pendingStore: OAuthPendingSessionStore = .shared,
        authClient: AuthClient = .shared
    ) async {
        // When ASWebAuthenticationSession is active it owns the callback. The
        // scene URL is only a duplicate delivery on some lifecycle paths.
        guard !WebAuthSession.isActive else { return }
        do {
            let pair = try await completeLogin(from: url, pendingStore: pendingStore, authClient: authClient)
            try await CloudAuthLoginCoordinator.login(pair: pair, container: container)
            NotificationCenter.default.post(
                name: .studyPulseAuthCallbackHandled,
                object: pair
            )
            Log.preferences.info("Auth callback handled and tokens saved")
        } catch {
            Log.preferences.error("Auth callback failed: \(error.localizedDescription)")
            NotificationCenter.default.post(
                name: .studyPulseAuthCallbackHandled,
                object: error
            )
        }
    }

    static func completeLogin(
        from url: URL,
        pendingStore: OAuthPendingSessionStore,
        authClient: AuthClient,
        now: Date = Date()
    ) async throws -> AuthTokenPair {
        let exchanged = try OAuthCallbackPipeline.consumeAuthorizationCode(from: url, store: pendingStore, now: now)
        return try await authClient.exchangeAuthorizationCode(
            code: exchanged.code,
            codeVerifier: exchanged.verifier,
            redirectURI: WebAuthSession.redirectURI
        )
    }
}

@MainActor
final class WebAuthSession: NSObject {
    static private(set) var isActive = false
    static let identityHost = "auth.chenkai.space"
    static let redirectURI = "studypulse://auth/callback"
    static let callbackURL = URL(string: redirectURI)!
    static let tokenURL = URL(string: "https://auth.chenkai.space/auth/token")!
    /// Host/path smoke-check URL; production always uses a fresh PKCE session.
    static let loginURL = URL(string: "https://auth.chenkai.space/login?return_to=studypulse%3A%2F%2Fauth%2Fcallback")!

    static func makeLoginURL(state: String, codeChallenge: String) -> URL {
        var login = URLComponents(string: "https://auth.chenkai.space/login")!
        login.queryItems = [
            URLQueryItem(name: "return_to", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return login.url!
    }

    private var session: ASWebAuthenticationSession?
    private let pendingStore: OAuthPendingSessionStore
    private let authClient: AuthClient
    private let anchorProvider: @MainActor () -> ASPresentationAnchor?

    init(
        pendingStore: OAuthPendingSessionStore = .shared,
        authClient: AuthClient = .shared,
        anchorProvider: @escaping @MainActor () -> ASPresentationAnchor? = {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
                .compactMap { scene in
                    scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
                }
                .first
        }
    ) {
        self.pendingStore = pendingStore
        self.authClient = authClient
        self.anchorProvider = anchorProvider
        super.init()
    }

    func authenticate() async throws -> AuthTokenPair {
        // Fail before creating or starting OAuth when there is no foreground window.
        guard let anchor = anchorProvider() else {
            throw WebAuthError.networkStartFailed
        }
        let presentationContext = WebAuthPresentationContext(anchor: anchor)
        let pending = pendingStore.begin()
        Self.isActive = true
        defer {
            session = nil
            Self.isActive = false
            pendingStore.clear()
            withExtendedLifetime(presentationContext) {}
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let challenge = OAuthPKCE.challengeS256(for: pending.codeVerifier)
            let authSession = ASWebAuthenticationSession(
                url: Self.makeLoginURL(state: pending.state, codeChallenge: challenge),
                callbackURLScheme: "studypulse"
            ) { callbackURL, error in
                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin {
                    continuation.resume(throwing: WebAuthError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: WebAuthError.oauthFailed(error.localizedDescription))
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: WebAuthError.callbackMissing)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            authSession.presentationContextProvider = presentationContext
            authSession.prefersEphemeralWebBrowserSession = true
            self.session = authSession
            guard authSession.start() else {
                continuation.resume(throwing: WebAuthError.networkStartFailed)
                return
            }
        }

        return try await AuthCallbackHandler.completeLogin(
            from: callbackURL,
            pendingStore: pendingStore,
            authClient: authClient
        )
    }
}

@MainActor
final class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
        super.init()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension WebAuthError {
    static let networkStartFailed = WebAuthError.oauthFailed("Unable to start the secure login session.")
}
