import AuthenticationServices
import Foundation
import UIKit
import os

enum WebAuthError: Error, LocalizedError, Equatable {
    case cancelled
    case oauthFailed(String)
    case callbackMissing
    case accessTokenMissing
    case refreshTokenMissing
    case stateMissing
    case stateMismatch
    case stateExpired
    case invalidCallback

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Login was cancelled."
        case .oauthFailed(let message): return message
        case .callbackMissing: return "The login callback was not received."
        case .accessTokenMissing: return "The login response did not contain an access token."
        case .refreshTokenMissing: return "The login response did not contain a refresh token."
        case .stateMissing: return "The login callback did not contain a security state."
        case .stateMismatch: return "The login callback could not be verified. Please try again."
        case .stateExpired: return "The login callback expired. Please try again."
        case .invalidCallback: return "The login callback is invalid."
        }
    }
}

/// One-time, short-lived state for the custom URL-scheme callback.
/// The value is kept in UserDefaults so a cold-launch callback can still be
/// matched, but it is never used as an authentication credential.
@MainActor
final class AuthCallbackStateStore {
    static let shared = AuthCallbackStateStore()

    private let defaults: UserDefaults
    private let stateKey: String
    private let createdAtKey: String
    let lifetime: TimeInterval

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "StudyPulse.AuthCallbackState",
        lifetime: TimeInterval = 10 * 60
    ) {
        self.defaults = defaults
        self.stateKey = "\(keyPrefix).value"
        self.createdAtKey = "\(keyPrefix).createdAt"
        self.lifetime = lifetime
    }

    var pendingState: String? {
        guard let state = defaults.string(forKey: stateKey),
              let createdAt = defaults.object(forKey: createdAtKey) as? Date else {
            return nil
        }
        guard Date().timeIntervalSince(createdAt) >= 0,
              Date().timeIntervalSince(createdAt) <= lifetime else {
            clear()
            return nil
        }
        return state
    }

    @discardableResult
    func begin(now: Date = Date()) -> String {
        clear()
        // UUID uses the system random source and is suitable for a short-lived
        // OAuth state value. Two UUIDs provide ample entropy after URL encoding.
        let state = "\(UUID().uuidString).\(UUID().uuidString)"
        defaults.set(state, forKey: stateKey)
        defaults.set(now, forKey: createdAtKey)
        return state
    }

    @discardableResult
    func consumeIfMatches(_ callbackState: String?, now: Date = Date()) -> Bool {
        guard let expected = defaults.string(forKey: stateKey),
              let createdAt = defaults.object(forKey: createdAtKey) as? Date else {
            return false
        }
        let age = now.timeIntervalSince(createdAt)
        guard age >= 0, age <= lifetime else {
            clear()
            return false
        }
        guard callbackState == expected else { return false }
        clear()
        return true
    }

    func clear() {
        defaults.removeObject(forKey: stateKey)
        defaults.removeObject(forKey: createdAtKey)
    }
}

enum WebAuthCallbackParser {
    static func parse(_ url: URL, expectedState: String) throws -> AuthTokenPair {
        guard url.scheme == "studypulse", url.host == "auth", url.path == "/callback" else {
            throw WebAuthError.invalidCallback
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw WebAuthError.invalidCallback
        }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value { values[item.name] = value }
        }
        guard let callbackState = values["state"], !callbackState.isEmpty else {
            throw WebAuthError.stateMissing
        }
        guard callbackState == expectedState else {
            throw WebAuthError.stateMismatch
        }
        if let error = values["error"] {
            throw WebAuthError.oauthFailed(values["error_description"] ?? error)
        }
        guard values["access_token"] != nil else { throw WebAuthError.accessTokenMissing }
        guard values["refresh_token"] != nil else { throw WebAuthError.refreshTokenMissing }
        guard let accessToken = values["access_token"], !accessToken.isEmpty else {
            throw WebAuthError.accessTokenMissing
        }
        guard let refreshToken = values["refresh_token"], !refreshToken.isEmpty else {
            throw WebAuthError.refreshTokenMissing
        }
        return AuthTokenPair(accessToken: accessToken, refreshToken: refreshToken)
    }

    /// Kept as a hard-failing overload so old call sites cannot accidentally
    /// bypass state validation during a future refactor.
    static func parse(_ url: URL) throws -> AuthTokenPair {
        throw WebAuthError.stateMissing
    }
}

extension Notification.Name {
    static let studyPulseAuthCallbackHandled = Notification.Name("StudyPulse.authCallbackHandled")
}

/// Handles URL-scheme callbacks delivered directly to the application.
///
/// `ASWebAuthenticationSession` normally receives the callback itself, but
/// iOS can also deliver the custom-scheme URL through the scene lifecycle
/// (notably when the app is backgrounded or cold-launched). Keeping this path
/// at the app level makes both cases use the same token persistence logic.
@MainActor
enum AuthCallbackHandler {
    static func handle(_ url: URL, container: RepositoryContainer) async {
        // When ASWebAuthenticationSession is active it owns the callback. The
        // scene URL is only a duplicate delivery on some lifecycle paths.
        guard !WebAuthSession.isActive else { return }
        do {
            guard let expectedState = AuthCallbackStateStore.shared.pendingState else {
                throw WebAuthError.stateExpired
            }
            let pair = try WebAuthCallbackParser.parse(url, expectedState: expectedState)
            guard AuthCallbackStateStore.shared.consumeIfMatches(url.queryValue(named: "state")) else {
                throw WebAuthError.stateExpired
            }
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
}

@MainActor
final class WebAuthSession: NSObject {
    static private(set) var isActive = false
    static let callbackURL = URL(string: "studypulse://auth/callback")!
    /// Legacy constant retained for UI/tests; production always uses a fresh state.
    static let loginURL = URL(string: "https://auth.chenkai.space/login?return_to=studypulse%3A%2F%2Fauth%2Fcallback")!

    static func makeLoginURL(state: String) -> URL {
        var callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)!
        callback.queryItems = [URLQueryItem(name: "state", value: state)]
        var login = URLComponents(string: "https://auth.chenkai.space/login")!
        login.queryItems = [URLQueryItem(name: "return_to", value: callback.url!.absoluteString)]
        return login.url!
    }

    private var session: ASWebAuthenticationSession?
    private let anchorProvider: @MainActor () -> ASPresentationAnchor?

    init(anchorProvider: @escaping @MainActor () -> ASPresentationAnchor? = {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .compactMap { scene in
                scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
            }
            .first
    }) {
        self.anchorProvider = anchorProvider
        super.init()
    }

    func authenticate() async throws -> AuthTokenPair {
        // Fail before creating or starting OAuth when there is no foreground window.
        guard let anchor = anchorProvider() else {
            throw WebAuthError.networkStartFailed
        }
        let presentationContext = WebAuthPresentationContext(anchor: anchor)
        // ASWebAuthenticationSession holds its presentation provider weakly.
        defer { withExtendedLifetime(presentationContext) {} }

        let state = AuthCallbackStateStore.shared.begin()
        Self.isActive = true
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthTokenPair, Error>) in
            let authSession = ASWebAuthenticationSession(
                url: Self.makeLoginURL(state: state),
                callbackURLScheme: "studypulse"
            ) { [weak self] callbackURL, error in
                defer {
                    self?.session = nil
                    Self.isActive = false
                    AuthCallbackStateStore.shared.clear()
                }
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
                do {
                    let pair = try WebAuthCallbackParser.parse(callbackURL, expectedState: state)
                    guard AuthCallbackStateStore.shared.consumeIfMatches(callbackURL.queryValue(named: "state")) else {
                        throw WebAuthError.stateExpired
                    }
                    continuation.resume(returning: pair)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            authSession.presentationContextProvider = presentationContext
            authSession.prefersEphemeralWebBrowserSession = true
            self.session = authSession
            guard authSession.start() else {
                self.session = nil
                Self.isActive = false
                AuthCallbackStateStore.shared.clear()
                continuation.resume(throwing: WebAuthError.networkStartFailed)
                return
            }
        }
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

private extension URL {
    func queryValue(named name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == name })?.value
    }
}

private extension WebAuthError {
    static let networkStartFailed = WebAuthError.oauthFailed("Unable to start the secure login session.")
}
