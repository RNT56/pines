import ImageIO
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
    @State private var editingMessage: ChatMessage?
    let thread: PinesThreadPreview

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.large) {
                    ChatTranscriptHeader(thread: thread)

                    LazyVStack(spacing: theme.spacing.medium) {
                        ForEach(thread.messages) { message in
                            ChatMessageRow(
                                threadID: thread.id,
                                message: message,
                                isStreaming: appModel.activeRunID == message.id,
                                canEdit: appModel.activeRunID == nil,
                                editingMessage: $editingMessage
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
        .sheet(item: $editingMessage) { message in
            ChatMessageEditSheet(
                message: message,
                cancel: { editingMessage = nil },
                save: { content in
                    editingMessage = nil
                    Task {
                        await appModel.editUserMessage(message, content: content, in: thread.id, services: services)
                    }
                }
            )
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

private struct ChatMessageRow: View {
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    let threadID: UUID
    let message: ChatMessage
    let isStreaming: Bool
    let canEdit: Bool
    @Binding var editingMessage: ChatMessage?

    var body: some View {
        ChatBubble(
            message: message,
            isStreaming: isStreaming,
            canEdit: canEdit && message.role == .user,
            canAddAttachmentsToVault: !message.attachments.isEmpty,
            copyMessage: copyMessage,
            editMessage: editMessage,
            addAttachmentsToVault: addAttachmentsToVault
        )
    }

    private func copyMessage() {
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty {
            let text = message.role == .assistant
                ? MarkdownMessageParser().plainText(from: content)
                : content
            copyToPasteboard(text)
        } else {
            copyToPasteboard(message.attachments.map(\.fileName).joined(separator: "\n"))
        }
        haptics.play(.primaryAction)
    }

    private func addAttachmentsToVault() {
        Task {
            await appModel.addMessageAttachmentsToVault(message, services: services)
        }
    }

    private func editMessage() {
        editingMessage = message
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
    let canEdit: Bool
    let canAddAttachmentsToVault: Bool
    let copyMessage: () -> Void
    let editMessage: () -> Void
    let addAttachmentsToVault: () -> Void

    var body: some View {
        SwipeableChatBubble(
            leadingActions: leadingSwipeActions,
            trailingActions: trailingSwipeActions
        ) {
            bubbleContent
        }
    }

    private var bubbleContent: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous)
        return VStack(alignment: .leading, spacing: theme.spacing.small) {
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

                if !message.toolCalls.isEmpty {
                    ChatToolCallList(toolCalls: message.toolCalls)
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

    private var leadingSwipeActions: [ChatBubbleSwipeAction] {
        guard canAddAttachmentsToVault else { return [] }
        return [
            ChatBubbleSwipeAction(
                title: "Vault",
                systemImage: "tray.and.arrow.down",
                tint: theme.colors.accent,
                perform: addAttachmentsToVault
            ),
        ]
    }

    private var trailingSwipeActions: [ChatBubbleSwipeAction] {
        var actions = [
            ChatBubbleSwipeAction(
                title: "Copy",
                systemImage: "doc.on.doc",
                tint: theme.colors.info,
                perform: copyMessage
            ),
        ]
        if canEdit {
            actions.append(
                ChatBubbleSwipeAction(
                    title: "Edit",
                    systemImage: "square.and.pencil",
                    tint: theme.colors.accent,
                    perform: editMessage
                )
            )
        }
        return actions
    }
}

private struct ChatToolCallList: View {
    @Environment(\.pinesTheme) private var theme
    let toolCalls: [ToolCallDelta]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            ForEach(toolCalls, id: \.id) { toolCall in
                HStack(alignment: .top, spacing: theme.spacing.xsmall) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.accent)
                        .frame(width: 16, height: 16)

                    VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                        Text(toolCall.name)
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)

                        if let preview = argumentsPreview(for: toolCall) {
                            Text(preview)
                                .font(theme.typography.code)
                                .foregroundStyle(theme.colors.secondaryText)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, theme.spacing.xsmall)
                .padding(.horizontal, theme.spacing.small)
                .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                        .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)
                }
            }
        }
        .accessibilityLabel("\(toolCalls.count) tool calls")
    }

    private func argumentsPreview(for toolCall: ToolCallDelta) -> String? {
        let trimmed = toolCall.argumentsFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed != "{}" else { return nil }
        let collapsed = trimmed
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return collapsed.count > 220 ? "\(collapsed.prefix(220))..." : collapsed
    }
}

private struct ChatBubbleSwipeAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: Color
    let perform: () -> Void
}

private struct SwipeableChatBubble<Content: View>: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let leadingActions: [ChatBubbleSwipeAction]
    let trailingActions: [ChatBubbleSwipeAction]
    @ViewBuilder let content: () -> Content
    @GestureState private var dragOffset: CGFloat = 0
    @State private var settledOffset: CGFloat = 0

    private let actionWidth: CGFloat = 74

    var body: some View {
        ZStack {
            actionRail
                .opacity(revealedOffset == 0 ? 0 : 1)

            content()
                .offset(x: revealedOffset)
                .gesture(horizontalSwipeGesture)
                .animation(reduceMotion ? nil : theme.motion.fast, value: settledOffset)
                .animation(reduceMotion ? nil : theme.motion.fast, value: dragOffset)
        }
        .onChange(of: leadingActions.count) { _, _ in closeActions() }
        .onChange(of: trailingActions.count) { _, _ in closeActions() }
    }

    private var actionRail: some View {
        HStack(spacing: theme.spacing.xsmall) {
            ForEach(leadingActions) { action in
                ChatBubbleSwipeActionButton(action: action, closeActions: closeActions)
            }

            Spacer(minLength: theme.spacing.small)

            ForEach(trailingActions) { action in
                ChatBubbleSwipeActionButton(action: action, closeActions: closeActions)
            }
        }
        .padding(.horizontal, theme.spacing.xsmall)
        .frame(maxWidth: .infinity)
    }

    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .updating($dragOffset) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                settle(after: value)
            }
    }

    private var revealedOffset: CGFloat {
        clamp(settledOffset + dragOffset)
    }

    private var leadingRevealWidth: CGFloat {
        CGFloat(leadingActions.count) * actionWidth
    }

    private var trailingRevealWidth: CGFloat {
        CGFloat(trailingActions.count) * actionWidth
    }

    private func settle(after value: DragGesture.Value) {
        let projected = clamp(settledOffset + value.predictedEndTranslation.width * 0.45)
        let current = clamp(settledOffset + value.translation.width)
        let target = abs(projected) > abs(current) ? projected : current
        let threshold: CGFloat = 42

        withAnimation(reduceMotion ? nil : theme.motion.fast) {
            if target > threshold, leadingRevealWidth > 0 {
                settledOffset = leadingRevealWidth
            } else if target < -threshold, trailingRevealWidth > 0 {
                settledOffset = -trailingRevealWidth
            } else {
                settledOffset = 0
            }
        }
    }

    private func closeActions() {
        withAnimation(reduceMotion ? nil : theme.motion.fast) {
            settledOffset = 0
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, -trailingRevealWidth), leadingRevealWidth)
    }
}

private struct ChatBubbleSwipeActionButton: View {
    @Environment(\.pinesTheme) private var theme
    let action: ChatBubbleSwipeAction
    let closeActions: () -> Void

    var body: some View {
        Button {
            closeActions()
            action.perform()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(height: 18)

                Text(action.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(action.tint)
            .frame(width: 68)
            .frame(minHeight: 58)
            .background(action.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                    .strokeBorder(action.tint.opacity(0.18), lineWidth: theme.stroke.hairline)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
    }
}

private struct ChatMessageEditSheet: View {
    @Environment(\.pinesTheme) private var theme
    let message: ChatMessage
    let cancel: () -> Void
    let save: (String) -> Void
    @State private var draft: String

    init(message: ChatMessage, cancel: @escaping () -> Void, save: @escaping (String) -> Void) {
        self.message = message
        self.cancel = cancel
        self.save = save
        _draft = State(initialValue: message.content)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: theme.spacing.medium) {
                TextEditor(text: $draft)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.primaryText)
                    .scrollContentBackground(.hidden)
                    .padding(theme.spacing.small)
                    .frame(minHeight: 220)
                    .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                            .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)
                    }

                if !message.attachments.isEmpty {
                    ChatAttachmentList(attachments: message.attachments)
                }
            }
            .padding(theme.spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.colors.sheetBackground.ignoresSafeArea())
            .navigationTitle("Edit Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(draft)
                    }
                    .disabled(!canSave || draft == message.content)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var canSave: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !message.attachments.isEmpty
    }
}

struct ChatAttachmentList: View {
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

struct ChatQuickSettingsButton: View {
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    let availability: ChatQuickSettingsAvailability

    var body: some View {
        Menu {
            if !availability.openAIReasoningEfforts.isEmpty {
                Picker("Reasoning", selection: reasoningSelection) {
                    ForEach(availability.openAIReasoningEfforts, id: \.self) { effort in
                        Text(effort.shortTitle).tag(effort)
                    }
                }
            }

            if availability.supportsOpenAITextVerbosity {
                Picker("Verbosity", selection: verbositySelection) {
                    ForEach(OpenAITextVerbosity.quickSettingOptions, id: \.self) { verbosity in
                        Text(verbosity.shortTitle).tag(verbosity)
                    }
                }
            }

            if !availability.anthropicEfforts.isEmpty {
                Picker("Effort", selection: anthropicEffortSelection) {
                    ForEach(availability.anthropicEfforts, id: \.self) { effort in
                        Text(effort.shortTitle).tag(effort)
                    }
                }
            }

            if !availability.geminiThinkingLevels.isEmpty {
                Picker("Thinking", selection: geminiThinkingSelection) {
                    ForEach(availability.geminiThinkingLevels, id: \.self) { level in
                        Text(level.shortTitle).tag(level)
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            theme.colors.primaryText,
                            theme.colors.accent
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: theme.radius.control + 6, style: .continuous)
                        .fill(theme.colors.glassSurface)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    theme.colors.surfaceHighlight.opacity(0.95),
                                    theme.colors.accentSoft.opacity(0.34),
                                    theme.colors.controlFill.opacity(0.76)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: theme.radius.control + 6, style: .continuous))
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radius.control + 6, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    theme.colors.surfaceHighlight.opacity(0.90),
                                    theme.colors.accent.opacity(0.32),
                                    theme.colors.controlBorder.opacity(0.70)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: theme.stroke.hairline
                        )
                }
                .shadow(color: theme.colors.accent.opacity(theme.colorScheme == .dark ? 0.18 : 0.12), radius: theme.shadow.panelRadius * 0.32, x: 0, y: theme.shadow.panelY * 0.18)
                .contentShape(RoundedRectangle(cornerRadius: theme.radius.control + 6, style: .continuous))
        }
        .accessibilityLabel("Model quick settings")
        .accessibilityValue(accessibilityValue)
        .simultaneousGesture(TapGesture().onEnded { haptics.play(.navigationSelected) })
    }

    private var reasoningSelection: Binding<OpenAIReasoningEffort> {
        Binding {
            availability.openAIReasoningEfforts.contains(appModel.openAIReasoningEffort)
                ? appModel.openAIReasoningEffort
                : defaultReasoningEffort
        } set: { effort in
            appModel.openAIReasoningEffort = effort
            haptics.play(.primaryAction)
        }
    }

    private var verbositySelection: Binding<OpenAITextVerbosity> {
        Binding {
            appModel.openAITextVerbosity
        } set: { verbosity in
            appModel.openAITextVerbosity = verbosity
            haptics.play(.primaryAction)
        }
    }

    private var anthropicEffortSelection: Binding<AnthropicEffort> {
        Binding {
            availability.anthropicEfforts.contains(appModel.anthropicEffort)
                ? appModel.anthropicEffort
                : defaultAnthropicEffort
        } set: { effort in
            appModel.anthropicEffort = effort
            haptics.play(.primaryAction)
        }
    }

    private var geminiThinkingSelection: Binding<GeminiThinkingLevel> {
        Binding {
            availability.geminiThinkingLevels.contains(appModel.geminiThinkingLevel)
                ? appModel.geminiThinkingLevel
                : defaultGeminiThinkingLevel
        } set: { level in
            appModel.geminiThinkingLevel = level
            haptics.play(.primaryAction)
        }
    }

    private var defaultReasoningEffort: OpenAIReasoningEffort {
        if availability.openAIReasoningEfforts.contains(.low) {
            return .low
        }
        return availability.openAIReasoningEfforts.first ?? AppSettingsSnapshot.defaultOpenAIReasoningEffort
    }

    private var defaultAnthropicEffort: AnthropicEffort {
        if availability.anthropicEfforts.contains(.medium) {
            return .medium
        }
        if availability.anthropicEfforts.contains(.low) {
            return .low
        }
        return availability.anthropicEfforts.first ?? AppSettingsSnapshot.defaultAnthropicEffort
    }

    private var defaultGeminiThinkingLevel: GeminiThinkingLevel {
        if availability.geminiThinkingLevels.contains(.medium) {
            return .medium
        }
        if availability.geminiThinkingLevels.contains(.low) {
            return .low
        }
        return availability.geminiThinkingLevels.first ?? AppSettingsSnapshot.defaultGeminiThinkingLevel
    }

    private var accessibilityValue: String {
        var parts = [String]()
        if !availability.openAIReasoningEfforts.isEmpty {
            parts.append("Reasoning \(reasoningSelection.wrappedValue.shortTitle)")
        }
        if availability.supportsOpenAITextVerbosity {
            parts.append("Verbosity \(appModel.openAITextVerbosity.shortTitle)")
        }
        if !availability.anthropicEfforts.isEmpty {
            parts.append("Effort \(anthropicEffortSelection.wrappedValue.shortTitle)")
        }
        if !availability.geminiThinkingLevels.isEmpty {
            parts.append("Thinking \(geminiThinkingSelection.wrappedValue.shortTitle)")
        }
        return parts.joined(separator: ", ")
    }
}

private extension OpenAIReasoningEffort {
    var shortTitle: String {
        switch self {
        case .none:
            "None"
        case .minimal:
            "Minimal"
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        case .xhigh:
            "X High"
        }
    }
}

private extension OpenAITextVerbosity {
    static let quickSettingOptions: [OpenAITextVerbosity] = [.low, .medium, .high]

    var shortTitle: String {
        switch self {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }
}

private extension AnthropicEffort {
    var shortTitle: String {
        switch self {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        case .xhigh:
            "X High"
        case .max:
            "Max"
        }
    }
}

private extension GeminiThinkingLevel {
    var shortTitle: String {
        switch self {
        case .minimal:
            "Minimal"
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }
}
