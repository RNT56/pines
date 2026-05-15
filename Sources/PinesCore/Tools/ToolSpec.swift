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

public struct ToolParameterSpec: Codable, Equatable, Hashable, Sendable {
    public let type: ToolValueType
    public let description: String?

    public init(type: ToolValueType, description: String? = nil) {
        self.type = type
        self.description = description
    }
}

public struct ToolIOSchema: Codable, Equatable, Hashable, Sendable {
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

extension NetworkPolicy: Hashable {}

public struct AnyToolSpec: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let version: String
    public let description: String
    public let inputSchema: ToolIOSchema
    public let outputSchema: ToolIOSchema
    public let inputJSONSchema: JSONValue?
    public let outputJSONSchema: JSONValue?
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
        inputJSONSchema = nil
        outputJSONSchema = nil
        permissions = spec.permissions
        sideEffect = spec.sideEffect
        networkPolicy = spec.networkPolicy
        timeoutSeconds = spec.timeoutSeconds
        explanationRequired = spec.explanationRequired
        inputType = spec.inputTypeName
        outputType = spec.outputTypeName
    }

    public init(
        name: String,
        version: String = "1.0.0",
        description: String,
        inputJSONSchema: JSONValue,
        outputJSONSchema: JSONValue? = nil,
        permissions: Set<ToolPermission> = [],
        sideEffect: SideEffectLevel = .none,
        networkPolicy: NetworkPolicy = .noNetwork,
        timeoutSeconds: Int = 30,
        explanationRequired: Bool = true,
        inputType: String = "JSON",
        outputType: String = "JSON"
    ) throws {
        self.name = try ToolSpec<EmptyToolInput, EmptyToolOutput>.validatedNameForErasure(name)
        self.version = version
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else {
            throw ToolSpecError.emptyDescription
        }
        self.description = trimmedDescription
        self.inputSchema = Self.toolIOSchema(from: inputJSONSchema)
        self.outputSchema = Self.toolIOSchema(from: outputJSONSchema ?? JSONValue.objectSchema())
        self.inputJSONSchema = inputJSONSchema
        self.outputJSONSchema = outputJSONSchema
        self.permissions = permissions
        self.sideEffect = sideEffect
        self.networkPolicy = networkPolicy
        self.timeoutSeconds = timeoutSeconds
        self.explanationRequired = explanationRequired
        self.inputType = inputType
        self.outputType = outputType
    }

    enum CodingKeys: String, CodingKey {
        case name
        case version
        case description
        case inputSchema
        case outputSchema
        case inputJSONSchema
        case outputJSONSchema
        case permissions
        case sideEffect
        case networkPolicy
        case timeoutSeconds
        case explanationRequired
        case inputType
        case outputType
    }

    private static func toolIOSchema(from schema: JSONValue) -> ToolIOSchema {
        guard let object = schema.objectValue else {
            return ToolIOSchema()
        }
        let type = (object["type"]?.stringValue).flatMap(ToolValueType.init(rawValue:)) ?? .object
        let required: [String]
        if case let .array(values)? = object["required"] {
            required = values.compactMap(\.stringValue)
        } else {
            required = []
        }
        var properties = [String: ToolParameterSpec]()
        if case let .object(propertyObjects)? = object["properties"] {
            for (name, value) in propertyObjects {
                guard let parameter = value.objectValue else { continue }
                let propertyType = (parameter["type"]?.stringValue).flatMap(ToolValueType.init(rawValue:)) ?? .string
                properties[name] = ToolParameterSpec(type: propertyType, description: parameter["description"]?.stringValue)
            }
        }
        return ToolIOSchema(type: type, properties: properties, required: required)
    }
}

private struct EmptyToolInput: ToolInput {}
private struct EmptyToolOutput: ToolOutput {}

public extension JSONValue {
    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }
}

public extension ToolParameterSpec {
    func jsonSchemaObject() -> [String: any Sendable] {
        var object: [String: any Sendable] = ["type": type.rawValue]
        if let description {
            object["description"] = description
        }
        return object
    }
}

public extension ToolIOSchema {
    var jsonValue: JSONValue {
        var propertiesObject = [String: JSONValue]()
        for (name, spec) in properties {
            var object: [String: JSONValue] = ["type": .string(spec.type.rawValue)]
            if let description = spec.description {
                object["description"] = .string(description)
            }
            propertiesObject[name] = .object(object)
        }

        return .object([
            "type": .string(type.rawValue),
            "properties": .object(propertiesObject),
            "required": .array(required.map(JSONValue.string)),
        ])
    }

    func jsonSchemaObject() -> [String: any Sendable] {
        var propertiesObject = [String: any Sendable]()
        for (name, spec) in properties {
            propertiesObject[name] = spec.jsonSchemaObject()
        }

        return [
            "type": type.rawValue,
            "properties": propertiesObject,
            "required": required,
        ]
    }
}

public extension AnyToolSpec {
    func openAIFunctionToolObject() -> [String: any Sendable] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": (inputJSONSchema ?? inputSchema.jsonValue).anySendable,
            ] as [String: any Sendable],
        ]
    }

    func anthropicToolObject() -> [String: any Sendable] {
        [
            "name": name,
            "description": description,
            "input_schema": (inputJSONSchema ?? inputSchema.jsonValue).anySendable,
        ]
    }

    func geminiFunctionDeclarationObject() -> [String: any Sendable] {
        [
            "name": name,
            "description": description,
            "parameters": (inputJSONSchema ?? inputSchema.jsonValue).anySendable,
        ]
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

    fileprivate static func validatedNameForErasure(_ name: String) throws -> String {
        try validatedName(name)
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
