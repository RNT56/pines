import Foundation
import PinesWatchSupport
import UserNotifications
@preconcurrency import WatchConnectivity

@MainActor
final class WatchChatViewModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var conversations: [WatchConversationSummary] = []
    @Published var selectedConversationID: UUID?
    @Published var messages: [WatchChatMessage] = []
    @Published var activeRunID: UUID?
    @Published var statusText = "Connecting"
    @Published var isReachable = false
    @Published var isWorking = false
    @Published var pendingRequestCount = 0
    @Published private(set) var pendingRequests: [PendingWatchRequest] = []

    let quickReplies = [
        "Continue",
        "Summarize",
        "Make shorter",
        "What should I do next?"
    ]

    private let session: WCSession
    private let cacheKey = "pines.watch.cachedState"
    private let pendingCacheKey = "pines.watch.pendingRequests"
    private var pendingRequestIDs = Set<UUID>() {
        didSet {
            pendingRequestCount = pendingRequestIDs.count
        }
    }
    private var queuedRequestIDs = Set<UUID>()
    private var lastSequenceByRequestID: [UUID: Int] = [:]
    private var isSceneActive = true

    init(session: WCSession = .default) {
        self.session = session
        super.init()
        restoreCachedState()
        restorePendingRequests()
    }

    func activate() {
        guard WCSession.isSupported() else {
            statusText = "Pair an iPhone with Pines"
            return
        }
        session.delegate = self
        session.activate()
        requestNotificationAuthorization()
        send(kind: .phoneStatus)
    }

    func setSceneActive(_ isActive: Bool) {
        isSceneActive = isActive
    }

    func refresh() {
        send(kind: .phoneStatus)
        send(kind: .listConversations)
    }

    func selectConversation(_ id: UUID) {
        selectedConversationID = id
        saveCachedState()
        send(kind: .loadConversation, payload: WatchLoadConversationRequest(conversationID: id))
    }

    func createConversation() {
        isWorking = true
        sendTracked(kind: .createConversation, summary: "Creating chat")
    }

    func renameConversation(_ id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendTracked(
            kind: .renameConversation,
            payload: WatchRenameConversationRequest(conversationID: id, title: trimmed),
            summary: "Renaming chat"
        )
    }

    func setConversationArchived(_ id: UUID, archived: Bool) {
        sendTracked(
            kind: .archiveConversation,
            payload: WatchArchiveConversationRequest(conversationID: id, archived: archived),
            summary: archived ? "Archiving chat" : "Restoring chat"
        )
    }

    func deleteConversation(_ id: UUID) {
        sendTracked(
            kind: .deleteConversation,
            payload: WatchDeleteConversationRequest(conversationID: id),
            summary: "Deleting chat"
        )
    }

    func sendDraft(_ draft: String) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, activeRunID == nil else { return }

        let request = WatchSendMessageRequest(conversationID: selectedConversationID, text: trimmed)
        let requestID = UUID()
        if selectedConversationID != nil {
            messages.append(
                WatchChatMessage(
                    id: request.clientMessageID,
                    role: .user,
                    content: trimmed,
                    createdAt: Date()
                )
            )
            saveCachedState()
        }
        isWorking = true
        sendTracked(kind: .sendMessage, requestID: requestID, payload: request, summary: trimmed)
    }

    func cancelRun() {
        guard let activeRunID else { return }
        send(kind: .cancelRun, payload: WatchCancelRunRequest(runID: activeRunID))
        self.activeRunID = nil
        isWorking = false
    }

    func retryPendingRequest(_ request: PendingWatchRequest) {
        do {
            let envelope = try WatchChatCodec.envelope(from: request.envelopeData)
            try send([WatchChatCodec.envelopeKey: request.envelopeData], kind: envelope.kind)
            statusText = "Retrying"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func discardPendingRequest(_ request: PendingWatchRequest) {
        completePendingRequest(request.requestID)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let isReachable = session.isReachable
        let statusText = error?.localizedDescription ?? (isReachable ? "Connected" : "Open Pines on iPhone")
        Task { @MainActor in
            self.isReachable = isReachable
            self.statusText = statusText
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor in
            self.isReachable = isReachable
            self.statusText = isReachable ? "Connected" : "Open Pines on iPhone"
            if isReachable {
                self.refresh()
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        let envelopeData = try? WatchChatCodec.envelopeData(from: message)
        Task { @MainActor in
            self.handleEnvelopeData(envelopeData)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let envelopeData = try? WatchChatCodec.envelopeData(from: userInfo)
        Task { @MainActor in
            self.handleEnvelopeData(envelopeData)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let envelopeData = try? WatchChatCodec.envelopeData(from: applicationContext)
        Task { @MainActor in
            self.handleEnvelopeData(envelopeData)
        }
    }

    private func send(kind: WatchChatMessageKind) {
        do {
            try send(WatchChatCodec.message(kind: kind), kind: kind)
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func send<Payload: Encodable>(
        kind: WatchChatMessageKind,
        requestID: UUID = UUID(),
        payload: Payload
    ) {
        do {
            try send(WatchChatCodec.message(kind: kind, requestID: requestID, payload: payload), kind: kind)
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func sendTracked(kind: WatchChatMessageKind, requestID: UUID = UUID(), summary: String) {
        do {
            let message = try WatchChatCodec.message(kind: kind, requestID: requestID)
            trackPendingRequest(message: message, kind: kind, requestID: requestID, summary: summary)
            try send(message, kind: kind)
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func sendTracked<Payload: Encodable>(
        kind: WatchChatMessageKind,
        requestID: UUID = UUID(),
        payload: Payload,
        summary: String
    ) {
        do {
            let message = try WatchChatCodec.message(kind: kind, requestID: requestID, payload: payload)
            trackPendingRequest(message: message, kind: kind, requestID: requestID, summary: summary)
            try send(message, kind: kind)
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func send(_ message: [String: Any], kind: WatchChatMessageKind) throws {
        guard WCSession.isSupported() else {
            statusText = "Pair an iPhone with Pines"
            return
        }
        let envelopeData = try WatchChatCodec.envelopeData(from: message)

        if session.activationState != .activated {
            session.activate()
        }

        if session.isReachable {
            session.sendMessage(message) { [weak self] reply in
                let envelopeData = try? WatchChatCodec.envelopeData(from: reply)
                Task { @MainActor in
                    self?.handleEnvelopeData(envelopeData)
                }
            } errorHandler: { [weak self] error in
                let message = error.localizedDescription
                Task { @MainActor in
                    if kind.isQueueableFromWatch {
                        self?.queueEnvelopeData(envelopeData)
                    } else {
                        self?.statusText = message
                        self?.isWorking = false
                    }
                }
            }
        } else {
            queueEnvelopeData(envelopeData)
        }
    }

    private func queueEnvelopeData(_ data: Data) {
        if let envelope = try? WatchChatCodec.envelope(from: data) {
            queuedRequestIDs.insert(envelope.requestID)
            markPendingRequestQueued(envelope.requestID)
        }
        session.transferUserInfo([WatchChatCodec.envelopeKey: data])
        statusText = "Queued for iPhone"
        savePendingRequests()
    }

    private func handleEnvelopeData(_ data: Data?) {
        do {
            guard let data else {
                throw WatchChatProtocolError.missingEnvelope
            }
            let envelope = try WatchChatCodec.envelope(from: data)
            if let sequence = envelope.sequence {
                let previous = lastSequenceByRequestID[envelope.requestID] ?? 0
                guard sequence > previous else { return }
                lastSequenceByRequestID[envelope.requestID] = sequence
            }
            handle(envelope)
        } catch {
            statusText = error.localizedDescription
            isWorking = false
        }
    }

    private func handle(_ envelope: WatchChatEnvelope) {
        do {
            switch envelope.kind {
            case .phoneStatus:
                let status = try WatchChatCodec.decode(WatchPhoneStatus.self, from: envelope)
                isReachable = status.reachable
                statusText = status.summary
            case .snapshot:
                completePendingRequest(envelope.requestID)
                apply(try WatchChatCodec.decode(WatchChatSnapshot.self, from: envelope))
            case .runUpdate:
                let update = try WatchChatCodec.decode(WatchChatRunUpdate.self, from: envelope)
                let pendingWasQueued = queuedRequestIDs.contains(envelope.requestID)
                    || pendingRequests.first(where: { $0.requestID == envelope.requestID })?.isQueued == true
                let shouldNotify = pendingWasQueued
                    && !isSceneActive
                    && update.status.isTerminal
                if update.status.isTerminal {
                    completePendingRequest(envelope.requestID)
                }
                apply(update)
                if shouldNotify {
                    notifyRunCompletion(update)
                }
            case .error:
                completePendingRequest(envelope.requestID)
                let error = try WatchChatCodec.decode(WatchChatErrorPayload.self, from: envelope)
                statusText = error.message
                isWorking = false
            case .listConversations,
                 .loadConversation,
                 .createConversation,
                 .renameConversation,
                 .archiveConversation,
                 .deleteConversation,
                 .sendMessage,
                 .cancelRun:
                break
            }
        } catch {
            statusText = error.localizedDescription
            isWorking = false
        }
    }

    private func apply(_ snapshot: WatchChatSnapshot) {
        conversations = snapshot.conversations
        selectedConversationID = snapshot.selectedConversationID
        messages = snapshot.messages
        activeRunID = snapshot.activeRunID
        isReachable = snapshot.status.reachable
        statusText = snapshot.status.summary
        isWorking = snapshot.activeRunID != nil
        saveCachedState()
    }

    private func apply(_ update: WatchChatRunUpdate) {
        selectedConversationID = update.conversationID
        if update.status == .accepted || update.status == .streaming {
            activeRunID = update.runID
            isWorking = true
        } else {
            activeRunID = nil
            isWorking = false
        }

        if let assistantMessageID = update.assistantMessageID {
            let message = WatchChatMessage(
                id: assistantMessageID,
                role: .assistant,
                content: update.text,
                createdAt: Date(),
                isStreaming: update.status == .streaming || update.status == .accepted
            )
            if let index = messages.firstIndex(where: { $0.id == assistantMessageID }) {
                messages[index] = message
            } else {
                messages.append(message)
            }
        }

        if let errorMessage = update.errorMessage {
            statusText = errorMessage
        } else {
            statusText = update.status == .streaming ? "Streaming" : "Connected"
        }
        saveCachedState()
    }

    private func trackPendingRequest(
        message: [String: Any],
        kind: WatchChatMessageKind,
        requestID: UUID,
        summary: String
    ) {
        guard let envelopeData = try? WatchChatCodec.envelopeData(from: message) else { return }
        pendingRequestIDs.insert(requestID)
        let request = PendingWatchRequest(
            requestID: requestID,
            kind: kind,
            envelopeData: envelopeData,
            summary: summary,
            createdAt: Date()
        )
        if let index = pendingRequests.firstIndex(where: { $0.requestID == requestID }) {
            pendingRequests[index] = request
        } else {
            pendingRequests.append(request)
        }
        savePendingRequests()
    }

    private func markPendingRequestQueued(_ requestID: UUID) {
        guard let index = pendingRequests.firstIndex(where: { $0.requestID == requestID }) else { return }
        pendingRequests[index].isQueued = true
        savePendingRequests()
    }

    private func completePendingRequest(_ requestID: UUID) {
        pendingRequestIDs.remove(requestID)
        queuedRequestIDs.remove(requestID)
        pendingRequests.removeAll { $0.requestID == requestID }
        savePendingRequests()
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyRunCompletion(_ update: WatchChatRunUpdate) {
        let content = UNMutableNotificationContent()
        content.title = update.status == .completed ? "Pines replied" : "Pines stopped"
        content.body = update.errorMessage ?? update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.body.isEmpty {
            content.body = update.status == .completed ? "Your watch chat has a new reply." : "Your watch request finished."
        }

        let request = UNNotificationRequest(identifier: update.runID.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func restoreCachedState() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let state = try? JSONDecoder().decode(CachedWatchState.self, from: data)
        else {
            return
        }

        conversations = state.conversations
        selectedConversationID = state.selectedConversationID
        messages = state.messages
        statusText = state.statusText
    }

    private func saveCachedState() {
        let state = CachedWatchState(
            conversations: conversations,
            selectedConversationID: selectedConversationID,
            messages: Array(messages.suffix(40)),
            statusText: statusText
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func restorePendingRequests() {
        guard let data = UserDefaults.standard.data(forKey: pendingCacheKey),
              let requests = try? JSONDecoder().decode([PendingWatchRequest].self, from: data)
        else {
            return
        }

        pendingRequests = requests
        pendingRequestIDs = Set(requests.map(\.requestID))
        queuedRequestIDs = Set(requests.filter(\.isQueued).map(\.requestID))
    }

    private func savePendingRequests() {
        if let data = try? JSONEncoder().encode(pendingRequests) {
            UserDefaults.standard.set(data, forKey: pendingCacheKey)
        }
    }
}

private struct CachedWatchState: Codable {
    var conversations: [WatchConversationSummary]
    var selectedConversationID: UUID?
    var messages: [WatchChatMessage]
    var statusText: String
}

struct PendingWatchRequest: Identifiable, Codable, Hashable {
    var requestID: UUID
    var kind: WatchChatMessageKind
    var envelopeData: Data
    var summary: String
    var createdAt: Date
    var isQueued = false

    var id: UUID { requestID }
}

private extension WatchChatMessageKind {
    var isQueueableFromWatch: Bool {
        switch self {
        case .createConversation, .renameConversation, .archiveConversation, .deleteConversation, .sendMessage:
            true
        case .phoneStatus, .listConversations, .loadConversation, .cancelRun, .snapshot, .runUpdate, .error:
            false
        }
    }
}

private extension WatchChatRunStatus {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            true
        case .accepted, .streaming:
            false
        }
    }
}
