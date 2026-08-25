import XCTest
@testable import StudyPulse

final class KeychainStoreTests: XCTestCase {
    private var store: KeychainStore!
    private var account: String!

    override func setUpWithError() throws {
        store = KeychainStore(service: "Gao.Chenkai.StudyPulseTests.\(UUID().uuidString)")
        account = "test-account"
        do {
            try store.write("entitlement-probe", account: "entitlement-probe")
            try store.delete(account: "entitlement-probe")
        } catch KeychainStore.StoreError.unexpectedStatus(-34018) {
            throw XCTSkip("The simulator test process has no Keychain access entitlement.")
        }
    }

    override func tearDownWithError() throws {
        try? store.delete(account: account)
        store = nil
        account = nil
    }

    func testWriteAndReadKey() throws {
        try store.write("secret-one", account: account)

        XCTAssertEqual(try store.read(account: account), "secret-one")
    }

    func testUpdateReplacesExistingKey() throws {
        try store.write("secret-one", account: account)
        try store.write("secret-two", account: account)

        XCTAssertEqual(try store.read(account: account), "secret-two")
    }

    func testDeleteRemovesKey() throws {
        try store.write("secret-one", account: account)
        try store.delete(account: account)

        XCTAssertNil(try store.read(account: account))
    }

    func testLegacyProviderMigrationPreservesAccessAndRemovesPlaintext() throws {
        let providerID = UUID()
        let plaintext = "migration-secret-\(UUID().uuidString)"
        let json = """
        {
          "llmEnabled": true,
          "llmProviders": [{
            "id": "\(providerID.uuidString)",
            "name": "Legacy",
            "baseURL": "https://example.com",
            "apiKey": "\(plaintext)",
            "model": "test-model"
          }],
          "activeLLMProviderId": "\(providerID.uuidString)"
        }
        """
        var preferences = try JSONDecoder().decode(
            AppPreferences.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertTrue(LLMAPIKeyMigrator.migrate(preferences: &preferences, keychain: store))
        XCTAssertEqual(
            try store.read(account: LLMAPIKeyAccount.provider(providerID)),
            plaintext
        )

        let persistedData = try JSONEncoder().encode(preferences)
        let persistedJSON = try XCTUnwrap(String(data: persistedData, encoding: .utf8))
        XCTAssertFalse(persistedJSON.contains(plaintext))
        XCTAssertFalse(persistedJSON.contains("\"apiKey\""))
        XCTAssertFalse(persistedJSON.contains("\"llmAPIKey\""))
        XCTAssertNil(preferences.llmProviders.first?.legacyAPIKey)
    }

    func testMigrationPrefersExistingKeychainValue() throws {
        let providerID = UUID()
        let account = LLMAPIKeyAccount.provider(providerID)
        try store.write("keychain-value", account: account)
        var preferences = AppPreferences()
        preferences.llmProviders = [
            LLMProvider(
                id: providerID,
                name: "Provider",
                baseURL: "https://example.com",
                legacyAPIKey: "stale-defaults-value",
                model: "test-model"
            )
        ]
        preferences.activeLLMProviderId = providerID

        XCTAssertTrue(LLMAPIKeyMigrator.migrate(preferences: &preferences, keychain: store))
        XCTAssertEqual(try store.read(account: account), "keychain-value")
        XCTAssertNil(preferences.llmProviders.first?.legacyAPIKey)
    }

    func testLegacySingleProviderMigrationRequiresNoReentry() throws {
        let plaintext = "single-provider-secret-\(UUID().uuidString)"
        let json = """
        {
          "llmEnabled": true,
          "llmBaseURL": "https://example.com",
          "llmAPIKey": "\(plaintext)",
          "llmModel": "test-model"
        }
        """
        var preferences = try JSONDecoder().decode(
            AppPreferences.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        let provider = try XCTUnwrap(preferences.llmProviders.first)

        XCTAssertTrue(LLMAPIKeyMigrator.migrate(preferences: &preferences, keychain: store))
        XCTAssertEqual(
            try store.read(account: LLMAPIKeyAccount.provider(provider.id)),
            plaintext
        )
        XCTAssertNil(preferences.llmAPIKey)
        XCTAssertFalse(try JSONEncoder().encode(preferences).contains(Data(plaintext.utf8)))
    }

    func testDebugExportRedactsCompleteAPIKey() {
        let secret = "debug-secret-\(UUID().uuidString)"
        let info = LLMCallDebugInfo(
            startTime: Date(),
            endTime: Date(),
            url: "https://example.com/\(secret)",
            model: "model",
            temperature: 0.7,
            systemPrompt: "Never print \(secret)",
            messages: [.user("accidental \(secret)")],
            streaming: false,
            response: "echo \(secret)",
            error: "error \(secret)",
            caller: "test"
        )

        let debugJSON = info.redacting(secret: secret).asDebugJSON()
        XCTAssertFalse(debugJSON.contains(secret))
        XCTAssertTrue(debugJSON.contains("<redacted>"))
    }
}
