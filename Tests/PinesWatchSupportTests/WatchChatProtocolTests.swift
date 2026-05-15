import Foundation
import PinesWatchSupport
import Testing

@Suite("Watch chat protocol")
struct WatchChatProtocolTests {
    @Test
    func messageEnvelopeRoundTripsPayloadAndMetadata() throws {
        let requestID = UUID(uuidString: "B74F40CC-C0AC-469F-9E24-2B0014F992D7")!
        let conversationID = UUID(uuidString: "35F5C539-3401-4D24-B66B-6911BF4190CE")!
        let clientMessageID = UUID(uuidString: "EC7356C5-8D57-4760-A4A3-4469015142E0")!
        let payload = WatchSendMessageRequest(
            conversationID: conversationID,
            text: "Summarize the latest notes.",
            clientMessageID: clientMessageID
        )

        let message = try WatchChatCodec.message(
            kind: .sendMessage,
            requestID: requestID,
            sequence: 4,
            payload: payload
        )
        let envelope = try WatchChatCodec.envelope(from: message)
        let decoded = try WatchChatCodec.decode(WatchSendMessageRequest.self, from: envelope)

        #expect(envelope.version == WatchChatProtocolVersion.current)
        #expect(envelope.kind == .sendMessage)
        #expect(envelope.requestID == requestID)
        #expect(envelope.sequence == 4)
        #expect(decoded.conversationID == conversationID)
        #expect(decoded.text == "Summarize the latest notes.")
        #expect(decoded.clientMessageID == clientMessageID)
    }

    @Test
    func snapshotRoundTripsConversationAndStatusState() throws {
        let conversationID = UUID(uuidString: "0FB5EF9A-F611-4A9A-841F-E2F24C98A598")!
        let messageID = UUID(uuidString: "1B735D98-C063-4F17-A431-DF5EBFB17207")!
        let snapshot = WatchChatSnapshot(
            conversations: [
                WatchConversationSummary(
                    id: conversationID,
                    title: "Watch chat",
                    lastMessage: "Done",
                    updatedAt: Date(timeIntervalSinceReferenceDate: 100),
                    modelName: "Local model",
                    archived: false
                ),
            ],
            selectedConversationID: conversationID,
            messages: [
                WatchChatMessage(
                    id: messageID,
                    role: .assistant,
                    content: "Done",
                    createdAt: Date(timeIntervalSinceReferenceDate: 101)
                ),
            ],
            activeRunID: nil,
            status: WatchPhoneStatus(
                reachable: true,
                runtimeReady: true,
                paired: true,
                watchAppInstalled: true,
                summary: "iPhone runtime ready"
            )
        )

        let message = try WatchChatCodec.message(kind: .snapshot, payload: snapshot)
        let envelope = try WatchChatCodec.envelope(from: message)
        let decoded = try WatchChatCodec.decode(WatchChatSnapshot.self, from: envelope)

        #expect(decoded == snapshot)
    }

    @Test
    func missingEnvelopeThrows() {
        #expect(throws: WatchChatProtocolError.missingEnvelope) {
            try WatchChatCodec.envelope(from: [:])
        }
    }

    @Test
    func unsupportedVersionThrows() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(
            WatchChatEnvelope(
                version: WatchChatProtocolVersion.current + 1,
                kind: .phoneStatus
            )
        )

        #expect(throws: WatchChatProtocolError.unsupportedVersion(WatchChatProtocolVersion.current + 1)) {
            try WatchChatCodec.envelope(from: data)
        }
    }
}
