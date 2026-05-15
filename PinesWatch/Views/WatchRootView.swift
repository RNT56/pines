import SwiftUI
import PinesWatchSupport

struct WatchRootView: View {
    @EnvironmentObject private var model: WatchChatViewModel
    @State private var renameConversation: WatchConversationSummary?
    @State private var renameTitle = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.isReachable ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(model.pendingRequestCount > 0 ? "\(model.statusText) • \(model.pendingRequestCount) queued" : model.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Section("Diagnostics") {
                    WatchDiagnosticRow(title: "Runtime", value: model.phoneStatus.runtimeReady ? "Ready" : "Open iPhone")
                    WatchDiagnosticRow(title: "Reachable", value: model.phoneStatus.reachable ? "Yes" : "No")
                    WatchDiagnosticRow(title: "Paired", value: model.phoneStatus.paired ? "Yes" : "No")
                    WatchDiagnosticRow(title: "Installed", value: model.phoneStatus.watchAppInstalled ? "Yes" : "No")
                }

                if !model.pendingRequests.isEmpty {
                    Section("Pending") {
                        ForEach(model.pendingRequests) { request in
                            PendingRequestRow(request: request)
                        }
                    }
                }

                Section {
                    Button {
                        model.createConversation()
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                    .disabled(model.isWorking)
                }

                Section("Chats") {
                    if model.conversations.isEmpty {
                        Text(model.statusText)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.conversations) { conversation in
                            NavigationLink(value: conversation.id) {
                                WatchConversationRow(conversation: conversation)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                WatchHaptics.shared.play(.navigationSelected)
                            })
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    renameTitle = conversation.title
                                    renameConversation = conversation
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button {
                                    model.setConversationArchived(conversation.id, archived: !conversation.archived)
                                } label: {
                                    Label(conversation.archived ? "Restore" : "Archive", systemImage: "archivebox")
                                }

                                Button(role: .destructive) {
                                    model.deleteConversation(conversation.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pines")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        WatchHaptics.shared.play(.primaryAction)
                        model.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            .navigationDestination(for: UUID.self) { conversationID in
                WatchTranscriptView(conversationID: conversationID)
            }
            .sheet(item: $renameConversation) { conversation in
                RenameConversationView(
                    title: $renameTitle,
                    onCancel: {
                        renameConversation = nil
                    },
                    onSave: {
                        model.renameConversation(conversation.id, title: renameTitle)
                        renameConversation = nil
                    }
                )
            }
        }
    }
}

private struct WatchDiagnosticRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption2)
    }
}

private struct PendingRequestRow: View {
    @EnvironmentObject private var model: WatchChatViewModel
    let request: PendingWatchRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(request.summary)
                .font(.caption)
                .lineLimit(2)

            Text(request.kind.displayTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    model.retryPendingRequest(request)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Retry")

                Button(role: .destructive) {
                    model.discardPendingRequest(request)
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Discard")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RenameConversationView: View {
    @Binding var title: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)

                Button {
                    onSave()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            }
            .navigationTitle("Rename")
        }
    }
}

private struct WatchConversationRow: View {
    let conversation: WatchConversationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)

                if conversation.archived {
                    Image(systemName: "archivebox")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(conversation.lastMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(conversation.modelName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

private extension WatchChatMessageKind {
    var displayTitle: String {
        switch self {
        case .createConversation:
            "New chat"
        case .renameConversation:
            "Rename"
        case .archiveConversation:
            "Archive"
        case .deleteConversation:
            "Delete"
        case .sendMessage:
            "Message"
        case .phoneStatus, .listConversations, .loadConversation, .cancelRun, .snapshot, .runUpdate, .error:
            rawValue
        }
    }
}
