import Foundation

public enum ToolRegistryError: Error, Equatable, CustomStringConvertible, Sendable {
    case duplicateTool(name: String)
    case toolNotFound(name: String)
    case typeMismatch(
        name: String,
        expectedInput: String,
        expectedOutput: String,
        actualInput: String,
        actualOutput: String
    )

    public var description: String {
        switch self {
        case let .duplicateTool(name):
            "Tool is already registered: \(name)"
        case let .toolNotFound(name):
            "Tool is not registered: \(name)"
        case let .typeMismatch(name, expectedInput, expectedOutput, actualInput, actualOutput):
            "Tool \(name) expects \(expectedInput) -> \(expectedOutput), got \(actualInput) -> \(actualOutput)."
        }
    }
}

private struct RegisteredTool: Sendable {
    let metadata: AnyToolSpec
    let run: @Sendable (Data) async throws -> Data
}

public actor ToolRegistry {
    private var tools: [String: RegisteredTool] = [:]

    public init() {}

    public func register<Input: ToolInput, Output: ToolOutput>(_ spec: ToolSpec<Input, Output>) throws {
        guard tools[spec.name] == nil else {
            throw ToolRegistryError.duplicateTool(name: spec.name)
        }

        let registered = RegisteredTool(metadata: AnyToolSpec(spec)) { data in
            let input = try JSONDecoder().decode(Input.self, from: data)
            let output = try await spec.handler(input)
            return try JSONEncoder().encode(output)
        }

        tools[spec.name] = registered
    }

    @discardableResult
    public func unregister(_ name: String) -> Bool {
        tools.removeValue(forKey: name) != nil
    }

    public func spec(named name: String) -> AnyToolSpec? {
        tools[name]?.metadata
    }

    public func listSpecs() -> [AnyToolSpec] {
        tools.values
            .map(\.metadata)
            .sorted { $0.name < $1.name }
    }

    public func call<Input: ToolInput, Output: ToolOutput>(
        _ name: String,
        input: Input,
        as outputType: Output.Type = Output.self
    ) async throws -> Output {
        guard let tool = tools[name] else {
            throw ToolRegistryError.toolNotFound(name: name)
        }

        let actualInput = String(reflecting: Input.self)
        let actualOutput = String(reflecting: Output.self)

        guard tool.metadata.inputType == actualInput, tool.metadata.outputType == actualOutput else {
            throw ToolRegistryError.typeMismatch(
                name: name,
                expectedInput: tool.metadata.inputType,
                expectedOutput: tool.metadata.outputType,
                actualInput: actualInput,
                actualOutput: actualOutput
            )
        }

        let inputData = try JSONEncoder().encode(input)
        let outputData = try await tool.run(inputData)
        return try JSONDecoder().decode(Output.self, from: outputData)
    }
}
