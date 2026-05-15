import Foundation
import PinesCore

@main
struct PinesCoreTestRunner {
    static func main() async throws {
        try testExecutionRouter()
        try testModelPreflight()
        try testPersistenceSchema()
        try testProductionTypes()
        try testArchitectureModules()
        try testRedactor()
        try testCalculator()
        try await testToolRegistry()
        try await testInferenceStreamAdapter()
        try await testAgentPolicyGate()
        try testVaultChunking()
        try testVectorIndex()
        print("PinesCoreTestRunner: all checks passed")
    }

    private static func testExecutionRouter() throws {
        let router = ExecutionRouter()
        let localOnly = router.routeChat(
            mode: .localOnly,
            local: nil,
            cloud: ("openai", ProviderCapabilities(local: false, toolCalling: true)),
            requiresVision: false,
            requiresTools: true
        )
        try expectEqual(
            localOnly.destination,
            .denied(reason: .unsupportedCapability("No local model satisfies this request."))
        )

        let preferLocal = router.routeChat(
            mode: .preferLocal,
            local: ("mlx", ProviderCapabilities(local: true, vision: true, toolCalling: true)),
            cloud: ("openai", ProviderCapabilities(local: false, vision: true, toolCalling: true)),
            requiresVision: true,
            requiresTools: true
        )
        try expectEqual(preferLocal.destination, .local("mlx"))
    }

    private static func testModelPreflight() throws {
        let llamaConfig = #"{"model_type":"llama"}"#.data(using: .utf8)!
        let llamaInput = ModelPreflightInput(
            repository: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            configJSON: llamaConfig,
            files: [
                .init(path: "model.safetensors", size: 1_200_000_000),
                .init(path: "tokenizer.json", size: 300_000),
            ]
        )
        let llama = ModelPreflightClassifier().classify(llamaInput)
        try expectEqual(llama.verification, .verified)
        try expect(llama.modalities.contains(.text), "curated llama should be text-capable")

        let bitnetConfig = #"{"model_type":"bitnet"}"#.data(using: .utf8)!
        let bitnetInput = ModelPreflightInput(
            repository: "mlx-community/bitnet-b1.58-2B-4T-4bit",
            configJSON: bitnetConfig,
            files: [
                .init(path: "model.safetensors", size: 1_800_000_000),
                .init(path: "tokenizer.json", size: 300_000),
            ],
            tags: ["bitnet"]
        )
        let bitnet = ModelPreflightClassifier().classify(bitnetInput)
        try expectEqual(bitnet.verification, .experimental)

        let unsupported = ModelPreflightClassifier().classify(
            ModelPreflightInput(
                repository: "mlx-community/Qwen3-4B-4bit",
                configJSON: #"{"model_type":"qwen3"}"#.data(using: .utf8)!,
                files: [.init(path: "tokenizer.json", size: 300_000)]
            )
        )
        try expectEqual(unsupported.verification, .unsupported)
    }

    private static func testPersistenceSchema() throws {
        let sql = PinesDatabaseSchema.migrations.flatMap(\.sql).joined(separator: "\n")
        try expect(sql.contains("CREATE TABLE IF NOT EXISTS conversations"), "missing conversations table")
        try expect(sql.contains("CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5"), "missing message FTS")
        try expect(sql.contains("CREATE VIRTUAL TABLE IF NOT EXISTS vault_chunks_fts USING fts5"), "missing vault FTS")
        try expect(sql.contains("CREATE TABLE IF NOT EXISTS audit_events"), "missing audit table")
        try expect(sql.contains("CREATE TABLE IF NOT EXISTS app_settings"), "missing settings table")
        try expect(sql.contains("CREATE TABLE IF NOT EXISTS cloud_providers"), "missing cloud provider table")
        try expect(sql.contains("CREATE TABLE IF NOT EXISTS model_downloads"), "missing download table")
        try expect(sql.contains("CREATE TABLE IF NOT EXISTS chat_runs"), "missing chat run table")
        try expect(sql.contains("CREATE TABLE IF NOT EXISTS tool_runs"), "missing tool run table")
        try expectEqual(PinesDatabaseSchema.currentVersion, 2)

        let config = LocalStoreConfiguration(iCloudSyncEnabled: true)
        try expect(config.iCloudSyncEnabled, "iCloud should be enabled")
        try expect(!config.syncsEmbeddings, "embeddings must not sync by default")
    }

    private static func testProductionTypes() throws {
        let settings = AppSettingsSnapshot(
            executionMode: .cloudAllowed,
            storeConfiguration: .init(iCloudSyncEnabled: true),
            defaultModelID: "local-model",
            requireToolApproval: true,
            braveSearchEnabled: true,
            onboardingCompleted: true,
            themeTemplate: "graphite",
            interfaceMode: "dark"
        )
        let decoded = try JSONDecoder().decode(AppSettingsSnapshot.self, from: JSONEncoder().encode(settings))
        try expectEqual(decoded.executionMode, .cloudAllowed)
        try expectEqual(decoded.themeTemplate, "graphite")

        let provider = CloudProviderConfiguration(
            id: "openai",
            kind: .openAICompatible,
            displayName: "OpenAI",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            defaultModelID: "gpt-4.1-mini",
            validationStatus: .valid,
            keychainAccount: "openai",
            enabledForAgents: true
        )
        try expectEqual(provider.validationStatus, .valid)
        try expectEqual(provider.defaultModelID?.rawValue, "gpt-4.1-mini")
    }

    private static func testArchitectureModules() throws {
        let modules = PinesArchitecture.modules
        try expectEqual(Set(modules.map(\.feature)), Set(PinesFeature.allCases))

        let tableOwners = Dictionary(grouping: modules.flatMap { module in
            module.ownsTables.map { table in (table, module.feature) }
        }, by: \.0)
        try expect(tableOwners["conversations"]?.contains { $0.1 == .chats } == true, "chats must own conversations")
        try expect(tableOwners["model_installs"]?.contains { $0.1 == .models } == true, "models must own model installs")
        try expect(tableOwners["vault_chunks"]?.contains { $0.1 == .vault } == true, "vault must own chunks")
    }

    private static func testRedactor() throws {
        let openAIShape = "sk-" + String(repeating: "a", count: 24)
        let huggingFaceShape = "hf_" + String(repeating: "b", count: 24)
        let bearerShape = "Bearer " + String(repeating: "c", count: 24)
        let input = "openai \(openAIShape) and \(huggingFaceShape) and \(bearerShape)"
        let output = Redactor().redact(input)
        try expect(!output.contains(openAIShape), "OpenAI key leaked")
        try expect(!output.contains(huggingFaceShape), "HF key leaked")
        try expect(!output.contains(bearerShape), "Bearer token leaked")
    }

    private static func testCalculator() throws {
        let evaluator = SafeCalculatorEvaluator()
        try expectClose(try evaluator.evaluate(" 1 + 2 * (3 + 4) "), 15)
        try expectClose(try evaluator.evaluate("-2^2"), -4)
        try expectClose(try evaluator.evaluate("(-2)^2"), 4)
        try expectClose(try evaluator.evaluate(".5 + 1.25e1"), 13)

        do {
            _ = try evaluator.evaluate("1 / (2 - 2)")
            throw TestFailure("division by zero should throw")
        } catch CalculatorEvaluationError.divisionByZero {
        }
    }

    private static func testToolRegistry() async throws {
        let registry = ToolRegistry()
        try await registry.register(CalculatorTool.spec())
        let output: CalculatorOutput = try await registry.call(
            CalculatorTool.name,
            input: CalculatorInput(expression: "6 * 7")
        )
        try expectClose(output.value, 42)
        try expectEqual(output.formatted, "42")

        let raw = try await registry.callRaw(CalculatorTool.name, inputJSON: #"{"expression":"7 * 6"}"#)
        try expect(raw.contains("42"), "raw tool output should contain encoded result")
    }

    private static func testInferenceStreamAdapter() async throws {
        let provider = FakeInferenceProvider()
        let stream = try await provider.stream(
            ChatRequest(modelID: "fake", messages: [ChatMessage(role: .user, content: "hello")])
        )
        var received = [TokenDelta.Kind]()
        for try await delta in stream {
            received.append(delta.kind)
        }
        try expectEqual(received, [.token, .metrics, .finish])
    }

    private static func testAgentPolicyGate() async throws {
        let spec = AnyToolSpec(try CalculatorTool.spec())
        let invocation = ToolInvocation(
            toolName: CalculatorTool.name,
            argumentsJSON: #"{"expression":"2+2"}"#,
            reason: "Need deterministic arithmetic.",
            expectedOutput: "A numeric result.",
            privacyImpact: "No data leaves the device."
        )
        try ToolPolicyGate().validate(invocation: invocation, spec: spec, policy: .init())

        let browserSpec = AnyToolSpec(try BuiltInToolSpecs.browserObserveSpec())
        let browserInvocation = ToolInvocation(
            toolName: "browser.observe",
            argumentsJSON: #"{"url":"https://example.com"}"#,
            reason: "Need page contents.",
            expectedOutput: "A page snapshot.",
            privacyImpact: "The page URL and visible contents are read by the local browser tool."
        )
        do {
            try ToolPolicyGate().validate(invocation: browserInvocation, spec: browserSpec, policy: .init())
            throw TestFailure("browser use should require explicit approval")
        } catch AgentError.permissionDenied {
        }
    }

    private static func testVaultChunking() throws {
        let chunker = VaultChunker(configuration: .init(maxCharacterCount: 5, overlapCharacterCount: 2))
        let first = chunker.chunk("abcdefghijkl", sourceID: "doc-a")
        let second = chunker.chunk("abcdefghijkl", sourceID: "doc-a")
        try expectEqual(first, second)
        try expectEqual(first.map(\.text), ["abcde", "defgh", "ghijk", "jkl"])
        try expectEqual(first.map(\.startOffset), [0, 3, 6, 9])

        let natural = VaultChunker(configuration: .init(maxCharacterCount: 12, overlapCharacterCount: 0))
            .chunk("alpha beta gamma delta", sourceID: "doc-b")
        try expectEqual(natural.map(\.text), ["alpha beta", "gamma delta"])
    }

    private static func testVectorIndex() throws {
        var index = VectorIndex()
        try index.insert(id: "x-axis", vector: [1.0, 0.0])
        try index.insert(id: "y-axis", vector: [0.0, 1.0])
        try index.insert(id: "diagonal", vector: [1.0, 1.0])

        let results = try index.search(query: [1.0, 0.0], limit: 3)
        try expectEqual(results.map(\.entry.id), ["x-axis", "diagonal", "y-axis"])
        try expectClose(results[0].score, 1)
        try expectClose(results[1].score, 1.0 / sqrt(2))
        try expectClose(results[2].score, 0)

        do {
            try index.insert(id: "bad", vector: [1.0])
            throw TestFailure("dimension mismatch should throw")
        } catch VectorIndexError.dimensionMismatch(expected: 2, actual: 1) {
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
        if actual != expected {
            throw TestFailure("Expected \(expected), received \(actual)")
        }
    }

    private static func expectClose(_ actual: Double, _ expected: Double, accuracy: Double = 1e-9) throws {
        if abs(actual - expected) > accuracy {
            throw TestFailure("Expected \(expected), received \(actual)")
        }
    }
}

private struct FakeInferenceProvider: InferenceProvider {
    var id: ProviderID { "fake" }
    var capabilities: ProviderCapabilities { .init(local: true) }

    func streamEvents(_ request: ChatRequest) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.token(TokenDelta(text: "hello", tokenCount: 1)))
            continuation.yield(.metrics(InferenceMetrics(promptTokens: 1, completionTokens: 1)))
            continuation.yield(.finish(InferenceFinish(reason: .stop)))
            continuation.finish()
        }
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        EmbeddingResult(modelID: request.modelID, vectors: [[1, 0]])
    }
}

struct TestFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
