import Foundation
import PinesCore

@main
struct PinesCoreTestRunner {
    static func main() async throws {
        try testExecutionRouter()
        try testModelPreflight()
        try testPersistenceSchema()
        try testProductionTypes()
        try testDeviceProfiles()
        try testArchitectureModules()
        try testRedactor()
        try testCalculator()
        try testToolSchemaSerialization()
        try testMCPTypes()
        try testMarkdownMessageParser()
        try await testToolRegistry()
        try await testInferenceStreamAdapter()
        try await testAgentPolicyGate()
        try testVaultChunking()
        try testVectorIndex()
        try testTurboQuantVectorCodec()
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
        try expect(sql.contains("CREATE TABLE IF NOT EXISTS vault_embeddings"), "missing vault embeddings table")
        try expect(sql.contains("CREATE TABLE IF NOT EXISTS chat_runs"), "missing chat run table")
        try expect(sql.contains("CREATE TABLE IF NOT EXISTS tool_runs"), "missing tool run table")
        try expect(sql.contains("CREATE TABLE IF NOT EXISTS mcp_servers"), "missing MCP server table")
        try expect(sql.contains("CREATE TABLE IF NOT EXISTS mcp_tools"), "missing MCP tool table")
        try expectEqual(PinesDatabaseSchema.currentVersion, 4)

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

        let runtimeProfile = RuntimeProfile()
        try expectEqual(runtimeProfile.quantization.algorithm, .turboQuant)
        try expectEqual(runtimeProfile.quantization.kvCacheStrategy, .turboQuant)
        try expectEqual(runtimeProfile.quantization.preset, .turbo3_5)
        try expectEqual(runtimeProfile.quantization.requestedBackend, .metalPolarQJL)
        try expectEqual(runtimeProfile.quantization.activeBackend, .mlxPacked)
        try expectEqual(runtimeProfile.quantization.metalCodecAvailable, false)
        let legacyQuantization = try JSONDecoder().decode(
            QuantizationProfile.self,
            from: #"{"kvBits":8,"kvGroupSize":64,"quantizedKVStart":256}"#.data(using: .utf8)!
        )
        try expectEqual(legacyQuantization.algorithm, .turboQuant)
        try expectEqual(legacyQuantization.preset, .turbo3_5)
        try expectEqual(legacyQuantization.requestedBackend, .metalPolarQJL)
        try expectEqual(legacyQuantization.metalCodecAvailable, false)

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

    private static func testDeviceProfiles() throws {
        let compact = DeviceProfile.recommended(
            for: RuntimeMemorySnapshot(
                physicalMemoryBytes: 6_000_000_000,
                availableMemoryBytes: 1_500_000_000,
                thermalState: "nominal"
            )
        )
        try expectEqual(compact.memoryTier, .compact)
        try expectEqual(compact.performanceClass, .a16Compact)
        try expectEqual(compact.recommendedPrefillStepSize, 256)
        try expectEqual(compact.recommendedSmallModelContextTokens, 16_384)
        try expectEqual(compact.recommendedEmbeddingBatchSize, 8)
        try expectEqual(compact.recommendedVectorScanLimit, 2048)

        let a19Sustained = DeviceProfile.recommended(
            for: RuntimeMemorySnapshot(
                physicalMemoryBytes: 12_000_000_000,
                availableMemoryBytes: 4_000_000_000,
                thermalState: "nominal",
                hardwareModelIdentifier: "iPhone18,2",
                metalKernelProfile: .sustainedA19Pro,
                metalSelfTestStatus: .passed
            )
        )
        try expectEqual(a19Sustained.performanceClass, .a19ProSustained)
        try expectEqual(a19Sustained.recommendedContextTokens, 32_768)
        try expectEqual(a19Sustained.recommendedSmallModelContextTokens, 65_536)
        try expectEqual(a19Sustained.recommendedPrefillStepSize, 1024)

        let pressured = DeviceProfile.recommended(
            for: RuntimeMemorySnapshot(
                physicalMemoryBytes: 16_000_000_000,
                availableMemoryBytes: 500_000_000,
                thermalState: "serious"
            )
        )
        try expectEqual(pressured.recommendedContextTokens, 4096)
        try expectEqual(pressured.recommendedEmbeddingBatchSize, 4)
        try expectEqual(pressured.turboQuantOptimizationPolicy, .conservative)
        try expect(pressured.thermalDownshiftActive, "thermal pressure should mark a downshift")
        try expect(!pressured.allowsVisionModels, "thermal pressure should disable vision defaults")

        let future = DeviceProfile.recommended(
            for: RuntimeMemorySnapshot(
                physicalMemoryBytes: 16_000_000_000,
                availableMemoryBytes: 8_000_000_000,
                thermalState: "nominal",
                hardwareModelIdentifier: "iPhone19,1",
                metalKernelProfile: .wideA18A19,
                metalSelfTestStatus: .passed
            )
        )
        try expectEqual(future.performanceClass, .futureVerified)
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

    private static func testToolSchemaSerialization() throws {
        let tool = AnyToolSpec(try CalculatorTool.spec())
        let openAIObject = tool.openAIFunctionToolObject()
        let function = try expectDictionary(openAIObject["function"], "OpenAI tool must include a function object")
        try expectEqual(function["name"] as? String, CalculatorTool.name)
        let parameters = try expectDictionary(function["parameters"], "OpenAI tool must include parameters")
        try expectEqual(parameters["type"] as? String, "object")

        let request = ChatRequest(
            modelID: "gpt-test",
            messages: [ChatMessage(role: .user, content: "2+2?")],
            allowsTools: true,
            availableTools: [tool]
        )
        let urlRequest = try OpenAICompatibleRequestBuilder().chatRequest(
            baseURL: URL(string: "https://api.example.test/v1")!,
            apiKey: "test",
            request: request
        )
        guard let body = urlRequest.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let tools = json["tools"] as? [[String: Any]]
        else {
            throw TestFailure("OpenAI-compatible request should advertise tools")
        }
        try expectEqual(tools.count, 1)
        try expectEqual(json["tool_choice"] as? String, "auto")

        let toolCall = ToolCallDelta(id: "call-1", name: CalculatorTool.name, argumentsFragment: #"{"expression":"2+2"}"#, isComplete: true)
        let encoded = try JSONEncoder().encode(
            ChatMessage(role: .assistant, content: "", toolCallID: toolCall.id, toolName: toolCall.name, toolCalls: [toolCall])
        )
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: encoded)
        try expectEqual(decoded.toolCalls, [toolCall])
    }

    private static func testMCPTypes() throws {
        let schema = JSONValue.object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Search query"),
                ]),
            ]),
            "required": .array([.string("query")]),
        ])
        let spec = try AnyToolSpec(
            name: "mcp.local.search",
            description: "Search a remote MCP server.",
            inputJSONSchema: schema,
            permissions: [.network],
            networkPolicy: .allowListedDomains(["localhost"])
        )
        let openAI = spec.openAIFunctionToolObject()
        let function = try expectDictionary(openAI["function"], "MCP tool must be a function")
        let parameters = try expectDictionary(function["parameters"], "MCP tool must preserve raw schema")
        try expectEqual(parameters["type"] as? String, "object")
        try expectEqual(MCPNameSanitizer.serverSlug(displayName: "Local MCP!", fallback: "fallback"), "local-mcp")
        try expect(MCPNameSanitizer.toolName(serverSlug: "server", originalName: "weird tool/name").hasPrefix("mcp.server.weird-tool-name"), "MCP tool names should be namespaced and sanitized")

        let record = MCPToolRecord(
            serverID: "local",
            originalName: "search",
            namespacedName: "mcp.local.search",
            displayName: "search",
            description: "Search",
            inputSchema: schema
        )
        let decoded = try JSONDecoder().decode(MCPToolRecord.self, from: JSONEncoder().encode(record))
        try expectEqual(decoded, record)
    }

    private static func testMarkdownMessageParser() throws {
        let source = """
        # Heading

        Hello **bold** *em* ~~old~~ `code` [link](https://example.com).

        - [x] Done
        - [ ] Todo
          - Nested

        | Name | Value |
        | --- | ---: |
        | `x` | **1** |

        ```swift
        let value = 1
        ```

        > Quote

        <div>raw</div>

        ![Alt](https://example.com/image.png)
        """

        let parsed = MarkdownMessageParser().parse(source)
        try expectEqual(parsed.containsIncompleteCodeFence, false)
        try expect(parsed.blocks.contains { block in
            if case let .heading(level, runs) = block {
                return level == 1 && MarkdownInlineRun.plainText(runs) == "Heading"
            }
            return false
        }, "markdown parser should parse headings")
        try expect(parsed.blocks.contains { block in
            if case let .unorderedList(items) = block {
                return items.count == 2 && items[0].checkbox == .checked && items[1].checkbox == .unchecked
            }
            return false
        }, "markdown parser should parse task list checkboxes")
        try expect(parsed.blocks.contains { block in
            if case let .table(table) = block {
                return table.header.count == 2
                    && table.rows.count == 1
                    && table.alignments.last == .trailing
            }
            return false
        }, "markdown parser should parse GFM tables")
        try expect(parsed.blocks.contains { block in
            if case let .codeBlock(language, code) = block {
                return language == "swift" && code.contains("let value")
            }
            return false
        }, "markdown parser should parse fenced code")
        try expect(parsed.blocks.contains { block in
            if case let .paragraph(runs) = block {
                return runs.contains { $0.traits.contains(.image) && $0.imageSource == "https://example.com/image.png" }
            }
            return false
        }, "markdown parser should preserve image placeholders")
        try expect(parsed.plainText.contains("bold"), "plain text should include formatted text")

        let streaming = MarkdownMessageParser().parse("```swift\nlet value = 1")
        try expect(streaming.containsIncompleteCodeFence, "streaming parser should detect incomplete fences")
        try expect(streaming.blocks.contains { block in
            if case let .codeBlock(language, code) = block {
                return language == "swift" && code.contains("let value")
            }
            return false
        }, "streaming parser should keep incomplete fenced code renderable")
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

        let remote = try AnyToolSpec(
            name: "mcp.local.echo",
            description: "Echo raw JSON.",
            inputJSONSchema: JSONValue.objectSchema(),
            permissions: [.network],
            networkPolicy: .allowListedDomains(["localhost"])
        )
        try await registry.registerRaw(remote) { inputJSON in
            #"{"echo":\#(inputJSON)}"#
        }
        let echoed = try await registry.callRaw("mcp.local.echo", inputJSON: #"{"value":true}"#)
        try expect(echoed.contains(#""value":true"#), "raw MCP tool should receive JSON unchanged")
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

    private static func testTurboQuantVectorCodec() throws {
        let codec = TurboQuantVectorCodec(preset: .turbo3_5, seed: 42)
        let vector: [Float] = [0.42, -0.2, 0.7, 0.1, -0.3, 0.15, 0.05, -0.4]
        let encoded = try codec.encode(vector)
        let encodedAgain = try codec.encode(vector)
        try expectEqual(encoded, encodedAgain)

        let decoded = try codec.decode(encoded)
        try expectEqual(decoded.count, vector.count)

        let score = try codec.approximateCosineSimilarity(query: vector, code: encoded)
        try expect(score > 0.92, "TurboQuant approximation should preserve self-similarity")

        let roundTrip = try codec.decode(data: try codec.encodeToData(vector))
        try expectEqual(roundTrip.count, vector.count)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }

    private static func expectDictionary(_ value: Any?, _ message: String) throws -> [String: any Sendable] {
        guard let dictionary = value as? [String: any Sendable] else {
            throw TestFailure(message)
        }
        return dictionary
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
