import ImageIO
import SwiftUI
import PinesCore
import UniformTypeIdentifiers

struct ChatComposerBar: View {
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
        .animation(theme.motion.fast, value: quickSettingsAvailability)
        .onChange(of: appModel.openAIReasoningEffort) { _, _ in
            Task { await appModel.saveSettings(services: services) }
        }
        .onChange(of: appModel.openAITextVerbosity) { _, _ in
            Task { await appModel.saveSettings(services: services) }
        }
        .onChange(of: appModel.anthropicEffort) { _, _ in
            Task { await appModel.saveSettings(services: services) }
        }
        .onChange(of: appModel.geminiThinkingLevel) { _, _ in
            Task { await appModel.saveSettings(services: services) }
        }
    }

    private var regularLayout: some View {
        HStack(spacing: theme.spacing.small) {
            attachButton
            if !activeMCPPrompts.isEmpty {
                promptButton
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            inputField
            if let quickSettingsAvailability {
                ChatQuickSettingsButton(availability: quickSettingsAvailability)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
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
                if let quickSettingsAvailability {
                    ChatQuickSettingsButton(availability: quickSettingsAvailability)
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

    private var quickSettingsAvailability: ChatQuickSettingsAvailability? {
        appModel.chatQuickSettingsAvailability(for: threadID, services: services)
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
            do {
                try FileManager.default.removeItem(at: localURL)
            } catch {
                attachmentError = "Could not remove \(attachment.fileName): \(error.localizedDescription)"
            }
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
        "png", "jpg", "jpeg", "webp", "gif", "heic", "heif", "heics", "heifs", "pdf", "txt", "md", "markdown", "json", "csv",
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

        let originalContentType = normalizedAttachmentContentType(for: sourceURL)
        guard let kind = attachmentKind(for: originalContentType) else {
            throw InferenceError.unsupportedCapability("Unsupported attachment type \(originalContentType).")
        }

        let directory = try chatAttachmentsDirectory()
        let contentType = convertedAttachmentContentType(for: originalContentType)
        let rawFileName = isHEICImageContentType(originalContentType)
            ? "\(sourceURL.deletingPathExtension().lastPathComponent).jpg"
            : sourceURL.lastPathComponent
        let fileName = sanitizedAttachmentFileName(
            rawFileName,
            fallbackExtension: fileExtension(for: contentType)
        )
        let destination = directory.appending(path: "\(UUID().uuidString)-\(fileName)")
        if isHEICImageContentType(originalContentType) {
            try convertHEICImage(at: sourceURL, toJPEGAt: destination)
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }

        let byteCount = try fileByteCount(at: destination)
        let maxBytes = kind == .image ? maxInlineImageBytes : maxInlineFileBytes
        guard byteCount > 0 else {
            try removeTemporaryAttachment(destination, context: "Attachment is empty.")
            throw InferenceError.invalidRequest("Attachment is empty.")
        }
        guard byteCount <= maxBytes else {
            try removeTemporaryAttachment(destination, context: "Attachment exceeds the \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)) limit.")
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
        case "heic":
            return "image/heic"
        case "heif":
            return "image/heif"
        case "heics":
            return "image/heic-sequence"
        case "heifs":
            return "image/heif-sequence"
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
            do {
                let values = try url.resourceValues(forKeys: [.contentTypeKey])
                if let mime = values.contentType?.preferredMIMEType?.lowercased() {
                    return mime == "image/jpg" ? "image/jpeg" : mime
                }
            } catch {
                return "application/octet-stream"
            }
            return "application/octet-stream"
        }
    }

    nonisolated private static func attachmentKind(for contentType: String) -> AttachmentKind? {
        switch contentType {
        case "image/png", "image/jpeg", "image/webp", "image/gif", "image/heic", "image/heif", "image/heic-sequence", "image/heif-sequence":
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
        case "image/heic", "image/heif", "image/heic-sequence", "image/heif-sequence":
            "jpg"
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

    nonisolated private static func removeTemporaryAttachment(_ url: URL, context: String) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw InferenceError.invalidRequest("\(context) Temporary file cleanup failed: \(error.localizedDescription)")
        }
    }

    nonisolated private static func convertedAttachmentContentType(for contentType: String) -> String {
        isHEICImageContentType(contentType) ? "image/jpeg" : contentType
    }

    nonisolated private static func isHEICImageContentType(_ contentType: String) -> Bool {
        switch contentType.lowercased() {
        case "image/heic", "image/heif", "image/heic-sequence", "image/heif-sequence":
            return true
        default:
            return false
        }
    }

    nonisolated private static func convertHEICImage(at sourceURL: URL, toJPEGAt destinationURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw InferenceError.invalidRequest("HEIC image could not be decoded.")
        }
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw InferenceError.invalidRequest("HEIC image could not be converted to JPEG.")
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, [
            kCGImageDestinationLossyCompressionQuality: 0.92,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw InferenceError.invalidRequest("HEIC image conversion could not be finalized.")
        }
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

struct ChatErrorBanner: View {
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
