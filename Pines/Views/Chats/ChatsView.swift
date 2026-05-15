import SwiftUI
import PinesCore

struct ChatsView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
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
            .onChange(of: selectedThreadID) { _, _ in
                haptics.play(.navigationSelected)
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
                .minimumScaleFactor(0.9)

            HStack(spacing: theme.spacing.xsmall) {
                PinesMetricPill(title: thread.status.title, systemImage: "circle.fill", tint: thread.status.tint(in: theme))

                Text(thread.modelName)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
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

                LazyVStack(spacing: theme.spacing.medium) {
                    ForEach(thread.messages) { message in
                        ChatBubble(
                            message: message,
                            isStreaming: appModel.activeRunID == message.id
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    ChatRunState(request: thread.request)
                }
                .animation(theme.motion.standard, value: thread.messages.count)

                if let serviceError = appModel.serviceError {
                    Text(serviceError)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.danger)
                        .pinesSurface(.elevated)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var haptics: PinesHaptics
    let message: ChatMessage
    let isStreaming: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous)
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            HStack(spacing: theme.spacing.xsmall) {
                PinesStatusIndicator(
                    color: message.role.tint(in: theme),
                    isActive: isStreaming,
                    size: isStreaming ? 9 : 8
                )

                Text(message.role.title)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .pinesFittingText()

                Spacer(minLength: theme.spacing.small)

                if isStreaming {
                    Text("streaming")
                        .font(theme.typography.caption.weight(.medium))
                        .foregroundStyle(theme.colors.accent)
                        .pinesFittingText()
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }

            MarkdownMessageView(
                messageID: message.id,
                content: message.content,
                isStreaming: isStreaming
            )
        }
        .padding(theme.spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role.bubbleFill(in: theme), in: shape)
        .overlay {
            shape
                .strokeBorder(message.role.bubbleBorder(in: theme), lineWidth: theme.stroke.hairline)
        }
        .shadow(color: theme.shadow.panelColor.opacity(message.role == .assistant ? 0.55 : 0.32), radius: theme.shadow.panelRadius * 0.25, x: 0, y: theme.shadow.panelY * 0.20)
        .scaleEffect(isStreaming && !reduceMotion ? 1.006 : 1)
        .animation(reduceMotion ? nil : theme.motion.fast, value: isStreaming)
        .contextMenu {
            Button {
                haptics.play(.primaryAction)
                copyToPasteboard(message.content)
            } label: {
                Label("Copy as Markdown", systemImage: "doc.on.doc")
            }

            Button {
                haptics.play(.primaryAction)
                copyToPasteboard(MarkdownMessageParser().plainText(from: message.content))
            } label: {
                Label("Copy as Plain Text", systemImage: "text.alignleft")
            }
        }
    }
}

private struct ChatRunState: View {
    @Environment(\.pinesTheme) private var theme
    let request: ChatRequest

    var body: some View {
        HStack(spacing: theme.spacing.medium) {
            PinesStatusIndicator(color: theme.colors.accent, isActive: true, size: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime standby")
                    .font(theme.typography.headline)
                    .pinesFittingText()

                Text(request.allowsTools ? "Tool routing enabled for this request." : "Waiting for the inference session.")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }

            Spacer()
        }
        .pinesSurface(.glass)
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

    func bubbleFill(in theme: PinesTheme) -> AnyShapeStyle {
        switch self {
        case .system:
            AnyShapeStyle(theme.colors.toolBubble)
        case .user:
            AnyShapeStyle(theme.colors.userBubble)
        case .assistant:
            AnyShapeStyle(theme.colors.assistantBubble)
        case .tool:
            AnyShapeStyle(theme.colors.toolBubble)
        }
    }

    func bubbleBorder(in theme: PinesTheme) -> Color {
        switch self {
        case .system:
            theme.colors.warning.opacity(0.24)
        case .user:
            theme.colors.info.opacity(0.24)
        case .assistant:
            theme.colors.accent.opacity(0.24)
        case .tool:
            theme.colors.separator
        }
    }
}

private struct ChatComposerBar: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var draft = ""
    @FocusState private var isFocused: Bool
    let threadID: UUID?

    var body: some View {
        HStack(spacing: theme.spacing.small) {
            Button {
                haptics.play(.primaryAction)
            } label: {
                Image(systemName: "paperclip")
            }
            .accessibilityLabel("Attach")
            .pinesButtonStyle(.icon)

            Menu {
                ForEach(appModel.mcpPrompts) { prompt in
                    Button(prompt.title ?? prompt.name) {
                        haptics.play(.primaryAction)
                        Task {
                            await appModel.useMCPPrompt(prompt, services: services)
                        }
                    }
                }
            } label: {
                Image(systemName: "text.bubble")
            }
            .accessibilityLabel("MCP prompts")
            .disabled(appModel.mcpPrompts.isEmpty)
            .pinesButtonStyle(.icon)

            TextField("Ask Pines", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.vertical, theme.spacing.xsmall)

            Button {
                let pending = draft
                draft = ""
                appModel.startSending(pending, in: threadID, services: services)
            } label: {
                Image(systemName: appModel.activeRunID == nil ? "arrow.up" : "stop.fill")
            }
            .accessibilityLabel("Send")
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appModel.activeRunID != nil)
            .pinesButtonStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appModel.activeRunID != nil ? .secondary : .primary)
        }
        .pinesSurface(.chrome, padding: theme.spacing.small)
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous)
                .strokeBorder(isFocused ? theme.colors.focusRing : Color.clear, lineWidth: isFocused ? theme.stroke.selected : 0)
        }
        .animation(theme.motion.fast, value: isFocused)
        .animation(theme.motion.fast, value: draft.isEmpty)
    }
}
