import Foundation
import PinesCore
import XCTest
@testable import pines

final class ArtifactActivityPollingSchedulerTests: XCTestCase {
    func testResearchOperationIdentityIgnoresUpdatedAt() throws {
        let original = makeResearchRun(updatedAt: Date(timeIntervalSince1970: 100))
        var refreshed = original
        refreshed.updatedAt = Date(timeIntervalSince1970: 200)
        refreshed.citationCount = 4
        refreshed.status = "queued"

        let originalOperation = try XCTUnwrap(ArtifactActivityPollOperation(researchRun: original))
        let refreshedOperation = try XCTUnwrap(ArtifactActivityPollOperation(researchRun: refreshed))

        XCTAssertEqual(originalOperation.id, refreshedOperation.id)
        XCTAssertEqual(
            ArtifactActivityPollOperation.stableSignature(for: [originalOperation]),
            ArtifactActivityPollOperation.stableSignature(for: [refreshedOperation])
        )
    }

    func testStableSignatureRestartsWhenRemoteOperationIdentityChanges() {
        let providerID = ProviderID(rawValue: "provider")
        let initial = ArtifactActivityPollOperation(
            id: "artifact",
            remoteID: "operations/first",
            providerID: providerID,
            kind: .geminiMedia
        )
        let updated = ArtifactActivityPollOperation(
            id: "artifact",
            remoteID: "operations/second",
            providerID: providerID,
            kind: .geminiMedia
        )

        XCTAssertNotEqual(
            ArtifactActivityPollOperation.stableSignature(for: [initial]),
            ArtifactActivityPollOperation.stableSignature(for: [updated])
        )
    }

    func testTerminalResearchRunDoesNotProducePollingOperation() {
        let completed = makeResearchRun(status: "completed")
        XCTAssertNil(ArtifactActivityPollOperation(researchRun: completed))
    }

    func testSchedulerSleepsBeforeEverySubsequentPoll() async {
        let events = PollEventRecorder()
        let attempts = PollAttemptCounter()
        let operation = makeOperation()
        let scheduler = ArtifactActivityPollingScheduler(
            configuration: .init(
                cadenceByKind: [.openAIVideo: 6],
                maximumBackoff: 30,
                jitterFraction: 0
            ),
            sleeper: { interval in
                await events.append(.sleep(interval))
            },
            randomUnit: { 0.5 }
        )

        await scheduler.run(operations: [operation]) { _ in
            let attempt = await attempts.increment(for: operation.id)
            await events.append(.poll(attempt))
            return attempt == 3 ? .terminal : .active
        }

        let recorded = await events.snapshot()
        XCTAssertEqual(
            recorded,
            [.poll(1), .sleep(6), .poll(2), .sleep(6), .poll(3)]
        )
    }

    func testSchedulerDeduplicatesOperationsAndNeverOverlapsOneOperation() async {
        let probe = PollOverlapProbe()
        let operation = makeOperation()
        let scheduler = ArtifactActivityPollingScheduler(
            configuration: .init(
                cadenceByKind: [.openAIVideo: 0],
                maximumBackoff: 0,
                jitterFraction: 0
            ),
            sleeper: { _ in },
            randomUnit: { 0.5 }
        )

        await scheduler.run(operations: [operation, operation]) { polledOperation in
            let attempt = await probe.begin(polledOperation.id)
            await Task.yield()
            await probe.end(polledOperation.id)
            return attempt == 2 ? .terminal : .active
        }

        let snapshot = await probe.snapshot(for: operation.id)
        XCTAssertEqual(snapshot.attempts, 2)
        XCTAssertEqual(snapshot.maximumInFlight, 1)
    }

    func testSchedulerAppliesExponentialBackoffAfterFailures() async {
        let intervals = PollIntervalRecorder()
        let attempts = PollAttemptCounter()
        let operation = makeOperation()
        let scheduler = ArtifactActivityPollingScheduler(
            configuration: .init(
                cadenceByKind: [.openAIVideo: 2],
                maximumBackoff: 10,
                jitterFraction: 0
            ),
            sleeper: { interval in
                await intervals.append(interval)
            },
            randomUnit: { 0.5 }
        )

        await scheduler.run(operations: [operation]) { _ in
            let attempt = await attempts.increment(for: operation.id)
            if attempt < 3 {
                throw PollTestError.transient
            }
            return .terminal
        }

        let recorded = await intervals.snapshot()
        XCTAssertEqual(recorded, [2, 4])
    }

    func testSchedulerCancellationStopsPendingLoop() async {
        let attempts = PollAttemptCounter()
        let operation = makeOperation()
        let scheduler = ArtifactActivityPollingScheduler(
            configuration: .init(
                cadenceByKind: [.openAIVideo: 60],
                maximumBackoff: 60,
                jitterFraction: 0
            ),
            sleeper: { _ in
                try await Task.sleep(for: .seconds(60))
            },
            randomUnit: { 0.5 }
        )

        let task = Task {
            await scheduler.run(operations: [operation]) { _ in
                _ = await attempts.increment(for: operation.id)
                return .active
            }
        }

        for _ in 0 ..< 1_000 {
            if await attempts.count(for: operation.id) > 0 {
                break
            }
            await Task.yield()
        }
        task.cancel()
        await task.value

        let count = await attempts.count(for: operation.id)
        XCTAssertEqual(count, 1)
    }

    private func makeOperation() -> ArtifactActivityPollOperation {
        ArtifactActivityPollOperation(
            id: "openAIVideo:openai:video-1",
            remoteID: "video-1",
            providerID: ProviderID(rawValue: "openai"),
            kind: .openAIVideo
        )
    }

    private func makeResearchRun(
        status: String = "in_progress",
        updatedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> ProviderResearchRunRecord {
        ProviderResearchRunRecord(
            id: "research-1",
            providerID: ProviderID(rawValue: "openai"),
            providerKind: .openAI,
            modelID: ModelID(rawValue: "gpt-test"),
            title: "Research",
            prompt: "Prompt",
            depth: "standard",
            sourcePolicy: .object([:]),
            reportFormat: "markdown",
            serviceTier: "default",
            status: status,
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: updatedAt
        )
    }
}

private enum PollTestError: Error {
    case transient
}

private enum PollEvent: Equatable, Sendable {
    case poll(Int)
    case sleep(TimeInterval)
}

private actor PollEventRecorder {
    private var events = [PollEvent]()

    func append(_ event: PollEvent) {
        events.append(event)
    }

    func snapshot() -> [PollEvent] {
        events
    }
}

private actor PollIntervalRecorder {
    private var intervals = [TimeInterval]()

    func append(_ interval: TimeInterval) {
        intervals.append(interval)
    }

    func snapshot() -> [TimeInterval] {
        intervals
    }
}

private actor PollAttemptCounter {
    private var counts = [String: Int]()

    func increment(for id: String) -> Int {
        counts[id, default: 0] += 1
        return counts[id, default: 0]
    }

    func count(for id: String) -> Int {
        counts[id, default: 0]
    }
}

private actor PollOverlapProbe {
    private var attempts = [String: Int]()
    private var inFlight = [String: Int]()
    private var maximumInFlight = [String: Int]()

    func begin(_ id: String) -> Int {
        attempts[id, default: 0] += 1
        inFlight[id, default: 0] += 1
        maximumInFlight[id] = max(maximumInFlight[id, default: 0], inFlight[id, default: 0])
        return attempts[id, default: 0]
    }

    func end(_ id: String) {
        inFlight[id, default: 0] -= 1
    }

    func snapshot(for id: String) -> (attempts: Int, maximumInFlight: Int) {
        (attempts[id, default: 0], maximumInFlight[id, default: 0])
    }
}
