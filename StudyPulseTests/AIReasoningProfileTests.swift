import XCTest
@testable import StudyPulse

final class AIReasoningProfileTests: XCTestCase {
    private func profile(_ model: String, cloud: Bool = false, provider: String? = nil, baseURL: String? = nil) -> AIReasoningProfile {
        AIReasoningProfile.resolve(isCloud: cloud, providerName: provider, baseURL: baseURL, model: model)
    }

    // MARK: Detection

    func testCloudOffersOffAutoHigh() {
        let p = profile("anything", cloud: true)
        XCTAssertEqual(p.family, .cloud)
        XCTAssertEqual(p.levels, [.off, .auto, .high])
        XCTAssertEqual(p.key, "cloud")
    }

    func testOpenAIFamilies() {
        XCTAssertEqual(profile("gpt-5-mini").levels, [.minimal, .low, .medium, .high])
        XCTAssertEqual(profile("openai/gpt-5.1").levels, [.off, .low, .medium, .high])
        XCTAssertEqual(profile("o4-mini").levels, [.low, .medium, .high])
        XCTAssertEqual(profile("gpt-5-chat-latest").family, .generic)
    }

    func testOtherFamilies() {
        XCTAssertEqual(profile("abab", baseURL: "https://api.minimaxi.com").family, .miniMax)
        XCTAssertEqual(profile("deepseek-reasoner").levels, [.high])
        XCTAssertFalse(profile("deepseek-reasoner").isAdjustable)
        XCTAssertEqual(profile("qwen3-max").family, .qwen)
        XCTAssertEqual(profile("gemini-2.5-flash").family, .reasoningEffort)
        XCTAssertEqual(profile("deepseek-chat").levels, [.off, .high])
    }

    func testGPT52AddsExtraHigh() {
        XCTAssertEqual(profile("gpt-5.2").levels, [.off, .low, .medium, .high, .xhigh])
        XCTAssertEqual(profile("gpt-5.1-codex-max").levels.last, .xhigh)
    }

    // MARK: Custom levels

    func testCustomLevelsOverrideDetectionAndUseReasoningEffort() {
        let p = AIReasoningProfile.resolve(
            isCloud: false, providerName: nil, baseURL: nil, model: "claude-opus-4-6",
            customLevels: [.max, .off, .high]
        )
        XCTAssertTrue(p.isCustom)
        XCTAssertEqual(p.family, .reasoningEffort)
        XCTAssertEqual(p.levels, [.off, .high, .max])
        XCTAssertEqual(p.defaultLevel, .high)
    }

    func testCustomLevelsAreIgnoredForCloud() {
        let p = AIReasoningProfile.resolve(isCloud: true, providerName: nil, baseURL: nil, model: nil, customLevels: [.max])
        XCTAssertFalse(p.isCustom)
        XCTAssertEqual(p.levels, [.off, .auto, .high])
    }

    func testParseDropsUnknownLevelsAndOrders() {
        XCTAssertEqual(AIReasoningLevel.parse(["max", "bogus", "low"]), [.low, .max])
        XCTAssertNil(AIReasoningLevel.parse(["bogus"]))
        XCTAssertNil(AIReasoningLevel.parse(nil))
    }

    func testKeysDifferPerModel() {
        XCTAssertNotEqual(profile("gpt-5").key, profile("gpt-5-mini").key)
    }

    // MARK: Resolution

    func testResolvePrefersStoredThenLegacyThenDefault() {
        let p = profile("gpt-5")
        XCTAssertEqual(p.resolve(stored: "low", legacy: .quick), .low)
        XCTAssertEqual(p.resolve(stored: "auto", legacy: .quick), .minimal)
        XCTAssertEqual(p.resolve(stored: nil, legacy: .deep), .medium)
    }

    func testPositionSpansTheModelsRange() {
        let p = profile("x", cloud: true)
        XCTAssertEqual(p.position(of: .off), 0)
        XCTAssertEqual(p.position(of: .auto), 0.5)
        XCTAssertEqual(p.position(of: .high), 1)
    }

    // MARK: Request tuning

    @MainActor
    func testTunedMapsLevelsToRequestParameters() {
        var config = LLMConfig.empty
        config.model = "gpt-5"
        let tuned = AIModeLLM.tuned(config, level: .high)
        XCTAssertEqual(tuned.reasoningEffort, "high")
        XCTAssertFalse(tuned.sendsTemperature)

        config.model = "qwen3-max"
        let qwenOff = AIModeLLM.tuned(config, level: .off)
        XCTAssertEqual(qwenOff.enableThinking, false)
        XCTAssertNil(qwenOff.thinkingBudgetTokens)

        config.model = "claude-opus-4-6"
        config.customReasoningLevels = [.off, .high, .max]
        XCTAssertEqual(AIModeLLM.tuned(config, level: .max).reasoningEffort, "max")
        XCTAssertNil(AIModeLLM.tuned(config, level: .off).reasoningEffort)
        XCTAssertTrue(AIModeLLM.tuned(config, level: .max).sendsTemperature)
        config.customReasoningLevels = nil

        config.isCloudProvider = true
        XCTAssertEqual(AIModeLLM.tuned(config, level: .off).thinkingMode, .off)
        XCTAssertEqual(AIModeLLM.tuned(config, level: .high).thinkingMode, .on)
    }
}
