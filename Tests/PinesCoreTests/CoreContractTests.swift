import PinesCore
import Testing

@Suite("Core contracts")
struct CoreContractTests {
    @Test
    func executionRouterDoesNotSilentlyFallbackToCloudInLocalOnlyMode() {
        let decision = ExecutionRouter().routeChat(
            mode: .localOnly,
            local: nil,
            cloud: (
                ProviderID(rawValue: "cloud"),
                ProviderCapabilities(local: false, textGeneration: true, toolCalling: true)
            ),
            requiresVision: false,
            requiresTools: true
        )

        #expect(decision.destination == .denied(reason: .unsupportedCapability("No local model satisfies this request.")))
    }

    @Test
    func executionRouterPrefersMatchingLocalProvider() {
        let localID = ProviderID(rawValue: "local")
        let decision = ExecutionRouter().routeChat(
            mode: .preferLocal,
            local: (
                localID,
                ProviderCapabilities(local: true, textGeneration: true, vision: true, toolCalling: true)
            ),
            cloud: (
                ProviderID(rawValue: "cloud"),
                ProviderCapabilities(local: false, textGeneration: true, vision: true, toolCalling: true)
            ),
            requiresVision: true,
            requiresTools: true
        )

        #expect(decision.destination == .local(localID))
    }

    @Test
    func redactorRemovesCommonCredentialShapes() {
        let text = "openai=sk-1234567890abcdef hf=hf_1234567890abcdef bearer=Bearer abcdefghijklmnop"
        let redacted = Redactor().redact(text)

        #expect(!redacted.contains("sk-1234567890abcdef"))
        #expect(!redacted.contains("hf_1234567890abcdef"))
        #expect(!redacted.contains("Bearer abcdefghijklmnop"))
        #expect(redacted.contains("[redacted-key]"))
        #expect(redacted.contains("Bearer [redacted-token]"))
    }

    @Test
    func calculatorHonorsOperatorPrecedenceAndRejectsDivisionByZero() throws {
        let evaluator = SafeCalculatorEvaluator()

        #expect(try evaluator.evaluate("2 + 3 * 4") == 14)
        #expect(try evaluator.evaluate("(2 + 3) * 4") == 20)
        #expect(throws: CalculatorEvaluationError.divisionByZero) {
            try evaluator.evaluate("1 / 0")
        }
    }
}
