import Foundation

public enum TurboQuantSchemaName: String, Codable, Sendable, CaseIterable {
    case admissionPlan = "AdmissionPlan"
    case runtimeMemoryZones = "RuntimeMemoryZones"
    case runDecision = "RunDecision"
    case failureEvent = "FailureEvent"
    case benchmarkReport = "BenchmarkReport"
    case profileEvidence = "ProfileEvidence"
    case qualityGate = "QualityGate"
    case memoryCalibration = "MemoryCalibration"
    case contextAssemblyPlan = "ContextAssemblyPlan"
    case kvSnapshotManifest = "KVSnapshotManifest"
    case snapshotSecurityPolicy = "SnapshotSecurityPolicy"
    case modelProfile = "ModelProfile"
    case turboQuantLayout = "TurboQuantLayout"
    case turboQuantLayoutNext = "TurboQuantLayoutNext"
    case adaptivePrecisionPolicy = "AdaptivePrecisionPolicy"
}

public struct TurboQuantSchemaDefinition: Hashable, Codable, Sendable {
    public var name: TurboQuantSchemaName
    public var version: Int

    public init(name: TurboQuantSchemaName, version: Int) {
        self.name = name
        self.version = version
    }
}

public enum TurboQuantSchemaRegistry {
    public static let admissionPlan = TurboQuantSchemaDefinition(name: .admissionPlan, version: 1)
    public static let runtimeMemoryZones = TurboQuantSchemaDefinition(name: .runtimeMemoryZones, version: 1)
    public static let runDecision = TurboQuantSchemaDefinition(name: .runDecision, version: 1)
    public static let failureEvent = TurboQuantSchemaDefinition(name: .failureEvent, version: 1)
    public static let benchmarkReport = TurboQuantSchemaDefinition(name: .benchmarkReport, version: 1)
    public static let profileEvidence = TurboQuantSchemaDefinition(name: .profileEvidence, version: 1)
    public static let qualityGate = TurboQuantSchemaDefinition(name: .qualityGate, version: 1)
    public static let memoryCalibration = TurboQuantSchemaDefinition(name: .memoryCalibration, version: 1)
    public static let contextAssemblyPlan = TurboQuantSchemaDefinition(name: .contextAssemblyPlan, version: 1)
    public static let kvSnapshotManifest = TurboQuantSchemaDefinition(name: .kvSnapshotManifest, version: 1)
    public static let snapshotSecurityPolicy = TurboQuantSchemaDefinition(name: .snapshotSecurityPolicy, version: 1)
    public static let modelProfile = TurboQuantSchemaDefinition(name: .modelProfile, version: 2)
    public static let turboQuantLayout = TurboQuantSchemaDefinition(name: .turboQuantLayout, version: 4)
    public static let turboQuantLayoutNext = TurboQuantSchemaDefinition(name: .turboQuantLayoutNext, version: 5)
    public static let adaptivePrecisionPolicy = TurboQuantSchemaDefinition(name: .adaptivePrecisionPolicy, version: 1)

    public static let allDefinitions: [TurboQuantSchemaDefinition] = [
        admissionPlan,
        runtimeMemoryZones,
        runDecision,
        failureEvent,
        benchmarkReport,
        profileEvidence,
        qualityGate,
        memoryCalibration,
        contextAssemblyPlan,
        kvSnapshotManifest,
        snapshotSecurityPolicy,
        modelProfile,
        turboQuantLayout,
        turboQuantLayoutNext,
        adaptivePrecisionPolicy,
    ]

    public static let versionsByName: [TurboQuantSchemaName: Int] = Dictionary(
        uniqueKeysWithValues: allDefinitions.map { ($0.name, $0.version) }
    )
}

public struct VersionedEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public var schemaName: String
    public var schemaVersion: Int
    public var producer: SchemaProducer
    public var compatibility: SchemaCompatibility
    public var createdAt: Date
    public var payload: Payload

    public init(
        schemaName: String,
        schemaVersion: Int,
        producer: SchemaProducer,
        compatibility: SchemaCompatibility,
        createdAt: Date,
        payload: Payload
    ) {
        self.schemaName = schemaName
        self.schemaVersion = schemaVersion
        self.producer = producer
        self.compatibility = compatibility
        self.createdAt = createdAt
        self.payload = payload
    }
}

public struct SchemaProducer: Hashable, Codable, Sendable {
    public var repo: String
    public var commit: String?
    public var build: String?
    public var osBuild: String?

    public init(repo: String, commit: String? = nil, build: String? = nil, osBuild: String? = nil) {
        self.repo = repo
        self.commit = commit
        self.build = build
        self.osBuild = osBuild
    }
}

public struct SchemaCompatibility: Hashable, Codable, Sendable {
    public var minReaderVersion: Int
    public var maxTestedReaderVersion: Int
    public var failClosedIfNewer: Bool

    public init(minReaderVersion: Int, maxTestedReaderVersion: Int, failClosedIfNewer: Bool) {
        self.minReaderVersion = minReaderVersion
        self.maxTestedReaderVersion = maxTestedReaderVersion
        self.failClosedIfNewer = failClosedIfNewer
    }
}
