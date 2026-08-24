//
//  CloudAuthLoginCoordinator.swift
//  StudyPulse
//
//  Validates the callback token against the HTTPS profile endpoint before
//  persisting anything in Keychain.
//

import Foundation

@MainActor
enum CloudAuthLoginCoordinator {
    static func login(
        pair: AuthTokenPair,
        container: RepositoryContainer,
        authClient: AuthClient = .shared,
        tokenStore: AuthTokenStore = .shared
    ) async throws {
        guard !pair.accessToken.isEmpty, !pair.refreshToken.isEmpty else {
            throw WebAuthError.invalidCallback
        }
        let workerURL = container.envManager.preferences.cloudAIWorkerURL ?? "spapi.chenkai.space"
        // Profile validation is deliberately performed before cloudSessionLogin,
        // which is the only operation that writes the pair to Keychain.
        let profile = try await authClient.getProfile(
            sessionToken: pair.accessToken,
            workerURL: workerURL
        )
        try container.envManager.cloudSessionLogin(
            accessToken: pair.accessToken,
            refreshToken: pair.refreshToken,
            email: profile.email,
            tokenStore: tokenStore
        )
        container.envManager.applyCloudProfile(profile)
    }
}
