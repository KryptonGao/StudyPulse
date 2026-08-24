//
//  AuthClient.swift
//  StudyPulse
//
//  Cloud AI 邮箱登录 HTTP 客户端。
//  Cloud AI email-login HTTP client.
//

import Foundation
import os

// MARK: - Auth Error

enum AuthError: Error, LocalizedError {
    case logoutFailed(String)
    case network(String)
    case missingWorkerURL

    var errorDescription: String? {
        switch self {
        case .logoutFailed(let msg):
            return String(format: "Logout failed: %@".localized(), msg)
        case .network(let msg):
            return String(format: "Network error: %@".localized(), msg)
        case .missingWorkerURL:
            return "Cloud AI Worker URL not configured.".localized()
        }
    }
}

// MARK: - Auth Response Types

struct AuthLogoutResponse: Decodable {
    let success: Bool
    let error: String?
}

struct AuthRefreshResponse: Decodable {
    let access_token: String?
    let refresh_token: String?
    let data: AuthRefreshData?
    let error: String?
    let message: String?
}

struct AuthRefreshData: Decodable {
    let access_token: String?
    let refresh_token: String?
}

// MARK: - Profile Response Types

struct ProfileResponse: Decodable {
    let success: Bool
    let error: String?
    let data: ProfileData?
}

struct ProfileData: Decodable {
    let email: String?
    let role: String?
    let membership: MembershipInfo?
    let plan: PlanInfo?
}

struct MembershipInfo: Decodable {
    let type: String?
    let expires_at: String?
    let effective_type: String?
}

struct PlanInfo: Decodable {
    let name: String?
    let daily_request_limit: Int?
    let monthly_token_limit: Int?
    let available_models: [String]?
}

// MARK: - Auth Client

@MainActor
final class AuthClient: @unchecked Sendable {
    static let shared = AuthClient()

    private let session: URLSession
    private let timeoutSeconds: TimeInterval = 30

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Public API

    /// Exchanges a refresh token at the identity center and returns the new pair.
    func refreshAccessToken(refreshToken: String, tokenStore: AuthTokenStore = .shared) async throws -> AuthTokenPair {
        guard let url = URL(string: "https://auth.chenkai.space/auth/refresh") else {
            throw AuthError.network("Invalid authentication server URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        request.timeoutInterval = timeoutSeconds

        let result = try await data(for: request)
        let decoded = try decode(AuthRefreshResponse.self, from: result.0)
        guard (200..<300).contains(result.1.statusCode),
              let access = decoded.access_token ?? decoded.data?.access_token, !access.isEmpty,
              let refresh = decoded.refresh_token ?? decoded.data?.refresh_token, !refresh.isEmpty else {
            throw AuthError.network(decoded.error ?? decoded.message ?? "Token refresh failed (HTTP \(result.1.statusCode))")
        }
        let pair = AuthTokenPair(accessToken: access, refreshToken: refresh)
        try tokenStore.save(pair)
        return pair
    }

    /// 退出登录。
    func logout(sessionToken: String, workerURL: String) async throws {
        let url = try buildURL(base: workerURL, path: "/auth/logout")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeoutSeconds

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("Non-HTTP response")
        }

        // 服务端即使 token 已失效也返回 200 success，客户端只清本地状态即可
        if http.statusCode == 200 {
            return
        }
        let decoded = (try? JSONDecoder().decode(AuthLogoutResponse.self, from: data))
        let msg = decoded?.error ?? "HTTP \(http.statusCode)"
        throw AuthError.logoutFailed(msg)
    }

    /// 获取当前用户信息和会员状态。
    func getProfile(sessionToken: String, workerURL: String) async throws -> ProfileData {
        let url = try buildURL(base: workerURL, path: "/user/profile")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeoutSeconds

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("Non-HTTP response")
        }

        let decoded = try JSONDecoder().decode(ProfileResponse.self, from: data)
        if http.statusCode == 200, decoded.success, let profileData = decoded.data {
            return profileData
        }
        let msg = decoded.error ?? "HTTP \(http.statusCode)"
        throw AuthError.network(msg)
    }

    private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("Non-HTTP response")
        }
        return (data, http)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AuthError.network("Invalid server response")
        }
    }

    // MARK: - Helpers

    private func buildURL(base: String, path: String) throws -> URL {
        guard let url = try? SecureEndpointURL.make(base: base, appending: path) else {
            throw AuthError.missingWorkerURL
        }
        return url
    }
}
