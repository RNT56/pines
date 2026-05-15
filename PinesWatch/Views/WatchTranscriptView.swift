import SwiftUI
import PinesWatchSupport

struct WatchTranscriptView: View {
    @EnvironmentObject private var model: WatchChatViewModel
    @State private var draft = ""
    let conversationID: UUID

    var body: some View {
        VStack(spacing: 8) {
            if !model.statusText.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.isReachable ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(statusLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.messages) { message in
                            WatchMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: model.messages) { _, messages in
                    guard let last = messages.last else { return }
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            if model.activeRunID == nil && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.quickReplies, id: \.self) { reply in
                            Button(reply) {
                                model.sendDraft(reply)
                            }
                            .font(.caption)
                            .lineLimit(1)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Message", text: $draft)
                    .disabled(model.activeRunID != nil)
                    .submitLabel(.send)
                    .onSubmit(sendDraft)

                if model.activeRunID == nil {
                    Button(action: sendDraft) {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send")
                } else {
                    Button {
                        model.cancelRun()
                    } label: {
                        Image(systemName: "stop.circle")
                    }
                    .accessibilityLabel("Stop")
                }
            }
        }
        .navigationTitle(title)
        .task(id: conversationID) {
            WatchHaptics.shared.play(.navigationSelected)
            model.selectConversation(conversationID)
        }
    }

    private var title: String {
        model.conversations.first { $0.id == conversationID }?.title ?? "Chat"
    }

    private var statusLine: String {
        model.pendingRequestCount > 0 ? "\(model.statusText) • \(model.pendingRequestCount) queued" : model.statusText
    }

    private func sendDraft() {
        let pending = draft
        draft = ""
        model.sendDraft(pending)
    }
}

private struct WatchMessageBubble: View {
    let message: WatchChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(message.role.title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(message.content.isEmpty ? "..." : message.content)
                .font(.body)
                .foregroundStyle(message.role == .user ? Color.primary : Color.green)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(message.role == .user ? Color.blue.opacity(0.18) : Color.green.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension WatchChatRole {
    var title: String {
        switch self {
        case .system:
            "System"
        case .user:
            "You"
        case .assistant:
            "Pines"
        case .tool:
            "Tool"
        }
    }
}
