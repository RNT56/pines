import SwiftUI
import PinesCore
import UniformTypeIdentifiers

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
                Section {
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
                } header: {
                    Text("Recent")
                        .font(theme.typography.section)
                        .foregroundStyle(theme.colors.tertiaryText)
                        .textCase(nil)
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
    @Environment(\.openPinesModelsPage) private var openModelsPage
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    let currentProviderID: ProviderID?
    let currentModelID: ModelID?
    let fallbackLabel: String?
    var accessibilityLabel = "Chat model"
    var fillWidth = false
    var maxWidth: CGFloat?
    let select: (ModelPickerOption) async -> Void

    var body: some View {
        let sections = appModel.modelPickerSections(services: services)
        let currentModelLabel = currentModelLabel(in: sections)

        Group {
            if sections.isEmpty {
                Button {
                    haptics.play(.navigationSelected)
                    openModelsPage()
                } label: {
                    pickerLabel(showsDisclosure: false, currentModelLabel: currentModelLabel)
                }
                .buttonStyle(.plain)
                .accessibilityValue("No models installed")
                .accessibilityHint("Opens Models")
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
                    pickerLabel(showsDisclosure: true, currentModelLabel: currentModelLabel)
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func pickerLabel(showsDisclosure: Bool, currentModelLabel: String) -> some View {
        let shape = Capsule()
        return HStack(spacing: theme.spacing.xsmall) {
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
        .background(pickerBackgroundStyle, in: shape)
        .overlay {
            shape
                .strokeBorder(pickerBorderStyle, lineWidth: theme.stroke.hairline)
        }
        .overlay {
            shape
                .strokeBorder(theme.colors.surfaceHighlight.opacity(0.68), lineWidth: theme.stroke.hairline)
                .blendMode(.plusLighter)
        }
        .shadow(color: pickerShadowColor, radius: theme.shadow.panelRadius * 0.22, x: 0, y: theme.shadow.panelY * 0.16)
        .contentShape(shape)
    }

    private var pickerBackgroundStyle: AnyShapeStyle {
        if theme.colorScheme == .dark {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        theme.colors.elevatedSurface.opacity(0.92),
                        theme.colors.controlFill.opacity(0.94),
                        theme.colors.accentSoft.opacity(0.62)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    theme.colors.elevatedSurface.opacity(theme.template == .graphite || theme.template == .obsidian ? 0.98 : 0.94),
                    theme.colors.controlFill.opacity(0.82),
                    theme.colors.accentSoft.opacity(0.50)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var pickerBorderStyle: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    theme.colors.accent.opacity(theme.colorScheme == .dark ? 0.46 : 0.34),
                    theme.colors.controlBorder.opacity(0.94),
                    theme.colors.surfaceHighlight.opacity(theme.colorScheme == .dark ? 0.28 : 0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var pickerShadowColor: Color {
        if theme.colorScheme == .dark {
            return theme.colors.accent.opacity(0.10)
        }
        return theme.shadow.panelColor.opacity(0.18)
    }

    private func currentModelLabel(in sections: [ModelPickerSection]) -> String {
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
        case .voyageAI:
            return "point.3.connected.trianglepath.dotted"
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
            .pinesExpressiveScrollHaptics()
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

            if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownMessageView(
                    messageID: message.id,
                    content: message.content,
                    isStreaming: isStreaming
                )
            }

            if !message.attachments.isEmpty {
                ChatAttachmentList(attachments: message.attachments)
            }
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

private struct ChatAttachmentList: View {
    @Environment(\.pinesTheme) private var theme
    let attachments: [ChatAttachment]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            ForEach(attachments.indices, id: \.self) { index in
                let attachment = attachments[index]
                HStack(spacing: theme.spacing.xsmall) {
                    Image(systemName: Self.iconName(for: attachment))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(attachment.fileName)
                            .font(theme.typography.caption.weight(.medium))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(Self.detailText(for: attachment))
                            .font(.caption2)
                            .foregroundStyle(theme.colors.tertiaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: theme.spacing.small)
                }
                .padding(.horizontal, theme.spacing.small)
                .padding(.vertical, theme.spacing.xsmall)
                .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(attachments.count) attachments")
    }

    static func iconName(for attachment: ChatAttachment) -> String {
        switch attachment.kind {
        case .image:
            "photo"
        case .document:
            attachment.normalizedContentType == "application/pdf" ? "doc.richtext" : "doc.text"
        case .webCapture:
            "globe"
        case .audio:
            "waveform"
        case .video:
            "film"
        }
    }

    static func detailText(for attachment: ChatAttachment) -> String {
        let size = attachment.byteCount > 0
            ? ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file)
            : "Unknown size"
        return "\(attachment.contentType) - \(size)"
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
        .pinesSurface(theme.template == .paper && theme.colorScheme == .light ? .panel : .glass)
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
    @State private var attachments: [ChatAttachment] = []
    @State private var attachmentError: String?
    @State private var isImportingAttachments = false
    @State private var showingAttachmentImporter = false
    @State private var didCommitSend = false
    @State private var selectedMCPPrompt: MCPPromptRecord?
    @State private var mcpPromptArguments: [String: String] = [:]
    @FocusState private var isFocused: Bool
    let threadID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            if !attachments.isEmpty || attachmentError != nil || isImportingAttachments {
                attachmentTray
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Group {
                if horizontalSizeClass == .compact {
                    compactLayout
                } else {
                    regularLayout
                }
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
        .fileImporter(
            isPresented: $showingAttachmentImporter,
            allowedContentTypes: Self.allowedAttachmentTypes,
            allowsMultipleSelection: true,
            onCompletion: importAttachments
        )
        .animation(theme.motion.fast, value: draft.isEmpty)
        .animation(theme.motion.fast, value: attachments)
        .animation(theme.motion.fast, value: attachmentError)
    }

    private var regularLayout: some View {
        HStack(spacing: theme.spacing.small) {
            attachButton
            if !activeMCPPrompts.isEmpty {
                promptButton
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            inputField
            sendButton
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            inputField

            HStack(spacing: theme.spacing.small) {
                attachButton
                if !activeMCPPrompts.isEmpty {
                    promptButton
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                Spacer(minLength: theme.spacing.small)
                sendButton
            }
        }
    }

    private var attachmentTray: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            if let attachmentError {
                Text(attachmentError)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isImportingAttachments {
                Label("Adding attachments", systemImage: "paperclip")
                    .font(theme.typography.caption.weight(.medium))
                    .foregroundStyle(theme.colors.secondaryText)
            }

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.spacing.xsmall) {
                        ForEach(attachments.indices, id: \.self) { index in
                            let attachment = attachments[index]
                            PendingChatAttachmentPill(
                                attachment: attachment,
                                remove: { removeAttachment(attachment) }
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var inputField: some View {
        TextField("Ask Pines", text: $draft, axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled()
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
            attachmentError = nil
            showingAttachmentImporter = true
        } label: {
            Image(systemName: "paperclip")
        }
        .accessibilityLabel("Attach")
        .disabled(appModel.activeRunID != nil || isImportingAttachments || attachments.count >= Self.maxAttachmentCount)
        .pinesButtonStyle(.icon)
    }

    private var promptButton: some View {
        Menu {
            ForEach(activeMCPPrompts) { prompt in
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
        .pinesButtonStyle(.icon)
    }

    private var sendButton: some View {
        Button {
            if appModel.activeRunID == nil {
                sendDraft()
            } else {
                appModel.stopCurrentRun()
            }
        } label: {
            Image(systemName: appModel.activeRunID == nil ? "arrow.up" : "stop.fill")
                .symbolEffect(.bounce, options: .nonRepeating, value: didCommitSend)
        }
        .accessibilityLabel(appModel.activeRunID == nil ? "Send" : "Stop")
        .disabled(appModel.activeRunID == nil && !canSend)
        .pinesButtonStyle(sendButtonStyle)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private var sendButtonStyle: PinesButtonKind {
        if appModel.activeRunID != nil {
            return .destructive
        }
        return canSend ? .primary : .secondary
    }

    private var activeMCPPrompts: [MCPPromptRecord] {
        let activeServerIDs = Set(
            appModel.mcpServers
                .filter { $0.enabled && $0.promptsEnabled && $0.status == .ready }
                .map(\.id)
        )
        guard !activeServerIDs.isEmpty else { return [] }
        return appModel.mcpPrompts.filter { activeServerIDs.contains($0.serverID) }
    }

    private func sendDraft() {
        guard canSend else { return }
        let pending = draft
        let pendingAttachments = attachments
        draft = ""
        attachments = []
        attachmentError = nil
        isFocused = false
        withAnimation(theme.motion.copySuccess) {
            didCommitSend.toggle()
        }
        appModel.startSending(pending, attachments: pendingAttachments, in: threadID, services: services)
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

    private func removeAttachment(_ attachment: ChatAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        if let localURL = attachment.localURL {
            try? FileManager.default.removeItem(at: localURL)
        }
    }

    private func importAttachments(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            attachmentError = error.localizedDescription
        case let .success(urls):
            let remainingSlots = Self.maxAttachmentCount - attachments.count
            guard remainingSlots > 0 else {
                attachmentError = "Remove an attachment before adding another file."
                return
            }
            let selectedURLs = Array(urls.prefix(remainingSlots))
            let overflowCount = max(0, urls.count - remainingSlots)
            isImportingAttachments = true
            attachmentError = overflowCount > 0 ? "Only the first \(remainingSlots) selected files were added." : nil

            Task {
                let outcome = await Self.importAttachmentFiles(selectedURLs)
                attachments.append(contentsOf: outcome.attachments)
                if !outcome.failures.isEmpty {
                    attachmentError = outcome.failures.joined(separator: "\n")
                }
                isImportingAttachments = false
            }
        }
    }

    private static let maxAttachmentCount = 8
    nonisolated private static let maxInlineImageBytes = 20 * 1024 * 1024
    nonisolated private static let maxInlineFileBytes = 50 * 1024 * 1024

    private static let allowedAttachmentTypes: [UTType] = [
        "png", "jpg", "jpeg", "webp", "gif", "pdf", "txt", "md", "markdown", "json", "csv",
    ].compactMap { UTType(filenameExtension: $0) }

    private struct AttachmentImportOutcome: Sendable {
        var attachments: [ChatAttachment]
        var failures: [String]
    }

    nonisolated private static func importAttachmentFiles(_ urls: [URL]) async -> AttachmentImportOutcome {
        await Task.detached(priority: .userInitiated) {
            var imported = [ChatAttachment]()
            var failures = [String]()
            for url in urls {
                do {
                    imported.append(try chatAttachment(from: url))
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return AttachmentImportOutcome(attachments: imported, failures: failures)
        }.value
    }

    nonisolated private static func chatAttachment(from sourceURL: URL) throws -> ChatAttachment {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let contentType = normalizedAttachmentContentType(for: sourceURL)
        guard let kind = attachmentKind(for: contentType) else {
            throw InferenceError.unsupportedCapability("Unsupported attachment type \(contentType).")
        }

        let directory = try chatAttachmentsDirectory()
        let fileName = sanitizedAttachmentFileName(
            sourceURL.lastPathComponent,
            fallbackExtension: fileExtension(for: contentType)
        )
        let destination = directory.appending(path: "\(UUID().uuidString)-\(fileName)")
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let byteCount = try fileByteCount(at: destination)
        let maxBytes = kind == .image ? maxInlineImageBytes : maxInlineFileBytes
        guard byteCount > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw InferenceError.invalidRequest("Attachment is empty.")
        }
        guard byteCount <= maxBytes else {
            try? FileManager.default.removeItem(at: destination)
            throw InferenceError.invalidRequest("Attachment exceeds the \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)) limit.")
        }

        return ChatAttachment(
            kind: kind,
            fileName: fileName,
            contentType: contentType,
            localURL: destination,
            byteCount: byteCount
        )
    }

    nonisolated private static func normalizedAttachmentContentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        case "pdf":
            return "application/pdf"
        case "txt", "text":
            return "text/plain"
        case "md", "markdown":
            return "text/markdown"
        case "json":
            return "application/json"
        case "csv":
            return "text/csv"
        default:
            if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
               let mime = values.contentType?.preferredMIMEType?.lowercased() {
                return mime == "image/jpg" ? "image/jpeg" : mime
            }
            return "application/octet-stream"
        }
    }

    nonisolated private static func attachmentKind(for contentType: String) -> AttachmentKind? {
        switch contentType {
        case "image/png", "image/jpeg", "image/webp", "image/gif":
            return .image
        case "application/pdf", "text/plain", "text/markdown", "text/x-markdown", "application/json", "text/csv":
            return .document
        default:
            return nil
        }
    }

    nonisolated private static func fileExtension(for contentType: String) -> String {
        switch contentType {
        case "image/png":
            "png"
        case "image/jpeg":
            "jpg"
        case "image/webp":
            "webp"
        case "image/gif":
            "gif"
        case "application/pdf":
            "pdf"
        case "text/markdown", "text/x-markdown":
            "md"
        case "application/json":
            "json"
        case "text/csv":
            "csv"
        default:
            "txt"
        }
    }

    nonisolated private static func chatAttachmentsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(path: "Pines/ChatAttachments", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated private static func fileByteCount(at url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize {
            return size
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    nonisolated private static func sanitizedAttachmentFileName(_ rawValue: String, fallbackExtension: String) -> String {
        let candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "attachment.\(fallbackExtension)"
            : rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- "))
        var sanitized = candidate.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- ").union(.whitespacesAndNewlines))
        if sanitized.isEmpty {
            sanitized = "attachment.\(fallbackExtension)"
        }
        if URL(fileURLWithPath: sanitized).pathExtension.isEmpty {
            sanitized += ".\(fallbackExtension)"
        }
        return String(sanitized.prefix(96))
    }
}

private struct PendingChatAttachmentPill: View {
    @Environment(\.pinesTheme) private var theme
    let attachment: ChatAttachment
    let remove: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.xsmall) {
            Image(systemName: ChatAttachmentList.iconName(for: attachment))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.colors.accent)

            VStack(alignment: .leading, spacing: 0) {
                Text(attachment.fileName)
                    .font(theme.typography.caption.weight(.medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 160, alignment: .leading)

                Text(ChatAttachmentList.detailText(for: attachment))
                    .font(.caption2)
                    .foregroundStyle(theme.colors.tertiaryText)
                    .lineLimit(1)
            }

            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .accessibilityLabel("Remove \(attachment.fileName)")
            .buttonStyle(.plain)
            .foregroundStyle(theme.colors.secondaryText)
        }
        .padding(.horizontal, theme.spacing.small)
        .padding(.vertical, theme.spacing.xsmall)
        .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                .strokeBorder(theme.colors.controlBorder, lineWidth: theme.stroke.hairline)
        }
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
