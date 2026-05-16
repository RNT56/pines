import SwiftUI
import PinesCore

struct ChatsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var selectedThreadID: PinesThreadPreview.ID?

    private var selectedThread: PinesThreadPreview? {
        guard let selectedThreadID = selectedThreadID ?? defaultThreadID else {
            return nil
        }

        return appModel.threads.first { $0.id == selectedThreadID }
    }

    private var defaultThreadID: PinesThreadPreview.ID? {
        shouldAutoSelectSidebarItem ? appModel.threads.first?.id : nil
    }

    private var shouldAutoSelectSidebarItem: Bool {
        horizontalSizeClass != .compact
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedThreadID) {
                Section("Recent") {
                    ForEach(appModel.threads) { thread in
                        NavigationLink(value: thread.id) {
                            ChatThreadRow(thread: thread, isSelected: selectedThreadID == thread.id)
                        }
                        .pinesSidebarListRow()
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                Task {
                                    await appModel.setThreadPinned(thread, pinned: !thread.isPinned, services: services)
                                }
                            } label: {
                                Label(thread.isPinned ? "Unpin" : "Pin", systemImage: thread.isPinned ? "pin.slash" : "pin")
                            }
                            .tint(theme.colors.accent)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    await appModel.deleteThread(thread, services: services)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                Task {
                                    await appModel.setThreadArchived(thread, archived: thread.status != .archived, services: services)
                                }
                            } label: {
                                Label(thread.status == .archived ? "Restore" : "Archive", systemImage: thread.status == .archived ? "tray.and.arrow.up" : "archivebox")
                            }
                            .tint(theme.colors.warning)
                        }
                    }
                }
            }
            .navigationTitle("Chats")
            .pinesExpressiveScrollHaptics()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            if let threadID = await appModel.createChat(services: services) {
                                selectedThreadID = threadID
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New chat")
                }
            }
            .onAppear(perform: selectDefaultThreadIfNeeded)
            .onChange(of: horizontalSizeClass) { _, _ in
                selectDefaultThreadIfNeeded()
            }
            .onChange(of: appModel.threads) { _, threads in
                if let selectedThreadID, !threads.contains(where: { $0.id == selectedThreadID }) {
                    self.selectedThreadID = nil
                }
                selectDefaultThreadIfNeeded()
            }
            .onChange(of: selectedThreadID) { _, _ in
                haptics.play(.navigationSelected)
            }
            .pinesSidebarListChrome()
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

    private func selectDefaultThreadIfNeeded() {
        guard shouldAutoSelectSidebarItem else { return }
        selectedThreadID = selectedThreadID ?? appModel.threads.first?.id
    }
}

private struct ChatModelPickerButton: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    let currentProviderID: ProviderID?
    let currentModelID: ModelID?
    let fallbackLabel: String?
    var accessibilityLabel = "Chat model"
    var fillWidth = false
    var maxWidth: CGFloat?
    let select: (ModelPickerOption) async -> Void

    var body: some View {
        let sections = appModel.modelPickerSections(services: services)

        Group {
            if sections.isEmpty {
                pickerLabel(showsDisclosure: false)
                    .accessibilityValue("No models installed")
            } else {
                Menu {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.models) { option in
                                Button {
                                    Task {
                                        await select(option)
                                    }
                                } label: {
                                    Label {
                                        Text(option.compactDisplayName)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    } icon: {
                                        Image(systemName: option.systemImage)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    pickerLabel(showsDisclosure: true)
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .task {
            await appModel.refreshCloudModelCatalog(services: services)
        }
    }

    private func pickerLabel(showsDisclosure: Bool) -> some View {
        HStack(spacing: theme.spacing.xsmall) {
            Text(currentModelLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.76)
            if fillWidth {
                Spacer(minLength: theme.spacing.xsmall)
            }
            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .font(theme.typography.callout.weight(.semibold))
        .foregroundStyle(showsDisclosure ? theme.colors.accent : theme.colors.secondaryText)
        .padding(.horizontal, theme.spacing.medium)
        .frame(maxWidth: fillWidth ? .infinity : maxWidth, minHeight: 44)
        .background(theme.colors.glassSurface, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(theme.colors.controlBorder, lineWidth: theme.stroke.hairline)
        }
        .overlay {
            Capsule()
                .strokeBorder(theme.colors.surfaceHighlight.opacity(0.68), lineWidth: theme.stroke.hairline)
                .blendMode(.plusLighter)
        }
        .shadow(color: theme.shadow.panelColor.opacity(0.22), radius: theme.shadow.panelRadius * 0.24, x: 0, y: theme.shadow.panelY * 0.18)
        .contentShape(Capsule())
    }

    private var currentModelLabel: String {
        let sections = appModel.modelPickerSections(services: services)
        let options = sections.flatMap(\.models)
        guard !options.isEmpty else { return "None" }

        if let currentProviderID,
           let currentModelID,
           let match = options.first(where: { $0.providerID == currentProviderID && $0.modelID == currentModelID }) {
            return match.displayName
        }
        if let currentModelID,
           let match = options.first(where: { $0.modelID == currentModelID }) {
            return match.displayName
        }
        if let match = options.first(where: { $0.providerID == appModel.defaultProviderID && $0.modelID == appModel.defaultModelID }) {
            return match.displayName
        }
        return fallbackLabel == "No model selected" ? "Select model" : (fallbackLabel ?? "Select model")
    }
}

private struct ChatThreadRow: View {
    @Environment(\.pinesTheme) private var theme
    let thread: PinesThreadPreview
    let isSelected: Bool

    var body: some View {
        PinesSidebarRow(
            title: thread.title,
            subtitle: "\(thread.lastMessage)\n\(thread.modelName)",
            systemImage: "bubble.left.and.text.bubble.right",
            detail: thread.updatedLabel,
            tint: thread.status.tint(in: theme),
            isSelected: isSelected,
            isActive: thread.status == .streaming
        ) {
            HStack(spacing: theme.spacing.xsmall) {
                if thread.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                        .accessibilityLabel("Pinned")
                }

                PinesStatusIndicator(
                    color: thread.status.tint(in: theme),
                    isActive: thread.status == .streaming,
                    size: 9
                )
            }
        }
    }
}

private extension ModelPickerOption {
    var compactDisplayName: String {
        guard displayName.count > 34 else { return displayName }
        let prefix = String(displayName.prefix(18)).trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(displayName.suffix(12)).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)...\(suffix)"
    }

    var systemImage: String {
        if isLocal {
            return "cpu"
        }
        switch providerKind {
        case .openAI:
            return "sparkles"
        case .anthropic:
            return "brain.head.profile"
        case .gemini:
            return "diamond"
        case .openRouter:
            return "arrow.triangle.branch"
        case .openAICompatible, .custom, nil:
            return "network"
        }
    }
}

private struct ChatTranscriptView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var retrySpin = false
    let thread: PinesThreadPreview

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.large) {
                    ChatTranscriptHeader(thread: thread)

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

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(contentPadding)
                .frame(maxWidth: theme.spacing.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: thread.messages.count) { _, _ in
                withAnimation(theme.motion.standard) {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
            .onChange(of: appModel.activeRunID) { _, _ in
                withAnimation(theme.motion.standard) {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
        }
        .navigationTitle(thread.title)
        .task(id: "\(thread.id.uuidString)-\(thread.lastMessage)") {
            await appModel.loadThreadMessages(
                threadID: thread.id,
                services: services,
                force: !thread.messages.isEmpty
            )
        }
        .pinesExpressiveScrollHaptics()
        .pinesInlineNavigationTitle()
        .toolbar {
            if horizontalSizeClass == .compact {
                ToolbarItem(placement: .principal) {
                    ChatModelSelector(thread: thread, fillWidth: false, maxWidth: 156)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.stopCurrentRun()
                } label: {
                    Image(systemName: "stop.circle")
                }
                .accessibilityLabel("Stop")
                .disabled(appModel.activeRunID == nil)

                Button {
                    haptics.play(.primaryAction)
                    withAnimation(theme.motion.emphasized) {
                        retrySpin.toggle()
                    }
                    appModel.retryLastUserMessage(in: thread, services: services)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, options: .nonRepeating, value: retrySpin)
                }
                .accessibilityLabel("Retry")
                .disabled(appModel.activeRunID != nil || !thread.messages.contains { $0.role == .user })
            }
        }
        .pinesAppBackground()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: theme.spacing.small) {
                if let chatError = appModel.chatError {
                    ChatErrorBanner(
                        message: chatError,
                        dismiss: { appModel.dismissChatError() }
                    )
                    .padding(.horizontal, contentPadding)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                ChatComposerBar(threadID: thread.id)
                    .padding(.horizontal, contentPadding)
            }
            .padding(.top, theme.spacing.xsmall)
            .padding(.bottom, theme.spacing.small)
            .animation(theme.motion.standard, value: appModel.chatError)
        }
    }

    private var contentPadding: CGFloat {
        horizontalSizeClass == .compact ? theme.spacing.medium : theme.spacing.large
    }
}

private struct ChatTranscriptHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    let thread: PinesThreadPreview

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            if horizontalSizeClass != .compact {
                ChatModelSelector(thread: thread, fillWidth: false, maxWidth: 280)
            }

            Text("\(thread.tokenCount) tokens - \(thread.status.title)")
                .font(theme.typography.callout)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatModelSelector: View {
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    let thread: PinesThreadPreview
    var fillWidth: Bool
    var maxWidth: CGFloat?

    var body: some View {
        ChatModelPickerButton(
            currentProviderID: thread.providerID,
            currentModelID: thread.modelID,
            fallbackLabel: thread.modelName,
            accessibilityLabel: "Chat model",
            fillWidth: fillWidth,
            maxWidth: maxWidth
        ) { option in
            await appModel.selectModel(option, for: thread.id, services: services)
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
            PinesStatusIndicator(color: theme.colors.accent, isActive: false, size: 10)

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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var draft = ""
    @State private var didCommitSend = false
    @State private var selectedMCPPrompt: MCPPromptRecord?
    @State private var mcpPromptArguments: [String: String] = [:]
    @FocusState private var isFocused: Bool
    let threadID: UUID?

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .sheet(item: $selectedMCPPrompt) { prompt in
            MCPPromptInvocationSheet(
                prompt: prompt,
                arguments: $mcpPromptArguments,
                cancel: { selectedMCPPrompt = nil },
                invoke: {
                    let values = promptArguments(for: prompt)
                    selectedMCPPrompt = nil
                    Task {
                        await appModel.useMCPPrompt(prompt, arguments: values, services: services)
                    }
                }
            )
            .environmentObject(haptics)
            .pinesTheme(theme)
        }
        .pinesSurface(.chrome, padding: theme.spacing.small)
        .contentShape(RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous))
        .onTapGesture {
            isFocused = true
        }
        .animation(theme.motion.fast, value: draft.isEmpty)
    }

    private var regularLayout: some View {
        HStack(spacing: theme.spacing.small) {
            attachButton
            promptButton
            inputField
            sendButton
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            inputField

            HStack(spacing: theme.spacing.small) {
                attachButton
                promptButton
                Spacer(minLength: theme.spacing.small)
                sendButton
            }
        }
    }

    private var inputField: some View {
        TextField("Ask Pines", text: $draft, axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .font(theme.typography.body)
            .foregroundStyle(theme.colors.primaryText)
            .padding(.vertical, theme.spacing.xsmall)
            .submitLabel(.send)
            .onSubmit {
                guard appModel.activeRunID == nil else { return }
                sendDraft()
            }
    }

    private var attachButton: some View {
        Button {
            haptics.play(.primaryAction)
        } label: {
            Image(systemName: "paperclip")
        }
        .accessibilityLabel("Attach")
        .pinesButtonStyle(.icon)
    }

    private var promptButton: some View {
        Menu {
            ForEach(appModel.mcpPrompts) { prompt in
                Button(prompt.title ?? prompt.name) {
                    haptics.play(.primaryAction)
                    selectedMCPPrompt = prompt
                    seedPromptArguments(prompt)
                }
            }
        } label: {
            Image(systemName: "text.bubble")
        }
        .accessibilityLabel("MCP prompts")
        .disabled(appModel.mcpPrompts.isEmpty)
        .pinesButtonStyle(.icon)
    }

    private var sendButton: some View {
        Button {
            sendDraft()
        } label: {
            Image(systemName: appModel.activeRunID == nil ? "arrow.up" : "stop.fill")
                .symbolEffect(.bounce, options: .nonRepeating, value: didCommitSend)
        }
        .accessibilityLabel("Send")
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appModel.activeRunID != nil)
        .pinesButtonStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appModel.activeRunID != nil ? .secondary : .primary)
    }

    private func sendDraft() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let pending = draft
        draft = ""
        isFocused = false
        withAnimation(theme.motion.copySuccess) {
            didCommitSend.toggle()
        }
        appModel.startSending(pending, in: threadID, services: services)
    }

    private func seedPromptArguments(_ prompt: MCPPromptRecord) {
        for argument in prompt.arguments where mcpPromptArguments[promptArgumentKey(prompt: prompt, argument: argument)] == nil {
            mcpPromptArguments[promptArgumentKey(prompt: prompt, argument: argument)] = ""
        }
    }

    private func promptArguments(for prompt: MCPPromptRecord) -> [String: String] {
        Dictionary(uniqueKeysWithValues: prompt.arguments.map { argument in
            (argument.name, mcpPromptArguments[promptArgumentKey(prompt: prompt, argument: argument)] ?? "")
        })
    }

    private func promptArgumentKey(prompt: MCPPromptRecord, argument: MCPPromptArgument) -> String {
        "\(prompt.id):\(argument.name)"
    }
}

private struct ChatErrorBanner: View {
    @Environment(\.pinesTheme) private var theme
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.colors.warning)
                .padding(.top, 2)

            Text(message)
                .font(theme.typography.callout)
                .foregroundStyle(theme.colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Spacer(minLength: theme.spacing.small)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Dismiss error")
            .pinesButtonStyle(.icon)
        }
        .pinesSurface(.elevated, padding: theme.spacing.medium)
    }
}

private struct MCPPromptInvocationSheet: View {
    @Environment(\.pinesTheme) private var theme
    let prompt: MCPPromptRecord
    @Binding var arguments: [String: String]
    let cancel: () -> Void
    let invoke: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    Text(prompt.title ?? prompt.name)
                        .font(theme.typography.headline)
                    if let description = prompt.description {
                        Text(description)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }

                Section("Arguments") {
                    if prompt.arguments.isEmpty {
                        Text("This prompt does not require arguments.")
                            .foregroundStyle(theme.colors.secondaryText)
                    } else {
                        ForEach(prompt.arguments, id: \.name) { argument in
                            TextField(
                                argument.required == true ? "\(argument.name) required" : argument.name,
                                text: Binding(
                                    get: { arguments["\(prompt.id):\(argument.name)"] ?? "" },
                                    set: { arguments["\(prompt.id):\(argument.name)"] = $0 }
                                ),
                                axis: .vertical
                            )
                            .lineLimit(1...4)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            if let description = argument.description {
                                Text(description)
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.secondaryText)
                            }
                        }
                    }
                }
            }
            .pinesExpressiveScrollHaptics()
            .navigationTitle("Use MCP Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invoke", action: invoke)
                }
            }
        }
    }
}
