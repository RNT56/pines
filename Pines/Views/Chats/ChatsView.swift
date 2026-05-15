import SwiftUI
import PinesCore

struct ChatsView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @State private var selectedThreadID: PinesThreadPreview.ID?

    private var selectedThread: PinesThreadPreview? {
        guard let selectedThreadID else {
            return appModel.threads.first
        }

        return appModel.threads.first { $0.id == selectedThreadID }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedThreadID) {
                Section("Recent") {
                    ForEach(appModel.threads) { thread in
                        ChatThreadRow(thread: thread)
                            .tag(thread.id)
                    }
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            selectedThreadID = await appModel.createChat(services: services)
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New chat")
                }
            }
            .onAppear {
                selectedThreadID = selectedThreadID ?? appModel.threads.first?.id
            }
            .scrollContentBackground(.hidden)
            .background(theme.colors.secondaryBackground)
        } detail: {
            if let selectedThread {
                ChatTranscriptView(thread: selectedThread)
            } else {
                PinesEmptyState(
                    title: "No chats",
                    detail: "Start a local chat when the inference runtime is connected.",
                    systemImage: "bubble.left.and.text.bubble.right"
                )
            }
        }
    }
}

private struct ChatThreadRow: View {
    @Environment(\.pinesTheme) private var theme
    let thread: PinesThreadPreview

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            HStack(alignment: .firstTextBaseline) {
                Text(thread.title)
                    .font(theme.typography.headline)
                    .lineLimit(1)

                Spacer(minLength: theme.spacing.small)

                Text(thread.updatedLabel)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.tertiaryText)
            }

            Text(thread.lastMessage)
                .font(theme.typography.callout)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(2)

            HStack(spacing: theme.spacing.xsmall) {
                PinesMetricPill(title: thread.status.title, systemImage: "circle.fill", tint: thread.status.tint(in: theme))

                Text(thread.modelName)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, theme.spacing.xsmall)
    }
}

private struct ChatTranscriptView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    let thread: PinesThreadPreview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                PinesSectionHeader(
                    thread.title,
                    subtitle: "\(thread.modelName) - \(thread.tokenCount) tokens - \(thread.status.title)"
                )

                VStack(spacing: theme.spacing.medium) {
                    ForEach(thread.messages) { message in
                        ChatBubble(
                            role: message.role.title,
                            text: message.content,
                            tint: message.role.tint(in: theme)
                        )
                    }

                    ChatRunState(request: thread.request)
                }

                if let serviceError = appModel.serviceError {
                    Text(serviceError)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.danger)
                        .pinesPanel()
                }
            }
            .padding(theme.spacing.large)
            .frame(maxWidth: theme.spacing.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(thread.title)
        .pinesInlineNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.stopCurrentRun()
                } label: {
                    Image(systemName: "stop.circle")
                }
                .accessibilityLabel("Stop")
                .disabled(appModel.activeRunID == nil)

                Button {
                    appModel.retryLastUserMessage(in: thread, services: services)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Retry")
                .disabled(appModel.activeRunID != nil || !thread.messages.contains { $0.role == .user })
            }
        }
        .pinesAppBackground()
        .safeAreaInset(edge: .bottom) {
            ChatComposerBar(threadID: thread.id)
                .padding(.horizontal, theme.spacing.large)
                .padding(.bottom, theme.spacing.small)
                .background(.bar)
        }
    }
}

private struct ChatBubble: View {
    @Environment(\.pinesTheme) private var theme
    let role: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            HStack(spacing: theme.spacing.xsmall) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)

                Text(role)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
            }

            Text(text)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pinesPanel()
    }
}

private struct ChatRunState: View {
    @Environment(\.pinesTheme) private var theme
    let request: ChatRequest

    var body: some View {
        HStack(spacing: theme.spacing.medium) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime standby")
                    .font(theme.typography.headline)

                Text(request.allowsTools ? "Tool routing enabled for this request." : "Waiting for the inference session.")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
            }

            Spacer()
        }
        .pinesPanel()
    }
}

private extension ChatRole {
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

    func tint(in theme: PinesTheme) -> Color {
        switch self {
        case .system:
            theme.colors.warning
        case .user:
            theme.colors.info
        case .assistant:
            theme.colors.accent
        case .tool:
            theme.colors.tertiaryText
        }
    }
}

private struct ChatComposerBar: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @State private var draft = ""
    let threadID: UUID?

    var body: some View {
        HStack(spacing: theme.spacing.small) {
            Button {
            } label: {
                Image(systemName: "paperclip")
            }
            .accessibilityLabel("Attach")

            TextField("Ask Pines", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)

            Button {
                let pending = draft
                draft = ""
                appModel.startSending(pending, in: threadID, services: services)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(theme.colors.accent)
            }
            .accessibilityLabel("Send")
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appModel.activeRunID != nil)
        }
        .padding(theme.spacing.small)
        .background(theme.colors.glassSurface, in: RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous)
                .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)
        }
    }
}
