import Foundation

public struct TurboQuantDeviceAcceptanceExport: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var report: TurboQuantBenchmarkReport
    public var importedEvidence: RuntimeProfileEvidence?
    public var importFailure: String?
    public var exportedAt: Date

    public init(
        schemaVersion: Int = Self.schemaVersion,
        report: TurboQuantBenchmarkReport,
        importedEvidence: RuntimeProfileEvidence? = nil,
        importFailure: String? = nil,
        exportedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.report = report
        self.importedEvidence = importedEvidence
        self.importFailure = importFailure
        self.exportedAt = exportedAt
    }
}

public struct TurboQuantDeviceAcceptanceRunner: Sendable {
    public init() {}

    public func importAcceptanceReport(
        _ report: TurboQuantBenchmarkReport,
        policy: TurboQuantBenchmarkImportPolicy
    ) -> TurboQuantDeviceAcceptanceExport {
        do {
            let result = try TurboQuantBenchmarkImporter().importReport(report, policy: policy)
            return TurboQuantDeviceAcceptanceExport(report: report, importedEvidence: result.evidence)
        } catch {
            return TurboQuantDeviceAcceptanceExport(
                report: report,
                importFailure: String(describing: error)
            )
        }
    }

    public func encodeExport(_ export: TurboQuantDeviceAcceptanceExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    public func decodeExport(_ data: Data) throws -> TurboQuantDeviceAcceptanceExport {
        try JSONDecoder().decode(TurboQuantDeviceAcceptanceExport.self, from: data)
    }
}

public struct TurboQuantEvidenceSupportBundle: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var evidence: [RuntimeProfileEvidence]
    public var revocations: [RuntimeEvidenceRevocation]
    public var memoryCalibrationSamples: [RuntimeMemoryCalibrationSample]
    public var memoryCalibrations: [RuntimeMemoryCalibration]
    public var exportedAt: Date

    public init(
        schemaVersion: Int = Self.schemaVersion,
        evidence: [RuntimeProfileEvidence],
        revocations: [RuntimeEvidenceRevocation] = [],
        memoryCalibrationSamples: [RuntimeMemoryCalibrationSample] = [],
        memoryCalibrations: [RuntimeMemoryCalibration] = [],
        exportedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.evidence = evidence
        self.revocations = revocations
        self.memoryCalibrationSamples = memoryCalibrationSamples
        self.memoryCalibrations = memoryCalibrations
        self.exportedAt = exportedAt
    }
}

public struct TurboQuantEvidenceSupportBundleExporter: Sendable {
    public init() {}

    public func encode(_ bundle: TurboQuantEvidenceSupportBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundle)
    }

    public func decode(_ data: Data) throws -> TurboQuantEvidenceSupportBundle {
        try JSONDecoder().decode(TurboQuantEvidenceSupportBundle.self, from: data)
    }
}
