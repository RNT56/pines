import Foundation
import PinesCore

#if canImport(GRDB)
import GRDB

extension GRDBPinesStore {
    func listProviderTransfers(providerID: ProviderID?) async throws -> [ProviderTransferRecord] {
        try await listProviderTransfers(providerID: providerID, limit: Int.max)
    }

    func listProviderTransfers(providerID: ProviderID?, limit: Int) async throws -> [ProviderTransferRecord] {
        guard limit > 0 else { return [] }
        return try await database.read { db in
            let rows: [Row]
            if let providerID {
                rows = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_transfers WHERE provider_id = ? ORDER BY updated_at DESC, id DESC LIMIT ?",
                    arguments: [providerID.rawValue, limit]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_transfers ORDER BY updated_at DESC, id DESC LIMIT ?",
                    arguments: [limit]
                )
            }
            return rows.compactMap(Self.providerTransfer(from:))
        }
    }

    func upsertProviderTransfer(_ transfer: ProviderTransferRecord) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO provider_transfers
                    (id, provider_id, provider_kind, source, source_reference, staged_local_path, file_name,
                     content_type, purpose, status, completed_bytes, total_bytes, retry_count, provider_object_id,
                     created_at, updated_at, completed_at, last_error)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    provider_id = excluded.provider_id,
                    provider_kind = excluded.provider_kind,
                    source = excluded.source,
                    source_reference = excluded.source_reference,
                    staged_local_path = excluded.staged_local_path,
                    file_name = excluded.file_name,
                    content_type = excluded.content_type,
                    purpose = excluded.purpose,
                    status = excluded.status,
                    completed_bytes = excluded.completed_bytes,
                    total_bytes = excluded.total_bytes,
                    retry_count = excluded.retry_count,
                    provider_object_id = excluded.provider_object_id,
                    updated_at = excluded.updated_at,
                    completed_at = excluded.completed_at,
                    last_error = excluded.last_error
                """,
                arguments: [
                    transfer.id.uuidString,
                    transfer.providerID.rawValue,
                    transfer.providerKind.rawValue,
                    transfer.source.rawValue,
                    transfer.sourceReference,
                    transfer.stagedLocalURL?.path,
                    transfer.fileName,
                    transfer.contentType,
                    transfer.purpose,
                    transfer.status.rawValue,
                    transfer.completedBytes,
                    transfer.totalBytes,
                    transfer.retryCount,
                    transfer.providerObjectID,
                    transfer.createdAt.timeIntervalSinceReferenceDate,
                    transfer.updatedAt.timeIntervalSinceReferenceDate,
                    transfer.completedAt?.timeIntervalSinceReferenceDate,
                    transfer.lastError,
                ]
            )
        }
    }

    func deleteProviderTransfer(id: UUID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM provider_transfers WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func markActiveProviderTransfersInterrupted(at date: Date) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                UPDATE provider_transfers
                SET status = ?, updated_at = ?, last_error = ?
                WHERE status IN (?, ?, ?, ?)
                """,
                arguments: [
                    ProviderTransferStatus.interrupted.rawValue,
                    date.timeIntervalSinceReferenceDate,
                    "Pines closed before this transfer finished. Retry to resume from the staged source.",
                    ProviderTransferStatus.queued.rawValue,
                    ProviderTransferStatus.preparing.rawValue,
                    ProviderTransferStatus.transferring.rawValue,
                    ProviderTransferStatus.verifying.rawValue,
                ]
            )
        }
    }

    func listCloudKitConflicts(unresolvedOnly: Bool) async throws -> [CloudKitConflictRecord] {
        try await database.read { db in
            let sql = unresolvedOnly
                ? "SELECT * FROM cloudkit_conflicts WHERE resolution = ? ORDER BY detected_at DESC"
                : "SELECT * FROM cloudkit_conflicts ORDER BY detected_at DESC"
            let arguments: StatementArguments = unresolvedOnly ? [CloudKitConflictResolution.unresolved.rawValue] : []
            return try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap(Self.cloudKitConflict(from:))
        }
    }

    func upsertCloudKitConflict(_ conflict: CloudKitConflictRecord) async throws {
        try await database.write { db in
            if conflict.resolution == .unresolved {
                try db.execute(
                    sql: "DELETE FROM cloudkit_conflicts WHERE entity = ? AND entity_id = ? AND resolution = ?",
                    arguments: [conflict.entity.rawValue, conflict.entityID.uuidString, CloudKitConflictResolution.unresolved.rawValue]
                )
            }
            try db.execute(
                sql: """
                INSERT INTO cloudkit_conflicts
                    (id, entity, entity_id, title, device_summary, icloud_summary, device_payload_json,
                     icloud_payload_json, device_updated_at, icloud_updated_at, resolution, detected_at, resolved_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    device_summary = excluded.device_summary,
                    icloud_summary = excluded.icloud_summary,
                    device_payload_json = excluded.device_payload_json,
                    icloud_payload_json = excluded.icloud_payload_json,
                    device_updated_at = excluded.device_updated_at,
                    icloud_updated_at = excluded.icloud_updated_at,
                    resolution = excluded.resolution,
                    resolved_at = excluded.resolved_at
                """,
                arguments: [
                    conflict.id.uuidString,
                    conflict.entity.rawValue,
                    conflict.entityID.uuidString,
                    conflict.title,
                    conflict.deviceSummary,
                    conflict.iCloudSummary,
                    conflict.devicePayloadJSON,
                    conflict.iCloudPayloadJSON,
                    conflict.deviceUpdatedAt.timeIntervalSinceReferenceDate,
                    conflict.iCloudUpdatedAt.timeIntervalSinceReferenceDate,
                    conflict.resolution.rawValue,
                    conflict.detectedAt.timeIntervalSinceReferenceDate,
                    conflict.resolvedAt?.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    func resolveCloudKitConflict(id: UUID, resolution: CloudKitConflictResolution, at date: Date) async throws {
        try await database.write { db in
            guard resolution != .unresolved,
                  let row = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM cloudkit_conflicts WHERE id = ? AND resolution = ?",
                    arguments: [id.uuidString, CloudKitConflictResolution.unresolved.rawValue]
                  ),
                  let entity = CloudKitConflictEntity(rawValue: row["entity"]),
                  let entityID = UUID(uuidString: row["entity_id"])
            else { return }

            switch (entity, resolution) {
            case (.conversation, .keepDevice):
                try db.execute(
                    sql: "UPDATE conversations SET sync_state = ?, updated_at = MAX(updated_at, ?) WHERE id = ?",
                    arguments: [SyncState.local.rawValue, date.timeIntervalSinceReferenceDate, entityID.uuidString]
                )
            case (.vaultDocument, .keepDevice):
                try db.execute(
                    sql: "UPDATE vault_documents SET sync_state = ?, updated_at = MAX(updated_at, ?) WHERE id = ?",
                    arguments: [SyncState.local.rawValue, date.timeIntervalSinceReferenceDate, entityID.uuidString]
                )
            case (.conversation, .useICloud):
                let json: String = row["icloud_payload_json"]
                let remote = try JSONDecoder().decode(CloudKitConversationSnapshot.self, from: Data(json.utf8))
                try Self.upsertCloudKitConversation(remote, deletedAt: remote.deletedAt, db: db)
            case (.vaultDocument, .useICloud):
                let json: String = row["icloud_payload_json"]
                let remote = try JSONDecoder().decode(CloudKitVaultDocumentSnapshot.self, from: Data(json.utf8))
                try Self.upsertCloudKitDocument(
                    remote,
                    syncState: remote.deletedAt == nil ? .synced : .deleted,
                    updatedAt: remote.deletedAt ?? remote.updatedAt,
                    db: db
                )
            case (_, .unresolved):
                return
            }
            try db.execute(
                sql: "UPDATE cloudkit_conflicts SET resolution = ?, resolved_at = ? WHERE id = ? AND resolution = ?",
                arguments: [
                    resolution.rawValue,
                    date.timeIntervalSinceReferenceDate,
                    id.uuidString,
                    CloudKitConflictResolution.unresolved.rawValue,
                ]
            )
        }
    }

    func openRouterSpendReport(window: OpenRouterSpendWindow, now: Date) async throws -> OpenRouterSpendReport {
        try await database.read { db in
            let rows: [Row]
            if let start = window.startDate(relativeTo: now) {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT provider_metadata_json
                    FROM messages
                    WHERE role = 'assistant' AND deleted_at IS NULL AND created_at >= ?
                      AND provider_metadata_json LIKE '%openrouter.%'
                    ORDER BY created_at DESC
                    """,
                    arguments: [start.timeIntervalSinceReferenceDate]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT provider_metadata_json
                    FROM messages
                    WHERE role = 'assistant' AND deleted_at IS NULL
                      AND provider_metadata_json LIKE '%openrouter.%'
                    ORDER BY created_at DESC
                    """
                )
            }

            var runCount = 0
            var reportedCostRunCount = 0
            var reportedCost = 0.0
            var upstreamCost = 0.0
            var promptTokens = 0
            var completionTokens = 0
            var webSearchRuns = 0
            var providers: [String: (runs: Int, reported: Double, upstream: Double)] = [:]

            for row in rows {
                guard let json: String = row["provider_metadata_json"],
                      let data = json.data(using: .utf8),
                      let metadata = try? JSONDecoder().decode([String: String].self, from: data)
                else { continue }
                runCount += 1
                let reported = metadata[CloudProviderMetadataKeys.openRouterCostCredits].flatMap(Double.init)
                let upstream = metadata[CloudProviderMetadataKeys.openRouterUpstreamInferenceCost].flatMap(Double.init) ?? 0
                if let reported {
                    reportedCostRunCount += 1
                    reportedCost += reported
                }
                upstreamCost += upstream
                promptTokens += metadata[CloudProviderMetadataKeys.openRouterPromptTokens].flatMap(Int.init) ?? 0
                completionTokens += metadata[CloudProviderMetadataKeys.openRouterCompletionTokens].flatMap(Int.init) ?? 0
                if metadata[CloudProviderMetadataKeys.openRouterWebSearchRequests].flatMap(Int.init) ?? 0 > 0 {
                    webSearchRuns += 1
                }
                let name = metadata[CloudProviderMetadataKeys.openRouterSelectedProvider]
                    ?? metadata[CloudProviderMetadataKeys.openRouterProvider]
                    ?? "Unreported provider"
                var bucket = providers[name] ?? (0, 0, 0)
                bucket.runs += 1
                bucket.reported += reported ?? 0
                bucket.upstream += upstream
                providers[name] = bucket
            }

            return OpenRouterSpendReport(
                window: window,
                generatedAt: now,
                runCount: runCount,
                reportedCostRunCount: reportedCostRunCount,
                missingCostRunCount: runCount - reportedCostRunCount,
                reportedCostCredits: reportedCost,
                upstreamCostCredits: upstreamCost,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                webSearchRunCount: webSearchRuns,
                byUpstreamProvider: providers.map { name, value in
                    OpenRouterSpendProviderBreakdown(
                        providerName: name,
                        runCount: value.runs,
                        reportedCostCredits: value.reported,
                        upstreamCostCredits: value.upstream
                    )
                }.sorted { $0.reportedCostCredits > $1.reportedCostCredits }
            )
        }
    }

    private static func providerTransfer(from row: Row) -> ProviderTransferRecord? {
        guard let id = UUID(uuidString: row["id"]),
              let kind = CloudProviderKind(rawValue: row["provider_kind"]),
              let source = ProviderTransferSource(rawValue: row["source"]),
              let status = ProviderTransferStatus(rawValue: row["status"])
        else { return nil }
        let stagedPath: String? = row["staged_local_path"]
        return ProviderTransferRecord(
            id: id,
            providerID: ProviderID(rawValue: row["provider_id"]),
            providerKind: kind,
            source: source,
            sourceReference: row["source_reference"],
            stagedLocalURL: stagedPath.map { URL(fileURLWithPath: $0) },
            fileName: row["file_name"],
            contentType: row["content_type"],
            purpose: row["purpose"],
            status: status,
            completedBytes: row["completed_bytes"],
            totalBytes: row["total_bytes"],
            retryCount: row["retry_count"],
            providerObjectID: row["provider_object_id"],
            createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"]),
            updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"]),
            completedAt: (row["completed_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:)),
            lastError: row["last_error"]
        )
    }

    private static func cloudKitConflict(from row: Row) -> CloudKitConflictRecord? {
        guard let id = UUID(uuidString: row["id"]),
              let entityID = UUID(uuidString: row["entity_id"]),
              let entity = CloudKitConflictEntity(rawValue: row["entity"]),
              let resolution = CloudKitConflictResolution(rawValue: row["resolution"])
        else { return nil }
        return CloudKitConflictRecord(
            id: id,
            entity: entity,
            entityID: entityID,
            title: row["title"],
            deviceSummary: row["device_summary"],
            iCloudSummary: row["icloud_summary"],
            devicePayloadJSON: row["device_payload_json"],
            iCloudPayloadJSON: row["icloud_payload_json"],
            deviceUpdatedAt: Date(timeIntervalSinceReferenceDate: row["device_updated_at"]),
            iCloudUpdatedAt: Date(timeIntervalSinceReferenceDate: row["icloud_updated_at"]),
            resolution: resolution,
            detectedAt: Date(timeIntervalSinceReferenceDate: row["detected_at"]),
            resolvedAt: (row["resolved_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))
        )
    }
}
#endif
