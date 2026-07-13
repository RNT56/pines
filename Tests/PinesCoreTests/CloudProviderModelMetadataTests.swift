import Foundation
import Testing
@testable import PinesCore

@Suite("Cloud provider model metadata")
struct CloudProviderModelMetadataTests {
    @Test
    func metadataAndPricingRoundTrip() throws {
        let model = CloudProviderModel(
            id: "example/vision-chat",
            displayName: "Vision Chat",
            capabilities: ProviderCapabilities(
                local: false,
                imageInputs: true,
                toolCalling: true,
                structuredOutputs: true,
                maxContextTokens: 131_072,
                maxOutputTokens: 16_384
            ),
            supportedParameters: ["tools", "structured_outputs"],
            metadata: CloudProviderModelMetadata(
                canonicalSlug: "example/vision-chat-2026-07-01",
                summary: "A bounded model summary.",
                inputModalities: ["text", "image"],
                outputModalities: ["text"],
                tokenizer: "Example",
                instructType: "chatml",
                contextLength: 131_072,
                maxCompletionTokens: 16_384,
                isModerated: true,
                pricing: CloudProviderModelPricing(
                    prompt: Decimal(string: "0.00000015"),
                    completion: Decimal(string: "0.0000006")
                )
            )
        )

        let decoded = try JSONDecoder().decode(
            CloudProviderModel.self,
            from: JSONEncoder().encode(model)
        )

        #expect(decoded == model)
        #expect(decoded.metadata?.pricing?.tokenPricePerMillion(decoded.metadata?.pricing?.prompt) == Decimal(string: "0.15"))
        #expect(decoded.metadata?.pricing?.tokenPricePerMillion(decoded.metadata?.pricing?.completion) == Decimal(string: "0.6"))
    }

    @Test
    func eligibilityRejectsOnlyDefinitiveCapabilityMismatches() {
        let model = CloudProviderModel(
            id: "example/text-only",
            displayName: "Text Only",
            capabilities: ProviderCapabilities(
                local: false,
                textGeneration: true,
                toolCalling: false,
                jsonMode: true,
                structuredOutputs: false
            )
        )

        let report = model.eligibility(
            requiredInputs: ProviderInputRequirements(requiresImages: true),
            requiresTools: true,
            structuredOutput: .jsonSchema(name: "answer", schema: .object([:]), strict: true)
        )

        #expect(!report.isEligible)
        #expect(report.reasons == [
            "This model does not advertise image input.",
            "This model does not advertise tool calling.",
            "This model does not advertise strict structured outputs.",
        ])

        let unknown = CloudProviderModel(id: "example/unknown", displayName: "Unknown")
        #expect(unknown.eligibility(requiredInputs: .init(requiresVideo: true), requiresTools: true).isEligible)
    }

    @Test
    func legacyCatalogEntryDecodesWithoutMetadata() throws {
        let data = Data(#"{"id":"example/model","displayName":"Example"}"#.utf8)

        let model = try JSONDecoder().decode(CloudProviderModel.self, from: data)

        #expect(model.metadata == nil)
        #expect(model.capabilities == nil)
        #expect(model.supportedParameters.isEmpty)
        #expect(model.supportedGenerationMethods.isEmpty)
    }
}
