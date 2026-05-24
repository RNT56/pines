import Foundation

public struct FreezeBreadcrumb: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var runID: String?
    public var stage: String
    public var detail: String?
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        runID: String? = nil,
        stage: String,
        detail: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.runID = runID
        self.stage = stage
        self.detail = detail
        self.metadata = metadata
    }
}

public actor FreezeBreadcrumbJournal {
    public static let shared = FreezeBreadcrumbJournal()
    public static let diagnosticsDirectoryName = "PinesDiagnostics"
    public static let breadcrumbFileName = "pines-freeze-breadcrumbs.jsonl"

    private let fileURL: URL
    private let maximumEvents: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil, maximumEvents: Int = 512) {
        self.fileURL = fileURL ?? Self.defaultBreadcrumbFileURL()
        self.maximumEvents = max(1, maximumEvents)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["PINES_FREEZE_BREADCRUMBS"] == "1"
            || environment["PINES_STRESS_MODE"] != nil
            || arguments.contains("--pines-freeze-breadcrumbs")
            || arguments.contains("--pines-stress-local-generation")
    }

    public static func defaultDiagnosticsDirectoryURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent(diagnosticsDirectoryName, isDirectory: true)
    }

    public static func defaultBreadcrumbFileURL() -> URL {
        defaultDiagnosticsDirectoryURL().appendingPathComponent(breadcrumbFileName)
    }

    public func record(
        stage: String,
        runID: String? = nil,
        detail: String? = nil,
        metadata: [String: String] = [:],
        enabled: Bool = FreezeBreadcrumbJournal.isEnabled()
    ) async {
        guard enabled else { return }
        await append(
            FreezeBreadcrumb(
                runID: runID,
                stage: stage,
                detail: detail,
                metadata: metadata
            )
        )
    }

    public func append(_ breadcrumb: FreezeBreadcrumb) async {
        do {
            var events = try readEvents()
            events.append(breadcrumb)
            if events.count > maximumEvents {
                events.removeFirst(events.count - maximumEvents)
            }
            try writeEvents(events)
        } catch {
            // Breadcrumbs must never affect app execution.
        }
    }

    public func reset() async {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: fileURL, options: .atomic)
        } catch {
            // Diagnostics are best effort.
        }
    }

    public func events() async -> [FreezeBreadcrumb] {
        (try? readEvents()) ?? []
    }

    private func readEvents() throws -> [FreezeBreadcrumb] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard let contents = String(data: data, encoding: .utf8) else { return [] }
        return contents
            .split(separator: "\n")
            .compactMap { line -> FreezeBreadcrumb? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(FreezeBreadcrumb.self, from: data)
            }
    }

    private func writeEvents(_ events: [FreezeBreadcrumb]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let lines = try events.map { event -> String in
            String(decoding: try encoder.encode(event), as: UTF8.self)
        }.joined(separator: "\n")
        let output = lines.isEmpty ? "" : lines + "\n"
        try Data(output.utf8).write(to: fileURL, options: .atomic)
    }
}
