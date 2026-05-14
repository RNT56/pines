import Foundation

public protocol ToolInput: Codable, Sendable {}
public protocol ToolOutput: Codable, Sendable {}

public enum ToolValueType: String, Codable, CaseIterable, Sendable {
    case array
    case boolean
    case integer
    case number
    case object
    case string
}

public struct ToolParameterSpec: Codable, Equatable, Sendable {
    public let type: ToolValueType
    public let description: String?

    public init(type: ToolValueType, description: String? = nil) {
        self.type = type
        self.description = description
    }
}

public struct ToolIOSchema: Codable, Equatable, Sendable {
    public let type: ToolValueType
    public let properties: [String: ToolParameterSpec]
    public let required: [String]

    public init(
        type: ToolValueType = .object,
        properties: [String: ToolParameterSpec] = [:],
        required: [String] = []
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

public typealias JSONSchema = ToolIOSchema

public enum ToolPermission: String, Codable, CaseIterable, Sendable {
    case localComputation
    case network
    case browser
    case files
    case photos
    case clipboard
    case cloudContext
}

public enum SideEffectLevel: String, Codable, CaseIterable, Sendable {
    case none
    case readsExternalData
    case writesLocalData
    case changesRemoteState
    case sensitive
}

public enum NetworkPolicy: Codable, Equatable, Sendable {
    case noNetwork
    case allowListedDomains([String])
    case userApproved

    enum CodingKeys: String, CodingKey {
        case kind
        case domains
    }

    enum Kind: String, Codable {
        case noNetwork
        case allowListedDomains
        case userApproved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .noNetwork:
            self = .noNetwork
        case .allowListedDomains:
            self = .allowListedDomains(try container.decode([String].self, forKey: .domains))
        case .userApproved:
            self = .userApproved
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noNetwork:
            try container.encode(Kind.noNetwork, forKey: .kind)
        case let .allowListedDomains(domains):
            try container.encode(Kind.allowListedDomains, forKey: .kind)
            try container.encode(domains, forKey: .domains)
        case .userApproved:
            try container.encode(Kind.userApproved, forKey: .kind)
        }
    }
}

public struct AnyToolSpec: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
    public let description: String
    public let inputSchema: ToolIOSchema
    public let outputSchema: ToolIOSchema
    public let permissions: Set<ToolPermission>
    public let sideEffect: SideEffectLevel
    public let networkPolicy: NetworkPolicy
    public let timeoutSeconds: Int
    public let explanationRequired: Bool
    public let inputType: String
    public let outputType: String

    public init<Input: ToolInput, Output: ToolOutput>(_ spec: ToolSpec<Input, Output>) {
        name = spec.name
        version = spec.version
        description = spec.description
        inputSchema = spec.inputSchema
        outputSchema = spec.outputSchema
        permissions = spec.permissions
        sideEffect = spec.sideEffect
        networkPolicy = spec.networkPolicy
        timeoutSeconds = spec.timeoutSeconds
        explanationRequired = spec.explanationRequired
        inputType = spec.inputTypeName
        outputType = spec.outputTypeName
    }
}

public enum ToolSpecError: Error, Equatable, CustomStringConvertible, Sendable {
    case emptyDescription
    case invalidName(String)

    public var description: String {
        switch self {
        case .emptyDescription:
            "Tool descriptions must not be empty."
        case let .invalidName(name):
            "Invalid tool name: \(name)"
        }
    }
}

public struct ToolSpec<Input: ToolInput, Output: ToolOutput>: Sendable {
    public typealias Handler = @Sendable (Input) async throws -> Output

    public let name: String
    public let version: String
    public let description: String
    public let inputSchema: ToolIOSchema
    public let outputSchema: ToolIOSchema
    public let permissions: Set<ToolPermission>
    public let sideEffect: SideEffectLevel
    public let networkPolicy: NetworkPolicy
    public let timeoutSeconds: Int
    public let explanationRequired: Bool
    public let inputTypeName: String
    public let outputTypeName: String

    let handler: Handler

    public init(
        name: String,
        version: String = "1.0.0",
        description: String,
        inputSchema: ToolIOSchema,
        outputSchema: ToolIOSchema,
        permissions: Set<ToolPermission> = [],
        sideEffect: SideEffectLevel = .none,
        networkPolicy: NetworkPolicy = .noNetwork,
        timeoutSeconds: Int = 10,
        explanationRequired: Bool = true,
        handler: @escaping Handler
    ) throws {
        self.name = try Self.validatedName(name)
        self.version = version

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else {
            throw ToolSpecError.emptyDescription
        }

        self.description = trimmedDescription
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.permissions = permissions
        self.sideEffect = sideEffect
        self.networkPolicy = networkPolicy
        self.timeoutSeconds = timeoutSeconds
        self.explanationRequired = explanationRequired
        inputTypeName = String(reflecting: Input.self)
        outputTypeName = String(reflecting: Output.self)
        self.handler = handler
    }

    public func call(_ input: Input) async throws -> Output {
        try await handler(input)
    }

    private static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = Array(trimmed.unicodeScalars)

        guard !scalars.isEmpty, scalars.count <= 64 else {
            throw ToolSpecError.invalidName(name)
        }

        guard let first = scalars.first, let last = scalars.last,
              Self.isAlphaNumeric(first), Self.isAlphaNumeric(last)
        else {
            throw ToolSpecError.invalidName(name)
        }

        for scalar in scalars {
            guard Self.isAllowedNameScalar(scalar) else {
                throw ToolSpecError.invalidName(name)
            }
        }

        return trimmed
    }

    private static func isAllowedNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        isAlphaNumeric(scalar) || scalar.value == 45 || scalar.value == 46 || scalar.value == 95
    }

    private static func isAlphaNumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            true
        default:
            false
        }
    }
}
