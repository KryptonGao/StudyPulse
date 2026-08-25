import XCTest
import UIKit
@testable import StudyPulse

@MainActor
final class SecureEndpointURLTests: XCTestCase {
    func testMissingSchemeDefaultsToHTTPS() throws {
        let url = try SecureEndpointURL.make(base: "api.example.com", appending: "/v1/chat")
        XCTAssertEqual(url.absoluteString, "https://api.example.com/v1/chat")
    }

    func testRejectsHTTPInvalidSchemeAndMissingHost() {
        XCTAssertThrowsError(try SecureEndpointURL.make(base: "http://api.example.com")) { error in
            XCTAssertEqual(error as? SecureEndpointURL.ValidationError, .insecureScheme)
        }
        XCTAssertThrowsError(try SecureEndpointURL.make(base: "ftp://api.example.com")) { error in
            XCTAssertEqual(error as? SecureEndpointURL.ValidationError, .invalid)
        }
        XCTAssertThrowsError(try SecureEndpointURL.make(base: "https://")) { error in
            XCTAssertEqual(error as? SecureEndpointURL.ValidationError, .missingHost)
        }
    }
}

@MainActor
final class HealthDataConsentTests: XCTestCase {
    func testHealthSharingDefaultsOffAndDecodesSafelyForOldPreferences() throws {
        XCTAssertFalse(AppPreferences().healthDataLLMSharingEnabled)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
        XCTAssertFalse(decoded.healthDataLLMSharingEnabled)
    }

    func testSensitivePromptCarriesHealthClassification() {
        let prompt = LLMPrompt(
            system: "system",
            messages: [.user("HRV=42")],
            sensitivity: .healthSensitive
        )
        XCTAssertEqual(prompt.sensitivity, .healthSensitive)
        XCTAssertNotNil(LLMError.healthDataConsentRequired.errorDescription)
    }

    func testHealthSensitiveRequestIsBlockedBeforeNetworkAndRevokeBlocksCachedResponse() async throws {
        ConsentNetworkStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConsentNetworkStub.self]
        let client = LLMClient(session: URLSession(configuration: configuration))
        let config = LLMConfig(
            enabled: true,
            baseURL: "https://example.com",
            apiKey: "api-key",
            model: "test-model",
            multimodalEnabled: false,
            thinkingEnabled: false,
            allowsHealthDataSharing: false,
            temperature: 0.7
        )
        let prompt = LLMPrompt(
            system: "health system",
            messages: [.user("HRV=42")],
            sensitivity: .healthSensitive
        )

        do {
            _ = try await client.complete(prompt: prompt, config: config, caller: "HealthConsentTests")
            XCTFail("Expected the privacy gate to reject the request")
        } catch let error as LLMError {
            XCTAssertEqual(error, .healthDataConsentRequired)
        }
        XCTAssertEqual(ConsentNetworkStub.requestCount, 0)

        var allowed = config
        allowed.allowsHealthDataSharing = true
        _ = try await client.complete(prompt: prompt, config: allowed, caller: "HealthConsentTests")
        XCTAssertEqual(ConsentNetworkStub.requestCount, 1)

        // Revocation is checked before cache lookup, so a previously cached
        // response cannot be reused after consent is withdrawn.
        var revoked = allowed
        revoked.allowsHealthDataSharing = false
        do {
            _ = try await client.complete(prompt: prompt, config: revoked, caller: "HealthConsentTests")
            XCTFail("Expected revoked consent to block even a cached response")
        } catch let error as LLMError {
            XCTAssertEqual(error, .healthDataConsentRequired)
        }
        XCTAssertEqual(ConsentNetworkStub.requestCount, 1)
        await LLMResponseCache.shared.clear()
    }
}

@MainActor
final class SecurityRedactionTests: XCTestCase {
    func testCallDebugInfoRedactsMultipleSecretsIncludingJSONExport() {
        let apiKey = "api-secret-123"
        let sessionToken = "session-secret-456"
        let info = LLMCallDebugInfo(
            startTime: .now,
            endTime: .now,
            url: "https://example.com?api=\(apiKey)",
            model: "model",
            temperature: 0.7,
            systemPrompt: "Bearer \(sessionToken)",
            messages: [.user("key=\(apiKey) token=\(sessionToken)")],
            streaming: false,
            response: "response \(sessionToken)",
            error: "error \(apiKey)",
            caller: "caller"
        )
        let redacted = info.redacting(secrets: [apiKey, sessionToken])
        let json = redacted.asDebugJSON()
        XCTAssertFalse(json.contains(apiKey))
        XCTAssertFalse(json.contains(sessionToken))
        XCTAssertTrue(json.contains("<redacted>"))
    }

    func testImageCacheUsesStableSHA256AndSeparateFilenameNamespace() {
        let data = Data("stable-image".utf8)
        XCTAssertEqual(ImageCache.dataCacheKey(data), ImageCache.dataCacheKey(data))
        XCTAssertNotEqual(ImageCache.dataCacheKey(data), ImageCache.dataCacheKey(Data("other-image".utf8)))
        XCTAssertNotEqual(ImageCache.dataCacheKey(data), ImageCache.filenameCacheKey("stable-image"))
        XCTAssertTrue(ImageCache.dataCacheKey(data).hasPrefix("d:"))
        XCTAssertTrue(ImageCache.filenameCacheKey("stable-image").hasPrefix("f:"))
    }
}

@MainActor
final class AuthEndpointValidationTests: XCTestCase {
    func testAuthProfileRejectsHTTPWorkerBeforeNetwork() async {
        let client = AuthClient(session: URLSession(configuration: .ephemeral))
        do {
            _ = try await client.getProfile(sessionToken: "session", workerURL: "http://worker.example.com")
            XCTFail("Expected HTTP worker URL to be rejected")
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

@MainActor
final class CloudAuthLoginCoordinatorTests: XCTestCase {
    func testProfileValidationFailureDoesNotPersistCallbackTokens() async throws {
        CloudProfileFailureStub.requestCount = 0
        let (container, _) = TestRepositoryContainerFactory.makeMockContainer()
        container.envManager.preferences.cloudAIWorkerURL = "https://worker.example.com"

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudProfileFailureStub.self]
        let client = AuthClient(session: URLSession(configuration: configuration))
        let tokenStore = AuthTokenStore(
            keychain: KeychainStore(service: "StudyPulse.ProfileValidationTests.\(UUID().uuidString)")
        )
        let pair = AuthTokenPair(accessToken: "callback-access", refreshToken: "callback-refresh")

        do {
            try await CloudAuthLoginCoordinator.login(
                pair: pair,
                container: container,
                authClient: client,
                tokenStore: tokenStore
            )
            XCTFail("Expected profile validation to fail")
        } catch let error as AuthError {
            guard case .network = error else {
                XCTFail("Unexpected auth error: \(error)")
                return
            }
        }

        XCTAssertNil(tokenStore.pair)
        XCTAssertNil(container.envManager.preferences.cloudSessionEmail)
        XCTAssertEqual(CloudProfileFailureStub.requestCount, 1)
    }
}

private final class ConsentNetworkStub: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0

    static func reset() { requestCount = 0 }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        let body = Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CloudProfileFailureStub: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        let body = Data(#"{"success":false,"error":"invalid session","data":null}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
