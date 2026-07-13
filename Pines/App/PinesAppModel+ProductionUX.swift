import Foundation
import PinesCore

@MainActor
extension PinesAppModel {
    func refreshOpenRouterSpend(window: OpenRouterSpendWindow, services: PinesAppServices) async {
        guard let repository = services.cloudSpendRepository else { return }
        do {
            setIfChanged(\.openRouterSpendReport, try await repository.openRouterSpendReport(window: window, now: Date()))
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
        }
    }

    func resolveCloudKitConflict(
        id: UUID,
        resolution: CloudKitConflictResolution,
        services: PinesAppServices
    ) async {
        guard resolution != .unresolved, let repository = services.cloudKitConflictRepository else { return }
        do {
            try await repository.resolveCloudKitConflict(id: id, resolution: resolution, at: Date())
            setIfChanged(\.cloudKitConflicts, try await repository.listCloudKitConflicts(unresolvedOnly: true))
            await appendAuditEvent(
                AuditEvent(
                    category: .security,
                    summary: resolution == .keepDevice
                        ? "Resolved an iCloud conflict by keeping this device's version."
                        : "Resolved an iCloud conflict by using the iCloud version."
                ),
                services: services,
                component: "cloudkit_conflict_resolved"
            )
            if resolution == .keepDevice {
                await syncCloudKitNow(services: services, reason: "conflict_keep_device")
            } else {
                await refreshAll(services: services)
            }
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
        }
    }
}
