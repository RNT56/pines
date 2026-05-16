import Foundation
import PinesWatchSupport

#if canImport(WatchConnectivity)
@preconcurrency import WatchConnectivity

@MainActor
final class PhoneWatchSessionService: NSObject, WCSessionDelegate {
    private let services: PinesAppServices
    private let session: WCSession
    private var runTasks: [UUID: Task<Void, Never>] = [:]
    private var requestRuns: [UUID: UUID] = [:]
    private var requestConversations: [UUID: UUID] = [:]
    private var completedRequests = Set<UUID>()
    private var completedRequestOrder: [UUID] = []
    private var suppressApplicationContextUpdates = false
    private static let completedRequestLimit = 64

    init(services: PinesAppServices, session: WCSession = .default) {
        self.services = services
        self.session = session
        super.init()
    }

    deinit {
        runTasks.values.forEach { $0.cancel() }
        session.delegate = nil
    }

    func start() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        publishPhoneStatus()
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.suppressApplicationContextUpdates = false
            self.publishPhoneStatus()
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.suppressApplicationContextUpdates = false
            session.activate()
            self.publishPhoneStatus()
        }
    }
    #endif

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.suppressApplicationContextUpdates = false
            self.publishPhoneStatus()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let envelopeData = try? WatchChatCodec.envelopeData(from: message)
        nonisolated(unsafe) let replyHandler = replyHandler
        Task { @MainActor in
            let reply: [String: Any]
            if let envelopeData {
                reply = await self.handleEnvelopeData(envelopeData)
            } else {
                reply = (try? self.errorReply("Invalid watch message.", requestID: UUID())) ?? [:]
            }
            replyHandler(reply)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let envelopeData = try? WatchChatCodec.envelopeData(from: userInfo)
        Task { @MainActor in
            if let envelopeData {
                _ = await self.handleEnvelopeData(envelopeData)
            }
        }
    }

    private func handleEnvelopeData(_ data: Data) async -> [String: Any] {
        do {
            let envelope = try WatchChatCodec.envelope(from: data)
            let orchestrator = WatchChatOrchestrator(services: services)

            switch envelope.kind {
            case .phoneStatus:
                return try WatchChatCodec.message(
                    kind: .phoneStatus,
                    requestID: envelope.requestID,
                    payload: phoneStatus()
                )
            case .listConversations:
                return try snapshotReply(
                    try await orchestrator.snapshot(),
                    requestID: envelope.requestID
                )
            case .loadConversation:
                let request = try WatchChatCodec.decode(WatchLoadConversationRequest.self, from: envelope)
                return try snapshotReply(
                    try await orchestrator.snapshot(selectedConversationID: request.conversationID),
                    requestID: envelope.requestID
                )
            case .createConversation:
                return try snapshotReply(
                    try await orchestrator.createConversation(),
                    requestID: envelope.requestID
                )
            case .renameConversation:
                let request = try WatchChatCodec.decode(WatchRenameConversationRequest.self, from: envelope)
                return try snapshotReply(
                    try await orchestrator.renameConversation(request),
                    requestID: envelope.requestID
                )
            case .archiveConversation:
                let request = try WatchChatCodec.decode(WatchArchiveConversationRequest.self, from: envelope)
                return try snapshotReply(
                    try await orchestrator.setConversationArchived(request),
                    requestID: envelope.requestID
                )
            case .deleteConversation:
                let request = try WatchChatCodec.decode(WatchDeleteConversationRequest.self, from: envelope)
                return try snapshotReply(
                    try await orchestrator.deleteConversation(request),
                    requestID: envelope.requestID
                )
            case .sendMessage:
                let request = try WatchChatCodec.decode(WatchSendMessageRequest.self, from: envelope)
                if completedRequests.contains(envelope.requestID) {
                    let snapshot = try await orchestrator.snapshot(selectedConversationID: requestConversations[envelope.requestID])
                    return try snapshotReply(snapshot, requestID: envelope.requestID)
                }
                if let existingRunID = requestRuns[envelope.requestID] {
                    let update = WatchChatRunUpdate(
                        runID: existingRunID,
                        conversationID: requestConversations[envelope.requestID] ?? request.conversationID ?? UUID(),
                        assistantMessageID: nil,
                        status: .accepted,
                        text: ""
                    )
                    return try WatchChatCodec.message(
                        kind: .runUpdate,
                        requestID: envelope.requestID,
                        payload: update
                    )
                }
                let runID = UUID()
                startRun(request, runID: runID, requestID: envelope.requestID)
                let selectedConversationID: UUID?
                if let conversationID = request.conversationID {
                    selectedConversationID = conversationID
                } else {
                    let snapshot = try? await orchestrator.snapshot()
                    selectedConversationID = snapshot?.selectedConversationID
                }
                requestRuns[envelope.requestID] = runID
                if let selectedConversationID {
                    requestConversations[envelope.requestID] = selectedConversationID
                }
                let update = WatchChatRunUpdate(
                    runID: runID,
                    conversationID: selectedConversationID ?? UUID(),
                    assistantMessageID: nil,
                    status: .accepted,
                    text: ""
                )
                return try WatchChatCodec.message(
                    kind: .runUpdate,
                    requestID: envelope.requestID,
                    payload: update
                )
            case .cancelRun:
                let request = try WatchChatCodec.decode(WatchCancelRunRequest.self, from: envelope)
                runTasks[request.runID]?.cancel()
                if let requestID = requestRuns.first(where: { $0.value == request.runID })?.key {
                    clearRun(runID: request.runID, requestID: requestID)
                } else {
                    runTasks[request.runID] = nil
                }
                return try WatchChatCodec.message(kind: .cancelRun, requestID: envelope.requestID)
            case .snapshot, .runUpdate, .error:
                return try errorReply("Unsupported watch-to-phone message: \(envelope.kind.rawValue)", requestID: envelope.requestID)
            }
        } catch {
            return (try? errorReply(error.localizedDescription, requestID: UUID())) ?? [:]
        }
    }

    private func startRun(_ request: WatchSendMessageRequest, runID: UUID, requestID: UUID) {
        runTasks[runID]?.cancel()
        let orchestrator = WatchChatOrchestrator(services: services)
        let task = Task { [weak self] in
            var sequence = 0
            var selectedConversationID = request.conversationID
            var lastDeliveredAt = Date.distantPast
            var lastDeliveredTokenCount = 0

            do {
                for try await update in orchestrator.sendMessage(request, runID: runID) {
                    guard let self else { return }
                    selectedConversationID = update.conversationID
                    self.requestConversations[requestID] = update.conversationID

                    if Self.shouldDeliver(update, lastDeliveredAt: lastDeliveredAt, lastDeliveredTokenCount: lastDeliveredTokenCount) {
                        sequence += 1
                        lastDeliveredAt = Date()
                        lastDeliveredTokenCount = update.tokenCount
                        self.deliver(kind: .runUpdate, requestID: requestID, sequence: sequence, payload: update)
                    }

                    if update.status == .completed || update.status == .failed || update.status == .cancelled {
                        self.markRequestCompleted(requestID)
                        let snapshot = try await orchestrator.snapshot(
                            selectedConversationID: update.conversationID,
                            activeRunID: nil
                        )
                        self.deliver(kind: .snapshot, requestID: requestID, sequence: sequence + 1, payload: snapshot)
                    }
                }
            } catch {
                guard let self else { return }
                self.deliver(
                    kind: .error,
                    requestID: requestID,
                    sequence: sequence + 1,
                    payload: WatchChatErrorPayload(message: error.localizedDescription)
                )

                if let selectedConversationID,
                   let snapshot = try? await orchestrator.snapshot(
                       selectedConversationID: selectedConversationID,
                       activeRunID: nil
                   ) {
                    self.deliver(kind: .snapshot, requestID: requestID, sequence: sequence + 2, payload: snapshot)
                }
            }

            await MainActor.run {
                self?.clearRun(runID: runID, requestID: requestID)
            }
        }
        runTasks[runID] = task
    }

    private func markRequestCompleted(_ requestID: UUID) {
        guard completedRequests.insert(requestID).inserted else { return }
        completedRequestOrder.append(requestID)

        while completedRequestOrder.count > Self.completedRequestLimit {
            let evictedRequestID = completedRequestOrder.removeFirst()
            completedRequests.remove(evictedRequestID)
            requestRuns[evictedRequestID] = nil
            requestConversations[evictedRequestID] = nil
        }
    }

    private func clearRun(runID: UUID, requestID: UUID) {
        runTasks[runID] = nil
        requestRuns[requestID] = nil
        if !completedRequests.contains(requestID) {
            requestConversations[requestID] = nil
        }
    }

    private static func shouldDeliver(
        _ update: WatchChatRunUpdate,
        lastDeliveredAt: Date,
        lastDeliveredTokenCount: Int
    ) -> Bool {
        switch update.status {
        case .accepted, .completed, .failed, .cancelled:
            true
        case .streaming:
            update.tokenCount - lastDeliveredTokenCount >= 8
                || Date().timeIntervalSince(lastDeliveredAt) >= 0.35
        }
    }

    private func snapshotReply(_ snapshot: WatchChatSnapshot, requestID: UUID) throws -> [String: Any] {
        try WatchChatCodec.message(kind: .snapshot, requestID: requestID, payload: snapshot)
    }

    private func errorReply(_ message: String, requestID: UUID) throws -> [String: Any] {
        try WatchChatCodec.message(
            kind: .error,
            requestID: requestID,
            payload: WatchChatErrorPayload(message: message)
        )
    }

    private func deliver<Payload: Encodable>(
        kind: WatchChatMessageKind,
        requestID: UUID,
        sequence: Int,
        payload: Payload
    ) {
        guard WCSession.isSupported(),
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled
        else { return }

        guard let message = try? WatchChatCodec.message(
            kind: kind,
            requestID: requestID,
            sequence: sequence,
            payload: payload
        ) else {
            return
        }
        let envelopeData = try? WatchChatCodec.envelopeData(from: message)

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] _ in
                guard let envelopeData else { return }
                self?.session.transferUserInfo([WatchChatCodec.envelopeKey: envelopeData])
            }
        } else {
            session.transferUserInfo(message)
        }
    }

    private func phoneStatus() -> WatchPhoneStatus {
        let paired: Bool
        let installed: Bool
        #if os(iOS)
        paired = session.isPaired
        installed = session.isWatchAppInstalled
        #else
        paired = true
        installed = true
        #endif

        let summary: String
        if !paired {
            summary = "Pair an Apple Watch"
        } else if !installed {
            summary = "Install Pines on Apple Watch"
        } else if !services.mlxRuntime.isLinked {
            summary = "Open Pines on iPhone"
        } else if session.isReachable {
            summary = "iPhone runtime ready"
        } else {
            summary = "Waiting for iPhone"
        }

        return WatchPhoneStatus(
            reachable: session.isReachable,
            runtimeReady: services.mlxRuntime.isLinked,
            paired: paired,
            watchAppInstalled: installed,
            summary: summary
        )
    }

    private func publishPhoneStatus() {
        guard WCSession.isSupported(), session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        guard !suppressApplicationContextUpdates else { return }
        #if targetEnvironment(simulator)
        guard session.isReachable else { return }
        #endif
        guard let message = try? WatchChatCodec.message(kind: .phoneStatus, payload: phoneStatus()) else { return }
        do {
            try session.updateApplicationContext(message)
        } catch {
            if shouldSuppressApplicationContextUpdates(for: error) {
                suppressApplicationContextUpdates = true
            }
        }
    }

    private func shouldSuppressApplicationContextUpdates(for error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == WCError.errorDomain else { return false }
        return WCError.Code(rawValue: nsError.code) == .watchAppNotInstalled
    }
}
#endif
