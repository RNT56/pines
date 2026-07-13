import Foundation
import PinesCore
import Testing

@Suite("Production UX contracts")
struct ProductionUXTypesTests {
    @Test
    func hostedToolApprovalExplainsEnvironmentEgressAndSideEffects() {
        let request = ChatRequest(
            modelID: ModelID(rawValue: "provider/model"),
            messages: [],
            hostedTools: [
                .bash,
                .webSearch,
                .remoteMCP(
                    serverLabel: "Issue tracker",
                    serverURL: "https://mcp.example.test",
                    requireApproval: "always"
                ),
            ],
            openAIResponseOptions: OpenAIResponseRequestOptions(
                hostedTools: [
                    OpenAIHostedToolRequest(kind: .textEditor),
                ]
            )
        )

        let descriptors = request.hostedToolApprovalDescriptors(providerName: "Example Cloud")
        #expect(descriptors.count == 3)
        #expect(descriptors.contains { $0.providerToolName == "bash" && $0.environment.contains("hosted container") })
        #expect(descriptors.contains { $0.providerToolName == "remote_mcp" && $0.networkDestinations == ["https://mcp.example.test"] })
        #expect(descriptors.allSatisfy { !$0.dataLeavingDevice.isEmpty && !$0.sideEffects.isEmpty && !$0.retentionNotice.isEmpty })
        #expect(!descriptors.contains { $0.providerToolName == "web_search" })
    }

    @Test
    func transferProgressIsBoundedAndRetryStateIsExplicit() {
        var transfer = ProviderTransferRecord(
            providerID: ProviderID(rawValue: "provider"),
            providerKind: .openAI,
            source: .localFile,
            sourceReference: "file.bin",
            fileName: "file.bin",
            status: .failed,
            completedBytes: 1_500,
            totalBytes: 1_000
        )
        #expect(transfer.progressFraction == 1)
        #expect(transfer.status.canRetry)
        transfer.completedBytes = -100
        #expect(transfer.progressFraction == 0)
    }

    @Test
    func spendWindowsHaveStableBoundaries() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        #expect(OpenRouterSpendWindow.day.startDate(relativeTo: now) == now.addingTimeInterval(-86_400))
        #expect(OpenRouterSpendWindow.week.startDate(relativeTo: now) == now.addingTimeInterval(-604_800))
        #expect(OpenRouterSpendWindow.month.startDate(relativeTo: now) == now.addingTimeInterval(-2_592_000))
        #expect(OpenRouterSpendWindow.all.startDate(relativeTo: now) == nil)
    }
}
